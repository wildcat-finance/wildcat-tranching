// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {MarketState, IERC20} from "../src/interfaces/IExternal.sol";

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory n, string memory s) {
        name = n;
        symbol = s;
    }

    function mint(address to, uint256 a) external {
        totalSupply += a;
        balanceOf[to] += a;
    }

    function approve(address sp, uint256 a) external returns (bool) {
        allowance[msg.sender][sp] = a;
        return true;
    }

    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a;
        balanceOf[to] += a;
        return true;
    }

    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        uint256 al = allowance[f][msg.sender];
        if (al != type(uint256).max) allowance[f][msg.sender] = al - a;
        balanceOf[f] -= a;
        balanceOf[t] += a;
        return true;
    }
}

/// @notice Mock Wildcat market: ERC20 market token + delinquency state + USDC withdrawal queue.
contract MockMarket {
    // --- market-token ERC20 (wmtUSDC) ---
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // --- state ---
    address public immutable asset; // USDC
    uint256 public delinquencyGracePeriod = 10 days;
    uint256 public withdrawalBatchDuration = 1 days;
    bool internal _isClosed;
    bool internal _isDelinquent;
    uint32 internal _timeDelinquent;
    uint16 internal _annualInterestBips = 1000;

    // --- withdrawal queue ---
    mapping(address => mapping(uint32 => uint256)) public owed; // account => expiry => wmt queued
    mapping(address => mapping(uint32 => uint256)) public paid; // account => expiry => USDC paid

    string internal _symbol = "abcUSDC";
    address public borrower;

    constructor(address _usdc) {
        asset = _usdc;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function setBorrower(address b_) external {
        borrower = b_;
    }

    function setSymbol(string calldata s_) external {
        _symbol = s_;
    }

    function mintTokens(address to, uint256 a) external {
        totalSupply += a;
        balanceOf[to] += a;
    }

    function approve(address sp, uint256 a) external returns (bool) {
        allowance[msg.sender][sp] = a;
        return true;
    }

    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a;
        balanceOf[to] += a;
        return true;
    }

    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        balanceOf[f] -= a;
        balanceOf[t] += a;
        return true;
    }

    function setTimeDelinquent(uint32 t) external {
        _timeDelinquent = t;
    }

    function setClosed(bool c) external {
        _isClosed = c;
    }

    function setDelinquent(bool d) external {
        _isDelinquent = d;
    }

    function setAnnualInterestBips(uint16 b) external {
        _annualInterestBips = b;
    }

    function currentState() external view returns (MarketState memory s) {
        s.isClosed = _isClosed;
        s.isDelinquent = _isDelinquent;
        s.timeDelinquent = _timeDelinquent;
        s.annualInterestBips = _annualInterestBips;
        s.scaleFactor = uint112(1e27);
    }

    uint256 public maxTotalSupply = type(uint256).max;

    function setMaxTotalSupply(uint256 m) external {
        maxTotalSupply = m;
    }

    function depositUpTo(uint256 amount) external returns (uint256 actual) {
        uint256 room = maxTotalSupply > totalSupply ? maxTotalSupply - totalSupply : 0;
        actual = amount < room ? amount : room;
        if (actual == 0) return 0;
        MockERC20(asset).transferFrom(msg.sender, address(this), actual);
        totalSupply += actual;
        balanceOf[msg.sender] += actual;
    }

    function queueWithdrawal(uint256 amount) external returns (uint32 expiry) {
        balanceOf[msg.sender] -= amount; // burn into the batch
        totalSupply -= amount;
        expiry = uint32(block.timestamp + withdrawalBatchDuration);
        owed[msg.sender][expiry] += amount;
    }

    /// @dev Pays the account min(outstanding, market USDC balance) to model partial liquidity.
    function executeWithdrawal(address account, uint32 expiry) external returns (uint256) {
        require(block.timestamp >= expiry, "NOT_EXPIRED");
        uint256 due = owed[account][expiry] - paid[account][expiry];
        uint256 bal = IERC20(asset).balanceOf(address(this));
        uint256 pay = due < bal ? due : bal;
        paid[account][expiry] += pay;
        if (pay > 0) IERC20(asset).transfer(account, pay);
        return pay;
    }
}

/// @notice Mock v-wmtUSDC: ERC-4626 wrapper over the market token, priced by a settable WAD.
contract MockWrapperFactory {
    mapping(address => address) public wrapperForMarket;
    bool public createReverts;

    function setWrapper(address market, address wrapper) external {
        wrapperForMarket[market] = wrapper;
    }

    function setCreateReverts(bool r) external {
        createReverts = r;
    }

    function createWrapper(address market) external returns (address w) {
        require(!createReverts, "WRAPPER_FACTORY_REVERT");
        require(wrapperForMarket[market] == address(0), "WRAPPER_EXISTS");
        w = address(new MockWrapper(market));
        wrapperForMarket[market] = w;
    }
}

contract MockWrapper {
    string public constant name = "v-wmtUSDC";
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public immutable market; // MockMarket
    uint256 public price = 1e18; // market tokens per wrapper share, WAD

    constructor(address _market) {
        market = _market;
    }

    function asset() external view returns (address) {
        return market;
    }

    function setPrice(uint256 p) external {
        price = p;
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        return (shares * price) / 1e18;
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        return (assets * 1e18) / price;
    }

    function previewRedeem(uint256 shares) external view returns (uint256) {
        return convertToAssets(shares);
    }

    function mintShares(address to, uint256 a) external {
        totalSupply += a;
        balanceOf[to] += a;
    }

    function approve(address sp, uint256 a) external returns (bool) {
        allowance[msg.sender][sp] = a;
        return true;
    }

    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a;
        balanceOf[to] += a;
        return true;
    }

    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        uint256 al = allowance[f][msg.sender];
        if (al != type(uint256).max) allowance[f][msg.sender] = al - a;
        balanceOf[f] -= a;
        balanceOf[t] += a;
        return true;
    }

    function deposit(uint256 assets, address to) external returns (uint256 shares) {
        MockMarket(market).transferFrom(msg.sender, address(this), assets);
        shares = convertToShares(assets);
        totalSupply += shares;
        balanceOf[to] += shares;
    }

    /// @dev Burns wrapper shares from `owner`, mints equivalent market tokens to `to`.
    function redeem(uint256 shares, address to, address owner) external returns (uint256 assets) {
        balanceOf[owner] -= shares;
        totalSupply -= shares;
        assets = convertToAssets(shares);
        MockMarket(market).mintTokens(to, assets);
    }
}

contract MockSentinel {
    mapping(address => bool) public flagged;

    function setSanctioned(address a, bool v) external {
        flagged[a] = v;
    }

    function isSanctioned(address, address account) external view returns (bool) {
        return flagged[account];
    }

    function createEscrow(address, address account, address) external pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked("escrow", account)))));
    }
}

contract MockArch {
    mapping(address => bool) public isRegisteredMarket;

    function setRegistered(address m, bool v) external {
        isRegisteredMarket[m] = v;
    }
}
