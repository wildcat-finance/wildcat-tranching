// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {WaterfallMath} from "./libraries/WaterfallMath.sol";
import {TrancheToken} from "./TrancheToken.sol";
import {IUnderlying4626, IWildcatMarket, ISentinelLike, IERC20, MarketState} from "./interfaces/IExternal.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/// @title TrancheController
/// @notice Senior/junior credit-tranche vault over a Wildcat ERC-4626 market wrapper (v-wmtUSDC).
///         Conservative Phase-0 model: priority-funded senior target (not a guarantee), junior
///         first-loss, fixed subordination floor, realised-only valuation, async redemption that
///         routes through the market's batched withdrawal queue senior-first, escrow on sanction,
///         and a default trigger mirroring Wildcat ToU §6.2 (grace + penalty window) on-chain.
contract TrancheController is ReentrancyGuard {
    using SafeTransferLib for address;

    // ----- immutable wiring -----
    IUnderlying4626 public immutable underlyingVault; // v-wmtUSDC
    IWildcatMarket public immutable market; // market token + delinquency state + withdrawal queue
    IERC20 public immutable baseAsset; // USDC (market.asset())
    ISentinelLike public immutable sentinel;
    address public immutable borrower;
    TrancheToken public immutable senior;
    TrancheToken public immutable junior;

    uint256 public immutable minJuniorBips;
    uint256 public immutable defaultPenaltyWindow;

    // ----- governance (bounded; senior share behind a timelock) -----
    address public governance;
    address public defaultDeclarer;
    /// @notice Senior's share of the market's base APR, in bips of BIPS (<= BIPS). The effective
    ///         senior target rate is derived live from the market; see currentSeniorRateBips().
    uint256 public seniorShareBips;
    uint256 public pendingSeniorShareBips;
    uint256 public seniorShareEta;
    bool public depositsPaused;
    mapping(address => bool) public juniorAllowed;

    // ----- accounting (in asset terms) -----
    uint256 public seniorOwed;
    uint256 public lastAccrual;
    /// @notice realised-only valuation high-watermark: assets per 1e18 underlying shares, advanced
    ///         only while the market is NOT delinquent. During delinquency the vault values its
    ///         holdings at this frozen mark, so unrealised penalty accrual is never booked as profit.
    uint256 public markPps;

    enum Status {
        Active,
        WindDown
    }

    Status public status;
    uint256 public seniorOwedAtDefault;
    bool public forcedDefault;

    // ----- async redemption queue -----
    struct Request {
        address owner;
        bool isSenior;
        uint128 wmt;
        uint128 usdcClaimed;
        uint32 expiry;
    }

    Request[] public requests;
    uint256 public totalSeniorWmtQueued;
    uint256 public totalJuniorWmtQueued;
    uint256 public recoveredUSDC;

    // ----- bounds -----
    uint256 internal constant BIPS = 1e4;
    uint256 internal constant MAX_SENIOR_SHARE_BIPS = 1e4; // senior may take at most 100% of the base APR
    uint256 internal constant MAX_PENALTY_WINDOW = 90 days;
    uint256 internal constant MIN_INITIAL = 1e6;
    uint256 internal constant PPS_UNIT = 1e18;
    uint256 public constant RATE_TIMELOCK = 2 days;

    event Deposit(bool indexed isSenior, address indexed receiver, uint256 shares, uint256 assetValue);
    event RedeemRequested(uint256 indexed id, bool isSenior, address indexed owner, uint256 shares, uint256 wmtQueued, uint32 expiry);
    event RecoveryPoked(uint32 indexed expiry, uint256 usdcReceived, uint256 totalRecovered);
    event Claimed(uint256 indexed id, address indexed owner, uint256 usdc, bool toEscrow);
    event WindDownEntered(uint256 seniorOwedAtDefault, bool forced);
    event SeniorShareProposed(uint256 shareBips, uint256 eta);
    event SeniorShareSet(uint256 shareBips);
    event JuniorAllowed(address indexed account, bool allowed);
    event DepositsPaused(bool paused);

    struct Params {
        address underlyingVault;
        address sentinel;
        address borrower;
        address governance;
        address defaultDeclarer;
        uint256 seniorShareBips;
        uint256 minJuniorBips;
        uint256 defaultPenaltyWindow;
        uint8 shareDecimals;
    }

    constructor(Params memory p) {
        require(p.underlyingVault != address(0), "ZERO_ADDR");
        require(p.seniorShareBips <= MAX_SENIOR_SHARE_BIPS, "BAD_SHARE");
        require(p.minJuniorBips >= 500 && p.minJuniorBips <= 9000, "BAD_SUBORDINATION");
        require(p.defaultPenaltyWindow > 0 && p.defaultPenaltyWindow <= MAX_PENALTY_WINDOW, "BAD_WINDOW");

        underlyingVault = IUnderlying4626(p.underlyingVault);
        market = IWildcatMarket(IUnderlying4626(p.underlyingVault).market());
        baseAsset = IERC20(market.asset());
        sentinel = ISentinelLike(p.sentinel);
        borrower = p.borrower;
        governance = p.governance;
        defaultDeclarer = p.defaultDeclarer;
        seniorShareBips = p.seniorShareBips;
        minJuniorBips = p.minJuniorBips;
        defaultPenaltyWindow = p.defaultPenaltyWindow;

        senior = new TrancheToken("Wildcat Senior Tranche", "sr-wmtUSDC", p.shareDecimals, true);
        junior = new TrancheToken("Wildcat Junior Tranche", "jr-wmtUSDC", p.shareDecimals, false);

        lastAccrual = block.timestamp;
        status = Status.Active;
        markPps = _curPps();
    }

    modifier onlyGovernance() {
        require(msg.sender == governance, "ONLY_GOV");
        _;
    }

    // ============================================================ valuation (realised-only)
    function _curPps() internal view returns (uint256) {
        return underlyingVault.convertToAssets(PPS_UNIT);
    }

    function _delinquent() internal view returns (bool) {
        return market.currentState().isDelinquent;
    }

    /// @dev Effective price per share: live while healthy, frozen at the watermark while delinquent.
    function _effPps() internal view returns (uint256) {
        uint256 cur = _curPps();
        if (_delinquent()) {
            if (markPps == 0) return cur;
            return cur < markPps ? cur : markPps;
        }
        return cur;
    }

    function _refreshMark() internal {
        if (!_delinquent()) markPps = _curPps();
    }

    function _assetsOf(uint256 shares) internal view returns (uint256) {
        return (shares * _effPps()) / PPS_UNIT;
    }

    function _sharesOf(uint256 assets) internal view returns (uint256) {
        uint256 p = _effPps();
        return p == 0 ? 0 : (assets * PPS_UNIT) / p;
    }

    // ============================================================ views
    function underlying() external view returns (address) {
        return address(underlyingVault);
    }

    function realisedValue() public view returns (uint256) {
        return _assetsOf(underlyingVault.balanceOf(address(this)));
    }

    function trancheValues() public view returns (uint256 sv, uint256 jv) {
        return WaterfallMath.split(realisedValue(), seniorOwed);
    }

    function seniorValue() public view returns (uint256 v) {
        (v,) = trancheValues();
    }

    function juniorValue() public view returns (uint256 v) {
        (, v) = trancheValues();
    }

    function trancheTotalAssets(bool isSenior) external view returns (uint256) {
        (uint256 sv, uint256 jv) = trancheValues();
        return underlyingVault.convertToShares(isSenior ? sv : jv);
    }

    function defaultReached() public view returns (bool) {
        if (forcedDefault) return true;
        MarketState memory s = market.currentState();
        if (s.isClosed) return true;
        return WaterfallMath.defaultReached(s.timeDelinquent, market.delinquencyGracePeriod(), defaultPenaltyWindow);
    }

    /// @notice Effective senior target rate (bips), derived live from the market's base APR:
    ///         senior = marketBaseAPR * seniorShareBips / BIPS, capped at the base APR so junior
    ///         bears credit risk, not rate risk. Reads annualInterestBips (base), never the penalty rate.
    function currentSeniorRateBips() public view returns (uint256) {
        uint256 marketApr = market.currentState().annualInterestBips;
        uint256 rate = (marketApr * seniorShareBips) / BIPS;
        return rate > marketApr ? marketApr : rate;
    }

    // ============================================================ accrual / lifecycle
    function accrue() public {
        _refreshMark();
        _syncDefault();
        if (status != Status.Active) return;
        uint256 dt = block.timestamp - lastAccrual;
        if (dt > 0) {
            seniorOwed = WaterfallMath.accrueSeniorOwed(seniorOwed, currentSeniorRateBips(), dt);
            lastAccrual = block.timestamp;
        }
    }

    function checkDefault() external {
        _syncDefault();
    }

    function _syncDefault() internal {
        if (status == Status.Active && defaultReached()) {
            status = Status.WindDown;
            seniorOwedAtDefault = seniorOwed;
            emit WindDownEntered(seniorOwed, forcedDefault);
        }
    }

    function declareDefault() external {
        require(msg.sender == governance || msg.sender == defaultDeclarer, "NOT_AUTH");
        forcedDefault = true;
        _syncDefault();
    }

    // ============================================================ deposits
    function depositSenior(uint256 underlyingShares, address receiver) external nonReentrant returns (uint256) {
        return _deposit(true, underlyingShares, receiver);
    }

    function depositJunior(uint256 underlyingShares, address receiver) external nonReentrant returns (uint256) {
        return _deposit(false, underlyingShares, receiver);
    }

    function _deposit(bool isSenior, uint256 underlyingShares, address receiver) internal returns (uint256 shares) {
        accrue();
        require(status == Status.Active, "NOT_ACTIVE");
        require(!depositsPaused, "DEPOSITS_PAUSED");
        require(!_isSanctioned(receiver) && !_isSanctioned(msg.sender), "SANCTIONED");
        if (!isSenior) require(juniorAllowed[receiver], "JUNIOR_NOT_WHITELISTED");

        uint256 dV = _assetsOf(underlyingShares);
        require(dV > 0, "ZERO_VALUE");

        (uint256 sv, uint256 jv) = trancheValues();
        TrancheToken token = isSenior ? senior : junior;
        uint256 supply = token.totalSupply();
        uint256 valueBefore = isSenior ? sv : jv;

        if (supply == 0) {
            require(dV >= MIN_INITIAL, "MIN_INITIAL");
            shares = dV;
        } else {
            require(valueBefore > 0, "TRANCHE_IMPAIRED");
            shares = (dV * supply) / valueBefore; // rounds down, favours the pool
        }
        require(shares > 0, "ZERO_SHARES");

        address(underlyingVault).safeTransferFrom(msg.sender, address(this), underlyingShares);

        if (isSenior) {
            seniorOwed += dV;
            require(WaterfallMath.meetsSubordination(sv + dV, jv, minJuniorBips), "SUBORDINATION");
        }
        token.mint(receiver, shares);
        emit Deposit(isSenior, receiver, shares, dV);
    }

    // ============================================================ async redemption
    function requestRedeem(bool isSenior, uint256 shares) external nonReentrant returns (uint256 id) {
        accrue();
        TrancheToken token = isSenior ? senior : junior;
        uint256 supply = token.totalSupply();
        require(supply > 0 && shares > 0, "BAD_SHARES");
        (uint256 sv, uint256 jv) = trancheValues();

        uint256 assetValue = (shares * (isSenior ? sv : jv)) / supply; // rounds down
        require(assetValue > 0, "ZERO_VALUE");

        if (isSenior) {
            uint256 owedShare = (shares * seniorOwed) / supply;
            seniorOwed = seniorOwed > owedShare ? seniorOwed - owedShare : 0;
        } else if (status == Status.Active) {
            require(assetValue <= WaterfallMath.maxJuniorWithdraw(sv, jv, minJuniorBips), "SUBORDINATION");
        }
        token.burn(msg.sender, shares); // effects before external interactions

        uint256 shares4626 = _sharesOf(assetValue);
        uint256 wmtGot = underlyingVault.redeem(shares4626, address(this), address(this));
        uint32 expiry = market.queueWithdrawal(wmtGot);

        id = requests.length;
        requests.push(Request({owner: msg.sender, isSenior: isSenior, wmt: uint128(wmtGot), usdcClaimed: 0, expiry: expiry}));
        if (isSenior) totalSeniorWmtQueued += wmtGot;
        else totalJuniorWmtQueued += wmtGot;
        emit RedeemRequested(id, isSenior, msg.sender, shares, wmtGot, expiry);
    }

    function pokeRecovery(uint32 expiry) external nonReentrant {
        uint256 before = baseAsset.balanceOf(address(this));
        market.executeWithdrawal(address(this), expiry);
        uint256 got = baseAsset.balanceOf(address(this)) - before;
        recoveredUSDC += got;
        emit RecoveryPoked(expiry, got, recoveredUSDC);
    }

    /// @notice USDC currently claimable by a request, under senior-first cumulative pro-rata.
    function claimable(uint256 id) public view returns (uint256) {
        Request memory r = requests[id];
        uint256 entitled;
        if (r.isSenior) {
            uint256 pool = recoveredUSDC < totalSeniorWmtQueued ? recoveredUSDC : totalSeniorWmtQueued;
            entitled = totalSeniorWmtQueued == 0 ? 0 : (uint256(r.wmt) * pool) / totalSeniorWmtQueued;
        } else {
            uint256 seniorPool = recoveredUSDC < totalSeniorWmtQueued ? recoveredUSDC : totalSeniorWmtQueued;
            uint256 jPool = recoveredUSDC > seniorPool ? recoveredUSDC - seniorPool : 0;
            if (jPool > totalJuniorWmtQueued) jPool = totalJuniorWmtQueued;
            entitled = totalJuniorWmtQueued == 0 ? 0 : (uint256(r.wmt) * jPool) / totalJuniorWmtQueued;
        }
        return entitled > r.usdcClaimed ? entitled - r.usdcClaimed : 0;
    }

    function claim(uint256 id) external nonReentrant returns (uint256 amt) {
        Request storage r = requests[id];
        amt = claimable(id);
        if (amt == 0) return 0;
        r.usdcClaimed += uint128(amt); // effects before transfer

        bool toEscrow = _isSanctioned(r.owner);
        if (toEscrow) {
            address escrow = sentinel.createEscrow(borrower, r.owner, address(baseAsset));
            address(baseAsset).safeTransfer(escrow, amt);
        } else {
            address(baseAsset).safeTransfer(r.owner, amt);
        }
        emit Claimed(id, r.owner, amt, toEscrow);
    }

    function requestsLength() external view returns (uint256) {
        return requests.length;
    }

    // ============================================================ transfer hook + sanctions
    function beforeTrancheTransfer(address token, address from, address to, uint256) external view {
        require(!_isSanctioned(from) && !_isSanctioned(to), "SANCTIONED");
        if (token == address(junior)) require(juniorAllowed[to], "JUNIOR_NOT_WHITELISTED");
    }

    function _isSanctioned(address account) internal view returns (bool) {
        if (address(sentinel) == address(0)) return false;
        return sentinel.isSanctioned(borrower, account);
    }

    // ============================================================ governance
    function proposeSeniorShareBips(uint256 shareBips) external onlyGovernance {
        require(shareBips <= MAX_SENIOR_SHARE_BIPS, "BAD_SHARE");
        pendingSeniorShareBips = shareBips;
        seniorShareEta = block.timestamp + RATE_TIMELOCK;
        emit SeniorShareProposed(shareBips, seniorShareEta);
    }

    function executeSeniorShareBips() external {
        require(seniorShareEta != 0 && block.timestamp >= seniorShareEta, "TIMELOCK");
        accrue();
        seniorShareBips = pendingSeniorShareBips;
        seniorShareEta = 0;
        emit SeniorShareSet(seniorShareBips);
    }

    function setJuniorAllowed(address account, bool allowed) external onlyGovernance {
        juniorAllowed[account] = allowed;
        emit JuniorAllowed(account, allowed);
    }

    function setDepositsPaused(bool paused) external onlyGovernance {
        depositsPaused = paused;
        emit DepositsPaused(paused);
    }

    function setDefaultDeclarer(address d) external onlyGovernance {
        defaultDeclarer = d;
    }
}
