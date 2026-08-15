// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";

import {TrancheFactory} from "../src/TrancheFactory.sol";
import {TrancheManager} from "../src/TrancheManager.sol";
import {TrancheOpenTermHooks} from "../src/TrancheOpenTermHooks.sol";
import {HooksFactory} from "v2-protocol/src/HooksFactory.sol";
import {WildcatArchController} from "v2-protocol/src/WildcatArchController.sol";
import {WildcatBorrowerIdentityRegistry} from "v2-protocol/src/WildcatBorrowerIdentityRegistry.sol";
import {WildcatSanctionsSentinel} from "v2-protocol/src/WildcatSanctionsSentinel.sol";
import {SingletonOpenTermHooks, SingletonOpenTermHooksInputs} from "v2-protocol/src/access/SingletonOpenTermHooks.sol";
import {CreateProviderInputs, NameAndProviderInputs} from "v2-protocol/src/access/ProviderStructs.sol";
import {DeployMarketInputs} from "v2-protocol/src/interfaces/WildcatStructsAndEnums.sol";
import {LibStoredInitCode} from "v2-protocol/src/libraries/LibStoredInitCode.sol";
import {WildcatMarket} from "v2-protocol/src/market/WildcatMarket.sol";
import {SingletonRoleProviderFactoryInputs} from "v2-protocol/src/providers/ISingletonRoleProviderFactory.sol";
import {ISingletonRoleProvider} from "v2-protocol/src/providers/ISingletonRoleProvider.sol";
import {SingletonRoleProviderFactory} from "v2-protocol/src/providers/SingletonRoleProviderFactory.sol";
import {RoleProvider} from "v2-protocol/src/types/RoleProvider.sol";
import {encodeHooksConfig} from "v2-protocol/src/types/HooksConfig.sol";
import {Wildcat4626Wrapper} from "v2-protocol/src/vault/Wildcat4626Wrapper.sol";
import {Wildcat4626WrapperFactory} from "v2-protocol/src/vault/Wildcat4626WrapperFactory.sol";

contract ForkChainalysisList {
    function isSanctioned(address) external pure returns (bool) {
        return false;
    }
}

