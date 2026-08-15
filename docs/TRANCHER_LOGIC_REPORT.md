# TrancheManager Design

## Position

The trancher is part of the market, rather than an adapter which can be attached, replaced or
reconfigured later. One Wildcat market has one `TrancheManager`, one canonical wrapper and two
tranche tokens for its entire life.

The borrower chooses the terms when creating the facility. Those terms do not move afterwards. If
the borrower wants another senior rate, junior floor or default window, they create another market
with another manager. The first manager stays where it is and continues servicing exits and claims.

There is no manager owner, general governance role, upgrade path or successor-manager mechanism.
Nothing can rewrite the waterfall, move custody, pause a holder's exit or change the senior claim
after funding.

## Product rules

1. The manager is the market's only admitted lender.
2. Users enter with the market's base asset and never handle market tokens or wrapper shares.
3. Senior receives a priority target, not a guarantee.
4. Junior owns the residual and takes the first loss.
5. Tranche value comes from assets held by the manager; claims come from cash actually recovered.
6. Entry policy may restrict who acquires exposure, but it cannot block burns, withdrawal execution
   or claims.
7. Every economic term is fixed when the manager is initialised.

That gives the facility one fairly useful property: its risk cannot drift because somebody still has
a key.

## Contract shape

```text
senior holders -----------+
                          | base asset
junior holders -----------+
                          v
                    TrancheManager
                          |
                          | sole deposit credential
                          v
                    Wildcat market
                          |
                          | market-token backing
                          v
              canonical Wildcat4626Wrapper
                          |
                          | every wrapper share
                          +--------------------> TrancheManager
```

The wrapper is a custody adapter, not another lender. The manager owns every wrapper share; the
wrapper holds the corresponding market tokens. Outside a deposit, redemption or queueing call, the
manager should hold neither idle market tokens nor standing token approvals.

### `TrancheFactory`

The factory is immutable and ownerless. It knows the canonical ArchController, wrapper factory and
singleton hook template. It deploys fixed manager bytecode with CREATE2 and records one permanent
manager for each market.

The manager address must be known before the market exists, because the sealed singleton provider
names that address as the sole lender. Deployment therefore runs in this order:

1. predict the manager from borrower and salt;
2. create and seal the singleton provider for that address;
3. create the hooks and market;
4. create the market's canonical wrapper;
5. deploy and initialise the manager at the predicted address;
6. verify every binding before recording it.

The factory checks the registered market, current borrower, borrower principal, sentinel, wrapper
factory, canonical wrapper, hook template, hook flags, sealed provider and predicted lender. A
market with a recorded manager cannot receive another one.

### `TrancheManager`

The manager holds custody and accounting. Its one-time parameters are:

- canonical wrapper and derived market/base asset;
- canonical sanctions sentinel;
- fixed senior rate;
- fixed minimum junior ratio;
- fixed default penalty window;
- immutable senior and junior entry gates, if used.

It accepts base assets, deposits them into the market, wraps every market token, mints tranche
shares, burns those shares into async exit requests, queues market withdrawals and allocates the
cash which comes back.

It exposes no arbitrary call, asset rescue destination, upgrade hook, rate setter, deposit pause,
discretionary default or role rotation.

### `TrancheToken`

Each tranche token has one immutable manager. Only that manager may mint or burn it. Ordinary
transfers run the recipient through the class entry policy and both parties through sanctions.

Mint and burn bypass the transfer hook. That is deliberate: entry can fail closed without turning
the same policy into an exit veto.

The token may expose ERC-4626-style valuation views, but it is not a synchronous ERC-4626 vault.
Redemption lives on the manager and follows the Wildcat withdrawal queue.

## Tranche accounting

Everything is denominated in the market's base asset:

```text
V = realised value attributable to the manager
S = min(seniorOwed, V)
J = V - S

S + J = V
```

`seniorOwed` begins with senior principal and accrues at the manager's fixed annual rate while the
facility is active. Junior receives whatever value remains after that claim. If value falls, junior
reaches zero before senior is impaired.

The rate is fixed because the senior liability needs one meaning between checkpoints. Tying it to a
mutable market APR would let a borrower-side market change reprice senior after funding.

Every state-changing accounting path checkpoints before using `seniorOwed`: deposits, redemption
requests, withdrawal execution, recovery synchronisation and the terminal-state check. The final
active interval is accrued before wind-down freezes the claim.

## Capital formation

`minJuniorBips` fixes junior's minimum share of total value:

```text
juniorValue / (seniorValue + juniorValue) >= minJuniorBips / 10,000
```

At a 20% junior floor, 1 unit of junior supports at most 4 units of senior. Once the facility sits on
that floor, another senior deposit and any junior exit both fail. Another 1 unit of junior opens room
for 4 units of senior.

The manager checks the floor on senior entry and junior exit while active. Junior entry always
improves the ratio. Senior exit does not need a floor check.

Deposits which would round to zero shares revert. The first deposit into either class has a minimum
size. All share issuance rounds against the entrant and in favour of the existing pool.

## Value during delinquency

