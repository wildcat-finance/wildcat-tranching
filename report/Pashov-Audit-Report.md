# Solidity Auditor Report (Pashov Audit Group skill)

Tooling: `pashov/skills` `solidity-auditor` v3, installed to `~/.claude/skills`. The audit orchestrates 12 specialist attacker agents (math-precision, access-control, economic-security, execution-trace, invariant, periphery, first-principles, asymmetry, boundary, and the numerical/trust/flow gap-hunters). Run three times against the in-scope contracts (`build/src/`: WaterfallMath, TrancheController, TrancheToken, TrancheFactory; interfaces, lib, and tests excluded per the skill's scope rules). Agents ran on Sonnet; 36 agent-runs total.

The findings below are deduplicated across all three passes and triaged. Convergence was high: the same handful of issues recurred every pass. One finding was verified with an executable proof of concept.

## Confirmed

### SR-D (medium) — frozen-mark over-redemption during delinquency
`requestRedeem` sizes the wrapper-share redemption at the frozen mark: `shares4626 = _sharesOf(assetValue)` uses `_effPps()`, which during delinquency is the frozen `markPps`. But `underlyingVault.redeem(shares4626)` converts those shares at the live price. When the wrapper price has risen above the frozen mark (penalty accrual during delinquency), the exiter pulls out `wmtGot = assetValue × curPps/markPps` market tokens, i.e. more than its frozen-mark entitlement. It thereby books the unrealised penalty appreciation that the high-watermark valuation deliberately freezes, depleting the pool by more shares than its claim warrants and diluting holders who stay.

Verified: `build/test/AuditPoC.t.sol::test_PoC_FrozenMarkOverRedemptionDuringDelinquency` — a senior redeeming half its position during delinquency at curPps 1.2 / markPps 1.0 queues 180 wmt for a 150 frozen-mark claim and debits the pool 150 wrapper shares (should be 125).

Why it matters: it is a real deviation from the stated realised-only / high-watermark invariant ("unrealised penalty accrual is never booked as profit"). It is bounded (only the appreciation between markPps and curPps, only if the borrower later funds the withdrawal) and intra-tranche, not external theft. Severity medium.

Fix: size the redemption at the live price so the queued amount equals the frozen claim: `shares4626 = (assetValue * PPS_UNIT) / _curPps()`. Then `wmtGot == assetValue` regardless of the freeze, and stayers are not diluted.

Note: this resolves the most-flagged item across the passes. Many agents reported a "wmt-vs-USDC unit mismatch leaking to junior in `_allocate`." That is a **false positive**: Wildcat's market token is USD-par (the rebasing balance is the normalized USDC claim), so `seniorWmtQueued`/`recoveredUSDC` are 1:1 and `_allocate` does not leak. The genuine defect those agents were circling is SR-D, located in `requestRedeem`, not `_allocate`.

## High-confidence (code-clear, not PoC'd)

### SR-A (medium) — recovered USDC can be stranded; no sweep
`pokeRecovery` credits `recoveredUSDC` via a balance delta around `market.executeWithdrawal`. On the real Wildcat market `executeWithdrawal(account, expiry)` is permissionless, so anyone can execute the controller's batch directly; that USDC lands in the controller outside the delta measurement and is never credited to `recoveredUSDC`. There is no sweep or rescue, so it is stranded. The same gap strands any USDC sent directly to the controller and any recovery in excess of queued face. Fix: derive recovered cash from the controller's actual idle USDC balance rather than a per-call delta, and/or add a governance sweep for unallocated residual.

### SR-B (medium) — `TrancheFactory.deployTranches` is permissionless and under-validated
Any caller can occupy the canonical `controllerForMarket[market]` slot for a registered market, front-running the legitimate deployer with attacker-chosen `governance` / `sentinel` / `defaultDeclarer`, or with `governance == address(0)` (permanently bricks governance), or with a fake `underlyingVault` whose `market()` returns a real registered market (the factory validates the market, not that the vault is a canonical Wildcat wrapper). The first deployment wins; the legitimate one then reverts `TRANCHES_EXIST`. Fix: gate `deployTranches` to a protocol role (or the market's borrower), validate `underlyingVault` against the official wrapper factory, and require non-zero `governance`/`sentinel`.

## Low / informational / by-design

- **`requestRedeem` can burn shares for a zero-value request** when `shares4626 = _sharesOf(assetValue)` rounds to 0 (high pps, dust position): `require(assetValue > 0)` does not cover it. Add `require(shares4626 > 0)`.
- **`uint128(wmtGot)` unchecked cast** in the Request struct: safe at USDC scale, but add a checked cast for non-standard decimals.
- **No governance transfer/rotation**: a lost or compromised governance key permanently freezes admin functions. Consider a two-step transfer. (Operational; design choice.)
- **`declareDefault` / `setDefaultDeclarer` are un-timelocked and WindDown is one-way**: a one-way, irreversible wind-down trigger. This matches the intended ToU stickiness but concentrates power in the declarer; document it.
- **Stale-accrual at the default boundary**: `_syncDefault` runs before the interest update in `accrue`, so the pre-default interest sliver is dropped on the commit that trips wind-down. This is the documented conservative behaviour (favours junior/the pool), accepted.
- **Accrual compounds under repeated `accrue()`**: already adjudicated as expected and protocol-faithful (mirrors the market's update-driven compounding); not a vulnerability.
- **Senior transfers are sanction-gated only, not credential-gated**: the open access-policy decision (delegate per-LP credential checks to the market's hook). Pending product decision.
- **First-mover incentive in impaired exits**: a senior exiting during impairment crystallises a loss while stayers capture recovery; FIFO with no exit cap. Inherent to a withdrawal queue; SR-D amplifies it and its fix mitigates it.
- **markPps == 0 at construction** would disable the delinquency freeze; unreachable with a live wrapper (scaleFactor starts at RAY). Informational.
- **Controller self-sanctioned edge**: if the controller address itself were sanctioned in the Wildcat sentinel, `redeem`/`queueWithdrawal` revert or route to a Wildcat escrow, stranding recovery. Edge case; note for ops.

## Suite status
40 -> 45 local tests with the SR-D PoC added; the prior 44 (37 local + 3 mainnet-fork from the option-(1) work) plus `AuditPoC.t.sol`. The PoC asserts the current (buggy) SR-D behaviour and should be converted to a regression once SR-D is fixed.
