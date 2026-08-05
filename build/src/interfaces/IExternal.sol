// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @dev Exact mirror of `src/libraries/MarketState.sol` MarketState so `currentState()` decodes
///      correctly against the real Wildcat market on a mainnet fork.
struct MarketState {
    bool isClosed;
    uint128 maxTotalSupply;
    uint128 accruedProtocolFees;
    uint128 normalizedUnclaimedWithdrawals;
    uint104 scaledTotalSupply;
    uint104 scaledPendingWithdrawals;
    uint32 pendingWithdrawalExpiry;
    bool isDelinquent;
    uint32 timeDelinquent;
    uint16 protocolFeeBips;
    uint16 annualInterestBips;
    uint16 reserveRatioBips;
    uint112 scaleFactor;
    uint32 lastInterestAccruedTimestamp;
}

/// @notice Wildcat market: it is simultaneously the ERC20 market token (wmtUSDC), the delinquency
///         state source, and the batched withdrawal queue that converts market tokens back to USDC.
interface IWildcatMarket {
    function currentState() external view returns (MarketState memory);
    function delinquencyGracePeriod() external view returns (uint256);
    function withdrawalBatchDuration() external view returns (uint256);
    function asset() external view returns (address); // the base asset (USDC)
    function borrower() external view returns (address);
    function symbol() external view returns (string memory);
    function queueWithdrawal(uint256 amount) external returns (uint32 expiry);
    function executeWithdrawal(address account, uint32 expiry) external returns (uint256);
    // ERC20 surface of the market token (wmtUSDC)
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @notice Wildcat ERC-4626 wrapper (`v-wmtUSDC`). Its `asset()` is the market token (wmtUSDC);
///         `redeem` returns market tokens (not USDC).
interface IUnderlying4626 {
    function asset() external view returns (address); // == market token
    function market() external view returns (address);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function previewRedeem(uint256 shares) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
}

interface ISentinelLike {
    function isSanctioned(address borrower, address account) external view returns (bool);
    function createEscrow(address borrower, address account, address asset) external returns (address);
}

interface IArchControllerLike {
    function isRegisteredMarket(address market) external view returns (bool);
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}
