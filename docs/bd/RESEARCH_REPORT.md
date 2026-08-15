# Wildcat tranching: credit and product research

## What the facility is

The prototype issues senior and junior participations over one Wildcat borrower market. It does not
pool borrowers or create a second loan. One `TrancheManager` holds the underlying market position,
accounts for the two classes, sends exits through the market withdrawal queue and allocates recovered
cash.

Senior has a simple annual accounting target and first claim on realised value. Junior takes realised
loss first and owns value above the senior claim. Senior exit requests clear before junior exit
requests; FIFO applies within each class. Neither class has a guaranteed return, repayment or exit date.

The borrower chooses the senior target, minimum junior percentage, extra wind-down window, class entry
settings and final surplus recipient when the facility is formed. Those manager terms have no later
setters. The underlying loan and protocol retain separate parameter and operating authority described
below.

## Current implementation

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

## Parameter authority

### Borrower-selected once, through this factory

`TrancheFactory.DeployParams` and `TrancheManager.Params` establish the facility choices:

- `seniorRateBips`: 0 to 10,000 bips;
- `minJuniorBips`: 500 to 9,000 bips, or 5% to 90%;
- `defaultPenaltyWindow`: greater than zero and no more than 90 days;
- `seniorGate` and `juniorGate`: zero for open entry, otherwise a contract address;
- `terminalRecipient`: nonzero and not the predicted manager; and
- deployment salt, namespaced by the calling borrower.

The caller must equal both the supplied borrower and `market.borrower()`. The terms are written during
factory-only initialisation. There are no setters. A nonzero gate address is fixed, although the policy
inside that external gate may itself be mutable. The factory supplies no economic defaults: the borrower
must submit every one-time tranche term. A 0% senior target and open gates are valid choices.

The base-asset-denominated value credited from the first deposit into either empty tranche class must
be at least `1e6` units. Conversion rounding can require a slightly larger tender. The human amount
depends on the asset's decimals; the manager requires at least six decimals. This is a fixed
implementation constraint, not a borrower parameter.

### Borrower-selected or borrower-operated in the underlying market

The Wildcat market is created before the tranching factory attaches a manager. At market creation the
borrower supplies market inputs such as capacity, lender APR, reserve ratio, withdrawal-batch duration,
delinquency fee and delinquency grace period, subject to the chosen hook template and protocol bounds.
The current generic bounds are 0 to 10,000 bips for APR, reserve ratio and delinquency fee; 0 to 90 days
for grace; and 0 to 365 days for the withdrawal-batch duration. The tranching factory narrows the
delinquency-fee range to 1 through 10,000 bips because it rejects a zero-fee market. Capacity is stored
as a `uint128`. The upstream market-hook minimum deposit is also a `uint128`, with zero meaning none.
At market creation, the operational borrower supplies that initial minimum and a `transfersDisabled`
flag as the singleton hook's exact 64-byte data tuple. The current hook administrator may later change
the minimum, but there is no setter for the transfer flag. The tranching factory accepts only
`transfersDisabled == false`, because the canonical wrapper needs market-token transfers.
Market capacity and APR retain borrower-authorised update paths under Wildcat rules. Reserve-ratio
changes travel with APR changes and can be constrained or derived by the OpenTerm hook rather than
accepted as a free borrower choice. The manager's senior target deliberately does not track a later
market APR change. The current hook administrator can change the upstream minimum deposit and block or
unblock the manager from making fresh market deposits. The role starts with the registered borrower
principal and can be transferred to another registered borrower under Wildcat's two-step
administrator-transfer rules. Its actions can suspend new tranche entry at the market layer without
changing the manager's economics, custody or exit waterfall.

### Protocol or factory authority

The protocol-fee rate and fee recipient come from the Wildcat hook-template configuration selected
through the ArchController owner, not from the tranche borrower. `protocolFeeBips` is a percentage of
base lender interest and is charged on top rather than deducted from it. Its 1,000-bip cap therefore
means at most 10% of the lender rate: a 10% lender APR and 1,000-bip fee setting produce 11% borrower
running base-interest cost, before any origination fee or delinquency charge. The factory can push a
changed fee rate to existing open markets; an existing market's fee recipient is immutable. The
template can also specify an origination-fee asset and amount which the borrower must echo and pay when
creating the market. The tranching factory's ArchController, wrapper factory, singleton hook template
and manager bytecode commitment are fixed when that factory is deployed.

### Verified, inherited or algorithmic

The tranching factory verifies the registered market, borrower, sanctions sentinel, canonical wrapper,
hook instance, sealed singleton provider and sole lender. The manager derives the market, base asset,
borrower principal and market grace period from those bindings. Senior-first recovery, junior-first
realised loss, FIFO inside each class, realised-only delinquency marks, sanctions escrow routing,
one-way terminalisation and one manager per market are code rules rather than commercial parameters.
Holder sanctions checks use the borrower-principal namespace captured when the manager is initialised;
the separate check for whether the manager itself will receive market settlement reads the market's live
principal. A later borrower-principal transfer therefore does not move every sanctions check into the
same namespace.

## External standards and conceptual prior art

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

