# TrancheManager Implementation Runbook

## Objective

Build the facility defined in [`TRANCHER_LOGIC_REPORT.md`](TRANCHER_LOGIC_REPORT.md): one immutable
manager for one singleton Wildcat market, with fixed economics and no manager control plane.

The first useful prototype is not another deployment proof. It is a real base-asset deposit,
wrapper custody cycle, queued exit and claim with the waterfall intact throughout.

## Rules for the build

1. One market receives one manager for its lifetime.
2. All economic parameters are fixed during one-time initialisation.
3. The manager accepts only the market's base asset.
4. The manager holds every canonical wrapper share.
5. Recovery is senior-first between classes and FIFO within each class.
6. No entry or policy call may block burns, batch execution or claims.
7. No arbitrary call, rescue destination, upgrade hook or privileged custody path is added.
8. Every accounting change lands with the property or scenario test which justifies it.
9. The protocol fee remains a market-level claim; the manager does not recreate or net it.

## Stage 1: immutable manager

`build/src/TrancheManager.sol` now matches the fixed-term facility. This is the base for the later
lifecycle stages.

### Parameters and state

The one-time economic and policy inputs are:

```solidity
struct Params {
    address underlyingVault;
    address sentinel;
    address seniorGate;
    address juniorGate;
    uint256 seniorRateBips;
    uint256 minJuniorBips;
    uint256 defaultPenaltyWindow;
}
```

`IEnterGate.canIncreaseCredit(account)` is the class policy. A zero gate means open entry. A nonzero
gate must contain code. `seniorRateBips`, `minJuniorBips`, `defaultPenaltyWindow` and both gate
addresses are written by the factory during atomic initialisation and have no setters.

### Lifecycle

`defaultReached()` depends only on market closure or:

```text
timeDelinquent >= delinquencyGracePeriod + defaultPenaltyWindow
```

`accrue()` remains permissionless. It books the final active interval before moving the manager to
wind-down. No caller chooses whether the transition occurs once the market condition is true.

Deposits are available only when active and healthy. There is no separate pause flag.

### Entry policy

The manager calls the relevant immutable class gate only on exposure increases:

- receiver on deposit;
- recipient on ordinary transfer;
- never sender on transfer;
- never mint, burn, request, batch execution or claim.

A reverting gate blocks entry but cannot reach the exit path.

### Tests

The local suite proves:

- no manager function can change the fixed terms;
- the only wind-down conditions are objective market state;
- healthy entry works and delinquent entry fails;
- gate failure blocks acquisition but never exit;
- public checkpointing cannot alter terms or direct assets.

Stage status: complete. The manager ABI has no general control role or mutable economic function.
The suite covers open, denying and reverting gates; delinquent deposit refusal; objective closure;
and exit after gate access is revoked.

## Stage 2: accounting independent of call timing

The manager now produces the same class entitlement for the same market history regardless of who
calls a permissionless checkpoint, or how often.

### Senior accrual

Senior interest is simple interest on outstanding principal. The manager carries the fractional
numerator between calls, so splitting an interval into many checkpoints does not discard interest
or introduce call-dependent compounding.

Accrual stops at the objective market-close instant. `TrancheOpenTermHooks` calls the immutable
manager during `closeMarket`, before V2.5 can lose the original close timestamp to a later state
write. The callback also passes the pre-close delinquency counter, so a threshold already visible at
closure takes precedence. For ordinary delinquency wind-down, the manager derives a cut-off from:

```text
delinquencyGracePeriod + defaultPenaltyWindow
```

V2.5's counter decays during cure; it is not a permanent record of a prior continuous delinquency
period. The facility deliberately follows the current counter exposed by the market. Reconstructing
a historical crossing after cure was considered separately and is outside this prototype. Closure
is checkpointed synchronously by the pinned hook.

### Split senior ledger

During distress, cumulative recovery must cover both senior components before junior receives cash:

```text
cumulativeSeniorPriority = seniorWmtQueued + seniorOwed
```