contract ForkAsset {
    string public constant name = "Fork Asset";
    string public constant symbol = "FORK";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
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

/// @notice Deploys the pinned V2.5 contracts on a mainnet fork and exercises the complete
///         market -> canonical wrapper -> predicted TrancheManager path.
contract ForkTest is Test {
    string internal constant DEFAULT_RPC = "https://eth-main.hinterlight.net";
    uint256 internal constant FORK_BLOCK = 25_758_381;
    bytes32 internal constant MANAGER_SALT = keccak256("tranche-manager-fork");

    ForkAsset internal asset;
    WildcatArchController internal archController;
    WildcatBorrowerIdentityRegistry internal borrowerIdentityRegistry;
    WildcatSanctionsSentinel internal sentinel;
    Wildcat4626WrapperFactory internal wrapperFactory;
    HooksFactory internal hooksFactory;
    SingletonRoleProviderFactory internal providerFactory;
    TrancheFactory internal trancheFactory;
    address internal singletonHooksTemplate;

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", DEFAULT_RPC);
        vm.createSelectFork(rpc, FORK_BLOCK);
    }

    function test_fork_fullV25DeploymentPath() public {
        _deployProtocolStack();

        address predictedManager = trancheFactory.computeManagerAddress(address(this), MANAGER_SALT);
        bytes memory hooksConstructorArgs = _singletonConstructorArgs(predictedManager);
        DeployMarketInputs memory marketInputs = _marketInputs();
        bytes32 marketSalt = bytes32((uint256(uint160(address(this))) << 96) | uint256(13));

        (address marketAddress, address hooksAddress) = hooksFactory.deployMarketAndHooks(
            singletonHooksTemplate,
            hooksConstructorArgs,
            marketInputs,
            abi.encode(uint128(0), false),
            marketSalt,
            address(0),
            0
        );
        WildcatMarket market = WildcatMarket(marketAddress);
        SingletonOpenTermHooks hooks = SingletonOpenTermHooks(hooksAddress);
        address wrapperAddress = wrapperFactory.createWrapper(marketAddress);

        RoleProvider[] memory providers = hooks.getPullProviders();
        assertEq(providers.length, 1, "singleton provider count");
        address singletonProvider = providers[0].providerAddress();

        address managerAddress = trancheFactory.deployTranches(
            MANAGER_SALT,
            TrancheFactory.DeployParams({
                market: marketAddress,
                wrapper: wrapperAddress,
                hooks: hooksAddress,
                singletonProvider: singletonProvider,
                sentinel: address(sentinel),
                borrower: address(this),
                seniorGate: address(0),
                juniorGate: address(0),
                seniorRateBips: 800,
                minJuniorBips: 2000,
                defaultPenaltyWindow: 28 days
            })
        );
        TrancheManager manager = TrancheManager(managerAddress);

        assertEq(managerAddress, predictedManager, "predicted manager");
        assertTrue(archController.isRegisteredMarket(marketAddress), "registered market");
        assertEq(market.registeredWrapper(), wrapperAddress, "market wrapper");
        assertEq(wrapperFactory.wrapperForMarket(marketAddress), wrapperAddress, "factory wrapper");
        assertEq(Wildcat4626Wrapper(wrapperAddress).market(), marketAddress, "wrapper market");
        assertEq(hooksFactory.getHooksTemplateForInstance(hooksAddress), singletonHooksTemplate, "hooks template");
        assertTrue(hooks.roleProviderConfigurationSealed(), "sealed provider configuration");
        assertEq(ISingletonRoleProvider(singletonProvider).lender(), managerAddress, "singleton lender");
        assertEq(trancheFactory.managerForMarket(marketAddress), managerAddress, "registered manager");
        assertEq(address(manager.market()), marketAddress, "manager market");
        assertEq(address(manager.underlyingVault()), wrapperAddress, "manager wrapper");
        assertEq(address(manager.baseAsset()), address(asset), "manager base asset");
        assertTrue(manager.initialized(), "manager initialised");
        assertEq(address(manager.seniorGate()), address(0), "senior entry gate");
        assertEq(address(manager.juniorGate()), address(0), "junior entry gate");
        assertEq(manager.seniorRateBips(), 800, "senior rate");
        assertEq(manager.minJuniorBips(), 2000, "minimum junior share");
        assertEq(manager.defaultPenaltyWindow(), 28 days, "default penalty window");
        assertEq(market.currentState().annualInterestBips, 1000, "market rate");
        assertEq(market.currentState().reserveRatioBips, 1000, "market reserve ratio");
        assertEq(market.currentState().maxTotalSupply, 1_000_000e18, "market capacity");
        assertEq(market.withdrawalBatchDuration(), 14 days, "withdrawal batch duration");
        assertEq(market.delinquencyGracePeriod(), 28 days, "delinquency grace period");
        assertEq(manager.senior().manager(), managerAddress, "senior manager");
        assertTrue(manager.senior().isSenior(), "senior class");
        assertEq(manager.junior().manager(), managerAddress, "junior manager");
        assertFalse(manager.junior().isSenior(), "junior class");
    }

    function _deployProtocolStack() internal {
        asset = new ForkAsset();
        archController = new WildcatArchController();
        borrowerIdentityRegistry = new WildcatBorrowerIdentityRegistry(address(archController));
        sentinel = new WildcatSanctionsSentinel(address(archController), address(new ForkChainalysisList()));
        wrapperFactory = new Wildcat4626WrapperFactory(address(archController), address(0));

        bytes memory marketInitCode = type(WildcatMarket).creationCode;
        hooksFactory = new HooksFactory(
            address(archController),
            address(sentinel),
            address(wrapperFactory),
            LibStoredInitCode.deployInitCode(marketInitCode),
            uint256(keccak256(marketInitCode)),
            address(borrowerIdentityRegistry)
        );
        archController.registerControllerFactory(address(hooksFactory));
        hooksFactory.registerWithArchController();

        providerFactory = new SingletonRoleProviderFactory();
        singletonHooksTemplate = LibStoredInitCode.deployInitCode(type(TrancheOpenTermHooks).creationCode);
        hooksFactory.addHooksTemplate(singletonHooksTemplate, "TrancheOpenTermHooks", address(0), address(0), 0, 0);
        archController.registerBorrower(address(this));
        trancheFactory = new TrancheFactory(address(archController), address(wrapperFactory), singletonHooksTemplate);
    }

    function _singletonConstructorArgs(address predictedManager) internal view returns (bytes memory) {
        SingletonRoleProviderFactoryInputs memory providerInputs = SingletonRoleProviderFactoryInputs({
            lender: predictedManager, salt: keccak256("tranche-singleton-provider")
        });
        NameAndProviderInputs memory accessInputs;
        accessInputs.name = "TrancheManager singleton";
        accessInputs.roleProviderFactory = address(providerFactory);
        accessInputs.newProviderInputs = new CreateProviderInputs[](1);
        accessInputs.newProviderInputs[0] =
            CreateProviderInputs({timeToLive: 0, providerFactoryCalldata: abi.encode(providerInputs)});
        return abi.encode(SingletonOpenTermHooksInputs({accessControlInputs: accessInputs, lender: predictedManager}));
    }

    function _marketInputs() internal view returns (DeployMarketInputs memory inputs) {
        inputs = DeployMarketInputs({
            asset: address(asset),
            namePrefix: "Wildcat ",
            symbolPrefix: "WC",
            maxTotalSupply: 1_000_000e18,
            annualInterestBips: 1000,
            delinquencyFeeBips: 0,
            withdrawalBatchDuration: 14 days,
            reserveRatioBips: 1000,
            delinquencyGracePeriod: 28 days,
            hooks: encodeHooksConfig({
                hooksAddress: address(0),
                useOnDeposit: true,
                useOnQueueWithdrawal: false,
                useOnExecuteWithdrawal: false,
                useOnTransfer: true,
                useOnBorrow: false,
                useOnRepay: false,
                useOnCloseMarket: true,
                useOnNukeFromOrbit: false,
                useOnSetMaxTotalSupply: false,
                useOnSetAnnualInterestAndReserveRatioBips: false,
                useOnSetProtocolFeeBips: false
            })
        });
    }
}
