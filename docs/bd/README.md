# One loan. Two risk books.

The borrower raises one facility. Junior takes the first loss and keeps the residual return. Senior sits
above it, accrues an annual simple accounting target and has first claim on realised value. Senior exit
requests clear before junior requests. Same borrower. Same pool of cash. Different attachment points.

That is the pitch. Do not open a meeting by explaining the platform.

This is a prototype, not a live offer, rating, guarantee, legal opinion or promise of liquidity.

## Take into the room

- [Meeting brief](MEETING_BRIEF.md): the opening, the questions and the close.
- [Desk primer](PRIMER.md): the trade, the downside and the cash mechanics.
- [Parameter worksheet](PARAMETER_DISCOVERY.md): the numbers and controls that need an answer.
- [Desk FAQ](FAQ_AND_CLAIMS.md): short answers when the room starts kicking the tyres.
- [Infographics](INFOGRAPHICS.md): six diagrams for a screen or follow-up note.

The [research report](RESEARCH_REPORT.md) and [delivery runbook](DELIVERY_RUNBOOK.md) are internal source
material. Use them to check a claim, not to sell the trade.

## The trade in numbers

Assume 300 senior, 100 junior and 315 owed to senior:

| Facility value | Senior | Junior | What happened |
| ---: | ---: | ---: | --- |
| 420 | 315 | 105 | Both classes are whole; junior keeps the excess |
| 340 | 315 | 25 | Junior has absorbed the loss |
| 280 | 280 | 0 | Junior is gone; senior is impaired |

Seniority changes the order of payment and loss. It does not make weak credit good.

## Who sets the deal

The borrower proposes the senior target, junior percentage, extra workout window, fixed eligibility-gate
addresses and final surplus recipient when the facility is formed. The ranges are bounded and the manager
terms do not have later setters. A gate's external eligibility policy may still change.

The underlying loan still has its own rate, size, liquidity, delinquency and amendment terms. Platform
fees and operating rails are set separately. The code fixes the waterfall, FIFO inside each class,
sanctions routing and wind-down mechanics.

In plain English: the borrower can price and shape the capital stack at inception. The borrower cannot
rewrite the waterfall after the money lands.

## What matters to a desk

- **Credit:** one named borrower exposure; no diversification trick.
- **Attachment:** junior absorbs loss first; senior takes loss after junior is exhausted.
- **Return:** senior has an annual simple target; junior owns the residual. Neither is guaranteed.
- **Liquidity:** exit waits for cash from the underlying loan and may be partial.
- **Transfer:** interests can move only to eligible, sanctions-cleared recipients. A bid is not promised.
- **Workout:** arrears stop new money; an observed threshold or loan close puts the facility into one-way
  wind-down.
- **Control:** facility economics are fixed at formation; loan-level operating rights remain separate.

## Never say

Guaranteed yield. Principal protected. Maintained cushion. Instant redemption. Freely transferable.
Liquid. Rated. Automatic legal default. Audited. Production-ready.

Say what the trade actually is: senior priority, junior first loss, asynchronous cash exit and one
borrower credit underneath both.