Queued senior face includes amounts already allocated or claimed because `recoveredUSDC` is also
cumulative. Healthy allocation continues to reserve only senior face already queued.

Each recovery delta is admitted only against obligations which exist when the cash arrives. Recovery
against queued face is allocatable. The pinned execution hook records every market withdrawal with
its execution-time state and expiry, including one called directly through the permissionless market
method. It admits that receipt only against face recorded for the same expiry; its excess can be
tagged against live senior owed but cannot fund a later batch. A generic late `sync()` records all
unexplained balance changes as surplus and never makes queue face claimable. The tagged reserve may migrate only into senior face queued during
distress. Cure, or an impaired exit which extinguishes more debt than it queues, retires the unused
amount to `recoverySurplus`.

If the manager itself is sanctioned, market execution reverts before the market consumes the batch
into sanctions escrow. Escrow release has no batch expiry, so the batch must remain pending until
the manager clears sanctions and can receive its authenticated recovery directly.

### Exit units and empty classes

The healthy checkpoint is an aggregate asset mark, not a frozen wrapper price. An exit converts the
holder's class entitlement down to whole wrapper shares. Its request face is the floor-normalised
value of those shares. Wrapper redemption and the market queue then move the same scaled units, and
the aggregate mark falls by that backed face. If the live wrapper price is above the delinquent
mark, unrecognised appreciation stays wrapped and outside book value until cure. Splitting an exit
cannot queue more than the marked class value or borrow backing from a later FIFO request.

The first moment both tranche supplies reach zero, the facility closes permanently. The factory
has already fixed a nonzero `terminalRecipient` for that facility and rejects the manager address
as a recipient. The final burn queues every wrapper share and market token left in custody. Its
receipt has no request face, so it reaches `recoverySurplus`; it cannot be relabelled as backing for
another capital cycle because deposits are closed forever.

### Tests

Prove:

- one annual checkpoint and many smaller checkpoints produce the same senior entitlement;
- fractional senior accrual survives repeated calls;
- a delayed call stops at closure or delinquency wind-down rather than call time;
- partial senior exit plus distress never releases junior cash before queued and live senior are
  both covered;
- one-shot and partitioned exits never exceed the marked class value, including at small decimals;
- recovery above existing obligations cannot be claimed by a later request;
- a junior request cannot substitute for the live senior debt which admitted an earlier reserve;
- zero supply plus residual class value cannot be captured by a new depositor.
- a final burn queues residual wrapper custody, leaves no live market-token balance and cannot
  redirect terminal surplus to the final holder or settlement caller.

Stage status: complete under the current-counter delinquency semantics above. Unit, fuzz and fork
tests cover partition-independent accrual, fractional carry, exact closure, the configured
delinquency derivation, complete senior distress reserve, partition-independent request face and
zero-supply residual refusal. Five stateful properties each run 32,768 calls without a revert.

## Stage 3: pin the deployment ceremony

The CREATE2 deployment shape is already close to the target. Keep it small.

### Factory checks

`TrancheFactory.deployTranches` should fail unless:

- the caller is the market's borrower;
- the market is registered with the pinned ArchController;
- the market asset uses at least six decimals;
- no manager is already recorded for the market;
- the supplied wrapper is both market-registered and canonical in the wrapper factory;
- the wrapper points back to the same market;
- the market sentinel matches the manager sentinel;
- the hook instance came from the pinned singleton template;
- deposit, transfer and close hook dispatch are enabled, with deposit and transfer access checks;
- global transfers are not disabled;
- provider configuration is sealed;
- the provider has one lender and it is the predicted manager.
- the submitted manager creation code hashes to the immutable `managerInitCodeHash`.

Initialisation happens in the deployment transaction. There is no proxy or implementation pointer.
The caller supplies the compiled manager creation code only for that transaction. The factory has
already committed its exact hash, so the generic CREATE2 deployer cannot be used to substitute a
different manager runtime.
The deployment verifier should also record the market's current `protocolFeeBips`, fee recipient and
maximum fee permitted by the pinned hooks factory. These are disclosed protocol terms, not manager
initialisation parameters.

