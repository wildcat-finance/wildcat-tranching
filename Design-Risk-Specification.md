# Design & Risk Specification: Wildcat In-House Tranching

*The design and risk specification for Wildcat's senior/junior tranching. Each decision is stated with the alternatives considered and the rationale; the closing section states the resulting system. Sections I–VIII (Q1–Q16) are implemented and tested (`build/src/`, two adversarial audit cycles); section IX (Q17–Q21) records the access, deployment and entry decisions from the abcUSDC facility iteration, now also implemented (69 tests passing: 65 local + 4 mainnet-fork including a live USDC round trip). Facility-specific analysis lives in `report/Six-Seven-Mechanisms-Report.md`; deployment and governance detail in `report/Deployment-Access-Governance-Notes.md`.*

## Status & decisions outstanding

| Status | Scope |
|---|---|
| **Implemented & audited** | Q1–Q16, including the audit-cycle hardening folded into their answers below (distress-gated allocation, accrual-before-freeze, live-price exit sizing, balance-derived recovery, two-step rotations) |
| **Implemented, awaiting review** | Q17–Q21 plus per-market token metadata — landed as the pre-deployment change set, nothing in the waterfall touched; the USDC entry path ships to production only after the ToU/MLA legal answer |
| **Open** | Foundation sign-off on the Q19 deployment posture · governance holder per facility (Q21) · ToU/MLA papering for tranche-only buyers (Q18) · recovery bit default per facility (Q21) · senior gate provider set per facility (Q17) · human audit engagement before real capital |

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

### Q1. What does the tranche layer wrap: the raw market token, or the `v-` 4626 wrapper?
- **(a)** Wrap the raw rebasing market token directly.
- **(b)** Wrap the audited `Wildcat4626Wrapper` (`v-` shares) as the underlying.
- **(c)** Build a single bespoke contract that re-implements wrapping + tranching together.

**Decision:** (b), wrap the market's 4626 wrapper.
**Why:** it is already deployed and audited, it converts rebasing to non-rebasing without extra work on our side (the `scaleFactor` math is solved), and it gives the tranche layer a standard ERC4626 underlying. Re-using audited code is the single largest reduction in both risk and cost available here. (Direct rebasing custody — option (a) — resurfaces as the deferred variant in Q18; the same rationale defers it.)

### Q2. Share-class structure: one multi-class vault, or two ERC4626 tokens + a controller?
- **(a)** One vault contract issuing two internal balance classes.
- **(b)** Two standalone tranche tokens (`sr-`, `jr-`) coordinated by a thin controller that holds the underlying and runs the waterfall.
- **(c)** A single ERC-1155 with senior/junior IDs.

**Decision:** (b), two tranche tokens plus a controller.
**Why:** this is the proven shape. Each tranche is a standard, independently-composable token, so integrators, accounting and permit all behave the way callers already expect. The controller isolates the waterfall logic in one auditable place, and senior and junior accounting stay separated. Token metadata is derived on-chain from the market's own symbol — `"Senior Tranched <SYM>"` / `sr-<SYM>` and the junior equivalents — so each facility's tranche set carries its own market's ticker with nothing caller-supplied.

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
- **(c)** An external benchmark oracle (e.g. Aave supply rate).
- **(d)** Derived live from the market's own base APR (`annualInterestBips`), scaled by a governance-set `seniorShareBips` and capped at the base APR.

**Decision:** (d), derived from the market's base APR.
**Why:** the borrower can move the facility APR over a perpetual line, so a fixed rate (a) or an absolute governance rate (b) drifts from what the borrower actually pays. A fixed coupon set above the facility APR is worse still: it makes junior subsidise senior out of principal even with no default, turning junior into a rate-risk taker. An external oracle (c) adds an attack and staleness surface. Reading the market's own published rate is not an oracle; it is the facility's own parameter. The effective rate is `currentSeniorRateBips() = annualInterestBips × seniorShareBips / BIPS`, capped at `annualInterestBips`, so senior always tracks the facility and junior bears credit risk rather than rate risk. `seniorShareBips` (≤ 100%) is governance-set behind the 48h timelock, and a pending proposal is cancellable before execution. The base rate is used, never the penalty rate, consistent with realised-only accounting (Q6). **Disclosure:** on an open-term facility both dials of the senior rate — the base APR and (where the borrower holds governance) the share — are borrower-controlled; senior buyers are told this in those words.

