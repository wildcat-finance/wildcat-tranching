# Re-Audit Report (Pashov solidity-auditor, post-fix cycle)

This is the second audit cycle, run after the first cycle's fixes landed. It re-runs the same `pashov/skills` `solidity-auditor` v3 process (the 12 specialist attacker agents) cold against the fixed code, with no hint of the prior findings, so the agents independently re-derive anything that survived.

**Re-audited commit:** `696a0120` (`wildcat-finance/wildcat-tranching`, PR #4), the post-fix baseline that resolved SR-D, SR-A, SR-B and the low items from the first cycle. In-scope: `build/src/` (WaterfallMath, TrancheController, TrancheToken, TrancheFactory); interfaces, lib, and tests excluded per the skill's scope rules. Agents ran on Sonnet.

**Pass status.** Pass 1 (12 agent-runs against `696a0120`) is the basis of the findings below. Pass 2 (12 agent-runs, cold) was then run against the post-R1/R2/R3 hash `f1ff690` (PR #5), with the agent bundles rebuilt from the fixed source; its results are in the "Pass 2 confirmation sweep" section at the end. Pass 3 was deliberately not run (work was scoped to stop after pass 2); convergence across passes 1 and 2 was high enough that a third pass is expected to re-confirm rather than extend the set.

## Validation of the first-cycle fixes

The headline first-cycle findings were not re-discovered as live bugs against `696a0120`:

- **SR-D (frozen-mark over-redemption):** surfaced only as "already fixed, verified in tests." No agent found a live over-redemption path; `requestRedeem` sizing the wrapper redemption at the live price holds.
- **SR-A (stranded recovery):** not re-found. The balance-derived `recoveredUSDC` plus permissionless `sync()` closes it.
- **SR-B (permissionless / under-validated factory):** not re-found. The owner gate plus zero-address validation holds.

The most-repeated agent claim across passes was again a **wmt-vs-USDC unit mismatch** (variously framed as "junior leak in `_allocate`," "excess USDC stranded when wmt appreciates," or "FIFO cap denominated in the wrong unit"). This remains a **false positive** for the same reason documented in the first cycle: the Wildcat market token is USD-par (its rebasing balance is the normalized USDC claim), so `seniorWmtQueued` / `juniorWmtQueued` and `recoveredUSDC` are 1:1 and the FIFO arithmetic does not leak. One periphery agent independently traced the live Wildcat `queueWithdrawal` / `executeWithdrawal` semantics and reached the same conclusion (queued normalized tokens settle 1:1 in USDC, with no in-queue interest accrual).

## New findings (this cycle), all fixed

These were genuinely new, code-clear, and convergent across multiple lenses. All three are fixed in the follow-up PR and carry a regression in `build/test/AuditPoC.t.sol`.

### R1 (low/medium) - RESOLVED - stale `seniorOwed` at the distress gate

Root cause (two coupled defects, same fix family):

1. `accrue()` ran `_syncDefault()` **before** the interest block, so the commit that trips wind-down froze `seniorOwedAtDefault` at the pre-accrual value, dropping the final period's senior interest.
2. `pokeRecovery`, `sync`, `checkDefault`, and `declareDefault` reached `_allocate()` (or the wind-down freeze) **without** an `accrue()` first, so the distress gate read a stale `seniorOwed`.

Because the distress gate releases junior cash only above `seniorOwed` (`juniorCeil = recoveredUSDC - seniorOwed`), an understated `seniorOwed` enlarges the junior ceiling and leaks recovery to junior ahead of senior priority. The leak equals the senior interest accrued since the last `accrue()`; over a long delinquency window in which only `pokeRecovery` is called, that can be the full window's interest. The first cycle had logged this as "stale-accrual at the default boundary, accepted as conservative." The re-audit's sharper analysis shows the direction of harm is toward junior, not toward the pool, so it is a senior-priority leak rather than a conservative rounding, and it is fixed rather than accepted.

**Fix.** `accrue()` now books interest while still Active and calls `_syncDefault()` last; `checkDefault` and `declareDefault` route through `accrue()`; `pokeRecovery` and `sync` call `accrue()` before crediting recovery. The distress reserve is therefore always the live obligation. Regression: `test_R1_AccrualBookedBeforeWindDown` (a full year elapses with no interaction, then `declareDefault`; `seniorOwedAtDefault` is the accrued 330, not the stale 300).

### R2 (low) - RESOLVED - single-step factory ownership transfer

`TrancheFactory.transferOwner` moved ownership atomically, inconsistent with the two-step governance rotation already present in `TrancheController`. A mistyped or uncontrolled successor would strand deploy rights (recoverable only by deploying a fresh factory).

**Fix.** Two-step `transferOwner` (propose) plus `acceptOwner` (successor confirms), mirroring `proposeGovernance` / `acceptGovernance`. Regression: `test_R2_FactoryTwoStepOwner`.

### R3 (informational) - RESOLVED - missing zero-address `borrower` guard

`borrower` was not validated against the zero address in either the controller constructor or `deployTranches`, yet it keys every `sentinel.isSanctioned(borrower, account)` and `sentinel.createEscrow(borrower, account, asset)` call. Low impact (the factory is owner-gated and a real borrower is always non-zero), but cheap defense-in-depth consistent with the existing governance/sentinel guards.

**Fix.** `require(p.borrower != address(0), "ZERO_BORROWER")` in both the constructor and `deployTranches`. Regression: `test_R3_ZeroBorrowerRejected`. (The fork harness, which set `borrower = address(0)` while `sentinel = address(0)`, was updated to a non-zero dummy; `borrower` is unread there because `_isSanctioned` short-circuits on a zero sentinel.)

## Considered, not changed

### Permit2 infinite allowance (informational, product decision)

`TrancheToken` inherits Solady ERC20's default `_givePermit2InfiniteAllowance() == true`, granting the canonical Permit2 contract a standing allowance over all tranche balances. Several access-control runs framed this as a drain vector. It is not: Permit2 only moves tokens against an owner-signed permit, and every resulting transfer still passes through `beforeTrancheTransfer`, which enforces sanctions on both parties and the junior whitelist on the recipient. So Permit2 cannot bypass the transfer restrictions. Disabling it (overriding the hook to return `false`) would remove gasless-approval composability with no security gain on senior (freely transferable, sanction-gated) and only a marginal surface reduction on junior (already whitelist-gated). This is left as a product decision, in the same bucket as the open senior-credential-gating question, and is not changed unilaterally.

## Recurring by-design / accepted items (re-confirmed, unchanged)

The agents re-surfaced the same design-level observations as the first cycle. Each was already adjudicated; the re-audit does not change the disposition:

- **Senior accrual rate tracks the live market base APR.** The borrower controls `annualInterestBips`; lowering it lowers the senior target. This is the intended definition (senior earns a share of what the market pays, capped at the base APR) and mirrors the already-accepted F1 "accrual is update-driven, by design." The lack of time-weighting is the same point-in-time accrual the underlying market itself uses.
- **Non-distressed `_allocate` reserves only queued senior face.** Unqueued senior is protected only once distressed. Documented design (the in-code comment is accurate); the distress gate is what enforces senior priority during stress.
- **Junior redemption is uncapped in WindDown** (no subordination floor). The cash gate in `_allocate` enforces priority; burned shares cannot pull cash ahead of senior.
- **Rounding dust favors the pool / stayers** (double floor division in `requestRedeem`). Conservative and sub-unit.
- **`markPps == 0` at construction** would disable the delinquency freeze; unreachable with a live wrapper (scaleFactor starts at RAY).
- **`claim()` is permissionless.** Funds always route to the request owner or, if sanctioned, to the Wildcat escrow; permissionless claim is keeper-friendly and cannot misdirect funds.
- **No request cancellation; one-way `declareDefault`; unbounded `requests` array.** Queue semantics and ToU stickiness; request access is O(1) with no on-chain enumeration.

## Suite status

51 tests passing (48 local + 3 mainnet-fork), including the 128k-call stateful invariants (conservation, junior-first-loss, no-over-distribution). The first cycle's 48 plus the three new R1/R2/R3 regressions.

## Pass 2 confirmation sweep (post-fix code `f1ff690`)

Pass 2 ran the same 12 cold specialist agents against the R1/R2/R3-fixed source (`f1ff690`), bundles rebuilt from the fixed contracts. Purpose: confirm R1/R2/R3 are resolved and surface any regression or new issue.

**R1, R2, R3 confirmed resolved.** No agent re-derived the accrual-ordering leak, the single-step factory ownership, or the missing zero-borrower guard. The reordered `accrue()` (interest before `_syncDefault`), the `accrue()` calls in `pokeRecovery`/`sync`/`checkDefault`/`declareDefault`, the two-step `acceptOwner`, and the `ZERO_BORROWER` guards are all present in the audited source and were not flagged.

**Convergent false positive re-confirmed.** The wmt-vs-USDC / scaleFactor "surplus stranded or leaked to junior" claim recurred across the math, invariant, numerical-gap, and periphery lenses. It is the same false positive documented in the first cycle: the v-wmtUSDC wrapper is USD-par (its rebasing balance is the normalized USDC claim, so `convertToAssets` already absorbs the market scaleFactor and `seniorWmtQueued`/`recoveredUSDC` are 1:1). One periphery agent independently re-derived the live Wildcat `queueWithdrawal`/`executeWithdrawal` semantics mid-pass and explicitly retracted the finding. The three mainnet-fork tests exercise the real wrapper and market and pass.

**New items surfaced in pass 2 (all LOW or informational; none changed).** Recorded for a future cycle; none is high-severity and none is an external-theft path:

- **R4 (low, governance ergonomics): `executeSeniorShareBips` is permissionless and has no cancel path.** Permissionless execution after the timelock is by design (the 2-day timelock is the gate, not the caller identity). The genuine gap is that a pending proposal can only be overwritten (resetting the 2-day clock), not cancelled, so a fat-fingered proposal could be executed by a watcher in the block before a corrective re-proposal lands. Recommendation (deferred): add `cancelSeniorShareProposal()` gated to `onlyGovernance` that zeroes `seniorShareEta`.
- **Low: `proposeGovernance` lacks the zero-address guard** that `TrancheFactory.transferOwner` has. Recoverable by re-proposing (a zero `pendingGovernance` can never accept), so impact is a transient stuck-pending state. Recommendation (deferred): mirror the factory's `require(next != address(0))`.
- **Low: `setDefaultDeclarer` emits no event and has no zero-address guard,** unlike its peer setters. Recommendation (deferred): add an event and a zero-check for monitorability.
- **Accepted / by-design (re-confirmed, unchanged):** premature `declareDefault` by a junior-aligned declarer freezing `seniorOwedAtDefault` low (governance-trust; `declareDefault`/`setDefaultDeclarer` power is the documented, accepted concentration); borrower control of the market base APR driving the senior accrual rate (the F1 family, accepted as mirroring the market's own update-driven accrual); junior redemption uncapped in WindDown (cash gate enforces priority); rounding dust to the pool; `markPps == 0` at construction (unreachable with a live wrapper).
- **Informational dependency/edge notes:** `claim()` routes a sanctioned owner's USDC to the Wildcat escrow, and a permanently reverting `sentinel.createEscrow` (or a USDC blacklist-and-destroy against the controller) is an external-dependency failure that could strand that USDC; both are extreme-edge and outside the controller's trust boundary. A cheap defensive `if (seniorCashAllocated + juniorCashAllocated >= recoveredUSDC) return;` guard in `_allocate` would harden the USDC-destroy edge; deferred.

## Disposition

The first-cycle fixes hold across two re-audit passes. The re-audit found one real senior-priority leak (R1), one consistency/safety gap (R2), and one defensive guard (R3), all fixed and regression-tested in PR #5, plus one informational product decision (Permit2). Pass 2 against the fixed code re-confirmed R1/R2/R3 resolved and surfaced only LOW/informational items (R4 and three minor governance-hygiene gaps), deferred to a future cycle with recommendations above. No high-severity issue and no external-theft path was found in either audit cycle. Pass 3 was not run (scoped to stop after pass 2).
