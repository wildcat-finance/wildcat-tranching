# TradFi outreach primer

## The short version

Wildcat tranching is a way to place two economic claims over one onchain credit market. Senior
capital has a fixed target and sits ahead of junior capital in realised-loss and recovery logic.
Junior capital takes first realised loss. Both claims remain tied to the same underlying market,
its borrower, its fee terms and its withdrawal queue.

The useful conversation is not “we have made private credit liquid”. We have not. It is: can a
credit desk that already understands a borrower and a loan use a transparent, constrained facility
to express senior and first-loss participation without maintaining a second loan book?

## Who to speak to

Start with people already comfortable underwriting a single borrower exposure but wanting a clearer
capital stack around it:

- originators and credit funds with a repeat borrower base;
- specialist lenders looking for a junior or first-loss capital partner;
- allocators that want a bounded senior exposure rather than the whole loan;
- treasury or balance-sheet teams evaluating programmable credit infrastructure.

Do not lead with token mechanics. Begin with the existing credit relationship, the desired risk
split, the withdrawal expectations and the constraints each participant will accept.

## What to say

“The facility keeps one Wildcat market as the loan. A manager holds the canonical wrapped market
position and issues senior and junior participation claims above it. Junior capital takes realised
loss first; recovery is senior-first. Redemptions are asynchronous because the underlying market is
asynchronous. The system is designed to make the risk split and settlement path inspectable, not to
hide a credit decision behind software.”

If protocol fees come up: the market’s protocol fee remains a disclosed market term and is paid in
the market layer. The tranches divide the net market position; they do not waive, redirect or create
a separate protocol-fee stream. That is an intentional trade-off: the protocol is providing the
market, wrapper, access controls and settlement rail on which the facility relies.

## Questions to ask early

1. Who underwrites the borrower, and what would make them stop lending?
2. What senior target, junior thickness and concentration limits are acceptable?
3. Who is permitted to acquire each class, and who runs that onboarding policy?
4. What redemption timing should participants expect in a normal market and in a shortfall?
5. Which sanctions, reporting, custody and legal arrangements are required before capital moves?
6. Are the market’s protocol fee, reserve ratio and delinquency terms acceptable as written?

## Boundaries to keep explicit

- Senior is not a guarantee. It remains exposed to borrower performance, market mechanics and
  residual loss once junior value is exhausted.
- Junior is not a generic tokenised fund interest. It is the first-loss claim for one named market.
- A redemption request is an instruction into the underlying queue, not a promise of cash on a set
  date.
- Entry gates restrict acquisition only. They do not trap an existing holder in a live facility.
- The current code is a demonstrable prototype. It needs the stated V2.5 audit-bundle changes,
  independent review, deployment controls and legal structuring before a production proposal.

## A sensible next meeting

Bring one candidate exposure and work through a single base case and a single shortfall. Confirm
the capital stack, expected queue behaviour, protocol fee, entry policy and operational roles. If
those do not make sense without a slide deck, they will not become clearer after deployment.
