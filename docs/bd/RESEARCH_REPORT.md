# Wildcat tranching BD field kit: study

## Problem statement

Wildcat BD needs a source-grounded set of material for first and second conversations with prospective
borrowers, senior lenders and junior capital providers. It must work for crypto-native firms and
traditional credit teams without asking either audience to adopt the other's vocabulary first.

The material must explain four things accurately:

1. what the current tranching prototype does over one Wildcat market;
2. how capital enters, accrues, queues for exit and receives recovery;
3. which terms the borrower chooses, which terms come from the underlying market, which terms belong
   to the protocol, and which rules are fixed in code; and
4. which commercial questions BD should ask without turning a prototype or an accounting target into
   a promise.

For this topic, a working prototype is a repository-native field kit that a BD colleague can open at
one index, use to prepare for a call, and share in parts. It comprises a research report, a short
primer, a one-page meeting brief, a parameter discovery guide, a question-and-answer and claims guide,
and a gallery of static SVG infographics. The check is that every material protocol claim maps to the
contracts, tests or pinned upstream source; every diagram renders without an external service; and the
repository documentation and test gates still run.

### Chosen reading of the request

"Factory permits borrower-driven decisions" is read narrowly. The market borrower is the only account
that may call `TrancheFactory.deployTranches`, and it supplies the senior target rate, minimum junior
subordination, tranche wind-down window, both entry-gate addresses and the terminal recipient. Those
terms are fixed after one-time initialisation and bounded by the manager. The borrower does not receive
a general control plane and cannot use the tranching factory to replace code, change the waterfall,
redirect custody or set the protocol fee.

The underlying Wildcat market has a separate parameter surface. Some market terms originate with the
borrower and some remain mutable under Wildcat's own rules. The protocol fee and canonical deployment
dependencies do not belong to the tranche borrower. The field kit must show these as separate columns.

## Existing implementation and prior art

### Current repository

The source of truth is `wildcat-finance/wildcat-tranching` at
`b90a155f257c76f96e50cf2fa29872e1735f8bd8`, the current `main` when this run began.

- `build/src/TrancheFactory.sol` is an ownerless CREATE2 factory. It pins the ArchController, wrapper
  factory, singleton hook template and manager init-code hash, authenticates the existing market stack,
  and permits one manager per market.
- `build/src/TrancheManager.sol` is the sole underlying market lender, custody holder, tranche
  accountant, asynchronous exit queue and recovery allocator.
- `build/src/TrancheToken.sol` provides transferable senior and junior ERC-20 claims with EIP-2612
  support and an ERC-4626-shaped valuation view surface. It does not provide synchronous ERC-4626
  redemption.
- `build/src/TrancheOpenTermHooks.sol` authenticates close and withdrawal-execution callbacks from the
  bound market so the manager can stop accrual and attribute recovery to the correct batch.
- `build/src/libraries/WaterfallMath.sol` contains the simple-interest senior accrual, realised-value
  split, minimum-subordination checks and objective wind-down threshold.

Existing prose already establishes the technical design:

- `docs/ARCHITECTURE.md` defines custody, trust boundaries and invariants.
- `docs/IMPLEMENTATION_RUNBOOK.md` records the prototype build and integration assumptions.
- `docs/TRANCHER_LOGIC_REPORT.md` explains the accounting and lifecycle design.
- `docs/PROTOTYPE_HANDOFF.md` gives a short repository handoff.
- `docs/TRADFI_OUTREACH_PRIMER.md` is a useful first-conversation note, but it does not yet provide the
  parameter authority map, worked scenarios, crypto/TradFi translation, fee bridge, meeting runbook or
  infographic set requested here.
- `docs/RELEASE_EVIDENCE.md` records the compiler profile and test commands.
- `docs/V25_AUDIT_BUNDLE_ASSESSMENT.md` distinguishes missing trancher dependencies from errors in the
  separate V2.5 audit branch.
- `docs/assets/tranching-prototype-infographic.png` supplies an attractive topology image, but contains
  no explanatory labels for terms, fees, queues or distress.

