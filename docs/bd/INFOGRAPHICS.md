# Deal diagrams

Six pictures. One trade. Keep the captions attached so nobody sells priority as a guarantee or
transferability as liquidity.

## One loan, two tickets

![One borrower facility supports senior and junior participation classes.](assets/one-market-two-claims.svg)

Same credit. Senior has first claim on value and senior exit requests clear before junior requests.
Junior takes the first loss and keeps the residual.

## Where the money goes

![Cash fills senior exit requests before junior requests, while junior absorbs loss before senior.](assets/priority-waterfall.svg)

Use this for the three cases that matter: whole, junior impaired and senior impaired.

## Who controls what

![Four columns separate borrower-selected facility terms, loan operating terms, platform settings and fixed mechanics.](assets/parameter-authority.svg)

The borrower shapes the deal at formation. That does not mean the borrower can rewrite it later.

## Cash in, cash out

![Seven steps run from agreeing terms through funding, loan performance, exit request, cash collection and payment.](assets/healthy-lifecycle.svg)

There is no instant exit. Cash comes out when the loan produces it.

## Arrears and workout

![An arrears timeline branches to cure or permanent wind-down, followed by recovery and settlement.](assets/distress-lifecycle.svg)

Use this to agree who watches the credit, who records the trigger and who runs the workout.

## Borrower cost versus holder return

![Borrower cost combines lender interest and the Wildcat protocol fee, while the facility separately divides value between senior and junior.](assets/cost-and-yield-bridge.svg)

The borrower rate, Wildcat protocol fee and senior target are three different numbers. Keep them that way.

## Reuse rules

- Keep the qualification with the picture.
- Treat every number as an illustration until a live credit is approved.
- Never promise repayment, liquidity, rating or legal treatment.
- Send implementation questions to the [internal research report](RESEARCH_REPORT.md).

## Source note

These diagrams describe the current prototype. They are not a rating, audit opinion or product approval.
The internal [delivery runbook](DELIVERY_RUNBOOK.md) records the render and repository checks.
