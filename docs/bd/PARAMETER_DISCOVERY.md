# Price the trade: desk worksheet

Fill this in for a real borrower. Blank boxes are useful: they show exactly where the deal is still
hand-waving.

## Counterparty and exposure

| Question | Answer |
| --- | --- |
| Borrower and legal entity |  |
| Purpose and source of repayment |  |
| Base asset and proposed capacity |  |
| Expected term and amortisation or repayment path |  |
| Covenants, collateral and recourse, if any |  |
| Base, downside and recovery assumptions |  |
| Required reporting and escalation contacts |  |

## Capital stack: who gets what, who loses first

| Term | System range | Borrower range | Senior range | Junior range | Discussion range |
| --- | --- | --- | --- | --- | --- |
| Senior target | 0 to 10,000 bips |  |  |  |  |
| Junior share at entry | 500 to 9,000 bips |  |  |  |  |
| Senior amount or proportion | Constrained by junior share |  |  |  |  |
| Junior amount or proportion | Funds first |  |  |  |  |
| Additional workout window | More than 0; no more than 90 days |  |  |  |  |
| Senior eligibility | Open or controlled |  |  |  |  |
| Junior eligibility | Open or controlled |  |  |  |  |

Make both sides defend their number. The senior target prices the senior ticket; it is not the borrower
coupon. The junior share is checked at entry and normal junior exit, then left to take the loss. The extra
window should match a workout someone is actually prepared to run.

## Loan economics: what the borrower pays, when cash comes back

| Item | Discussion range or requirement | Change or consent expectation |
| --- | --- | --- |
| Lender rate |  |  |
| Capacity |  |  |
| Reserve or liquidity requirement |  |  |
| Withdrawal period |  |  |
| Delinquency charge and grace |  |  |
| Platform-fee rate |  |  |
| Origination fee |  |  |
| Expected normal time to cash |  |  |
| Expected stressed time to cash |  |  |

Borrower running cost is lender interest plus the platform charge, before origination or arrears costs.
The current facility adds no second fee. For every term, write down who can change it, who gets notice and
who can say no.

## Operations: who can hold it, who has to move when it goes wrong

| Question | Answer |
| --- | --- |
| Who may acquire senior? |  |
| Who may acquire junior? |  |
| Who runs each eligibility policy? |  |
| Can that policy change after formation? |  |
| What custody arrangements are acceptable? |  |
| What sanctions and escrow process applies? |  |
| Who monitors arrears and records the wind-down trigger? |  |
| Who retries settlement if the facility account is sanctioned? |  |
| Who receives genuine surplus after final settlement? |  |

Eligibility constrains acquisition, not an existing holder's right to request exit. Exit can still be
slow or partial. A sanctioned holder's proceeds use escrow; a sanctioned facility account can defer
settlement for everyone until cleared.

## Scenario record

For each case, record facility value, senior owed, junior value, cash available, time to cash and the
assumed borrower action.

| Case | Facility value | Senior value | Junior value | Cash timing | Notes |
| --- | ---: | ---: | ---: | --- | --- |
| Base |  |  |  |  |  |
| Junior impairment |  |  |  |  |  |
| Senior impairment |  |  |  |  |  |
| Arrears and cure |  |  |  |  |  |
| Wind-down and recovery |  |  |  |  |  |

## Internal implementation record

BD does not need this for the pitch, but implementation owners must record the exact loan address,
asset, borrower identity, eligibility contracts, current platform fee, withdrawal period, delinquency
terms, fixed residual recipient and the accounts responsible for monitoring and settlement.

This worksheet does not amend a live facility. It tells the deal team whether there is a trade worth
forming.
