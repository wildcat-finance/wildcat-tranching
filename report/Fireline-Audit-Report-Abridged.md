# Internal Review: Outstanding Wildcat Tranching Issue

Run: `runs/20260628T225808Z-build-48cc01d`
Target repo: `/home/kethcode/audits/wildcat-tranching`
Target commit: `48cc01d`
Date reviewed: 2026-06-29

## Executive Summary

One item is worth review:

**Pre-distress junior cash allocation remains claimable after the market becomes distressed, even when the distress gate would reserve all recovered cash for senior.**

This is not the same as Pashov SR-D, which was the frozen-mark over-redemption bug in `requestRedeem` and is fixed. It also is not Pashov R1, which fixed stale `seniorOwed` at the distress gate by intentionally accruing before wind-down.

The open question is product/legal semantics:

- If a junior request's cash allocation is meant to become vested once allocated while the market is healthy, this should be explicitly documented and regression-tested.
- If the stated senior-first distress priority is meant to apply at claim time until cash leaves the controller, this is a real issue and should be fixed before production.

My read from the local product docs and red-team framework is that the second interpretation is stronger: during distress, junior should not be able to claim recovered cash while the full senior obligation is uncovered.

## Prior Audit Cross-Check

Local audit/report material checked:

- `/home/kethcode/audits/wildcat-tranching/report/Pashov-Audit-Report.md`
- `/home/kethcode/audits/wildcat-tranching/report/Pashov-Audit-Report-Reaudit.md`
- `/home/kethcode/audits/wildcat-tranching/Red-Team-Technical-Framework.md`
- `/home/kethcode/audits/wildcat-tranching/Design-Risk-Specification.md`
- `/home/kethcode/audits/wildcat-tranching/Tranching-Explained.md`
- `/home/kethcode/audits/wildcat-tranching/README.md`
- rendered report PDFs/HTML under `/home/kethcode/audits/wildcat-tranching/report/`

No `SECURITY.md` was present in the repo.

Relevant prior findings:

- **SR-D fixed:** Pashov's frozen-mark over-redemption during delinquency was fixed by sizing wrapper redemption at the live price. Regression: `test_FrozenMarkRedemptionSizedAtLivePrice`.
- **R1 fixed:** Pashov's stale `seniorOwed` at the distress gate was fixed by accruing before default/wind-down and before recovery allocation. Regression: `test_R1_AccrualBookedBeforeWindDown`.
- **Compounding accepted:** repeated `accrue()` compounding is explicitly accepted/by-design in the Pashov report and red-team framework.

The stale junior allocation issue below does not appear to be covered by those prior reports. It is a different state-transition case: cash was allocated to junior while healthy, then the market became distressed before `claim()`.

## Finding: Pre-Distress Junior Allocation Can Be Claimed After Distress

Status: **needs product review**
Suggested severity if unintended: **medium/high**, depending on whether this is framed as violation of senior-priority cash settlement or as loss of senior reserve during distress.

### Impact

A junior LP can receive USDC after the market becomes delinquent even though:

- `recoveredUSDC < seniorOwed`
- no senior cash reserve is fully funded
- the distress allocation rule would compute a junior ceiling of zero

This conflicts with the documented property that recovered cash is distributed senior-first during trouble/default and that junior absorbs losses before senior.

### Preconditions

1. Junior has a redeem request while the market is still healthy.
2. The request is small enough to pass the Active subordination withdrawal gate.
3. Some USDC is recovered while the market is healthy and is allocated to junior.
4. Before the junior calls `claim()`, the market becomes delinquent or enters wind-down.
5. At that point, recovered cash is still less than `seniorOwed`.

### Root Cause

`_allocate()` enforces the distress gate only when assigning *new* recovered cash. It does not claw back or rebucket already allocated junior cash after the market state changes.

Relevant code:

```solidity
uint256 seniorReserve = _distressed() ? seniorOwed : seniorWmtQueued;
uint256 juniorCeil = recoveredUSDC > seniorReserve ? recoveredUSDC - seniorReserve : 0;
if (juniorCeil > juniorWmtQueued) juniorCeil = juniorWmtQueued;
uint256 juniorRoom = juniorCeil > juniorCashAllocated ? juniorCeil - juniorCashAllocated : 0;
uint256 toJunior = undistributed < juniorRoom ? undistributed : juniorRoom;
if (toJunior > 0) juniorCashAllocated += toJunior;
```

