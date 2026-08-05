// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {TrancheController} from "../src/TrancheController.sol";
import {WhitelistGate} from "../src/WhitelistGate.sol";
import {TrancheFactory} from "../src/TrancheFactory.sol";
import {TrancheToken} from "../src/TrancheToken.sol";
import {MockERC20, MockMarket, MockWrapper, MockSentinel, MockArch} from "./Mocks.sol";

contract TrancheTest is Test {
    WhitelistGate internal jrGate = new WhitelistGate(address(this));
    MockERC20 usdc;
    MockMarket market;
    MockWrapper wrapper;
    MockSentinel sentinel;
    TrancheController c;
    TrancheToken senior;
    TrancheToken junior;

    address gov = address(0x6011);
    address declarer = address(0xDEC);
    address srLP = address(0x5E11);
    address jrLP = address(0x10110);
    address borrower = address(0xB0110);

    uint256 constant MIN_JUNIOR_BIPS = 2000;
    uint256 constant SENIOR_SHARE_BIPS = 10000; // senior takes 100% of the mock market APR (1000 bps) => 10%
    uint256 constant WINDOW = 90 days;

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC");
        market = new MockMarket(address(usdc));
        wrapper = new MockWrapper(address(market));
        sentinel = new MockSentinel();

        c = new TrancheController(
            TrancheController.Params({
                underlyingVault: address(wrapper),
                sentinel: address(sentinel),
                borrower: borrower,
                governance: gov,
                defaultDeclarer: declarer,
                seniorGate: address(0),
                juniorGate: address(jrGate),
                seniorShareBips: SENIOR_SHARE_BIPS,
                minJuniorBips: MIN_JUNIOR_BIPS,
                defaultPenaltyWindow: WINDOW,
                shareDecimals: 18
            })
        );
        senior = c.senior();
        junior = c.junior();

        wrapper.mintShares(srLP, 10_000_000e18);
        wrapper.mintShares(jrLP, 10_000_000e18);
        jrGate.setAllowed(jrLP, true);

        _depositJunior(jrLP, 100e18); // value 100
        _depositSenior(srLP, 300e18); // value 300 -> junior 25% of TVL
    }

    // ---------- helpers ----------
    function _depositSenior(address who, uint256 shares) internal returns (uint256) {
        vm.startPrank(who);
        wrapper.approve(address(c), shares);
        uint256 s = c.depositSenior(shares, who);
        vm.stopPrank();
        return s;
    }

    function _depositJunior(address who, uint256 shares) internal returns (uint256) {
        vm.startPrank(who);
        wrapper.approve(address(c), shares);
        uint256 s = c.depositJunior(shares, who);
        vm.stopPrank();
        return s;
    }

    function _inv() internal view {
        (uint256 sv, uint256 jv) = c.trancheValues();
        assertEq(sv + jv, c.realisedValue(), "INV senior+junior==realised");
    }

    // ---------- core waterfall ----------
    function test_DepositSplitAndSubordination() public view {
        (uint256 sv, uint256 jv) = c.trancheValues();
        assertEq(sv, 300e18);
        assertEq(jv, 100e18);
        assertEq(c.seniorOwed(), 300e18);
        _inv();
    }

    function test_SeniorDepositRevertsAboveLeverage() public {
        _depositSenior(srLP, 100e18); // junior now exactly 20%
        vm.startPrank(srLP);
        wrapper.approve(address(c), 1e18);
        vm.expectRevert(bytes("SUBORDINATION"));
        c.depositSenior(1e18, srLP);
        vm.stopPrank();
    }

    function test_SeniorTargetFundedByJuniorWhenNoYield() public {
        vm.warp(block.timestamp + 365 days);
        c.accrue();
        (uint256 sv, uint256 jv) = c.trancheValues();
        assertApproxEqAbs(sv, 330e18, 1e15, "senior +10% target");
        assertApproxEqAbs(jv, 70e18, 1e15, "junior funded coupon");
        _inv();
    }

    function test_JuniorLeveragedResidual() public {
        vm.warp(block.timestamp + 365 days);
        wrapper.setPrice(1.2e18); // +20% yield => realised 480
        c.accrue();
        (uint256 sv, uint256 jv) = c.trancheValues();
        assertApproxEqAbs(sv, 330e18, 1e15, "senior capped at target");
        assertApproxEqAbs(jv, 150e18, 1e15, "junior leveraged residual");
        _inv();
    }

    function test_LossHitsJuniorFirst() public {
        wrapper.setPrice(0.8e18); // realised 320
        (uint256 sv, uint256 jv) = c.trancheValues();
        assertEq(sv, 300e18, "senior preserved");
        assertEq(jv, 20e18, "junior absorbs loss");
        wrapper.setPrice(0.5e18); // realised 200 < senior 300
        (sv, jv) = c.trancheValues();
        assertEq(jv, 0, "junior wiped first");
        assertEq(sv, 200e18, "senior impaired only after junior gone");
        _inv();
    }

    // ---------- default trigger (ToU mirror) ----------
    function test_DefaultTriggerMirrorsToU_haltsAccrual() public {
        market.setTimeDelinquent(uint32(10 days + WINDOW - 1));
        assertFalse(c.defaultReached());
        vm.warp(block.timestamp + 30 days);
        c.accrue();
        assertGt(c.seniorOwed(), 300e18, "accrued while performing");
        uint256 owedBefore = c.seniorOwed();

        market.setTimeDelinquent(uint32(10 days + WINDOW)); // grace + 90d penalty
        assertTrue(c.defaultReached(), "ToU default");
        c.checkDefault();
        assertEq(uint256(c.status()), uint256(TrancheController.Status.WindDown));
        assertEq(c.seniorOwedAtDefault(), owedBefore);

        vm.warp(block.timestamp + 365 days);
        c.accrue();
        assertEq(c.seniorOwed(), owedBefore, "accrual halted at default");
    }

    function test_JuniorGateMandatory() public {
        vm.expectRevert(bytes("NO_JUNIOR_GATE"));
        new TrancheController(
            TrancheController.Params({
                underlyingVault: address(wrapper),
                sentinel: address(sentinel),
                borrower: borrower,
                governance: gov,
                defaultDeclarer: declarer,
                seniorGate: address(0),
                juniorGate: address(0),
                seniorShareBips: SENIOR_SHARE_BIPS,
                minJuniorBips: MIN_JUNIOR_BIPS,
                defaultPenaltyWindow: WINDOW,
                shareDecimals: 18
            })
        );
    }

    function test_SeniorGate_entryOnly() public {
        // second controller with a credentialed senior gate
        WhitelistGate srGate = new WhitelistGate(address(this));
        TrancheController c2 = new TrancheController(
            TrancheController.Params({
                underlyingVault: address(wrapper),
                sentinel: address(sentinel),
                borrower: borrower,
                governance: gov,
                defaultDeclarer: declarer,
                seniorGate: address(srGate),
                juniorGate: address(jrGate),
                seniorShareBips: SENIOR_SHARE_BIPS,
                minJuniorBips: MIN_JUNIOR_BIPS,
                defaultPenaltyWindow: WINDOW,
                shareDecimals: 18
            })
        );
        jrGate.setAllowed(jrLP, true);
        srGate.setAllowed(srLP, true);
        vm.prank(jrLP);
        wrapper.approve(address(c2), type(uint256).max);
        vm.prank(jrLP);
        c2.depositJunior(100e18, jrLP);

        // ungated senior deposit blocked
        address stranger = address(0x51124);
        wrapper.mintShares(stranger, 10e18);
        vm.startPrank(stranger);
        wrapper.approve(address(c2), type(uint256).max);
        vm.expectRevert(bytes("SENIOR_GATED"));
        c2.depositSenior(10e18, stranger);
        vm.stopPrank();

        // gated senior deposits fine; transfer-in to ungated recipient blocked
        vm.startPrank(srLP);
        wrapper.approve(address(c2), type(uint256).max);
        c2.depositSenior(100e18, srLP);
        TrancheToken sr2 = c2.senior();
        vm.expectRevert(bytes("SENIOR_GATED"));
        sr2.transfer(stranger, 1e18);
        // exit path never consults the gate: un-credential srLP, redemption still works
        vm.stopPrank();
        srGate.setAllowed(srLP, false);
        vm.prank(srLP);
        c2.requestRedeem(true, 10e18);
    }

    function test_DerivedTokenMetadata() public view {
        assertEq(senior.name(), "Senior Tranched abcUSDC");
        assertEq(senior.symbol(), "sr-abcUSDC");
        assertEq(junior.name(), "Junior Tranched abcUSDC");
        assertEq(junior.symbol(), "jr-abcUSDC");
    }

    function test_EmptyMarketSymbolRevertsDeployment() public {
        MockMarket m2 = new MockMarket(address(usdc));
        m2.setSymbol("");
        MockWrapper w2 = new MockWrapper(address(m2));
        vm.expectRevert(bytes("NO_SYMBOL"));
        new TrancheController(
            TrancheController.Params({
                underlyingVault: address(w2),
                sentinel: address(sentinel),
                borrower: borrower,
                governance: gov,
                defaultDeclarer: declarer,
                seniorGate: address(0),
                juniorGate: address(jrGate),
                seniorShareBips: SENIOR_SHARE_BIPS,
                minJuniorBips: MIN_JUNIOR_BIPS,
                defaultPenaltyWindow: WINDOW,
                shareDecimals: 18
            })
        );
    }

    function test_ClaimMany() public {
        // three partial senior exits, each its own request id across separate batches
        uint256 sShares = senior.balanceOf(srLP);
        uint256[] memory ids = new uint256[](4);
        uint32[3] memory expiries;
        for (uint256 i; i < 3; ++i) {
            vm.prank(srLP);
            ids[i] = c.requestRedeem(true, sShares / 4);
            expiries[i] = uint32(block.timestamp + market.withdrawalBatchDuration());
            vm.warp(block.timestamp + market.withdrawalBatchDuration() + 1);
        }
        ids[3] = ids[2]; // duplicate: second occurrence must claim zero, not revert
        usdc.mint(address(market), 300e18);
        for (uint256 i; i < 3; ++i) c.pokeRecovery(expiries[i]);

        uint256 expected = c.claimable(ids[0]) + c.claimable(ids[1]) + c.claimable(ids[2]);
        assertGt(expected, 0, "something claimable");
        uint256 total = c.claimMany(ids);
        assertEq(total, expected, "claimMany sums per-id claims");
        assertEq(usdc.balanceOf(srLP), expected, "paid to request owner");
        // second pass over the same ids is a no-op, not a revert
        assertEq(c.claimMany(ids), 0);
    }

    function test_DeclareDefaultOverride() public {
        vm.prank(declarer);
        c.declareDefault();
        assertEq(uint256(c.status()), uint256(TrancheController.Status.WindDown));
        assertTrue(c.forcedDefault());
    }

    // ---------- async redemption ----------
    function test_AsyncRedemption_happy() public {
        uint256 sShares = senior.balanceOf(srLP);
        vm.prank(srLP);
        uint256 id = c.requestRedeem(true, sShares); // queues 300 wmt
        uint32 expiry = uint32(block.timestamp + market.withdrawalBatchDuration());

        usdc.mint(address(market), 300e18); // market becomes liquid
        vm.warp(expiry + 1);
        c.pokeRecovery(expiry);
        assertEq(c.recoveredUSDC(), 300e18);

        vm.prank(srLP);
        uint256 got = c.claim(id);
        assertApproxEqAbs(got, 300e18, 1, "senior redeemed in full");
        assertApproxEqAbs(usdc.balanceOf(srLP), 300e18, 1);
    }

    function test_AsyncRedemption_seniorFirstOnShortfall() public {
        uint256 sShares = senior.balanceOf(srLP);
        uint256 jShares = junior.balanceOf(jrLP);
        vm.prank(srLP);
        uint256 sid = c.requestRedeem(true, sShares); // 300 wmt senior
        vm.prank(jrLP);
        uint256 jid = c.requestRedeem(false, jShares); // 100 wmt junior
        uint32 expiry = uint32(block.timestamp + market.withdrawalBatchDuration());
        vm.warp(expiry + 1);

        // partial liquidity: only 300 of 400 available -> senior must be made whole, junior gets 0
        usdc.mint(address(market), 300e18);
        c.pokeRecovery(expiry);
        assertEq(c.claimable(sid), 300e18, "senior fully claimable");
        assertEq(c.claimable(jid), 0, "junior gets nothing until senior whole");
        vm.prank(srLP);
        c.claim(sid);

        // borrower pays the rest -> junior now recovers
        usdc.mint(address(market), 100e18);
        c.pokeRecovery(expiry);
        assertEq(c.claimable(jid), 100e18, "junior recovers after senior");
        vm.prank(jrLP);
        uint256 jgot = c.claim(jid);
        assertEq(jgot, 100e18);
    }

    function test_SanctionedClaimGoesToEscrow() public {
        uint256 sShares = senior.balanceOf(srLP);
        vm.prank(srLP);
        uint256 id = c.requestRedeem(true, sShares);
        uint32 expiry = uint32(block.timestamp + market.withdrawalBatchDuration());
        usdc.mint(address(market), 300e18);
        vm.warp(expiry + 1);
        c.pokeRecovery(expiry);

        sentinel.setSanctioned(srLP, true);
        vm.prank(srLP);
        c.claim(id);
        address escrow = address(uint160(uint256(keccak256(abi.encodePacked("escrow", srLP)))));
        assertApproxEqAbs(usdc.balanceOf(escrow), 300e18, 1, "routed to escrow");
        assertEq(usdc.balanceOf(srLP), 0, "sanctioned LP gets nothing directly");
    }

    // ---------- governance ----------
    function test_SeniorShareTimelock() public {
        vm.prank(gov);
        c.proposeSeniorShareBips(5000);
        vm.expectRevert(bytes("TIMELOCK"));
        c.executeSeniorShareBips();
        vm.warp(block.timestamp + c.RATE_TIMELOCK());
        c.executeSeniorShareBips();
        assertEq(c.seniorShareBips(), 5000);
        assertEq(c.currentSeniorRateBips(), 500); // 50% of the 1000 bps market APR
    }

    // senior target is derived live from the market's base APR (capped at that APR)
    function test_SeniorRateDerivedFromMarketAPR() public {
        assertEq(c.currentSeniorRateBips(), 1000); // share 100% of the 1000 bps market APR
        market.setAnnualInterestBips(2000); // borrower lifts the facility APR
        assertEq(c.currentSeniorRateBips(), 2000); // senior target tracks it up
        market.setAnnualInterestBips(400); // borrower cuts the facility APR
        assertEq(c.currentSeniorRateBips(), 400); // senior target falls with it
        // accrual uses the live rate: one year at 4% on 300 principal
        vm.warp(block.timestamp + 365 days);
        c.accrue();
        (uint256 sv,) = c.trancheValues();
        assertApproxEqAbs(sv, 312e18, 1e15, "senior accrued at the live 4% rate");
    }

    function test_SanctionsAndWhitelistOnDeposit() public {
        sentinel.setSanctioned(srLP, true);
        vm.startPrank(srLP);
        wrapper.approve(address(c), 1e18);
        vm.expectRevert(bytes("SANCTIONED"));
        c.depositSenior(1e18, srLP);
        vm.stopPrank();
        sentinel.setSanctioned(srLP, false);

        address rando = address(0xBEEF);
        wrapper.mintShares(rando, 100e18);
        vm.startPrank(rando);
        wrapper.approve(address(c), 10e18);
        vm.expectRevert(bytes("JUNIOR_GATED"));
        c.depositJunior(10e18, rando);
        vm.stopPrank();
    }

    function test_4626Views() public view {
        assertEq(senior.asset(), address(wrapper));
        // senior value 300 (wmt) at price 1.0 => 300 wrapper shares of totalAssets
        assertApproxEqAbs(senior.totalAssets(), 300e18, 1);
        assertApproxEqAbs(senior.convertToAssets(senior.totalSupply()), 300e18, 1);
    }

    // realised-only valuation: unrealised penalty accrual during delinquency is NOT booked
    function test_RealisedOnlyFreezesDelinquentAccrual() public {
        (uint256 sv0, uint256 jv0) = c.trancheValues(); // 300 / 100 at price 1.0
        // market goes delinquent and the wrapper price climbs on (unpaid) penalty accrual
        market.setDelinquent(true);
        wrapper.setPrice(1.2e18);
        c.accrue();
        (uint256 sv1, uint256 jv1) = c.trancheValues();
        assertEq(sv1, sv0, "senior NAV frozen during delinquency");
        assertEq(jv1, jv0, "junior books no phantom gain on unrealised accrual");
        // once cured, the now-realised value is recognised
        market.setDelinquent(false);
        c.accrue();
        (, uint256 jv2) = c.trancheValues();
        assertGt(jv2, jv1, "junior recognises the upside only after it is realised");
        _inv();
    }
}

