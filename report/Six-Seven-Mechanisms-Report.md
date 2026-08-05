# Mechanisms Report: Tranching the abcUSDC Facility (Six Seven Ltd)

*Where the tranching mechanisms stand, instantiated on a concrete facility rather than in the abstract. Every number below is derived from the code in `build/src/`, not from the marketing copy. Companion infographic: `report/six-seven-mechanisms.html`.*

---

## Decisions outstanding

The analysis below is complete; these are the calls still open, in the order they bite. Deployment- and governance-level decisions have their own register in `Deployment-Access-Governance-Notes.md`.

| Decision | What it determines | Where argued | Owner |
|---|---|---|---|
| **Senior entry policy** — which gate/provider set `sr-abcUSDC` carries, if any | Whether senior exposure is open to any non-sanctioned address or restricted to credentialed holders; under the USDC front door the gates are the *only* per-user compliance surface | §12 | Desk + borrower |
| **Junior sizing vs the floor** — place junior ~22% or exactly at 20% | At the floor, any delinquency breaches subordination from its first second and freezes the facility to new senior (§8.4); ~2 points of junior coupon buys the headroom | §8.4–8.6 | Junior anchor + desk |
| **Grace period ask** — negotiate 28d toward 14d | At 28d the borrower gets two penalty-free missed exit cycles, and a disciplined borrower can orbit inside grace indefinitely without ever reaching the default trigger | §8.2 | Desk ↔ borrower |
| **Governance holder for this facility** | A borrower-held governance controls both senior-rate dials and the un-timelocked wind-down trigger — legitimate, but it must be disclosed to senior buyers in those words | companion notes | Desk + borrower |
| **Loan Agreement & `defaultDeclarer`** | Zero declarer = pure ToU day-118 mirror; a bilateral agreement names a lender-side declarer and changes the default definition | §2, §12.4 | Legal + desk |
| **Human audit engagement** | Two agentic audit cycles are not an audit engagement; required before real capital | §10 | Protocol |

Settled design, pending build (one pre-deployment PR): tranche token metadata derived from the market symbol (§11), the entry-gate pointers (§12), `claimMany` (§7), and the deployment/entry changes in the companion notes.

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
| Reserve ratio (`reserveRatioBips`) | **0** | given |
| Delinquency grace period | **28 days** | given |

These two are the most consequential terms in the sheet and they are not neutral: a zero reserve ratio and a grace period twice the withdrawal cycle together produce a **118-day** default clock with no early-warning signal, and they put the structure in continuous breach of its own subordination floor during any delinquency. §8 works this through — it is the part of this report that most affects how senior should be priced and sold.

Everything below assumes the full 10,000,000 of current supply arrives through the tranche set — i.e. the facility is fully tranched, and the tranche controller is the market's lender of record. A partially-tranched facility works identically; the stack just sits on the tranched sleeve rather than on the whole book.

Naming follows the existing convention: the audited ERC-4626 wrapper is `v-abcUSDC`, and the tranche tokens are `sr-abcUSDC` / `jr-abcUSDC`. See §11 — the code does not currently emit those symbols.

One scoping note for §8. The tranche layer does not compute delinquency; it reads `isDelinquent` and `timeDelinquent` off `MarketState` and inherits whatever the market decides. So the timing analysis below rests on Wildcat market semantics external to this repo (the mocks in `build/test/Mocks.sol` stub both flags directly, so the test suite cannot confirm it). The mechanics are standard — required liquidity counts pending withdrawals at full face, applies the reserve ratio to non-withdrawing supply, and requires accrued protocol fees to be liquid — but the timing conclusions should be confirmed against the deployed market before they go in front of a buyer.

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

Senior leverage is **4.00×**, right at the cap. This is the binding state, and §5 works through what that actually means for placement.

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

The path to capacity is therefore fixed, and the arithmetic lands exactly:

