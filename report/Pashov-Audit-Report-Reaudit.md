# Re-Audit Report (Pashov solidity-auditor)

This is the second audit cycle, run after the first cycle's fixes landed. It re-runs the same `pashov/skills` `solidity-auditor` v3 process cold against the fixed code, with no hint of the prior findings, so the agents independently re-derive anything that survived.

**Method.** 12 specialist attacker agents (math-precision, access-control, economic-security, execution-trace, invariant, periphery, first-principles, asymmetry, boundary, and the numerical/trust/flow gap-hunters), run three times (36 agent-runs, Sonnet) against `build/src/` (WaterfallMath, TrancheController, TrancheToken, TrancheFactory); interfaces, lib, and tests excluded per the skill's scope rules. Findings are deduplicated and triaged across all passes. Convergence was high: the same handful of items recurred every pass.

**Scope.** The first cycle (see `report/Pashov-Audit-Report.md`) audited the option-(1) redemption model and resolved SR-A, SR-B, SR-D and the low items. This re-audit ran against that post-fix code. Every actionable item it surfaced is now fixed, each with a regression in `build/test/AuditPoC.t.sol`. The suite is 55 tests (52 local + 3 mainnet-fork), all passing, including the 128k-call stateful invariants (conservation, junior-first-loss, no-over-distribution).

## First-cycle fixes hold

The headline first-cycle findings were not re-discovered as live bugs:

- **SR-D (frozen-mark over-redemption):** no agent found a live over-redemption path; sizing the wrapper redemption at the live price holds.
- **SR-A (stranded recovery):** not re-found. The balance-derived `recoveredUSDC` plus the permissionless `sync()` closes it.
- **SR-B (permissionless / under-validated factory):** not re-found. The owner gate plus zero-address validation holds.

## Findings (all resolved)

### R1 (low/medium) - stale `seniorOwed` at the distress gate

