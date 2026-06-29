# Final Audit Comparison Report

Date: 2026-06-29

Branch / commit: `doc/fireline-audit` / `a5b855e`

## Inputs Compared

- `report/Pashov-Audit-Report.md`
- `report/Pashov-Audit-Report-Reaudit.md`
- `report/Fireline-Audit-Report-Abridged.md`
- `build/x-ray/x-ray.md`
- `build/x-ray/invariants.md`
- `build/fizz_data/report.md`
- Latest local `solidity-auditor` pass from this session

## Final Verdict

Not clean.

The original Pashov findings remain fixed. The Fireline outstanding issue is confirmed by the latest x-ray, solidity-auditor pass, and Medusa/Echidna fuzzing:

> Pre-distress junior cash allocation remains claimable after the market becomes distressed, even when current distress priority would reserve all recovered cash for senior.

Treat this as a release-blocking product/security decision. If senior-first priority applies until cash leaves the controller, this is a protocol bug. If allocation is intended to vest once assigned while healthy, the docs and tests currently overstate senior-first distress priority and must be narrowed.

## Prior Findings

| Item | Prior Status | Current Status | Notes |
| --- | --- | --- | --- |
| Pashov SR-D: frozen-mark over-redemption | Fixed | Still fixed | `requestRedeem()` sizes wrapper redemption at live PPS. Regression exists. |
| Pashov SR-A: stranded recovered USDC | Fixed | Still fixed | `recoveredUSDC = idle USDC + totalClaimedOut`; `sync()` exists. |
| Pashov SR-B: permissionless/under-validated factory | Fixed | Still fixed | Factory deploy is owner-gated with zero-address and registry checks. |
| Pashov R1: stale `seniorOwed` at distress gate | Fixed | Still fixed | `accrue()` books before default sync; `pokeRecovery()` and `sync()` accrue first. |
| Pashov R2/R3/R4/governance hygiene | Fixed | Still fixed | Two-step owner, borrower guards, cancel proposal, declarer/governance guards remain present. |
| Pashov `_allocate` underflow guard | Fixed | Still fixed | `_allocate()` returns early if recovered balance falls below existing allocation. |
| Fireline stale junior allocation after distress | Needs review | Confirmed open | Confirmed by x-ray `I-17`, latest auditor, and Fizz failing property. |

## Confirmed Open Issue

### F-01: Junior Allocation Vests Through Later Distress

Severity: Medium/High, depending on intended settlement semantics.

Current behavior:

1. Junior requests redemption while healthy.
2. USDC recovery arrives while healthy.
3. `_allocate()` assigns recovered cash to junior because the healthy reserve only considers queued senior face.
4. Market later becomes delinquent or enters wind-down.
5. `claimable()` still reads stale `juniorCashAllocated`.
6. `claim()` transfers USDC without revalidating current distress priority.

Relevant code:

- `_distressed()` says junior cash release is gated against the full senior obligation while distressed: `build/src/TrancheController.sol:156`
- `_allocate()` uses `seniorReserve = _distressed() ? seniorOwed : seniorWmtQueued`: `build/src/TrancheController.sol:393`
- `claimable()` reads monotonic `juniorCashAllocated`: `build/src/TrancheController.sol:408`
- `claim()` transfers without distress revalidation: `build/src/TrancheController.sol:418`

Current independent evidence:

- Fireline PoC shows a junior claim after delinquency while `recoveredUSDC < seniorOwed`.
- x-ray marks this exact gap as `I-17` and links it to async recovery allocation.
- Latest solidity-auditor re-found the same issue as stale junior allocation after distress.
- Fizz: `property_distressedJuniorAllocationReservesSeniorPriority` fails in both Medusa and Echidna.
- Medusa failing state: `recoveredUSDC = juniorCashAllocated`, `seniorOwed > recoveredUSDC`, `juniorCeiling = 0`.

This is not SR-D and not R1. SR-D was redemption sizing at frozen PPS. R1 was stale senior owed before allocation. Here senior owed is live; the stale value is the previously assigned junior allocation.

This is also not the old wmt-vs-USDC false positive. The issue is state transition and claim-time priority, not denomination conversion.

## Latest Solidity-Auditor Cross-Check

The latest auditor pass converged on the same core issue and produced these additional leads:

| Lead | Current Disposition |
| --- | --- |
| Distress reserve undercounts queued/already allocated senior cash | Covered by F-01/Fizz property; should be handled in the same fix design. |
| Stale junior allocation after distress | Confirmed open as F-01. |
| Delinquent junior deposit stale-mark dilution | Backlog / needs dedicated snapshot property. x-ray `I-16` marks a gap, but no final PoC was committed. |
| Frozen/live PPS residual stranding | Backlog / needs residual ghost model. x-ray `I-18` marks a gap. |
| Segmented accrual truncation / retroactive APR sampling | Backlog unless material loss is demonstrated. x-ray `I-19`/`I-20` mark temporal gaps; prior reports treat related compounding behavior as by-design. |
| Sanctioned-owner escrow timing and senior credential gating | Product / integration risk, not current release-blocking evidence. |

## Recommended Disposition

### If F-01 Is Unintended

Fix before production.

Preferred fix direction:

- Recompute or cap junior claimability under `_distressed()`.
- Ensure junior cannot claim cash above `min(juniorWmtQueued, max(0, recoveredUSDC - seniorCashAllocated - seniorOwed))` while distressed.
- Handle partially claimed junior requests explicitly.
- Add a Foundry regression for: healthy junior allocation -> delinquency before claim -> `recoveredUSDC < seniorOwed` -> junior claim blocked/reduced.
- Rerun Medusa/Echidna after the fix.

### If F-01 Is Intended

Document it explicitly.

Required wording/test changes:

- State that class allocation vests once assigned, even if the market later becomes distressed before claim.
- Narrow "senior-first" language to new allocation, not already allocated-but-unclaimed junior cash.
- Add a regression asserting the current behavior.
- Update x-ray/Fizz properties so they do not treat this as a violation.

## Final Release Gate

Current release status: blocked until F-01 is either fixed or explicitly accepted as vested-allocation semantics.

All previously reported Pashov actionable findings are closed in current code.