### EOA ceremony

1. Predict the manager from borrower and salt.
2. Create the singleton provider, hooks and market for that address.
3. Create the canonical wrapper.
4. Deploy and initialise the manager.
5. Run the binding verifier before funding.

The intermediate state is inert: the sole lender address has no code until the final call.

### Safe ceremony

Use a Safe batch which preserves the Safe as `msg.sender`:

1. predict the manager;
2. create provider, hooks and market;
3. create the wrapper;
4. deploy and initialise the manager;
5. finish with a reverting verifier.

The whole batch either creates a valid facility or creates nothing.

Exit condition: EOA and Safe deployment tests produce the predicted address and prove every binding.
The factory permanently rejects a second manager for the same market.

## Stage 4: prove the real deposit path

Extend `build/test/Fork.t.sol` against the pinned V2.5 contracts.

1. Complete the deployment ceremony.
2. Satisfy the junior entry gate and fund junior first.
3. Deposit junior base assets through `depositJunior`.
4. Deposit senior base assets up to the subordination floor.
5. Check the observed balances and approvals after each call.

Required assertions:

```text
baseAsset.balanceOf(manager) == 0
market.balanceOf(manager) == 0
wrapper.balanceOf(manager) == wrapper.totalSupply()
seniorValue + juniorValue == realisedValue
```

Use scaled market-token accounting for the full custody identity if normalised balances can round.

The manager should:

1. checkpoint;
2. validate active/healthy state, sanctions, gate and receiver;
3. calculate class value and supply before entry;
4. transfer base assets from the caller;
5. approve the market for the exact amount;
6. observe market tokens received;
7. approve the canonical wrapper for the exact amount;
8. observe wrapper shares received;
9. clear approvals;
10. calculate tranche shares from observed value;
11. apply the senior floor check and mint.

Do not let nominal input stand in for an observed external-call result.

### Rounding cases

Test:

- the first deposit at the market's actual decimals;
- a deposit which mints one tranche share;
- a deposit which would mint zero;
- repeated small deposits;
- wrapper rounding in both directions;
- direct wrapper-share donation to the manager;
- no residual market tokens or approvals after success;
- full transaction rollback when a post-investment check fails.

Stage status: complete. The pinned stack accepts junior then senior base-asset deposits through the
manager, keeps custody entirely in the canonical wrapper, clears transient approvals and conserves
the waterfall value.

## Stage 5: prove the real exit path

The pinned fork now runs a bounded delinquent partial-recovery async path against the same deployed
stack:

1. burn a capped junior slice, then the senior position, then the remaining junior position into one
   shared market expiry;
2. record exact class faces and prove neither request is claimable before recovery;
3. borrow 100 base assets before expiry, then prove the market exposes only 300 assets from the
   aggregate withdrawal to the manager;
4. execute through `pokeRecovery`, which reaches the pinned withdrawal-execution hook;
5. prove senior allocation fills before junior allocation;
6. claim the senior request through an unrelated keeper and prove the recorded holder receives the
   base asset;
7. repay the final 100 assets, execute the remaining batch payment, and claim junior through the
   keeper, leaving none in the manager.

Required assertions:

- exact senior and junior request face follows their backing;
- both class shares burn before the market batch is executable;
- no request is claimable before the market callback records recovery;
- senior is paid before junior from the shared receipt;
- claims return the complete settled balance to their recorded owner;
- the manager retains no base asset after both claims.

Stage status: complete for one bounded delinquent shortfall path. `Fork.t.sol` covers deposit,
custody, burn, queue, partial execution, senior-first allocation ahead of an earlier junior request,
later recovery and claim as one real-contract lifecycle. It intentionally leaves accrued market
interest queued after all tranche face settles. Broader delinquency and sanctions cases remain
separate hardening work.

## Stage 6: exercise delinquency and loss

### Marking