| Step | Junior | Senior | TVL | `maxSeniorDeposit` after |
|---|---|---|---|---|
| Today | 2,000,000 | 8,000,000 | 10,000,000 | 0 |
| Junior adds 1,000,000 | 3,000,000 | 8,000,000 | 11,000,000 | **4,000,000** |
| Senior fills that room | 3,000,000 | 12,000,000 | **15,000,000** | 0 |

1,000,000 of new first-loss capital unlocks exactly 4,000,000 of senior and lands precisely on the 15,000,000 capacity. Junior's rate stays 18.00% throughout, because the ratio is unchanged.

**This is the operational finding.** Placing this facility isn't "sell 5,000,000 of paper". It's "source 1,000,000 of first-loss, then sell 4,000,000 of senior, in that order" — sequence it the other way round and it reverts on `SUBORDINATION`. If BD wants senior-led placement, the structure needs a warehousing arrangement where a junior provider commits first, or `minJuniorBips` set lower at deployment. That one is immutable, so it's a one-shot decision.

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

Two break-evens to quote to buyers, on a one-year view:

- **Junior** earns 360,000, which is **3.60% of the pool**. One year of carry absorbs a 3.60% pool loss before junior's principal is net down. Principal is exhausted at 20%.
- **Senior** earns 640,000 against a 2,000,000 cushion, so cushion plus coupon absorbs a **26.4%** pool loss before senior is net down on the year.

Note what the contract does *not* do here. There is no mark-down mechanism. `realisedValue()` reads the wrapper balance at the effective price, and `WaterfallMath.split` allocates it. A loss only appears in these numbers once cash actually comes back short — which means the table above describes terminal outcomes, not a mid-flight price path.

---

## 7. Liquidity: the 14-day cycle, end to end

The 14-day `withdrawalBatchDuration` is the clock the whole exit path runs on. One round trip:

1. **`requestRedeem(isSenior, shares)`** — tranche shares burn at the current tranche NAV. For senior, `seniorOwed` is reduced by the exiting share pro-rata. For junior while Active, the request must clear `maxJuniorWithdraw` (today: it cannot, §5). The controller redeems `v-abcUSDC` at the **live** price (the SR-D fix) and calls `market.queueWithdrawal`, which drops the claim into whatever batch is currently open.
2. **Wait for expiry** — anywhere from 0 to 14 days, depending on where in the cycle the request lands. A holder timing an exit for the start of a fresh batch waits the full 14; one arriving late in a batch waits days. There is no way to choose your batch.
3. **Settle** — `pokeRecovery(expiry)` calls `market.executeWithdrawal`. This is permissionless on the real market, so USDC can also arrive without the poke; the balance-derived `recoveredUSDC` plus the permissionless `sync()` (the SR-A fix) catches it either way.
4. **Allocate** — `_allocate()` fills the senior class first, up to the senior face queued, then releases to junior. The reserve held back against junior depends on state: **`seniorWmtQueued` while healthy, the entire `seniorOwed` while distressed.** More on this in §10.
5. **`claim(id)`** — FIFO within class, O(1) per request via `faceBefore[id]`. A sanctioned owner is routed to a sentinel escrow instead of paid directly.

**Round-trip expectation:** on a fully-funded batch, up to 14 days plus settlement. Under-funded, the market pays pro-rata and the remainder rolls, so an exit under stress is a multiple of 14 days — and each roll re-tests the senior-priority gate. This is what "semi-liquid" concretely means on this facility: **a two-week floor and no ceiling.**

**One rough edge.** `claim` is per-request and there's no batch-claim helper, so a senior holder exiting in tranches across a stressed period accumulates one request ID per 14-day cycle, each needing its own transaction. Access is O(1) so there's no DoS, but a holder with a dozen partial fills pays a dozen gas costs, and a 14-day cycle accumulates them faster than a long one would. `claimMany(uint256[])` is a small, safe addition and I'd add it before this facility goes live.

---

## 8. The distress clock: what a zero reserve ratio and a 28-day grace produce

### 8.1 The default clock is 118 days