---

## III. Loss & impairment (the crux)

### Q5. What event constitutes a loss, and who declares it?
- **(a)** **Realised shortfall only**, derived automatically from on-chain market state (market closed and recovered assets < principal; or an expired withdrawal batch finalised below par).
- **(b)** A **time-based mark-down** that begins when the market goes delinquent.
- **(c)** **Continuous mark-to-market** from a NAV/valuation oracle or a guardian's declaration.

**Decision:** (a), realised shortfall only, automatic from on-chain facts, no human discretion.
**Why:** delinquency on a Wildcat market is *late*, not *lost*. Penalty APR is accruing and principal may still be repaid, so writing it down (b) socialises a paper loss that can reverse and punishes whoever exits at the wrong moment. Oracles and guardians (c) add trust and dispute risk to the most sensitive path in the system. A loss is only booked when assets actually come back short.

**The terminal default trigger.** "Realised shortfall only" needs a definite end to indefinite delinquency, and Wildcat defines one in the Terms of Use rather than in code. ToU §6.2: once a market "has incurred the penalty rate (as determined by the grace tracker) for a continuous period of ninety (90) days, [the] Market will be considered in default", and a bilateral Loan Agreement, where present, supersedes this. Note that this is not the 90-day *cap* on the grace period (`MaximumDelinquencyGracePeriod`): default requires exhausting grace and then lapping it by 90 days of active penalty (`timeDelinquent ≥ delinquencyGracePeriod + 90 days`). The inputs are all on-chain (the grace tracker / `timeDelinquent`, which ratchets down on cure rather than resetting), so the controller mirrors the ToU condition deterministically as its on-chain wind-down trigger without it being gameable. On trigger: freeze deposits; halt senior-target accrual — with the final period's interest booked *before* the freeze, since every state-changing path accrues before testing for default; an understated `seniorOwed` would enlarge junior's ceiling at the distress gate (Q11) and leak recovery ahead of senior priority. Then: queue recovery; pay senior-first, junior-residual as cash arrives. Because ToU "default" is a legal status whose remedies are off-chain (enforcement, legal action) and supersedable by a Loan Agreement, the trigger is per-market configurable: the default mirrors grace+90d, and an optional designated declarer can front a Loan-Agreement market's own terms. Recovery is whatever the off-chain process eventually routes back on-chain. The loss therefore stays realised rather than becoming a timer-driven paper write-down, and is restored to junior first if the borrower cures.

### Q6. Accounting during delinquency: do `scaleFactor` gains count as profit?
- **(a)** Book all `scaleFactor` accrual (incl. penalty APR) as distributable profit as it accrues.
- **(b)** Recognise **only realised (paid, liquid) value**; treat accrual that hasn't been paid out by the market as **unrealised** and non-distributable.
- **(c)** Mark down on delinquency (mirror of Q5b).

**Decision:** (b), recognise only realised value; delinquent accruals are unrealised.
**Why:** during delinquency the market token's value rises on paper (penalty APR), but that value is illiquid and may never be paid. Letting junior book it as profit (a) would let junior holders withdraw phantom gains that then reverse into a senior loss on default. Valuation is held at a high-watermark that advances only while the market is non-delinquent, so unrealised penalty accrual is never booked. Exits requested during delinquency are **sized against the live wrapper price while valued at the frozen mark**, so the unrealised appreciation stays in the pool for remaining holders rather than being extracted by the exiter.

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
- **(b)** A **dynamic curve** (leverage/utilisation-based).
- **(c)** No enforcement; free float.

**Decision:** (a), fixed minimum plus hard gating.
**Why:** it is predictable, easy to reason about and audit, with no curve math. Senior deposits are capped and junior withdrawals are blocked whenever they would push the junior cushion below the minimum. A consequence to keep in view when structuring: the gates are *exactly* binding at the floor, so a facility placed with junior exactly at the minimum is pinned — no senior can enter and no junior can leave until junior is topped up above the floor. Placement sequencing is junior-first by construction, and junior is best placed with headroom above the floor rather than on it.

