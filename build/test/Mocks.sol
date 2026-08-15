// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {HookedMarket} from "v2-protocol/src/access/OpenTermHooks.sol";
import {IERC20} from "v2-protocol/src/interfaces/IERC20.sol";
import {MarketState} from "v2-protocol/src/libraries/MarketState.sol";
import {RoleProvider} from "v2-protocol/src/types/RoleProvider.sol";
import {HooksConfig} from "v2-protocol/src/types/HooksConfig.sol";

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

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockMarket {
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public immutable asset;
    address public immutable wrapperFactory;
    address public factory;
    address public borrower;
    address public immutable borrowerPrincipal;
    address public immutable sentinel;
    HooksConfig public immutable hooks;
    address public registeredWrapper;
    uint256 public delinquencyGracePeriod = 10 days;
    uint256 public withdrawalBatchDuration = 1 days;
    bool internal _isClosed;
    bool internal _isDelinquent;
    uint32 internal _timeDelinquent;
    uint16 internal _annualInterestBips = 1000;

    mapping(address => mapping(uint32 => uint256)) public owed;
    mapping(address => mapping(uint32 => uint256)) public paid;

    constructor(address baseAsset_, address wrapperFactory_, address hooks_, address borrower_, address sentinel_) {
        asset = baseAsset_;
        wrapperFactory = wrapperFactory_;
        borrower = borrower_;
        borrowerPrincipal = borrower_;
        sentinel = sentinel_;
        hooks = HooksConfig.wrap(
            (uint256(uint160(hooks_)) << 96) | (uint256(1) << 95) | (uint256(1) << 92)
        );
    }

    function setRegisteredWrapper(address wrapper) external {
        require(registeredWrapper == address(0), "WRAPPER_SET");
        registeredWrapper = wrapper;
    }

    function setFactory(address factory_) external {
        factory = factory_;
    }

    function setBorrower(address borrower_) external {
        borrower = borrower_;
    }

    function deposit(uint256 amount) external {
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        totalSupply += amount;
        balanceOf[msg.sender] += amount;
    }

    function mintTokens(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function setTimeDelinquent(uint32 value) external {
        _timeDelinquent = value;
    }

    function setClosed(bool value) external {
        _isClosed = value;
    }

    function setDelinquent(bool value) external {
        _isDelinquent = value;
    }

    function setAnnualInterestBips(uint16 value) external {
        _annualInterestBips = value;
    }

    function currentState() external view returns (MarketState memory state) {
        state.isClosed = _isClosed;
        state.isDelinquent = _isDelinquent;
        state.timeDelinquent = _timeDelinquent;
        state.annualInterestBips = _annualInterestBips;
        state.scaleFactor = uint112(1e27);
    }

    function queueWithdrawal(uint256 amount) external returns (uint32 expiry) {
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        expiry = uint32(block.timestamp + withdrawalBatchDuration);
        owed[msg.sender][expiry] += amount;
    }

    function executeWithdrawal(address account, uint32 expiry) external returns (uint256) {
        require(block.timestamp >= expiry, "NOT_EXPIRED");
        uint256 due = owed[account][expiry] - paid[account][expiry];
        uint256 available = IERC20(asset).balanceOf(address(this));
        uint256 amount = due < available ? due : available;
        paid[account][expiry] += amount;
        if (amount > 0) IERC20(asset).transfer(account, amount);
        return amount;
    }
}

contract MockWrapper {
    string public constant name = "v-wmt";
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    address public immutable market;
    uint256 public price = 1e18;

    constructor(address market_) {
        market = market_;
    }

    function asset() external view returns (address) {
        return market;
    }

    function setPrice(uint256 value) external {
        price = value;
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

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        MockMarket(market).transferFrom(msg.sender, address(this), assets);
        shares = convertToShares(assets);
        totalSupply += shares;
        balanceOf[receiver] += shares;
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        balanceOf[owner] -= shares;
        totalSupply -= shares;
        assets = convertToAssets(shares);
        MockMarket(market).transfer(receiver, assets);
    }
}

contract MockWrapperFactory {
    mapping(address => address) public wrapperForMarket;

    function setWrapper(address market, address wrapper) external {
        wrapperForMarket[market] = wrapper;
    }
}

contract MockHooksFactory {
    mapping(address => address) public getHooksTemplateForInstance;

    function setTemplate(address hooks, address template) external {
        getHooksTemplateForInstance[hooks] = template;
    }
}

contract MockSingletonProvider {
    address public immutable lender;

    constructor(address lender_) {
        lender = lender_;
    }
}

contract MockSingletonHooks {
    bool public roleProviderConfigurationSealed = true;
    RoleProvider[] internal _providers;
    mapping(address => HookedMarket) internal _markets;

    constructor(address provider) {
        _providers.push(RoleProvider.wrap(uint256(uint160(provider)) << 64));
    }

    function version() external pure returns (string memory) {
        return "SingletonOpenTermHooks";
    }

    function setSealed(bool value) external {
        roleProviderConfigurationSealed = value;
    }

    function setMarket(address market, bool transfersDisabled) external {
        _markets[market] = HookedMarket(true, true, true, 0, transfersDisabled);
    }

    function getPullProviders() external view returns (RoleProvider[] memory) {
        return _providers;
    }

    function getHookedMarket(address market) external view returns (HookedMarket memory) {
        return _markets[market];
    }
}

contract MockUnpinnedHooks is MockSingletonHooks {
    constructor(address provider) MockSingletonHooks(provider) {}

    function marker() external pure returns (bytes32) {
        return keccak256("not-the-pinned-template");
    }
}

contract MockSentinel {
    mapping(address => bool) public flagged;

    function setSanctioned(address account, bool value) external {
        flagged[account] = value;
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

    function setRegistered(address market, bool value) external {
        isRegisteredMarket[market] = value;
    }
}
