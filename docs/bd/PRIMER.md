# Wildcat tranching: counterparty primer

## What this is

The current prototype puts two participation classes over one Wildcat market. A per-market
`TrancheManager` is the market's sole lender and holds the whole wrapped market position. Senior and
junior holders own claims issued by that manager; neither class owns a separate loan.

Senior has a fixed accounting target and first claim on realised value and recovery. Junior receives
what remains and takes realised loss first. Both classes still face the same borrower, market and exit
process. The structure changes payment order. It does not guarantee senior principal or return.

This material describes the prototype at repository commit
`b90a155f257c76f96e50cf2fa29872e1735f8bd8`. It is not a live offering, rating, legal opinion, audit
report or promise of liquidity.

## The one-minute explanation

A borrower creates one Wildcat market for a predicted `TrancheManager` address, with the manager fixed
as the only underlying lender. The borrower then attaches the manager and chooses a bounded set of
tranche terms once: senior target rate, minimum junior percentage, an additional delinquency window,
entry-gate contracts for each class, and the eventual recipient of genuine terminal surplus.

Junior capital normally enters first. Senior can enter only while the chosen junior percentage is
preserved. The manager lends the combined base asset into the same Wildcat market and wraps the entire
position. Senior accrues its accounting target on outstanding senior principal; junior receives the
residual. A holder exits by burning tranche shares into the underlying Wildcat withdrawal queue. Cash
is allocated senior first across classes and FIFO within each class as the market pays.

## One market, two claims

| Credit-language term | Contract-language term | What it means here |
| --- | --- | --- |
| Underlying exposure | Wildcat market | One borrower credit market, not a pool |
| Facility agent and waterfall | `TrancheManager` | Sole lender, custody holder, accountant and recovery allocator |
| Senior participation | Senior `TrancheToken` | Fixed accounting target with first priority, limited by realised value |
| First-loss participation | Junior `TrancheToken` | Residual return and first realised loss |
| Eligibility policy | Senior or junior entry gate | Fixed gate address; policy inside the gate contract may change |
| Redemption notice and settlement | Request, Wildcat batch and claim | Asynchronous exit rather than cash on demand |
| Objective wind-down | Manager `WindDown` state | One-way onchain state after market close or the delinquency threshold |

The analogy stops at payment priority. There is one market, one borrower, no SPV, no diversified loan
pool, no rating and no repayment guarantee.

## Who chooses the terms

Yes, the borrower has genuine formation choices. The market borrower is the only account allowed to
deploy the manager for its market and supplies these one-time terms:

| Tranche term | Prototype bound | After deployment |
| --- | --- | --- |
| Senior target rate | 0% to 100% a year | Fixed |
| Minimum junior percentage | 5% to 90% | Fixed |
| Additional delinquency window | More than 0 and no more than 90 days | Fixed |
| Senior and junior entry gates | Zero address for open entry, otherwise a contract | Gate address fixed; external gate policy may change |
| Terminal-surplus recipient | Nonzero and not the manager | Fixed |

The factory has no economic defaults. These values must be supplied. They are not governance rights
and the borrower cannot reprice the tranches later through the manager.

The underlying Wildcat market has its own terms and authorities. Capacity and lender APR have
borrower-authorised update paths. The current hook administrator can change the upstream market-hook
minimum deposit or block fresh manager deposits, and that administrator role can transfer under
Wildcat's rules. The protocol-fee rate, recipient and any origination fee come from the Wildcat hook
template rather than the tranche borrower. None of those upstream powers can rewrite the manager's
waterfall or an existing holder's claim.

## How value is divided

Senior accrues simple interest on outstanding senior principal. It is an accounting target, not the
underlying market APR and not a payment promise. At a checkpoint:

1. the manager measures the realised value of its wrapped market position;
2. senior receives the lesser of that value and the accrued senior amount; and
3. junior receives the remainder.

Consider an illustrative facility with 300 of senior principal, 100 of junior capital and 315 owed to
senior after time has passed:

