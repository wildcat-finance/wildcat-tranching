// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {WaterfallMath} from "../src/libraries/WaterfallMath.sol";

contract WaterfallFuzzTest is Test {
    function testFuzz_splitConservesAndJuniorFirst(uint256 realised, uint256 owed) public pure {
        realised = bound(realised, 0, 1e33);
        owed = bound(owed, 0, 1e33);
        (uint256 seniorValue, uint256 juniorValue) = WaterfallMath.split(realised, owed);
        assertEq(seniorValue + juniorValue, realised, "conservation");
        assertLe(seniorValue, owed, "senior capped at owed");
        if (realised >= owed) assertEq(seniorValue, owed, "senior whole when covered");
        else assertEq(juniorValue, 0, "junior wiped before senior impaired");
    }

    function testFuzz_maxSeniorDepositKeepsFloor(uint256 seniorValue, uint256 juniorValue, uint256 minBips)
        public
        pure
    {
        seniorValue = bound(seniorValue, 0, 1e30);
        juniorValue = bound(juniorValue, 0, 1e30);
        minBips = bound(minBips, 1, 9000);
        if (!WaterfallMath.meetsSubordination(seniorValue, juniorValue, minBips)) return;
        uint256 amount = WaterfallMath.maxSeniorDeposit(seniorValue, juniorValue, minBips);
        assertTrue(WaterfallMath.meetsSubordination(seniorValue + amount, juniorValue, minBips));
    }

    function testFuzz_maxJuniorWithdrawKeepsFloor(uint256 seniorValue, uint256 juniorValue, uint256 minBips)
        public
        pure
    {
        seniorValue = bound(seniorValue, 0, 1e30);
        juniorValue = bound(juniorValue, 0, 1e30);
        minBips = bound(minBips, 1, 9000);
        uint256 amount = WaterfallMath.maxJuniorWithdraw(seniorValue, juniorValue, minBips);
        if (amount == 0) return;
        assertTrue(WaterfallMath.meetsSubordination(seniorValue, juniorValue - amount, minBips));
    }

    function testFuzz_accrualMonotonic(uint256 owed, uint256 rate, uint256 elapsed) public pure {
        owed = bound(owed, 0, 1e30);
        rate = bound(rate, 0, 1e4);
        elapsed = bound(elapsed, 0, 3650 days);
        assertGe(WaterfallMath.accrueSeniorOwed(owed, rate, elapsed), owed);
    }
}
