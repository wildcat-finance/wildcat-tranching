// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {TrancheController} from "../src/TrancheController.sol";
import {WhitelistGate} from "../src/WhitelistGate.sol";
import {TrancheToken} from "../src/TrancheToken.sol";
import {TrancheFactory} from "../src/TrancheFactory.sol";
import {MockERC20, MockMarket, MockWrapper, MockSentinel, MockArch} from "./Mocks.sol";

/// @notice PoC for the headline external-review finding (SR-D): during delinquency, requestRedeem
///         sizes the wrapper-share redemption at the FROZEN mark (_effPps) but underlyingVault.redeem
///         converts those shares at the LIVE price, so the exiter pulls out more market tokens (and
///         hence more recoverable USDC) than its frozen-mark entitlement, booking the unrealised
///         penalty appreciation that the high-watermark valuation deliberately freezes, at the
///         expense of holders who stay. This test asserts the (buggy) over-redemption to document it.
contract AuditPoCTest is Test {
    WhitelistGate internal jrGate = new WhitelistGate(address(this));
    MockERC20 usdc;
    MockMarket market;
    MockWrapper wrapper;
    MockSentinel sentinel;
    TrancheController c;
    TrancheToken senior;
    TrancheToken junior;

    address gov = address(0x6011);
    address srLP = address(0x5E11);
    address jrLP = address(0x10110);

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC");
        market = new MockMarket(address(usdc));
        wrapper = new MockWrapper(address(market));
        sentinel = new MockSentinel();
        c = new TrancheController(
            TrancheController.Params({
                underlyingVault: address(wrapper),
                sentinel: address(sentinel),
                borrower: address(0xB0110),
                governance: gov,
                defaultDeclarer: address(0xDEC),
                seniorGate: address(0),
                juniorGate: address(jrGate),
                seniorShareBips: 10000,
                minJuniorBips: 2000,
                defaultPenaltyWindow: 90 days,
                shareDecimals: 18,
                borrowerRecovery: false
            })
        );
        senior = c.senior();
        junior = c.junior();
        wrapper.mintShares(srLP, 1_000e18);
        wrapper.mintShares(jrLP, 1_000e18);
        jrGate.setAllowed(jrLP, true);
        // deposits at price 1.0 -> markPps frozen at 1.0
        vm.startPrank(jrLP);
        wrapper.approve(address(c), 100e18);
        c.depositJunior(100e18, jrLP);
        vm.stopPrank();
        vm.startPrank(srLP);
        wrapper.approve(address(c), 300e18);
        c.depositSenior(300e18, srLP);
        vm.stopPrank();
    }

    /// @dev Regression for SR-D (fixed): redeeming during delinquency now sizes the wrapper
    ///      redemption at the LIVE price, so the exiter queues exactly its frozen-mark claim and
    ///      the unrealised appreciation stays in the pool for the residual instead of being booked.
    function test_FrozenMarkRedemptionSizedAtLivePrice() public {
        // market goes delinquent and the wrapper price climbs on (unpaid) penalty accrual
        market.setDelinquent(true);
        wrapper.setPrice(1.2e18); // curPps = 1.2, markPps frozen at 1.0 -> effPps = 1.0

        uint256 balBefore = wrapper.balanceOf(address(c)); // 400e18

        // a senior holder redeems half its position (150 shares of 300); frozen-mark claim = 150
        vm.prank(srLP);
        uint256 id = c.requestRedeem(true, 150e18);

        // FIXED: queued amount equals the frozen-mark claim (150), not 1.2x it
        (,, uint128 wmt,,) = c.requests(id);
        assertEq(uint256(wmt), 150e18, "queued exactly the 150 frozen-mark claim (no over-redeem)");

        // FIXED: only 125 wrapper shares (150 / 1.2 live) are redeemed, leaving the appreciation
        // on the extra 25 shares in the pool for the residual (junior) rather than the exiter
        uint256 redeemed = balBefore - wrapper.balanceOf(address(c));
        assertEq(redeemed, 125e18, "redeemed 125 wrapper shares (sized at live price)");
    }

    /// @dev SR-A (fixed): USDC that arrives outside pokeRecovery (e.g. a permissionless market
    ///      executeWithdrawal, the real-market default path) is no longer stranded; sync() credits
    ///      it from the actual balance.
    function test_SR_A_ExternalWithdrawalNotStranded() public {
        uint256 sShares = senior.balanceOf(srLP);
        vm.prank(srLP);
        uint256 id = c.requestRedeem(true, sShares);
        (,, uint128 wmt,, uint32 expiry) = c.requests(id);
        usdc.mint(address(market), uint256(wmt));
        vm.warp(uint256(expiry) + 1);

        // someone executes the controller's batch DIRECTLY, bypassing pokeRecovery's delta accounting
        market.executeWithdrawal(address(c), expiry);
        assertGt(usdc.balanceOf(address(c)), 0, "USDC landed in the controller");
        assertEq(c.recoveredUSDC(), 0, "but it is not yet credited");
        assertEq(c.claimable(id), 0, "and would be stranded without the fix");

        // sync() rescues it from the actual balance
        c.sync();
        assertEq(c.claimable(id), uint256(wmt), "sync credits the externally-recovered USDC");
        vm.prank(srLP);
        assertEq(c.claim(id), uint256(wmt), "claim now settles");
    }

    /// @dev SR-B (fixed): deployTranches is owner-gated and validates governance/sentinel.
    function _dp(address g, address s) internal view returns (TrancheFactory.DeployParams memory) {
        return TrancheFactory.DeployParams({
            underlyingVault: address(wrapper),
            sentinel: s,
            borrower: address(0xB0110),
            governance: g,
            defaultDeclarer: address(0xDEC),
            seniorGate: address(0),
            juniorGate: address(jrGate),
            seniorShareBips: 8000,
            minJuniorBips: 2000,
            defaultPenaltyWindow: 90 days,
            borrowerRecovery: false
        });
    }

    function test_SR_B_DeployTranchesGated() public {
        MockArch arch = new MockArch();
        TrancheFactory factory = new TrancheFactory(address(arch)); // owner = this test contract
        arch.setRegistered(address(market), true);

        vm.prank(address(0xBAD));
        vm.expectRevert(bytes("ONLY_OWNER"));
        factory.deployTranches(_dp(gov, address(sentinel)));

        vm.expectRevert(bytes("ZERO_GOV"));
        factory.deployTranches(_dp(address(0), address(sentinel)));

        vm.expectRevert(bytes("ZERO_SENTINEL"));
        factory.deployTranches(_dp(gov, address(0)));

        address ctrl = factory.deployTranches(_dp(gov, address(sentinel))); // owner, valid params
        assertEq(factory.controllerForMarket(address(market)), ctrl);
    }

    /// @dev Governance is now rotatable via a two-step transfer (addresses the no-rotation finding).
    function test_GovernanceTwoStepTransfer() public {
        address newGov = address(0x9999);
        vm.prank(address(0xBAD));
        vm.expectRevert(bytes("ONLY_GOV"));
        c.proposeGovernance(newGov);

        vm.prank(gov);
        c.proposeGovernance(newGov);
        assertEq(c.pendingGovernance(), newGov);

        vm.prank(address(0xBAD));
        vm.expectRevert(bytes("NOT_PENDING"));
        c.acceptGovernance();

        vm.prank(newGov);
        c.acceptGovernance();
        assertEq(c.governance(), newGov);
        assertEq(c.pendingGovernance(), address(0));

        // old governance can no longer act; new one can
        vm.prank(gov);
        vm.expectRevert(bytes("ONLY_GOV"));
        c.setDepositsPaused(true);
        vm.prank(newGov);
        c.setDepositsPaused(true);
        assertTrue(c.depositsPaused());
    }

    /// @dev R1 (re-audit): accrue() now books the elapsed interest BEFORE testing for default, and
    ///      declareDefault/checkDefault/pokeRecovery/sync all accrue first, so the distress gate in
    ///      _allocate always reserves the live seniorOwed. Here a full year elapses with no other
    ///      interaction, then declareDefault trips wind-down: seniorOwedAtDefault must include the
    ///      year of senior interest. Before the fix _syncDefault ran first and froze the stale value.
    function test_R1_AccrualBookedBeforeWindDown() public {
        assertEq(c.seniorOwed(), 300e18, "seniorOwed after deposit");
        vm.warp(block.timestamp + 365 days);
        vm.prank(address(0xDEC)); // defaultDeclarer
        c.declareDefault();
        // 300 + 10% (1000 bips base APR, 100% senior share) * 300 = 330 booked before the freeze
        assertEq(c.seniorOwedAtDefault(), 330e18, "final year of senior interest booked before freeze");
        assertEq(c.seniorOwed(), 330e18, "seniorOwed frozen at the accrued value, not the stale one");
    }

    /// @dev R2 (re-audit): factory ownership transfer is two-step (propose + accept), matching the
    ///      controller's governance rotation, so a mistyped/uncontrolled successor cannot strand it.
    function test_R2_FactoryTwoStepOwner() public {
        MockArch arch = new MockArch();
        TrancheFactory factory = new TrancheFactory(address(arch)); // owner = this test contract
        address newOwner = address(0xA11CE);

        vm.prank(address(0xBAD));
        vm.expectRevert(bytes("ONLY_OWNER"));
        factory.transferOwner(newOwner);

        // propose: ownership does NOT move yet
        factory.transferOwner(newOwner);
        assertEq(factory.pendingOwner(), newOwner, "pending set");
        assertEq(factory.owner(), address(this), "owner unchanged until accepted");

        // only the proposed successor can accept
        vm.prank(address(0xBAD));
        vm.expectRevert(bytes("NOT_PENDING"));
        factory.acceptOwner();

        vm.prank(newOwner);
        factory.acceptOwner();
        assertEq(factory.owner(), newOwner, "ownership transferred on accept");
        assertEq(factory.pendingOwner(), address(0), "pending cleared");
    }

    /// @dev R3 (re-audit): borrower must be non-zero; it keys every sentinel sanctions/escrow call.
    function test_R3_ZeroBorrowerRejected() public {
        MockArch arch = new MockArch();
        TrancheFactory factory = new TrancheFactory(address(arch));
        arch.setRegistered(address(market), true);

        TrancheFactory.DeployParams memory p = _dp(gov, address(sentinel));
        p.borrower = address(0);
        vm.expectRevert(bytes("ZERO_BORROWER"));
        factory.deployTranches(p);

        // the controller constructor guards it directly too
        vm.expectRevert(bytes("ZERO_BORROWER"));
        new TrancheController(
            TrancheController.Params({
                underlyingVault: address(wrapper),
                sentinel: address(sentinel),
                borrower: address(0),
                governance: gov,
                defaultDeclarer: address(0xDEC),
                seniorGate: address(0),
                juniorGate: address(jrGate),
                seniorShareBips: 10000,
                minJuniorBips: 2000,
                defaultPenaltyWindow: 90 days,
                shareDecimals: 18,
                borrowerRecovery: false
            })
        );
    }

    /// @dev R4 (re-audit): governance can cancel a pending senior-share proposal outright, instead of
    ///      only being able to overwrite it (which resets the clock) while execution is permissionless.
    function test_R4_CancelSeniorShareProposal() public {
        vm.prank(gov);
        c.proposeSeniorShareBips(5000);
        assertGt(c.seniorShareEta(), 0, "proposal pending");

        vm.prank(address(0xBAD));
        vm.expectRevert(bytes("ONLY_GOV"));
        c.cancelSeniorShareProposal();

        vm.prank(gov);
        c.cancelSeniorShareProposal();
        assertEq(c.seniorShareEta(), 0, "eta cleared");
        assertEq(c.pendingSeniorShareBips(), 0, "pending cleared");

        // after cancel, the proposal cannot be executed even once the old timelock would have elapsed
        vm.warp(block.timestamp + 2 days + 1);
        vm.expectRevert(bytes("TIMELOCK"));
        c.executeSeniorShareBips();
    }

    /// @dev re-audit low item: proposeGovernance rejects the zero address (mirrors the factory guard).
    function test_ProposeGovernanceRejectsZero() public {
        vm.prank(gov);
        vm.expectRevert(bytes("ZERO_GOV"));
        c.proposeGovernance(address(0));
    }

    /// @dev re-audit low item: setDefaultDeclarer guards the zero address and emits an event.
    function test_SetDefaultDeclarerGuarded() public {
        vm.prank(gov);
        vm.expectRevert(bytes("ZERO_DECLARER"));
        c.setDefaultDeclarer(address(0));

        vm.prank(gov);
        c.setDefaultDeclarer(address(0xABCD));
        assertEq(c.defaultDeclarer(), address(0xABCD));
    }

    /// @dev re-audit low item: a forced external USDC balance drop (modelling a blacklist-and-destroy
    ///      against the controller) must not brick _allocate via underflow; the guard returns early.
    function test_AllocateSurvivesForcedBalanceDrop() public {
        uint256 sShares = senior.balanceOf(srLP);
        vm.prank(srLP);
        uint256 id = c.requestRedeem(true, sShares);
        (,, uint128 wmt,, uint32 expiry) = c.requests(id);
        usdc.mint(address(market), uint256(wmt));
        vm.warp(uint256(expiry) + 1);
        c.pokeRecovery(expiry);
        uint256 alloc = c.seniorCashAllocated();
        assertGt(alloc, 0, "senior cash allocated");

        // forcibly remove half the controller's USDC (models USDC admin destroy).
        // read the balance first so the argument call does not consume the prank.
        uint256 half = usdc.balanceOf(address(c)) / 2;
        vm.prank(address(c));
        usdc.transfer(address(0xdead), half);

        // recoveredUSDC now falls below what is already allocated; sync must NOT revert
        c.sync();
        assertLt(c.recoveredUSDC(), alloc, "recoveredUSDC fell below allocated without bricking");
    }
}
