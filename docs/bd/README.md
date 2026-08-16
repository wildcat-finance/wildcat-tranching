# One credit. Two ways to own it.

A borrower has a credit worth funding. Senior wants a funded first-loss piece beneath it. Junior wants
the return left after senior's fixed annual target. Put both into one facility and the same borrower cash
supports two different tickets.

The point is not to make bad credit look good. It is to give good credit more than one clearing price.
Start with the borrower, return and attachment point. Explain the software if somebody asks.

## Why desks take the meeting

**Senior** can own the named credit above explicit funded first-loss capital, with priority on facility
value and a fixed annual target.

**Junior** takes the first hit and owns the residual after senior. If the credit performs above the senior
target, junior keeps the difference.

**The borrower** can bring both pools of capital into one facility and set the initial senior target,
junior percentage and workout window around the credit being financed.

Nobody gets diversification by vocabulary. Both tickets still underwrite the same borrower.

## Take into the room

- [Meeting brief](MEETING_BRIEF.md): the opening and the five useful questions.
- [Desk primer](PRIMER.md): return, loss and cash timing.
- [Parameter worksheet](PARAMETER_DISCOVERY.md): the decisions needed to price a facility.
- [Desk FAQ](FAQ_AND_CLAIMS.md): short answers for the obvious objections.
- [Infographics](INFOGRAPHICS.md): the structure on a screen.
- [Acme worked example](ACME_WORKED_EXAMPLE.md): a $20m facility through performing, cured and loss paths.

The [research report](RESEARCH_REPORT.md) is internal source material. Use it to check an edge case, not
to pitch the trade.

## Put this on the first page of every deal

Borrower and use of proceeds. Facility size and expected draw. Lender rate and total borrower cost.
Senior and junior cheques. Senior target and attachment point. Withdrawal cycle and expected time to cash.
One delayed-payment case and one loss case.

## Read the payoff in thirty seconds

Assume 300 senior, 100 junior and 315 due to senior:

| Facility value | Senior | Junior | Result |
| ---: | ---: | ---: | --- |
| 420 | 315 | 105 | Senior target covered; junior keeps the excess |
| 340 | 315 | 25 | Junior has absorbed the reduction in value |
| 280 | 280 | 0 | Junior is gone; senior is impaired |

The same credit can suit one desk at the senior attachment and another at the junior attachment. Seniority
changes the order of value and loss; underwriting still decides whether either ticket is worth owning.

## What the borrower sets

At formation, the borrower proposes:

- the senior annual target;
- the junior percentage;
- the extra arrears window before permanent wind-down;
- whether each class is open or uses a named eligibility provider; and
- who receives genuine surplus after every holder has been paid.

Those manager terms do not have later setters. A named provider can still run a policy that changes over
time.

The loan has its own size, lender rate, withdrawal cycle, grace period, arrears charge and amendment
rights. The platform fee is set separately. Put all of them on the term sheet because they affect cost,
cash timing or both.

## What earns the second call

- **Credit:** one named borrower, not a diversified pool.
- **Attachment:** junior loses first; senior loses after junior reaches zero.
- **Return:** senior has a fixed annual accounting target; junior owns the residual. Neither is promised.
- **Cash:** exit waits for cash from the borrower and may settle in pieces.
- **Transfer:** for an open class, yes: any wallet can receive it unless the Chainalysis sanctions oracle
  flags the wallet. That does not create a buyer or a price.
- **Workout:** arrears stop new money. A recorded threshold or loan close starts permanent wind-down.
- **Control:** manager economics are fixed at formation; loan-level amendment rights remain separate.

## Never say

Guaranteed yield. Principal protected. Maintained cushion. Instant redemption. Liquid. Rated. Automatic
legal default. Audited. Production-ready.

Say what it is: one borrower credit, split into a senior claim and a junior first-loss claim, with cash
exit tied to the borrower's ability to pay.

## Scope

This pack assumes the intended V2.5 integration lands as designed and describes the facility Wildcat means
to bring to market. The current repository is tested implementation work, not a live offer, rating,
guarantee, legal opinion or promise of liquidity. That belongs in diligence; it does not need to be the
opening slide.
