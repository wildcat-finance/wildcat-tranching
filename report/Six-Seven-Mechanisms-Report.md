# Mechanisms Report: Tranching the abcUSDC Facility (Six Seven Ltd)

*Where the tranching mechanisms stand, instantiated on a concrete facility rather than in the abstract. Every number below is derived from the code in `build/src/`, not from the marketing copy. Companion infographic: `report/six-seven-mechanisms.html`.*

---

## 1. The facility we are tranching

| Term | Value | Source |
|---|---|---|
| Borrower | Six Seven Ltd | given |
| Market token | `abcUSDC` (base asset USDC) | given |
| Term | Open / perpetual, no maturity | given |
| Base APR (`annualInterestBips`) | **10.00%** (1000 bips) | given |
| Withdrawal cycle (`withdrawalBatchDuration`) | **14 days** | given |
| Capacity (`maxTotalSupply`) | 15,000,000 | given |
| Currently supplied | 10,000,000 (66.7% drawn, 5,000,000 headroom) | given |
| Reserve ratio (`reserveRatioBips`) | **not specified** | — |
| Delinquency grace period | **not specified** | — |

Two parameters that matter to the mechanism are not in the brief. The **reserve ratio** is what actually defines delinquency on a Wildcat market, so it sets the trigger the whole distress path hangs off. The **grace period** is the first addend in the default clock. Both are needed before this facility can be priced properly; §8 states what changes across their plausible range.

Everything below assumes the full 10,000,000 of current supply arrives through the tranche set — i.e. the facility is fully tranched, and the tranche controller is the market's lender of record. A partially-tranched facility works identically; the stack just sits on the tranched sleeve rather than on the whole book.

Naming follows the existing convention: the audited ERC-4626 wrapper is `v-abcUSDC`, and the tranche tokens are `sr-abcUSDC` / `jr-abcUSDC`. See §10 — the code does not currently emit those symbols.

---

## 2. Parameters this facility needs at deployment

Four values are set per-market when `TrancheFactory.deployTranches` runs, and are not derivable from the market itself. Proposed for Six Seven Ltd:

| Parameter | Proposed | Bound in code | Effect |
|---|---|---|---|
| `minJuniorBips` | **2000** (junior ≥ 20%) | 500–9000 | Attachment point; senior leverage cap |
| `seniorShareBips` | **8000** (senior takes 80% of base APR) | ≤ 10000 | Senior target rate; junior's spread |
| `defaultPenaltyWindow` | **90 days** | > 0, ≤ 90 days | ToU §6.2 mirror |
| `defaultDeclarer` | **`address(0)`** unless a Loan Agreement exists | non-zero if set | Bilateral-override authority |

`seniorShareBips` is the only one that moves post-deployment, behind the 48-hour `RATE_TIMELOCK`, and it can be cancelled mid-flight (`cancelSeniorShareProposal`). `minJuniorBips` and `defaultPenaltyWindow` are `immutable` — getting them wrong means redeploying, not retuning.

Setting `defaultDeclarer` to zero is the deliberate choice for a facility with no bilateral Loan Agreement: it leaves the ToU grace+90d mirror as the sole default trigger and removes a discretionary, un-timelocked, one-way power from the system. If Six Seven Ltd signs a Loan Agreement with its own default definition, that address gets populated and the report needs revisiting.

---

## 3. The capital stack as it would stand today

At 10,000,000 supplied with junior exactly at its 20% floor:

| | Amount | Share of stack |
|---|---|---|
| Senior `sr-abcUSDC` | 8,000,000 | 80% |
| Junior `jr-abcUSDC` | 2,000,000 | 20% |
| **Total** | **10,000,000** | 100% |

Senior leverage is **4.00×** — exactly at the cap. This is the binding state, and §5 shows it has a consequence people usually miss.

---

## 4. Interest waterfall, worked

The facility generates `10,000,000 × 10.00% = 1,000,000` per year. The waterfall splits it:

