# Solidity Auditor Report (Pashov Audit Group skill)

Tooling: `pashov/skills` `solidity-auditor` v3, installed to `~/.claude/skills`. The audit orchestrates 12 specialist attacker agents (math-precision, access-control, economic-security, execution-trace, invariant, periphery, first-principles, asymmetry, boundary, and the numerical/trust/flow gap-hunters). Run three times against the in-scope contracts (`build/src/`: WaterfallMath, TrancheController, TrancheToken, TrancheFactory; interfaces, lib, and tests excluded per the skill's scope rules). Agents ran on Sonnet; 36 agent-runs total.

The findings below are deduplicated across all three passes and triaged. Convergence was high: the same handful of issues recurred every pass. One finding was verified with an executable proof of concept.

**Audited commit:** `0bc5bf2` (`wildcat-finance/wildcat-tranching`, PR #3) — the option-(1) redemption model. **Resolution:** all findings were addressed in the follow-up fixes PR; status is annotated inline below. A second full 3-pass run was then executed against the fixed code (see "Re-audit" at the end).

Status summary: SR-D fixed, SR-A fixed, SR-B fixed, low items fixed (zero-redeem guard, checked cast, governance rotation); the remaining items are accepted/by-design and documented.

## Confirmed

### SR-D (medium) — RESOLVED — frozen-mark over-redemption during delinquency
`requestRedeem` sizes the wrapper-share redemption at the frozen mark: `shares4626 = _sharesOf(assetValue)` uses `_effPps()`, which during delinquency is the frozen `markPps`. But `underlyingVault.redeem(shares4626)` converts those shares at the live price. When the wrapper price has risen above the frozen mark (penalty accrual during delinquency), the exiter pulls out `wmtGot = assetValue × curPps/markPps` market tokens, i.e. more than its frozen-mark entitlement. It thereby books the unrealised penalty appreciation that the high-watermark valuation deliberately freezes, depleting the pool by more shares than its claim warrants and diluting holders who stay.

Verified at baseline: a senior redeeming half its position during delinquency at curPps 1.2 / markPps 1.0 queued 180 wmt for a 150 frozen-mark claim and debited the pool 150 wrapper shares (should be 125).

**Resolved:** `requestRedeem` now sizes the redemption at the live price (`shares4626 = assetValue * PPS_UNIT / _curPps()`), so `wmtGot == assetValue` and the appreciation stays in the pool for the residual. Regression: `build/test/AuditPoC.t.sol::test_FrozenMarkRedemptionSizedAtLivePrice` (queues exactly 150, redeems 125).

Why it matters: it is a real deviation from the stated realised-only / high-watermark invariant ("unrealised penalty accrual is never booked as profit"). It is bounded (only the appreciation between markPps and curPps, only if the borrower later funds the withdrawal) and intra-tranche, not external theft. Severity medium.

Fix: size the redemption at the live price so the queued amount equals the frozen claim: `shares4626 = (assetValue * PPS_UNIT) / _curPps()`. Then `wmtGot == assetValue` regardless of the freeze, and stayers are not diluted.

Note: this resolves the most-flagged item across the passes. Many agents reported a "wmt-vs-USDC unit mismatch leaking to junior in `_allocate`." That is a **false positive**: Wildcat's market token is USD-par (the rebasing balance is the normalized USDC claim), so `seniorWmtQueued`/`recoveredUSDC` are 1:1 and `_allocate` does not leak. The genuine defect those agents were circling is SR-D, located in `requestRedeem`, not `_allocate`.

## High-confidence (code-clear, not PoC'd)

### SR-A (medium) — RESOLVED — recovered USDC could be stranded; no sweep
`pokeRecovery` credited `recoveredUSDC` via a balance delta around `market.executeWithdrawal`. On the real Wildcat market `executeWithdrawal(account, expiry)` is permissionless, so anyone can execute the controller's batch directly; that USDC lands in the controller outside the delta measurement and was never credited to `recoveredUSDC`. There was no sweep or rescue, so it was stranded. The same gap stranded any USDC sent directly to the controller and any recovery in excess of queued face.

**Resolved:** recovery is now derived from the actual balance: `recoveredUSDC = baseAsset.balanceOf(this) + totalClaimedOut` (a new cumulative `totalClaimedOut` is incremented on every claim). `pokeRecovery` uses this, and a new permissionless `sync()` credits any USDC that arrived outside `pokeRecovery`. Regression: `AuditPoC.t.sol::test_SR_A_ExternalWithdrawalNotStranded`.

### SR-B (medium) — RESOLVED — `TrancheFactory.deployTranches` permissionless and under-validated
Any caller could occupy the canonical `controllerForMarket[market]` slot for a registered market, front-running the legitimate deployer with attacker-chosen `governance` / `sentinel` / `defaultDeclarer`, or with `governance == address(0)` (bricks governance), or with a fake `underlyingVault` whose `market()` returns a real registered market (the factory validated the market, not the vault).

**Resolved:** `deployTranches` is now owner-gated (`owner` set at factory deploy, two-step `transferOwner`), and rejects `governance == address(0)` and `sentinel == address(0)`. The owner gate also closes the fake-vault vector (only the trusted owner deploys). `TrancheController`'s constructor also requires non-zero governance. Regression: `AuditPoC.t.sol::test_SR_B_DeployTranchesGated`.

## Low / informational / by-design

- **FIXED — `requestRedeem` could burn shares for a zero-value request** when the share conversion rounds to 0: now guarded by `require(shares4626 > 0, "ZERO_REDEEM")`.
- **FIXED — `uint128(wmtGot)` unchecked cast**: now `require(wmtGot <= type(uint128).max, "WMT_OVERFLOW")` before the cast.
- **FIXED — No governance transfer/rotation**: added a two-step `proposeGovernance` / `acceptGovernance`, and the constructor now requires non-zero governance.
- **`declareDefault` / `setDefaultDeclarer` are un-timelocked and WindDown is one-way**: a one-way, irreversible wind-down trigger. This matches the intended ToU stickiness but concentrates power in the declarer; documented, not changed.
- **Stale-accrual at the default boundary**: `_syncDefault` runs before the interest update in `accrue`, so the pre-default interest sliver is dropped on the commit that trips wind-down. This is the documented conservative behaviour (favours junior/the pool), accepted.
- **Accrual compounds under repeated `accrue()`**: already adjudicated as expected and protocol-faithful (mirrors the market's update-driven compounding); not a vulnerability.
- **Senior transfers are sanction-gated only, not credential-gated**: the open access-policy decision (delegate per-LP credential checks to the market's hook). Pending product decision.
- **First-mover incentive in impaired exits**: a senior exiting during impairment crystallises a loss while stayers capture recovery; FIFO with no exit cap. Inherent to a withdrawal queue; SR-D amplifies it and its fix mitigates it.
- **markPps == 0 at construction** would disable the delinquency freeze; unreachable with a live wrapper (scaleFactor starts at RAY). Informational.
- **Controller self-sanctioned edge**: if the controller address itself were sanctioned in the Wildcat sentinel, `redeem`/`queueWithdrawal` revert or route to a Wildcat escrow, stranding recovery. Edge case; note for ops.

## Suite status
51 tests, all passing (48 local + 3 mainnet-fork). The SR-D PoC was converted to a regression asserting the fix, and SR-A / SR-B / governance-rotation each gained a regression in `AuditPoC.t.sol`. The second audit cycle added three more regressions (R1 / R2 / R3); see the re-audit report.

## Re-audit
After the fixes, the same `solidity-auditor` process was re-run cold against the fixed code (`696a0120`). The first-cycle fixes held; the re-audit surfaced one senior-priority leak (R1, stale `seniorOwed` at the distress gate), one consistency gap (R2, single-step factory ownership), and one defensive guard (R3, zero-address borrower), all now fixed and regression-tested. Full write-up in `report/Pashov-Audit-Report-Reaudit.md`.
