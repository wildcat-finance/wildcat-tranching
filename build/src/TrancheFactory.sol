// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {TrancheManager} from "./TrancheManager.sol";
import {HookedMarket} from "v2-protocol/src/access/OpenTermHooks.sol";
import {SingletonOpenTermHooks} from "v2-protocol/src/access/SingletonOpenTermHooks.sol";
import {IHooksFactory} from "v2-protocol/src/IHooksFactory.sol";
import {IWildcatArchController} from "v2-protocol/src/interfaces/IWildcatArchController.sol";
import {WildcatMarket} from "v2-protocol/src/market/WildcatMarket.sol";
import {ISingletonRoleProvider} from "v2-protocol/src/providers/ISingletonRoleProvider.sol";
import {RoleProvider} from "v2-protocol/src/types/RoleProvider.sol";
import {HooksConfig} from "v2-protocol/src/types/HooksConfig.sol";
import {Wildcat4626Wrapper} from "v2-protocol/src/vault/Wildcat4626Wrapper.sol";
import {Wildcat4626WrapperFactory} from "v2-protocol/src/vault/Wildcat4626WrapperFactory.sol";

/// @dev Keeps the manager creation code out of TrancheFactory's runtime bytecode. Only its parent
///      factory can consume a salt; the manager itself still records that parent as `factory`.
contract TrancheManagerDeployer {
    address public immutable factory;

    error OnlyFactory();

    constructor(address factory_) {
        factory = factory_;
    }

    function deploy(bytes32 salt) external returns (TrancheManager manager) {
        if (msg.sender != factory) revert OnlyFactory();
        manager = new TrancheManager{salt: salt}(factory);
    }

    function computeAddress(bytes32 salt) external view returns (address predicted) {
        bytes32 digest = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash()));
        predicted = address(uint160(uint256(digest)));
    }

    function initCodeHash() public view returns (bytes32) {
        return keccak256(abi.encodePacked(type(TrancheManager).creationCode, abi.encode(factory)));
    }
}

