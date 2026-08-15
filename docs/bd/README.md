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
| Borrower or hook administrator at the Wildcat market layer | Initial market capacity, lender APR, reserve settings, withdrawal timing, delinquency terms, minimum deposit and access administration; some terms retain Wildcat-authorised update paths | "The underlying market has its own operating terms and authorities. They are not all frozen by the tranching factory." |
| Wildcat protocol or factory | Protocol fee and recipient; registered dependencies; canonical wrapper factory; hook template; exact manager bytecode commitment | "The tranche borrower does not set the protocol fee or replace the verified deployment stack." |
| Derived or fixed in code | Bound market and asset; market grace period; senior-first recovery; junior-first realised loss; FIFO within class; sanctions routing; objective wind-down; terminal settlement | "These are verified facts or code rules, not commercial dials." |

The address of each nonzero entry gate is fixed, but the policy inside that external contract may change.
The manager itself has no economic setter, upgrade route, pause role or discretionary default button.
The surrounding Wildcat hook administrator can still operate upstream deposit controls, including
blocking fresh market deposits, without rewriting existing tranche claims or their exit waterfall.

## Claims boundary

Use "fixed senior target", "junior first realised loss", "senior-first recovery", "controlled
transferability" and "asynchronous exit".

Do not use "guaranteed yield", "principal protected", "instant redemption", "freely transferable",
"maintained collateral cushion", "audited", "production-ready" or a credit-rating analogy. A mechanical
manager wind-down is not, by itself, a legal declaration of default.

The protocol fee remains at the Wildcat market layer. The manager adds no second fee in the current
code. Borrower cost, lender APR and tranche economics should be shown separately because the protocol
fee is paid in addition to lender base interest and has market-level priority.