### Q9. How thick is the junior cushion (max senior leverage)?
- **(a)** **Junior ≥ 20%** of TVL (senior ≤ 4×).
- **(b)** Junior ≥ ~10% (senior ≤ ~9×).
- **(c)** Junior ≥ 5% (senior ≤ ~19×).

**Decision:** (a), junior ≥ 20%, senior ≤ 4×.
**Why:** this tranches single-borrower undercollateralised credit, where a default can impair a large fraction of principal at once, rather than a diversified, slowly-marked liquid pool. A 20% first-loss cushion means junior absorbs a 20% principal haircut before senior is touched. Thin leverage suits low-volatility liquid yield, not binary credit risk.

---

## V. Redemptions & liquidity

### Q10. Redemption model against a semi-liquid underlying.
- **(a)** Synchronous redemptions from an idle buffer the vault keeps liquid.
- **(b)** **Asynchronous request → execute**, mirroring the market's batch/expiry queue (ERC-7540-style): the vault queues a withdrawal on the market, waits for batch expiry, executes, then releases.
- **(c)** No native redemption; exit only via a secondary AMM.

**Decision:** (b), async, mirroring the market's withdrawal queue.
**Why:** the underlying is only semi-liquid (batched, expiry-dated, pro-rata). Async settlement is the model that matches reality: it passes the real liquidity profile through to tranche holders and makes no instant-liquidity promise the protocol can't keep. It also prevents anyone from front-running a loss, because a redeemer's exit settles at the post-event state, not the pre-event one. Recovery crediting is **balance-derived** (`recoveredUSDC = idle balance + total claimed`), with a permissionless `sync()`, so cash arriving outside the poke path — a third party executing the withdrawal, a direct transfer, recovery above queued face — is captured rather than stranded.

### Q11. Allocating partial/short batch proceeds across tranches.
- **(a)** **Senior-priority waterfall**: settled proceeds pay senior claims (principal + accrued target) first, junior gets the residual.
- **(b)** Pro-rata across all requesters regardless of tranche.
- **(c)** Junior-first.

**Decision:** (a), senior-priority waterfall on every settlement, **hardened with a distress gate**: while the market is delinquent *or* the vault is in wind-down, junior may only draw settled cash beyond the **entire senior obligation** (`seniorOwed`) — not merely the senior face actually queued. While healthy, only the queued senior face is reserved.
**Why:** subordination must hold on liquidity, not just on solvency. Senior is paid out of whatever comes back before junior, which is the same ordering as the loss waterfall applied to cash flow. The distress gate closes the slow-motion-default case: without it, first-loss capital could queue and exit against settled cash during a deepening delinquency while unqueued senior waited on a claim the recovery could no longer cover. Reserving the full live obligation under distress protects senior that has not yet queued, which is what "first-loss" has to mean under stress. This does mean senior can exit ahead of a slow-developing loss and concentrate it on remaining junior — the intended meaning of subordination.

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
**Why:** it is deterministic, manipulation-resistant, and consistent with "realised only" (Q5/Q6). Senior's price rises predictably by the funded target; junior gets everything left over after senior and after any realised loss. MEV on the yield side is negligible (interest accrues smoothly per block), and MEV on the loss side is neutralised by async settlement (Q10) plus live-price exit sizing (Q6), so no separate oracle or vesting machinery is required. Accrual is update-driven and compounds at interaction frequency, mirroring the market's own behaviour; the realised senior rate therefore sits slightly above the nominal target, bounded by the facility's own accrual.

---

## VII. Compliance & eligibility

### Q14. Where are KYC/sanctions enforced, given the vault pools many lenders?
- **(a)** Inherit only the market's check (the vault is the lender; individuals invisible).
- **(b)** **Re-enforce per-user at the vault layer**: check the Wildcat sentinel on every deposit/redeem/transfer, and route a sanctioned user's redemption to a per-user escrow, exactly as the 4626 wrapper does.
- **(c)** Permissionless tranches, no KYC.

