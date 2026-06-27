# Design & Risk Specification: Wildcat In-House Tranching

*The design and risk specification for Wildcat's senior/junior tranching. Each decision is stated with the alternatives considered and the rationale; the closing section states the resulting system.*

The conservative bias behind every decision below:
1. Protect senior principal above all.
2. Never create an unfunded obligation the contracts can't honour from real assets.
3. Recognise losses only when realised, never on paper and never on an oracle's say-so.
4. Minimise trust, discretion, oracle and upgrade surface.
5. Never trap a user's exit.
6. Prefer a thick first-loss cushion over leverage, and where two safe options exist, prefer the simpler one (fewer lines = fewer bugs = cheaper audit).

A structural property of Wildcat shapes everything: the market token's `scaleFactor` only ever increases (interest). So a junior tranche cannot lose money from price moves, only from a credit event (borrower default, or market closure with a shortfall). The model is therefore event-driven rather than mark-to-market, with no continuous loss accounting and no valuation oracle.

---

## I. Architecture

### Q1. What does the tranche layer wrap: the raw market token, or the `v-wmtUSDC` 4626 wrapper?
- **(a)** Wrap the raw rebasing market token (`wmtUSDC`) directly.
- **(b)** Wrap the audited `Wildcat4626Wrapper` (`v-wmtUSDC`) as the underlying.
- **(c)** Build a single bespoke contract that re-implements wrapping + tranching together.

**Decision:** (b), wrap the `v-wmtUSDC` 4626.
**Why:** it is already deployed and audited, it converts rebasing to non-rebasing without extra work on our side (the `scaleFactor` math is solved), and it gives the tranche layer a standard ERC4626 underlying, which is the surface Strata/Royco are built for. Re-using audited code is the single largest reduction in both risk and cost available here.

### Q2. Share-class structure: one multi-class vault, or two ERC4626 tokens + a controller?
- **(a)** One vault contract issuing two internal balance classes.
- **(b)** Two standalone tranche tokens (`sr-`, `jr-`) coordinated by a thin controller that holds the underlying and runs the waterfall.
- **(c)** A single ERC-1155 with senior/junior IDs.

**Decision:** (b), two tranche tokens plus a controller.
**Why:** this is the proven Strata/Royco shape. Each tranche is a standard, independently-composable token, so integrators, accounting and permit all behave the way callers already expect. The controller isolates the waterfall logic in one auditable place, and senior and junior accounting stay separated.

---

## II. Senior economics

### Q3. Senior return type: fixed coupon, floor + priority, or pure priority?
- **(a)** Hard **fixed** coupon the protocol must pay regardless.
- **(b)** A **target rate funded by priority**: senior is paid its target first out of realised yield, topped up from junior NAV down to a floor; if junior is exhausted, senior simply earns whatever the underlying yields.
- **(c)** Pure pro-rata priority with no target at all.

**Decision:** (b), a priority claim to a target derived from the facility APR (Q4), not an unconditional guarantee.
**Why:** a hard fixed coupon (a) is an unfunded liability the contracts cannot honour in a default, which violates rule 2. Option (b) gives senior the economic experience of a fixed rate in all normal and most stressed states, while the contract only ever promises priority on assets that exist. "Guaranteed yield" stays a marketing description; the code never enforces solvency it can't back.

### Q4. Where does the senior target rate come from?
- **(a)** Immutable, fixed at deployment.
- **(b)** A governance-set absolute rate, within hard-coded bounds, behind a timelock.
- **(c)** An external benchmark oracle (e.g. Aave supply rate), as Strata uses.
- **(d)** Derived live from the market's own base APR (`annualInterestBips`), scaled by a governance-set `seniorShareBips` and capped at the base APR.

**Decision:** (d), derived from the market's base APR.
**Why:** the borrower can move the facility APR over a perpetual line, so a fixed rate (a) or an absolute governance rate (b) drifts from what the borrower actually pays. A fixed coupon set above the facility APR is worse still: it makes junior subsidise senior out of principal even with no default, turning junior into a rate-risk taker. An external oracle (c) adds an attack and staleness surface. Reading the market's own published rate is not an oracle; it is the facility's own parameter. The effective rate is `currentSeniorRateBips() = annualInterestBips × seniorShareBips / BIPS`, capped at `annualInterestBips`, so senior always tracks the facility and junior bears credit risk rather than rate risk. `seniorShareBips` (≤ 100%) is governance-set behind the 48h timelock. The base rate is used, never the penalty rate, consistent with realised-only accounting (Q6).

---

## III. Loss & impairment (the crux)

### Q5. What event constitutes a loss, and who declares it?
- **(a)** **Realised shortfall only**, derived automatically from on-chain market state (market closed and recovered assets < principal; or an expired withdrawal batch finalised below par).
- **(b)** A **time-based mark-down** that begins when the market goes delinquent.
- **(c)** **Continuous mark-to-market** from a NAV/valuation oracle or a guardian's declaration.