| Claim | Rate | Annual | Base |
|---|---|---|---|
| Senior target (`10.00% × 8000/10000`) | **8.00%** | 640,000 | 8,000,000 |
| Junior residual | **18.00%** | 360,000 | 2,000,000 |
| Facility total | 10.00% | 1,000,000 | 10,000,000 |

Junior earns 18.00% out of a 10.00% loan — **1.80× the facility rate** — because it collects the 2.00% spread on the entire 10,000,000 against a 2,000,000 base.

That multiple is structural, not coincidental. At the subordination floor:

$$r_{jr} = \frac{r_{APR} - r_{sr}(1-j)}{j} = r_{APR} \cdot \frac{1 - s(1-j)}{j}$$

with junior fraction `j = 0.20` and senior share `s = 0.80`, giving `1.80 × r_APR` for **any** APR. Two things follow, and they are the point of the Q4 decision:

- **Junior takes no rate risk relative to the facility.** If Six Seven Ltd moves the APR, junior's rate moves proportionally and its multiple is untouched. Junior is a pure credit-risk position.
- **Junior's return is scale-invariant at the floor.** Growing the facility to capacity does not dilute it (§5).

Rate sensitivity, holding share at 80% and junior at the floor:

| Base APR | Senior target | Junior | Junior multiple |
|---|---|---|---|
| 6.00% | 4.80% | 10.80% | 1.80× |
| 8.00% | 6.40% | 14.40% | 1.80× |
| **10.00%** | **8.00%** | **18.00%** | **1.80×** |
| 12.00% | 9.60% | 21.60% | 1.80× |

And the `seniorShareBips` dial itself, at 10% APR:

| `seniorShareBips` | Senior target | Junior | Junior multiple |
|---|---|---|---|
| 6000 | 6.00% | 26.00% | 2.60× |
| 7000 | 7.00% | 22.00% | 2.20× |
| **8000** | **8.00%** | **18.00%** | **1.80×** |
| 9000 | 9.00% | 14.00% | 1.40× |
| 10000 | 10.00% | 10.00% | 1.00× |

The last row is the degenerate case the explainer already flags: at a 100% share, junior takes first-loss for zero excess return. The gap below 100% *is* junior's premium. 8000 is the defensible setting — it prices senior above what a T-bill pays while leaving junior a 1.80× multiple for standing in front.

---

## 5. The structure is pinned at 10,000,000, and that is the headline

Both subordination gates are exactly binding right now. Running the library functions on the live state (`sv = 8,000,000`, `jv = 2,000,000`, `minJuniorBips = 2000`):

- `maxSeniorDeposit` = `(2,000,000 × 10000 / 2000) − 10,000,000` = `10,000,000 − 10,000,000` = **0**
- `maxJuniorWithdraw` — `jv × BIPS = 2×10¹⁰` versus `minJuniorBips × tvl = 2×10¹⁰`, so the `lhsJ <= rhs` branch returns **0**

So on the 5,000,000 of remaining capacity: **senior cannot deposit a single unit, and junior cannot withdraw a single unit.** The facility's growth is gated entirely on junior, and junior's exit is gated entirely on senior shrinking.

The path to capacity is therefore fixed, and it is pleasingly exact:

| Step | Junior | Senior | TVL | `maxSeniorDeposit` after |
|---|---|---|---|---|
| Today | 2,000,000 | 8,000,000 | 10,000,000 | 0 |
| Junior adds 1,000,000 | 3,000,000 | 8,000,000 | 11,000,000 | **4,000,000** |
| Senior fills that room | 3,000,000 | 12,000,000 | **15,000,000** | 0 |

1,000,000 of new first-loss capital unlocks exactly 4,000,000 of senior and lands precisely on the 15,000,000 capacity. Junior's rate stays 18.00% throughout, because the ratio is unchanged.

