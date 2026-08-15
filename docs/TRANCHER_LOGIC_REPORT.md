# TrancheManager Design and Implementation Position

## Scope

This document sets out the economic logic, contract shape and remaining choices for a two-class
Wildcat trancher. It reads as the design itself: what senior and junior own, how value and losses are
recognised, how exits settle, and what the singleton V2.5 construction permits.

The current contracts are an engineering prototype. The deterministic deployment path works
against the pinned V2.5 stack; the complete real-contract deposit and exit lifecycle is still the
next proof.

## The mechanism

The intended product is one Wildcat credit position with two claims over it:

- senior owns a priority target, expressed in base-asset terms;
- junior owns the residual and takes the first loss;
- neither class receives a promise that exceeds value actually held or cash actually recovered;
- one manager is the lender to the market and custodian of the canonical wrapper shares;
- entry may be restricted, but burns, withdrawal execution and claims must remain available.

The accounting identity is simple:

```text
V = realised value attributable to the manager
S = min(seniorOwed, V)
J = V - S

S + J = V
```

`seniorOwed` starts with senior principal and accrues while the manager is active. Junior receives
the market return left after that accrual. If value falls, junior reaches zero before senior is
impaired.

### Capital formation

`minJuniorBips` fixes the minimum junior fraction of total value. At a 20% floor, every 1 unit of
junior supports at most 4 units of senior. The constraint is enforced on senior entry and junior
exit:

```text
juniorValue / (seniorValue + juniorValue) >= minJuniorBips / 10,000
```

That makes junior capital the admission condition for senior capital. A factory can deploy a
manager with poor terms, but it cannot fill the senior tranche unless junior funds those terms.

A useful facility shape is 20% junior and 80% senior. At that floor, senior entry and junior exit
both close. An extra 1 unit of junior then permits 4 units of senior. The floor is therefore a live
constraint, not a loss waterfall drawn on a slide.

### Value recognition during delinquency

The design avoids an oracle. Wrapper price per share is allowed to advance while the market is
healthy. Once the market reports delinquency, the manager caps valuation at the last healthy mark:

```text
effectivePps = min(livePps, lastHealthyPps)
```

Penalty interest is not treated as profit before it is realised. Downward moves still count. A cure
allows the live value to be recognised again.

Two consequences follow:

1. a checkpoint taken before the exact delinquency transition can leave some healthy appreciation
   unrecognised until cure;
2. entry during delinquency needs an explicit pricing rule because the existing position is held at
   the frozen mark while new base assets are converted at the live wrapper price.

The first is a conservative marking choice. The second needs a direct rule: `_invest` accepts base
assets and returns the live wrapper conversion, while the existing position is valued at the frozen
mark. The tests do not cover a deposit after the mark has frozen and the live wrapper price has
moved. Entry during delinquency should therefore be closed until its pricing is specified.

### Default and wind-down

The automatic default proxy is:

```text
timeDelinquent >= delinquencyGracePeriod + defaultPenaltyWindow
```

A closed market also triggers wind-down. Governance or an optional `defaultDeclarer` may force the
same transition earlier. The transition is one-way. The manager accrues the final active interval,
freezes the senior obligation, closes deposits and stops further senior accrual.

This order is required. Checking default before accruing understates `seniorOwed` and can release
cash to junior too early. The final active interval must be booked before wind-down.

### Exit and recovery

Exit mirrors the Wildcat withdrawal queue:

1. burn tranche shares;
2. calculate the class value represented by those shares;
3. redeem enough wrapper shares at the live wrapper price to receive that amount of market tokens;
4. queue the market tokens in a Wildcat withdrawal batch;
5. record the request's class, face, expiry and FIFO position;
6. execute the batch after expiry;
7. allocate recovered base assets senior-first, then permit claims.

Wrapper redemption must use the live price even while tranche valuation uses the frozen mark.
Sizing the wrapper withdrawal at the frozen mark would let an exiter pull delinquency appreciation
which the accounting has deliberately excluded.

Settlement uses cumulative FIFO positions. Dividing a class cash pool by a face total which keeps
growing would let a late request claim against cash already paid to an earlier request. The
conserving form is:

```text
faceBefore[id] = class face queued before this request
entitlement = clamp(classCashAllocated - faceBefore[id], 0, requestFace)
claimable = entitlement - alreadyClaimed
```

This is FIFO within each class and senior-first between classes. FIFO was chosen because it matches
the market's batch ordering, is O(1) per request and never needs a clawback. It is not pari-passu
within a tranche.

While healthy, junior cash is held behind senior face already queued. While delinquent or in
wind-down, junior cash is held behind the full senior obligation, including senior which has not
queued. This is the point which turns a normal queue into an actual senior/junior recovery waterfall.

Recovery is derived from the manager's base-asset balance plus cash already claimed. This lets a
permissionless `sync()` account for funds which arrive outside `pokeRecovery`, including a market
withdrawal executed directly by another caller.

### Access and sanctions

