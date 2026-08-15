# Wildcat tranching: meeting brief

## Open with this

One Wildcat market can have two participation classes without splitting custody or creating a second
loan. A `TrancheManager` is the sole underlying lender. Senior has a fixed accounting target and first
priority in realised value and recovery; junior receives the residual and takes realised loss first.
Both retain the same borrower exposure, and both exit through the Wildcat withdrawal queue.

This is a prototype discussion, not an offer, rating, audit opinion or promise of repayment or timing.

## Five facts to establish

1. **One exposure.** Senior and junior sit over the same named borrower and market.
2. **Priority, not protection.** Junior absorbs loss first, but senior can be impaired once junior is
   exhausted.
3. **Fixed tranche terms.** The borrower chooses a bounded set at formation; the manager has no later
   economic setter.
4. **Separate market controls.** Wildcat market, hook and protocol terms keep their own authorities.
5. **Queued exit.** A request burns tranche shares and settles as the underlying market processes and
   pays its withdrawal batch.

## Borrower choices at formation

- senior target rate: 0% to 100%;
- minimum junior percentage: 5% to 90%;
- extra delinquency window: more than 0 and no more than 90 days;
- senior and junior gate contracts: zero for open entry, otherwise a contract; and
- terminal-surplus recipient: fixed, nonzero and not the manager.

There are no factory defaults for those terms. Gate addresses are fixed, but a gate contract may carry
mutable policy. These choices do not let the borrower change the deployed waterfall later.

## Ask the borrower

- Who is the named credit exposure, and what market capacity and lender APR are contemplated?
- What senior target and junior thickness make the all-in cost and capital mix workable?
- How long after the market grace period should the facility wait before irreversible wind-down?
- Should either class be open, allowlisted, credential-based or restricted to named entities?
- Who controls each gate contract, and can its policy change?
- What withdrawal-batch duration, reserve behaviour and repayment plan should lenders model?
- Are the current protocol-fee basis, update authority and any origination charge understood?
- Who should receive genuine surplus after every holder claim and custody position has cleared?

## Ask senior lenders

- What junior percentage is the minimum acceptable at entry?
- What target rate compensates for the borrower risk, queue and controlled transferability?
- Which accounts or legal entities must be eligible to acquire the position?
- What information is needed to monitor the market, delinquency counter and withdrawal queue?
- What partial-recovery and delayed-settlement cases must be modelled before approval?

## Ask junior providers

- What expected residual is needed for first-loss exposure and senior accrual?
- What maximum senior size and target are acceptable against the junior contribution?
- Is senior-first cash recovery acceptable during stress?
- How should the active junior-exit constraint affect treasury planning?
- What reporting is needed to explain changes in the realised mark and remaining junior value?

## Keep these boundaries in the room

Say:

- fixed senior accounting target;
- junior first realised loss;
- senior-first recovery, FIFO within class;
- controlled transferability; and
- asynchronous exit.

Do not say:

- guaranteed yield or principal protected;
- maintained junior cushion;
- instant redemption or liquid market;
- immutable allowlist;
- legal default, rating or securitisation conclusion; or
- audited, production-ready or live V2.5 product.

## Close with the next piece of work

Agree a range rather than a term sheet: senior target, junior percentage, extra delinquency window,
market APR and capacity, withdrawal timing, gate model and operator, protocol charges, reporting needs
and two stress cases. Record who controls each answer. Anything legal, tax, regulatory, sanctions-policy
or credit-underwriting specific goes to the relevant owner before it becomes external language.