`defaultReached()` fires at `timeDelinquent ≥ delinquencyGracePeriod + defaultPenaltyWindow` = `28 + 90` = **118 days** of accumulated delinquency. In the units that matter to a holder, that is **8.4 withdrawal cycles**. Until day 118 the structure cannot enter wind-down, senior accrual cannot be frozen, and no recovery waterfall can start.

So the senior liquidity statement for this facility, said plainly: *your exit clears in 14 days if the borrower funds it, and if they don't, the structure can't force the issue for 118 days, after which recovery depends on off-chain enforcement.*

### 8.2 Grace is twice the withdrawal cycle, and that is the most senior-adverse term here

The cycle is 14 days; grace is 28. So a borrower who ignores a senior exit request gets **two full withdrawal cycles with no penalty rate at all**. Penalty APR only begins on day 29.

For a product whose entire pitch to senior is payment priority, I'd push on that asymmetry. Grace at 14 days would align one grace period to one exit cycle, so a borrower who misses a single batch starts paying immediately. It's a market parameter rather than a tranche parameter — Six Seven Ltd's term — so changing it is a conversation with the borrower, not a code change.

There is a second-order effect: `timeDelinquent` decays on cure rather than resetting, roughly 1:1 with time cured. A borrower oscillating inside a 28-day grace — delinquent 27 days, cured 27 days, repeating — **never pays a penalty and never approaches the 118-day trigger**, while senior's exits keep failing to clear. The wider the grace, the wider that band. Nothing in the code is broken here; the trigger is simply not reachable by a borrower who stays disciplined about the boundary.

### 8.3 A zero reserve ratio makes delinquency exit-triggered, so there is no early warning

With `reserveRatioBips = 0`, Six Seven Ltd has no obligation to keep any liquidity against the 10,000,000 outstanding. Required liquidity is near zero in steady state, and a queued withdrawal counts toward it at **full face**. Two consequences:

- **The facility reads perfectly healthy right up to the first exit request.** There is no reserve buffer to erode, so there is no gradual signal to monitor. The market flips from non-delinquent to delinquent on the first withdrawal the borrower does not fund.
- **The distress gate — the strongest senior protection in the system — is dormant until someone tries to leave.** `_distressed()` is false while the market is not delinquent, so `_allocate` reserves only the queued senior face rather than the full `seniorOwed`. The mechanism is correct and it arms exactly when it needs to, but it is reactive by construction. Nobody should expect it to give advance notice.

One caveat that cuts the other way: `accruedProtocolFees` must also be liquid. So a borrower at literally 100% deployment can be delinquent on protocol fees alone. A zero reserve ratio does **not** mean "cannot go delinquent," and a small persistent fee delinquency would keep the mark frozen and `_distressed()` armed continuously — see §8.4 for why that matters more than it sounds.

### 8.4 Junior sits exactly on the floor, so any delinquency breaches subordination immediately

This is the finding I would put in front of a junior buyer.

Junior's value is `realisedValue − seniorOwed`. During delinquency the mark freezes, so `realisedValue` stops growing — but `seniorOwed` keeps accruing at 8.00% for as long as `status == Active`, which is until day 118. Junior absorbs that gap out of its own book value, with **no credit loss anywhere**.

Because junior sits at *exactly* 20%, the breach is not gradual — it begins in the first second of delinquency:

| Delinquency elapsed | Senior accrued | Junior book value | Junior share of TVL |
|---|---|---|---|
| 0 | 0 | 2,000,000 | 20.00% (at floor) |
| 14 days (one cycle) | 24,548 | 1,975,452 | 19.75% |
| 28 days (grace ends) | 49,096 | 1,950,904 | 19.51% |
| 118 days (default) | 206,904 | 1,793,096 | **17.93%** |

Senior accrues `640,000 / 365 = 1,753` a day, so a full slide to default costs junior **206,904, or −10.35% of book value**, before any actual loss.

