// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {WaterfallMath} from "./libraries/WaterfallMath.sol";
import {TrancheToken} from "./TrancheToken.sol";
import {IEnterGate} from "./interfaces/IEnterGate.sol";
import {IERC20} from "v2-protocol/src/interfaces/IERC20.sol";
import {IWildcatSanctionsSentinel} from "v2-protocol/src/interfaces/IWildcatSanctionsSentinel.sol";
import {MarketState} from "v2-protocol/src/libraries/MarketState.sol";
import {WildcatMarket} from "v2-protocol/src/market/WildcatMarket.sol";
import {HooksConfig} from "v2-protocol/src/types/HooksConfig.sol";
import {Wildcat4626Wrapper} from "v2-protocol/src/vault/Wildcat4626Wrapper.sol";
import {ReentrancyGuard} from "../lib/solady/src/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "../lib/solady/src/utils/SafeTransferLib.sol";

/// @title TrancheManager
/// @notice Per-market custody and accounting contract for two Wildcat credit tranches.
/// @dev The manager is the singleton-authorised market lender. It accepts only the base asset,
///      deposits it into the market, wraps every market token, and never transfers wrapper shares.
contract TrancheManager is ReentrancyGuard {
    using SafeTransferLib for address;

    error ManagerSanctioned();

    // ----- one-time factory wiring -----
    address public immutable factory;
    bool public initialized;
    Wildcat4626Wrapper public underlyingVault;
    WildcatMarket public market;
    address public marketHooks;
    address public borrowerPrincipal;
    IERC20 public baseAsset;
    IWildcatSanctionsSentinel public sentinel;
    TrancheToken public senior;
    TrancheToken public junior;
    IEnterGate public seniorGate;
    IEnterGate public juniorGate;

    uint256 public minJuniorBips;
    uint256 public defaultPenaltyWindow;
    uint256 public delinquencyGracePeriod;
    /// @notice Fixed annual senior target, set once during factory initialisation.
    uint256 public seniorRateBips;

    // ----- accounting (in asset terms) -----
    uint256 public seniorPrincipal;
    uint256 public seniorOwed;
    uint256 public seniorAccrualRemainder;
    uint256 public lastAccrual;
    /// @notice Realised-only aggregate book value, advanced only while the market is healthy.
    ///         During delinquency withdrawals reduce this value by their backed face, so changing
    ///         wrapper share count cannot leak unrealised penalty accrual into later requests.
    uint256 public markedAssets;

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
    uint256 public pendingRequests;
    /// @notice Cumulative class face (in wmt) queued strictly BEFORE each request: its place in the
    ///         class FIFO. Recovered cash fills each class in queue order, so a request is paid only
    ///         once allocation reaches its position. This is what makes settlement conserving.
    mapping(uint256 => uint256) public faceBefore;
    uint256 public seniorWmtQueued; // cumulative senior face ever queued
    uint256 public juniorWmtQueued; // cumulative junior face ever queued
    uint256 public seniorCashAllocated; // USDC assigned to the senior class (its FIFO fill level)
    uint256 public juniorCashAllocated; // USDC assigned to the junior class
    /// @notice Face recorded against each exact Wildcat withdrawal batch. Execution proceeds may
    ///         only admit recovery against the batch which produced them.
    mapping(uint32 => uint256) public faceQueuedByExpiry;
    /// @notice Queue face already backed by an authenticated receipt or a tagged senior reserve.
    ///         This is distinct from the raw receipt total because a reserve may replace an exit's
    ///         backing before the underlying batch later executes.
    mapping(uint32 => uint256) public faceCreditedByExpiry;
    /// @notice Cumulative market recovery observed for each batch, including any excess that was
    ///         intentionally placed in a senior reserve or terminal surplus.
    mapping(uint32 => uint256) public recoveryObservedByExpiry;
    uint256 public recoveredUSDC; // total USDC ever received = idle balance + totalClaimedOut
    uint256 public allocatableUSDC; // recovery admitted against queued face which existed on arrival
    uint256 public seniorDebtReserveUSDC; // recovery admitted only against live distressed senior debt
    uint256 public recoverySurplus; // recovery above those obligations; never inherited by later requests
    uint256 public totalClaimedOut; // cumulative USDC paid out via claim (to owners or escrow)
    /// @notice Immutable facility term which receives proven residual after every holder and
    ///         request is settled. It cannot be selected by a last-minute tranche buyer.
    address public terminalRecipient;
    bool public terminalised;

    // ----- bounds -----
    uint256 internal constant MAX_SENIOR_RATE_BIPS = 1e4;
    uint256 internal constant MAX_PENALTY_WINDOW = 90 days;
    uint256 internal constant MIN_INITIAL = 1e6;

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
    event TerminalCustodyQueued(uint256 wrapperShares, uint256 marketTokens, uint32 expiry);
    event TerminalSurplusSettled(address indexed terminalRecipient, address indexed recipient, uint256 usdc, bool toEscrow);
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
        address terminalRecipient;
    }

    constructor(address factory_) {
        require(factory_ != address(0), "ZERO_FACTORY");
        factory = factory_;
    }

    function initialize(Params memory p) external {
        require(msg.sender == factory, "ONLY_FACTORY");
        require(!initialized, "ALREADY_INITIALIZED");
        require(p.underlyingVault != address(0), "ZERO_ADDR");
        require(p.terminalRecipient != address(0), "ZERO_TERMINAL_RECIPIENT");
        require(p.seniorGate == address(0) || p.seniorGate.code.length != 0, "BAD_SENIOR_GATE");
        require(p.juniorGate == address(0) || p.juniorGate.code.length != 0, "BAD_JUNIOR_GATE");
        require(p.seniorRateBips <= MAX_SENIOR_RATE_BIPS, "BAD_RATE");
        require(p.minJuniorBips >= 500 && p.minJuniorBips <= 9000, "BAD_SUBORDINATION");
        require(p.defaultPenaltyWindow > 0 && p.defaultPenaltyWindow <= MAX_PENALTY_WINDOW, "BAD_WINDOW");

        underlyingVault = Wildcat4626Wrapper(p.underlyingVault);
        market = WildcatMarket(Wildcat4626Wrapper(p.underlyingVault).market());
        marketHooks = market.hooks().hooksAddress();
        borrowerPrincipal = market.borrowerPrincipal();
        baseAsset = IERC20(market.asset());
        terminalRecipient = p.terminalRecipient;
        sentinel = IWildcatSanctionsSentinel(p.sentinel);
        seniorGate = IEnterGate(p.seniorGate);
        juniorGate = IEnterGate(p.juniorGate);
        seniorRateBips = p.seniorRateBips;
        minJuniorBips = p.minJuniorBips;
        defaultPenaltyWindow = p.defaultPenaltyWindow;
        delinquencyGracePeriod = market.delinquencyGracePeriod();

        uint8 shareDecimals = market.decimals();
        require(shareDecimals >= 6, "BAD_DECIMALS");
        senior = new TrancheToken("Wildcat Senior Tranche", "sr-wmt", shareDecimals, true);
        junior = new TrancheToken("Wildcat Junior Tranche", "jr-wmt", shareDecimals, false);

        lastAccrual = block.timestamp;
        status = Status.Active;
        markedAssets = underlyingVault.convertToAssets(underlyingVault.balanceOf(address(this)));
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
    function _delinquent() internal view returns (bool) {
        return market.currentState().isDelinquent;
    }

    /// @dev Distress = the market is delinquent or the vault has entered wind-down. Junior cash
    ///      release is gated against the full senior obligation while distressed, so first-loss
    ///      capital cannot exit ahead of senior priority during a slow-motion default.
    function _distressed() internal view returns (bool) {
        return status == Status.WindDown || _delinquent();
    }

    function _refreshMark() internal {
        if (!_delinquent()) markedAssets = _liveAssets();
    }

    function _liveAssets() internal view returns (uint256) {
        return underlyingVault.convertToAssets(underlyingVault.balanceOf(address(this)));
    }

    // ============================================================ views
    function underlying() external view returns (address) {
        return address(baseAsset);
    }

    function realisedValue() public view returns (uint256) {
        uint256 liveAssets = _liveAssets();
        if (!_delinquent()) return liveAssets;
        return liveAssets < markedAssets ? liveAssets : markedAssets;
    }

    function trancheValues() public view returns (uint256 sv, uint256 jv) {
        return WaterfallMath.split(realisedValue(), previewSeniorOwed());
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
        return _defaultReached(market.currentState());
    }

    /// @notice Fixed senior target rate in annual bips. It is deliberately not read from the
    ///         market's mutable APR, avoiding retroactive repricing between checkpoints.
    function currentSeniorRateBips() public view returns (uint256) {
        return seniorRateBips;
    }

    /// @notice Senior obligation after applying elapsed fixed-rate accrual without writing state.
    function previewSeniorOwed() public view returns (uint256 owed) {
        owed = seniorOwed;
        if (status != Status.Active) return owed;
        MarketState memory s = market.currentState();
        uint256 accrualEnd = _accrualEnd(s);
        if (accrualEnd <= lastAccrual) return owed;
        (uint256 interest,) = WaterfallMath.accrueSeniorInterest(
            seniorPrincipal, seniorRateBips, accrualEnd - lastAccrual, seniorAccrualRemainder
        );
        return owed + interest;
    }

    // ============================================================ accrual / lifecycle
    /// @dev The market state is read before interest is booked so a delinquency threshold caps the
    ///      accrual interval. Market closure uses the synchronous hook callback below because V2.5
    ///      does not retain an immutable close timestamp after later state writes.
    function accrue() public {
        MarketState memory s = market.currentState();
        _refreshMark();
        if (status == Status.Active) {
            uint256 accrualEnd = _accrualEnd(s);
            _accrueTo(accrualEnd);
        }
        _syncDefault(s);
        emit AccountingCheckpoint(block.timestamp, seniorOwed, realisedValue());
    }

    /// @notice Exact terminal checkpoint called by this market's pinned TrancheOpenTermHooks.
    /// @dev Closure can only move the manager from Active to WindDown; it cannot be undone.
    function onMarketClosed(address closedMarket, uint32 marketTimeDelinquent) external {
        require(msg.sender == marketHooks, "ONLY_MARKET_HOOKS");
        require(closedMarket == address(market), "WRONG_MARKET");
        if (status != Status.Active) return;
        _accrueTo(_delinquencyAccrualEnd(marketTimeDelinquent));
        _enterWindDown();
    }

    /// @notice Exact recovery checkpoint called by the pinned market hook before the base asset is
    ///         transferred to this manager. This keeps recovery provenance independent of whoever
    ///         called the market's permissionless withdrawal executor.
    function onMarketWithdrawalExecuted(
        address executedMarket,
        uint32 expiry,
        uint128 normalizedAmount,
        MarketState calldata state
    )
        external
    {
        require(msg.sender == marketHooks, "ONLY_MARKET_HOOKS");
        require(executedMarket == address(market), "WRONG_MARKET");
        // A sanctioned manager would receive this withdrawal through the market escrow, which has
        // no expiry-bearing release callback. Revert before the market marks the batch executed so
        // its authenticated provenance remains available after the sanction is cleared.
        if (_isMarketSettlementSanctioned()) revert ManagerSanctioned();
        if (status == Status.Active) {
            _accrueTo(_accrualEnd(state));
            if (_defaultReached(state)) _enterWindDown();
        }
        bool reserveLiveSenior = status == Status.WindDown || state.isDelinquent;
        _bookWithdrawalRecovery(expiry, normalizedAmount, reserveLiveSenior, reserveLiveSenior);
    }

    function checkDefault() external {
        accrue(); // accrue the final sliver before any default freeze (see accrue)
    }

    function _syncDefault(MarketState memory s) internal {
        if (status == Status.Active && _defaultReached(s)) {
            _enterWindDown();
        }
    }

    function _accrueTo(uint256 accrualEnd) internal {
        if (accrualEnd <= lastAccrual) return;
        (uint256 interest, uint256 nextRemainder) = WaterfallMath.accrueSeniorInterest(
            seniorPrincipal, seniorRateBips, accrualEnd - lastAccrual, seniorAccrualRemainder
        );
        seniorOwed += interest;
        seniorAccrualRemainder = nextRemainder;
        lastAccrual = accrualEnd;
    }

    function _enterWindDown() internal {
        Status previous = status;
        status = Status.WindDown;
        seniorOwedAtDefault = seniorOwed;
        emit StatusChanged(previous, status);
    }

    function _defaultReached(MarketState memory s) internal view returns (bool) {
        if (s.isClosed) return true;
        return WaterfallMath.defaultReached(s.timeDelinquent, delinquencyGracePeriod, defaultPenaltyWindow);
    }

    function _accrualEnd(MarketState memory s) internal view returns (uint256 end) {
        if (s.isClosed) {
            // A correctly pinned TrancheOpenTermHooks instance checkpoints closure synchronously.
            // If an already-closed market is observed during initialisation, do not invent elapsed
            // active time from a timestamp which V2.5 may have advanced after closure.
            return lastAccrual;
        }
        return _delinquencyAccrualEnd(s.timeDelinquent);
    }

    function _delinquencyAccrualEnd(uint32 timeDelinquent) internal view returns (uint256 end) {
        end = block.timestamp;
        uint256 threshold = delinquencyGracePeriod + defaultPenaltyWindow;
        if (timeDelinquent >= threshold) {
            end -= uint256(timeDelinquent) - threshold;
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
        // Retire any unqueued senior-debt reserve from an earlier delinquency before fresh capital
        // can enter and become the apparent justification for it.
        _syncRecovered();
        require(!terminalised, "TERMINAL");
        require(status == Status.Active, "NOT_ACTIVE");
        require(!_delinquent(), "DELINQUENT");
        require(receiver != address(0), "ZERO_RECEIVER");
        require(!_isSanctioned(receiver) && !_isSanctioned(msg.sender), "SANCTIONED");
        _checkEntry(isSenior, receiver);

        (uint256 sv, uint256 jv) = trancheValues();
        TrancheToken token = isSenior ? senior : junior;
        uint256 supply = token.totalSupply();
        uint256 valueBefore = isSenior ? sv : jv;
        if (supply == 0) require(valueBefore == 0, "RESIDUAL_VALUE");

        uint256 dV = _invest(baseAssets);
        require(dV > 0, "ZERO_VALUE");
        markedAssets = _liveAssets();

        if (supply == 0) {
            require(dV >= MIN_INITIAL, "MIN_INITIAL");
            shares = dV;
        } else {
            require(valueBefore > 0, "TRANCHE_IMPAIRED");
            shares = (dV * supply) / valueBefore; // rounds down, favours the pool
        }
        require(shares > 0, "ZERO_SHARES");

        if (isSenior) {
            seniorPrincipal += dV;
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
        // Classify cash which arrived before this request against the pre-request obligation set.
        // Otherwise a caller could enlarge the admission ceiling before an earlier balance delta
        // is observed, allowing the new request to inherit old recovery.
        _syncRecovered();
        TrancheToken token = isSenior ? senior : junior;
        uint256 supply = token.totalSupply();
        require(supply > 0 && shares > 0, "BAD_SHARES");
        (uint256 sv, uint256 jv) = trancheValues();

        uint256 assetValue = (shares * (isSenior ? sv : jv)) / supply; // rounds down
        require(assetValue > 0, "ZERO_VALUE");

        if (isSenior) {
            uint256 owedShare;
            uint256 principalShare;
            if (shares == supply) {
                owedShare = seniorOwed;
                principalShare = seniorPrincipal;
                seniorAccrualRemainder = 0;
            } else {
                owedShare = (shares * seniorOwed) / supply;
                principalShare = (shares * seniorPrincipal) / supply;
                seniorAccrualRemainder -= (shares * seniorAccrualRemainder) / supply;
            }
            seniorOwed = seniorOwed > owedShare ? seniorOwed - owedShare : 0;
            seniorPrincipal = seniorPrincipal > principalShare ? seniorPrincipal - principalShare : 0;
        } else if (status == Status.Active) {
            require(assetValue <= WaterfallMath.maxJuniorWithdraw(sv, jv, minJuniorBips), "SUBORDINATION");
        }
        token.burn(msg.sender, shares); // effects before external interactions
        bool enteringTerminal = senior.totalSupply() == 0 && junior.totalSupply() == 0;
        if (enteringTerminal) terminalised = true;

        // Remove an exact number of scaled wrapper shares, then denominate the request at the
        // floor-normalised value of those shares. The wrapper's redeem label and the market queue
        // both move the same scaled units, so FIFO face cannot exceed its actual backing.
        uint256 shares4626 = underlyingVault.convertToShares(assetValue);
        require(shares4626 > 0, "ZERO_REDEEM");
        uint256 requestFace = underlyingVault.convertToAssets(shares4626);
        require(requestFace > 0, "ZERO_FACE");
        require(requestFace <= type(uint128).max, "WMT_OVERFLOW");
        uint256 redeemLabel = underlyingVault.redeem(shares4626, address(this), address(this));
        uint32 expiry = market.queueWithdrawal(redeemLabel);
        markedAssets -= requestFace;

        id = requests.length;
        if (isSenior) {
            faceBefore[id] = seniorWmtQueued;
            seniorWmtQueued += requestFace;
        } else {
            faceBefore[id] = juniorWmtQueued;
            juniorWmtQueued += requestFace;
        }
        faceQueuedByExpiry[expiry] += requestFace;
        requests.push(
            Request({owner: msg.sender, isSenior: isSenior, wmt: uint128(requestFace), usdcClaimed: 0, expiry: expiry})
        );
        ++pendingRequests;
        emit RedeemRequested(id, isSenior, msg.sender, shares, shares4626, requestFace, expiry);
        if (isSenior && _distressed()) _migrateSeniorDebtReserve(expiry, requestFace);
        // A newly queued senior (more senior room) or a reduced senior obligation (a senior exit) can
        // release cash that was being held back; re-run allocation so it reaches the right class.
        _allocate();
        // A frozen mark can make the final tranche burn consume fewer live-priced wrapper shares
        // than remain in custody. That excess belongs to the immutable facility residual, not to a
        // later capital cycle (which is forbidden once this point is reached). Queue it now so the
        // terminal settlement path can never be stranded behind an unreachable wrapper balance.
        if (enteringTerminal) _queueTerminalCustody();
    }

    /// @dev Once both supplies are zero, no live holder exists to own residual wrapper or market
    ///      custody. Queue it alongside the final holder withdrawal; its unaffiliated receipt is
    ///      deliberately booked as `recoverySurplus` by the authenticated execution callback.
    function _queueTerminalCustody() internal {
        uint256 wrapperShares = underlyingVault.balanceOf(address(this));
        if (wrapperShares > 0) {
            underlyingVault.redeem(wrapperShares, address(this), address(this));
        }

        uint256 marketTokens = market.balanceOf(address(this));
        // There is no longer a tranche claim on the aggregate mark once both supplies are gone.
        markedAssets = 0;
        if (marketTokens == 0) return;
        // `balanceOf` is normalised while the market keeps scaled balances. Queueing that displayed
        // amount can round back down and strand a scaled unit, so terminal custody must use the
        // market's exact full-balance primitive.
        uint32 expiry = market.queueFullWithdrawal();
        emit TerminalCustodyQueued(wrapperShares, marketTokens, expiry);
    }

    function pokeRecovery(uint32 expiry) external nonReentrant {
        accrue();
        // Classify any pre-existing balance conservatively. The execute hook books the exact new
        // amount and contemporaneous state before the market transfers it, even if another caller
        // invokes `market.executeWithdrawal` directly.
        _syncRecovered();
        uint256 before = baseAsset.balanceOf(address(this));
        market.executeWithdrawal(address(this), expiry);
        uint256 got = baseAsset.balanceOf(address(this)) - before;
        _syncRecovered();
        emit WithdrawalExecuted(expiry, got, recoveredUSDC);
    }

    /// @notice Credit any USDC the manager holds that has not yet been booked, then re-allocate.
    ///         Market withdrawal proceeds are already classified by the pinned execution hook;
    ///         this conservatively captures direct transfers and other unexplained balance changes.
    function sync() external nonReentrant {
        accrue(); // refresh seniorOwed so the distress gate in _allocate reserves the live obligation
        _syncRecovered();
    }

    /// @dev Generic balance observation is deliberately conservative: the pinned execution hook
    ///      has already classified market withdrawals at their exact arrival-time state and expiry.
    ///      Unattributed cash can never be safely assigned to one queued batch, so it is terminal
    ///      surplus rather than another source of claimable recovery.
    function _syncRecovered() internal {
        uint256 observed = baseAsset.balanceOf(address(this)) + totalClaimedOut;
        if (observed > recoveredUSDC) {
            _bookUnattributedRecovery(observed - recoveredUSDC, _distressed());
        } else {
            _retireObsoleteSeniorDebtReserve(_distressed());
            _allocate();
        }
    }

    function _bookUnattributedRecovery(uint256 delta, bool distressed) internal {
        _retireObsoleteSeniorDebtReserve(distressed);
        recoveredUSDC += delta;
        recoverySurplus += delta;
        _allocate(distressed);
    }

    /// @dev A market execution identifies its withdrawal batch. Keep its recovery admission keyed
    ///      to that expiry so a scaled surplus from an older batch cannot later be re-labelled as
    ///      backing for a request queued in a newer batch.
    function _bookWithdrawalRecovery(uint32 expiry, uint256 delta, bool reserveLiveSenior, bool distressed) internal {
        _retireObsoleteSeniorDebtReserve(distressed);
        recoveredUSDC += delta;

        uint256 observed = recoveryObservedByExpiry[expiry];
        uint256 batchFace = faceQueuedByExpiry[expiry];
        uint256 batchCredited = faceCreditedByExpiry[expiry];
        uint256 batchRoom = batchFace > batchCredited ? batchFace - batchCredited : 0;
        uint256 globalCeiling = seniorWmtQueued + juniorWmtQueued;
        uint256 globalRoom = globalCeiling > allocatableUSDC ? globalCeiling - allocatableUSDC : 0;
        uint256 queuedAdmission = delta < batchRoom ? delta : batchRoom;
        if (queuedAdmission > globalRoom) queuedAdmission = globalRoom;
        recoveryObservedByExpiry[expiry] = observed + delta;
        faceCreditedByExpiry[expiry] = batchCredited + queuedAdmission;
        allocatableUSDC += queuedAdmission;
        delta -= queuedAdmission;

        if (delta > 0 && reserveLiveSenior) {
            uint256 reserveRoom = seniorOwed > seniorDebtReserveUSDC ? seniorOwed - seniorDebtReserveUSDC : 0;
            uint256 reserveAdmission = delta < reserveRoom ? delta : reserveRoom;
            seniorDebtReserveUSDC += reserveAdmission;
            delta -= reserveAdmission;
        }
        recoverySurplus += delta;
        _allocate(distressed);
    }

    /// @dev Convert a tagged live-senior reserve only into the senior face which replaces that debt.
    ///      Any reserve above the remaining live obligation is terminal surplus.
    function _migrateSeniorDebtReserve(uint32 expiry, uint256 requestFace) internal {
        uint256 migrated = requestFace < seniorDebtReserveUSDC ? requestFace : seniorDebtReserveUSDC;
        seniorDebtReserveUSDC -= migrated;
        allocatableUSDC += migrated;
        faceCreditedByExpiry[expiry] += migrated;
        _retireObsoleteSeniorDebtReserve(true);
    }

    function _retireObsoleteSeniorDebtReserve(bool distressed) internal {
        uint256 retained = distressed ? seniorOwed : 0;
        if (seniorDebtReserveUSDC > retained) {
            uint256 retired = seniorDebtReserveUSDC - retained;
            seniorDebtReserveUSDC = retained;
            recoverySurplus += retired;
        }
    }

    /// @notice Assign not-yet-allocated recovered USDC to the senior class first (up to the senior
    ///         face queued), then to junior. Under distress (delinquent or wind-down) junior may only
    ///         draw cash beyond the FULL senior obligation (seniorOwed), so first-loss capital cannot
    ///         exit ahead of senior priority; the held-back remainder stays for the senior obligation
    ///         and is released to junior only once senior is covered. O(1); no clawback.
    function _allocate() internal {
        _allocate(_distressed());
    }

    /// @dev `onMarketWithdrawalExecuted` receives the exact market state while the market lock is
    ///      held, so it must supply `distressed` rather than re-entering `currentState()` here.
    function _allocate(bool distressed) internal {
        // Guard the subtraction: recoveredUSDC is balance-derived, so a forced external balance drop
        // (e.g. a USDC blacklist-and-destroy against this contract) can push it below what is already
        // allocated. Returning early keeps allocation and claims live instead of bricking on underflow.
        uint256 allocated = seniorCashAllocated + juniorCashAllocated;
        if (allocatableUSDC <= allocated) return;
        uint256 undistributed = allocatableUSDC - allocated;

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
            // `seniorDebtReserveUSDC` is segregated cash already covering unqueued live senior
            // debt. Deduct only the uncovered remainder from queued-face recovery; otherwise that
            // same senior protection would block a junior request whose own cash is fully backed.
            uint256 uncoveredSeniorOwed =
                seniorOwed > seniorDebtReserveUSDC ? seniorOwed - seniorDebtReserveUSDC : 0;
            uint256 seniorReserve = distressed ? seniorWmtQueued + uncoveredSeniorOwed : seniorWmtQueued;
            uint256 juniorCeil = allocatableUSDC > seniorReserve ? allocatableUSDC - seniorReserve : 0;
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
        if (r.usdcClaimed == r.wmt) --pendingRequests;
        totalClaimedOut += amt; // keep recoveredUSDC = idle balance + claimed invariant intact

        bool toEscrow = _isSanctioned(r.owner);
        address recipient = r.owner;
        if (toEscrow) recipient = sentinel.createEscrow(borrowerPrincipal, r.owner, address(baseAsset));
        address(baseAsset).safeTransfer(recipient, amt);
        emit Claimed(id, r.owner, recipient, amt, toEscrow);
    }

    /// @notice Release base asset which is provably outside every tranche claim after the final
    ///         position and request have settled. The recipient is an immutable facility term,
    ///         never selected by this caller or by the final share burn.
    function settleTerminalSurplus() external nonReentrant returns (uint256 amt) {
        accrue();
        _syncRecovered();
        require(terminalised, "NOT_TERMINAL");
        require(senior.totalSupply() == 0 && junior.totalSupply() == 0, "LIVE_SUPPLY");
        require(underlyingVault.balanceOf(address(this)) == 0 && market.balanceOf(address(this)) == 0, "LIVE_CUSTODY");
        require(seniorDebtReserveUSDC == 0, "SENIOR_RESERVE");
        require(pendingRequests == 0, "REQUESTS_PENDING");

        amt = recoverySurplus;
        if (amt == 0) return 0;
        recoverySurplus = 0;
        totalClaimedOut += amt;
        bool toEscrow = _isSanctioned(terminalRecipient);
        address recipient = terminalRecipient;
        if (toEscrow) recipient = sentinel.createEscrow(borrowerPrincipal, terminalRecipient, address(baseAsset));
        address(baseAsset).safeTransfer(recipient, amt);
        emit TerminalSurplusSettled(terminalRecipient, recipient, amt, toEscrow);
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
        return sentinel.isSanctioned(borrowerPrincipal, account);
    }

    /// @dev Match the market's live sanctions namespace for the pre-transfer execution callback.
    ///      `borrowerPrincipal` may rotate after manager deployment, and this predicate determines
    ///      whether the market will pay this manager directly or route the withdrawal to escrow.
    function _isMarketSettlementSanctioned() internal view returns (bool) {
        if (address(sentinel) == address(0)) return false;
        return sentinel.isSanctioned(market.borrowerPrincipal(), address(this));
    }
}