Two coupled defects with one fix family: `accrue()` ran `_syncDefault()` before the interest block (so the commit that tripped wind-down froze `seniorOwedAtDefault` at the pre-accrual value, dropping the final period's senior interest), and `pokeRecovery` / `sync` / `checkDefault` / `declareDefault` reached `_allocate()` (or the wind-down freeze) without accruing first (so the distress gate read a stale `seniorOwed`). Because the gate releases junior cash only above `seniorOwed` (`juniorCeil = recoveredUSDC - seniorOwed`), an understated `seniorOwed` enlarges the junior ceiling and leaks recovery to junior ahead of senior priority. The leak equals the senior interest accrued since the last `accrue()`.

**Fix.** `accrue()` books interest while still Active and calls `_syncDefault()` last; `checkDefault` and `declareDefault` route through `accrue()`; `pokeRecovery` and `sync` call `accrue()` before crediting recovery. The distress reserve is therefore always the live obligation. Regression: `test_R1_AccrualBookedBeforeWindDown`.

### R2 (low) - single-step factory ownership

`TrancheFactory.transferOwner` moved ownership atomically, inconsistent with the controller's two-step governance rotation. A mistyped or uncontrolled successor would strand deploy rights.

**Fix.** Two-step `transferOwner` (propose) plus `acceptOwner` (successor confirms), mirroring `proposeGovernance` / `acceptGovernance`. Regression: `test_R2_FactoryTwoStepOwner`.

### R3 (informational) - missing zero-address `borrower` guard

`borrower` was not validated against the zero address, yet it keys every `sentinel.isSanctioned(borrower, account)` and `sentinel.createEscrow(borrower, account, asset)` call.

**Fix.** `require(p.borrower != address(0), "ZERO_BORROWER")` in both the constructor and `deployTranches`. Regression: `test_R3_ZeroBorrowerRejected`.

### R4 (low) - no cancel path for a pending senior-share proposal

Senior-share execution is permissionless once the timelock elapses, so a mis-entered proposal could only be overwritten (which resets the clock), not aborted; a watcher could execute the bad proposal in the block before a corrective re-proposal landed.

**Fix.** `cancelSeniorShareProposal()` (onlyGovernance) clears `pendingSeniorShareBips` and `seniorShareEta`, so a pending proposal can be aborted outright. Regression: `test_R4_CancelSeniorShareProposal`.

### Governance hygiene

`proposeGovernance` now rejects `address(0)` (mirroring `TrancheFactory.transferOwner`), and `setDefaultDeclarer` rejects `address(0)` and emits `DefaultDeclarerSet` for monitorability of this default-trigger role. Regressions: `test_ProposeGovernanceRejectsZero`, `test_SetDefaultDeclarerGuarded`.

### Defensive guard - `_allocate` underflow

`recoveredUSDC` is balance-derived, so a forced external balance drop (for example a USDC blacklist-and-destroy against the controller) could push it below what is already allocated and brick `_allocate` on underflow. `_allocate` now returns early when `recoveredUSDC <= seniorCashAllocated + juniorCashAllocated`, keeping allocation and claims live. Regression: `test_AllocateSurvivesForcedBalanceDrop`.

## Considered, not changed

### Permit2 infinite allowance (informational, product decision)

`TrancheToken` inherits Solady ERC20's default `_givePermit2InfiniteAllowance() == true`, granting the canonical Permit2 contract a standing allowance over all tranche balances. This is not a drain vector: Permit2 only moves tokens against an owner-signed permit, and every resulting transfer still passes through `beforeTrancheTransfer`, which enforces sanctions on both parties and the junior whitelist on the recipient, so the transfer restrictions cannot be bypassed. Disabling it would remove gasless-approval composability with no security gain on senior (freely transferable, sanction-gated) and only a marginal surface reduction on junior (already whitelist-gated). Left as a product decision, in the same bucket as the open senior-credential-gating question.

## Re-confirmed false positive

The most-repeated agent claim across every pass was a **wmt-vs-USDC denomination mismatch** (variously framed as "junior leak in `_allocate`", "scaleFactor surplus stranded", or "senior underpaid on batch interest"). It is a false positive: the Wildcat market token is USD-par (its rebasing balance is the normalized USDC claim, so `convertToAssets` already absorbs the market scaleFactor and `seniorWmtQueued` / `recoveredUSDC` are 1:1). Multiple agents independently traced the live `queueWithdrawal` / `executeWithdrawal` semantics and retracted the finding mid-pass. The three mainnet-fork tests exercise the real wrapper and market and pass. A related claim that `_allocate`'s junior ceiling should also subtract `seniorCashAllocated` is likewise incorrect: junior can only queue against positive `jv`, and junior redemption provably preserves `realisedValue >= seniorOwed` (senior stays pool-backed), so the proposed change would instead strand junior's own settled batch proceeds; the conservation and junior-first-loss invariants confirm no over-distribution.

## Accepted by-design (re-confirmed)

The agents re-surfaced the same design-level observations as the first cycle; dispositions are unchanged:

- **Senior accrual rate tracks the live market base APR.** The borrower controls `annualInterestBips`; lowering it lowers the senior target. This is the intended definition (senior earns a share of what the market pays, capped at the base APR) and mirrors the accepted F1 update-driven accrual.
- **Non-distressed `_allocate` reserves only queued senior face.** Unqueued senior is protected once distressed; the distress gate is what enforces senior priority during stress.
- **Junior redemption is uncapped in WindDown** (no subordination floor). The cash gate enforces priority; burned shares cannot pull cash ahead of senior.
- **Deposits at the frozen mark during delinquency** under-credit the depositor relative to live value (the depositor over-pays). This follows from the realised-only valuation and disadvantages only the voluntary depositor.
- **ERC-4626 view surface (`trancheTotalAssets` / `pricePerShare`) uses the frozen mark during delinquency,** so it can understate value to integrators in a narrow impairment window. Redemption is async (ERC-7540-style), so the tranches expose a 4626 view surface, not a synchronous vault; the conservative valuation is intentional.
- **Rounding dust favors the pool; `markPps == 0` at construction is unreachable with a live wrapper; the `requests` array is unbounded but accessed O(1); the transfer hook and `claim` escrow depend on the trusted, immutable sentinel.** All informational.

## Disposition

The first-cycle fixes hold. The re-audit surfaced one senior-priority leak (R1), several consistency and defensive items (R2, R3, R4, governance hygiene, the `_allocate` guard), and one informational product decision (Permit2). Every actionable item is fixed and regression-tested; the remaining items are accepted by-design or re-confirmed false positives. No high-severity issue and no external-theft path was found in either audit cycle.
