// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {WaterfallMath} from "./libraries/WaterfallMath.sol";
import {TrancheToken} from "./TrancheToken.sol";
import {IEnterGate} from "./interfaces/IEnterGate.sol";
import {IERC20} from "v2-protocol/src/interfaces/IERC20.sol";
import {IWildcatSanctionsSentinel} from "v2-protocol/src/interfaces/IWildcatSanctionsSentinel.sol";
import {MarketState} from "v2-protocol/src/libraries/MarketState.sol";
import {WildcatMarket} from "v2-protocol/src/market/WildcatMarket.sol";
import {Wildcat4626Wrapper} from "v2-protocol/src/vault/Wildcat4626Wrapper.sol";
import {ReentrancyGuard} from "../lib/solady/src/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "../lib/solady/src/utils/SafeTransferLib.sol";

/// @title TrancheManager
/// @notice Per-market custody and accounting contract for two Wildcat credit tranches.
/// @dev The manager is the singleton-authorised market lender. It accepts only the base asset,
///      deposits it into the market, wraps every market token, and never transfers wrapper shares.
contract TrancheManager is ReentrancyGuard {
    using SafeTransferLib for address;

    // ----- one-time factory wiring -----
    address public immutable factory;
    bool public initialized;
    Wildcat4626Wrapper public underlyingVault;
    WildcatMarket public market;
    IERC20 public baseAsset;
    IWildcatSanctionsSentinel public sentinel;
    TrancheToken public senior;
    TrancheToken public junior;
    IEnterGate public seniorGate;
    IEnterGate public juniorGate;

    uint256 public minJuniorBips;
    uint256 public defaultPenaltyWindow;
    /// @notice Fixed annual senior target, set once during factory initialisation.
    uint256 public seniorRateBips;

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

    // ----- async redemption queue -----
    struct Request {
        address owner;
        bool isSenior;
        uint128 wmt;
        uint128 usdcClaimed;
        uint32 expiry;
    }

    Request[] public requests;
    /// @notice Cumulative class face (in wmt) queued strictly BEFORE each request: its place in the
    ///         class FIFO. Recovered cash fills each class in queue order, so a request is paid only
    ///         once allocation reaches its position. This is what makes settlement conserving.
    mapping(uint256 => uint256) public faceBefore;
    uint256 public seniorWmtQueued; // cumulative senior face ever queued
    uint256 public juniorWmtQueued; // cumulative junior face ever queued
    uint256 public seniorCashAllocated; // USDC assigned to the senior class (its FIFO fill level)
    uint256 public juniorCashAllocated; // USDC assigned to the junior class
    uint256 public recoveredUSDC; // total USDC ever received = idle balance + totalClaimedOut
    uint256 public totalClaimedOut; // cumulative USDC paid out via claim (to owners or escrow)

    // ----- bounds -----
    uint256 internal constant MAX_SENIOR_RATE_BIPS = 1e4;
    uint256 internal constant MAX_PENALTY_WINDOW = 90 days;
    uint256 internal constant MIN_INITIAL = 1e6;
    uint256 internal constant PPS_UNIT = 1e18;

    event Initialized(
        address indexed market,
        address indexed wrapper,
        address senior,
        address junior,
        address seniorGate,
        address juniorGate
    );
    event Deposited(
        bool indexed isSenior,
        address indexed caller,
        address indexed receiver,
        uint256 baseAssets,
        uint256 trancheShares
    );
    event RedeemRequested(
        uint256 indexed id,
        bool isSenior,
        address indexed owner,
        uint256 shares,
        uint256 wrapperShares,
        uint256 wmtQueued,
        uint32 expiry
    );
    event WithdrawalExecuted(uint32 indexed expiry, uint256 baseAssetsReceived, uint256 totalRecovered);
    event RecoveryAllocated(uint256 seniorDelta, uint256 juniorDelta, uint256 seniorTotal, uint256 juniorTotal);
    event Claimed(uint256 indexed id, address indexed owner, address indexed recipient, uint256 usdc, bool toEscrow);
    event StatusChanged(Status indexed previousStatus, Status indexed newStatus);
    event AccountingCheckpoint(uint256 timestamp, uint256 seniorOwed, uint256 realisedValue);

    struct Params {
        address underlyingVault;
        address sentinel;
        address seniorGate;
        address juniorGate;
        uint256 seniorRateBips;
        uint256 minJuniorBips;
        uint256 defaultPenaltyWindow;
    }

    constructor(address factory_) {
        require(factory_ != address(0), "ZERO_FACTORY");
        factory = factory_;
    }

    function initialize(Params memory p) external {
        require(msg.sender == factory, "ONLY_FACTORY");
        require(!initialized, "ALREADY_INITIALIZED");
        require(p.underlyingVault != address(0), "ZERO_ADDR");
        require(p.seniorGate == address(0) || p.seniorGate.code.length != 0, "BAD_SENIOR_GATE");
        require(p.juniorGate == address(0) || p.juniorGate.code.length != 0, "BAD_JUNIOR_GATE");
        require(p.seniorRateBips <= MAX_SENIOR_RATE_BIPS, "BAD_RATE");
        require(p.minJuniorBips >= 500 && p.minJuniorBips <= 9000, "BAD_SUBORDINATION");
        require(p.defaultPenaltyWindow > 0 && p.defaultPenaltyWindow <= MAX_PENALTY_WINDOW, "BAD_WINDOW");

        underlyingVault = Wildcat4626Wrapper(p.underlyingVault);
        market = WildcatMarket(Wildcat4626Wrapper(p.underlyingVault).market());
        baseAsset = IERC20(market.asset());
        sentinel = IWildcatSanctionsSentinel(p.sentinel);
        seniorGate = IEnterGate(p.seniorGate);
        juniorGate = IEnterGate(p.juniorGate);
        seniorRateBips = p.seniorRateBips;
        minJuniorBips = p.minJuniorBips;
        defaultPenaltyWindow = p.defaultPenaltyWindow;

        uint8 shareDecimals = market.decimals();
        senior = new TrancheToken("Wildcat Senior Tranche", "sr-wmt", shareDecimals, true);
        junior = new TrancheToken("Wildcat Junior Tranche", "jr-wmt", shareDecimals, false);

        lastAccrual = block.timestamp;
        status = Status.Active;
        markPps = _curPps();
        initialized = true;
        emit Initialized(
            address(market),
            address(underlyingVault),
            address(senior),
            address(junior),
            address(seniorGate),
            address(juniorGate)
        );
    }

    // ============================================================ valuation (realised-only)
    function _curPps() internal view returns (uint256) {
        return underlyingVault.convertToAssets(PPS_UNIT);
    }

    function _delinquent() internal view returns (bool) {
        return market.currentState().isDelinquent;
    }

    /// @dev Distress = the market is delinquent or the vault has entered wind-down. Junior cash
    ///      release is gated against the full senior obligation while distressed, so first-loss
    ///      capital cannot exit ahead of senior priority during a slow-motion default.
    function _distressed() internal view returns (bool) {
        return status == Status.WindDown || _delinquent();
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

    // ============================================================ views
    function underlying() external view returns (address) {
        return address(baseAsset);
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
        return isSenior ? sv : jv;
    }

    function defaultReached() public view returns (bool) {
        MarketState memory s = market.currentState();
        if (s.isClosed) return true;
        return WaterfallMath.defaultReached(s.timeDelinquent, market.delinquencyGracePeriod(), defaultPenaltyWindow);
    }

    /// @notice Fixed senior target rate in annual bips. It is deliberately not read from the
    ///         market's mutable APR, avoiding retroactive repricing between checkpoints.
    function currentSeniorRateBips() public view returns (uint256) {
        return seniorRateBips;
    }

    // ============================================================ accrual / lifecycle
    /// @dev Order matters: book interest for the elapsed period FIRST (while still Active), THEN
    ///      test for default. If _syncDefault ran first it would freeze seniorOwedAtDefault at the
    ///      pre-accrual value, dropping the final period's senior interest. Because the distress gate
    ///      in _allocate reserves seniorOwed, an understated seniorOwed leaks cash to junior ahead of
    ///      senior priority; accruing before the freeze keeps the reserve whole.
    function accrue() public {
        _refreshMark();
        if (status == Status.Active) {
            uint256 dt = block.timestamp - lastAccrual;
            if (dt > 0) {
                seniorOwed = WaterfallMath.accrueSeniorOwed(seniorOwed, currentSeniorRateBips(), dt);
                lastAccrual = block.timestamp;
            }
        }
        _syncDefault();
        emit AccountingCheckpoint(block.timestamp, seniorOwed, realisedValue());
    }

    function checkDefault() external {
        accrue(); // accrue the final sliver before any default freeze (see accrue)
    }

    function _syncDefault() internal {
        if (status == Status.Active && defaultReached()) {
            Status previous = status;
            status = Status.WindDown;
            seniorOwedAtDefault = seniorOwed;
            emit StatusChanged(previous, status);
        }
    }

    // ============================================================ deposits
    function depositSenior(uint256 baseAssets, address receiver) external nonReentrant returns (uint256) {
        return _deposit(true, baseAssets, receiver);
    }

    function depositJunior(uint256 baseAssets, address receiver) external nonReentrant returns (uint256) {
        return _deposit(false, baseAssets, receiver);
    }

    function _deposit(bool isSenior, uint256 baseAssets, address receiver) internal returns (uint256 shares) {
        accrue();
        require(status == Status.Active, "NOT_ACTIVE");
        require(!_delinquent(), "DELINQUENT");
        require(receiver != address(0), "ZERO_RECEIVER");
        require(!_isSanctioned(receiver) && !_isSanctioned(msg.sender), "SANCTIONED");
        _checkEntry(isSenior, receiver);

        (uint256 sv, uint256 jv) = trancheValues();
        TrancheToken token = isSenior ? senior : junior;
        uint256 supply = token.totalSupply();
        uint256 valueBefore = isSenior ? sv : jv;

        uint256 dV = _invest(baseAssets);
        require(dV > 0, "ZERO_VALUE");

        if (supply == 0) {
            require(dV >= MIN_INITIAL, "MIN_INITIAL");
            shares = dV;
        } else {
            require(valueBefore > 0, "TRANCHE_IMPAIRED");
            shares = (dV * supply) / valueBefore; // rounds down, favours the pool
        }
        require(shares > 0, "ZERO_SHARES");

        if (isSenior) {
            seniorOwed += dV;
            require(WaterfallMath.meetsSubordination(sv + dV, jv, minJuniorBips), "SUBORDINATION");
        }
        token.mint(receiver, shares);
        emit Deposited(isSenior, msg.sender, receiver, baseAssets, shares);
    }

    function _invest(uint256 baseAssets) internal returns (uint256 value) {
        address(baseAsset).safeTransferFrom(msg.sender, address(this), baseAssets);
        uint256 marketBefore = market.balanceOf(address(this));
        address(baseAsset).safeApproveWithRetry(address(market), baseAssets);
        market.deposit(baseAssets);
        address(baseAsset).safeApproveWithRetry(address(market), 0);
        uint256 marketTokens = market.balanceOf(address(this)) - marketBefore;
        require(marketTokens > 0, "ZERO_MARKET_TOKENS");

        uint256 wrapperBefore = underlyingVault.balanceOf(address(this));
        address(market).safeApproveWithRetry(address(underlyingVault), marketTokens);
        underlyingVault.deposit(marketTokens, address(this));
        address(market).safeApproveWithRetry(address(underlyingVault), 0);
        uint256 wrapperShares = underlyingVault.balanceOf(address(this)) - wrapperBefore;
        value = underlyingVault.convertToAssets(wrapperShares);
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

        // Size the wrapper redemption at the LIVE price, not the frozen mark. During delinquency the
        // mark is frozen below the live price, and redeeming at the frozen size while the wrapper pays
        // out at the live price would let the exiter pull more than its frozen-mark claim (booking
        // unrealised penalty appreciation, diluting holders who stay). Using the live price makes
        // wmtGot == assetValue, so the appreciation stays in the pool for the residual.
        uint256 cur = _curPps();
        uint256 shares4626 = cur == 0 ? 0 : (assetValue * PPS_UNIT) / cur;
        require(shares4626 > 0, "ZERO_REDEEM");
        uint256 wmtGot = underlyingVault.redeem(shares4626, address(this), address(this));
        require(wmtGot <= type(uint128).max, "WMT_OVERFLOW");
        uint32 expiry = market.queueWithdrawal(wmtGot);

        id = requests.length;
        if (isSenior) {
            faceBefore[id] = seniorWmtQueued;
            seniorWmtQueued += wmtGot;
        } else {
            faceBefore[id] = juniorWmtQueued;
            juniorWmtQueued += wmtGot;
        }
        requests.push(
            Request({owner: msg.sender, isSenior: isSenior, wmt: uint128(wmtGot), usdcClaimed: 0, expiry: expiry})
        );
        emit RedeemRequested(id, isSenior, msg.sender, shares, shares4626, wmtGot, expiry);
        // A newly queued senior (more senior room) or a reduced senior obligation (a senior exit) can
        // release cash that was being held back; re-run allocation so it reaches the right class.
        _allocate();
    }

    function pokeRecovery(uint32 expiry) external nonReentrant {
        accrue(); // refresh seniorOwed so the distress gate in _allocate reserves the live obligation
        uint256 before = baseAsset.balanceOf(address(this));
        market.executeWithdrawal(address(this), expiry);
        uint256 got = baseAsset.balanceOf(address(this)) - before;
        _syncRecovered();
        emit WithdrawalExecuted(expiry, got, recoveredUSDC);
    }

    /// @notice Credit any USDC the manager holds that has not yet been booked, then re-allocate.
    ///         Recovery is derived from the actual balance (idle USDC + everything already claimed),
    ///         so USDC that arrives outside pokeRecovery (a permissionless market executeWithdrawal,
    ///         a direct transfer, or recovery above queued face) is captured rather than stranded.
    function sync() external nonReentrant {
        accrue(); // refresh seniorOwed so the distress gate in _allocate reserves the live obligation
        _syncRecovered();
    }

    function _syncRecovered() internal {
        recoveredUSDC = baseAsset.balanceOf(address(this)) + totalClaimedOut;
        _allocate();
    }

    /// @notice Assign not-yet-allocated recovered USDC to the senior class first (up to the senior
    ///         face queued), then to junior. Under distress (delinquent or wind-down) junior may only
    ///         draw cash beyond the FULL senior obligation (seniorOwed), so first-loss capital cannot
    ///         exit ahead of senior priority; the held-back remainder stays for the senior obligation
    ///         and is released to junior only once senior is covered. O(1); no clawback.
    function _allocate() internal {
        // Guard the subtraction: recoveredUSDC is balance-derived, so a forced external balance drop
        // (e.g. a USDC blacklist-and-destroy against this contract) can push it below what is already
        // allocated. Returning early keeps allocation and claims live instead of bricking on underflow.
        uint256 allocated = seniorCashAllocated + juniorCashAllocated;
        if (recoveredUSDC <= allocated) return;
        uint256 undistributed = recoveredUSDC - allocated;

        // Senior claimants are always filled first, in queue order, up to the senior face queued.
        uint256 seniorRoom = seniorWmtQueued > seniorCashAllocated ? seniorWmtQueued - seniorCashAllocated : 0;
        uint256 toSenior = undistributed < seniorRoom ? undistributed : seniorRoom;
        if (toSenior > 0) {
            seniorCashAllocated += toSenior;
            undistributed -= toSenior;
        }
        uint256 toJunior;
        if (undistributed > 0) {
            // Junior is gated: while distressed, reserve the entire senior obligation (protects even
            // senior that has not queued yet); otherwise only the senior amount actually queued.
            uint256 seniorReserve = _distressed() ? seniorOwed : seniorWmtQueued;
            uint256 juniorCeil = recoveredUSDC > seniorReserve ? recoveredUSDC - seniorReserve : 0;
            if (juniorCeil > juniorWmtQueued) juniorCeil = juniorWmtQueued;
            uint256 juniorRoom = juniorCeil > juniorCashAllocated ? juniorCeil - juniorCashAllocated : 0;
            toJunior = undistributed < juniorRoom ? undistributed : juniorRoom;
            if (toJunior > 0) juniorCashAllocated += toJunior;
        }
        if (toSenior > 0 || toJunior > 0) {
            emit RecoveryAllocated(toSenior, toJunior, seniorCashAllocated, juniorCashAllocated);
        }
        // Any remainder stays undistributed: reserved for the senior obligation or for later requests.
    }

    /// @notice USDC currently claimable by a request. Its class fills FIFO from cash allocated to that
    ///         class, so the request is paid only once allocation reaches its position in the queue.
    ///         This mirrors the underlying market's batch ordering and never promises more than has
    ///         been recovered (sum of claimable across a class == cash allocated to it).
    function claimable(uint256 id) public view returns (uint256) {
        Request memory r = requests[id];
        uint256 allocated = r.isSenior ? seniorCashAllocated : juniorCashAllocated;
        uint256 fb = faceBefore[id];
        if (allocated <= fb) return 0;
        uint256 reached = allocated - fb;
        uint256 entitled = reached < r.wmt ? reached : r.wmt; // capped at this request's face
        return entitled > r.usdcClaimed ? entitled - r.usdcClaimed : 0;
    }

    function claim(uint256 id) external nonReentrant returns (uint256 amt) {
        Request storage r = requests[id];
        amt = claimable(id);
        if (amt == 0) return 0;
        r.usdcClaimed += uint128(amt); // effects before transfer
        totalClaimedOut += amt; // keep recoveredUSDC = idle balance + claimed invariant intact

        bool toEscrow = _isSanctioned(r.owner);
        address recipient = r.owner;
        if (toEscrow) recipient = sentinel.createEscrow(market.borrowerPrincipal(), r.owner, address(baseAsset));
        address(baseAsset).safeTransfer(recipient, amt);
        emit Claimed(id, r.owner, recipient, amt, toEscrow);
    }

    function requestsLength() external view returns (uint256) {
        return requests.length;
    }

    // ============================================================ transfer hook + sanctions
    function beforeTrancheTransfer(address token, address from, address to, uint256) external view {
        require(msg.sender == token && (token == address(senior) || token == address(junior)), "ONLY_TRANCHE_TOKEN");
        require(!_isSanctioned(from) && !_isSanctioned(to), "SANCTIONED");
        _checkEntry(token == address(senior), to);
    }

    function _checkEntry(bool isSenior, address account) internal view {
        IEnterGate gate = isSenior ? seniorGate : juniorGate;
        if (address(gate) != address(0)) require(gate.canIncreaseCredit(account), "ENTRY_NOT_ALLOWED");
    }

    function _isSanctioned(address account) internal view returns (bool) {
        if (address(sentinel) == address(0)) return false;
        return sentinel.isSanctioned(market.borrowerPrincipal(), account);
    }
}