**Decision:** (a), realised shortfall only, automatic from on-chain facts, no human discretion.
**Why:** delinquency on a Wildcat market is *late*, not *lost*. Penalty APR is accruing and principal may still be repaid, so writing it down (b) socialises a paper loss that can reverse and punishes whoever exits at the wrong moment. Oracles and guardians (c) add trust and dispute risk to the most sensitive path in the system. A loss is only booked when assets actually come back short.

**The terminal default trigger.** "Realised shortfall only" needs a definite end to indefinite delinquency, and Wildcat defines one in the Terms of Use rather than in code. ToU §6.2: once a market "has incurred the penalty rate (as determined by the grace tracker) for a continuous period of ninety (90) days, [the] Market will be considered in default", and a bilateral Loan Agreement, where present, supersedes this. Note that this is not the 90-day *cap* on the grace period (`MaximumDelinquencyGracePeriod`): default requires exhausting grace and then lapping it by 90 days of active penalty (`timeDelinquent ≥ delinquencyGracePeriod + 90 days`). The inputs are all on-chain (the grace tracker / `timeDelinquent`, which ratchets down on cure rather than resetting), so the controller mirrors the ToU condition deterministically as its on-chain wind-down trigger without it being gameable. On trigger: freeze deposits; halt senior-target accrual (a defaulted loan stops minting contractual yield, so senior caps at principal + accrued-to-trigger); queue a full withdrawal; pay recoveries senior-first, junior-residual as cash arrives. Because ToU "default" is a legal status whose remedies are off-chain (enforcement, legal action) and supersedable by a Loan Agreement, the trigger is per-market configurable: the default mirrors grace+90d, and an optional designated declarer can front a Loan-Agreement market's own terms. Recovery is whatever the off-chain process eventually routes back on-chain. The loss therefore stays realised rather than becoming a timer-driven paper write-down, and is restored to junior first if the borrower cures.

### Q6. Accounting during delinquency: do `scaleFactor` gains count as profit?
- **(a)** Book all `scaleFactor` accrual (incl. penalty APR) as distributable profit as it accrues.
- **(b)** Recognise **only realised (paid, liquid) value**; treat accrual that hasn't been paid out by the market as **unrealised** and non-distributable.
- **(c)** Mark down on delinquency (mirror of Q5b).

**Decision:** (b), recognise only realised value; delinquent accruals are unrealised.
**Why:** during delinquency the market token's value rises on paper (penalty APR), but that value is illiquid and may never be paid. Letting junior book it as profit (a) would let junior holders withdraw phantom gains that then reverse into a senior loss on default. Valuation is held at a high-watermark that advances only while the market is non-delinquent, so unrealised penalty accrual is never booked.

### Q7. Loss-waterfall depth.
- **(a)** Two-tier: **junior → senior.**
- **(b)** Three-tier: junior → a protocol **reserve buffer** (funded by a yield skim) → senior.
- **(c)** Junior first-loss plus a separate junior-funded senior insurance pool.

**Decision:** (a), two-tier junior → senior, with the thick subordination ratio (Q9) serving as senior's cushion.
**Why:** a reserve (b) is a genuine second cushion, but it adds yield-skim accounting and another pot to get right, and with a conservatively thick junior (≥20%, Q9) the marginal protection is small. The waterfall is deliberately kept to the two-tier form.

---

## IV. Subordination

### Q8. How is subordination enforced?
- **(a)** A **fixed minimum** junior:senior ratio, enforced by blocking deposits/withdrawals that would breach it.
- **(b)** A **dynamic curve** (leverage/utilisation-based, Strata/Royco style).
- **(c)** No enforcement; free float.

**Decision:** (a), fixed minimum plus hard gating.
**Why:** it is predictable, easy to reason about and audit, with no curve math. Senior deposits are capped and junior withdrawals are blocked whenever they would push the junior cushion below the minimum.

### Q9. How thick is the junior cushion (max senior leverage)?
- **(a)** **Junior ≥ 20%** of TVL (senior ≤ 4×).
- **(b)** Junior ≥ ~10% (senior ≤ ~9×).
- **(c)** Junior ≥ 5% (senior ≤ ~19×, Strata-like).

**Decision:** (a), junior ≥ 20%, senior ≤ 4×.
**Why:** this tranches single-borrower undercollateralised credit, where a default can impair a large fraction of principal at once, rather than a diversified, slowly-marked liquid pool. A 20% first-loss cushion means junior absorbs a 20% principal haircut before senior is touched. Thin Strata-style leverage suits low-volatility liquid yield, not binary credit risk.

---

## V. Redemptions & liquidity

