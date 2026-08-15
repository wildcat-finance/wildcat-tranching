// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {TrancheManager} from "../src/TrancheManager.sol";
import {TrancheFactory} from "../src/TrancheFactory.sol";
import {TrancheToken} from "../src/TrancheToken.sol";
import {WaterfallMath} from "../src/libraries/WaterfallMath.sol";
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
            defaultPenaltyWindow: WINDOW,
            terminalRecipient: borrower
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
                defaultPenaltyWindow: WINDOW,
                terminalRecipient: borrower
            })
        );
    }

    function test_ManagerRejectsAssetsBelowSixDecimals() public {
        TrancheManager candidate = new TrancheManager(address(this));
        market.setDecimals(5);
        vm.expectRevert(bytes("BAD_DECIMALS"));
        candidate.initialize(
            TrancheManager.Params({
                underlyingVault: address(wrapper),
                sentinel: address(sentinel),
                seniorGate: address(0),
                juniorGate: address(0),
                seniorRateBips: SENIOR_RATE_BIPS,
                minJuniorBips: MIN_JUNIOR_BIPS,
                defaultPenaltyWindow: WINDOW,
                terminalRecipient: borrower
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

    function test_SeniorAccrualIsIndependentOfCheckpointFrequency() public {
        uint256 start = block.timestamp;
        uint256 snapshot = vm.snapshotState();
        for (uint256 i; i < 365; ++i) {
            vm.warp(start + ((i + 1) * 1 days));
            manager.accrue();
        }
        uint256 daily = manager.seniorOwed();

        assertTrue(vm.revertToStateAndDelete(snapshot));
        vm.warp(start + 365 days);
        manager.accrue();
        assertEq(manager.seniorOwed(), daily);
        assertEq(daily, 330e18);
    }

    function test_SeniorAccrualCarriesSubUnitRemainder() public pure {
        uint256 interest;
        uint256 remainder;
        for (uint256 i; i < 365; ++i) {
            (uint256 daily, uint256 nextRemainder) = WaterfallMath.accrueSeniorInterest(364, 10_000, 1 days, remainder);
            interest += daily;
            remainder = nextRemainder;
        }
        assertEq(interest, 364);
        assertEq(remainder, 0);
    }

    function test_ValueViewsPreviewElapsedSeniorAccrual() public {
        vm.warp(block.timestamp + 365 days);
        assertEq(manager.seniorOwed(), 300e18, "stored checkpoint");
        assertEq(manager.previewSeniorOwed(), 330e18, "previewed obligation");
        assertEq(senior.totalAssets(), 330e18, "senior view");
        assertEq(junior.totalAssets(), 70e18, "junior view");
    }

    function test_SeniorRedemptionRemovesPrincipalAndAccruedClaimProRata() public {
        vm.warp(block.timestamp + 365 days);
        manager.accrue();
        uint256 shares = senior.balanceOf(srLP) / 2;
        vm.prank(srLP);
        manager.requestRedeem(true, shares);
        assertEq(manager.seniorPrincipal(), 150e18);
        assertEq(manager.seniorOwed(), 165e18);
    }

    function test_RequestFaceMatchesScaledBacking() public {
        wrapper.setPrice(1.5e18);
        vm.prank(srLP);
        uint256 id = manager.requestRedeem(true, 2);
        (,, uint128 face,, uint32 expiry) = manager.requests(id);

        assertEq(face, 1, "floor-normalised request face");
        assertEq(market.owed(address(manager), expiry), 2, "market queue backing");
        assertEq(manager.seniorWmtQueued(), 1, "class face");
    }

    function test_RoundedFifoRequestCannotConsumeNextRequestsBacking() public {
        address secondSenior = address(0x5E12);
        seniorGate.setAllowed(secondSenior, true);
        vm.prank(srLP);
        senior.transfer(secondSenior, 2);
        wrapper.setPrice(1.5e18);

        vm.prank(srLP);
        uint256 firstId = manager.requestRedeem(true, 2);
        vm.prank(secondSenior);
        uint256 secondId = manager.requestRedeem(true, 2);
        (,,,, uint32 expiry) = manager.requests(secondId);

        assertEq(manager.seniorWmtQueued(), 2, "two backed faces");
        vm.warp(uint256(expiry) + 1);
        manager.pokeRecovery(expiry);
        assertEq(manager.claimable(firstId), 1, "first capped to own backing");
        assertEq(manager.claimable(secondId), 1, "second retains its backing");
    }

    function test_UnattributedRecoveryCannotFundAnyRequest() public {
        vm.prank(srLP);
        uint256 firstId = manager.requestRedeem(true, 100e18);
        (,, uint128 firstFace,,) = manager.requests(firstId);

        usdc.mint(address(manager), uint256(firstFace) + 10e18);
        manager.sync();
        assertEq(manager.claimable(firstId), 0, "unattributed cash cannot fund a request");
        assertEq(manager.recoverySurplus(), uint256(firstFace) + 10e18, "unattributed cash is surplus");

        vm.prank(srLP);
        uint256 secondId = manager.requestRedeem(true, 10e18);
        assertEq(manager.claimable(secondId), 0, "later request cannot inherit old recovery");

        (,, uint128 secondFace,,) = manager.requests(secondId);
        usdc.mint(address(manager), secondFace);
        manager.sync();
        assertEq(manager.claimable(secondId), 0, "unattributed cash remains surplus");
        assertEq(
            manager.recoverySurplus(), uint256(firstFace) + 10e18 + secondFace, "surplus remains terminal"
        );
    }

    function test_UnattributedCashCannotDoubleAdmitAnExecutedBatch() public {
        market.setClosed(true);
        market.setDelinquent(true);
        wrapper.setPrice(1.5e18);

        vm.prank(jrLP);
        uint256 id = manager.requestRedeem(false, 2);
        (,, uint128 face,, uint32 expiry) = manager.requests(id);

        // The manager cannot know which market batch a bare token transfer belongs to.
        usdc.mint(address(manager), face);
        manager.sync();
        assertEq(manager.allocatableUSDC(), 0, "unattributed transfer is not queue recovery");
        assertEq(manager.recoverySurplus(), face, "unattributed transfer is terminal surplus");

        vm.warp(uint256(expiry) + 1);
        market.executeWithdrawal(address(manager), expiry);

        assertEq(manager.recoveryObservedByExpiry(expiry), 2, "market receipt recorded once");
        assertEq(manager.allocatableUSDC(), face, "only the batch face is admitted");
        assertEq(manager.seniorDebtReserveUSDC(), face, "batch excess remains senior reserve");
        assertEq(manager.recoverySurplus(), face, "earlier untagged cash remains surplus");
    }

    function test_RequestSynchronizesRecoveryBeforeAddingFace() public {
        usdc.mint(address(manager), 10e18);

        vm.prank(srLP);
        uint256 id = manager.requestRedeem(true, 10e18);

        assertEq(manager.recoverySurplus(), 10e18, "pre-existing recovery is surplus");
        assertEq(manager.claimable(id), 0, "new request cannot inherit old recovery");
    }

    function test_TerminalSurplusFollowsFinalShareBurnAfterAllClaims() public {
        uint256 seniorShares = senior.balanceOf(srLP);
        uint256 juniorShares = junior.balanceOf(jrLP);
        vm.prank(srLP);
        uint256 seniorId = manager.requestRedeem(true, seniorShares);
        vm.prank(jrLP);
        uint256 juniorId = manager.requestRedeem(false, juniorShares);
        (,,,, uint32 expiry) = manager.requests(juniorId);

        assertEq(manager.terminalRecipient(), borrower, "terminal recipient is immutable facility term");
        assertEq(manager.markedAssets(), 0, "terminal facility has no marked tranche value");
        vm.expectRevert(bytes("REQUESTS_PENDING"));
        manager.settleTerminalSurplus();

        vm.warp(uint256(expiry) + 1);
        market.executeWithdrawal(address(manager), expiry);
        manager.claim(seniorId);
        manager.claim(juniorId);

        usdc.mint(address(manager), 7e18);
        manager.sync();
        assertEq(manager.recoverySurplus(), 7e18, "late cash remains terminal surplus");
        vm.startPrank(jrLP);
        usdc.approve(address(manager), 1e18);
        vm.expectRevert(bytes("TERMINAL"));
        manager.depositJunior(1e18, jrLP);
        vm.stopPrank();
        uint256 before = usdc.balanceOf(borrower);
        vm.prank(address(0xBEEF));
        assertEq(manager.settleTerminalSurplus(), 7e18, "terminal settlement amount");
        assertEq(usdc.balanceOf(borrower), before + 7e18, "caller cannot redirect terminal residual");
        assertEq(manager.recoverySurplus(), 0, "terminal surplus cleared");
    }

    function test_DelayedSyncCannotCreateDistressedSeniorReserve() public {
        market.setDelinquent(true);
        usdc.mint(address(manager), 300e18);
        manager.sync();
        assertEq(manager.allocatableUSDC(), 0, "unobserved cash has no queue admission");
        assertEq(manager.seniorDebtReserveUSDC(), 0, "late sync cannot infer distressed arrival");
        assertEq(manager.recoverySurplus(), 300e18, "unobserved cash is terminal surplus");
    }

    function test_AtomicPokeTagsScaledWithdrawalExcessToSeniorReserve() public {
        market.setClosed(true);
        market.setDelinquent(true);
        wrapper.setPrice(1.5e18);

        vm.prank(jrLP);
        uint256 juniorId = manager.requestRedeem(false, 2);
        (,,,, uint32 expiry) = manager.requests(juniorId);
        vm.warp(uint256(expiry) + 1);
        manager.pokeRecovery(expiry);

        assertEq(manager.claimable(juniorId), 0, "junior cannot use senior reserve in distress");
        assertEq(manager.allocatableUSDC(), 1, "queued face receives its own admission");
        assertEq(manager.seniorDebtReserveUSDC(), 1, "atomic excess is tagged to senior debt");

        vm.prank(srLP);
        uint256 seniorId = manager.requestRedeem(true, 2);
        assertEq(manager.seniorDebtReserveUSDC(), 0, "reserve migrates into senior replacement face");
        assertEq(manager.seniorCashAllocated(), 1, "migrated reserve fills senior before junior");
        assertEq(manager.claimable(seniorId), 1, "senior can claim the tagged excess");
    }

    function test_MigratedSeniorReserveCannotDoubleFundItsBatch() public {
        market.setClosed(true);
        market.setDelinquent(true);
        wrapper.setPrice(1.5e18);

        vm.prank(jrLP);
        uint256 juniorId = manager.requestRedeem(false, 2);
        (,,,, uint32 juniorExpiry) = manager.requests(juniorId);
        vm.warp(uint256(juniorExpiry) + 1);
        manager.pokeRecovery(juniorExpiry);
        assertEq(manager.seniorDebtReserveUSDC(), 1, "excess is reserved for senior");

        vm.prank(srLP);
        uint256 seniorId = manager.requestRedeem(true, 2);
        (,, uint128 seniorFace,, uint32 seniorExpiry) = manager.requests(seniorId);
        assertEq(seniorFace, 1, "senior batch face");
        assertEq(manager.faceCreditedByExpiry(seniorExpiry), seniorFace, "reserve credits senior batch");
        uint256 allocatableBefore = manager.allocatableUSDC();

        vm.warp(uint256(seniorExpiry) + 1);
        manager.pokeRecovery(seniorExpiry);

        assertEq(manager.allocatableUSDC(), allocatableBefore, "executed batch cannot double-admit reserve face");
        assertEq(manager.recoveryObservedByExpiry(seniorExpiry), 2, "full senior batch receipt recorded");
    }

    function test_PermissionlessExecutionUsesTheSameRecoveryProvenance() public {
        market.setClosed(true);
        market.setDelinquent(true);
        wrapper.setPrice(1.5e18);

        vm.prank(jrLP);
        uint256 juniorId = manager.requestRedeem(false, 2);
        (,,,, uint32 expiry) = manager.requests(juniorId);
        vm.warp(uint256(expiry) + 1);

        vm.prank(address(0xBEEF));
        market.executeWithdrawal(address(manager), expiry);

        assertEq(manager.recoveredUSDC(), 2, "hook books exact withdrawal before transfer");
        assertEq(manager.allocatableUSDC(), 1, "queued face is admitted");
        assertEq(manager.seniorDebtReserveUSDC(), 1, "excess has the same senior provenance");
        assertEq(manager.recoverySurplus(), 0, "direct execution cannot force surplus treatment");
        assertEq(manager.claimable(juniorId), 0, "senior priority is unchanged");
    }

    function test_ExecutedBatchCannotFundLaterBatch() public {
        market.setClosed(true);
        market.setDelinquent(true);
        wrapper.setPrice(1.5e18);

        vm.prank(jrLP);
        uint256 firstId = manager.requestRedeem(false, 2);
        (,,,, uint32 firstExpiry) = manager.requests(firstId);

        // Queue a separate, later market batch before anyone executes the old one.
        vm.warp(uint256(firstExpiry) + 1);
        vm.prank(jrLP);
        uint256 secondId = manager.requestRedeem(false, 2);
        (,,,, uint32 secondExpiry) = manager.requests(secondId);
        assertGt(secondExpiry, firstExpiry, "distinct withdrawal batches");
        assertEq(manager.faceQueuedByExpiry(firstExpiry), 1, "first batch face");
        assertEq(manager.faceQueuedByExpiry(secondExpiry), 1, "second batch face");

        // First batch pays two market units for its one-unit normalized face. Its excess may be
        // reserved for senior, but it cannot become recovery for the subsequently queued batch.
        market.executeWithdrawal(address(manager), firstExpiry);

        assertEq(manager.recoveryObservedByExpiry(firstExpiry), 2, "first batch receipt recorded");
        assertEq(manager.allocatableUSDC(), 1, "only first batch face admitted");
        assertEq(manager.seniorDebtReserveUSDC(), 1, "first batch excess keeps its provenance");
        assertEq(manager.claimable(secondId), 0, "later batch has no recovery yet");
    }

    function test_SanctionedManagerDefersBatchExecutionUntilClear() public {
        market.setClosed(true);
        market.setDelinquent(true);
        wrapper.setPrice(1.5e18);
        vm.prank(jrLP);
        uint256 juniorId = manager.requestRedeem(false, 2);
        (,,,, uint32 expiry) = manager.requests(juniorId);
        sentinel.setSanctioned(address(manager), true);
        vm.warp(uint256(expiry) + 1);

        vm.expectRevert(TrancheManager.ManagerSanctioned.selector);
        market.executeWithdrawal(address(manager), expiry);

        assertEq(manager.recoveredUSDC(), 0, "no recovery is booked before custody");
        assertEq(manager.claimable(juniorId), 0, "no phantom claim is created");
        address escrow = address(uint160(uint256(keccak256(abi.encodePacked("escrow", address(manager))))));
        assertEq(usdc.balanceOf(escrow), 0, "batch remains executable after sanctions clear");

        sentinel.setSanctioned(address(manager), false);
        market.executeWithdrawal(address(manager), expiry);
        assertEq(manager.recoveredUSDC(), 2, "clearance restores exact batch execution");
    }

    function test_ManagerSanctionCheckUsesLiveMarketPrincipal() public {
        market.setClosed(true);
        market.setDelinquent(true);
        wrapper.setPrice(1.5e18);
        vm.prank(jrLP);
        uint256 juniorId = manager.requestRedeem(false, 2);
        (,,,, uint32 expiry) = manager.requests(juniorId);

        address nextPrincipal = address(0xB0B);
        market.setBorrowerPrincipal(nextPrincipal);
        sentinel.setSanctionedFor(nextPrincipal, address(manager), true);
        vm.warp(uint256(expiry) + 1);

        vm.expectRevert(TrancheManager.ManagerSanctioned.selector);
        market.executeWithdrawal(address(manager), expiry);
        assertEq(manager.recoveredUSDC(), 0, "live market namespace prevents phantom recovery");
    }

    function test_FullyCoveredSeniorReserveDoesNotBlockQueuedJuniorRecovery() public {
        market.setClosed(true);
        market.setDelinquent(true);
        wrapper.setRedeemBonus(300e18);
        uint256 juniorShares = junior.balanceOf(jrLP);
        vm.prank(jrLP);
        uint256 juniorId = manager.requestRedeem(false, juniorShares);
        (,,,, uint32 expiry) = manager.requests(juniorId);

        vm.warp(uint256(expiry) + 1);
        manager.pokeRecovery(expiry);

        assertEq(manager.allocatableUSDC(), 100e18, "junior face has its own admission");
        assertEq(manager.seniorDebtReserveUSDC(), 300e18, "live senior debt is fully reserved");
        assertEq(manager.claimable(juniorId), 100e18, "fully covered senior reserve does not double-block junior");
    }

    function test_PartitionedDelinquentExitCannotRealiseFrozenUpside() public {
        uint256 seniorShares = senior.balanceOf(srLP);
        vm.prank(srLP);
        manager.requestRedeem(true, seniorShares);
        market.setDelinquent(true);
        uint256 livePrice = 1.1e18;
        wrapper.setPrice(livePrice);
        // The mock tracks only normalised balances while the production market tracks scaled
        // balances. One extra wei supplies the mock's final round-up without changing the case.
        market.mintTokens(address(wrapper), 10e18 + 1);
        uint256 half = junior.balanceOf(jrLP) / 2;

        vm.startPrank(jrLP);
        uint256 firstId = manager.requestRedeem(false, half);
        uint256 secondId = manager.requestRedeem(false, junior.balanceOf(jrLP));
        vm.stopPrank();

        (,, uint128 firstFace,,) = manager.requests(firstId);
        (,, uint128 secondFace,,) = manager.requests(secondId);
        uint256 aggregateFace = wrapper.convertToAssets(wrapper.convertToShares(100e18));
        assertEq(uint256(firstFace) + uint256(secondFace), aggregateFace, "partitioned face");
        assertEq(manager.juniorWmtQueued(), aggregateFace, "class face");
        assertEq(manager.markedAssets(), 0, "zero-share facility has no live book value");
        assertEq(wrapper.balanceOf(address(manager)), 0, "excluded appreciation is terminal custody");
        assertEq(market.balanceOf(address(manager)), 0, "terminal custody is queued immediately");
        assertEq(market.queueFullWithdrawalCalls(), 1, "terminal queue consumes exact market balance");
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

    function test_DelayedCheckpointStopsSeniorAccrualAtMarketClosure() public {
        uint256 start = block.timestamp;
        vm.warp(start + 1 days);
        vm.prank(address(hooks));
        manager.onMarketClosed(address(market), 0);
        vm.warp(start + 366 days);
        manager.accrue();

        (uint256 expectedInterest,) = WaterfallMath.accrueSeniorInterest(300e18, SENIOR_RATE_BIPS, 1 days, 0);
        assertEq(manager.seniorOwed(), 300e18 + expectedInterest);
        assertEq(manager.lastAccrual(), start + 1 days);
    }

    function test_CloseHookRejectsAnyOtherCaller() public {
        vm.expectRevert(bytes("ONLY_MARKET_HOOKS"));
        manager.onMarketClosed(address(market), 0);
    }

    function test_CloseHookRejectsAnotherMarketOnSameHook() public {
        vm.prank(address(hooks));
        vm.expectRevert(bytes("WRONG_MARKET"));
        manager.onMarketClosed(address(0xBAD), 0);
    }

    function test_CloseHookUsesEarlierDelinquencyThreshold() public {
        uint256 start = block.timestamp;
        uint256 threshold = market.delinquencyGracePeriod() + WINDOW;
        vm.warp(start + threshold + 30 days);
        vm.prank(address(hooks));
        manager.onMarketClosed(address(market), uint32(threshold + 30 days));

        (uint256 expectedInterest,) = WaterfallMath.accrueSeniorInterest(300e18, SENIOR_RATE_BIPS, threshold, 0);
        assertEq(manager.seniorOwed(), 300e18 + expectedInterest);
        assertEq(manager.lastAccrual(), start + threshold);
    }

    function test_DelayedCheckpointStopsAtDelinquencyThreshold() public {
        uint256 start = block.timestamp;
        uint256 threshold = market.delinquencyGracePeriod() + WINDOW;
        vm.warp(start + threshold + 7 days);
        market.setTimeDelinquent(uint32(threshold + 7 days));
        manager.accrue();

        (uint256 expectedInterest,) = WaterfallMath.accrueSeniorInterest(300e18, SENIOR_RATE_BIPS, threshold, 0);
        assertEq(manager.seniorOwed(), 300e18 + expectedInterest);
        assertEq(manager.lastAccrual(), start + threshold);
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
                defaultPenaltyWindow: WINDOW,
                terminalRecipient: borrower
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
                defaultPenaltyWindow: WINDOW,
                terminalRecipient: borrower
            })
        );
    }

    function test_DistressReserveCoversQueuedAndLiveSenior() public {
        market.setClosed(true);
        uint256 juniorShares = junior.balanceOf(jrLP);
        vm.prank(jrLP);
        manager.requestRedeem(false, juniorShares);
        uint256 seniorShares = senior.balanceOf(srLP) / 2;
        vm.prank(srLP);
        uint256 seniorId = manager.requestRedeem(true, seniorShares);
        uint32 expiry = uint32(block.timestamp + market.withdrawalBatchDuration());

        vm.prank(address(market));
        usdc.transfer(address(0xBEEF), 200e18);
        vm.warp(uint256(expiry) + 1);
        manager.pokeRecovery(expiry);

        assertEq(manager.seniorWmtQueued(), 150e18);
        assertEq(manager.seniorOwed(), 150e18);
        assertEq(manager.seniorCashAllocated(), 150e18);
        assertEq(manager.juniorCashAllocated(), 0);
        assertEq(manager.claimable(seniorId), 150e18);
        manager.claim(seniorId);
        assertEq(usdc.balanceOf(address(manager)), 50e18, "reserved for live senior");
    }

    function test_ZeroSupplyClassWithResidualValueCannotReopen() public {
        uint256 seniorShares = senior.balanceOf(srLP);
        vm.prank(srLP);
        manager.requestRedeem(true, seniorShares);
        market.setDelinquent(true);
        uint256 livePrice = 1.1e18;
        wrapper.setPrice(livePrice);
        // The mock tracks only normalised balances while the production market tracks scaled
        // balances. One extra wei supplies the mock's final round-up without changing the case.
        market.mintTokens(address(wrapper), 10e18 + 1);
        uint256 juniorShares = junior.balanceOf(jrLP);
        vm.prank(jrLP);
        uint256 id = manager.requestRedeem(false, juniorShares);
        (,, uint128 face,,) = manager.requests(id);

        uint256 expectedShares = (100e18 * 1e18) / livePrice;
        uint256 expectedFace = (expectedShares * livePrice) / 1e18;
        assertEq(face, expectedFace, "request uses scaled backing value");
        assertEq(wrapper.balanceOf(address(manager)), 0, "final burn queues residual wrapper custody");
        assertEq(market.balanceOf(address(manager)), 0, "terminal custody is not left liquid");
        assertEq(market.queueFullWithdrawalCalls(), 1, "terminal queue uses exact full withdrawal");
        assertEq(junior.totalSupply(), 0);
        assertTrue(manager.terminalised(), "zero supply permanently closes the facility");

        // The final redeem burns only the frozen-mark backing. The live-price remainder is queued
        // separately for the immutable terminal recipient rather than becoming unclaimable dust.
        uint32 expiry = uint32(block.timestamp + market.withdrawalBatchDuration());
        assertGt(market.owed(address(manager), expiry), uint256(face), "terminal residual is queued");

        address nextJunior = address(0xB0B);
        juniorGate.setAllowed(nextJunior, true);
        usdc.mint(nextJunior, 1e18);
        market.setDelinquent(false);
        vm.startPrank(nextJunior);
        usdc.approve(address(manager), 1e18);
        vm.expectRevert(bytes("TERMINAL"));
        manager.depositJunior(1e18, nextJunior);
        vm.stopPrank();
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

        otherMarket.setDelinquencyFeeBips(0);
        vm.expectRevert(TrancheFactory.ZeroDelinquencyFee.selector);
        factory.deployTranches(
            otherSalt, _params(address(otherMarket), address(otherWrapper), address(otherHooks), address(otherProvider))
        );

        otherMarket.setDelinquencyFeeBips(1);
        vm.expectRevert(TrancheFactory.HookConfigurationInvalid.selector);
        factory.deployTranches(
            otherSalt, _params(address(otherMarket), address(otherWrapper), address(otherHooks), address(otherProvider))
        );
    }

    function test_FactoryRejectsInvalidTerminalRecipient() public {
        bytes32 otherSalt = keccak256("terminal-recipient");
        TrancheFactory.DeployParams memory p =
            _params(address(market), address(wrapper), address(hooks), address(provider));

        p.terminalRecipient = address(0);
        vm.expectRevert(TrancheFactory.TerminalRecipientInvalid.selector);
        factory.deployTranches(otherSalt, p);

        p.terminalRecipient = factory.computeManagerAddress(address(this), otherSalt);
        vm.expectRevert(TrancheFactory.TerminalRecipientInvalid.selector);
        factory.deployTranches(otherSalt, p);
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