Two things to keep straight. First, this is **recoverable**: on cure, `_refreshMark()` releases the frozen gap in one step and junior gets it back, which is what realised-only accounting is for. It only becomes permanent if the borrower never cures. Second, breach is **not an error state** — nothing reverts. `meetsSubordination` is only tested on senior deposit, and junior exit is gated by `maxJuniorWithdraw`. Both were already zero (§5). So the practical consequence of breach is that **the facility is frozen to new senior capital for the entire delinquency and cannot self-heal except by junior injecting more first-loss.**

### 8.5 And the one action that heals it is penalised

Restoring the floor after a full 118-day slide takes a junior top-up of `206,904 / 0.8` = **258,630**. Junior *can* deposit during delinquency — only wind-down blocks deposits — but the deposit is credited at the **frozen mark** while the wrapper shares handed over are worth the live price. That is the accepted by-design item "deposits at the frozen mark under-credit the depositor," and here it lands badly: the depositor overpays by exactly the frozen-versus-live gap, which *widens* the longer the delinquency runs and the more penalty interest accrues unbooked.

So the mechanism asks first-loss capital to step in precisely when doing so is most expensive. It is not a bug — it follows directly from Q6 — but it is a real disincentive at the worst moment, and a junior provider will find it. Worth pricing, or worth an explicit side arrangement for emergency junior top-ups.

### 8.6 What I would change

- **Place junior above the floor, not on it.** At the 15,000,000 target size senior accrues ~2,630 a day, so a full 118-day slide drifts ~310,000. Placing junior around 22% instead of 20% buys enough headroom that ordinary delinquency does not immediately breach. The cost is rate: junior at 25% earns 16.00% instead of 18.00%, so the trade is roughly two points of coupon for floor headroom. Put that choice to the junior buyer explicitly.
- **Negotiate grace toward 14 days** so one grace period equals one exit cycle.
- **Decide whether 118 days is acceptable.** `defaultPenaltyWindow` accepts any value in `(0, 90 days]`, so the clock can be shortened in code — but the 90-day setting is what makes it a faithful ToU §6.2 mirror. Deviating needs a bilateral Loan Agreement to be defensible, and that is a papering decision, not a parameter tweak.

---

## 9. What "open term" changes

No maturity means there is no scheduled event at which the structure resolves. Three consequences:

**The senior rate is not a locked coupon.** Six Seven Ltd controls `annualInterestBips` and can move it at will over a perpetual line. Senior's target is 80% of whatever it currently is — `currentSeniorRateBips()` reads it live on every accrual. If the borrower cuts to 6%, senior's target is 4.80% from that block forward, with no timelock and no consent. This is the accepted Q4 design (senior tracks the facility rather than bearing rate risk against it), but on an open term it is the single most important thing to disclose to a senior buyer, because there is no maturity at which they get their money back at the original rate. Their remedy is to exit — which is the 14-day queue.

**The only terminal events are closure and the ToU clock.** `defaultReached()` returns true on `isClosed`, on `forcedDefault`, or when `timeDelinquent ≥ delinquencyGracePeriod + 90 days` — here, **118 days** (§8.1). With no maturity, that clock is the entire backstop against indefinite delinquency. Note it requires grace to be **exhausted and then lapped** by 90 days; it is not the 90-day cap on grace itself. And `timeDelinquent` ratchets down on cure rather than resetting, so partial cures do not reset the clock to zero — but by the same token a borrower who cures often enough never reaches it (§8.2).

