# Wildcat In-House Tranching: Effort Assessment

*Prepared 2026-06-27. Sources: code review of `v2-protocol`, `contracts-tranches` (Strata), `royco-dawn`, `USP` (Pareto); on-chain reads via mainnet RPC; Strata×Wildcat×Wintermute proposal; Strata/Pareto/Royco docs.*

---

## Bottom line

Consider a Wildcat-built MVP that covers the common ground of the three: two share classes (senior/junior) over a Wildcat market, a yield waterfall (senior priority plus floor, junior residual plus risk premium), a first-loss waterfall (junior absorbs losses first), per-tranche NAV accounting, a subordination/coverage ratio, async redemptions through Wildcat's withdrawal queue, and a factory plus roles. That scopes to roughly:

> **~4–6 engineer-months of build + a ~$80–150k external audit, ≈ 3.5–5 months calendar with 2 strong Solidity engineers.**

Reaching full feature parity with Strata/Royco (adaptive yield-split curves, depeg/valuation handling, isolated liquid-junior/illiquid-senior liquidity routing, fixed-term recovery state machine, recursive tranching/Pendle) adds another ~3–5 months, and most of it is not needed for the Wintermute facility.

The novel, security-critical logic is small, **~600–2,000 lines** in every one of these protocols. The cost is not the line count. It is (a) getting the credit-loss waterfall right (Wildcat's risk is lumpy default risk rather than smooth mark-to-market, and none of the three handle this exact case), (b) wiring redemptions through Wildcat's semi-liquid batched withdrawal queue (no reusable template exists), and (c) testing/audit to your existing bar.

The fastest path to the same outcome with zero engineering is the Strata partnership already on the table. Building in-house buys control, no revenue share, and tighter UX, at the cost of the quarter-plus above and owning the audit/risk surface indefinitely.

---

## 1. The three reference protocols

| Repo | What it really is | True senior/junior tranching engine in the repo? |
|---|---|---|
| **Strata** (`contracts-tranches`) | A CDO-style risk-tranching layer over any ERC4626/yield asset. Splits one underlying into senior + junior ERC4626 tranche tokens. | Yes, fully. Three accounting engines (continuous `Accounting`, `DiscreteAccounting`, `DYSAccounting`), cooldown silos, isolated dual-strategy routing. |
| **Royco Dawn** (`royco-dawn`) | A from-scratch senior/junior tranching protocol for yield assets. Not the order-matching/incentive "Royco Markets"; there is no weiroll/offers/auction code at all. | Yes, fully, and the most sophisticated of the three. Dual-NAV (raw vs effective), impermanent-loss tracking with prioritized recovery, perpetual↔fixed-term state machine, adaptive yield-share curve, self-liquidation bonus. |
| **Pareto** (`USP`) | A synthetic dollar (USP) plus a first-loss staking vault (sUSP). It buys the senior (AA) tranche of external Idle/Pareto Credit Vaults and adds its own first-loss layer via sUSP. | No, not in this repo. The actual AA/BB tranche engine (the part analogous to Strata/Royco) lives in Idle's CDO contracts, which are not in the zip. USP only consumes it (`depositAA`, `virtualPrice(AATranche())`). |

**Implication:** "what all three do" really means "what Strata and Royco do natively." Pareto's distinctive contributions that are in-repo take a different shape: a $1-pegged senior (the stablecoin itself), a staked first-loss buffer (sUSP), and an epoch redemption queue with an undercollateralized pro-rata fallback. Replicating Pareto-style epoch-based credit vaults with per-borrower AA/BB tranches would mean building that engine from the docs rather than porting it from this code.

**On-chain note:** the `v-wmtUSDC` 4626 (`0xf654…`) is Wildcat's own `Wildcat4626Wrapper`, not a Strata contract. It wraps `0xC949…` ("Wintermute Trading USD Coin", ~$69.65M, 8.5% APR), a different market from `0x50ebdf…` ("Wintermute USD Coin", ~$2.23M), on a different borrower wallet. The tranching targets the former, the wrapped facility.

---

## 2. The common ground (the intersection to rebuild)

Strata and Royco converge on the same eight primitives. This is the spec for an in-house "covers what they do" MVP:

1. **Two share classes** (senior + junior) over a single yield-bearing underlying (an ERC4626).
2. **Yield waterfall.** Senior gets priority and a floor/target rate, junior gets the residual, and senior pays junior a risk premium (equivalently, junior funds any senior shortfall).
3. **Loss waterfall.** Junior is first-loss; losses cascade junior → (reserve) → senior.
4. **Per-tranche NAV accounting,** marked off the underlying's value and re-synced on every interaction.
5. **Subordination / coverage ratio.** Caps senior leverage over junior and gates deposits/withdrawals near the floor (Strata blocks junior exit and senior deposit; Royco enforces a coverage invariant plus utilization).
6. **Async / semi-liquid redemption,** via cooldown silos (Strata) or a request/execute queue (Royco), because the underlying isn't instantly liquid.
7. **Governance:** who sets the senior rate/benchmark, pauses, manages the reserve, and handles shortfall/default, plus timelocks and guardians.
8. **A factory** to deploy a tranche set per underlying.

Everything beyond this list is differentiation, not common ground: Royco's fixed-term recovery state machine, IL recovery, self-liquidation, recursive tranching, Pendle; Strata's three accounting modes, daily-loss floor, depeg/valuation oracle, isolated liquidity routing, and its ~9 per-protocol strategy adapters.

---

## 3. What Wildcat already has (and where tranching attaches)

You are not starting from zero, and tranching is not a protocol fork. It is an app-layer vault stack on top of an unchanged market.

**Reuse directly:**
- **`Wildcat4626Wrapper.sol`**, the deployed `v-wmtUSDC`. It already solves the two hardest integration problems: rebasing→non-rebasing conversion via `scaleFactor`, and pass-through sanctions, with scaled-delta verification against the market. This is ~80% of one tranche's plumbing; a tranche vault is this wrapper with two share classes and a waterfall added.
- **`scaleFactor()` as an accrual oracle.** Interest accrues monotonically, so computing the yield to split senior/junior is straightforward (`Δ(scaledBalance × scaleFactor)`). That is easier than in the three reference protocols, which must diff a noisy ERC4626 share price.
- **`MathUtils` (ray/bip), `SafeCastLib`, `FIFOQueue`, `ReentrancyGuard`**, Solady ERC20/ERC4626/permit bases.
- **The permissionless, arch-gated, one-per-market factory pattern** (`Wildcat4626WrapperFactory`), which a `TrancheVaultFactory` can copy.
- **The sentinel integration pattern** for re-enforcing sanctions at the vault layer.
- **Engineering rigor already in place:** invariant tests, fuzzing, the a16z ERC4626 suite, external audits. A new component is expected to clear the same bar.

**Architectural seam:** tranching cannot live in the hooks system. Hooks are reactive/restrictive (they can revert, and only tweak APR/reserve), so they cannot route funds or hold dual-class accounting. The tranche logic must be a separate vault that holds the market token (or v-wmtUSDC) and issues senior/junior shares. Hooks can assist (for example, restricting a market so only the tranche vault may deposit), but that is optional.

---

## 4. The Wildcat-specific hard parts (where the months actually go)

These are the three areas with the least reusable code and the most design and risk:

1. **Credit-loss vs mark-to-market loss.** Strata/Royco/Pareto tranche liquid yield where loss equals a falling ERC4626 share price, detected automatically. Wildcat is undercollateralized private credit: the upside (interest) is smooth and easy to tranche, but loss is lumpy and discrete. Delinquency (penalty APR, delayed withdrawals, principal still intact) is distinct from default or closure with a shortfall (principal impaired). You must define the loss trigger (When is the loan impaired? Who declares it? How is a delayed or partial recovery socialized back?) before any junior-first write-down can be coded. This is a design and probably legal question rather than a coding one, and it sits at the center of the work.
2. **Redemptions through a semi-liquid, batched, pro-rata, time-delayed queue.** Wildcat withdrawals are queued into expiry-dated batches, paid as liquidity allows, with a FIFO unpaid-batch queue and pro-rata fills. A tranche vault must `queueWithdrawal`, wait for expiry, then `executeWithdrawal`, and allocate the partial, delayed proceeds across senior/junior per the waterfall (senior first). None of the three reference protocols handle anything this complex on the redemption side; they assume instant or simple-cooldown ERC4626 liquidity. On the redemption side this is the largest block of net-new design.
3. **Per-user KYC/sanctions at the vault layer.** When lenders are pooled into a tranche vault, the market only sees the vault as the lender, so per-user credential and sanctions visibility is lost at the market level. The existing 4626 wrapper already shows the pattern (re-check the sentinel on every entry and on share transfers); a permissioned senior/junior product re-enforces per-user credential gating in the vault too.

---

## 5. Effort estimate

Assumes 2 strong Solidity engineers, reuse of the 4626 wrapper + math libs, and your existing test/audit standard.

| Phase | Scope | New Solidity (incl. tests) | Calendar |
|---|---|---|---|
| **0. Design & risk spec** | Define the credit-loss model (impairment trigger, recovery socialization), redemption allocation across batches, coupon-vs-delinquency interaction, coverage ratio + param bounds. This phase carries most of the design. | spec, not code | 3–5 wks |
| **1. MVP core** | 2 tranche tokens; yield waterfall (senior floor + priority, junior residual + risk premium); junior first-loss; coverage-ratio gating; NAV off `scaleFactor`; redemption orchestration through the withdrawal queue + a tranche cooldown; factory; roles; pause. | ~3.5–5k LOC | 6–10 wks |
| **2. Hardening** | Invariant + fuzz tests to your bar, a16z 4626 suite, delinquency/default/partial-fill edge cases, vault-layer sanctions/KYC. | folded in | 4–6 wks |
| **3. Audit + fixes** | External audit + remediation. | n/a | 4–8 wks calendar (+ $80–150k) |
| **MVP TOTAL (common ground, audited)** | | **~4–6 eng-months build** | **~3.5–5 months** |
| **4. Advanced (full parity, optional)** | Adaptive/dynamic yield-split curve; depeg/valuation oracle; isolated liquid-junior/illiquid-senior routing; fixed-term recovery state machine; recursive tranching / Pendle. | +3–6k LOC | +3–5 months |

**Why not faster, given the IP is only ~1–2k LOC?** Because in this domain calendar time is dominated by (1) the loss-model design, (2) the redemption integration that has no template, and (3) test + audit to a credit-protocol standard. The reference repos are 22k–48k LOC precisely because of tests/adapters/ops around a small core, and ~32k of Royco's 48k is tests.

---

## 6. Build vs. partner

- **Partner (Strata, as proposed):** the Wintermute facility gets senior/junior tranches in **weeks with ~zero Wildcat engineering**. Strata provides NAV accounting, programmable waterfalls, automated yield distribution, and enforced mint/redeem; Wildcat provides the market + joint UI ("toggle v-/sr-/jr-wmtUSDC at deposit time"). Cost: revenue share, external dependency/trust surface, less control over UX and roadmap.
- **Build in-house:** full control, no revenue share, native UX, reusable across every Wildcat market via a factory. Cost: the quarter-plus above, owning the audit + ongoing maintenance, and owning the credit-loss-model risk.
- **Pragmatic middle:** partner to ship the Wintermute facility and learn real demand/UX, while scoping the in-house build (the design spec) in parallel. The design phase is cheap and de-risks the rest of the build; the decision to proceed to the MVP follows once the loss model and redemption design are settled.

---

## Appendix: reference-protocol core files (where the real IP sits)

- **Strata:** `contracts/tranches/Accounting.sol` (deployed continuous engine, ~628 LOC, the most direct expression of the model), `DYSAccounting.sol` (~1,203 LOC, advanced), `StrataCDO.sol` (orchestrator), `Tranche.sol` (ERC4626 tranche token), `strategies/spark/SparkUSDCStrategy.sol` (the generic-ERC4626-wrap template, the closest analog to wrapping v-wmtUSDC), `base/cooldown/SharesCooldown.sol`.
- **Royco Dawn:** `src/accountant/RoycoAccountant.sol` (~916 LOC: waterfalls, IL, state machine), `src/kernels/base/RoycoKernel.sol` (~966 LOC: coverage, self-liquidation), `src/ydm/AdaptiveCurveYDM_V2.sol`, `src/tranches/base/RoycoVaultTranche.sol`, `src/libraries/Units.sol` (typed NAV accounting), `src/periphery/RoycoEntryPoint.sol` (async queue).
- **Pareto:** `src/ParetoDollarQueue.sol` (~757 LOC: NAV aggregation, epoch queue, gain/loss → sUSP first-loss), `src/ParetoDollarStaking.sol` (sUSP buffer). The AA/BB engine itself is external (Idle).
- **Wildcat (reuse):** `src/vault/Wildcat4626Wrapper.sol`, `src/vault/Wildcat4626WrapperFactory.sol`, `src/libraries/MarketState.sol`, `src/market/WildcatMarketWithdrawals.sol` + `src/libraries/Withdrawal.sol`, `src/libraries/MathUtils.sol`.