This exact V2.5 tranching stack is a repository prototype, not a live product.

## Commercial boundaries

- The repository is a prototype. It is not audited, production-ready, compliant, insured, rated,
  principal-protected or liquid.
- Legal classification remains open. Structured-credit and securitisation language is explanatory
  analogy, not a conclusion that the claims are securities, a securitisation or a collective vehicle.
- The senior rate is an accounting target and priority claim limited by realised value and recovery.
  It is neither the Wildcat market APR nor a promised return.
- Minimum junior subordination is enforced on senior entry and active junior exit. It is not a
  continuously maintained collateral ratio after market movement or loss.
- Transferability is conditional on sanctions and the fixed class-gate address. It is not a secondary
  liquidity undertaking.
- A redemption request burns tranche shares into the Wildcat withdrawal process. Timing and amount
  depend on market liquidity and borrower repayment.
- The protocol fee sits at the market layer. The manager charges no additional fee in the current code.
  Accrued fees are reserved ahead of unprocessed market withdrawals; already-processed unclaimed
  withdrawals rank ahead of later fee collection. The manager can divide only what its market position
  produces and recovers.
- The gate address is fixed; policy inside the selected gate may be mutable.
- The manager has no admin setters. The upstream hook administrator can still change the market minimum
  deposit or block fresh deposits by the manager.
- Deployment records must be assembled from contract storage and market configuration. The current
  `Initialized` event omits the economic terms and terminal recipient, and the factory does not record
  the live protocol-fee configuration.

## Non-goals

- A production term sheet, offering memorandum, investment recommendation or legal opinion.
- A claim that a BD questionnaire grants governance or post-deployment amendment rights.
- A pricing model for a real borrower or a forecast of default, recovery or time to liquidity.
- More than two tranches, cross-market portfolios, diversification or an SPV structure.
- A new front end, hosted microsite, interactive calculator or generated presentation deck.

## Commercial and technical risks

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
- **Version drift.** Source or dependency changes can make the material stale. Recheck the claims whenever
  the manager, compiler profile or V2.5 pin changes.

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

## Glossary

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
- [Architecture](../ARCHITECTURE.md)
- [Trancher logic report](../TRANCHER_LOGIC_REPORT.md)
- [TradFi outreach primer](../TRADFI_OUTREACH_PRIMER.md)

### Pinned upstream source

The V2.5 submodule is pinned at `e88e799bedd3108feb5ff45b33dc7b62f865b56c`.

- [Market deployment and template fees](https://github.com/wildcat-finance/v2-protocol/blob/e88e799bedd3108feb5ff45b33dc7b62f865b56c/src/HooksFactory.sol)
- [Market input structure](https://github.com/wildcat-finance/v2-protocol/blob/e88e799bedd3108feb5ff45b33dc7b62f865b56c/src/interfaces/WildcatStructsAndEnums.sol)
- [Market parameter bounds](https://github.com/wildcat-finance/v2-protocol/blob/e88e799bedd3108feb5ff45b33dc7b62f865b56c/src/access/MarketConstraintHooks.sol)
- [OpenTerm controls](https://github.com/wildcat-finance/v2-protocol/blob/e88e799bedd3108feb5ff45b33dc7b62f865b56c/src/access/OpenTermHooks.sol)
- [Hook-administrator transfer and access controls](https://github.com/wildcat-finance/v2-protocol/blob/e88e799bedd3108feb5ff45b33dc7b62f865b56c/src/access/BaseAccessControls.sol)
- [Sealed singleton hook](https://github.com/wildcat-finance/v2-protocol/blob/e88e799bedd3108feb5ff45b33dc7b62f865b56c/src/access/SingletonOpenTermHooks.sol)
- [Sealed singleton lender provider](https://github.com/wildcat-finance/v2-protocol/blob/e88e799bedd3108feb5ff45b33dc7b62f865b56c/src/providers/SingletonRoleProvider.sol)
- [Mutable market configuration](https://github.com/wildcat-finance/v2-protocol/blob/e88e799bedd3108feb5ff45b33dc7b62f865b56c/src/market/WildcatMarketConfig.sol)
- [Market immutables](https://github.com/wildcat-finance/v2-protocol/blob/e88e799bedd3108feb5ff45b33dc7b62f865b56c/src/market/WildcatMarketBase.sol)
- [Market-state withdrawal ordering](https://github.com/wildcat-finance/v2-protocol/blob/e88e799bedd3108feb5ff45b33dc7b62f865b56c/src/libraries/MarketState.sol)
- [Withdrawal availability](https://github.com/wildcat-finance/v2-protocol/blob/e88e799bedd3108feb5ff45b33dc7b62f865b56c/src/libraries/Withdrawal.sol)
- [Protocol-fee calculation](https://github.com/wildcat-finance/v2-protocol/blob/e88e799bedd3108feb5ff45b33dc7b62f865b56c/src/libraries/FeeMath.sol)
- [Canonical wrapper](https://github.com/wildcat-finance/v2-protocol/blob/e88e799bedd3108feb5ff45b33dc7b62f865b56c/src/vault/Wildcat4626Wrapper.sol)

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
