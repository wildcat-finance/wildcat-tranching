// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @dev Exact mirror of the V2/V2.5 MarketState return tuple.
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

struct HookedMarket {
    bool isHooked;
    bool transferRequiresAccess;
    bool depositRequiresAccess;
    uint128 minimumDeposit;
    bool transfersDisabled;
}

interface IWildcatMarket {
    function currentState() external view returns (MarketState memory);
    function delinquencyGracePeriod() external view returns (uint256);
    function withdrawalBatchDuration() external view returns (uint256);
    function asset() external view returns (address);
    function decimals() external view returns (uint8);
    function borrower() external view returns (address);
    function borrowerPrincipal() external view returns (address);
    function sentinel() external view returns (address);
    function hooks() external view returns (uint256);
    function wrapperFactory() external view returns (address);
    function registeredWrapper() external view returns (address);
    function deposit(uint256 amount) external;
    function queueWithdrawal(uint256 amount) external returns (uint32 expiry);
    function executeWithdrawal(address account, uint32 expiry) external returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IUnderlying4626 {
    function asset() external view returns (address);
    function market() external view returns (address);
    function totalSupply() external view returns (uint256);
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

interface IWrapperFactoryLike {
    function wrapperForMarket(address market) external view returns (address wrapper);
}

interface ISingletonHooksLike {
    function roleProviderConfigurationSealed() external view returns (bool);
    function getPullProviders() external view returns (uint256[] memory);
    function getHookedMarket(address market) external view returns (HookedMarket memory);
}

interface ISingletonProviderLike {
    function lender() external view returns (address);
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
