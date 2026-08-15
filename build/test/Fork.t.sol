// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";

import {TrancheFactory} from "../src/TrancheFactory.sol";
import {TrancheManager} from "../src/TrancheManager.sol";
import {TrancheToken} from "../src/TrancheToken.sol";
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
import {LibString} from "../lib/solady/src/utils/LibString.sol";

contract ForkChainalysisList {
    mapping(address => bool) internal sanctioned;

    function setSanctioned(address account, bool value) external {
        sanctioned[account] = value;
    }

    function isSanctioned(address account) external view returns (bool) {
        return sanctioned[account];
    }
}

contract ForkEnterGate {
    mapping(address => bool) internal allowed;

    function setAllowed(address account, bool value) external {
        allowed[account] = value;
    }

    function canIncreaseCredit(address account) external view returns (bool) {
        return allowed[account];
    }
}

contract ForkAsset {
    string public constant name = "Fork Asset";
    string public constant symbol = "FORK";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

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
    ForkChainalysisList internal chainalysisList;
    WildcatSanctionsSentinel internal sentinel;
    Wildcat4626WrapperFactory internal wrapperFactory;
    HooksFactory internal hooksFactory;
    SingletonRoleProviderFactory internal providerFactory;
    TrancheFactory internal trancheFactory;
    address internal singletonHooksTemplate;

    struct ExitRequests {
        uint256 firstJunior;
        uint256 senior;
        uint256 finalJunior;
        uint32 expiry;
    }

    struct Facility {
        WildcatMarket market;
        TrancheManager manager;
        address marketAddress;
        address managerAddress;
        address wrapperAddress;
    }

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
                defaultPenaltyWindow: 28 days,
                terminalRecipient: address(this)
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
        string memory marketId = LibString.toHexStringNoPrefix(marketAddress);
        assertEq(manager.senior().name(), string.concat("Wildcat Senior Tranche WCFORK ", marketId), "senior facility name");
        assertEq(manager.senior().symbol(), string.concat("sr-WCFORK-", marketId), "senior facility symbol");
        assertEq(manager.junior().name(), string.concat("Wildcat Junior Tranche WCFORK ", marketId), "junior facility name");
        assertEq(manager.junior().symbol(), string.concat("jr-WCFORK-", marketId), "junior facility symbol");

        _exerciseExitLifecycle(manager, market, asset, managerAddress, wrapperAddress);
    }

    function test_fork_delinquencyMarksAndCures() public {
        Facility memory facility = _deployFacility();
        asset.mint(address(this), 400e18);
        asset.approve(facility.managerAddress, 400e18);
        facility.manager.depositJunior(100e18, address(this));
        facility.manager.depositSenior(300e18, address(this));

        facility.market.borrow(300e18);
        facility.manager.requestRedeem(false, 25e18);
        facility.manager.requestRedeem(true, 250e18);

        uint256 mark = facility.manager.markedAssets();
        assertEq(mark, 125e18, "requests reduce the aggregate mark by backed face");
        assertTrue(facility.market.currentState().isDelinquent, "unpaid batch makes market delinquent");

        vm.warp(block.timestamp + 1 days);
        uint256 live = Wildcat4626Wrapper(facility.wrapperAddress).convertToAssets(
            Wildcat4626Wrapper(facility.wrapperAddress).balanceOf(facility.managerAddress)
        );
        assertGt(live, mark, "retained wrapper position accrues live value");
        facility.manager.accrue();
        assertEq(facility.manager.markedAssets(), mark, "delinquent checkpoint preserves healthy mark");
        assertEq(facility.manager.realisedValue(), mark, "delinquent upside remains excluded from the mark");
        vm.expectRevert(bytes("DELINQUENT"));
        facility.manager.depositJunior(1e18, address(this));

        asset.approve(facility.marketAddress, 300e18);
        facility.market.repay(300e18);
        assertFalse(facility.market.currentState().isDelinquent, "repayment cures liquidity shortfall");
        facility.manager.accrue();
        assertEq(facility.manager.markedAssets(), facility.manager.realisedValue(), "cure refreshes the live mark");
        assertGt(facility.manager.markedAssets(), mark, "cure recognises retained live value");

    }

    function test_fork_delinquencyThresholdWindDown() public {
        Facility memory facility = _deployFacility();
        asset.mint(address(this), 400e18);
        asset.approve(facility.managerAddress, 400e18);
        facility.manager.depositJunior(100e18, address(this));
        facility.manager.depositSenior(300e18, address(this));
        facility.market.borrow(300e18);
        facility.manager.requestRedeem(false, 25e18);
        facility.manager.requestRedeem(true, 250e18);
        assertTrue(facility.market.currentState().isDelinquent, "unpaid batch starts delinquency clock");

        vm.warp(block.timestamp + facility.manager.delinquencyGracePeriod() + facility.manager.defaultPenaltyWindow());
        facility.manager.accrue();
        assertEq(uint256(facility.manager.status()), uint256(TrancheManager.Status.WindDown), "threshold enters wind-down");
        uint256 frozenOwed = facility.manager.seniorOwedAtDefault();

        asset.approve(facility.marketAddress, 300e18);
        facility.market.repay(300e18);
        assertFalse(facility.market.currentState().isDelinquent, "repayment cures market after wind-down");
        facility.manager.accrue();
        assertEq(uint256(facility.manager.status()), uint256(TrancheManager.Status.WindDown), "cure cannot reactivate manager");
        assertEq(facility.manager.seniorOwed(), frozenOwed, "cure cannot restart senior accrual");
        vm.warp(block.timestamp + 365 days);
        facility.manager.accrue();
        assertEq(facility.manager.seniorOwed(), frozenOwed, "senior accrual stops after wind-down");
        vm.expectRevert(bytes("NOT_ACTIVE"));
        facility.manager.depositJunior(1e18, address(this));
    }

    function test_fork_terminalFullWithdrawalLeavesNoScaledCustody() public {
        Facility memory facility = _deployFacility();
        asset.mint(address(this), 400e18);
        asset.approve(facility.managerAddress, 400e18);
        facility.manager.depositJunior(100e18, address(this));
        facility.manager.depositSenior(300e18, address(this));

        // The real market's scale factor is now non-integral. A final exit must consume the
        // manager's exact scaled balance rather than queueing its rounded `balanceOf` display.
        vm.warp(block.timestamp + 1 days);
        facility.manager.accrue();
        facility.manager.requestRedeem(true, facility.manager.senior().balanceOf(address(this)));
        facility.manager.requestRedeem(false, facility.manager.junior().balanceOf(address(this)));

        assertTrue(facility.manager.terminalised(), "final share burn terminalises facility");
        assertEq(
            Wildcat4626Wrapper(facility.wrapperAddress).balanceOf(facility.managerAddress),
            0,
            "no wrapper shares remain after terminal queue"
        );
        assertEq(facility.market.scaledBalanceOf(facility.managerAddress), 0, "no scaled market custody remains");
    }

    function test_fork_entryGateControlsAcquisitionButNotExit() public {
        ForkEnterGate seniorGate = new ForkEnterGate();
        ForkEnterGate juniorGate = new ForkEnterGate();
        Facility memory facility = _deployFacility(address(seniorGate), address(juniorGate));
        asset.mint(address(this), 400e18);
        asset.approve(facility.managerAddress, 400e18);

        vm.expectRevert(bytes("ENTRY_NOT_ALLOWED"));
        facility.manager.depositJunior(100e18, address(this));

        seniorGate.setAllowed(address(this), true);
        juniorGate.setAllowed(address(this), true);
        facility.manager.depositJunior(100e18, address(this));
        facility.manager.depositSenior(300e18, address(this));

        address receiver = address(0xBEEF);
        TrancheToken junior = facility.manager.junior();
        vm.expectRevert(bytes("ENTRY_NOT_ALLOWED"));
        junior.transfer(receiver, 1e18);
        juniorGate.setAllowed(receiver, true);
        junior.transfer(receiver, 1e18);

        seniorGate.setAllowed(address(this), false);
        uint256 id = facility.manager.requestRedeem(true, facility.manager.senior().balanceOf(address(this)));
        assertEq(id, 0, "entry policy cannot block an existing holder exit");
    }

    function test_fork_sanctionedHolderExitsToCanonicalEscrow() public {
        Facility memory facility = _deployFacility();
        address holder = address(0xA11CE);
        asset.mint(holder, 100e18);
        vm.startPrank(holder);
        asset.approve(facility.managerAddress, 100e18);
        facility.manager.depositJunior(100e18, holder);
        vm.stopPrank();

        chainalysisList.setSanctioned(holder, true);
        uint256 holderShares = facility.manager.junior().balanceOf(holder);
        vm.prank(holder);
        uint256 id = facility.manager.requestRedeem(false, holderShares);
        (,,,, uint32 expiry) = facility.manager.requests(id);
        vm.warp(uint256(expiry) + 1);
        facility.manager.pokeRecovery(expiry);

        address escrow = sentinel.getEscrowAddress(facility.market.borrowerPrincipal(), holder, address(asset));
        facility.manager.claim(id);
        assertEq(asset.balanceOf(escrow), 100e18, "sanction redirects payment without changing claim");
    }

    function test_fork_managerSanctionDefersAuthenticatedRecovery() public {
        Facility memory facility = _deployFacility();
        asset.mint(address(this), 100e18);
        asset.approve(facility.managerAddress, 100e18);
        facility.manager.depositJunior(100e18, address(this));
        uint256 id = facility.manager.requestRedeem(false, facility.manager.junior().balanceOf(address(this)));
        (,,,, uint32 expiry) = facility.manager.requests(id);

        chainalysisList.setSanctioned(facility.managerAddress, true);
        vm.warp(uint256(expiry) + 1);
        vm.expectRevert(TrancheManager.ManagerSanctioned.selector);
        facility.market.executeWithdrawal(facility.managerAddress, expiry);
        assertEq(facility.manager.recoveredUSDC(), 0, "sanction cannot create phantom recovery");

        chainalysisList.setSanctioned(facility.managerAddress, false);
        facility.manager.pokeRecovery(expiry);
        assertEq(facility.manager.claimable(id), 100e18, "cleared manager receives tagged recovery");
    }

    function _deployFacility() internal returns (Facility memory facility) {
        return _deployFacility(address(0), address(0));
    }

    function _deployFacility(address seniorGate, address juniorGate) internal returns (Facility memory facility) {
        _deployProtocolStack();
        address predictedManager = trancheFactory.computeManagerAddress(address(this), MANAGER_SALT);
        bytes memory hooksConstructorArgs = _singletonConstructorArgs(predictedManager);
        DeployMarketInputs memory marketInputs = _marketInputs();
        bytes32 marketSalt = bytes32((uint256(uint160(address(this))) << 96) | uint256(14));
        address hooksAddress;
        (facility.marketAddress, hooksAddress) = hooksFactory.deployMarketAndHooks(
            singletonHooksTemplate,
            hooksConstructorArgs,
            marketInputs,
            abi.encode(uint128(0), false),
            marketSalt,
            address(0),
            0
        );
        facility.wrapperAddress = wrapperFactory.createWrapper(facility.marketAddress);
        RoleProvider[] memory providers = SingletonOpenTermHooks(hooksAddress).getPullProviders();
        facility.managerAddress = trancheFactory.deployTranches(
            MANAGER_SALT,
            TrancheFactory.DeployParams({
                market: facility.marketAddress,
                wrapper: facility.wrapperAddress,
                hooks: hooksAddress,
                singletonProvider: providers[0].providerAddress(),
                sentinel: address(sentinel),
                borrower: address(this),
                seniorGate: seniorGate,
                juniorGate: juniorGate,
                seniorRateBips: 800,
                minJuniorBips: 2000,
                defaultPenaltyWindow: 28 days,
                terminalRecipient: address(this)
            })
        );
        facility.market = WildcatMarket(facility.marketAddress);
        facility.manager = TrancheManager(facility.managerAddress);
    }

    function _exerciseExitLifecycle(
        TrancheManager manager,
        WildcatMarket market,
        ForkAsset asset,
        address managerAddress,
        address wrapperAddress
    ) internal {
        asset.mint(address(this), 400e18);
        asset.approve(managerAddress, 400e18);
        uint256 juniorShares = manager.depositJunior(100e18, address(this));
        uint256 seniorShares = manager.depositSenior(300e18, address(this));

        assertEq(juniorShares, 100e18, "junior shares minted");
        assertEq(seniorShares, 300e18, "senior shares minted");
        assertEq(manager.junior().balanceOf(address(this)), 100e18, "junior receiver balance");
        assertEq(manager.senior().balanceOf(address(this)), 300e18, "senior receiver balance");
        assertEq(manager.junior().totalSupply(), 100e18, "junior supply");
        assertEq(manager.senior().totalSupply(), 300e18, "senior supply");
        assertEq(manager.seniorPrincipal(), 300e18, "senior principal");
        assertEq(manager.seniorOwed(), 300e18, "senior owed");
        assertEq(manager.markedAssets(), 400e18, "marked assets");
        assertEq(manager.realisedValue(), 400e18, "realised value");
        assertEq(manager.juniorValue(), 100e18, "junior value");
        assertEq(manager.seniorValue(), 300e18, "senior value");
        assertEq(asset.balanceOf(managerAddress), 0, "no idle base asset");
        assertEq(market.balanceOf(managerAddress), 0, "no idle market tokens");
        assertEq(market.balanceOf(wrapperAddress), 400e18, "wrapper market balance");
        assertEq(
            Wildcat4626Wrapper(wrapperAddress).balanceOf(managerAddress),
            Wildcat4626Wrapper(wrapperAddress).totalSupply(),
            "manager owns wrapper supply"
        );
        assertEq(asset.allowance(managerAddress, address(market)), 0, "market approval cleared");
        assertEq(market.allowance(managerAddress, wrapperAddress), 0, "wrapper approval cleared");
        assertEq(manager.seniorValue() + manager.juniorValue(), manager.realisedValue(), "waterfall conserves value");

        market.borrow(100e18);
        assertEq(asset.balanceOf(address(this)), 100e18, "borrower creates an exit shortfall");

        ExitRequests memory requests = _queuePriorityExit(manager, seniorShares, juniorShares);
        assertEq(manager.claimable(requests.senior), 0, "senior not claimable before recovery");
        assertEq(manager.claimable(requests.firstJunior), 0, "first junior request not claimable before recovery");
        assertEq(manager.claimable(requests.finalJunior), 0, "final junior request not claimable before recovery");

        address keeper = address(0xBEEF);
        vm.warp(uint256(requests.expiry) + 1);
        assertTrue(market.currentState().isDelinquent, "shortfall makes the market delinquent");
        assertEq(market.getAvailableWithdrawalAmount(managerAddress, requests.expiry), 300e18, "market pays available liquidity");
        vm.prank(keeper);
        manager.pokeRecovery(requests.expiry);

        assertEq(manager.recoveredUSDC(), 300e18, "first recovery observed");
        assertEq(manager.allocatableUSDC(), 300e18, "first recovery allocated");
        assertEq(manager.recoveryObservedByExpiry(requests.expiry), 300e18, "expiry receipt recorded");
        assertEq(manager.faceCreditedByExpiry(requests.expiry), 300e18, "expiry face credited once");
        assertEq(manager.recoverySurplus(), 0, "no unattributed recovery");
        assertEq(manager.claimable(requests.senior), 300e18, "senior recovery is allocated first");
        assertEq(manager.claimable(requests.firstJunior), 0, "earlier junior request waits behind senior");
        assertEq(manager.claimable(requests.finalJunior), 0, "later junior request waits behind senior");
        assertEq(asset.balanceOf(managerAddress), 300e18, "first recovery reaches manager");
        vm.prank(keeper);
        assertEq(manager.claim(requests.senior), 300e18, "senior claim paid");

        assertEq(asset.balanceOf(address(this)), 400e18, "recorded senior owner receives payment");
        assertEq(asset.balanceOf(keeper), 0, "keeper cannot redirect senior claim");
        assertEq(manager.totalClaimedOut(), 300e18, "senior claim recorded");

        asset.approve(address(market), 100e18);
        market.repayAndProcessUnpaidWithdrawalBatches(100e18, 1);
        assertEq(market.getAvailableWithdrawalAmount(managerAddress, requests.expiry), 100e18, "repaid liquidity is reserved for the batch");
        vm.prank(keeper);
        manager.pokeRecovery(requests.expiry);

        assertEq(manager.recoveredUSDC(), 400e18, "total recovery observed");
        assertEq(manager.allocatableUSDC(), 400e18, "total recovery allocated");
        assertEq(manager.recoveryObservedByExpiry(requests.expiry), 400e18, "full expiry receipt recorded");
        assertEq(manager.faceCreditedByExpiry(requests.expiry), 400e18, "full expiry face credited once");
        assertEq(manager.claimable(requests.firstJunior), 25e18, "first junior request receives later recovery");
        assertEq(manager.claimable(requests.finalJunior), 75e18, "second junior request receives later recovery");
        assertTrue(market.currentState().isDelinquent, "accrued interest remains in the market batch");
        assertEq(asset.balanceOf(managerAddress), 100e18, "second recovery reaches manager");
        vm.prank(keeper);
        assertEq(manager.claim(requests.firstJunior), 25e18, "first junior claim paid");
        vm.prank(keeper);
        assertEq(manager.claim(requests.finalJunior), 75e18, "second junior claim paid");
        assertEq(asset.balanceOf(address(this)), 400e18, "claimant receives settled base asset");
        assertEq(asset.balanceOf(keeper), 0, "keeper cannot redirect junior claim");
        assertEq(asset.balanceOf(managerAddress), 0, "no base asset retained after claims");
        assertEq(manager.totalClaimedOut(), 400e18, "all claims accounted");
    }

    function _queuePriorityExit(TrancheManager manager, uint256 seniorShares, uint256 juniorShares)
        internal
        returns (ExitRequests memory requests)
    {
        // Start with junior deliberately: the initial shortfall must still fill the later senior
        // request before either junior request can claim.
        requests.firstJunior = manager.requestRedeem(false, 25e18);
        requests.senior = manager.requestRedeem(true, seniorShares);
        requests.finalJunior = manager.requestRedeem(false, juniorShares - 25e18);

        (,, uint128 firstJuniorFace,, uint32 firstJuniorExpiry) = manager.requests(requests.firstJunior);
        (,, uint128 seniorFace,, uint32 seniorExpiry) = manager.requests(requests.senior);
        (,, uint128 finalJuniorFace,, uint32 finalJuniorExpiry) = manager.requests(requests.finalJunior);

        assertEq(firstJuniorFace, 25e18, "first junior request face");
        assertEq(seniorFace, 300e18, "senior request face");
        assertEq(finalJuniorFace, 75e18, "final junior request face");
        assertEq(firstJuniorExpiry, seniorExpiry, "first junior and senior share market batch");
        assertEq(seniorExpiry, finalJuniorExpiry, "senior and final junior share market batch");
        assertEq(manager.faceQueuedByExpiry(seniorExpiry), 400e18, "expiry records all request faces");
        assertEq(manager.senior().totalSupply(), 0, "senior shares burned for exit");
        assertEq(manager.junior().totalSupply(), 0, "junior shares burned for exit");
        requests.expiry = seniorExpiry;
    }

    function _deployProtocolStack() internal {
        asset = new ForkAsset();
        archController = new WildcatArchController();
        borrowerIdentityRegistry = new WildcatBorrowerIdentityRegistry(address(archController));
        chainalysisList = new ForkChainalysisList();
        sentinel = new WildcatSanctionsSentinel(address(archController), address(chainalysisList));
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
            delinquencyFeeBips: 1,
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