**This is the operational finding.** Placing this facility is not "sell 5,000,000 of paper." It is "source 1,000,000 of first-loss, then sell 4,000,000 of senior, in that order." Sequencing it the other way round reverts on `SUBORDINATION`. If BD wants senior-led placement, the structure needs a warehousing arrangement where a junior provider commits first, or `minJuniorBips` needs to be set lower at deployment — and that is an immutable, one-shot decision.

---

## 6. Loss waterfall, worked

Losses run the same waterfall from the bottom. Junior absorbs to zero before senior is touched.

| Pool loss | Pool value | Junior value | Senior value | Junior P&L | Senior P&L |
|---|---|---|---|---|---|
| 0% | 10,000,000 | 2,000,000 | 8,000,000 | 0% | 0% |
| 5% | 9,500,000 | 1,500,000 | 8,000,000 | −25.0% | 0% |
| 10% | 9,000,000 | 1,000,000 | 8,000,000 | −50.0% | 0% |
| **20%** | 8,000,000 | **0** | 8,000,000 | **−100%** | **0%** ← attachment |
| 30% | 7,000,000 | 0 | 7,000,000 | −100% | −12.5% |
| 50% | 5,000,000 | 0 | 5,000,000 | −100% | −37.5% |

Senior's loss-given-default above the attachment point is `(L − 20%) / 80%` of its principal — a 30% pool loss costs senior 12.5%, a 50% pool loss costs it 37.5%.

Two break-evens worth quoting to buyers, on a one-year view:

- **Junior** earns 360,000, which is **3.60% of the pool**. One year of carry absorbs a 3.60% pool loss before junior's principal is net down. Principal is exhausted at 20%.
- **Senior** earns 640,000 against a 2,000,000 cushion, so cushion plus coupon absorbs a **26.4%** pool loss before senior is net down on the year.

Note what the contract does *not* do here. There is no mark-down mechanism. `realisedValue()` reads the wrapper balance at the effective price, and `WaterfallMath.split` allocates it. A loss only appears in these numbers once cash actually comes back short — which means the table above describes terminal outcomes, not a mid-flight price path.

---

## 7. Liquidity: the 14-day cycle, end to end

The 14-day `withdrawalBatchDuration` is the clock the whole exit path runs on. One round trip:

1. **`requestRedeem(isSenior, shares)`** — tranche shares burn at the current tranche NAV. For senior, `seniorOwed` is reduced by the exiting share pro-rata. For junior while Active, the request must clear `maxJuniorWithdraw` (today: it cannot, §5). The controller redeems `v-abcUSDC` at the **live** price (the SR-D fix) and calls `market.queueWithdrawal`, which drops the claim into whatever batch is currently open.
2. **Wait for expiry** — anywhere from 0 to 14 days, depending on where in the cycle the request lands. A holder timing an exit for the start of a fresh batch waits the full 14; one arriving late in a batch waits days. There is no way to choose your batch.
3. **Settle** — `pokeRecovery(expiry)` calls `market.executeWithdrawal`. This is permissionless on the real market, so USDC can also arrive without the poke; the balance-derived `recoveredUSDC` plus the permissionless `sync()` (the SR-A fix) catches it either way.
4. **Allocate** — `_allocate()` fills the senior class first, up to the senior face queued, then releases to junior. The reserve held back against junior depends on state: **`seniorWmtQueued` while healthy, the entire `seniorOwed` while distressed.** More on this in §9.
5. **`claim(id)`** — FIFO within class, O(1) per request via `faceBefore[id]`. A sanctioned owner is routed to a sentinel escrow instead of paid directly.

**Round-trip expectation:** on a fully-funded batch, up to 14 days plus settlement. Under-funded, the market pays pro-rata and the remainder rolls, so an exit under stress is a multiple of 14 days — and each roll re-tests the senior-priority gate. This is what "semi-liquid" concretely means on this facility: **a two-week floor and no ceiling.**