contract TrancheFactoryTest is Test {
    WhitelistGate internal jrGate = new WhitelistGate(address(this));
    function test_FactoryGatesOnRegisteredMarket() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC");
        MockMarket market = new MockMarket(address(usdc));
        MockWrapper wrapper = new MockWrapper(address(market));
        MockSentinel sentinel = new MockSentinel();
        MockArch arch = new MockArch();
        TrancheFactory factory = new TrancheFactory(address(arch));

        TrancheFactory.DeployParams memory p = TrancheFactory.DeployParams({
            underlyingVault: address(wrapper),
            sentinel: address(sentinel),
            borrower: address(0xB0110),
            governance: address(0x6011),
            defaultDeclarer: address(0xDEC),
            seniorGate: address(0),
            juniorGate: address(jrGate),
            seniorShareBips: 8000,
            minJuniorBips: 2000,
            defaultPenaltyWindow: 90 days
        });

        vm.expectRevert(bytes("MARKET_NOT_REGISTERED"));
        factory.deployTranches(p);

        arch.setRegistered(address(market), true);
        address ctrl = factory.deployTranches(p);
        assertEq(factory.controllerForMarket(address(market)), ctrl);
        assertEq(factory.controllersLength(), 1);

        vm.expectRevert(bytes("TRANCHES_EXIST"));
        factory.deployTranches(p);
    }
}
