// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {TrancheController} from "../src/TrancheController.sol";
import {TrancheToken} from "../src/TrancheToken.sol";
import {MockERC20, MockMarket, MockWrapper, MockSentinel} from "./Mocks.sol";

/// @notice Sentinel that reenters the controller during createEscrow, to probe the reentrancy
///         posture of the one external call with plausible custom logic (F10/F11).
contract ReentrantSentinel {
    TrancheController public c;
    mapping(address => bool) public flagged;
    bool public reentryAttempted;
    bool public stateReentryReverted;
    uint256 public recoveredSeenMidClaim;

    function setController(TrancheController _c) external {
        c = _c;
    }

    function setSanctioned(address a, bool v) external {
        flagged[a] = v;
    }

    function isSanctioned(address, address account) external view returns (bool) {
        return flagged[account];
    }

    function createEscrow(address, address account, address) external returns (address) {
        if (address(c) != address(0)) {
            reentryAttempted = true;
            // state-changing reentry must be blocked by ReentrancyGuard
            try c.claim(0) {
                stateReentryReverted = false;
            } catch {
                stateReentryReverted = true;
            }
            // read-only reentry into a view must observe consistent state (no double-count)
            recoveredSeenMidClaim = c.recoveredUSDC();
        }
        return address(uint160(uint256(keccak256(abi.encodePacked("escrow", account)))));
    }
}