- checkpoint healthy aggregate wrapper value;
- move live price above the mark and set the market delinquent;
- prove tranche values do not book the upside;
- move live price below the mark and prove the loss is recognised;
- prove both class deposits fail while delinquent;
- cure before wind-down and confirm the live value is recognised again.

### Redemption during delinquency

- redeem at the live wrapper price;
- prove request face does not exceed the holder's frozen class claim;
- prove the aggregate mark falls by the backed request face;
- prove unrecognised appreciation remains wrapped and outside book value until cure;
- compare one-shot and partitioned exits;
- vary live/frozen price ratios and wrapper rounding.

### Automatic wind-down

- cross `delinquencyGracePeriod + defaultPenaltyWindow`;
- call `accrue()` from an arbitrary account;
- prove the final active interval is included in `seniorOwedAtDefault`;
- prove future accrual stops;
- repeat with market closure;
- prove deposits stay closed while requests, batch execution, `sync()` and claims remain live.

Stage status: the pinned fork now proves frozen aggregate marking, exclusion of live upside, entry
refusal, cure recognition, the fixed wind-down threshold and stopped senior accrual. It does not
reconstruct a past continuous delinquency interval. V2.5 maintains debt-based market-token value:
the local wrapper-price tests, not the pinned market test, supply the controllable loss vector. The
threshold fork explicitly cures its market afterwards and proves the manager remains in wind-down.

Exit condition: no account can choose the default outcome, and the transition cannot leak the final
senior accrual interval to junior.

## Stage 7: stress recovery ordering

Exercise many requests and recoveries rather than one friendly batch.

### Healthy shortfall

- interleave senior and junior requests across several batches;
- recover less than total face;
- prove senior fills before junior;
- prove FIFO within each class;
- prove a late request cannot claim cash paid to an earlier request.

### Distress reserve

- leave part of senior unqueued;
- queue junior and recover cash during delinquency;
- prove junior allocation cannot rise until the full senior obligation is covered;
- queue senior after cash arrives and prove reserved cash releases to it;
- underfund wind-down recovery and repeat.

### Cash arriving outside `pokeRecovery`

- execute the manager's market withdrawal directly;
- execute an older batch only after a later batch exists and prove the later request remains
  unclaimable until its own batch recovers;
- transfer base assets directly to the manager;
- call `sync()` permissionlessly;
- prove each balance increase is recognised once;
- simulate a forced base-asset balance reduction and prove claims already allocated remain callable.

### Protocol fee

Run the recovery scenarios with zero fee, the deployment fee and the maximum fee permitted by the
pinned hooks factory.

- prove lender base interest still enters the market-token scale factor in full;
- prove the protocol fee accrues as a separate market liability on base interest only;
- prove accrued fees count towards required liquidity and are reserved before an unprocessed manager
  withdrawal;
- prove assets already processed into unclaimed withdrawals are not taken for later fee collection;
- change `protocolFeeBips` through the authorised hooks-factory path and prove no manager term or
  tranche balance changes directly;
- create a fee-driven recovery shortfall and prove junior absorbs it before senior;
- prove the manager never charges, collects or allocates a second protocol fee.

The manager waterfall should only see base assets actually recovered. Do not subtract the fee from
`seniorOwed`, wrapper value or tranche share issuance.

### Stateful properties

The handler should vary healthy entry, wrapper price, delinquency, cure, closure, time, requests,
partial recoveries, direct cash arrival and claims.

```text
seniorValue + juniorValue == realisedValue
juniorValue > 0 => seniorValue == min(seniorOwed, realisedValue)
seniorCashAllocated + juniorCashAllocated <= recoveredUSDC
claimed(id) + claimable(id) <= requestFace(id)
sum of request claims and claimable cash <= recoveredUSDC
distress and senior uncovered => juniorCashAllocated does not increase
wrapper.balanceOf(manager) == wrapper.totalSupply()
market.balanceOf(manager) == 0 outside an executing custody transition
```

Exit condition: unit and fuzz tests plus `TrancheInvariantTest` cover live-price redemption,
balance-derived recovery, late-request ordering, full senior distress reserve and accrual before
wind-down.