**Accrual is update-driven and compounds.** `accrueSeniorOwed` is linear per call, so `seniorOwed` compounds at the frequency someone touches the contract. This is adjudicated as protocol-faithful (it mirrors the market's own behaviour), but over a perpetual term the drift between the nominal 8.00% and the realised effective rate is a function of interaction frequency. On a facility with a 14-day cycle there is a natural cadence of pokes and claims, so expect the effective senior rate to sit slightly above 8.00%. It is not unbounded — it is bounded by the facility's own accrual — but senior marketing material should say "8.00% target" and not imply an exact figure.

---

## 10. Where the mechanisms stand

**All sixteen design questions are settled and implemented.** The Q1–Q16 decision set in `Design-Risk-Specification.md` is fully built in `build/src/`, with 55 tests passing (52 local, 3 mainnet-fork against the live wrapper and market, plus 128k-call stateful invariants for conservation, junior-first-loss, and no-over-distribution). Nothing in the mechanism design is still on the drawing board.

**Five mechanisms were added or changed by the audit cycles, beyond what the spec describes.** These are the substantive movements since the design doc, and they all sharpened senior priority:

1. **The distress gate in `_allocate` is new.** The spec (Q11) said senior-priority allocation of settled proceeds. What is built is stronger: while distressed — delinquent *or* in wind-down — junior may only draw cash beyond the **entire** `seniorOwed`, not merely the senior face actually queued. This protects senior that has not queued yet, and it is what stops first-loss capital walking out during a slow-motion default. This mechanism is not in the design spec and should be written back into it.
2. **Accrual now happens before the wind-down freeze.** The first audit cycle *accepted* dropping the final interest sliver at the default boundary as conservative. The re-audit reversed that: because the distress gate reserves `seniorOwed`, an understated `seniorOwed` enlarges junior's ceiling and leaks recovery to junior ahead of senior. `accrue()` now books interest while still Active and tests for default last, and `checkDefault` / `declareDefault` / `pokeRecovery` / `sync` all accrue first. A disposition that flipped from "accepted" to "bug" on second look; remember that one.
3. **Redemptions are sized at the live price, not the frozen mark** (SR-D). Sizing at the frozen mark while the wrapper pays at the live price let an exiter during delinquency book unrealised penalty appreciation and dilute stayers.
4. **Recovery is balance-derived, with a permissionless `sync()`** (SR-A). `market.executeWithdrawal` is permissionless, so USDC could arrive outside the measured delta and strand.
5. **The factory is owner-gated with two-step ownership** (SR-B, R2), which also closes the fake-wrapper vector.

**Two items remain open, and both are product decisions rather than bugs:**

- **F8, senior credential-gating on transfer.** `sr-abcUSDC` transfers to any non-sanctioned address with no market-credential check. So a non-KYC'd party can acquire senior exposure on the secondary market even though they could not have deposited into the market directly. This is the one real open design question in the system, and it's *more* pressing here than in the abstract: senior is the product being sold to treasuries and conservative allocators, and it is the tranche whose holder base a compliance desk will ask about. The choice is between delegating per-holder credential checks to the market's own hook or leaving senior freely transferable and sanction-gated only. It needs a decision before this facility is placed, not after. §12 proposes the mechanism that makes it a per-facility configuration rather than a global choice.
- **Permit2 infinite allowance.** Inherited from Solady's ERC20 default. Not a drain vector — Permit2 still requires an owner signature and every resulting transfer passes `beforeTrancheTransfer` — so it is a composability-versus-surface trade with no security delta. Fine to leave, but it should be a recorded decision rather than an inherited default.

**On audit status, precision matters.** Two full three-pass agentic review cycles have been run: 12 specialist attacker agents per pass, 36 agent-runs per cycle, findings deduplicated and triaged, every actionable item fixed with a regression in `AuditPoC.t.sol`. That process found real bugs, including a senior-priority leak. It is **not** a human audit engagement. No external human review has been commissioned, and I wouldn't put Six Seven Ltd's 10,000,000 behind agentic review alone.

---

## 11. One concrete blocker for a second facility

Instantiating on abcUSDC surfaced a gap that a single-market build hides. `TrancheController`'s constructor hardcodes the tranche token metadata:

```solidity
senior = new TrancheToken("Wildcat Senior Tranche", "sr-wmtUSDC", p.shareDecimals, true);
junior = new TrancheToken("Wildcat Junior Tranche", "jr-wmtUSDC", p.shareDecimals, false);
```

`Params` carries no name or symbol field. So deploying against Six Seven Ltd's market mints tokens symbolled **`sr-wmtUSDC` / `jr-wmtUSDC`** — the wrong market's ticker — and every tranche set on every market gets identical symbols. The factory is explicitly built to deploy one set per registered market, so this contradicts the architecture rather than merely being cosmetic: two live facilities would be indistinguishable in wallets, block explorers, accounting exports, and any integrator's token list.

The fix is small and decided: derive the metadata on-chain from `IERC20(market).symbol()`, minting `"Senior Tranched <SYM>"` / `sr-<SYM>` and the junior equivalents. It is a required change before a second facility, and it is the kind of thing only a second facility reveals.

---

## 12. Imported mechanism: Morpho Midnight-style entry gates

*The entry-gating design imports Morpho Midnight's gate system — the entry-gate half of it maps onto this architecture almost exactly, it turns the F8 access question into per-facility deployment configuration rather than a global choice, and the bridge already exists: Wildcat's `secdemo-gateaccess` repo demonstrates the existing `IRoleProvider` credential stack driving Midnight gates, and the same gate contract can serve the tranche layer unchanged. Sources: the [Midnight concept docs](https://docs.morpho.org/learn/concepts/midnight/), [`IGate.sol`](https://github.com/morpho-org/midnight/blob/main/src/interfaces/IGate.sol) and `Midnight.sol` in [morpho-org/midnight](https://github.com/morpho-org/midnight), the [Morpho Vault V2 gate docs](https://docs.morpho.org/curate/concepts/gates/) for contrast, the [sealed-entity-credentials draft ERC](https://hackmd.io/@wildcatlabs/erc-draft-sealed-entity-credentials), and the `secdemo-gateaccess` demo repo (Wildcat Labs, July 2026).*

### 12.1 What Midnight's gates actually are

Midnight markets may name **up to two optional gate contracts at creation, fixed thereafter**:

```solidity
interface IEnterGate {
    function canIncreaseCredit(address account) external view returns (bool);
    function canIncreaseDebt(address account) external view returns (bool);
}

interface ILiquidatorGate {
    function canLiquidate(address account) external view returns (bool);
}
```

The protocol consults them with a short-circuit — `enterGate == address(0) || canIncreaseCredit(buyer)` — so a zero gate means unrestricted. The critical property is **what is never gated**: the enter gate applies only to *increasing* a position. Withdrawals, repayments, and collateral exits carry no gate check at all, so a participant can always leave even if the gate contract is malicious or bricked. Gates are policy plug-ins; the core stays immutable and non-custodial.

(Morpho's Vault V2 has a richer four-gate system — `receiveSharesGate` / `sendSharesGate` / `receiveAssetsGate` / `sendAssetsGate`, curator-set behind a timelock. Note that its send-side gates **can** lock users out of exiting, which their own docs flag as the critical risk and mitigate with a `forceDeallocate` escape hatch. That half is the part *not* to import.)

### 12.2 Why the pattern fits this codebase specifically

Design rule 5 here is "never trap a user's exit" — the same invariant Midnight's entry-only gating encodes. And the tranching architecture already enforces it structurally, which is what makes the import nearly free:

- `TrancheToken._beforeTokenTransfer` only consults the controller when `from != address(0) && to != address(0)` — **mint and burn bypass the hook entirely**.
- `requestRedeem` burns; `claim` transfers USDC, not tranche tokens. Neither routes through `beforeTrancheTransfer`.

So a gate wired into deposits and transfer-receipt **cannot block an exit even if it reverts unconditionally** — the exit path never calls it. Adopting Midnight's pattern costs nothing on the axis its designers cared most about, because this codebase already made the same choice.

The controller also already *contains* two hardcoded gates — it just doesn't call them that: the junior whitelist (`juniorAllowed[to]`, checked in `_deposit` and `beforeTrancheTransfer`) and the sanctions check. F8 exists precisely because senior's entry policy is hardcoded to "anyone non-sanctioned."

### 12.3 The bridge already exists: `WildcatRoleProviderGate`

The `secdemo-gateaccess` repo (presented to Morpho alongside the sealed-entity-credentials draft ERC) settles the make-or-buy question for the gate implementation. Its `WildcatRoleProviderGate` is a Midnight `IEnterGate`/`ILiquidatorGate` whose policy is delegated to **sets of Wildcat `IRoleProvider`s, one set per gated role** (CREDIT / DEBT / LIQUIDATE), carrying over the design rules from Wildcat's `AccessControlHooks`:

- *Pull* providers queried live inside the view gate via guarded staticcalls — a reverting or misbehaving provider is skipped, never bricking the gate (fail-closed, exactly the property §12.4 asks for);
- *Push* providers (Merkle proofs, signed attestations) staged through a permissionless `refreshCredential` and cached as `{provider, timestamp}` against a per-provider TTL;
- owner-managed provider sets with a one-way `freeze()` — the same constitutional ratchet the rest of Wildcat uses.

The demo ships with a forge suite (~40 unit cases), a py-evm runtime check (25 assertions executed), and an env-gated mainnet-fork scenario; it is demo-grade and unaudited, but the pattern is proven against Midnight's actual interfaces (mirrored from `morpho-org/midnight` main, July 2026).

**How to use it in the tranche layer — adopt the Midnight gate interface verbatim rather than inventing one:**

- Add `Params.seniorGate` / `Params.juniorGate` as `IEnterGate` pointers, immutable at deployment (Midnight's choice, consistent with `minJuniorBips` being immutable here — mutability, where a policy needs it, lives inside the gate via its provider sets, not in the controller).
- Check `canIncreaseCredit(receiver)` in `_deposit` and in `beforeTrancheTransfer` on the recipient — the two places tranche exposure can increase. Never in `requestRedeem`, `claim`, or on the sender. "Increase credit" is the semantically correct verb for gaining lender-side tranche exposure, which is why the interface transfers without strain.
- `address(0)` short-circuits to today's behaviour. The sanctions sentinel stays hardwired and non-optional; gates are additive policy on top, never a replacement for it.

Adopting the interface rather than the shape means **one gate deployment serves both worlds**: the same `WildcatRoleProviderGate` instance that credentials a Midnight market can be pointed at by a tranche set, and the whole existing Wildcat credential stack — balance gates, soulbound markers, Merkle allowlists, sealed-entity-credential providers — reaches the tranche layer with zero new policy code. F8 stops being a design question and becomes provider selection: senior open (zero gate), senior = the market's own credentialed lenders (a provider wrapping the market hook), or whatever a Loan Agreement requires. The junior whitelist (`juniorAllowed` / `setJuniorAllowed`) migrates out of the controller into a provider on the junior gate's CREDIT set, shrinking the audited core (rule 6).

**The `ILiquidatorGate` analogue needs no code at all.** There are no liquidations here; the nearest gated distress actor is the `defaultDeclarer`. It is already an arbitrary address, so a gate-shaped policy contract — the demo's LIQUIDATE role, an M-of-N of lenders, or an attestation matching the Loan Agreement — can sit behind it today with zero controller changes.

### 12.4 The sealed-credential convergence: one predicate, both consequences

The draft ERC's borrower-side provider (`SealedCredentialRoleProvider`) pins trigger class `WILDCAT_DELINQ_90D_V1` — **the same grace-plus-90-days predicate as this controller's `defaultReached()`**. That's not a coincidence to note in passing — it's a mechanism to use. If Six Seven Ltd carries a sealed entity credential bound to that trigger class, then on the day `timeDelinquent ≥ grace + 90d` becomes true, two things latch off the same on-chain fact:

- the tranche controller enters **wind-down** — deposits freeze, senior accrual stops, recoveries pay senior-first; and
- the borrower credential's **disclosure trigger** becomes latchable — Tier S1 (officer names, recourse instructions) unseals publicly, and Tier S2 (service contacts, identity evidence) unseals to qualified recipients.

That closes the loop on "recovery is part code, part courtroom", which the fine print has carried all along. The code half (senior-first cash allocation) and the courtroom half (a defined recourse path to the legal entity) would arm on the same block, with no declarer discretion in either. The demo's providers also withdraw a borrower's *entry* credential the moment the trigger merely becomes **latchable** — so a defaulting-in-progress borrower is barred from originating new obligations before the default even finalises. The tranche analogue is automatic [deposits require `Status.Active`], and it's reassuring that the two systems made the same conservative choice independently.

For this facility the sequencing implication: the trigger contract the credential binds should read the abcUSDC market's grace tracker. With the given terms it latches at day 118 (§8.1), and the senior sales conversation can then say, accurately, that *both* priorities arm together, on-chain, at a knowable time.

### 12.5 The one behavioural delta to document

In Midnight a reverting enter gate blocks only new entries. Here, because the recipient check sits in the transfer hook, a reverting `seniorGate` would also freeze **secondary transfers** of senior — the token degrades to hold-or-exit until the gate recovers. Exits remain live throughout (the burn path never calls the gate), so nothing is trapped; but it is a stronger liveness dependency than Midnight's, and it is the failure mode Vault V2's "gates must never revert" rule exists for. `WildcatRoleProviderGate` already handles it at the provider level (guarded staticcalls, misbehaving providers skipped), so the residual risk is only a gate that is *itself* broken — mitigated by using that one audited gate implementation everywhere rather than bespoke gates per market.

**Cost and sequencing:** a `Params` extension, two short-circuit checks against the mirrored `IEnterGate` interface, a provider wrapping the current junior whitelist — plus tests. It touches the same struct as the symbol fix (§11), so both belong in one small pre-deployment PR for abcUSDC. The gate contract itself comes from `secdemo-gateaccess` hardened to production (it is explicitly demo-grade today), which is work that serves the Midnight integration and the tranche layer at once.

---

## 13. Sequencing

The register at the top of this document lists the open calls; this is the order to take them in, because some block others:

1. **Put the §8 findings to both buyers.** The 118-day default clock, the no-early-warning delinquency trigger, and junior's immediate floor breach during any delinquency are all consequences of the given terms (reserve ratio 0, grace 28d). Negotiate grace toward 14 days if possible; place junior above the floor either way.
2. **Settle F8 via the gate mechanism (§12).** Adopt Midnight's `IEnterGate` interface in `Params`, back it with `WildcatRoleProviderGate` from `secdemo-gateaccess` (hardened from demo-grade), and decide the senior provider set for this facility — recommendation: a provider wrapping the market's own credential hook if Six Seven Ltd's market runs one; zero gate otherwise. Require Six Seven Ltd to carry a sealed entity credential bound to the `WILDCAT_DELINQ_90D_V1` trigger class so recourse disclosure latches on the same day-118 predicate as wind-down (§12.4).
3. **Fix the hardcoded token symbols.** Blocks deployment on abcUSDC. Trivial; same PR as the gates.
4. **Add `claimMany`.** A 14-day cycle accumulates request IDs faster than a long one.
5. **Confirm the placement sequence with BD.** Junior first, 1,000,000 of it, then 4,000,000 of senior. If that ordering is commercially unworkable, `minJuniorBips` has to change *before* deployment, because it is immutable.
6. **Commission human audit** before real capital, and correct the audit language in `BD-Primer.md`.
7. **Write the distress gate back into `Design-Risk-Specification.md`.** The spec currently understates what Q11 actually became.

---

*Derived from `build/src/` at commit `48cc01d`. Facility terms as provided (reserve ratio 0, 28-day grace). Tranche parameters in §2 are proposals, not settings. External sources for §12: Morpho Midnight docs, whitepaper, and repository as linked. Deployment and governance design: `Deployment-Access-Governance-Notes.md`.*
