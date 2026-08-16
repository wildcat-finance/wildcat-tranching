# Facility worksheet

This is where appetite becomes terms. Start with a borrower worth funding, then make senior and junior
write down the price, attachment and cash timing each will actually accept. Blank cells mean there is no
deal yet.

## 1. Credit

| Question | Answer |
| --- | --- |
| Borrower and legal entity |  |
| Use of proceeds |  |
| Primary source of repayment |  |
| Facility asset and maximum size |  |
| Expected draw, term and repayment path |  |
| Covenants, collateral and recourse |  |
| Reporting package and frequency |  |
| Base, delayed-payment and recovery assumptions |  |

## 2. Capital stack

| Term | System limit | Proposed | Senior view | Junior view |
| --- | --- | --- | --- | --- |
| Senior amount | Must preserve junior percentage at entry |  |  |  |
| Senior target | 0% to 100% p.a.; simple accrual |  |  |  |
| Junior amount | Normally funds first |  |  |  |
| Junior percentage at entry | 5% to 90% |  |  |  |
| Extra arrears window after loan grace | More than 0; no more than 90 days |  |  |  |
| Senior access | Open or named provider |  |  |  |
| Junior access | Open or named provider |  |  |  |

The senior target prices the senior ticket; it is not the borrower coupon. The junior percentage is an
entry and active-exit test, not a cushion that is restored after loss.

The implementation also has a dust floor for the first credited value in an empty class: `1e6` raw asset
units. That is one token for a six-decimal asset and a tiny fraction of an 18-decimal token. It is not the
commercial minimum ticket. Conversion rounding may require a slightly larger tender.

## 3. Borrower economics and cash timing

| Item | Proposed | Who can change it? | Notice or consent |
| --- | --- | --- | --- |
| Lender rate |  |  |  |
| Platform fee on lender interest |  |  |  |
| One-off fee |  |  |  |
| Maximum facility size |  |  |  |
| Reserve requirement |  |  |  |
| Withdrawal cycle |  |  |  |
| Grace period |  |  |  |
| Arrears charge |  |  |  |
| Expected normal time to cash |  |  |  |
| Expected stressed time to cash |  |  |  |

Borrower running cost is lender interest plus the platform fee, before arrears and one-off costs. The
participation layer does not charge a fee.

## 4. Operations

| Question | Answer |
| --- | --- |
| Is each class open or restricted? |  |
| If restricted, who runs the eligibility provider? |  |
| Can that external policy change? |  |
| Which custodians can support the asset and participation? |  |
| Who monitors arrears each day? |  |
| Who records the permanent wind-down trigger before cure? |  |
| Who runs collections and workout? |  |
| Who receives surplus after every holder is paid? |  |

For an open class, any wallet can acquire or receive the participation unless the Chainalysis sanctions
oracle flags it. A flagged holder can still request exit; the detailed settlement route belongs in the
operating procedure.

## 5. Cash cases

| Case | Facility value | Senior value | Junior value | Cash timing | Borrower action |
| --- | ---: | ---: | ---: | --- | --- |
| Paid as agreed |  |  |  |  |  |
| Paid late and cured |  |  |  |  |  |
| Junior impaired |  |  |  |  |  |
| Senior impaired |  |  |  |  |  |
| Wind-down and recovery |  |  |  |  |  |

Record both value and cash. A seven-day withdrawal cycle can still lead to a longer wait when the borrower
has not returned the money.

## 6. Decision record

| Owner | Name |
| --- | --- |
| Credit |  |
| Legal |  |
| Operations |  |
| Arrears monitoring |  |
| Workout |  |

This worksheet does not amend a facility. It tells the deal team whether both cheques can clear on terms
worth documenting.