The manager uses the canonical wrapper price rather than an external oracle. While the market is
healthy, it advances a price-per-share mark. During delinquency:

```text
effectivePps = min(livePps, lastHealthyPps)
```

Penalty interest is not booked as profit before it is realised. A downward move still counts, so
the mark cannot hide a loss. Cure reopens recognition of the live value.

The mark is only as fresh as the last manager checkpoint. Capturing the exact healthy-to-delinquent
transition would require a market callback or another protocol-level checkpoint.

Ordinary deposits should close while delinquent. The existing position is valued at the frozen
mark, whereas newly invested base assets are converted at the live wrapper price. Allowing entry
without a separate pricing rule would let `_invest` decide economics as a side effect. A junior
rescue facility can be designed later if a real term sheet calls for one.

## Wind-down

Wind-down is objective and one-way. It begins when either:

```text
market.currentState().isClosed
```

or:

```text
timeDelinquent >= delinquencyGracePeriod + defaultPenaltyWindow
```

Any account may checkpoint the manager and advance it into wind-down once the condition is true.
The final active interval accrues first; future senior accrual then stops. New deposits close, while
redemption requests, withdrawal execution, recovery synchronisation and claims stay live.

There is no discretionary default button. If a facility needs an off-chain party to declare a
legal default, that is a different product term and should not be smuggled into this contract as a
general control role.

## Exit and recovery

An exit follows the market queue:

1. checkpoint value and lifecycle state;
2. calculate the holder's share of its class value;
3. burn tranche shares;
4. redeem enough wrapper shares at the live wrapper price to receive that value in market tokens;
5. queue the market tokens in a Wildcat withdrawal batch;
6. record owner, class, face, expiry and FIFO position;
7. execute the expired batch;
8. allocate observed base assets;
9. pay the recorded owner or sanctions escrow.

The wrapper redemption uses the live price even when tranche valuation is frozen. Sizing it at the
frozen mark would pull the delinquency appreciation which the accounting has excluded.

Settlement is FIFO within each class and senior-first between classes:

```text
faceBefore[id] = class face queued before this request
entitlement = clamp(classCashAllocated - faceBefore[id], 0, requestFace)
claimable = entitlement - alreadyClaimed
```

FIFO matches the underlying batch ordering, keeps every request O(1) and never needs a clawback. It
does mean an earlier request in one class fills before a later request in the same class.

While healthy, junior cash may only be allocated after senior face already queued. During
delinquency or wind-down, junior cash may only be allocated after the full senior obligation,
including senior which has not queued. Without that second rule, junior could leave during a slow
default while senior remained in the manager.

Recovery is balance-derived:

```text
recoveredBaseAsset = baseAsset.balanceOf(manager) + totalClaimedOut
```

Anyone may call `sync()` after a market withdrawal, direct transfer or other cash arrival. Allocation
never depends on one privileged keeper observing the transfer.

## Entry and sanctions

The manager stores an immutable entry-gate address for each class. A zero gate means unrestricted
entry. A facility may require a junior gate while leaving senior open.

The manager checks the receiver on deposit and recipient on ordinary transfer. It does not check
the sender, burn, redemption request or claim. Any mutability inside a gate belongs to that policy
contract and cannot alter tranche economics or exit rights.

Sanctions use the market's registered borrower principal and canonical sentinel. Both parties to an
ordinary transfer are checked. A sanctioned holder may still burn and queue an exit; the eventual
claim keeps its value and queue position but pays the canonical escrow instead of the holder.

## Invariants

The implementation and tests should state these directly:

1. The manager, market and canonical wrapper all resolve to the same registered facility.
2. The sealed singleton provider names the manager as its only lender.
3. The manager owns every wrapper share and holds no idle market tokens outside a custody call.
4. Senior value plus junior value equals realised manager value, apart from explicit rounding dust.
5. Junior reaches zero before senior takes loss.
6. Senior entry and active junior exit cannot breach the minimum junior ratio.
7. Allocated recovery never exceeds observed base assets.
8. A request never receives more than its face or FIFO entitlement.
9. During distress, junior receives no cash while the senior obligation is uncovered.
10. Entry policy and sanctions cannot prevent burns, withdrawal execution or claims.
11. Wind-down cannot be reversed and senior accrual cannot restart.
12. The manager cannot be rebound, replaced or initialised twice.

## Work still open

The economic shape is fixed. The remaining questions are narrower:

- whether exact delinquency marking deserves a protocol callback;
- the final allocation of wrapper, market-token and base-asset dust;
- unique senior and junior token metadata;
- whether either tranche needs an external entry gate for the first facility;
- whether `claimMany` is worth adding;
- whether the request surface should advertise an ERC-7540 interface.

The current Solidity prototype still contains a manager governance address, mutable senior rate,
deposit pause, local junior allowlist and discretionary default path. Those do not belong in this
design and should be removed before the lifecycle work is treated as representative.

The implementation sequence is in
[`TRANCHER_LOGIC_RUNBOOK.md`](TRANCHER_LOGIC_RUNBOOK.md).
