# TrancheManager Implementation Runbook

## Objective

Build a production-shaped prototype in which one `TrancheManager` is the sole economic lender to
one Wildcat market, holds every share of that market's canonical `Wildcat4626Wrapper`, and issues
senior and junior claims over the resulting position.

This is an implementation sequence, not a production-readiness claim. Do not start the accounting
rewrite until the checkpoint decision in Gate 2 is specified well enough to test as an invariant.

## Gate 1 — Pin the integration surface

Pin a V2.5 commit and compile against its interfaces. The implementation relies on:

- the market factory accepting a predicted manager as the singleton lender;
- `market.asset()`, `deposit`, `queueWithdrawal`, `executeWithdrawal` and `registeredWrapper()`;
- the market's canonical wrapper factory;
- `wrapperFactory.createWrapper(market)` and `wrapperForMarket(market)`;
- the wrapper's ERC-4626 `deposit`, `redeem`, `asset` and `totalAssets` behavior;
- the sealed singleton role provider and its market-hook verifier.

Do not duplicate these interfaces from memory. Vendor or import the pinned definitions and add a
fork test that proves selectors and return types against deployed V2.5 contracts.

The singleton workstream must first make the small change described in
[`SINGLETON_WRAPPER_HANDOFF.md`](SINGLETON_WRAPPER_HANDOFF.md): remove the global transfer-disable
requirement while preserving transfer-hook access checks and exempting only the nonzero canonical
registered wrapper from the normal recipient-credential check.

## Gate 2 — Freeze accounting semantics

Resolve these points in a short specification before changing storage:

1. Which exact event or callback checkpoints senior accrual before a market APR change?
2. How is the last healthy wrapper price captured when a quiet market becomes delinquent?
3. Is senior owed a time-accruing liability, a share of realized market yield, or the lesser of the
   two? Define rounding direction at every boundary.
4. When a user exits, which wrapper shares and market-token face enter the Wildcat withdrawal
   queue, and how is over- or under-recovery allocated?
5. Which recovery ordering is contractual: class priority plus FIFO within class, or another rule?
6. What state ends new deposits and junior exits, and can that transition ever be reversed?

Required conservation statement:

```text
manager wrapper value + idle base asset + base asset already paid
  == active tranche value + queued claim value + explicit rounding dust
```

The current sketch uses the current APR over the entire elapsed interval and can retain a stale
healthy-price watermark. Treat both as unresolved behavior, not as defaults.

## Target source layout

```text
src/
  TrancheFactory.sol
  TrancheManager.sol
  TrancheToken.sol
  interfaces/
    IWildcatV25.sol
    ITrancheManager.sol
  libraries/
    WaterfallMath.sol
    TrancheErrors.sol
test/
  unit/
  invariant/
  integration/
  deployment/
```

Keep pure waterfall arithmetic isolated from custody and lifecycle transitions. Prefer custom
errors, named constants and typed interfaces. Avoid arbitrary calls, delegatecall, upgrade slots,
generic token rescue, generic approvals and governance-controlled custody destinations.

## Build order

### 1. Implement deterministic `TrancheFactory`

The target factory is immutable and ownerless. It stores canonical protocol dependencies and uses
CREATE2 to deploy fixed manager runtime code.

Expose:

```solidity
function computeManagerAddress(address deployer, bytes32 salt) external view returns (address);
function deployManager(bytes32 salt, ManagerInit calldata init)
  external returns (address manager);
```

Namespace the CREATE2 salt by `msg.sender`. Address prediction must not depend on the market,
wrapper or tranche parameters because the predicted manager must be supplied while creating the
market, before the wrapper exists. Achieve this with constant constructor code and a factory-only,
one-time `initialize`. Initialization must occur in the deployment transaction; this is not a
proxy and there is no implementation pointer.

`deployManager` must verify before registration:

- the market is registered with the pinned ArchController;
- the wrapper equals both `market.registeredWrapper()` and
  `wrapperFactory.wrapperForMarket(market)`;
- the wrapper's asset is the market;
- the hook/provider pair is the intended sealed singleton construction;
- the provider's sole lender is the newly deployed manager;
- deposit and transfer hooks are enabled and access-required;
- the market does not report global transfers disabled;
- no manager is already registered for the market;
- base asset, borrower and immutable terms agree across all components.

Record one current manager per market and an append-only list. Do not add replacement or migration
until its custody and claim semantics are separately specified.

Recommended factory event:

```solidity
event TrancheManagerDeployed(
  address indexed market,
  address indexed wrapper,
  address indexed manager,
  address senior,
  address junior,
  address deployer,
  bytes32 salt
);
```

### 2. Implement one-time manager initialization

`initialize` must be callable only by the factory and only once. Validate every address before
writing state, deploy the two `TrancheToken` contracts, initialize lifecycle/accounting state, then
close initialization permanently.

Bind at least:

- market, canonical wrapper and base asset;
- borrower, hooks and singleton provider;
- sanctions sentinel and escrow destination or resolver;
- governance and optional default declarer;
- senior economics, minimum junior subordination and default threshold;
- senior and junior token metadata.

Emit the complete immutable/bound configuration once. A useful shape is:

```solidity
event Initialized(
  address indexed market,
  address indexed wrapper,
  address indexed borrower,
  address senior,
  address junior,
  address governance,
  address sentinel,
  uint256 seniorShareBips,
  uint256 minJuniorBips,
  uint256 defaultPenaltyWindow
);
```

### 3. Replace the deposit front door

The target manager accepts only the market's base asset. It must not accept user-supplied market
tokens or wrapper shares.

For each deposit:

1. checkpoint accounting and lifecycle state;
2. reject a zero receiver, zero amount, inactive status, paused deposits or ineligible parties;
3. calculate tranche shares using pre-deposit class values and explicit downward rounding;
4. transfer base assets from the caller to the manager;
5. approve the market for the exact amount and call `market.deposit`;
6. approve the canonical wrapper for the exact market-token amount and call `wrapper.deposit` with
   the manager as receiver;
7. clear any residual approvals where the integrated token behavior makes that necessary;
8. update the senior obligation/subordination state and mint tranche shares;
9. assert or test that the manager holds the new wrapper shares and no unintended idle market
   tokens remain.

Use checks-effects-interactions with a reentrancy guard and balance deltas around external calls.
Never trust nominal inputs when the integrated method returns or transfers an observed amount.

Recommended event:

```solidity
event Deposited(
  address indexed caller,
  address indexed receiver,
  address indexed tranche,
  uint256 baseAssets,
  uint256 marketTokens,
  uint256 wrapperShares,
  uint256 trancheShares
);
```

### 4. Implement async exits as explicit requests

An exit is not an ERC-4626 synchronous withdrawal. The manager must:

1. checkpoint;
2. calculate the holder's class entitlement and required wrapper shares;
3. burn tranche shares before external interactions;
4. redeem wrapper shares to market tokens with the manager as receiver;
5. queue those market tokens in the Wildcat withdrawal batch;
6. append an immutable request containing owner, class, face, queue expiry and FIFO position;
7. later execute the expired market batch permissionlessly;
8. allocate observed base-asset recovery according to the frozen recovery rule;
9. permit permissionless claiming only to the recorded owner or canonical sanctions escrow.

Events should make the lifecycle reconstructible without replaying internal math:

```solidity
event RedemptionRequested(
  uint256 indexed requestId,
  address indexed owner,
  address indexed tranche,
  uint256 trancheShares,
  uint256 wrapperShares,
  uint256 marketTokens,
  uint32 expiry
);
event WithdrawalExecuted(uint32 indexed expiry, uint256 assetsReceived, uint256 cumulativeRecovered);
event RecoveryAllocated(
  uint256 seniorDelta,
  uint256 juniorDelta,
  uint256 seniorTotal,
  uint256 juniorTotal
);
event Claimed(
  uint256 indexed requestId,
  address indexed owner,
  address indexed recipient,
  uint256 assets,
  bool escrowed
);
```

Do not emit a second copy of ERC-20 `Transfer` data. Emit only protocol state that is otherwise
hard to reconstruct.

### 5. Make lifecycle and governance auditable

Represent lifecycle transitions with one event carrying previous state, next state and trigger.
Wind-down/default entry should be monotonic unless a reversal is explicitly part of the terms.

```solidity
event StatusChanged(Status indexed previous, Status indexed current, bytes32 indexed trigger);
event AccountingCheckpoint(
  uint256 timestamp,
  uint256 seniorOwed,
  uint256 wrapperShares,
  uint256 effectiveAssets
);
```

For each mutable setting, use bounded values, a delay where economic impact warrants it, two-step
role rotation, and events containing previous and new values. Governance may pause entry; it must
not block burns, withdrawal execution or claims. Entry restrictions on tranche transfers must
ignore mint and burn and must not create a claim veto.

## Deployment ceremonies

### EOA