**Decision:** (b), re-enforce the sentinel per-user at the vault.
**Why:** pooling otherwise destroys Wildcat's compliance guarantees, since the market can only "nuke" the whole vault rather than one user. The 4626 wrapper already implements this pattern. Under the Q18 entry surface this layer is not merely parallel protection but the **only** per-user policy a USDC-entry buyer ever meets, together with the Q17 gates.

### Q15. Who may hold junior vs senior?
- **(a)** Both open to any KYC'd lender.
- **(b)** **Junior restricted to whitelisted/qualified first-loss providers; senior open** to the market's standard KYC'd lenders.
- **(c)** Both restricted.

**Decision:** (b), junior whitelisted, senior open — with the enforcement mechanism generalised into the Q17 entry gates, where the junior whitelist becomes the default junior-gate provider and senior's policy becomes a per-facility choice.
**Why:** junior is leveraged first-loss credit risk, so it should be sold only to sophisticated providers who understand it. Restricting junior reduces mis-selling and legal risk, and it matches who actually supplies first-loss capital in practice.

---

## VIII. Governance & lifecycle

### Q16. Upgradeability, pause powers, wind-down, and deployment.
- **(a)** Upgradeable proxy (UUPS) for everything; broad guardian powers; permissionless per-market deployment.
- **(b)** **Immutable logic + a bounded, timelocked parameter set; pause halts *deposits* only and never blocks senior redemptions; deterministic automatic wind-down on default/close; a protocol-level factory.**
- **(c)** Fully immutable with zero parameters and permissionless deployment.

**Decision:** (b).
**Why, point by point:**
- *Immutable logic + bounded timelocked params*: matches Wildcat's immutable-market ethos. Logic can't be rugged via upgrade, but the few economic knobs (senior share, junior eligibility) remain adjustable within hard limits. New versions are new deployments.
- *Pause deposits only, never exits*: prevents any honeypot scenario, since users can always leave by the same path the underlying allows.
- *Automatic wind-down*: on default or closure the controller halts senior accrual and distributes arriving proceeds strictly by the seniority waterfall (with the Q11 distress reserve). This is where a real loss crystallises and junior takes the hit, with no human in the loop.
- *Protocol-level factory*: the `TrancheFactory` rides Wildcat's own registry rails (`WildcatArchController`, `isRegisteredMarket`), one live tranche set per registered market. Deployment access, parameter surface, and replacement policy are specified in Q19–Q20.
- *Role rotations are two-step everywhere*: governance and factory-level roles propose a successor who must accept, so a role can never be stranded on a typo'd or call-incapable address.

The governance role itself has no interface — the controller never calls into it; the requirement is behavioral (anything that can originate arbitrary calls: EOA, Safe, timelock, DAO executor). Its powers: the senior-share proposal/cancel (48h timelock, bounded), junior eligibility, deposits-pause, declarer assignment, rotation — and `declareDefault`, the one **un-timelocked, irreversible** power. Holder selection per facility is an open commercial decision; recovery of a lost holder is Q21.

---

## IX. Access, deployment & entry

*Implemented alongside Q1–Q16 (one pre-deployment change set, plus the per-market token metadata from Q2). Nothing in this section touches the waterfall.*

### Q17. How is entry to the tranche tokens gated?
- **(a)** Hardcoded per-class policy in the controller (junior whitelist mapping; senior open to any non-sanctioned address).
- **(b)** A four-gate Vault-V2-style set, including send-side gates on transfers out and asset withdrawals.
- **(c)** **Midnight-style entry gates**: two optional gate pointers (`seniorGate`, `juniorGate`) implementing Morpho Midnight's `IEnterGate`, fixed at deployment, checked only where tranche exposure *increases* (deposit receiver, transfer recipient), `address(0)` = unrestricted. The sanctions sentinel (Q14) stays hardwired underneath.

