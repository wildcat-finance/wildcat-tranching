// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {TrancheController} from "../src/TrancheController.sol";
import {WhitelistGate} from "../src/WhitelistGate.sol";
import {TrancheToken} from "../src/TrancheToken.sol";
import {MockERC20, MockMarket, MockWrapper, MockSentinel} from "./Mocks.sol";

/// @notice Property checks on the ERC-4626 *view* surface of the tranche tokens. Redemption is
///         asynchronous (ERC-7540 style), so the synchronous a16z ERC-4626 suite does not apply;
///         these target the view functions integrators actually read: asset, totalAssets,
///         convertToAssets, convertToShares, pricePerShare.
contract ViewPropsTest is Test {
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
        market.setBorrower(address(0xB0110));
        wrapper = new MockWrapper(address(market));
        sentinel = new MockSentinel();
        c = new TrancheController(
            TrancheController.Params({
                underlyingVault: address(wrapper),
                sentinel: address(sentinel),
                governance: gov,
                defaultDeclarer: address(0xDEC),
                seniorGate: address(0),
                juniorGate: address(jrGate),
                seniorShareBips: 8000,
                minJuniorBips: 2000,
                defaultPenaltyWindow: 90 days,
                shareDecimals: 18,
                borrowerRecovery: false
            })
        );
        senior = c.senior();
        junior = c.junior();
        wrapper.mintShares(srLP, 1e30);
        wrapper.mintShares(jrLP, 1e30);
        jrGate.setAllowed(jrLP, true);
    }

    function _depJ(uint256 a) internal {
        vm.startPrank(jrLP);
        wrapper.approve(address(c), a);
        c.depositJunior(a, jrLP);
        vm.stopPrank();
    }

    function _depS(uint256 a) internal {
        vm.startPrank(srLP);
        wrapper.approve(address(c), a);
        c.depositSenior(a, srLP);
        vm.stopPrank();
    }

    /// @dev asset() points at the underlying wrapper.
    function test_AssetIsUnderlying() public view {
        assertEq(senior.asset(), address(wrapper));
        assertEq(junior.asset(), address(wrapper));
    }

    /// @dev empty tranche: conversions are the identity and zero-safe.
    function test_EmptyTrancheViewsAreIdentity() public view {
        assertEq(senior.totalSupply(), 0);
        assertEq(senior.convertToAssets(123e18), 123e18, "supply 0 => convertToAssets identity");
        assertEq(senior.convertToShares(123e18), 123e18, "supply 0 => convertToShares identity");
        assertEq(senior.convertToAssets(0), 0);
        assertEq(senior.convertToShares(0), 0);
    }

    /// @dev round-trip never mints value: convertToShares(convertToAssets(s)) <= s, and
    ///      convertToAssets is monotonic non-decreasing in shares.
    function testFuzz_roundTripNoValueCreation(uint256 jDep, uint256 sDep, uint256 priceWad, uint256 shares)
        public
    {
        jDep = bound(jDep, 1e6, 1e24);
        sDep = bound(sDep, 1e6, 4 * jDep); // within the subordination cap
        priceWad = bound(priceWad, 0.4e18, 3e18);
        _depJ(jDep);
        _depS(sDep);
        wrapper.setPrice(priceWad);
        c.accrue();

        uint256 supply = senior.totalSupply();
        shares = bound(shares, 0, supply);
        uint256 assets = senior.convertToAssets(shares);
        assertLe(senior.convertToShares(assets), shares, "round-trip does not create shares");
        if (shares < supply) {
            assertGe(senior.convertToAssets(shares + 1), assets, "convertToAssets monotonic");
        }
        assertEq(senior.convertToAssets(0), 0, "zero shares -> zero assets");
    }

    /// @dev pricePerShare == convertToAssets(1e18); a full-supply round-trip equals totalAssets.
    function testFuzz_totalAssetsAndPpsConsistent(uint256 jDep, uint256 sDep, uint256 priceWad) public {
        jDep = bound(jDep, 1e6, 1e24);
        sDep = bound(sDep, 1e6, 4 * jDep);
        priceWad = bound(priceWad, 0.4e18, 3e18);
        _depJ(jDep);
        _depS(sDep);
        wrapper.setPrice(priceWad);
        c.accrue();

        assertEq(senior.pricePerShare(), senior.convertToAssets(1e18), "pps == convertToAssets(1e18)");
        assertApproxEqAbs(
            senior.convertToAssets(senior.totalSupply()), senior.totalAssets(), 2, "senior round-trip == totalAssets"
        );
        assertApproxEqAbs(
            junior.convertToAssets(junior.totalSupply()), junior.totalAssets(), 2, "junior round-trip == totalAssets"
        );
    }
}
