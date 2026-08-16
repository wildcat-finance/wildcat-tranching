# Desk FAQ

## Why does this exist?

Because the same borrower can be attractive at one attachment point and uninvestable at another. Senior
gets funded first-loss capital beneath it. Junior gets the residual above senior's fixed target. The
borrower gets one facility rather than asking every desk to accept the same return and loss profile.

## What am I buying?

A senior or junior participation in one named borrower facility. Both classes own the same credit.

## Where do I attach?

Junior loses first. Senior loses after junior reaches zero.

## Who gets the cash first?

Senior exit requests clear before junior exit requests, FIFO inside each class. During distress, cash is
also held for senior claims that have not requested exit.

## Is senior guaranteed?

No. Priority cannot protect senior from a loss large enough to consume junior.

## Is the junior cushion maintained?

No. It is tested when senior enters and while an active junior investor exits. A loss can reduce it to
zero.

## Is the senior target the loan coupon?

No. The loan coupon is what the borrower pays. The senior target is an annual simple hurdle used to split
facility value.

## How do I get cash out?

Submit an exit request and wait for borrower cash. Payment can be late or partial.

## Can I sell it?

For an open class, yes: anyone can receive it unless their wallet is flagged by the Chainalysis sanctions
oracle. The system does not promise a market, buyer or price.

## Why mention sanctions at all?

Because the transfer check exists. That is the whole front-room answer. In operations, a borrower-specific
override can clear an oracle flag for that facility, and a flagged holder's claim is routed through escrow.

## What happens in arrears?

New money stops. The facility cannot use accruing arrears charges to mark itself up while arrears continue,
although losses still count. Cure can restore operation if permanent wind-down has not been recorded.

## What starts wind-down?

Loan close, or an operating checkpoint that observes current arrears at the grace period plus the agreed
extra window. Once recorded, wind-down is permanent and senior accrual freezes at the cutoff.

## Is that legal default?

Not by itself. Legal default, enforcement and remedies belong in the deal documents.

## What does the borrower pay?

The lender rate plus a platform fee calculated as a percentage of lender interest, before arrears and
one-off charges. At a 10% lender rate, a 5% platform fee adds 0.5 percentage points. Running cost is 10.5%.
There is no fee at the participation layer.

## Who chooses the terms?

The borrower proposes the senior target, junior percentage, extra arrears window, class access setting and
final surplus recipient within fixed limits. Those manager terms are set once.

The loan's rate, size, reserve, withdrawal cycle and amendment rights sit outside those fixed manager
terms. The platform controls its own fee schedule.

## Can the capital stack be repriced later?

Not through the manager. There is no manager owner with a repricing, pause or discretionary default button.
Any consent rights need to be written into the deal documents.

## What if the facility account itself is sanctioned?

New withdrawal-batch execution and recovery wait until the account is cleared and the operation is retried.
Cash already allocated remains claimable, subject to the holder's own escrow check.

## What belongs in credit committee?

Borrower memo, use of proceeds, capital stack, price, base and downside cash cases, time to cash, amendment
rights, reporting, legal analysis and named workout owners.

## What stage is this at?

The structure, parameter set and worked economics are ready for counterparty design discussions on the
assumption that the intended V2.5 integration lands as designed. The repository is tested implementation
work; it is not itself a live offer, rating or completed audit.

## Say this

One borrower. Two attachment points. Senior owns priority above funded first loss. Junior owns the residual
and takes the first hit. The borrower shapes the opening stack. Cash exit follows borrower payment. Open
transfer remains subject to the sanctions oracle.

## Do not say this

Guaranteed yield. Principal protected. Maintained cushion. Instant redemption. Liquid. Rated. Automatic
legal default. Audited. Production-ready.