**Decision:** (c).
**Why:** entry-only gating is rule 5 made structural — mint and burn bypass the transfer hook and `claim` pays USDC directly, so a gate cannot block an exit even if it reverts unconditionally. Send-side gates (b) can trap exits, which their own documentation flags as the critical risk; that half is explicitly not imported. Adopting Midnight's interface *verbatim* rather than a bespoke one means a single gate deployment — the `WildcatRoleProviderGate` pattern, which bridges Wildcat's existing `IRoleProvider` credential stack (pull/push providers, TTLs, fail-closed staticcalls, one-way freeze) to Midnight's gate interfaces — serves Midnight markets and tranche sets alike. The Q15 junior whitelist migrates into a provider on the junior gate, shrinking the audited core (rule 6). Senior's policy becomes per-facility provider selection: open (zero gate), the market's own credentialed lenders (a provider wrapping the market hook), or whatever a Loan Agreement requires. A borrower sealed-entity credential pinned to the `WILDCAT_DELINQ_90D_V1` trigger class latches recourse disclosure on the *same* grace+90d predicate as the Q5 wind-down trigger, so the on-chain and courtroom halves of recovery arm together. **Open:** the provider set per facility; gate-author guidance (return `false`, don't revert — a reverting senior gate degrades senior to hold-or-exit until it recovers, though exits stay live throughout).

### Q18. What asset do depositors bring?
- **(a)** Wrapper shares only (`v-`), lenders run the market-deposit and wrap hops themselves.
- **(b)** Also accept the market token, auto-wrapped inside deposit.
- **(c)** **A USDC front door**: the controller deposits into the market itself as **lender of record**, wraps the minted market tokens internally, and accepts all three assets (USDC / market token / `v-`) through one valuation path.
- **(d)** Direct rebasing custody: drop the wrapper and hold the market token.

**Decision:** (c), with (d) deferred to a v2.
**Why:** the exit path already operates the controller as a market lender (`queueWithdrawal` / `executeWithdrawal`), so (c) completes an existing pattern rather than introducing one — entering as a wrapper-user but exiting as a market lender was asymmetry without benefit. The 4626 wrapper is precedent for a pooled contract-lender in the holder-of-claims sense; (c) extends it exactly one step, to pooled *depositor*, whose only new prerequisite is that the borrower credentials the controller under their market's hooks policy at deployment (a missed step fails loudly — deposits revert). The wrapper stays in the custody path because the entire audited valuation core (watermark, freeze, live-price sizing) is written against wrapper shares; (d) rewrites that core against `scaleFactor` and reopens the audited surface for a benefit buyers can't see — the Q1 rationale, applied again. Consequences owned: the buyer base decouples from the market's access policy (a USDC-entry buyer never becomes a market lender), which makes the Q17 gates plus Q14 sentinel the *entire* per-user compliance surface, and moves ToU/MLA acceptance to the tranche layer — **open, legal**, and gating this feature's ship date. Market capacity applies at deposit exactly as it would to any lender.

### Q19. Who may deploy a tranche set, and what does deployment do?
- **(a)** A factory owner (protocol ops) deploys on request.
- **(b)** The Foundation deploys on borrower application, parameters passed through.
- **(c)** Permissionless.
- **(d)** **Borrower-gated, ownerless**: `deployTranches(market, …)` requires `msg.sender == market.borrower()`; all neutrality lives in hard-coded bounds; the factory resolves the market's canonical 4626 wrapper and **deploys it in the same transaction if missing** (the wrapper factory is permissionless; the compose is idempotent).

**Decision:** (d).
**Why:** Wildcat Labs and the Foundation are bound to neutrality — they cannot select or endorse an attachment point, so (a) is untenable and (b) is (a) with extra ceremony and worse optics. (c) re-opens slot-squatting with hostile parameters. (d) is squat-proof without any trusted party — exactly one address in existence can deploy for a given market, the one with the legal identity behind the facility — and borrower-set terms are not a deviation from Wildcat's model but the model itself: the borrower already sets every term lenders face on a base market. Lender protection is structural (bounds in code: floor ∈ [5%, 90%], window ≤ 90d, share ≤ 100%; registration check; wrapper resolution) and economic: the Q8 gates make a fresh set unable to accept senior until whitelisted first-loss capital funds it, so **parameters are ratified by the first junior deposit** — a badly-parameterised set is inert, not a trap. One borrower transaction brings up the full stack atomically: wrapper (if absent), controller, both tokens. The borrower supplies economics, governance, and the optional declarer; wrapper, sentinel, borrower identity, and token metadata are all resolved or derived, not supplied. **Open:** Foundation sign-off on this posture before the factory is built.

