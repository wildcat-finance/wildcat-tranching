# Acme Ltd: a $20m worked credit

This is a desk illustration, not a quote or forecast. It assumes one USDC equals one dollar, a full draw
for one year and simple rounded calculations. A live transaction would use the contract's exact accrual,
scaling and rounding.

## The proposed facility

| Term | Acme example |
| --- | ---: |
| Borrower | Acme Ltd |
| Facility | `acmeUSDC` |
| Asset | USDC |
| Maximum size and assumed draw | $20,000,000 |
| Term | Open |
| Senior | $16,000,000 / 80% |
| Junior | $4,000,000 / 20% |
| Lender rate | 10% p.a. |
| Platform fee | 5% of lender interest |
| Borrower running cost | 10.5% p.a. before arrears or one-off charges |
| Senior target | 8% p.a., simple |
| Arrears charge | 2% p.a. after grace |
| Withdrawal cycle | 7 days |
| Grace period | 21 days |
| Extra arrears window | 7 days |
| Permanent wind-down threshold | Day 28 of current arrears, if observed by a checkpoint |
| Loan reserve requirement | 0% |
| Entry and transfer | Open, subject to the Chainalysis sanctions oracle |
| Origination fee | None assumed |

The 8% senior target, 2% arrears charge and seven-day extra window are example choices. They are not
defaults or recommendations.

## Before running the paths

Three rates do three different jobs:

1. Acme pays 10% lender interest: $20m × 10% = $2,000,000.
2. The platform fee is 5% of that interest: $2m × 5% = $100,000.
3. Senior's 8% target divides value between senior and junior. It does not add to Acme's debt.

Acme's running annual cost is therefore $2,100,000, or 10.5% of principal, before arrears or one-off
charges. The participation layer charges no fee.

The seven-day withdrawal cycle is a batch period. With no reserve requirement, it is not a promise that
cash will be waiting after seven days.

## Paid-as-agreed case

Assume Acme uses the full $20m for one year and pays principal and lender interest in full.

| Calculation | Result |
| --- | ---: |
| Principal returned to the facility | $20,000,000 |
| Lender interest returned to the facility | $2,000,000 |
| Facility value for the two classes | $22,000,000 |
| Platform fee paid separately | $100,000 |
| Total Acme running cost | $2,100,000 / 10.5% |
| Senior target interest | $16m × 8% = $1,280,000 |
| Senior value | $17,280,000 |
| Junior value | $22m − $17.28m = $4,720,000 |
| Junior gain on $4m | $720,000 / 18% |

Senior reaches its 8% annual target. Junior earns 18% because it receives the 10% loan return left after
senior's lower target. Neither result is promised outside these assumptions.

A holder who asks to exit still enters the weekly batch. Payment depends on Acme returning enough cash.

## Neutral path: paid late, cured on day 24

Assume Acme falls into arrears but cures on day 24, then completes the same one-year payment. The first 21
days sit inside grace. Three days carry the 2% arrears charge. Cure occurs four days before the day-28
threshold could be recorded.

| Calculation | Result |
| --- | ---: |
| Arrears charge | $20m × 2% × 3/365 ≈ $3,288 |
| Facility value after full payment and cure | ≈ $22,003,288 |
| Platform fee on base lender interest | $100,000 |
| Total Acme running and arrears cost | ≈ $2,103,288 |
| Senior value after one year | $17,280,000 |
| Junior value | ≈ $4,723,288 |
| Junior gain on $4m | ≈ $723,288 / 18.08% |

While arrears continue, new funding stops and the extra arrears charge does not mark the participation up.
The value appears after cure. An exit request can pass its seven-day batch date and still wait for Acme's
cash.

The facility stays open because the day-28 threshold was not recorded. Someone still needs to monitor the
loan and record the threshold while it is observable; the system does not reconstruct a missed trigger
after cure.

## Catastrophic path: wind-down and 60% net recovery

Assume current arrears reach day 28 and a checkpoint records permanent wind-down. Six months later, the
net cash available to the two classes is $12,000,000. That 60% recovery is an assumption, not a forecast.

| Calculation | Result |
| --- | ---: |
| Senior target accrued through day 28 | $16m × 8% × 28/365 ≈ $98,192 |
| Senior claim frozen at wind-down | ≈ $16,098,192 |
| Assumed net cash recovered six months later | $12,000,000 |
| Cash to senior | $12,000,000 |
| Cash to junior | $0 |
| Senior recovery on original principal | 75.00% |
| Senior recovery on frozen claim | ≈ 74.54% |
| Junior loss | $4,000,000 / 100% |

Junior is wiped out before senior receives less than its claim. The weekly withdrawal cycle has no bearing
on the assumed six-month recovery. Legal costs, fees, enforcement timing and the actual recovery would be
underwritten separately in a live deal.

## Questions for the room

### Senior desk

- Is an 8% target enough for Acme and the expected time to cash?
- Is $4m of funded junior enough against the desk's own downside?
- Is a 75% principal recovery in the severe case too generous or too harsh?
- What amendment rights, reporting and escalation does senior require?

### Junior desk

- Is the 18% performing return enough for first-loss risk?
- Can treasury tolerate senior exit requests clearing first?
- Which Acme outcome takes the residual to zero in the desk's own model?

### Acme

- Is 10.5% running cost acceptable before arrears charges?
- Are 21 days of grace and the seven-day extra window workable?
- Is open transfer acceptable, subject to the sanctions oracle?
- Who owns daily monitoring, cure and workout communications?

## The one-line read

Acme pays 10.5% running cost on a $20m line. Senior puts in $16m for an 8% accounting target. Junior puts
in $4m, takes the first loss and keeps the residual. Weekly batching governs exit requests; Acme's cash
governs payment.
