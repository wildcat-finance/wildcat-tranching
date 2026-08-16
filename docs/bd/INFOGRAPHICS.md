# Deal diagrams

Eleven screen-ready pictures: six pages for the structure and five for the Acme worked credit. Do not send
all eleven as a dump. Pick the structure, payoff and cash case that answer the room's actual question.

## One loan, two claims

![One named borrower facility supports a senior claim and a junior first-loss claim.](assets/one-loan-two-claims.png)

Use this first. Both classes own the same borrower credit. Senior has a fixed accounting target; junior
takes the first loss and keeps the residual.

## Loss waterfall

![Three cases show junior absorbing loss before senior is impaired.](assets/loss-waterfall.png)

Use this before discussing yield. The junior percentage is not rebuilt after loss.

## Who sets what

![Borrower formation terms, loan terms and system or platform settings are shown separately.](assets/who-sets-what.png)

The borrower shapes the capital stack at formation. Loan amendments and platform settings remain separate.

## Cash lifecycle

![Six steps show funding, borrower draw, exit request and cash clearing.](assets/cash-lifecycle.png)

The withdrawal cycle batches an exit request. Payment still waits for borrower cash. For an open class,
any wallet may receive the participation unless the Chainalysis sanctions oracle flags it.

## Arrears and workout

![An arrears timeline branches to cure or permanent wind-down.](assets/arrears-and-workout.png)

Cure must happen before the live threshold is recorded. Once recorded, wind-down stays and senior accrual
freezes at the cutoff.

## Borrower cost and holder return

![A 10 percent lender rate plus a fee equal to 5 percent of interest produces a 10.5 percent running borrower cost, while the participation waterfall separately divides value.](assets/cost-and-returns.png)

A 5% platform fee means 5% of the interest bill, not five percentage points of principal. The senior target
is another number again: it divides value between the two classes. No fee is charged at the participation
layer.

## Use them properly

- Keep the qualification with the picture.
- Treat every number as an illustration until a live credit is approved.
- Do not promise repayment, liquidity, rating or legal treatment.
- Use the [field-kit visual rules](BRAND_AND_VISUALS.md) for any new image.
- Send implementation questions to the [internal research report](RESEARCH_REPORT.md).

These diagrams assume the intended V2.5 integration lands as designed. They describe the facility Wildcat
means to bring to market; they are not a rating, audit opinion or live offer.

## Worked sequence

The [Acme Ltd example](ACME_WORKED_EXAMPLE.md) has five pages that can be presented in order:

1. [Terms](assets/acme-terms.png)
2. [Funding](assets/acme-funding.png)
3. [Happy: paid as agreed](assets/acme-performing.png)
4. [Neutral: cured on day 24](assets/acme-cure.png)
5. [Catastrophic: $12m net recovery](assets/acme-loss.png)
