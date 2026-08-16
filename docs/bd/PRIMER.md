# Desk primer

Some credits are attractive at one attachment point and wrong at another. This structure lets senior and
junior price different parts of one named borrower exposure, then funds both through one facility.

## The trade

One borrower raises one facility from two classes of capital.

| | Senior | Junior |
| --- | --- | --- |
| Starting position | Above junior | First-loss piece |
| Return | Fixed annual simple accounting target | Value left after senior |
| Loss | After junior reaches zero | First |
| Recovery cash | Senior exit requests clear first; FIFO within senior | Clears after senior exit requests; FIFO within junior |
| Exit | Waits for borrower cash | Waits for borrower cash |
| Transfer in an open class | Any wallet unless the sanctions oracle flags it | Any wallet unless the sanctions oracle flags it |

Both classes own the same borrower risk. There is no pool and no diversification benefit hiding inside
the structure.

The senior target is not the loan coupon. It is the accounting hurdle used to divide facility value
between the two classes, and it is paid only if the value or recovery exists.

## Why each side wants it

**Borrower:** combine senior pricing with junior risk appetite in one line, with the opening capital stack
set for the credit being financed.

**Senior desk:** own a named credit above visible funded junior capital, with priority on value and a fixed
annual target.

**Junior desk:** own the residual above senior's fixed target in exchange for taking the first hit and
waiting behind senior exit requests.

This is useful precisely because the tickets are different. The final decision still comes down to the
obligor, use of proceeds, price, junior thickness, covenants and expected time to cash.

## What the spread can buy

In the [Acme example](ACME_WORKED_EXAMPLE.md), the borrower pays a 10% lender rate. Senior supplies 80% of
the capital at an 8% annual target. In the paid-as-agreed case, junior's $4m first-loss cheque ends the year
at $4.72m: an 18% illustrative return. The same structure shows junior going to zero before senior is
impaired in the severe case.

That is the pitch in numbers. Junior earns the spread when the credit performs and absorbs the first loss
when it does not.

## Run the downside before discussing yield

Assume 300 senior, 100 junior and 315 due to senior:

| Facility value | Senior | Junior | Result |
| ---: | ---: | ---: | --- |
| 420 | 315 | 105 | Senior target covered; junior keeps the excess |
| 340 | 315 | 25 | Junior value is 75 below its opening cheque |
| 280 | 280 | 0 | Junior is wiped; senior is 35 short of target |

The junior percentage is checked when senior capital enters and while an active junior investor exits.
It is not replenished after a loss. The cushion can fall to zero.

## Cash is asynchronous

Junior normally funds first. Senior can enter only if the agreed junior percentage remains in place.
Both cheques finance the same loan.

An exit request joins the loan's withdrawal cycle. It is paid when cash is available, which may be later
and may happen in pieces. Senior exit requests clear before junior exit requests; requests are FIFO inside
each class. In distress, cash is also held for the senior claim that has not yet requested exit.

A transferable position is not necessarily liquid. A holder may have no buyer, no venue and no useful
bid.

## Arrears and workout

New funding stops while the loan is in arrears. Accrued arrears charges cannot mark the position up while
arrears continue, although losses still count.

If the borrower cures before permanent wind-down is recorded, the facility can resume. Wind-down begins
when the loan closes or when a live arrears threshold is observed by an operating checkpoint. Once
recorded, it does not reverse. Senior accrual freezes at the cutoff; exits, collections and claims carry
on.

This is an operating rule. Legal default, enforcement and remedies belong in the loan documents.

## Keep the three rates separate

1. **Lender rate:** what lenders earn from the borrower before the platform fee.
2. **Platform fee:** a percentage of lender interest, paid by the borrower on top.
3. **Senior target:** the rate used to split facility value between senior and junior.

At a 10% lender rate, a 5% platform fee means 5% of the interest bill. It adds 0.5 percentage points, so
the running borrower cost is 10.5% before arrears or one-off charges. There is no fee at the participation
layer.

## Before anyone says yes

- underwrite the borrower, use of proceeds and repayment source;
- set a junior cheque that survives the downside case the desk actually believes;
- model whole, junior-loss and senior-loss outcomes with time to cash;
- list every loan term that can change and whose consent is required;
- settle custody and transfer operations;
- name the people monitoring arrears and running a workout; and
- get legal, tax, regulatory and accounting advice for the parties involved.

Use the [parameter worksheet](PARAMETER_DISCOVERY.md) to price the case. Keep the
[desk FAQ](FAQ_AND_CLAIMS.md) nearby when the questions start.