**One rough edge.** `claim` is per-request, and there is no batch-claim helper. A senior holder exiting in tranches across a stressed period accumulates one request ID per 14-day cycle, each needing its own transaction. Access is O(1) so there is no DoS, but a holder with a dozen partial fills pays a dozen gas costs. On a 14-day cycle that accumulates faster than on a long one. A `claimMany(uint256[])` is a small, safe addition and I would add it before this facility goes live.

---

## 8. What "open term" changes

No maturity means there is no scheduled event at which the structure resolves. Three consequences:

**The senior rate is not a locked coupon.** Six Seven Ltd controls `annualInterestBips` and can move it at will over a perpetual line. Senior's target is 80% of whatever it currently is — `currentSeniorRateBips()` reads it live on every accrual. If the borrower cuts to 6%, senior's target is 4.80% from that block forward, with no timelock and no consent. This is the accepted Q4 design (senior tracks the facility rather than bearing rate risk against it), but on an open term it is the single most important thing to disclose to a senior buyer, because there is no maturity at which they get their money back at the original rate. Their remedy is to exit — which is the 14-day queue.

**The only terminal events are closure and the ToU clock.** `defaultReached()` returns true on `isClosed`, on `forcedDefault`, or when `timeDelinquent ≥ delinquencyGracePeriod + 90 days`. With no maturity, that clock is the entire backstop against indefinite delinquency. Note it requires grace to be **exhausted and then lapped** by 90 days — it is not the 90-day cap on grace itself. With grace unspecified, the trigger sits somewhere around 90–97 days of accumulated delinquency for typical settings, and `timeDelinquent` ratchets down on cure rather than resetting, so partial cures do not reset the clock to zero.