`claimable()` then reads the stored class allocation directly:

```solidity
uint256 allocated = r.isSenior ? seniorCashAllocated : juniorCashAllocated;
uint256 fb = faceBefore[id];
if (allocated <= fb) return 0;
uint256 reached = allocated - fb;
uint256 entitled = reached < r.wmt ? reached : r.wmt;
return entitled > r.usdcClaimed ? entitled - r.usdcClaimed : 0;
```

`claim()` does not call `accrue()`, `sync()`, `_allocate()`, or any distress rebalance before transferring:

```solidity
amt = claimable(id);
if (amt == 0) return 0;
r.usdcClaimed += uint128(amt);
totalClaimedOut += amt;
address(baseAsset).safeTransfer(r.owner, amt);
```

### Why This Is Not SR-D

Pashov SR-D was about `requestRedeem` using a frozen mark to size wrapper shares while `redeem()` paid at the live price, causing over-redemption during delinquency. The current code fixes that by sizing at `_curPps()`.

This issue is about already allocated `juniorCashAllocated` surviving a later state transition into distress. The junior request queues the expected face amount; the problem is that the stored cash allocation remains claimable after the senior reserve rule changes.

### Why This Is Not R1

Pashov R1 was about stale `seniorOwed` at the distress gate. The fix makes `accrue()`, `checkDefault()`, `declareDefault()`, `pokeRecovery()`, and `sync()` refresh senior owed before the distress gate is evaluated.

Here, `seniorOwed` is not stale. The PoC explicitly shows the distress junior ceiling is zero using the current `seniorOwed`, but `claimable()` still returns the old junior allocation.

## Proof of Concept

Preserved PoC:

`runs/20260628T225808Z-build-48cc01d/legacy/20260628T225809Z-pristine-79266ce-2357fa/pocs/candidate-cda04171ea6ab68a/artifacts/files/68d5fb0f77e88c7e-CandidateCDA04171.t.sol`

Run:

```bash
cd runs/20260628T225808Z-build-48cc01d/legacy/20260628T225809Z-pristine-79266ce-2357fa/pocs/candidate-cda04171ea6ab68a/scratch
forge test --match-path test/CandidateCDA04171.t.sol --match-test test_ClaimUsesStaleJuniorAllocationAfterDistress -vvv
```

Result:

```text
Ran 1 test for test/CandidateCDA04171.t.sol:CandidateCDA04171PoC
[PASS] test_ClaimUsesStaleJuniorAllocationAfterDistress() (gas: 452514)
Suite result: ok. 1 passed; 0 failed; 0 skipped
```

Critical test body:

```solidity
function test_ClaimUsesStaleJuniorAllocationAfterDistress() public {
    vm.prank(jrLP);
    uint256 juniorRequestId = controller.requestRedeem(false, 20e18);
    (,, uint128 queuedWmt,, uint32 expiry) = controller.requests(juniorRequestId);
    assertEq(uint256(queuedWmt), 20e18, "junior queued allowed face");
    assertEq(controller.seniorWmtQueued(), 0, "no senior redemption is queued");
    assertEq(controller.seniorOwed(), 300e18, "full senior obligation remains outstanding");

    usdc.mint(address(market), 20e18);
    vm.warp(uint256(expiry) + 1);
    controller.pokeRecovery(expiry);

    assertEq(controller.recoveredUSDC(), 20e18, "only junior-sized USDC has been recovered");
    assertEq(controller.juniorCashAllocated(), 20e18, "healthy allocation assigned recovery to junior");
    assertEq(controller.claimable(juniorRequestId), 20e18, "junior is claimable before distress");

    market.setDelinquent(true);

    uint256 distressedJuniorCeil =
        controller.recoveredUSDC() > controller.seniorOwed() ? controller.recoveredUSDC() - controller.seniorOwed() : 0;
    assertEq(distressedJuniorCeil, 0, "distress gate should reserve all recovered USDC for seniorOwed");
    assertEq(controller.claimable(juniorRequestId), 20e18, "claimable still uses stale healthy allocation");

    uint256 seniorReserveBefore = usdc.balanceOf(address(controller));
    vm.prank(jrLP);
    uint256 claimed = controller.claim(juniorRequestId);

    assertEq(claimed, 20e18, "junior claim was released while distressed");
    assertEq(usdc.balanceOf(jrLP), 20e18, "recovered USDC left the controller to junior");
    assertEq(usdc.balanceOf(address(controller)), seniorReserveBefore - 20e18, "senior reserve cash was depleted");
    assertEq(controller.totalClaimedOut(), 20e18, "claim consumed stale allocation accounting");
    assertLt(usdc.balanceOf(address(controller)), controller.seniorOwed(), "senior obligation is no longer cash-reserved");
}
```