### Q10. Redemption model against a semi-liquid underlying.
- **(a)** Synchronous redemptions from an idle buffer the vault keeps liquid.
- **(b)** **Asynchronous request → execute**, mirroring the market's batch/expiry queue (ERC-7540-style): the vault queues a withdrawal on the market, waits for batch expiry, executes, then releases.
- **(c)** No native redemption; exit only via a secondary AMM.

**Decision:** (b), async, mirroring the market's withdrawal queue.
**Why:** the underlying is only semi-liquid (batched, expiry-dated, pro-rata). Async settlement is the model that matches reality: it passes the real liquidity profile through to tranche holders and makes no instant-liquidity promise the protocol can't keep. It also prevents anyone from front-running a loss, because a redeemer's exit settles at the post-event state, not the pre-event one.

### Q11. Allocating partial/short batch proceeds across tranches.
- **(a)** **Senior-priority waterfall**: settled proceeds pay senior claims (principal + accrued target) first, junior gets the residual.
- **(b)** Pro-rata across all requesters regardless of tranche.
- **(c)** Junior-first.

**Decision:** (a), senior-priority waterfall on every settlement.
**Why:** subordination must hold on liquidity, not just on solvency. Senior is paid out of whatever comes back before junior, which is the same ordering as the loss waterfall applied to cash flow. This does mean senior can exit ahead of a slow-developing loss and concentrate it on remaining junior, which is the intended meaning of subordination.

### Q12. Does the vault hold an instant-liquidity buffer?
- **(a)** **No buffer**: every exit goes through the async queue.
- **(b)** An optional uninvested buffer (X% kept liquid) for instant small exits.
- **(c)** A junior-funded liquidity facility.

**Decision:** (a), no buffer.
**Why:** a buffer is a UX nicety rather than a safety feature, and it introduces idle-asset accounting and a pot that can be gamed or drained first. Better to keep one exit path for everyone.

---

## VI. Pricing / NAV

### Q13. How are tranche share prices computed (and MEV handled)?
- **(a)** Split the underlying's `convertToAssets` purely pro-rata each block.
- **(b)** **Senior accrues via a deterministic target index** (time × target rate, off realised value); **junior NAV = realised underlying value − senior NAV**; losses only on realisation (Q5). No oracle.
- **(c)** External valuation oracle marks both tranches continuously.

**Decision:** (b), senior target index plus junior realised residual, oracle-free.
**Why:** it is deterministic, manipulation-resistant, and consistent with "realised only" (Q5/Q6). Senior's price rises predictably by the funded target; junior gets everything left over after senior and after any realised loss. MEV on the yield side is negligible (interest accrues smoothly per block), and MEV on the loss side is neutralised by async settlement (Q10), so no separate oracle or vesting machinery is required.

---

## VII. Compliance & eligibility

### Q14. Where are KYC/sanctions enforced, given the vault pools many lenders?
- **(a)** Inherit only the market's check (the vault is the lender; individuals invisible).
- **(b)** **Re-enforce per-user at the vault layer**: check the Wildcat sentinel on every deposit/redeem/transfer, and route a sanctioned user's redemption to a per-user escrow, exactly as the 4626 wrapper does.
- **(c)** Permissionless tranches, no KYC.

**Decision:** (b), re-enforce the sentinel per-user at the vault.
**Why:** pooling otherwise destroys Wildcat's compliance guarantees, since the market can only "nuke" the whole vault rather than one user. The 4626 wrapper already implements this pattern.

### Q15. Who may hold junior vs senior?
- **(a)** Both open to any KYC'd lender.
- **(b)** **Junior restricted to whitelisted/qualified first-loss providers; senior open** to the market's standard KYC'd lenders.
- **(c)** Both restricted.

**Decision:** (b), junior whitelisted, senior open.
**Why:** junior is leveraged first-loss credit risk, so it should be sold only to sophisticated providers who understand it. Restricting junior reduces mis-selling and legal risk, and it matches who actually supplies first-loss capital in practice.

---

## VIII. Governance & lifecycle

### Q16. Upgradeability, pause powers, wind-down, and deployment.
- **(a)** Upgradeable proxy (UUPS) for everything; broad guardian powers; permissionless per-market deployment.
- **(b)** **Immutable logic + a bounded, timelocked parameter set; pause halts *deposits* only and never blocks senior redemptions; deterministic automatic wind-down on default/close; a protocol-level factory.**
- **(c)** Fully immutable with zero parameters and permissionless deployment.