**Accrual is update-driven and compounds.** `accrueSeniorOwed` is linear per call, so `seniorOwed` compounds at the frequency someone touches the contract. This is adjudicated as protocol-faithful (it mirrors the market's own behaviour), but over a perpetual term the drift between the nominal 8.00% and the realised effective rate is a function of interaction frequency. On a facility with a 14-day cycle there is a natural cadence of pokes and claims, so expect the effective senior rate to sit slightly above 8.00%. It is not unbounded — it is bounded by the facility's own accrual — but senior marketing material should say "8.00% target" and not imply an exact figure.

---

## 9. Where the mechanisms stand

**All sixteen design questions are settled and implemented.** The Q1–Q16 decision set in `Design-Risk-Specification.md` is fully built in `build/src/`, with 55 tests passing (52 local, 3 mainnet-fork against the live wrapper and market, plus 128k-call stateful invariants for conservation, junior-first-loss, and no-over-distribution). Nothing in the mechanism design is still on the drawing board.

**Five mechanisms were added or changed by the audit cycles, beyond what the spec describes.** These are the substantive movements since the design doc, and they all sharpened senior priority:

1. **The distress gate in `_allocate` is new.** The spec (Q11) said senior-priority allocation of settled proceeds. What is built is stronger: while distressed — delinquent *or* in wind-down — junior may only draw cash beyond the **entire** `seniorOwed`, not merely the senior face actually queued. This protects senior that has not queued yet, and it is what stops first-loss capital walking out during a slow-motion default. This mechanism is not in the design spec and should be written back into it.
2. **Accrual now happens before the wind-down freeze.** The first audit cycle *accepted* dropping the final interest sliver at the default boundary as conservative. The re-audit reversed that: because the distress gate reserves `seniorOwed`, an understated `seniorOwed` enlarges junior's ceiling and leaks recovery to junior ahead of senior. `accrue()` now books interest while still Active and tests for default last, and `checkDefault` / `declareDefault` / `pokeRecovery` / `sync` all accrue first. A disposition that flipped from "accepted" to "bug" on second look is worth remembering.
3. **Redemptions are sized at the live price, not the frozen mark** (SR-D). Sizing at the frozen mark while the wrapper pays at the live price let an exiter during delinquency book unrealised penalty appreciation and dilute stayers.
4. **Recovery is balance-derived, with a permissionless `sync()`** (SR-A). `market.executeWithdrawal` is permissionless, so USDC could arrive outside the measured delta and strand.
5. **The factory is owner-gated with two-step ownership** (SR-B, R2), which also closes the fake-wrapper vector.

**Two items are genuinely open, and both are product decisions rather than bugs:**

- **F8, senior credential-gating on transfer.** `sr-abcUSDC` transfers to any non-sanctioned address with no market-credential check. So a non-KYC'd party can acquire senior exposure on the secondary market even though they could not have deposited into the market directly. This is the one honest open design question in the system, and it is *more* pressing here than in the abstract: senior is the product being sold to treasuries and conservative allocators, and it is the tranche whose holder base a compliance desk will ask about. The choice is between delegating per-holder credential checks to the market's own hook or leaving senior freely transferable and sanction-gated only. It needs a decision before this facility is placed, not after.
- **Permit2 infinite allowance.** Inherited from Solady's ERC20 default. Not a drain vector — Permit2 still requires an owner signature and every resulting transfer passes `beforeTrancheTransfer` — so it is a composability-versus-surface trade with no security delta. Fine to leave, but it should be a recorded decision rather than an inherited default.

**On audit status, be precise.** Two full three-pass cycles have been run with the `pashov/skills` `solidity-auditor` tooling — 36 agent-runs per cycle, findings deduplicated and triaged, every actionable item fixed with a regression in `AuditPoC.t.sol`. That is agentic review, and it found real bugs including a genuine senior-priority leak. It is **not** a human audit engagement. `BD-Primer.md` still says "not yet audited," which is now understated in one direction and could be read as overstated in the other; it should say what actually happened. No external human review has been commissioned, and I would not put Six Seven Ltd's 10,000,000 behind agentic review alone.

---

## 10. One concrete blocker for a second facility

Instantiating on abcUSDC surfaced a gap that a single-market build hides. `TrancheController`'s constructor hardcodes the tranche token metadata:

```solidity
senior = new TrancheToken("Wildcat Senior Tranche", "sr-wmtUSDC", p.shareDecimals, true);
junior = new TrancheToken("Wildcat Junior Tranche", "jr-wmtUSDC", p.shareDecimals, false);
```

`Params` carries no name or symbol field. So deploying against Six Seven Ltd's market mints tokens symbolled **`sr-wmtUSDC` / `jr-wmtUSDC`** — the wrong market's ticker — and every tranche set on every market gets identical symbols. The factory is explicitly built to deploy one set per registered market, so this contradicts the architecture rather than merely being cosmetic: two live facilities would be indistinguishable in wallets, block explorers, accounting exports, and any integrator's token list.

The fix is small — add `string name` / `string symbol` to `Params` and pass them through `deployTranches`, or derive them from `IERC20(market).symbol()` on-chain. Either way it is a required change before a second facility, and it is the kind of thing only a second facility reveals.

---

## 11. What I would decide next

In order, because some of these block others:

1. **Get the reserve ratio and grace period for this market.** They define delinquency and the default clock. The distress-gate mechanism is the most consequential thing in the system and neither of its triggers can be modelled without them.
2. **Settle F8 (senior credential-gating).** It is a compliance question about the product being sold, it is unresolved, and it changes `beforeTrancheTransfer`.
3. **Fix the hardcoded token symbols.** Blocks deployment on abcUSDC. Trivial.
4. **Add `claimMany`.** A 14-day cycle accumulates request IDs faster than a long one.
5. **Confirm the placement sequence with BD.** Junior first, 1,000,000 of it, then 4,000,000 of senior. If that ordering is commercially unworkable, `minJuniorBips` has to change *before* deployment, because it is immutable.
6. **Commission human audit** before real capital, and correct the audit language in `BD-Primer.md`.
7. **Write the distress gate back into `Design-Risk-Specification.md`.** The spec currently understates what Q11 actually became.

---

*Derived from `build/src/` at commit `48cc01d`. Facility terms as briefed; reserve ratio and grace period outstanding. Tranche parameters in §2 are proposals, not settings.*
