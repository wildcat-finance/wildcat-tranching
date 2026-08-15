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

## Stage 1: remove the control plane

Align `build/src/TrancheManager.sol` with the immutable facility before extending its lifecycle.

### Parameters and state

Keep only one-time economic and policy inputs:

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

The exact gate interface should be selected before implementation. Zero may mean unrestricted; if
junior must always be restricted, reject a zero junior gate during initialisation.

Remove:

- `governance` and `pendingGovernance`;
- `pendingSeniorRateBips`, `seniorRateEta` and `RATE_TIMELOCK`;
- `depositsPaused`;
- the manager-local `juniorAllowed` mapping;
- `defaultDeclarer` and `forcedDefault`;
- every setter, proposal, execution, cancellation, declaration and rotation function attached to
  those fields;
- their events and modifiers.

`seniorRateBips`, `minJuniorBips`, `defaultPenaltyWindow` and gate addresses are written once by the
factory during atomic initialisation and have no setters.

### Lifecycle

`defaultReached()` should depend only on market closure or:

```text
timeDelinquent >= delinquencyGracePeriod + defaultPenaltyWindow
```

`accrue()` remains permissionless. It books the final active interval before moving the manager to
wind-down. No caller chooses whether the transition occurs once the market condition is true.

Deposits are available only when active and healthy. There is no separate pause flag.

### Entry policy

Replace `juniorAllowed` checks with immutable class-gate calls on exposure increases:

- receiver on deposit;
- recipient on ordinary transfer;
- never sender on transfer;
- never mint, burn, request, batch execution or claim.

A reverting gate blocks entry but cannot reach the exit path.

### Tests

Delete tests for manager role rotation, rate proposals, pause and discretionary default. Add tests
which prove:

- no manager function can change the fixed terms;
- the only wind-down conditions are objective market state;
- healthy entry works and delinquent entry fails;
- gate failure blocks acquisition but never exit;
- public checkpointing cannot alter terms or direct assets.

Exit condition: the manager ABI has no general control role or mutable economic function, and the
local suite states that absence directly.

## Stage 2: pin the deployment ceremony

The CREATE2 deployment shape is already close to the target. Keep it small.

### Factory checks

`TrancheFactory.deployTranches` should fail unless:

- the caller is the market's borrower;
- the market is registered with the pinned ArchController;
- no manager is already recorded for the market;
- the supplied wrapper is both market-registered and canonical in the wrapper factory;
- the wrapper points back to the same market;
- the market sentinel matches the manager sentinel;
- the hook instance came from the pinned singleton template;
- deposit and transfer hook dispatch and access checks are enabled;
- global transfers are not disabled;
- provider configuration is sealed;
- the provider has one lender and it is the predicted manager.

Initialisation happens in the deployment transaction. There is no proxy or implementation pointer.

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

## Stage 3: prove the real deposit path

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

Exit condition: one junior and one senior base-asset deposit pass against the real stack, and every
unit of rounding has a named recipient.

## Stage 4: prove the real exit path

Add one complete async exit against the same deployed stack:

1. request a partial senior redemption;
2. confirm tranche shares burn before external calls;
3. confirm wrapper shares fall by the observed amount;
4. confirm the manager queues the market tokens actually received;
5. advance to the batch expiry;
6. fund and execute the batch through the supported market path;
7. call `pokeRecovery` from another account;
8. call `claim` from another account and confirm payment goes to the recorded owner;
9. call `claim` again and receive zero.

Repeat with junior once the senior path works.

Required assertions:

- request face matches observed market tokens, subject to documented rounding;
- `recoveredUSDC == baseAsset.balanceOf(manager) + totalClaimedOut`;
- claimable cash never exceeds request face or recovered cash;
- the request owner and FIFO position never change;
- the manager retains no unintended market-token balance.

Exit condition: deposit, custody, burn, queue, execute, allocate and claim pass as one real-contract
lifecycle.

## Stage 5: exercise delinquency and loss

### Marking

- checkpoint a healthy wrapper mark;
- move live price above the mark and set the market delinquent;
- prove tranche values do not book the upside;
- move live price below the mark and prove the loss is recognised;
- prove both class deposits fail while delinquent;
- cure before wind-down and confirm the live value is recognised again.

### Redemption during delinquency

- redeem at the live wrapper price;
- prove request face equals the holder's frozen class claim;
- prove the unrecognised appreciation remains with the manager;
- vary live/frozen price ratios and wrapper rounding.

### Automatic wind-down

- cross `delinquencyGracePeriod + defaultPenaltyWindow`;
- call `accrue()` from an arbitrary account;
- prove the final active interval is included in `seniorOwedAtDefault`;
- prove future accrual stops;
- repeat with market closure;
- prove deposits stay closed while requests, batch execution, `sync()` and claims remain live.

Exit condition: no account can choose the default outcome, and the transition cannot leak the final
senior accrual interval to junior.

## Stage 6: stress recovery ordering

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
- transfer base assets directly to the manager;
- call `sync()` permissionlessly;
- prove each balance increase is recognised once;
- simulate a forced base-asset balance reduction and prove claims already allocated remain callable.

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

## Stage 7: settle terminal accounting

Write the terminal rule before adding a sweep.

It must cover:

1. both tranche supplies are zero while requests remain unpaid;
2. all requests are paid while wrapper dust remains;
3. direct base assets arrive after the final claim;
4. senior is fully paid and junior residual remains;
5. both classes are impaired and the last conversion rounds down.

Prefer a deterministic final-recipient rule. Any sweep must be limited to a proven surplus and must
not choose an arbitrary destination.

Exit condition: no attributable wrapper share, market token or base asset can be stranded, and no
caller can take value owed to an active request.

## Stage 8: finish entry, sanctions and metadata

### Gates

Pin the entry-gate interface and test zero/nonzero gate behaviour for both classes. The manager
stores the gate address once. Policy changes inside a gate cannot alter the manager's economics or
exit path.

### Sanctions

Test the real sentinel and escrow path using `market.borrowerPrincipal()`:

- borrower wallet rotation does not change the sanctions principal;
- a sanctioned holder can burn and queue an exit;
- value and FIFO position remain unchanged;
- claim payment moves to canonical escrow;
- a manager-level sanction or token blacklist has a written operational response.

### Metadata and interfaces

Replace hard-coded `sr-wmt` and `jr-wmt` before a second facility is presented to users. Derive
names from the market symbol or pass validated immutable metadata through the factory.

Keep ERC-4626 methods explicitly view-only. Decide whether the request surface should advertise
ERC-7540 after the lifecycle is stable. Add `claimMany` only if it earns its extra surface.

Exit condition: on-chain data identifies the facility and entry policy, while no policy call can
veto exit.

## Stage 9: review and release evidence

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
- immutable entry gates and sanctions sentinel;
- test commands and results;
- any remaining conservative marking or terminal-dust limitation.

## Suggested PR sequence

1. **Immutable manager:** delete the control plane and install immutable class gates.
2. **Real deposit lifecycle:** base asset through market and wrapper into tranche shares.
3. **Real exit lifecycle:** burn through queue, recovery allocation and claim.
4. **Delinquency and recovery:** frozen mark, objective wind-down and stateful distress cases.
5. **Terminal accounting:** final request and dust rules.
6. **Entry surface:** gate integration, real sanctions path and unique metadata.

Each PR changes one accounting proposition at a time and carries the test which states it.
