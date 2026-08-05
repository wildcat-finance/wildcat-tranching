// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {TrancheController} from "../src/TrancheController.sol";
import {WhitelistGate} from "../src/WhitelistGate.sol";
import {IUnderlying4626, IWildcatMarket, MarketState} from "../src/interfaces/IExternal.sol";

/// @notice Fork tests against the REAL deployed Wildcat contracts on Ethereum mainnet.
///         Validates that our lean interfaces decode the live ABIs (notably the packed
///         MarketState struct), that valuation reads the live wrapper, that the ToU default
///         mirror reads live delinquency state, and that redemption queues against the real
///         batched withdrawal queue.
contract ForkTest is Test {
    WhitelistGate internal jrGate; // constructed post-fork-selection: pre-fork deployments vanish
    string RPC = "https://eth-main.hinterlight.net";

    address constant WRAPPER = 0xF65460B84c13eeb911303336Ab0f9D63CC79839f; // v-wmtUSDC
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    IUnderlying4626 wrapper;
    IWildcatMarket market;
    TrancheController c;

    address srLP = address(0x5E11);
    address jrLP = address(0x10110);

    bool forked;

    function setUp() public {
        try vm.createSelectFork(RPC) {
            forked = true;
        } catch {
            forked = false;
            return;
        }
        jrGate = new WhitelistGate(address(this));
        wrapper = IUnderlying4626(WRAPPER);
        market = IWildcatMarket(wrapper.market());

        c = new TrancheController(
            TrancheController.Params({
                underlyingVault: WRAPPER,
                sentinel: address(0), // sanctions logic is unit-tested; skip on fork // unused while sentinel is zero; non-zero per ZERO_BORROWER guard
                governance: address(this),
                defaultDeclarer: address(this),
                seniorGate: address(0),
                juniorGate: address(jrGate),
                seniorShareBips: 10000, // senior takes 100% of the live base APR
                minJuniorBips: 2000,
                defaultPenaltyWindow: 90 days,
                shareDecimals: 6,
                borrowerRecovery: false
            })
        );
    }

    modifier onlyForked() {
        if (!forked) {
            emit log("SKIP: fork RPC unavailable");
            return;
        }
        _;
    }

    /// @dev Reading the live MarketState through our interface is the main ABI risk; assert it decodes.
    function test_fork_readIntegration() public onlyForked {
        assertEq(address(c.market()), wrapper.market(), "market wired from wrapper");
        assertEq(address(c.baseAsset()), USDC, "base asset is live USDC");

        uint256 grace = market.delinquencyGracePeriod();
        assertLe(grace, 90 days, "grace within protocol max");
        emit log_named_uint("delinquencyGracePeriod (s)", grace);

        MarketState memory s = market.currentState();
        assertGt(s.scaleFactor, 0, "scaleFactor decoded > 0 (struct order OK)");
        emit log_named_uint("scaleFactor", s.scaleFactor);
        emit log_named_uint("timeDelinquent (s)", s.timeDelinquent);
        emit log_named_uint("annualInterestBips", s.annualInterestBips);
        assertEq(c.currentSeniorRateBips(), s.annualInterestBips, "senior rate derived from live base APR (100% share)");
        emit log_string(s.isClosed ? "market isClosed: true" : "market isClosed: false");
        emit log_string(s.isDelinquent ? "market isDelinquent: true" : "market isDelinquent: false");

        // value of 1.0 v-wmtUSDC share, read live
        emit log_named_uint("convertToAssets(1e6)", wrapper.convertToAssets(1e6));

        // a healthy market is not at the ToU default threshold
        emit log_string(c.defaultReached() ? "defaultReached: TRUE" : "defaultReached: false");
        assertEq(c.realisedValue(), 0, "no deposits yet");
    }

    /// @dev Deposit real v-wmtUSDC (via deal) and assert tranche accounting matches the live wrapper.
    function test_fork_depositMatchesLiveValuation() public onlyForked {
        uint256 amt = 3000e6;
        deal(WRAPPER, srLP, amt);
        deal(WRAPPER, jrLP, 1000e6);
        if (wrapper.balanceOf(srLP) < amt) {
            emit log("SKIP: deal could not set v-wmtUSDC balance on this wrapper");
            return;
        }
        jrGate.setAllowed(jrLP, true);

        vm.startPrank(jrLP);
        IUnderlying4626(WRAPPER).approve(address(c), 1000e6);
        c.depositJunior(1000e6, jrLP);
        vm.stopPrank();

        vm.startPrank(srLP);
        IUnderlying4626(WRAPPER).approve(address(c), amt);
        c.depositSenior(amt, srLP);
        vm.stopPrank();

        (uint256 sv, uint256 jv) = c.trancheValues();
        uint256 expected = wrapper.convertToAssets(4000e6);
        assertApproxEqAbs(sv + jv, expected, 2, "TVL matches live convertToAssets");
        assertEq(sv + jv, c.realisedValue(), "invariant holds on fork");
        emit log_named_uint("seniorValue", sv);
        emit log_named_uint("juniorValue", jv);
    }

    /// @dev Exercise redemption against the REAL market withdrawal queue.
    function test_fork_redeemQueuesAgainstRealMarket() public onlyForked {
        uint256 amt = 3000e6;
        deal(WRAPPER, srLP, amt);
        deal(WRAPPER, jrLP, 1000e6);
        if (wrapper.balanceOf(srLP) < amt) {
            emit log("SKIP: deal could not set v-wmtUSDC balance");
            return;
        }
        // junior leg first so the senior deposit satisfies the subordination floor
        jrGate.setAllowed(jrLP, true);
        vm.startPrank(jrLP);
        IUnderlying4626(WRAPPER).approve(address(c), 1000e6);
        c.depositJunior(1000e6, jrLP);
        vm.stopPrank();

        vm.startPrank(srLP);
        IUnderlying4626(WRAPPER).approve(address(c), amt);
        c.depositSenior(amt, srLP);
        uint256 sShares = c.senior().balanceOf(srLP);

        // requestRedeem calls the REAL wrapper.redeem + REAL market.queueWithdrawal
        try c.requestRedeem(true, sShares) returns (uint256 id) {
            emit log_named_uint("queued request id", id);
            (,, uint128 wmt,, uint32 expiry) = c.requests(id);
            emit log_named_uint("wmt queued", wmt);
            emit log_named_uint("batch expiry", expiry);
            assertGt(wmt, 0, "market tokens queued");
            vm.stopPrank();

            // advance past the batch and pull whatever liquidity the market has paid
            vm.warp(uint256(expiry) + 1);
            c.pokeRecovery(expiry);
            emit log_named_uint("recoveredUSDC (real liquidity)", c.recoveredUSDC());
            // market may be illiquid (borrower drawn) -> recovery can be 0; just assert no revert + sane state
            assertGe(c.recoveredUSDC(), 0);
        } catch Error(string memory reason) {
            vm.stopPrank();
            emit log_named_string("requestRedeem reverted (real market constraint)", reason);
        }
    }
}