**Decision:** (b).
**Why, point by point:**
- *Immutable logic + bounded timelocked params*: matches Wildcat's immutable-market ethos. Logic can't be rugged via upgrade, but the few economic knobs (senior target, junior whitelist) remain adjustable within hard limits. New versions are new deployments.
- *Pause deposits only, never exits*: prevents any honeypot scenario, since users can always leave by the same path the underlying allows.
- *Automatic wind-down*: on default or closure the controller halts senior accrual and distributes arriving proceeds strictly by the seniority waterfall. This is where a real loss crystallises and junior takes the hit, with no human in the loop.
- *Protocol-level deployment*: the `TrancheFactory` is registered with the `WildcatArchController` and deploys one tranche set per **registered market** (gated on `isRegisteredMarket`), exactly like `Wildcat4626WrapperFactory`. This rides Wildcat's own deployment rails and registry rather than a bespoke gate, and per-market risk params (subordination, senior target, junior whitelist) are set at deployment within hard bounds.

---

## The resulting system

A credit-tranche vault over the audited `v-wmtUSDC` ERC4626: oracle-free, event-driven, thick first-loss, async-exit, immutable-logic.

**Contracts**
- `TrancheController`: immutable orchestrator (`ReentrancyGuard`, `SafeTransferLib`). Holds the `v-wmtUSDC` shares; runs the yield waterfall, the loss waterfall, subordination gating, and the async redemption queue; re-enforces the Wildcat sentinel per user, routing sanctioned redemptions to escrow.
- `senior` / `junior` (`sr-wmtUSDC` / `jr-wmtUSDC`): Solady ERC20 + EIP-2612 permit with an ERC-4626 value-view surface. Senior is open to KYC'd lenders; junior is restricted to whitelisted qualified first-loss providers.
- `TrancheFactory`: registered at the Wildcat protocol level (`WildcatArchController`), deploying one tranche set per registered market, gated on `isRegisteredMarket`, mirroring `Wildcat4626WrapperFactory`.
- Reused: `Wildcat4626Wrapper`, `WildcatSanctionsSentinel` + escrow, the Wildcat market withdrawal queue; Solady `ERC20` / `ReentrancyGuard` / `SafeTransferLib`.

**Parameters**
- Subordination: junior ≥ 20% of TVL (senior ≤ 4×), enforced by gating senior deposits and junior withdrawals.
- Senior: target rate derived live as `annualInterestBips × seniorShareBips / BIPS`, capped at the base APR; `seniorShareBips` (≤ 100%) governance-set behind a 48h timelock. Priority on realised yield, topped from junior down to a floor, no guarantee once junior is exhausted.
- Losses: recognised only on realised shortfall (market close / short batch settlement); junior → senior; no reserve; no oracle; no discretion.
- Default trigger: `timeDelinquent ≥ delinquencyGracePeriod + 90 days` (ToU §6.2 mirror), per-market configurable, plus a Loan-Agreement `declareDefault` override.
- Redemptions: async, mirroring the market's batch/expiry queue; senior-priority allocation of settled proceeds; no instant buffer.
- Accounting: realised-only, with valuation frozen at a high-watermark while delinquent.
- Compliance: sentinel re-checked per user incl. escrow; junior whitelisted.
- Lifecycle: immutable logic; pause halts deposits only, never senior exits; automatic waterfall wind-down on default/close; protocol-level factory, one tranche set per registered market.

**Behaviour across the four states**
- *Healthy:* interest accrues via `scaleFactor`; senior takes its target, junior takes the (leveraged) rest. Deposits and redemptions flow through the async queue, with subordination respected.
- *Delinquent (< 90 days penalised, late rather than lost):* no write-down. New deposits may pause, junior withdrawals gate to preserve the cushion, and senior keeps priority on whatever the market pays. Paper accrual is held unrealised.
- *Default / wind-down (closure-with-shortfall OR 90 cumulative days of penalised delinquency):* deposits frozen; senior-target accrual halts (claim caps at principal + accrued-to-trigger); a full withdrawal is queued; recoveries pay senior-first, junior-residual. Loss is booked here as the realised terminal shortfall, junior to zero before senior is touched, restored to junior first if the borrower later cures.
- *Terminal:* market fully repaid (everyone whole, junior keeps its accrued) or fully written off (junior wiped, senior takes any residual loss).

---

## Design characteristics & edge cases

- Indefinite delinquency is bounded by the terminal default trigger (Q5): the vault enters wind-down at grace + 90 days of penalty, per-market configurable to honour Loan-Agreement overrides. The on-chain proxy uses accumulated penalty time from the grace tracker.
- The senior "target" is a priority claim, not a guarantee. The contract enforces priority rather than solvency, and UI and legal copy state this plainly.
- First-deposit inflation/donation is guarded by a minimum initial deposit, with share conversions rounding down.
- Rounding: every conversion rounds against the user, in favour of the pool, so dust never accrues to a single tranche.
- Senior exiting ahead of a slow loss concentrates it on remaining junior, which is the intended subordination. Junior exit gates precisely when the cushion is thin.
- Composability: `sr-`/`jr-` tokens are transferable and composable, and integrators should account for credit-event cascade risk if they are used as collateral elsewhere.
