// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {WaterfallMath} from "../src/libraries/WaterfallMath.sol";
import {TrancheManager} from "../src/TrancheManager.sol";
import {TrancheToken} from "../src/TrancheToken.sol";
import {MockERC20, MockMarket, MockWrapper, MockSentinel} from "./Mocks.sol";

/// @notice Property fuzzing on the pure waterfall math.
contract WaterfallFuzzTest is Test {
    function testFuzz_splitConservesAndJuniorFirst(uint256 realised, uint256 owed) public pure {
        realised = bound(realised, 0, 1e33);
        owed = bound(owed, 0, 1e33);
        (uint256 sv, uint256 jv) = WaterfallMath.split(realised, owed);
        assertEq(sv + jv, realised, "conservation");
        assertLe(sv, owed, "senior capped at owed");
        if (realised >= owed) {
            assertEq(sv, owed, "senior whole when covered");
        } else {
            assertEq(jv, 0, "junior wiped before senior impaired");
        }
    }

    function testFuzz_maxSeniorDepositKeepsFloor(uint256 sv, uint256 jv, uint256 minB) public pure {
        sv = bound(sv, 0, 1e30);
        jv = bound(jv, 0, 1e30);
        minB = bound(minB, 1, 9000);
        // property only meaningful from a compliant state (else max deposit is correctly 0)
        if (!WaterfallMath.meetsSubordination(sv, jv, minB)) return;
        uint256 x = WaterfallMath.maxSeniorDeposit(sv, jv, minB);
        // after depositing the max, junior must still be >= minB of TVL
        assertTrue(WaterfallMath.meetsSubordination(sv + x, jv, minB), "floor holds at max senior deposit");
    }

    function testFuzz_maxJuniorWithdrawKeepsFloor(uint256 sv, uint256 jv, uint256 minB) public pure {
        sv = bound(sv, 0, 1e30);
        jv = bound(jv, 0, 1e30);
        minB = bound(minB, 1, 9000);
        uint256 x = WaterfallMath.maxJuniorWithdraw(sv, jv, minB);
        if (x == 0) return;
        assertTrue(WaterfallMath.meetsSubordination(sv, jv - x, minB), "floor holds after max junior withdraw");
    }

    function testFuzz_accrualMonotonic(uint256 owed, uint256 rate, uint256 dt) public pure {
        owed = bound(owed, 0, 1e30);
        rate = bound(rate, 0, 5000);
        dt = bound(dt, 0, 3650 days);
        assertGe(WaterfallMath.accrueSeniorOwed(owed, rate, dt), owed, "accrual never decreases owed");
    }
}

