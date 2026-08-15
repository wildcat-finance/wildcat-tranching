# Wildcat tranching: FAQ and claims guide

## What is being tranched?

One wrapped position in one Wildcat market. The manager is the sole underlying lender and issues senior
and junior claims over the same realised value and cash recovery. This is not a pool of loans.

## Is senior principal protected?

No. Junior absorbs realised loss first, but senior is impaired after junior value reaches zero. Senior
priority changes the order of loss and payment; it does not remove borrower credit risk.

## Is the senior rate a fixed yield?

No. It is a fixed accounting target used to divide realised manager value. It accrues on outstanding
senior principal, but payment remains limited by value and recovery. It does not automatically follow
the Wildcat market APR.

## Does the junior percentage stay in place?

No. The contract checks the chosen minimum when senior enters and when junior exits while active. It is
not rebalanced after market movement or loss. Junior can fall below the initial percentage and can be
fully exhausted.

## Can the borrower choose the terms?

Yes, within strict limits and only at formation. The borrower supplies the senior target, minimum junior
percentage, extra delinquency window, two entry-gate addresses and terminal recipient. Those manager
terms have no later setter.

The borrower does not choose everything. The market, hook and protocol layers have separate terms and
authorities. The tranching factory also verifies the registered market, sole-lender arrangement,
canonical wrapper, hook template, sanctions sentinel and exact manager code.

## Can the borrower change anything later?

Not through the manager. The underlying market borrower retains Wildcat-authorised paths for market
capacity and APR. The current hook administrator can change the upstream market-hook minimum deposit or
block fresh manager deposits, and that role can transfer. The protocol factory can update the
protocol-fee rate for an existing open market within its cap. None of those paths reprices the senior
target or rewrites existing payment priority.

## Are the gate policies immutable?

The gate addresses are fixed after manager deployment. A nonzero gate is an external contract, so its
internal policy may change if that contract permits it. Use "fixed gate address", not "immutable
allowlist".

## Can a gate stop someone leaving?

No. Gates apply when an account acquires tranche exposure through deposit or incoming transfer. An
existing holder can still burn, request exit and claim. Sanctions routing remains separate.

## Are the tranche tokens freely transferable?

No. Transfers require both parties to pass sanctions checks and the recipient to pass the class gate.
Even when a transfer is allowed, the protocol does not promise a buyer, venue, price or settlement
liquidity.

## Is redemption instant?

No. The holder burns tranche shares into a Wildcat withdrawal batch. Settlement depends on the market's
batch timing, liquidity and borrower repayment. A request may receive partial cash over time.

## Who receives recovery first?

Senior request face receives cash before junior request face. Within a class, requests are FIFO. During
distress, junior cash is held behind both queued senior face and the remaining live senior obligation.

## What happens during delinquency?

Deposits stop. Recognised value cannot rise above the last healthy mark because of delinquency penalty
upside, although live loss still reduces it. A cure before the objective wind-down threshold can refresh
the mark and reopen entry.

## What causes wind-down?

The manager enters irreversible wind-down if the market closes or its onchain delinquency counter
reaches market grace plus the borrower-chosen tranche window. Senior accrual stops at that objective
cutoff. Exit, recovery and claims continue. This contract state is not necessarily a legal default.

## What fees does the manager charge?

None in the current code. The Wildcat protocol fee is charged at the market layer on top of base lender
interest. A 1,000-bip fee setting is 10% of the lender rate: on a 10% lender APR it adds 1% of running
base-interest cost, before any origination fee or delinquency charge.

Accrued fees reserve liquidity ahead of unprocessed withdrawals. Once a withdrawal is processed and
unclaimed, later fee collection does not displace it. The manager divides only its market position and
cash actually recovered.

## Can the protocol fee change?

The protocol factory can push a changed rate to an existing open market, subject to the 1,000-bip cap.
The fee recipient for that existing market is fixed. A separate origination-fee asset and amount can be
required when the market is created.

## What happens if a holder is sanctioned?

Sanctions block acquisition and ordinary transfers, but do not confiscate the position or prevent
exit. A sanctioned holder can request redemption; claim proceeds route to Wildcat's canonical escrow.

## Who gets money sent directly to the manager?

An unattributed transfer is not treated as recovery for a tranche request. It becomes terminal surplus.
This prevents later requests from claiming cash that was not tied to their Wildcat withdrawal batch.

## What is terminal surplus?

Base asset proven not to belong to a live senior reserve or any holder request. After both tranche
supplies are zero, all custody is unwound, every request is settled and no reserve remains, anyone can
trigger payment to the fixed terminal recipient. A final holder cannot redirect it.

## Is this ERC-4626 or ERC-7540?

The canonical Wildcat wrapper is ERC-4626-shaped custody. The tranche tokens expose valuation-shaped
views but are not full ERC-4626 vaults. The manager's request and claim lifecycle is ERC-7540-style, but
the prototype does not claim full ERC-7540 conformance.

## Is this a CLO, securitisation or rated product?

No such conclusion is made here. Tranche and waterfall language helps explain payment priority. The
prototype has one borrower and one market, no SPV, no diversified pool and no rating. Legal, tax and
regulatory classification belongs with counsel for the proposed facts and jurisdictions.

## Is this audited or production-ready?

No. The repository calls it a prototype. It has tests and release evidence, but those are not an audit
or a production deployment claim. The current V2.5 integration also depends on reconciling the specific
trancher capabilities described in the repository's compatibility assessment. Their absence from a
separate V2.5-only branch is not an error in that branch.

## Approved short phrases

- two claims over one Wildcat market;
- fixed senior accounting target;
- junior first realised loss;
- senior-first recovery and FIFO within class;
- controlled transferability;
- asynchronous exit through the Wildcat queue;
- borrower-selected, bounded terms at formation; and
- objective onchain wind-down.

## Phrases not to use

| Avoid | Why | Use instead |
| --- | --- | --- |
| Guaranteed yield | Payment is limited by realised value and recovery | Fixed senior accounting target |
| Principal protected | Senior can be impaired after junior is exhausted | Senior priority with junior first loss |
| Maintained 20% cushion | The floor is checked at entry and active junior exit, not restored after loss | 20% minimum at the checked actions |
| Instant redemption | Exit uses the Wildcat withdrawal queue | Asynchronous exit |
| Freely transferable | Sanctions and class gates apply; a market is not promised | Controlled transferability |
| Immutable allowlist | Only the gate address is fixed | Fixed gate contract with separately governed policy |
| Borrower controls the facility | Borrower choices are bounded and one-time; upstream authorities differ | Borrower chooses named formation terms |
| Protocol fee comes out of lender APR | It is charged to the borrower on top of base interest | Protocol fee on top of lender base interest |
| Onchain default | Wind-down is a mechanical state and may differ from legal default | Objective manager wind-down |
| Audited or production-ready | Current status is a tested prototype | Prototype under review |

## Escalate before answering

Do not improvise answers about legal classification, securities treatment, tax, accounting treatment,
regulatory permissions, sanctions exceptions, credit approval, a named borrower's likelihood of
repayment, future protocol changes, secondary-market support or production launch dates. Record the
question and send it to the relevant owner.
