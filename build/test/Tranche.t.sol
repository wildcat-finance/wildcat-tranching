// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {TrancheManager} from "../src/TrancheManager.sol";
import {TrancheFactory} from "../src/TrancheFactory.sol";
import {TrancheToken} from "../src/TrancheToken.sol";
import {
    MockERC20,
    MockMarket,
    MockWrapper,
    MockWrapperFactory,
    MockHooksFactory,
    MockSingletonProvider,
    MockSingletonHooks,
    MockUnpinnedHooks,
    MockSentinel,
    MockEnterGate,
    MockArch
} from "./Mocks.sol";

contract TrancheTest is Test {
    MockERC20 usdc;
    MockMarket market;
    MockWrapper wrapper;
    MockWrapperFactory wrapperFactory;
    MockHooksFactory hooksFactory;
    MockSingletonProvider provider;
    MockSingletonHooks hooks;
    MockSentinel sentinel;
    MockEnterGate seniorGate;
    MockEnterGate juniorGate;
    MockArch arch;
    TrancheFactory factory;
    TrancheManager manager;
    TrancheToken senior;
    TrancheToken junior;

    address srLP = address(0x5E11);
    address jrLP = address(0x10110);
    address borrower;
    bytes32 salt = keccak256("fixture");
    address hookTemplate;

    uint256 constant MIN_JUNIOR_BIPS = 2000;
    uint256 constant SENIOR_RATE_BIPS = 1000;
    uint256 constant WINDOW = 90 days;

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC");
        wrapperFactory = new MockWrapperFactory();
        arch = new MockArch();
        borrower = address(this);
        hookTemplate = address(new MockSingletonHooks(address(1)));
        hooksFactory = new MockHooksFactory();
        factory = new TrancheFactory(address(arch), address(wrapperFactory), hookTemplate);

        address predicted = factory.computeManagerAddress(address(this), salt);
        provider = new MockSingletonProvider(predicted);
        hooks = new MockSingletonHooks(address(provider));
        sentinel = new MockSentinel();
        seniorGate = new MockEnterGate();
        juniorGate = new MockEnterGate();
        market = new MockMarket(address(usdc), address(wrapperFactory), address(hooks), borrower, address(sentinel));
        wrapper = new MockWrapper(address(market));

        market.setFactory(address(hooksFactory));
        hooksFactory.setTemplate(address(hooks), hookTemplate);
        hooks.setMarket(address(market), false);
        market.setRegisteredWrapper(address(wrapper));
        wrapperFactory.setWrapper(address(market), address(wrapper));
        arch.setRegistered(address(market), true);
        seniorGate.setAllowed(srLP, true);
        juniorGate.setAllowed(jrLP, true);

        address deployed =
            factory.deployTranches(salt, _params(address(market), address(wrapper), address(hooks), address(provider)));
        assertEq(deployed, predicted, "CREATE2 prediction");
        manager = TrancheManager(deployed);
        senior = manager.senior();
        junior = manager.junior();

        usdc.mint(srLP, 10_000_000e18);
        usdc.mint(jrLP, 10_000_000e18);

        _depositJunior(jrLP, 100e18);
        _depositSenior(srLP, 300e18);
    }

    function _params(address market_, address wrapper_, address hooks_, address provider_)
        internal
        view
        returns (TrancheFactory.DeployParams memory p)
    {
        p = TrancheFactory.DeployParams({
            market: market_,
            wrapper: wrapper_,
            hooks: hooks_,
            singletonProvider: provider_,
            sentinel: address(sentinel),
            borrower: borrower,
            seniorGate: address(seniorGate),
            juniorGate: address(juniorGate),
            seniorRateBips: SENIOR_RATE_BIPS,
            minJuniorBips: MIN_JUNIOR_BIPS,
            defaultPenaltyWindow: WINDOW
        });
    }

    function _depositSenior(address who, uint256 assets) internal returns (uint256) {
        vm.startPrank(who);
        usdc.approve(address(manager), assets);
        uint256 shares = manager.depositSenior(assets, who);
        vm.stopPrank();
        return shares;
    }

    function _depositJunior(address who, uint256 assets) internal returns (uint256) {
        vm.startPrank(who);
        usdc.approve(address(manager), assets);
        uint256 shares = manager.depositJunior(assets, who);
        vm.stopPrank();
        return shares;
    }

    function _assertConservation() internal view {
        (uint256 seniorValue, uint256 juniorValue) = manager.trancheValues();
        assertEq(seniorValue + juniorValue, manager.realisedValue(), "waterfall conservation");
    }

    function test_DeploymentBindsCanonicalSingletonStack() public view {
        assertEq(factory.managerForMarket(address(market)), address(manager));
        assertEq(address(manager.factory()), address(factory));
        assertEq(address(manager.market()), address(market));
        assertEq(address(manager.underlyingVault()), address(wrapper));
        assertEq(address(manager.baseAsset()), address(usdc));
        assertTrue(manager.initialized());
    }

    function test_Create2PredictionIsNamespacedByCaller() public view {
        assertTrue(factory.computeManagerAddress(address(this), salt) != factory.computeManagerAddress(srLP, salt));
        assertEq(factory.managerInitCodeHash(), factory.managerDeployer().initCodeHash());
    }

    function test_ManagerCannotBeReinitialized() public {
        vm.prank(address(factory));
        vm.expectRevert(bytes("ALREADY_INITIALIZED"));
        manager.initialize(
            TrancheManager.Params({
                underlyingVault: address(wrapper),
                sentinel: address(sentinel),
                seniorGate: address(seniorGate),
                juniorGate: address(juniorGate),
                seniorRateBips: SENIOR_RATE_BIPS,
                minJuniorBips: MIN_JUNIOR_BIPS,
                defaultPenaltyWindow: WINDOW
            })
        );
    }

    function test_FactoryRejectsDeploymentByNonBorrower() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(TrancheFactory.BorrowerMismatch.selector);
        factory.deployTranches(
            bytes32(uint256(123)), _params(address(market), address(wrapper), address(hooks), address(provider))
        );
    }

    function test_DepositsBaseAssetAndKeepsCustodyAirtight() public view {
        assertEq(usdc.balanceOf(address(manager)), 0, "no idle base asset");
        assertEq(market.balanceOf(address(manager)), 0, "manager wraps all market tokens");
        assertEq(market.balanceOf(address(wrapper)), 400e18, "wrapper holds market tokens");
        assertEq(wrapper.balanceOf(address(manager)), wrapper.totalSupply(), "manager holds every wrapper share");
        assertEq(senior.asset(), address(usdc), "tranche view asset is base asset");
        assertEq(junior.asset(), address(usdc), "tranche view asset is base asset");
    }

    function test_SanctionsScopeKeepsRegisteredPrincipalAfterBorrowerRotation() public {
        address nextBorrower = address(0xB0B);
        market.setBorrower(nextBorrower);
        vm.expectCall(address(sentinel), abi.encodeCall(MockSentinel.isSanctioned, (borrower, srLP)));
        _depositSenior(srLP, 1e18);
    }

    function test_DepositSplitAndSubordination() public view {
        (uint256 seniorValue, uint256 juniorValue) = manager.trancheValues();
        assertEq(seniorValue, 300e18);
        assertEq(juniorValue, 100e18);
        assertEq(manager.seniorOwed(), 300e18);
        _assertConservation();
    }

    function test_SeniorDepositRevertsAboveLeverage() public {
        _depositSenior(srLP, 100e18);
        vm.startPrank(srLP);
        usdc.approve(address(manager), 1e18);
        vm.expectRevert(bytes("SUBORDINATION"));
        manager.depositSenior(1e18, srLP);
        vm.stopPrank();
    }

    function test_FixedSeniorRateDoesNotRetroactivelyTrackMarketAPR() public {
        market.setAnnualInterestBips(4000);
        assertEq(manager.currentSeniorRateBips(), SENIOR_RATE_BIPS);
        vm.warp(block.timestamp + 365 days);
        manager.accrue();
        (uint256 seniorValue, uint256 juniorValue) = manager.trancheValues();
        assertApproxEqAbs(seniorValue, 330e18, 1e15);
        assertApproxEqAbs(juniorValue, 70e18, 1e15);
    }

    function test_LossHitsJuniorFirst() public {
        wrapper.setPrice(0.8e18);
        (uint256 seniorValue, uint256 juniorValue) = manager.trancheValues();
        assertEq(seniorValue, 300e18);
        assertEq(juniorValue, 20e18);
        wrapper.setPrice(0.5e18);
        (seniorValue, juniorValue) = manager.trancheValues();
        assertEq(juniorValue, 0);
        assertEq(seniorValue, 200e18);
        _assertConservation();
    }

    function test_DefaultFreezesAccrual() public {
        market.setTimeDelinquent(uint32(10 days + WINDOW));
        manager.checkDefault();
        uint256 frozen = manager.seniorOwed();
        assertEq(uint256(manager.status()), uint256(TrancheManager.Status.WindDown));
        vm.warp(block.timestamp + 365 days);
        manager.accrue();
        assertEq(manager.seniorOwed(), frozen);
    }

    function test_ClosedMarketTriggersObjectiveWindDown() public {
        market.setClosed(true);
        manager.accrue();
        assertEq(uint256(manager.status()), uint256(TrancheManager.Status.WindDown));
        assertEq(manager.seniorOwedAtDefault(), manager.seniorOwed());
    }

    function test_DelinquencyRejectsDepositsAndCureReopensEntry() public {
        market.setDelinquent(true);
        vm.startPrank(srLP);
        usdc.approve(address(manager), 1e18);
        vm.expectRevert(bytes("DELINQUENT"));
        manager.depositSenior(1e18, srLP);
        vm.stopPrank();

        market.setDelinquent(false);
        _depositSenior(srLP, 1e18);
    }

    function test_EntryGateControlsAcquisitionButCannotBlockExit() public {
        address denied = address(0xD3111ED);
        usdc.mint(denied, 1e18);

        vm.startPrank(denied);
        usdc.approve(address(manager), 1e18);
        vm.expectRevert(bytes("ENTRY_NOT_ALLOWED"));
        manager.depositSenior(1e18, denied);
        vm.stopPrank();

        vm.prank(srLP);
        vm.expectRevert(bytes("ENTRY_NOT_ALLOWED"));
        senior.transfer(denied, 1e18);

        seniorGate.setAllowed(srLP, false);
        seniorGate.setShouldRevert(true);
        uint256 balanceBefore = usdc.balanceOf(srLP);
        vm.prank(srLP);
        uint256 id = manager.requestRedeem(true, 1e18);
        (,, uint128 face,, uint32 expiry) = manager.requests(id);
        vm.warp(uint256(expiry) + 1);
        manager.pokeRecovery(expiry);
        manager.claim(id);
        assertEq(usdc.balanceOf(srLP), balanceBefore + uint256(face));
    }

    function test_RevertingEntryGateFailsClosed() public {
        seniorGate.setShouldRevert(true);
        vm.startPrank(srLP);
        usdc.approve(address(manager), 1e18);
        vm.expectRevert(bytes("GATE_REVERT"));
        manager.depositSenior(1e18, srLP);
        vm.stopPrank();
    }

    function test_ZeroEntryGatesAreOpen() public {
        TrancheManager openManager = new TrancheManager(address(this));
        openManager.initialize(
            TrancheManager.Params({
                underlyingVault: address(wrapper),
                sentinel: address(sentinel),
                seniorGate: address(0),
                juniorGate: address(0),
                seniorRateBips: SENIOR_RATE_BIPS,
                minJuniorBips: MIN_JUNIOR_BIPS,
                defaultPenaltyWindow: WINDOW
            })
        );
        assertEq(address(openManager.seniorGate()), address(0));
        assertEq(address(openManager.juniorGate()), address(0));
    }

    function test_EntryGateMustBeAContract() public {
        TrancheManager badManager = new TrancheManager(address(this));
        vm.expectRevert(bytes("BAD_SENIOR_GATE"));
        badManager.initialize(
            TrancheManager.Params({
                underlyingVault: address(wrapper),
                sentinel: address(sentinel),
                seniorGate: address(0xBEEF),
                juniorGate: address(0),
                seniorRateBips: SENIOR_RATE_BIPS,
                minJuniorBips: MIN_JUNIOR_BIPS,
                defaultPenaltyWindow: WINDOW
            })
        );
    }

    function test_ManagerHasNoControlPlaneSelectors() public {
        bytes[4] memory calls = [
            abi.encodeWithSignature("setDepositsPaused(bool)", true),
            abi.encodeWithSignature("proposeSeniorRateBips(uint256)", 500),
            abi.encodeWithSignature("declareDefault()"),
            abi.encodeWithSignature("proposeGovernance(address)", address(this))
        ];
        for (uint256 i; i < calls.length; ++i) {
            (bool ok,) = address(manager).call(calls[i]);
            assertFalse(ok);
        }
    }

    function test_AsyncRedemptionSeniorFirstOnShortfall() public {
        uint256 seniorShares = senior.balanceOf(srLP);
        vm.prank(srLP);
        uint256 seniorId = manager.requestRedeem(true, seniorShares);
        uint256 juniorShares = junior.balanceOf(jrLP);
        vm.prank(jrLP);
        uint256 juniorId = manager.requestRedeem(false, juniorShares);
        uint32 expiry = uint32(block.timestamp + market.withdrawalBatchDuration());

        vm.prank(address(market));
        usdc.transfer(address(0xBEEF), 100e18);
        vm.warp(expiry + 1);
        manager.pokeRecovery(expiry);
        assertEq(manager.claimable(seniorId), 300e18);
        assertEq(manager.claimable(juniorId), 0);

        vm.prank(srLP);
        manager.claim(seniorId);
        usdc.mint(address(market), 100e18);
        manager.pokeRecovery(expiry);
        assertEq(manager.claimable(juniorId), 100e18);
    }

    function test_SanctionedClaimGoesToEscrow() public {
        uint256 seniorShares = senior.balanceOf(srLP);
        vm.prank(srLP);
        uint256 id = manager.requestRedeem(true, seniorShares);
        uint32 expiry = uint32(block.timestamp + market.withdrawalBatchDuration());
        vm.warp(expiry + 1);
        manager.pokeRecovery(expiry);
        sentinel.setSanctioned(srLP, true);
        manager.claim(id);
        address escrow = address(uint160(uint256(keccak256(abi.encodePacked("escrow", srLP)))));
        assertEq(usdc.balanceOf(escrow), 300e18);
    }

    function test_FactoryRejectsTransferDisabledMarket() public {
        bytes32 otherSalt = keccak256("disabled");
        address predicted = factory.computeManagerAddress(address(this), otherSalt);
        MockSingletonProvider otherProvider = new MockSingletonProvider(predicted);
        MockSingletonHooks otherHooks = new MockSingletonHooks(address(otherProvider));
        MockMarket otherMarket =
            new MockMarket(address(usdc), address(wrapperFactory), address(otherHooks), borrower, address(sentinel));
        MockWrapper otherWrapper = new MockWrapper(address(otherMarket));
        otherMarket.setFactory(address(hooksFactory));
        hooksFactory.setTemplate(address(otherHooks), hookTemplate);
        otherHooks.setMarket(address(otherMarket), true);
        otherMarket.setRegisteredWrapper(address(otherWrapper));
        wrapperFactory.setWrapper(address(otherMarket), address(otherWrapper));
        arch.setRegistered(address(otherMarket), true);

        vm.expectRevert(TrancheFactory.HookConfigurationInvalid.selector);
        factory.deployTranches(
            otherSalt, _params(address(otherMarket), address(otherWrapper), address(otherHooks), address(otherProvider))
        );
    }

    function test_FactoryRejectsWrongSingletonLender() public {
        bytes32 otherSalt = keccak256("wrong-lender");
        MockSingletonProvider otherProvider = new MockSingletonProvider(address(0xBAD));
        MockSingletonHooks otherHooks = new MockSingletonHooks(address(otherProvider));
        MockMarket otherMarket =
            new MockMarket(address(usdc), address(wrapperFactory), address(otherHooks), borrower, address(sentinel));
        MockWrapper otherWrapper = new MockWrapper(address(otherMarket));
        otherMarket.setFactory(address(hooksFactory));
        hooksFactory.setTemplate(address(otherHooks), hookTemplate);
        otherHooks.setMarket(address(otherMarket), false);
        otherMarket.setRegisteredWrapper(address(otherWrapper));
        wrapperFactory.setWrapper(address(otherMarket), address(otherWrapper));
        arch.setRegistered(address(otherMarket), true);

        vm.expectRevert(TrancheFactory.SingletonLenderMismatch.selector);
        factory.deployTranches(
            otherSalt, _params(address(otherMarket), address(otherWrapper), address(otherHooks), address(otherProvider))
        );
    }

    function test_FactoryRejectsUnpinnedHookTemplate() public {
        bytes32 otherSalt = keccak256("unpinned-hook");
        address predicted = factory.computeManagerAddress(address(this), otherSalt);
        MockSingletonProvider otherProvider = new MockSingletonProvider(predicted);
        MockUnpinnedHooks otherHooks = new MockUnpinnedHooks(address(otherProvider));
        MockMarket otherMarket =
            new MockMarket(address(usdc), address(wrapperFactory), address(otherHooks), borrower, address(sentinel));
        MockWrapper otherWrapper = new MockWrapper(address(otherMarket));
        otherMarket.setFactory(address(hooksFactory));
        hooksFactory.setTemplate(address(otherHooks), address(otherHooks));
        otherHooks.setMarket(address(otherMarket), false);
        otherMarket.setRegisteredWrapper(address(otherWrapper));
        wrapperFactory.setWrapper(address(otherMarket), address(otherWrapper));
        arch.setRegistered(address(otherMarket), true);

        vm.expectRevert(TrancheFactory.HookTemplateMismatch.selector);
        factory.deployTranches(
            otherSalt, _params(address(otherMarket), address(otherWrapper), address(otherHooks), address(otherProvider))
        );
    }
}