/// @notice Stateful invariant handler: random deposits and redemptions in both tranches, price
///         moves, time, donations, delinquency toggles, the ToU default clock, and recovery+claims.
///         Every manager call is wrapped so the fuzzer keeps exploring through expected reverts.
contract InvariantHandler is Test {
    TrancheManager public c;
    MockWrapper public w;
    MockMarket public m;
    MockERC20 public usdc;

    constructor(TrancheManager _c, MockWrapper _w, MockMarket _m, MockERC20 _u) {
        c = _c;
        w = _w;
        m = _m;
        usdc = _u;
    }

    function depositSenior(uint256 a) public {
        a = bound(a, 1e6, 1e12);
        w.mintShares(address(this), a);
        w.approve(address(c), a);
        try c.depositSenior(a, address(this)) {} catch {}
    }

    function depositJunior(uint256 a) public {
        a = bound(a, 1e6, 1e12);
        w.mintShares(address(this), a);
        w.approve(address(c), a);
        try c.depositJunior(a, address(this)) {} catch {}
    }

    function redeemSenior(uint256 a) public {
        uint256 bal = c.senior().balanceOf(address(this));
        if (bal == 0) return;
        a = bound(a, 1, bal);
        try c.requestRedeem(true, a) {} catch {}
    }

    function redeemJunior(uint256 a) public {
        uint256 bal = c.junior().balanceOf(address(this));
        if (bal == 0) return;
        a = bound(a, 1, bal);
        try c.requestRedeem(false, a) {} catch {}
    }

    function movePrice(uint256 p) public {
        w.setPrice(bound(p, 0.4e18, 3e18));
    }

    function toggleDelinquent(bool d) public {
        m.setDelinquent(d);
        try c.accrue() {} catch {}
    }

    function donate(uint256 a) public {
        w.mintShares(address(c), bound(a, 0, 1e12));
    }

    function passTime(uint256 t) public {
        vm.warp(block.timestamp + bound(t, 0, 60 days));
        try c.accrue() {} catch {}
    }

    function advanceDefaultClock(uint256 t) public {
        // push the on-chain delinquency clock, sometimes far enough to trip the ToU default
        m.setTimeDelinquent(uint32(bound(t, 0, 200 days)));
        try c.checkDefault() {} catch {}
    }

    function pokeAndClaim(uint256 seed, uint256 fund) public {
        uint256 n = c.requestsLength();
        if (n == 0) return;
        uint256 i = seed % n;
        (,,,, uint32 expiry) = c.requests(i);
        if (block.timestamp <= expiry) vm.warp(uint256(expiry) + 1);
        usdc.mint(address(m), bound(fund, 0, 1e12)); // partial-to-over liquidity
        try c.pokeRecovery(expiry) {} catch {}
        try c.claim(i) {} catch {}
    }
}

contract TrancheInvariantTest is Test {
    TrancheManager c;
    MockWrapper w;
    MockMarket m;
    MockERC20 usdc;
    InvariantHandler handler;

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC");
        m = new MockMarket(address(usdc));
        w = new MockWrapper(address(m));
        MockSentinel sentinel = new MockSentinel();

        c = new TrancheManager(
            TrancheManager.Params({
                underlyingVault: address(w),
                sentinel: address(sentinel),
                borrower: address(0xB0110),
                governance: address(this),
                defaultDeclarer: address(this),
                seniorShareBips: 10000,
                minJuniorBips: 2000,
                defaultPenaltyWindow: 90 days,
                shareDecimals: 18
            })
        );
        handler = new InvariantHandler(c, w, m, usdc);
        c.setJuniorAllowed(address(handler), true);

        // seed a balanced position so deposits have a basis
        w.mintShares(address(this), 1000e18);
        w.approve(address(c), 1000e18);
        c.setJuniorAllowed(address(this), true);
        c.depositJunior(200e18, address(this));
        c.depositSenior(500e18, address(this));

        targetContract(address(handler));
    }

    /// @dev senior + junior value always equals realised value (no value created or lost).
    function invariant_conservation() public view {
        (uint256 sv, uint256 jv) = c.trancheValues();
        assertEq(sv + jv, c.realisedValue(), "conservation");
    }

    /// @dev while junior has value, senior is never impaired (first-loss ordering).
    function invariant_juniorFirstLoss() public view {
        (uint256 sv, uint256 jv) = c.trancheValues();
        if (jv > 0) assertEq(sv, c.seniorOwed(), "senior whole while junior has value");
    }

    /// @dev the redemption queue never promises more USDC than has actually been recovered. This held
    ///      after the FIFO senior-first settlement fix (it failed against the old growing-denominator
    ///      pool; see AttackTest.test_LateQueuerNotOverPromised).
    function invariant_noOverDistribution() public view {
        uint256 n = c.requestsLength();
        uint256 totalEntitled;
        for (uint256 i = 0; i < n; i++) {
            (,,, uint128 usdcClaimed,) = c.requests(i);
            totalEntitled += uint256(usdcClaimed) + c.claimable(i);
        }
        assertLe(totalEntitled, c.recoveredUSDC(), "no over-distribution beyond recovered USDC");
    }
}