/// @notice Ownerless CREATE2 factory for one tranche manager per Wildcat market.
/// @dev Deployment is permissionless but not squattable: the sealed singleton provider must name
///      the manager address predicted for the caller and salt before any code is deployed.
contract TrancheFactory {
    IWildcatArchController public immutable archController;
    Wildcat4626WrapperFactory public immutable wrapperFactory;
    TrancheManagerDeployer public immutable managerDeployer;
    address public immutable singletonHooksTemplate;

    mapping(address => address) public managerForMarket;
    address[] public allManagers;

    event TrancheManagerDeployed(
        address indexed market,
        address indexed wrapper,
        address indexed manager,
        address deployer,
        bytes32 salt,
        address senior,
        address junior
    );

    error ZeroAddress();
    error MarketNotRegistered();
    error TranchesExist();
    error WrapperFactoryMismatch();
    error WrapperMismatch();
    error HookMismatch();
    error HookTemplateMismatch();
    error HookConfigurationInvalid();
    error ProviderConfigurationNotSealed();
    error ProviderConfigurationInvalid();
    error SingletonLenderMismatch();
    error BorrowerMismatch();
    error SentinelMismatch();

    constructor(address archController_, address wrapperFactory_, address singletonHooksTemplate_) {
        if (archController_ == address(0) || wrapperFactory_ == address(0) || singletonHooksTemplate_ == address(0)) {
            revert ZeroAddress();
        }
        archController = IWildcatArchController(archController_);
        wrapperFactory = Wildcat4626WrapperFactory(wrapperFactory_);
        if (singletonHooksTemplate_.code.length == 0) revert HookTemplateMismatch();
        singletonHooksTemplate = singletonHooksTemplate_;
        managerDeployer = new TrancheManagerDeployer(address(this));
    }

    struct DeployParams {
        address market;
        address wrapper;
        address hooks;
        address singletonProvider;
        address sentinel;
        address borrower;
        address governance;
        address defaultDeclarer;
        uint256 seniorRateBips;
        uint256 minJuniorBips;
        uint256 defaultPenaltyWindow;
    }

    function deployTranches(bytes32 salt, DeployParams calldata p) external returns (address managerAddr) {
        if (p.market == address(0) || p.wrapper == address(0) || p.hooks == address(0)) revert ZeroAddress();
        if (msg.sender != p.borrower) revert BorrowerMismatch();
        if (!archController.isRegisteredMarket(p.market)) revert MarketNotRegistered();
        if (managerForMarket[p.market] != address(0)) revert TranchesExist();

        managerAddr = computeManagerAddress(msg.sender, salt);
        _validateBindings(managerAddr, p);

        bytes32 effectiveSalt = _effectiveSalt(msg.sender, salt);
        TrancheManager manager = managerDeployer.deploy(effectiveSalt);
        if (address(manager) != managerAddr) revert SingletonLenderMismatch();

        manager.initialize(
            TrancheManager.Params({
                underlyingVault: p.wrapper,
                sentinel: p.sentinel,
                governance: p.governance,
                defaultDeclarer: p.defaultDeclarer,
                seniorRateBips: p.seniorRateBips,
                minJuniorBips: p.minJuniorBips,
                defaultPenaltyWindow: p.defaultPenaltyWindow
            })
        );

        managerForMarket[p.market] = managerAddr;
        allManagers.push(managerAddr);
        emit TrancheManagerDeployed(
            p.market, p.wrapper, managerAddr, msg.sender, salt, address(manager.senior()), address(manager.junior())
        );
    }

    function computeManagerAddress(address deployer, bytes32 salt) public view returns (address predicted) {
        predicted = managerDeployer.computeAddress(_effectiveSalt(deployer, salt));
    }

    function managerInitCodeHash() public view returns (bytes32) {
        return managerDeployer.initCodeHash();
    }

    function managersLength() external view returns (uint256) {
        return allManagers.length;
    }

    function _effectiveSalt(address deployer, bytes32 salt) internal pure returns (bytes32) {
        return keccak256(abi.encode(deployer, salt));
    }

    function _validateBindings(address predictedManager, DeployParams calldata p) internal view {
        WildcatMarket market = WildcatMarket(p.market);
        if (market.borrower() != p.borrower) revert BorrowerMismatch();
        if (market.borrowerPrincipal() == address(0)) revert BorrowerMismatch();
        if (market.sentinel() != p.sentinel) revert SentinelMismatch();
        if (market.wrapperFactory() != address(wrapperFactory)) revert WrapperFactoryMismatch();
        if (
            market.registeredWrapper() != p.wrapper || wrapperFactory.wrapperForMarket(p.market) != p.wrapper
                || Wildcat4626Wrapper(p.wrapper).market() != p.market
                || Wildcat4626Wrapper(p.wrapper).asset() != p.market
        ) revert WrapperMismatch();

        HooksConfig hooksConfig = market.hooks();
        if (hooksConfig.hooksAddress() != p.hooks) revert HookMismatch();
        if (!hooksConfig.useOnDeposit() || !hooksConfig.useOnTransfer()) {
            revert HookConfigurationInvalid();
        }

        SingletonOpenTermHooks hooks = SingletonOpenTermHooks(p.hooks);
        if (IHooksFactory(market.factory()).getHooksTemplateForInstance(p.hooks) != singletonHooksTemplate) {
            revert HookTemplateMismatch();
        }
        if (!hooks.roleProviderConfigurationSealed()) revert ProviderConfigurationNotSealed();
        HookedMarket memory hooked = hooks.getHookedMarket(p.market);
        if (
            !hooked.isHooked || !hooked.depositRequiresAccess || !hooked.transferRequiresAccess
                || hooked.transfersDisabled
        ) revert HookConfigurationInvalid();

        RoleProvider[] memory providers = hooks.getPullProviders();
        if (providers.length != 1 || providers[0].providerAddress() != p.singletonProvider) {
            revert ProviderConfigurationInvalid();
        }
        if (ISingletonRoleProvider(p.singletonProvider).lender() != predictedManager) {
            revert SingletonLenderMismatch();
        }
    }
}
