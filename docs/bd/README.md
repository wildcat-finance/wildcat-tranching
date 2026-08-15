# Wildcat tranching: BD field kit

This directory is the source for lender and borrower conversations about the Wildcat tranching
prototype. It is written for credit teams, treasury teams, allocators, originators and crypto-native
firms that already understand the borrower exposure and want to discuss how two participation classes
could sit over one Wildcat market.

The material describes `wildcat-finance/wildcat-tranching` at
`b90a155f257c76f96e50cf2fa29872e1735f8bd8`. It is a prototype, not a live offering, an audit report,
a credit rating, a legal opinion or a promise of liquidity or repayment.

## Start here

Read the [research report](RESEARCH_REPORT.md) for the contracts, lifecycle, parameter authority,
constraints and source list. The [delivery runbook](DELIVERY_RUNBOOK.md) records how the shareable
primer, meeting material and infographics are being assembled and checked.

For the underlying design and test status, use the repository's
[architecture](../ARCHITECTURE.md), [prototype handoff](../PROTOTYPE_HANDOFF.md) and
[release evidence](../RELEASE_EVIDENCE.md). The
[V2.5 compatibility assessment](../V25_AUDIT_BUNDLE_ASSESSMENT.md) explains which additions are needed
if the trancher is included in that audit bundle. Their absence from a V2.5-only branch is not an error
in that branch.

## The short answer

One `TrancheManager` is the sole lender to one Wildcat market. It holds the market's canonical wrapped
position and issues two claims over the same realised value:

- Senior accrues a fixed accounting target and receives first priority in realised value and recovery.
- Junior receives the residual and absorbs realised loss before senior.

Both classes retain the same underlying borrower risk. Seniority changes ordering; it does not create a
guarantee. Exits burn tranche shares into the Wildcat withdrawal queue and settle as the market pays.

## Who chooses what

Yes: the market borrower chooses a bounded set of tranche terms when the manager is attached. Those
terms are fixed after deployment. The factory does not grant the borrower a continuing control plane.

| Authority | What it covers | What BD should say |
| --- | --- | --- |
| Borrower, once at tranche formation | Senior target rate; minimum junior percentage; additional delinquency window; fixed senior and junior gate contracts; terminal recipient; deployment salt | "The borrower proposes the tranche economics and entry structure within hard bounds, then those manager terms are fixed." |
| Market borrower | Initial capacity, lender APR, reserve setting, withdrawal timing and delinquency terms; capacity and APR retain Wildcat-authorised update paths | "The underlying market has its own borrower-set operating terms. They are separate from the fixed tranche terms." |
| Current hook administrator | Upstream market-hook minimum deposit and block or unblock of fresh deposits; the role starts with the registered borrower principal and can be transferred under Wildcat's rules | "The hook administrator can affect new capital entering the market, but cannot rewrite existing tranche claims or the waterfall." |
| Wildcat protocol or factory | Protocol-fee rate and recipient, any origination fee, registered dependencies, canonical wrapper factory, hook template and exact manager bytecode commitment | "The tranche borrower does not set protocol charges or replace the verified deployment stack." |
| Derived or fixed in code | Bound market and asset; market grace period; senior-first recovery; junior-first realised loss; FIFO within class; sanctions routing; objective wind-down; terminal settlement | "These are verified facts or code rules, not commercial dials." |

The address of each nonzero entry gate is fixed, but the policy inside that external contract may change.
The manager itself has no economic setter, upgrade route, pause role or discretionary default button.
The current Wildcat hook administrator can still change the upstream market-hook minimum deposit and
block or unblock fresh deposits by the manager. That role is transferable under Wildcat's
administrator-transfer rules. Its holder cannot rewrite existing tranche claims or their exit
waterfall.

## Claims boundary

Use "fixed senior target", "junior first realised loss", "senior-first recovery", "controlled
transferability" and "asynchronous exit".

Do not use "guaranteed yield", "principal protected", "instant redemption", "freely transferable",
"maintained collateral cushion", "audited", "production-ready" or a credit-rating analogy. A mechanical
manager wind-down is not, by itself, a legal declaration of default.

The protocol fee remains at the Wildcat market layer. The manager adds no second fee in the current
code. The fee rate is a percentage of base lender interest, charged on top to the borrower: a 1,000-bip
setting on a 10% lender APR gives an 11% running base-interest cost before any origination fee or
delinquency charge. Accrued fees are reserved ahead of unprocessed market withdrawals; an
already-processed unclaimed withdrawal is not later displaced by fee collection. Senior and junior
divide only the manager's position and cash actually recovered.