| Realised manager value | Senior value | Junior value | Reading |
| ---: | ---: | ---: | --- |
| 420 | 315 | 105 | Senior target covered; junior owns the residual |
| 340 | 315 | 25 | Junior absorbs the 80 reduction first |
| 280 | 280 | 0 | Junior is exhausted and senior is impaired |

These figures are an accounting illustration. They are not a forecast, quote or term proposal.

The minimum junior percentage is checked when senior enters and when junior exits while the facility
is active. It is not a continuously maintained cushion. Market loss or price movement can reduce
junior below the chosen percentage and can eventually impair senior.

## Entry and transfer

Deposits require a healthy, active market, sanctions clearance and the relevant class gate. Junior
usually seeds the structure; senior entry must preserve the chosen junior percentage. The value
credited from the first deposit into an empty class must be at least `1e6` base-asset-denominated units,
and conversion rounding can require a slightly larger tender.

Tranche tokens can move between eligible accounts. The sender and recipient must pass sanctions checks,
and the recipient must pass the class gate. This is controlled transferability, not an undertaking that
a buyer or trading venue will exist. A gate can prevent a new account acquiring a position; it cannot
stop an existing holder burning shares, requesting exit or claiming cash.

## Exit and recovery

Exit follows the underlying Wildcat queue:

1. the holder asks the manager to redeem tranche shares;
2. the manager checkpoints value, burns the shares, removes the corresponding wrapped backing and
   queues a Wildcat market withdrawal;
3. the request records the holder, class, face amount and batch expiry; and
4. as the market processes that batch, the manager allocates cash and the recorded holder claims it.

Requests can settle partially. Timing and amount depend on market liquidity, borrower repayment and
the Wildcat batch process. In a shortfall, senior request face is funded before junior request face;
requests within the same class remain FIFO.

If a holder is sanctioned, the holder can still leave. Claim proceeds route to Wildcat's canonical
sanctions escrow rather than being trapped in the manager.

## Delinquency and wind-down

New deposits stop while the market is delinquent. The manager prevents delinquency penalty upside from
being used to inflate tranche value: recognised value is capped at the last healthy mark, while live
losses still count. If the market cures before the objective threshold, the healthy mark can refresh
and entry can reopen.

The manager enters one-way wind-down when the market closes or when the market's onchain delinquency
counter reaches its grace period plus the borrower-chosen tranche window. Senior accrual stops at the
objective cutoff. Deposits remain closed, but exits, recovery, claims and terminal settlement continue.
This is a contract state transition, not necessarily a legal declaration of default.

## Fees

The manager adds no second fee in the current code. Wildcat's protocol fee sits at the market layer and
is charged to the borrower on top of base lender interest. The setting is a percentage of that base
interest: a 1,000-bip protocol setting on a 10% lender APR gives an 11% running base-interest cost,
before any origination fee or delinquency charge.

The protocol can update the rate for an existing open market within the 1,000-bip cap; that market's
fee recipient is fixed. Accrued fees reserve liquidity ahead of unprocessed market withdrawals. An
already-processed unclaimed withdrawal is not later displaced by fee collection. Senior and junior
divide the manager's position and cash actually recovered after the market-level mechanics have run.

## What each side should decide

Borrowers should decide what senior target, junior thickness, entry policy and extra delinquency window
are commercially workable alongside the market APR, protocol charges, reserve behaviour and expected
withdrawal timing.

Senior lenders should decide whether the junior thickness, target return, borrower risk, market terms,
eligibility controls and asynchronous exit are acceptable without treating priority as protection from
all loss.

Junior providers should decide whether the expected residual compensates for first-loss exposure,
senior accrual, senior-first recovery and the limits on active junior exit.

Use the [parameter discovery guide](PARAMETER_DISCOVERY.md) to record those preferences and the
[FAQ and claims guide](FAQ_AND_CLAIMS.md) before sharing any shorthand externally.