An EOA cannot make the three protocol transactions atomic. The intended sequence is still safe
because the only admitted lender is an address with no code until the final transaction:

1. Call `computeManagerAddress(eoa, salt)`.
2. Create the market and singleton hooks with that predicted address as sole lender. Deposit and
   transfer hooks are enabled/access-required; global transfers are not disabled.
3. Call `Wildcat4626WrapperFactory.createWrapper(market)`.
4. Call `TrancheFactory.deployManager(salt, init)`.
5. Run the verifier checklist below before funding or publishing the tranche addresses.

The gap is inert, not partially live: no other address has the deposit credential, the manager is
undeployed, and the wrapper factory is the only party that can register the canonical wrapper.

### Safe

Use a Safe MultiSend delegatecall so the Safe remains `msg.sender` for every nested call:

1. predict the manager using `(safe, salt)`;
2. create the market and singleton hooks for that predicted manager;
3. create and register the canonical wrapper;
4. deploy and initialize the manager;
5. call a read-only verifier that reverts unless all bindings and invariants hold.

The whole ceremony succeeds or reverts atomically. If another smart account or batcher is used,
confirm its call semantics preserve the address used to namespace the salt; do not assume they match
Safe MultiSend.

The wrapper sometimes must be deployed in the same ceremony: specifically when atomic deployment
is required by operational policy or by a downstream verifier. It cannot be constructor input to
the market because the canonical wrapper is registered only after market creation. Predict the
manager, not the wrapper, and resolve the wrapper live during manager initialization.

## Deployment verifier checklist

The final verifier should revert unless every statement is true:

- market is registered and its base asset is expected;
- manager code exists at the predicted address;
- factory registration maps market to manager;
- provider lender equals manager and provider mutation is sealed;
- deposit and transfer hook dispatch/access requirements remain enabled;
- global market transfers are not disabled;
- registered wrapper is nonzero, canonical and bound to the same market;
- manager's wrapper and market match those canonical addresses;
- manager initialization is closed;
- senior and junior tokens point back to the manager and have the expected class flags;
- no other manager is current for the market;
- wrapper supply/backing checks hold at zero state.

After first funding, additionally check:

```text
market scaled supply
  == manager scaled balance + wrapper scaled balance + scaled pending withdrawals
wrapper total supply == wrapper balance of manager
```

## Test matrix

### Unit

- every initialization field and invalid combination;
- CREATE2 prediction for EOA and Safe callers;
- deposit share math, rounding and minimum subordination;
- healthy, delinquent, closed and forced wind-down transitions;
- partial, excess and zero recovery;
- FIFO within each class and senior priority between classes;
- sanctions escrow without amount or queue-position changes;
- every governance bound, delay and two-step transfer.

### Integration

- market creation precedes wrapper creation;
- canonical wrapper registration succeeds when global transfers are not disabled;
- manager-to-wrapper wrapping succeeds;
- wrapper-to-manager unwrapping succeeds through the manager credential;
- transfers to an uncredentialed stranger fail;
- an unregistered or fake wrapper receives no exception;
- EOA ceremony verifies after its final transaction;
- Safe batch is atomic and produces the predicted manager.

### Invariant/stateful

- custody and wrapper-supply identities in `ARCHITECTURE.md`;
- conservation across deposits, transfers, exits, partial recoveries and claims;
- junior absorbs loss first;
- junior cannot escape the subordination floor while active;
- junior receives no distressed recovery while senior remains uncovered;
- claims never exceed recovery or a request's FIFO entitlement;
- no user action can strand wrapper shares after the last tranche share exits;
- no entry policy or governance action can prevent burn and claim.

### Fork

- selectors and hook flags against the pinned V2.5 deployment;
- wrapper factory registration path;
- actual market-token rounding and queue expiry behavior;
- Safe MultiSend call semantics if it is part of the supported deployment path.

## Delta from the current sketch

The current `build/` contracts remain useful test scaffolding, but implementation work must replace:

- an owner-gated, parameter-dependent factory deployment with ownerless deterministic deployment;
- constructor-bound manager state with atomic one-time factory initialization;
- user deposits of wrapper shares with base-asset deposit, market deposit and canonical wrapping;
- string reverts with typed custom errors;
- abbreviated events with the custody and lifecycle events above;
- implicit APR/watermark behavior with the Gate 2 checkpoint specification.

Preserve the existing pure waterfall and lifecycle tests where they still express the frozen
semantics. Delete or rewrite tests that merely encode the sketch's old custody path.