## Stage 8: settle terminal accounting

The terminal recipient is a facility term supplied to `TrancheFactory.deployTranches`, not a prize
for whichever holder burns their last wei latest. It is immutable, nonzero, and cannot be the
predicted manager address.

When both supplies first reach zero, `terminalised` closes deposits for good. The request that
caused it queues its own backed face, then the manager redeems and queues any residual wrapper or
market-token custody with `queueFullWithdrawal()`, which consumes its exact scaled market balance.
The latter has no request face and is therefore terminal surplus when the market batch executes. A
direct base-asset transfer remains terminal surplus for the same reason.

`pendingRequests` is incremented once per request and decremented only on its final claim. This
makes the final check constant-cost even if holders created many small requests. Anyone can call
`settleTerminalSurplus()` only after supplies are zero, custody is empty, the live senior reserve is
zero and `pendingRequests` is zero. It pays the immutable recipient, or that recipient's sanctions
escrow, and cannot touch an outstanding queue entitlement.

Exit condition: no attributable wrapper share, market token or base asset can be stranded, and no
holder, keeper or later depositor can choose the recipient of terminal value.

## Stage 9: finish entry, sanctions and metadata

### Gates

The manager stores one immutable gate address for each class. A zero address leaves that class
open. A nonzero gate controls deposits and transfer recipients only; policy changes inside the gate
cannot alter the manager's economics or exit path. The pinned fork proves a gate can reject both a
deposit and a transfer, then shows an existing holder can still create a senior exit after the gate
is turned off.

### Sanctions

The pinned suite uses the real sentinel and escrow contracts with `market.borrowerPrincipal()`:

- the local suite separately proves borrower wallet rotation does not change the sanctions principal;
- a sanctioned holder can burn and queue an exit;
- value and FIFO position remain unchanged;
- claim payment moves to canonical escrow;
- a manager-level sanction or token blacklist has a written operational response.

### Metadata and interfaces

The manager derives immutable names and symbols from `market.symbol()` plus the bound market
address: `Wildcat Senior Tranche <market symbol> <market id>`, `sr-<market symbol>-<market id>`,
`Wildcat Junior Tranche <market symbol> <market id>` and `jr-<market symbol>-<market id>`. The
fork asserts the resulting identifiers on a real V2.5 market.

Keep ERC-4626 methods explicitly view-only. Decide whether the request surface should advertise
ERC-7540 after the lifecycle is stable. Add `claimMany` only if it earns its extra surface.

Exit condition: complete. On-chain data identifies the facility and entry policy, while no policy
call can veto exit.

## Stage 10: review and release evidence

Run, in order:

1. formatter and compiler with the pinned toolchain;
2. local unit tests;
3. fuzz and stateful suites with recorded run counts;
4. pinned V2.5 deployment and lifecycle fork tests;
5. storage, selector and bytecode-size checks;
6. adversarial review of the final source;
7. separate human review before any production-readiness claim.

Release evidence should name:

- exact `v2-protocol` and singleton-hook revisions;
- deployment addresses and CREATE2 inputs;
- fixed senior rate, junior floor and default window;
- protocol fee at deployment, its permitted bound, fee recipient and update authority;
- immutable entry gates and sanctions sentinel;
- immutable terminal recipient and its terminalisation rule;
- test commands and results;
- any remaining conservative marking limitation.

## Suggested PR sequence

1. **Immutable manager:** delete the control plane and install immutable class gates.
2. **Accounting determinism:** accrual timing, complete distress reserve, request units and
   zero-supply residual guard.
3. **Real deposit lifecycle:** base asset through market and wrapper into tranche shares.
4. **Real exit lifecycle:** burn through queue, recovery allocation and claim.
5. **Delinquency and recovery:** frozen mark, objective wind-down and stateful distress cases.
6. **Terminal accounting:** immutable recipient, final request and residual-custody settlement.
7. **Entry surface:** gate integration, real sanctions path and unique metadata.

Each PR changes one accounting proposition at a time and carries the test which states it.