## Product Decision Needed

The core question:

**When recovered USDC has been allocated to a junior request while healthy, but has not yet been claimed, should later distress invalidate or suspend that junior claim until senior is covered?**

Reasons to answer "yes":

- Docs repeatedly say senior-first settlement applies when cash comes back in trouble/default.
- Red-team invariant 3 says no junior request can be allocated USDC while the senior obligation is uncovered under distress.
- Red-team invariant 10 says no actor should withdraw more than their tranche value entitles or subvert priority ordering.
- The actual cash has not left the controller yet, so the contract can still enforce priority at claim time.

Reasons to answer "no":

- `_allocate()` is explicitly monotonic and says "O(1); no clawback."
- `claimable()` is modeled as FIFO settlement from class allocation; once allocated, the request may be intended to have a vested right to claim.
- Reversing allocation after it becomes claimable may add complexity and edge cases for queue fairness.

If "no" is the intended answer, the docs and invariants should be tightened to say that senior-first distress priority only governs new allocation, not already allocated but unclaimed junior proceeds.

## Fix Direction If Unintended

Avoid trying to patch only `claim()`. The actual invariant is about class allocation after state transitions.

Possible approaches:

1. On any transition into distress, rebalance `juniorCashAllocated` down to the current distressed `juniorCeil`, moving excess back to unallocated cash reserved for senior. This is semantically clean but needs care around already partially claimed junior requests.
2. Make `claimable()` cap junior claimability by the live distressed ceiling when `_distressed()` is true. This may be simpler but can make class FIFO math harder if earlier junior requests partially claimed before distress.
3. If allocation is intentionally vested, add an explicit regression test that reproduces this sequence and asserts the current behavior, then adjust product wording.

Any code fix should add a regression covering:

- junior allocated while healthy
- market becomes delinquent before claim
- `recoveredUSDC < seniorOwed`
- junior claim is blocked or reduced until senior is covered

## Other Generated Findings Not Recommended for Escalation

### Delayed default synchronization over-accrues senior obligation

Not recommended. Current code intentionally books elapsed senior interest before checking default. This is the Pashov R1 fix, not a new issue. Local regression `test_R1_AccrualBookedBeforeWindDown` asserts the behavior.

### Senior accrual compounds when elapsed time is split across calls

Not recommended. Pashov and the red-team framework explicitly mark update-driven compounding as accepted/by-design and protocol-faithful.

### Permissionless frequent accrual truncates senior interest

Mechanically true, but not ready for escalation. The generated PoC relies on very small remaining `seniorOwed` and extreme call frequency. It would need a realistic material-loss trace under expected share decimals, APRs, and principal sizes before it becomes useful.

### Elapsed senior interest repriced across rate-change boundaries

Not recommended on current evidence. The mock can change APR arbitrarily, but the generated report did not prove the production Wildcat APR-change path can be exercised between controller accruals in a way that violates intended semantics. Local design docs say senior tracks the facility's live base APR.

## Verification Performed

```bash
cd /home/kethcode/audits/wildcat-tranching/build
forge test --match-path test/AuditPoC.t.sol -vv
```

Result: 11 passed, 0 failed.

```bash
cd /home/kethcode/wildcat/faultline/runs/20260628T225808Z-build-48cc01d/legacy/20260628T225809Z-pristine-79266ce-2357fa/pocs/candidate-cda04171ea6ab68a/scratch
forge test --match-path test/CandidateCDA04171.t.sol --match-test test_ClaimUsesStaleJuniorAllocationAfterDistress -vvv
```

Result: 1 passed, 0 failed.