The tranche tokens call the manager on ordinary transfers. Mint and burn skip the hook, so an entry
policy cannot block exit. The current policy is:

- both tranches: sender and recipient must not be sanctioned;
- junior: recipient must also be in `juniorAllowed`;
- a sanctioned owner may still claim, but the payment goes to a sentinel escrow;
- sanctions use the market's registered borrower principal, which remains stable across borrower
  wallet rotation.

The manager currently keeps a local junior allowlist and leaves senior open apart from sanctions.
External entry gates are useful only if eligibility policy must be shared across products.

## Design position

| Question | Adopted position | Remaining work |
|---|---|---|
| Custody | The manager deposits base assets, wraps every market token and holds every wrapper share. | Prove the complete custody cycle against the pinned contracts. |
| Market admission | The borrower deploys a predicted CREATE2 manager already named by a sealed singleton provider. | Keep the factory verification matched to the final V2.5 hook ABI. |
| Deposit asset | Base asset only. The singleton boundary says users should not own market tokens or wrapper shares. | Specify whether any entry is allowed during delinquency. |
| Senior return | Fixed annual `seniorRateBips`, checkpointed before a timelocked change. | Confirm the facility rate and who controls changes. |
| Junior floor | Immutable minimum junior ratio, bounded to 5% through 90%. | Select the facility value at deployment. |
| Valuation | Wrapper-price watermark frozen during delinquency. | Define exact-transition marking and delinquent-entry pricing. |
| Default | Market closure, grace plus penalty window, or an authorised declaration. | Confirm the declarer and whether the role can later be retired. |
| Recovery | Senior-first across classes, FIFO within each class, full senior reserve under distress. | Restore broad distress and recovery coverage on the current manager. |
| Entry rules | Manager-local junior allowlist; senior is restricted only by sanctions. | Decide whether either class needs an external gate. |
| Factory registry | One manager per market; replacement is rejected. | Resolve successor semantics before any facility needs replacement. |
| Governance recovery | None. Lost governance freezes policy but does not block exit. | Decide before production whether recovery is wanted at all. |
| Token metadata | Hard-coded `sr-wmt` and `jr-wmt`. | Make names unique before two managers are presented to users. |
| Batch claims | Single `claim`. | `claimMany` is convenience work and does not block the mechanism proof. |
| Terminal dust | No allocation rule. | Specify and test it before deployment. |

## Contract shape

The present topology is internally coherent:

```text
senior/junior users
        |
        | base asset
        v
TrancheManager -- sole deposit credential --> Wildcat market
        |                                      |
        | owns every share                     | market-token backing
        v                                      v
canonical Wildcat4626Wrapper <-----------------+
```

The manager address is known before the market exists. The singleton provider is sealed with that
address as its lender. The market and canonical wrapper are then created, and the manager is
deployed at the predicted address. The factory verifies the market, wrapper, hook template,
provider and sentinel before initialising the manager.

This makes the factory slot unsquattable without introducing a factory owner. The product is not a
tranching adapter attached to an ordinary market with other direct lenders. The manager is the only
economic lender, and the wrapper is only its custody adapter.

`build/test/Fork.t.sol` proves deployment against the V2.5 contracts pinned at
`49be5432dbc8f268aec84beaada31de406fad875`. It does not yet run a base-asset deposit and async exit
through that real stack. Deployment is proven; the economic lifecycle is not.

## Open design decisions

### 1. Fixed or floating senior rate

The current fixed rate is the better prototype default. A floating definition would let a borrower
APR change alter the senior target at the next checkpoint. A fixed manager rate gives each
checkpoint one unambiguous liability. A floating product can still be built, but it should be a
term-sheet choice with its own tests.

### 2. Deposits during delinquency

There are three defensible rules: reject new deposits while delinquent; admit only junior rescue
capital using a stated price; or admit both classes under a frozen-mark calculation. The code should
not choose among them as a side effect of `_invest`. The shortest route to a trustworthy prototype
is to reject ordinary entry while delinquent, then add a separate junior rescue path later if the
facility needs one.

### 3. Supersession

Two live managers for one market would make the senior claims of one manager pari-passu at market
level with the junior assets of the other. That breaks the meaning of seniority. Replacement should
therefore move the factory's current pointer only after the incumbent is wound down or has no
tranche supply, while claims on the retired manager remain callable forever.

### 4. Governance loss

Lost governance currently freezes policy while leaving exits alive. That is a safe failure mode for
the assets, albeit awkward operationally. A borrower recovery path adds takeover risk and should not
be added merely for convenience.

### 5. Exact delinquency marking and terminal dust

Both affect who receives value. They need written rules before code. A market callback could capture
the exact healthy-to-delinquent mark. A terminal rule must say who receives residual wrapper shares,
base assets and rounding dust after all tranche supply and requests are gone.

The build sequence from here is in
[`TRANCHER_LOGIC_RUNBOOK.md`](TRANCHER_LOGIC_RUNBOOK.md).