### Q20. How many tranche sets per market?
- **(a)** Concurrent sets with different parameters.
- **(b)** Strictly one, ever.
- **(c)** **One live set, with supersession**: a replacement may be deployed only when the incumbent is empty or wound down; the old set retires (deposits closed, exits live forever); the registry points at the current one.

**Decision:** (c).
**Why:** subordination is internal to a controller; at the market layer, two controllers are pari-passu lenders whose withdrawal claims fill pro-rata from the same batches. Under stress, one set's *senior* would compete on equal footing with another set's *junior* for the same cash — "senior on this facility" would stop meaning one thing, which guts the product's core claim. Concurrency (a) also fragments junior capital (the scarce input) and prices one credit risk twice. But (b) fails on the fact that the risk parameters are immutable: a mis-set floor or renegotiated terms need a replacement path. Supersession provides it with zero pari-passu exposure.

### Q21. Can a lost governance role be recovered?
- **(a)** No recovery; a lost role freezes the parameter set forever.
- **(b)** The deployer (borrower) holds a standing power to replace governance.
- **(c)** **A dead-man's switch with an incumbent veto**, whose existence is a per-deployment bit: `reclaimGovernance(next)` callable only by `market.borrower()`, behind a ~30-day timelock, loudly evented, cancellable by the incumbent governance with a single call at any time during the window, and completing through the standard two-step acceptance.

**Decision:** (c) as the mechanism; each facility chooses the bit at deploy (recommended default **off**); (b) rejected outright.
**Why:** (b) makes the deployer the real governance with extra steps — any lender-side governance named as a selling point would be revocable exactly when it mattered. (a) is genuinely defensible because frozen governance is a *safe* state here (immutable logic, immutable floor, share frozen at last value, exits ungateable, and the Q5 terminal trigger fires with no governance at all) — which is why the bit exists and why "off" is a legitimate, sellable choice. Where recovery is wanted, the veto construction is the only shape that preserves both properties: dead governance cannot veto, so recovery completes; live governance vetoes in one transaction, so takeover against a functioning holder is impossible — the recovery path is strictly weaker than the role it recovers. Adjacent fix in the same area: `setDefaultDeclarer` gains a deliberate path to zero, so the discretionary default trigger can be *retired* back to the pure ToU mirror rather than only ever replaced — one-way doors should point toward less discretion.

---

## The resulting system

A credit-tranche vault over the audited market 4626 wrapper: oracle-free, event-driven, thick first-loss, async-exit, immutable-logic. Deployed by the borrower inside code bounds, ratified by first-loss capital, gated at entry only, and governed by a role that can tune but never trap.

**Contracts**
- `TrancheController`: immutable orchestrator (`ReentrancyGuard`, `SafeTransferLib`). Holds the wrapper shares; under Q18 also the market lender of record for USDC entry; runs the yield waterfall, the distress-gated loss/cash waterfall, subordination gating, and the async redemption queue; re-enforces the Wildcat sentinel per user, routing sanctioned redemptions to escrow; recovery balance-derived with permissionless `sync()`.
- `senior` / `junior` tranche tokens: Solady ERC20 + EIP-2612 permit with an ERC-4626 value-view surface; per-market name/symbol derived from the market. Junior gated by the whitelist provider (mandatory); senior policy per facility (Q17).
- `TrancheFactory`: ownerless, borrower-gated, bounds-in-code (Q19). One live set per registered market with supersession (Q20). Composes wrapper deployment.
- Reused: `Wildcat4626Wrapper`, `WildcatSanctionsSentinel` + escrow, the Wildcat market withdrawal queue; Solady `ERC20` / `ReentrancyGuard` / `SafeTransferLib`; Morpho Midnight `IEnterGate` + the `WildcatRoleProviderGate` bridge (Q17).