On 15 August 2026, the selected conventional, fuzz, view and release suites reported 52
unit/integration tests, five fuzz tests, one view test and one release-evidence test passing. The exact
non-fork command was also attempted, but it ended before reporting the stateful property campaigns or a shell
exit status. Foundry emitted an unresolved-symbol diagnostic from the pinned SphereX source while
continuing through the reported suites. The result is therefore not recorded as a complete non-fork
baseline. The stateful property and fork suites remain part of the final verification step.

### Parameter authority established by the code

#### Borrower-selected once, through this factory

`TrancheFactory.DeployParams` and `TrancheManager.Params` establish the facility choices:

- `seniorRateBips`: 0 to 10,000 bips;
- `minJuniorBips`: 500 to 9,000 bips, or 5% to 90%;
- `defaultPenaltyWindow`: greater than zero and no more than 90 days;
- `seniorGate` and `juniorGate`: zero for open entry, otherwise a contract address;
- `terminalRecipient`: nonzero and not the predicted manager; and
- deployment salt, namespaced by the calling borrower.

The caller must equal both the supplied borrower and `market.borrower()`. The terms are written during
factory-only initialisation. There are no setters. A nonzero gate address is fixed, although the policy
inside that external gate may itself be mutable. The correct phrase is therefore "fixed gate contract",
not "immutable allowlist". The factory supplies no economic defaults: the borrower must submit every
one-time tranche term. A 0% senior target and open gates are valid choices.

The first deposit into either empty tranche class must be at least `1e6` raw base-asset units. The
human amount depends on the asset's decimals; the manager requires at least six decimals. This is a
fixed implementation constraint, not a borrower parameter.

#### Borrower-selected or borrower-operated in the underlying market

The Wildcat market is created before the tranching factory attaches a manager. At market creation the
borrower supplies market inputs such as capacity, lender APR, reserve ratio, withdrawal-batch duration,
delinquency fee and delinquency grace period, subject to the chosen hook template and protocol bounds.
The current generic bounds are 0 to 10,000 bips for APR, reserve ratio and delinquency fee; 0 to 90 days
for grace; and 0 to 365 days for the withdrawal-batch duration. The tranching factory narrows the
delinquency-fee range to 1 through 10,000 bips because it rejects a zero-fee market. Capacity is stored
as a `uint128`. The upstream market-hook minimum deposit is also a `uint128`, with zero meaning none.
Market capacity and APR retain borrower-authorised update paths under Wildcat rules. Reserve-ratio
changes travel with APR changes and can be constrained or derived by the OpenTerm hook rather than
accepted as a free borrower choice. The manager's senior target deliberately does not track a later
market APR change. The current hook administrator can change the upstream minimum deposit and block or
unblock the manager from making fresh market deposits. The role starts with the registered borrower
principal and can be transferred to another registered borrower under Wildcat's two-step
administrator-transfer rules. Its actions can suspend new tranche entry at the market layer without
changing the manager's economics, custody or exit waterfall.

#### Protocol or factory authority

The protocol-fee rate and fee recipient come from the Wildcat hook-template configuration selected
through the ArchController owner, not from the tranche borrower. `protocolFeeBips` is a percentage of
base lender interest and is charged on top rather than deducted from it. Its 1,000-bip cap therefore
means at most 10% of the lender rate: a 10% lender APR and 1,000-bip fee setting produce 11% borrower
cost. The factory can push a changed fee rate to existing open markets; an existing market's fee
recipient is immutable. The template can also specify an origination-fee asset and amount which the
borrower must echo and pay when creating the market. The tranching factory's ArchController, wrapper
factory, singleton hook template and manager bytecode commitment are fixed when that factory is
deployed.

#### Verified, inherited or algorithmic

The tranching factory verifies the registered market, borrower, sanctions sentinel, canonical wrapper,
hook instance, sealed singleton provider and sole lender. The manager derives the market, base asset,
borrower principal and market grace period from those bindings. Senior-first recovery, junior-first
realised loss, FIFO inside each class, realised-only delinquency marks, sanctions escrow routing,
one-way terminalisation and one manager per market are code rules rather than commercial parameters.
Holder sanctions checks use the borrower-principal namespace captured when the manager is initialised;
the separate check for whether the manager itself will receive market settlement reads the market's live
principal. The field kit should describe the observed routing and avoid claiming that every sanctions
check automatically follows a later principal transfer.

