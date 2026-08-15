# One loan, two classes: desk primer

## The trade

The borrower wants one line of credit. Junior puts up the first-loss capital. Senior funds above it for an
annual simple accounting target. Senior has first claim on realised value; senior exit requests clear
before junior requests. When value falls, junior is hit first. Once junior is gone, senior loses money.

No pool. No diversification. No alchemy. Both classes own the same borrower risk.

| | Senior | Junior |
| --- | --- | --- |
| Return | Annual simple accounting target | Everything left after senior |
| Loss | After junior is exhausted | First loss |
| Recovery cash | Senior exit requests first; FIFO within senior | After senior exit requests; FIFO within junior |
| Exit | Waits for cash from the loan | Waits for cash from the loan |
| Transfer | Eligible, sanctions-cleared recipients only | Eligible, sanctions-cleared recipients only |

The senior target is not the borrower's coupon and it is not guaranteed. It accrues on outstanding senior
principal and is the hurdle used to divide the facility's value between the two classes.

## Why each side might care

**Borrower:** one facility can reach two pools of capital with different return and loss appetites. The
borrower proposes the capital stack once, inside fixed limits.

**Senior desk:** defined priority, visible first-loss capital and a fixed return target without taking the
residual position.

**Junior desk:** the residual economics in exchange for taking the first hit and having junior exit
requests wait behind senior exit requests.

That is the commercial bargain. Whether it is a good trade still comes down to the borrower, the price,
the junior thickness and the time to cash.

## The downside, without the theatre

Assume 300 senior, 100 junior and 315 owed to senior:

| Facility value | Senior | Junior | Read it as |
| ---: | ---: | ---: | --- |
| 420 | 315 | 105 | Senior target covered; junior earns the residual |
| 340 | 315 | 25 | Facility value is down 60; another 15 has accrued to senior |
| 280 | 280 | 0 | Junior is wiped; senior is 35 short of target and 20 below principal |

The junior percentage is checked when senior money comes in and when junior leaves before permanent
wind-down is recorded. It is not topped back up after a loss. If the credit deteriorates, the cushion can
shrink to zero.

## Cash in, cash out

Junior normally funds first. Senior can fund only while the agreed junior percentage remains in place.
Both cheques go into the same loan.

Exit is not cash on demand. A holder submits a request and waits for liquidity and borrower repayment.
Cash can arrive in pieces. Senior requests are paid before junior requests; requests stay FIFO inside
each class. During distress, cash is also held behind the remaining live senior obligation.

The interests are transferable subject to eligibility and sanctions checks. Transferable does not mean
liquid. There may be no buyer, no venue and no useful bid.

## Arrears and workout

Once the loan is in arrears, new funding stops. Arrears charges cannot be used to mark the position up;
losses still count. A cure can return the facility to normal operation if wind-down has not already been
recorded.

Wind-down starts when the loan closes or when an operating checkpoint sees the current arrears period at
the loan grace period plus the agreed extra window. Once recorded, it does not reverse. Senior stops
accruing at the cutoff; exits, collections and claims carry on.

That is an operating trigger, not automatically a legal event of default. Put legal remedies in the loan
documents where they belong.

## Price the right thing

Borrower cost is the loan rate plus the Wildcat protocol fee, a platform charge calculated on lender
interest, before origination or arrears charges. The current facility adds no second manager fee.

If the lender rate is 10% and the protocol-fee setting is 1,000 bips, the running cost is 11%: 10% to
lenders and one percentage point to the platform.

The senior target is a separate number. It divides value between senior and junior; it does not increase
what the borrower owes.

## Before anyone says yes

- underwrite the borrower, purpose, repayment source, covenants and collateral;
- choose the senior attachment and a junior cheque that survives the actual downside case;
- model base, junior-loss and senior-loss outcomes, including time to cash;
- agree which loan terms can move and whose consent is required;
- settle eligibility, custody, sanctions and transfer operations;
- name the people monitoring arrears and running a workout; and
- get legal, tax, regulatory and accounting advice for the actual parties and jurisdictions.

Use the [parameter worksheet](PARAMETER_DISCOVERY.md) to price a live case. Use the [desk FAQ](FAQ_AND_CLAIMS.md)
before sending language outside the firm.