**Parameters**
- Subordination: junior ≥ 20% of TVL (senior ≤ 4×), enforced by gating senior deposits and junior withdrawals; exactly binding at the floor (place junior above it).
- Senior: target rate derived live as `annualInterestBips × seniorShareBips / BIPS`, capped at the base APR; `seniorShareBips` (≤ 100%) governance-set behind a 48h timelock, proposals cancellable. Priority on realised yield; no guarantee once junior is exhausted.
- Losses: recognised only on realised shortfall; junior → senior; no reserve; no oracle; no discretion.
- Default trigger: `timeDelinquent ≥ delinquencyGracePeriod + 90 days` (ToU §6.2 mirror), per-market configurable, plus a Loan-Agreement `declareDefault` override (declarer retirable to zero via clearDefaultDeclarer).
- Redemptions: async, mirroring the market's batch/expiry queue; senior-priority allocation with the full-obligation distress reserve; exits sized at the live price during delinquency; no instant buffer.
- Accounting: realised-only, valuation frozen at a high-watermark while delinquent; accrual booked before any default freeze.
- Compliance: sentinel re-checked per user incl. escrow; entry gates per facility (junior gate mandatory); junior whitelisted via the default provider.
- Lifecycle: immutable logic; pause halts deposits only, never senior exits; automatic waterfall wind-down on default/close; borrower-deployed, one live set per market, supersession on empty/wound-down; governance recovery per-facility bit (30d window, incumbent veto).

**Behaviour across the four states**
- *Healthy:* interest accrues via `scaleFactor`; senior takes its target, junior takes the (leveraged) rest. Deposits and redemptions flow through the async queue, with subordination respected; allocation reserves queued senior face.
- *Delinquent (late rather than lost):* no write-down; the mark freezes at the watermark while `seniorOwed` continues to accrue. New deposits may pause, junior withdrawals gate to preserve the cushion, exits size at the live price, and the distress gate reserves the full senior obligation out of any settled cash. A junior placed exactly at the floor breaches subordination immediately on delinquency (nothing reverts; the facility freezes to new senior until cured or topped up — and a top-up during delinquency credits at the frozen mark, disadvantaging the voluntary depositor).
- *Default / wind-down (closure-with-shortfall OR grace exhausted and lapped by the penalty window):* deposits frozen; senior-target accrual halts, final period booked; recoveries pay senior-first, junior-residual. Loss is booked here as the realised terminal shortfall, junior to zero before senior is touched, restored to junior first if the borrower later cures.
- *Terminal:* market fully repaid (everyone whole, junior keeps its accrued) or fully written off (junior wiped, senior takes any residual loss).

---

## Design characteristics & edge cases

- Indefinite delinquency is bounded by the terminal default trigger (Q5): grace + penalty window of accumulated delinquency, per-market configurable. Because `timeDelinquent` decays on cure, a borrower who cures inside grace repeatedly never pays penalty and never approaches the trigger — the width of grace sets the width of that orbit, which is a term-sheet fact, not a code defect.
- The senior "target" is a priority claim, not a guarantee. The contract enforces priority rather than solvency, and UI and legal copy state this plainly.
- First-deposit inflation/donation is guarded by a minimum initial deposit, with share conversions rounding down.
- Rounding: every conversion rounds against the user, in favour of the pool, so dust never accrues to a single tranche.
- Senior exiting ahead of a slow loss concentrates it on remaining junior, which is the intended subordination. Junior exit gates precisely when the cushion is thin, and the distress gate (Q11) holds settled cash against the full senior obligation while delinquent.
- Deposits during delinquency credit at the frozen mark and so under-credit the depositor relative to live value; this follows from realised-only valuation and disadvantages only the voluntary depositor — including a junior provider topping up a breached floor, which is worth pricing into any junior-anchor arrangement.
- Composability: the tranche tokens are transferable (senior subject to its per-facility gate) and composable; integrators should account for credit-event cascade risk if they are used as collateral elsewhere.
- Governance holds one undelayed power (`declareDefault`); everything else it can do is bounded, timelocked, entry-only, or deposits-only. Choose the holder accordingly.