contract AttackTest is Test {
    MockERC20 usdc;
    MockMarket market;
    MockWrapper wrapper;
    MockSentinel sentinel;
    TrancheController c;
    TrancheToken senior;
    TrancheToken junior;

    address gov = address(0x6011);
    address declarer = address(0xDEC);
    address srLP = address(0x5E11);
    address jrLP = address(0x10110);
    address borrower = address(0xB0110);

    uint256 constant MIN_JUNIOR_BIPS = 2000;
    uint256 constant SENIOR_SHARE_BIPS = 10000;
    uint256 constant WINDOW = 90 days;

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC");
        market = new MockMarket(address(usdc));
        wrapper = new MockWrapper(address(market));
        sentinel = new MockSentinel();
        c = _deploy(address(sentinel), 18);
        senior = c.senior();
        junior = c.junior();

        wrapper.mintShares(srLP, 100_000_000e18);
        wrapper.mintShares(jrLP, 100_000_000e18);
        vm.prank(gov);
        c.setJuniorAllowed(jrLP, true);

        _depositJunior(jrLP, 100e18); // value 100
        _depositSenior(srLP, 300e18); // value 300, junior 25% of TVL, seniorOwed 300
    }

    function _deploy(address sent, uint8 dec) internal returns (TrancheController) {
        return new TrancheController(
            TrancheController.Params({
                underlyingVault: address(wrapper),
                sentinel: sent,
                borrower: borrower,
                governance: gov,
                defaultDeclarer: declarer,
                seniorShareBips: SENIOR_SHARE_BIPS,
                minJuniorBips: MIN_JUNIOR_BIPS,
                defaultPenaltyWindow: WINDOW,
                shareDecimals: dec
            })
        );
    }

    function _depositSenior(address who, uint256 shares) internal returns (uint256) {
        vm.startPrank(who);
        wrapper.approve(address(c), shares);
        uint256 s = c.depositSenior(shares, who);
        vm.stopPrank();
        return s;
    }

    function _depositJunior(address who, uint256 shares) internal returns (uint256) {
        vm.startPrank(who);
        wrapper.approve(address(c), shares);
        uint256 s = c.depositJunior(shares, who);
        vm.stopPrank();
        return s;
    }

    function _inv() internal view {
        (uint256 sv, uint256 jv) = c.trancheValues();
        assertEq(sv + jv, c.realisedValue(), "conservation");
    }

    // ----------------------------------------------------------------- F4: donation / inflation
    /// @dev A direct donation of wrapper shares cannot inflate senior: senior is capped at
    ///      seniorOwed, so the donation lands entirely in the junior residual.
    function test_DonationCannotInflateSenior() public {
        uint256 ppsBefore = senior.convertToAssets(1e18);
        wrapper.mintShares(address(c), 1_000_000e18); // attacker donates
        c.accrue();

        (uint256 sv, uint256 jv) = c.trancheValues();
        assertEq(sv, 300e18, "senior value unchanged by donation");
        assertEq(jv, 100e18 + 1_000_000e18, "donation accrues to junior residual only");
        assertEq(senior.convertToAssets(1e18), ppsBefore, "senior pps not inflated");
        _inv();
    }

    /// @dev The classic first-depositor inflation attack cannot silently steal: a victim whose
    ///      share computation rounds to zero reverts (ZERO_SHARES) rather than minting nothing
    ///      and gifting the deposit to the attacker. The donation that powers the attack is also
    ///      fully reclaimable by the attacker, so it is capital-intensive griefing, not theft.
    function test_JuniorDonationCannotSilentlySteal() public {
        // attacker is the only junior holder (jrLP, 100 shares, value 100)
        uint256 attackerShares = junior.balanceOf(jrLP);

        // attacker donates a large amount to inflate junior price-per-share (~1e4 per share)
        wrapper.mintShares(address(c), 1_000_000e18);
        c.accrue();
        (, uint256 jvInflated) = c.trancheValues();
        assertEq(jvInflated, 100e18 + 1_000_000e18, "junior value inflated by donation");

        // a victim deposit below the (inflated) price-per-share rounds to zero shares and REVERTS
        // rather than minting nothing: no silent loss. Inflating pps enough to threaten a realistic
        // deposit needs a donation far larger than that deposit, so it is not a profitable theft.
        address victim = address(0xBEEF1);
        vm.prank(gov);
        c.setJuniorAllowed(victim, true);
        wrapper.mintShares(victim, 1e4); // below pps -> would round to zero shares
        vm.startPrank(victim);
        wrapper.approve(address(c), 1e4);
        vm.expectRevert(bytes("ZERO_SHARES"));
        c.depositJunior(1e4, victim);
        vm.stopPrank();

        // the donation is fully attributed to the attacker's own shares (never burned, not seized
        // by the protocol): reclaimable capital, so the grief only costs the attacker liquidity.
        assertEq(
            junior.convertToAssets(attackerShares),
            100e18 + 1_000_000e18,
            "donation accrues to the attacker's shares, recoverable not stolen"
        );
        _inv();
    }

    /// @dev A victim depositing an amount large enough to mint a nonzero share count is not
    ///      materially diluted: redeemable value comes back within one-share rounding of the deposit.
    function test_JuniorDonationVictimNotDiluted() public {
        wrapper.mintShares(address(c), 900e18); // junior value 100 -> 1000, supply 100, pps 10
        c.accrue();

        address victim = address(0xBEEF2);
        vm.prank(gov);
        c.setJuniorAllowed(victim, true);
        wrapper.mintShares(victim, 50e18);
        uint256 vShares = _depositJunior(victim, 50e18); // 50 * 100 / 1000 = 5 shares
        assertEq(vShares, 5e18, "victim mints fair nonzero shares");

        uint256 got = _redeemJuniorToUsdc(victim, vShares);
        // one-share rounding tolerance at pps ~10 is < 10e18
        assertApproxEqAbs(got, 50e18, 10e18, "victim recovers ~deposit, no material dilution");
        _inv();
    }

    // ----------------------------------------------------------------- F5: senior exit while impaired
    /// @dev When senior is impaired (junior wiped), a senior partial exit conserves value and
    ///      leaves remaining holders at the same per-share value as the exiting holder.
    function test_SeniorExitDuringImpairmentIsFairAndConserves() public {
        wrapper.setPrice(0.5e18); // realised 200 < seniorOwed 300 -> jv 0, sv 200
        c.accrue();
        (uint256 sv0, uint256 jv0) = c.trancheValues();
        assertEq(jv0, 0, "junior wiped");
        assertEq(sv0, 200e18, "senior impaired to realised");

        uint256 supply0 = senior.totalSupply(); // 300e18
        uint256 redeemerPerShare = (sv0 * 1e18) / supply0; // ~0.6667e18

        uint256 half = senior.balanceOf(srLP) / 2; // 150e18
        vm.prank(srLP);
        c.requestRedeem(true, half);

        assertEq(c.seniorOwed(), 150e18, "owed reduced pro-rata by burned shares");
        (uint256 sv1, uint256 jv1) = c.trancheValues();
        assertEq(jv1, 0, "junior still wiped");
        assertEq(sv1, 100e18, "remaining senior value tracks remaining realised");
        assertEq(sv1 + jv1, c.realisedValue(), "conservation after impaired exit");

        uint256 remPerShare = (sv1 * 1e18) / senior.totalSupply();
        assertApproxEqAbs(remPerShare, redeemerPerShare, 1, "no wealth transfer across the exit");
    }

    /// @dev A holder who exits during impairment crystallizes the loss; holders who stay capture
    ///      the upside if the market later recovers. That asymmetry is intended.
    function test_StayersCaptureRecoveryAfterImpairedExit() public {
        wrapper.setPrice(0.5e18);
        c.accrue();
        uint256 half = senior.balanceOf(srLP) / 2;
        vm.prank(srLP);
        c.requestRedeem(true, half); // exits at 0.6667/share, owed -> 150, realised -> 100

        wrapper.setPrice(1e18); // recovery
        c.accrue();
        (uint256 sv,) = c.trancheValues();
        // remaining wrapper balance 200e18 at price 1.0 = 200 realised; owed 150 -> senior whole at 150
        assertEq(sv, 150e18, "stayers made whole up to remaining owed after recovery");
        assertEq(senior.convertToAssets(senior.totalSupply()), sv, "stayer per-share recovered");
    }

    // ----------------------------------------------------------------- F6: non-par recovery, senior-first in USD
    /// @dev Under a sub-par (haircut) recovery, senior is made whole in USD before junior receives
    ///      a cent, and junior only ever sees the surplus above the senior face.
    function test_NonParRecoverySeniorFirstInUsd() public {
        uint256 sShares = senior.balanceOf(srLP);
        uint256 jShares = junior.balanceOf(jrLP);
        vm.prank(srLP);
        uint256 sid = c.requestRedeem(true, sShares); // 300 wmt face
        vm.prank(jrLP);
        uint256 jid = c.requestRedeem(false, jShares); // 100 wmt face
        uint32 expiry = uint32(block.timestamp + market.withdrawalBatchDuration());
        vm.warp(expiry + 1);

        // borrower repays only 240 of 400 face (60 cents on the dollar)
        usdc.mint(address(market), 240e18);
        c.pokeRecovery(expiry);
        assertEq(c.claimable(sid), 240e18, "senior takes the whole haircut recovery first");
        assertEq(c.claimable(jid), 0, "junior gets nothing while senior is short");

        // top up to exactly the senior face
        usdc.mint(address(market), 60e18);
        c.pokeRecovery(expiry);
        assertEq(c.claimable(sid), 300e18, "senior reaches its full face");
        assertEq(c.claimable(jid), 0, "junior still nothing at the senior-face boundary");

        // only the surplus above the senior face reaches junior
        usdc.mint(address(market), 50e18);
        c.pokeRecovery(expiry);
        assertEq(c.claimable(jid), 50e18, "junior receives only the surplus");
    }

    /// @dev Senior-first holds even when senior and junior queue at different wrapper prices, i.e.
    ///      the wmt pro-rata basis stays a faithful proxy for USD priority across price moves.
    function test_SeniorFirstAcrossPriceMovesBetweenRequests() public {
        // senior queues at price 1.0
        uint256 sShares = senior.balanceOf(srLP);
        vm.prank(srLP);
        uint256 sid = c.requestRedeem(true, sShares); // assetValue 300 -> 300 wmt

        // price rises before junior queues; junior still has residual value
        wrapper.setPrice(1.5e18);
        c.accrue();
        uint256 jShares = junior.balanceOf(jrLP);
        vm.prank(jrLP);
        uint256 jid = c.requestRedeem(false, jShares);
        (,, uint128 jWmt,,) = c.requests(jid);
        assertGt(jWmt, 0, "junior queued some wmt");

        uint32 expiry = uint32(block.timestamp + market.withdrawalBatchDuration());
        vm.warp(expiry + 1);

        // partial recovery below the senior face: senior must still be first
        usdc.mint(address(market), 200e18);
        c.pokeRecovery(expiry);
        assertEq(c.claimable(sid), 200e18, "senior first regardless of junior's queue price");
        assertEq(c.claimable(jid), 0, "junior waits until senior face is covered");
    }

    // -------------------------------------------------- multi-request / multi-poke interleaving
    /// @dev Two senior and two junior requests, recovered in chunks across the senior/junior pool
    ///      boundary, with claims interleaved: senior-first holds cumulatively and nothing is
    ///      double-claimed or over-distributed.
    function test_MultiRequestMultiPokeInterleaving() public {
        // top up balanced legs: split senior and junior into two holders each
        address sr2 = address(0x5E22);
        address jr2 = address(0x1022);
        wrapper.mintShares(sr2, 1_000e18);
        wrapper.mintShares(jr2, 1_000e18);
        vm.prank(gov);
        c.setJuniorAllowed(jr2, true);
        _depositJunior(jr2, 100e18); // junior total value 200
        _depositSenior(sr2, 300e18); // senior total value 600, junior 25%

        uint256 s1 = senior.balanceOf(srLP);
        uint256 s2 = senior.balanceOf(sr2);
        uint256 j1 = junior.balanceOf(jrLP);
        uint256 j2 = junior.balanceOf(jr2);

        vm.prank(srLP);
        uint256 sid1 = c.requestRedeem(true, s1); // 300 wmt
        vm.prank(sr2);
        uint256 sid2 = c.requestRedeem(true, s2); // 300 wmt  (senior face 600)
        vm.prank(jrLP);
        uint256 jid1 = c.requestRedeem(false, j1); // 100 wmt
        vm.prank(jr2);
        uint256 jid2 = c.requestRedeem(false, j2); // 100 wmt  (junior face 200)

        uint32 expiry = uint32(block.timestamp + market.withdrawalBatchDuration());
        vm.warp(expiry + 1);

        // chunk 1: 300 -> split pro-rata across senior only
        usdc.mint(address(market), 300e18);
        c.pokeRecovery(expiry);
        assertEq(c.claimable(sid1), 150e18, "senior 1 pro-rata of senior pool");
        assertEq(c.claimable(sid2), 150e18, "senior 2 pro-rata of senior pool");
        assertEq(c.claimable(jid1), 0, "junior 1 waits");
        assertEq(c.claimable(jid2), 0, "junior 2 waits");

        // one senior claims mid-stream
        vm.prank(srLP);
        c.claim(sid1);

        // chunk 2: another 300 completes the senior face (600 total); junior still nothing
        usdc.mint(address(market), 300e18);
        c.pokeRecovery(expiry);
        assertEq(c.claimable(sid1), 150e18, "senior 1 remainder after its earlier claim");
        assertEq(c.claimable(sid2), 300e18, "senior 2 now full");
        assertEq(c.claimable(jid1), 0, "junior still nothing at senior face");
        assertEq(c.claimable(jid2), 0, "junior still nothing at senior face");

        // chunk 3: surplus splits pro-rata across junior
        usdc.mint(address(market), 100e18);
        c.pokeRecovery(expiry);
        assertEq(c.claimable(jid1), 50e18, "junior 1 pro-rata of surplus");
        assertEq(c.claimable(jid2), 50e18, "junior 2 pro-rata of surplus");

        _assertNoOverDistribution();
    }

    /// @dev Total claimed + still-claimable never exceeds total recovered USDC.
    function _assertNoOverDistribution() internal view {
        uint256 n = c.requestsLength();
        uint256 totalEntitled;
        for (uint256 i = 0; i < n; i++) {
            (,,, uint128 usdcClaimed,) = c.requests(i);
            totalEntitled += uint256(usdcClaimed) + c.claimable(i);
        }
        assertLe(totalEntitled, c.recoveredUSDC(), "no over-distribution beyond recovered USDC");
    }

    // ------------------------------------------------------------------ F10/F11: reentrancy posture
    /// @dev A malicious sentinel reentering during createEscrow cannot reenter a state-changing
    ///      entrypoint (ReentrancyGuard), and a read-only reentry observes consistent state.
    function test_ReadOnlyReentrancyIsContained() public {
        ReentrantSentinel evil = new ReentrantSentinel();
        TrancheController cc = _deploy(address(evil), 18);
        evil.setController(cc);
        TrancheToken sr = cc.senior();
        TrancheToken jr = cc.junior();

        wrapper.mintShares(srLP, 1_000e18);
        wrapper.mintShares(jrLP, 1_000e18);
        vm.prank(gov);
        cc.setJuniorAllowed(jrLP, true);

        vm.startPrank(jrLP);
        wrapper.approve(address(cc), 100e18);
        cc.depositJunior(100e18, jrLP);
        vm.stopPrank();
        vm.startPrank(srLP);
        wrapper.approve(address(cc), 300e18);
        cc.depositSenior(300e18, srLP);
        uint256 sShares = sr.balanceOf(srLP);
        uint256 id = cc.requestRedeem(true, sShares);
        vm.stopPrank();

        uint32 expiry = uint32(block.timestamp + market.withdrawalBatchDuration());
        vm.warp(expiry + 1);
        usdc.mint(address(market), 300e18);
        cc.pokeRecovery(expiry);

        // owner sanctioned -> claim routes through sentinel.createEscrow -> reentry attempts
        evil.setSanctioned(srLP, true);
        vm.prank(srLP);
        uint256 got = cc.claim(id);

        assertTrue(evil.reentryAttempted(), "sentinel did attempt reentry");
        assertTrue(evil.stateReentryReverted(), "state-changing reentry blocked by guard");
        assertEq(evil.recoveredSeenMidClaim(), 300e18, "view reentry saw consistent recovered total");
        assertApproxEqAbs(got, 300e18, 1, "claim still settled exactly once");
        // escrow funded, LP got nothing directly, no double-spend
        address escrow = address(uint160(uint256(keccak256(abi.encodePacked("escrow", srLP)))));
        assertApproxEqAbs(usdc.balanceOf(escrow), 300e18, 1, "escrow funded once");
        assertEq(usdc.balanceOf(srLP), 0, "sanctioned LP not paid directly");
        jr; // silence unused
    }

    // ----------------------------------------------------------------- decimals are cosmetic
    /// @dev shareDecimals only affects the token's displayed decimals, not the internal share
    ///      math (which works in raw asset-value integers). A 6-decimal deployment behaves
    ///      identically and remains immune to senior inflation.
    function test_ShareDecimalsAreCosmetic() public {
        TrancheController c6 = _deploy(address(sentinel), 6);
        assertEq(c6.senior().decimals(), 6, "token reports 6 decimals");

        wrapper.mintShares(srLP, 1_000e18);
        wrapper.mintShares(jrLP, 1_000e18);
        vm.prank(gov);
        c6.setJuniorAllowed(jrLP, true);
        vm.startPrank(jrLP);
        wrapper.approve(address(c6), 100e18);
        uint256 jsh = c6.depositJunior(100e18, jrLP);
        vm.stopPrank();
        vm.startPrank(srLP);
        wrapper.approve(address(c6), 300e18);
        uint256 ssh = c6.depositSenior(300e18, srLP);
        vm.stopPrank();

        // share counts equal the asset value (same integers as an 18-decimal deploy)
        assertEq(jsh, 100e18, "junior shares == value, decimals do not scale the math");
        assertEq(ssh, 300e18, "senior shares == value");

        // donation still cannot inflate senior at 6 decimals
        uint256 pps = c6.senior().convertToAssets(1e18);
        wrapper.mintShares(address(c6), 500e18);
        c6.accrue();
        assertEq(c6.senior().convertToAssets(1e18), pps, "senior pps unaffected at 6 decimals");
    }

    // ----------------------------------------------------------------- FINDING (self-review)
    /// @dev FOUND BY THE no-over-distribution INVARIANT. The redemption queue divides recoveries by
    ///      a class total (totalJuniorWmtQueued / totalSeniorWmtQueued) that only ever grows and is
    ///      never reconciled against amounts already claimed. A request that queues AFTER an earlier
    ///      request has already claimed a recovery is credited a pro-rata slice of that
    ///      already-distributed USDC. The result: claimable() over-states, total promised exceeds
    ///      total recovered, and under a partial (sub-par) recovery the earlier claimant captures
    ///      more than its pro-rata share, leaving the late queuer's claim unbacked.
    ///      This documents the bug; see the red-team framework "Self-review findings" for fix options.
    function test_Finding_LateQueuerOverPromisesRecovery() public {
        TrancheController cc = _deploy(address(sentinel), 18);
        TrancheToken jr = cc.junior();
        address a = address(0xA11);
        address b = address(0xB22);
        vm.startPrank(gov);
        cc.setJuniorAllowed(a, true);
        cc.setJuniorAllowed(b, true);
        vm.stopPrank();
        wrapper.mintShares(a, 100e18);
        wrapper.mintShares(b, 100e18);

        // A deposits 100 junior and queues a redemption (owed 100)
        vm.startPrank(a);
        wrapper.approve(address(cc), 100e18);
        cc.depositJunior(100e18, a);
        uint256 aid = cc.requestRedeem(false, jr.balanceOf(a));
        vm.stopPrank();

        uint32 e1 = uint32(block.timestamp + market.withdrawalBatchDuration());
        vm.warp(e1 + 1);

        // a partial recovery of 100 arrives and A, the only queuer, claims all of it
        usdc.mint(address(market), 100e18);
        cc.pokeRecovery(e1);
        vm.prank(a);
        uint256 aGot = cc.claim(aid);
        assertEq(aGot, 100e18, "A claims the whole recovery as sole queuer");
        assertEq(cc.recoveredUSDC(), 100e18);

        // B now deposits 100 junior and queues; no new recovery has arrived
        vm.startPrank(b);
        wrapper.approve(address(cc), 100e18);
        cc.depositJunior(100e18, b);
        uint256 bid = cc.requestRedeem(false, jr.balanceOf(b));
        vm.stopPrank();

        // BUG 1: claimable() credits B a slice of the already-distributed recovery
        uint256 bClaimable = cc.claimable(bid);
        assertGt(bClaimable, 0, "FINDING: late queuer credited already-paid recovery");

        // BUG 2: total promised now exceeds total recovered (the invariant that caught this)
        assertGt(aGot + bClaimable, cc.recoveredUSDC(), "FINDING: over-promise beyond recovered USDC");

        // BUG 3: the promise is unbacked, so B's claim cannot actually settle
        vm.prank(b);
        vm.expectRevert();
        cc.claim(bid);
    }

    // ---- helper: junior redeem all the way to USDC in hand ----
    function _redeemJuniorToUsdc(address who, uint256 shares) internal returns (uint256) {
        vm.prank(who);
        uint256 id = c.requestRedeem(false, shares);
        (,, uint128 wmt,, uint32 expiry) = c.requests(id);
        usdc.mint(address(market), uint256(wmt)); // fund the batch at par
        vm.warp(uint256(expiry) + 1);
        c.pokeRecovery(expiry);
        uint256 before = usdc.balanceOf(who);
        vm.prank(who);
        c.claim(id);
        return usdc.balanceOf(who) - before;
    }
}
