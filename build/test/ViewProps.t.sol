// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {TrancheManager} from "../src/TrancheManager.sol";
import {TrancheToken} from "../src/TrancheToken.sol";
import {MockERC20, MockMarket, MockWrapper, MockWrapperFactory, MockSingletonHooks, MockSentinel} from "./Mocks.sol";

contract ViewPropsTest is Test {
    MockERC20 base;
    MockMarket market;
    MockWrapper wrapper;
    TrancheManager manager;
    TrancheToken senior;

    function setUp() public {
        base = new MockERC20("Base", "BASE");
        MockWrapperFactory wrapperFactory = new MockWrapperFactory();
        MockSingletonHooks hooks = new MockSingletonHooks(address(1));
        MockSentinel sentinel = new MockSentinel();
        market =
            new MockMarket(address(base), address(wrapperFactory), address(hooks), address(this), address(sentinel));
        wrapper = new MockWrapper(address(market));
        manager = new TrancheManager(address(this));
        manager.initialize(
            TrancheManager.Params({
                underlyingVault: address(wrapper),
                sentinel: address(sentinel),
                seniorGate: address(0),
                juniorGate: address(0),
                seniorRateBips: 800,
                minJuniorBips: 2000,
                defaultPenaltyWindow: 90 days,
                terminalRecipient: address(this)
            })
        );
        senior = manager.senior();
    }

    function test_EmptyViewsUseBaseAssetAndIdentityConversions() public view {
        assertEq(senior.asset(), address(base));
        assertEq(senior.totalAssets(), 0);
        assertEq(senior.convertToAssets(123e18), 123e18);
        assertEq(senior.convertToShares(123e18), 123e18);
    }
}
