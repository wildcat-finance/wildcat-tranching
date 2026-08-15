// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @title WaterfallMath
/// @notice Pure senior/junior tranche accounting for the Wildcat in-house tranching layer.
///         Senior holds a priority claim that accrues at a target rate; junior is the
///         first-loss residual. Everything is denominated in underlying-asset terms and is
///         driven off *realised* value only (no oracle, no mark-to-market).
///
/// Core invariant (holds after every operation):
///         seniorValue + juniorValue == realisedValue
/// and junior floors at 0 before senior takes any loss (first-loss subordination).
library WaterfallMath {
    uint256 internal constant BIPS = 1e4;
    uint256 internal constant YEAR = 365 days;

    /// @notice Linear accrual of the senior's owed claim at an annual bips rate (Wildcat-style,
    ///         linear-per-update). Senior accrues only while the market is performing; the
    ///         manager stops calling this once a default is mirrored on-chain.
    function accrueSeniorOwed(uint256 seniorOwed, uint256 annualRateBips, uint256 dt) internal pure returns (uint256) {
        if (seniorOwed == 0 || annualRateBips == 0 || dt == 0) return seniorOwed;
        uint256 interest = (seniorOwed * annualRateBips * dt) / (BIPS * YEAR);
        return seniorOwed + interest;
    }

    /// @notice Split realised value: senior up to its owed claim, junior the residual.
    ///         Junior is first-loss: it absorbs the entire shortfall before senior is impaired.
    function split(uint256 realisedValue, uint256 seniorOwed)
        internal
        pure
        returns (uint256 seniorValue, uint256 juniorValue)
    {
        seniorValue = realisedValue < seniorOwed ? realisedValue : seniorOwed;
        juniorValue = realisedValue - seniorValue;
    }

    /// @notice True if junior is at least `minJuniorBips` of TVL (the subordination floor).
    function meetsSubordination(uint256 seniorValue, uint256 juniorValue, uint256 minJuniorBips)
        internal
        pure
        returns (bool)
    {
        uint256 tvl = seniorValue + juniorValue;
        if (tvl == 0) return true;
        return juniorValue * BIPS >= minJuniorBips * tvl;
    }

    /// @notice Largest senior deposit (by value) that keeps junior >= minJuniorBips of TVL.
    ///         A senior deposit leaves junior value unchanged and grows TVL by x:
    ///         require junior*BIPS >= minJuniorBips*(tvl + x).
    function maxSeniorDeposit(uint256 seniorValue, uint256 juniorValue, uint256 minJuniorBips)
        internal
        pure
        returns (uint256)
    {
        if (minJuniorBips == 0) return type(uint256).max;
        uint256 cap = (juniorValue * BIPS) / minJuniorBips; // max TVL allowed
        uint256 tvl = seniorValue + juniorValue;
        return cap > tvl ? cap - tvl : 0;
    }

    /// @notice Largest junior withdrawal (by value) that keeps junior >= minJuniorBips of TVL.
    ///         A junior withdrawal of x lowers both junior value and TVL by x:
    ///         require (junior - x)*BIPS >= minJuniorBips*(tvl - x).
    function maxJuniorWithdraw(uint256 seniorValue, uint256 juniorValue, uint256 minJuniorBips)
        internal
        pure
        returns (uint256)
    {
        uint256 tvl = seniorValue + juniorValue;
        uint256 lhsJ = juniorValue * BIPS;
        uint256 rhs = minJuniorBips * tvl;
        if (lhsJ <= rhs) return 0;
        uint256 den = BIPS - minJuniorBips; // minJuniorBips < BIPS enforced by manager
        return (lhsJ - rhs) / den;
    }

    /// @notice Mirror of Wildcat Terms-of-Use §6.2 using the market's on-chain delinquency counter:
    ///             timeDelinquent >= delinquencyGracePeriod + penaltyWindow.
    /// @dev V2.5 reduces `timeDelinquent` during cure rather than reconstructing separate episodes.
    ///      The manager reads that counter as supplied. The penalty window is fixed at deployment.
    function defaultReached(uint256 timeDelinquent, uint256 gracePeriod, uint256 penaltyWindow)
        internal
        pure
        returns (bool)
    {
        return timeDelinquent >= gracePeriod + penaltyWindow;
    }
}
