// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {WaterfallMath} from "./libraries/WaterfallMath.sol";
import {TrancheToken} from "./TrancheToken.sol";
import {IUnderlying4626, IWildcatMarket, ISentinelLike, IERC20, MarketState} from "./interfaces/IExternal.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/// @title TrancheManager
/// @notice Senior/junior credit-tranche vault over a Wildcat ERC-4626 market wrapper (v-wmtUSDC).
///         Conservative Phase-0 model: priority-funded senior target (not a guarantee), junior
///         first-loss, fixed subordination floor, realised-only valuation, async redemption that
///         routes through the market's batched withdrawal queue senior-first, escrow on sanction,
///         and a default trigger mirroring Wildcat ToU §6.2 (grace + penalty window) on-chain.
contract TrancheManager is ReentrancyGuard {
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
    address public pendingGovernance;
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
    uint256 internal constant BIPS = 1e4;
    uint256 internal constant MAX_SENIOR_SHARE_BIPS = 1e4; // senior may take at most 100% of the base APR
    uint256 internal constant MAX_PENALTY_WINDOW = 90 days;
    uint256 internal constant MIN_INITIAL = 1e6;
    uint256 internal constant PPS_UNIT = 1e18;
    uint256 public constant RATE_TIMELOCK = 2 days;

    event Deposit(bool indexed isSenior, address indexed receiver, uint256 shares, uint256 assetValue);
    event RedeemRequested(
        uint256 indexed id, bool isSenior, address indexed owner, uint256 shares, uint256 wmtQueued, uint32 expiry
    );
    event RecoveryPoked(uint32 indexed expiry, uint256 usdcReceived, uint256 totalRecovered);
    event Claimed(uint256 indexed id, address indexed owner, uint256 usdc, bool toEscrow);
    event WindDownEntered(uint256 seniorOwedAtDefault, bool forced);
    event SeniorShareProposed(uint256 shareBips, uint256 eta);
    event SeniorShareSet(uint256 shareBips);
    event SeniorShareProposalCancelled();
    event JuniorAllowed(address indexed account, bool allowed);
    event DepositsPaused(bool paused);
    event DefaultDeclarerSet(address indexed declarer);
    event GovernanceProposed(address indexed pending);
    event GovernanceTransferred(address indexed from, address indexed to);

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
        require(p.governance != address(0), "ZERO_GOV");
        require(p.borrower != address(0), "ZERO_BORROWER");
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
    }

    function checkDefault() external {
        accrue(); // accrue the final sliver before any default freeze (see accrue)
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
        accrue(); // books interest up to the forced-default instant, then freezes seniorOwedAtDefault
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
        emit RedeemRequested(id, isSenior, msg.sender, shares, wmtGot, expiry);
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
        emit RecoveryPoked(expiry, got, recoveredUSDC);
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
        if (undistributed == 0) return;

        // Junior is gated: while distressed, reserve the entire senior obligation (protects even
        // senior that has not queued yet); otherwise only the senior amount actually queued.
        uint256 seniorReserve = _distressed() ? seniorOwed : seniorWmtQueued;
        uint256 juniorCeil = recoveredUSDC > seniorReserve ? recoveredUSDC - seniorReserve : 0;
        if (juniorCeil > juniorWmtQueued) juniorCeil = juniorWmtQueued;
        uint256 juniorRoom = juniorCeil > juniorCashAllocated ? juniorCeil - juniorCashAllocated : 0;
        uint256 toJunior = undistributed < juniorRoom ? undistributed : juniorRoom;
        if (toJunior > 0) juniorCashAllocated += toJunior;
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

    /// @notice Cancel a pending senior-share proposal before it executes. Execution is permissionless
    ///         once the timelock elapses, so without this a mis-entered proposal could only be
    ///         overwritten (resetting the clock); cancelling lets governance abort it outright.
    function cancelSeniorShareProposal() external onlyGovernance {
        pendingSeniorShareBips = 0;
        seniorShareEta = 0;
        emit SeniorShareProposalCancelled();
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
        require(d != address(0), "ZERO_DECLARER");
        defaultDeclarer = d;
        emit DefaultDeclarerSet(d);
    }

    /// @notice Two-step governance transfer so a lost or rotated key is recoverable. The current
    ///         governance proposes a successor; the successor must accept, which prevents handing
    ///         control to an address that cannot use it.
    function proposeGovernance(address next) external onlyGovernance {
        require(next != address(0), "ZERO_GOV");
        pendingGovernance = next;
        emit GovernanceProposed(next);
    }

    function acceptGovernance() external {
        require(msg.sender == pendingGovernance, "NOT_PENDING");
        emit GovernanceTransferred(governance, pendingGovernance);
        governance = pendingGovernance;
        pendingGovernance = address(0);
    }
}