### External standards and conceptual prior art

[ERC-4626](https://eips.ethereum.org/EIPS/eip-4626) standardises shares over a single ERC-20 asset and
the related valuation views. The canonical Wildcat wrapper uses that pattern as the manager's custody
layer. The tranche tokens expose only a valuation-shaped subset and must not be sold as complete
ERC-4626 vaults.

[ERC-7540](https://eips.ethereum.org/EIPS/eip-7540) adds request, pending, claimable and claimed states
for asynchronous vault flows, including undercollateralised lending use cases. The manager's exit flow
is ERC-7540-style, but the current contracts do not claim full ERC-7540 conformance.

[Investor.gov's CMO glossary](https://www.investor.gov/introduction-investing/investing-basics/glossary/mortgage-backed-securities-and-collateralized)
describes tranches as classes paid according to a priority of payments. The analogy helps a traditional
credit audience understand senior and junior ordering. It stops there: this prototype has one borrower
and one market, no loan pool, no SPV, no rating and no repayment guarantee.

The [Wildcat introduction](https://docs.wildcat.finance/overview/introduction),
[borrower guide](https://docs.wildcat.finance/using-wildcat/day-to-day-usage/borrowers),
[lender guide](https://docs.wildcat.finance/using-wildcat/day-to-day-usage/lenders),
[protocol-fee guide](https://docs.wildcat.finance/using-wildcat/protocol-usage-fees) and
[core-behaviour guide](https://docs.wildcat.finance/technical-overview/security-developer-dives/core-behaviour)
remain the public source for the underlying market. They state that Wildcat does not underwrite the
borrower or guarantee repayment, that market withdrawals are asynchronous, and that protocol fees sit
at the market layer rather than being chosen by the borrower.

No public source was found that establishes this exact V2.5 tranching stack as a live product. The
repository itself is controlling: it deploys a pinned V2.5 revision in fork tests and describes the
trancher as a prototype.

## Constraints

- Start from `main` at `b90a155`; do not include the unrelated dirty manager-gas worktree.
- Preserve the repository's prototype label. Do not call it audited, production-ready, compliant,
  insured, rated, principal-protected or liquid.
- Keep legal classification open. Structured-credit and securitisation language is explanatory
  analogy, not a conclusion that these claims are securities, a securitisation or a collective vehicle.
- State that the senior rate is an accounting target and priority claim limited by realised value and
  recovery. It is neither the Wildcat market APR nor a promised return.
- State that minimum junior subordination is enforced on senior entry and active junior exit. It is not
  a continuously maintained collateral ratio after market movement or loss.
- State that transferability is conditional on sanctions and the fixed class gate. It is not a secondary
  liquidity undertaking.
- State that a redemption request burns tranche shares into the Wildcat withdrawal process. Timing and
  amount depend on market liquidity and borrower repayment.
- Show protocol fee at the market layer. The manager charges no additional fee in the current code.
  Accrued fees are reserved ahead of unprocessed market withdrawals; already-processed unclaimed
  withdrawals rank ahead of later fee collection. The manager can divide only what its market position
  produces and recovers.
- Show the exact distinction between a fixed gate address and potentially mutable gate policy.
- Distinguish the manager's lack of admin setters from the upstream hook administrator's ability to
  change the market minimum deposit or block fresh deposits by the manager.
- Build deployment records by reading contract storage and market configuration. The current
  `Initialized` event does not emit the economic terms or terminal recipient, and the factory does not
  record the live protocol-fee configuration.
- Use British English, plain prose, accessible colour contrast and static repository assets.
- Keep diagrams correct when viewed on GitHub, without JavaScript, hosted fonts or third-party renderers.
- Do not modify Solidity, V2.5 dependencies or economic logic as part of this run.

## Non-goals

- A production term sheet, offering memorandum, investment recommendation or legal opinion.
- A claim that a BD questionnaire grants governance or post-deployment amendment rights.
- A pricing model for a real borrower or a forecast of default, recovery or time to liquidity.
- More than two tranches, cross-market portfolios, diversification or an SPV structure.
- A new front end, hosted microsite, interactive calculator or generated presentation deck.
- Changes to V2.5, the canonical wrapper, singleton hooks or the manager.
- Replacement of technical documentation already in the repository.

## Design options

### Option A: one long report

Put research, primer, questions, examples and diagrams into one Markdown file.

The file is easy to find and review. It is awkward in a meeting: BD must scroll past technical detail to
reach a question, counterparties receive more internal qualification than they need, and a single edit
becomes responsible for several audiences.

### Option B: modular repository field kit

Create `docs/bd/` with a short index, a technical research report, a plain-language primer, a one-page
meeting brief, a parameter discovery guide, a question-and-answer and claims guide, and a gallery. Put
five or six labelled SVG diagrams under `docs/bd/assets/`, and cross-link each document to the relevant
visual and source.

This takes slightly more file organisation but gives each audience a document with one job. Static SVG
keeps words searchable, diffs reviewable and diagrams usable in a browser, screenshot or later deck.

### Option C: generated website or slide deck

Build a branded microsite or presentation with richer navigation and animation.

This would be useful after the underlying terms and narrative survive real conversations. At this stage
it adds layout and export work, creates another maintenance surface and makes factual review harder.

### Selection

Choose Option B. It is the least elaborate construction that gives BD call preparation, shareable
counterparty material, source notes and reusable diagrams without mixing legal, engineering and sales
claims. The existing `TRADFI_OUTREACH_PRIMER.md` can become a pointer to the field kit so old links keep
working.

## Proposed material set

1. `docs/bd/README.md`: index, intended audience, recommended reading order and prototype warning.
2. `docs/bd/RESEARCH_REPORT.md`: implementation-grounded product research, authority matrix, lifecycle,
   economics, risk allocation, fees and deployment status.
3. `docs/bd/PRIMER.md`: short lender and borrower explanation with crypto/TradFi vocabulary bridges.
4. `docs/bd/MEETING_BRIEF.md`: a one-page call aid: 60-second explanation, five facts, five boundaries and
   next-meeting checklist.
5. `docs/bd/PARAMETER_DISCOVERY.md`: separate borrower and lender questions, acceptable-range worksheet,
   scenario prompts and who actually controls each answer.
6. `docs/bd/FAQ_AND_CLAIMS.md`: questions BD will receive, approved answers, prohibited shorthand and
   escalation points.
7. `docs/bd/INFOGRAPHICS.md`: a gallery with captions, alt text and instructions for reuse.
8. `docs/bd/assets/one-market-two-claims.svg`: custody and exposure topology.
9. `docs/bd/assets/priority-waterfall.svg`: conditional protocol-fee reserve at market layer, then the
   manager's senior and junior allocation of cash actually recovered, with full, junior-loss and
   senior-impairment examples.
10. `docs/bd/assets/parameter-authority.svg`: borrower-at-formation, market borrower, protocol/factory,
    inherited and hard-coded columns.
11. `docs/bd/assets/healthy-lifecycle.svg`: formation through deposit, accrual, request, batch and claim.
12. `docs/bd/assets/distress-lifecycle.svg`: delinquency mark, window, wind-down, recovery and settlement.
13. `docs/bd/assets/cost-and-yield-bridge.svg`: market lender APR, protocol fee on top for borrower cost,
    senior target and junior residual, with no extra manager fee.

## Risk register seed

### Factual and commercial risks

- **Guarantee drift.** "Senior target" becomes "fixed yield" or "principal protection". Require the
  realised-value limitation beside every senior-return explanation.
- **Authority drift.** "Borrower chooses terms" becomes "borrower can change terms" or "borrower controls
  every parameter". Keep the four authority buckets visible.
- **Control-plane drift.** "No manager admin" becomes "nothing can stop new deposits". Name the upstream
  hook administrator's deposit controls without implying it can alter holder claims or the waterfall.
- **Liquidity drift.** Transferable ERC-20 claims become "liquid" and an asynchronous request becomes a
  redemption date. Pair transfer language with gate, sanctions and queue conditions.
- **Subordination drift.** The formation constraint becomes a maintained 20% cushion. Explain that market
  loss can consume junior value and then impair senior.
- **Fee omission.** A scenario compares market APR and senior target without the protocol-fee basis,
  origination charge or exact withdrawal ordering. Show borrower cost, lender APR and tranche allocation
  separately; distinguish unprocessed from already-processed withdrawals.
- **Legal analogy drift.** TradFi language becomes a legal classification or rating claim. Label every
  capital-stack example as an analogy and prototype illustration.
- **Version drift.** Current material is reused after manager source, compiler profile or V2.5 pin changes.
  Put the reviewed commit and status in the research report and field-kit index.

### Technical claims requiring careful treatment

- The manager is sole lender only after the sealed singleton market, canonical wrapper and predicted
  address ceremony succeed.
- A nonzero gate can contain mutable policy even though its address cannot change.
- The manager has no economic setter, while the surrounding hook administrator retains upstream market
  deposit controls.
- `TrancheToken` has ERC-4626-shaped views, not the complete mutable interface.
- Exit semantics are ERC-7540-style, not a conformance claim.
- The delinquency counter can decay during cure. The manager reads that on-chain counter and enters
  one-way wind-down at market grace plus the tranche window.
- Direct base asset sent to the manager is terminal surplus and does not fund an exit request.
- A sanctioned holder can exit, but recovered assets route to the canonical escrow.
- Accrued protocol fees reserve liquidity ahead of unprocessed manager withdrawals, while processed
  unclaimed withdrawals are not later displaced. The trancher does not waive or duplicate the fee.
- Holder sanctions checks retain the manager's initial borrower-principal namespace; the manager's own
  market-settlement check uses the market's live principal.
- The V2.5 audit-bundle branch discussed in `V25_AUDIT_BUNDLE_ASSESSMENT.md` is not faulty because it lacks
  trancher-only features. Production integration requires a reconciled, frozen revision.

### Review focus for this documentation-only run

No Solidity security audit applies because no contract code will change. Review should instead compare
each statement and diagram against `TrancheFactory`, `TrancheManager`, `TrancheToken`,
`TrancheOpenTermHooks`, `WaterfallMath`, the pinned V2.5 source and tests. The highest-risk seams are
parameter authority, fee priority, senior-target wording, async timing, gate mutability and prototype
status.

## Glossary seeds

- **Base asset:** the ERC-20 asset lent to the Wildcat market and used for tranche accounting.
- **Wildcat market:** the single underlying borrower credit market; the trancher does not create a
  second loan.
- **Canonical wrapper:** the market's registered ERC-4626 wrapper. It holds the market-token backing;
  the manager holds all wrapper shares in this design.
- **TrancheManager:** the per-market custody, accounting, exit and recovery contract.
- **Senior tranche:** the claim with a fixed accounting target and first priority in realised value and
  recovery, still exposed after junior is exhausted.
- **Junior tranche:** the residual claim that absorbs realised loss before senior and receives recovery
  after senior.
- **Senior target:** simple interest accrued on outstanding senior principal for waterfall accounting;
  not a guaranteed payment or the underlying market APR.
- **Minimum junior subordination:** the chosen junior percentage required for senior entry and active
  junior exit.
- **Entry gate:** the fixed contract consulted when an account acquires tranche exposure; zero means open
  entry, and the gate cannot stop an existing holder's exit.
- **Withdrawal batch:** the Wildcat market queue period to which a burned tranche redemption request is
  assigned.
- **Request face:** the floor-normalised market-token value backed by wrapper shares removed for an exit.
- **Realised mark:** the aggregate wrapper value last observed while healthy, reduced by backed exits;
  delinquency upside above it is excluded until cure while losses remain visible.
- **Wind-down:** the manager's irreversible state after market close or the objective delinquency
  threshold; deposits and senior accrual stop, while exits and settlement continue.
- **Protocol fee:** Wildcat's market-level fee, set through protocol/factory authority and paid in
  addition to lender base interest.
- **Terminal recipient:** the deployment-time recipient of proven residual surplus after every holder,
  request, reserve and custody position has cleared.
- **Terminal surplus:** base asset proven not to belong to any tranche request or live senior reserve.

## Sources

### Repository

- [README](../../README.md)
- [TrancheFactory](../../build/src/TrancheFactory.sol)
- [TrancheManager](../../build/src/TrancheManager.sol)
- [TrancheToken](../../build/src/TrancheToken.sol)
- [TrancheOpenTermHooks](../../build/src/TrancheOpenTermHooks.sol)
- [WaterfallMath](../../build/src/libraries/WaterfallMath.sol)
- [Tranche tests](../../build/test/Tranche.t.sol)
- [Fuzz tests](../../build/test/Fuzz.t.sol)
- [Invariant tests](../../build/test/Invariant.t.sol)
- [Fork tests](../../build/test/Fork.t.sol)
- [Release evidence tests](../../build/test/ReleaseEvidence.t.sol)
- [Architecture](../ARCHITECTURE.md)
- [Implementation runbook](../IMPLEMENTATION_RUNBOOK.md)
- [Trancher logic report](../TRANCHER_LOGIC_REPORT.md)
- [Prototype handoff](../PROTOTYPE_HANDOFF.md)
- [TradFi outreach primer](../TRADFI_OUTREACH_PRIMER.md)
- [Release evidence](../RELEASE_EVIDENCE.md)
- [V2.5 audit-bundle assessment](../V25_AUDIT_BUNDLE_ASSESSMENT.md)

### Pinned upstream source

The V2.5 submodule is pinned at `e88e799bedd3108feb5ff45b33dc7b62f865b56c`.

- [Market deployment and template fees](../../build/lib/v2-protocol/src/HooksFactory.sol)
- [Market input structure](../../build/lib/v2-protocol/src/interfaces/WildcatStructsAndEnums.sol)
- [Market parameter bounds](../../build/lib/v2-protocol/src/access/MarketConstraintHooks.sol)
- [OpenTerm controls](../../build/lib/v2-protocol/src/access/OpenTermHooks.sol)
- [Hook-administrator transfer and access controls](../../build/lib/v2-protocol/src/access/BaseAccessControls.sol)
- [Sealed singleton hook](../../build/lib/v2-protocol/src/access/SingletonOpenTermHooks.sol)
- [Sealed singleton lender provider](../../build/lib/v2-protocol/src/providers/SingletonRoleProvider.sol)
- [Mutable market configuration](../../build/lib/v2-protocol/src/market/WildcatMarketConfig.sol)
- [Market immutables](../../build/lib/v2-protocol/src/market/WildcatMarketBase.sol)
- [Market-state withdrawal ordering](../../build/lib/v2-protocol/src/libraries/MarketState.sol)
- [Withdrawal availability](../../build/lib/v2-protocol/src/libraries/Withdrawal.sol)
- [Protocol-fee calculation](../../build/lib/v2-protocol/src/libraries/FeeMath.sol)
- [Canonical wrapper](../../build/lib/v2-protocol/src/vault/Wildcat4626Wrapper.sol)

### Public references

- [Wildcat introduction](https://docs.wildcat.finance/overview/introduction)
- [Wildcat borrower guide](https://docs.wildcat.finance/using-wildcat/day-to-day-usage/borrowers)
- [Wildcat lender guide](https://docs.wildcat.finance/using-wildcat/day-to-day-usage/lenders)
- [Wildcat protocol fees](https://docs.wildcat.finance/using-wildcat/protocol-usage-fees)
- [Wildcat core behaviour](https://docs.wildcat.finance/technical-overview/security-developer-dives/core-behaviour)
- [ERC-4626](https://eips.ethereum.org/EIPS/eip-4626)
- [ERC-7540](https://eips.ethereum.org/EIPS/eip-7540)
- [Investor.gov: mortgage-backed securities and CMOs](https://www.investor.gov/introduction-investing/investing-basics/glossary/mortgage-backed-securities-and-collateralized)
- [ECB: what is securitisation?](https://data.ecb.europa.eu/methodology/what-securitisation)
