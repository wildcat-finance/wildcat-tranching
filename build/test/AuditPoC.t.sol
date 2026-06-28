// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {TrancheController} from "../src/TrancheController.sol";
import {TrancheToken} from "../src/TrancheToken.sol";
import {MockERC20, MockMarket, MockWrapper, MockSentinel} from "./Mocks.sol";

/// @notice PoC for the pashov-auditor headline finding (SR-D): during delinquency, requestRedeem
///         sizes the wrapper-share redemption at the FROZEN mark (_effPps) but underlyingVault.redeem
///         converts those shares at the LIVE price, so the exiter pulls out more market tokens (and
///         hence more recoverable USDC) than its frozen-mark entitlement, booking the unrealised
///         penalty appreciation that the high-watermark valuation deliberately freezes, at the
///         expense of holders who stay. This test asserts the (buggy) over-redemption to document it.
contract AuditPoCTest is Test {
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
                seniorShareBips: 10000,
                minJuniorBips: 2000,
                defaultPenaltyWindow: 90 days,
                shareDecimals: 18
            })
        );
        senior = c.senior();
        junior = c.junior();
        wrapper.mintShares(srLP, 1_000e18);
        wrapper.mintShares(jrLP, 1_000e18);
        vm.prank(gov);
        c.setJuniorAllowed(jrLP, true);
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

    function test_PoC_FrozenMarkOverRedemptionDuringDelinquency() public {
        // market goes delinquent and the wrapper price climbs on (unpaid) penalty accrual
        market.setDelinquent(true);
        wrapper.setPrice(1.2e18); // curPps = 1.2, markPps frozen at 1.0 -> effPps = 1.0

        uint256 balBefore = wrapper.balanceOf(address(c)); // 400e18

        // a senior holder redeems half its position (150 shares of 300)
        vm.prank(srLP);
        uint256 id = c.requestRedeem(true, 150e18);

        // frozen-mark entitlement of these shares is 150 (assetValue at effPps = 1.0)
        // but the queued market tokens are sized at the live price:
        (,, uint128 wmt,,) = c.requests(id);
        assertEq(uint256(wmt), 180e18, "BUG: queued 180 wmt for a 150 frozen-mark claim (1.2x over-redeem)");

        // and the controller's wrapper balance dropped by 150 shares (sized at frozen 1.0),
        // not the 125 shares (150 / 1.2) a live-priced redemption of a 150 claim would cost
        uint256 redeemed = balBefore - wrapper.balanceOf(address(c));
        assertEq(redeemed, 150e18, "BUG: redeemed 150 wrapper shares (frozen sizing) not 125 (live)");

        // The exiter has queued 180 USDC-equivalent of claim; once the market pays, they book the
        // 30 of unrealised appreciation the high-watermark was meant to freeze, diluting stayers.
    }
}
