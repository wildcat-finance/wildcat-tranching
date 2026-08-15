// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {TrancheManager} from "../src/TrancheManager.sol";
import {MockERC20, MockMarket, MockWrapper, MockWrapperFactory, MockSingletonHooks, MockSentinel} from "./Mocks.sol";

contract TrancheInvariantHandler is Test {
    TrancheManager public manager;
    MockERC20 public base;
    MockMarket public market;
    MockWrapper public wrapper;

    constructor(TrancheManager manager_, MockERC20 base_, MockMarket market_, MockWrapper wrapper_) {
        manager = manager_;
        base = base_;
        market = market_;
        wrapper = wrapper_;
        base.approve(address(manager), type(uint256).max);
    }

    function depositJunior(uint256 amount) external {
        amount = bound(amount, 1e6, 1000e18);
        try manager.depositJunior(amount, address(this)) {} catch {}
    }

    function depositSenior(uint256 amount) external {
        amount = bound(amount, 1e6, 1000e18);
        try manager.depositSenior(amount, address(this)) {} catch {}
    }

    function redeemJunior(uint256 amount) external {
        uint256 balance = manager.junior().balanceOf(address(this));
        if (balance == 0) return;
        amount = bound(amount, 1, balance);
        try manager.requestRedeem(false, amount) {} catch {}
    }

    function redeemSenior(uint256 amount) external {
        uint256 balance = manager.senior().balanceOf(address(this));
        if (balance == 0) return;
        amount = bound(amount, 1, balance);
        try manager.requestRedeem(true, amount) {} catch {}
    }

    function movePrice(uint256 price) external {
        wrapper.setPrice(bound(price, 0.5e18, 2e18));
        try manager.accrue() {} catch {}
    }

    function passTime(uint256 elapsed) external {
        vm.warp(block.timestamp + bound(elapsed, 0, 30 days));
        try manager.accrue() {} catch {}
    }

    function recoverAndClaim(uint256 seed, uint256 liquidity) external {
        uint256 count = manager.requestsLength();
        if (count == 0) return;
        uint256 id = seed % count;
        (,,,, uint32 expiry) = manager.requests(id);
        if (block.timestamp <= expiry) vm.warp(uint256(expiry) + 1);
        base.mint(address(market), bound(liquidity, 0, 1000e18));
        try manager.pokeRecovery(expiry) {} catch {}
        try manager.claim(id) {} catch {}
    }
}

contract TrancheInvariantTest is Test {
    TrancheManager manager;
    MockERC20 base;
    MockMarket market;
    MockWrapper wrapper;
    TrancheInvariantHandler handler;

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
                seniorRateBips: 1000,
                minJuniorBips: 2000,
                defaultPenaltyWindow: 90 days,
                terminalRecipient: address(this)
            })
        );

        handler = new TrancheInvariantHandler(manager, base, market, wrapper);
        base.mint(address(handler), 1_000_000_000e18);

        handler.depositJunior(200e18);
        handler.depositSenior(500e18);
        targetContract(address(handler));
    }

    function invariant_waterfallConservesValue() public view {
        (uint256 seniorValue, uint256 juniorValue) = manager.trancheValues();
        assertEq(seniorValue + juniorValue, manager.realisedValue());
    }

    function invariant_juniorTakesFirstLoss() public view {
        (uint256 seniorValue, uint256 juniorValue) = manager.trancheValues();
        if (juniorValue > 0) assertEq(seniorValue, manager.previewSeniorOwed());
    }

    function invariant_seniorAccrualStateIsBounded() public view {
        assertLe(manager.seniorPrincipal(), manager.seniorOwed());
        assertLt(manager.seniorAccrualRemainder(), 1e4 * 365 days);
    }

    function invariant_managerOwnsWrapperSupplyAndNoMarketTokens() public view {
        assertEq(wrapper.balanceOf(address(manager)), wrapper.totalSupply());
        assertEq(market.balanceOf(address(manager)), 0);
    }

    function invariant_claimsNeverExceedRecovery() public view {
        uint256 count = manager.requestsLength();
        uint256 entitled;
        for (uint256 i; i < count; ++i) {
            (,,, uint128 claimed,) = manager.requests(i);
            entitled += uint256(claimed) + manager.claimable(i);
        }
        assertLe(entitled, manager.recoveredUSDC());
        assertLe(manager.allocatableUSDC(), manager.recoveredUSDC());
        assertEq(
            manager.allocatableUSDC() + manager.seniorDebtReserveUSDC() + manager.recoverySurplus(),
            manager.recoveredUSDC()
        );
    }
}
