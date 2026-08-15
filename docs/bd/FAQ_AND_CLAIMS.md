# Desk FAQ

## What am I buying?

A senior or junior participation in one named borrower facility. Not a pool. Not a different loan.

## Where do I attach?

Junior takes loss first. Senior takes loss after junior reaches zero.

## Who gets paid first?

Senior has first claim on facility value. Senior exit requests clear before junior exit requests, and
requests stay FIFO inside each class. During distress, cash is also reserved for the remaining live
senior obligation.

## Is senior guaranteed?

No. Priority is not protection from a loss large enough to wipe out junior.

## Is the junior cushion maintained?

No. It is checked when senior enters and when junior exits before permanent wind-down is recorded. It can
shrink or disappear after a loss.

## Is the senior target the loan coupon?

No. The loan coupon is what the borrower pays. The senior target is an annual simple accounting hurdle
used to divide value between senior and junior.

## How do I get cash out?

Request an exit and wait for the underlying loan to produce cash. Settlement can be delayed or partial.

## Can I sell it?

Only to an eligible, sanctions-cleared recipient. The system does not promise a market, buyer or price.

## What happens in arrears?

New money stops. The position cannot be marked up using arrears charges, though losses still count. Cure
can restore normal operation before wind-down is recorded.

## What starts wind-down?

Loan close, or an operating checkpoint that sees the current arrears period reach loan grace plus the
agreed extra window. Once recorded, wind-down is permanent and senior stops accruing at the cutoff.

## Is that legal default?

Not by itself. Legal default, enforcement and remedies belong in the deal documents.

## What does the borrower pay?

The loan rate plus the Wildcat protocol fee, before origination and arrears charges. The current facility
adds no second manager fee. The protocol fee is a platform charge calculated on lender interest, not
principal.

## Who chooses the terms?

The borrower proposes the senior target, junior percentage, extra workout window, each class's eligibility
setting and final surplus recipient inside fixed ranges. Entry can be open or use a fixed provider. Manager
economics and that open-or-provider choice are set once; a selected provider's policy may change.

## Can the deal be repriced later?

Not through the facility. There is no manager governance, repricing, pause or discretionary default role.
Any consent rights need to be written into the offchain deal.

## What happens under sanctions?

A sanctioned holder can exit, with proceeds routed to escrow. If the facility account is sanctioned,
new withdrawal-batch execution and recovery are deferred for everyone until clearance and retry. Cash
already allocated can still be claimed, subject to the holder's own sanctions routing.

## What belongs in credit committee?

The borrower memo, capital stack, pricing, base and downside cash cases, time to cash, amendment rights,
reporting, eligibility, sanctions operations, legal analysis and named workout owners.

## Is it ready to buy?

No. It is a tested prototype. It is not rated, audited or in production.

## Say this

One borrower exposure. Senior priority. Junior first loss. Annual simple senior target. Asynchronous cash
exit. Controlled transferability. Manager economics and eligibility settings fixed at formation.

## Never say this

Guaranteed yield. Principal protected. Maintained cushion. Instant redemption. Freely transferable.
Liquid. Rated. Automatic legal default. Audited. Production-ready.
