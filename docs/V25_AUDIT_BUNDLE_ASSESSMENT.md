# V2.5 audit-bundle compatibility scope

## Decision

The Pashov cycles identify **no error in code present** at
[`feat/v2.5-events-data-model` @ `5f3caa8`](https://github.com/wildcat-finance/v2-protocol/tree/5f3caa86b4fef7e0391b3af55b84498bfba31e49).
They do not call for a corrective V2.5 patch.

There is a separate audit-scope choice. If the frozen bundle is also meant to cover this trancher,
it must include the already-developed singleton-hook series and withdrawal-expiry callback change
from [`e88e799`](https://github.com/wildcat-finance/v2-protocol/commit/e88e799bedd3108feb5ff45b33dc7b62f865b56c).
If the bundle does not cover the trancher, `5f3caa8` can remain as it is. Absence of those features
is not a fault in that branch.

## Compatibility additions only if the trancher enters the bundle

| Requirement | Trancher dependency | Scope at `5f3caa8` | Consequence for the trancher only |
| --- | --- | --- | --- |
| One sealed lender plus the canonical-wrapper exception | `TrancheOpenTermHooks` inherits `SingletonOpenTermHooks`; the manager is the sealed lender | The singleton provider and hook specialisation are outside this branch | The current trancher has no one-manager admission model against this bundle |
| Exact market-close checkpoint | `TrancheOpenTermHooks` overrides `onCloseMarket`; `TrancheFactory` requires close dispatch and the manager freezes senior accrual in the synchronous callback | The generic hook advertises `useOnCloseMarket: false` and its callback is not virtual; optional close dispatch is outside this branch | The trancher specialisation cannot supply its close callback; without it the manager cannot reconstruct the close timestamp and omits the final senior-accrual interval |
| Withdrawal execution carries its `expiry` | `TrancheOpenTermHooks.onExecuteWithdrawal` passes `expiry` to `TrancheManager.onMarketWithdrawalExecuted` | This callback ABI addition is outside this branch: `IHooks.onExecuteWithdrawal` takes lender, amount, state and data only | A trancher manager cannot know which batch supplied cash when any account calls permissionless execution |
| Exact scaled exit of residual market custody | Manager queues the exact remaining scaled balance at terminalisation | Present: `queueWithdrawalScaled` and `queueFullWithdrawal` are in the branch | No compatibility addition needed; retain this V2.5 queue work |

The branch and `e88e799` are not in the same ancestry. Their merge base is
[`60cfdbc`](https://github.com/wildcat-finance/v2-protocol/commit/60cfdbc56eab4616ae667b2bd71359b27c32e492);
the singleton series, optional close support and expiry change appear only on the `e88e799` side.
This is a branch-composition fact, not an implementation failure in either line.

## Why the expiry is required by this trancher

The market already knows `expiry` at execution: it receives it in `executeWithdrawal(account,
expiry)` and passes it into `_executeWithdrawal`. The frozen branch discards that fact at the hook
boundary. The manager cannot reconstruct it from the paid amount or `MarketState`; several batches
can be executable and amounts are not unique.

The trancher records `faceQueuedByExpiry`, `faceCreditedByExpiry` and
`recoveryObservedByExpiry`. Its hook callback receives the exact expiry before cash moves. That lets
it cap admission against the batch’s outstanding face and the global queue room. Cash without that
authenticated batch identity is deliberately terminal surplus rather than claimable recovery.

That rule came out of the Pashov cycles. The relevant regression coverage is:

- `test_PermissionlessExecutionUsesTheSameRecoveryProvenance`;
- `test_ExecutedBatchCannotFundLaterBatch`;
- `test_UnattributedCashCannotDoubleAdmitAnExecutedBatch`.

Without the expiry argument, the safe alternative is to treat all direct execution proceeds as
unattributed surplus. That prevents cross-batch theft, but it also makes valid permissionless market
execution unable to fund the request that produced it. It is not an acceptable facility behaviour.

## Additions required only for a trancher-inclusive bundle

1. Bring the sealed singleton role-provider and singleton open-term hook specialisation into the
   audit tip, including the canonical-wrapper recipient rule, a virtual `onCloseMarket`,
   `useOnCloseMarket: true` as an optional hook capability, and the associated integration tests.
2. Apply the `e88e799` ABI change throughout the hook hierarchy, mocks and tests: add
   `uint32 expiry` to `IHooks.onExecuteWithdrawal` and pass the already-known expiry from
   `WildcatMarketWithdrawals._executeWithdrawal`.
3. Keep the V2.5 scaled withdrawal queue API. The trancher uses `queueFullWithdrawal` when its last
   tranche shares burn, so it does not leave scaled-balance dust stranded.
4. Re-run V2.5’s hook integration tests and the trancher’s pinned fork tests against the reconciled
   revision. Freeze that exact revision and compiler profile together.

## Things the Pashov cycles do **not** identify as V2.5 errors

- No new protocol-fee rule. V2.5 already calculates protocol fees in `FeeMath`; the facility must
  disclose the market term and divides the resulting net position.
- No change to the underlying sanctions escrow flow. The manager reverts its authenticated callback
  while it is sanctioned, before the market commits execution, then retries after clearance.
- No reconstruction of a continuous delinquency episode. The target counter decays on cure, and
  changing that historical meaning is explicitly out of scope. The manager instead rejects
  zero-delinquency-fee markets because V2.5 only advances `timeDelinquent` when that fee is nonzero.
- No special core transfer-disable rule. The trancher rejects transfer-disabled markets and relies on
  the wrapper exception in the singleton hook path.

## Verification record

The prototype’s current V2.5 pin is `e88e799`. On that pin, the real fork suite passes seven paths:
full deployment, delinquency mark/cure, threshold wind-down, gated entry with unrestricted exit,
sanctioned-holder escrow, manager-sanction retry and terminal full withdrawal. The release suite also
passes 66 conventional/fuzz/fork tests and five stateful properties at 256 runs × 128 calls.

Those results prove the trancher against its pin. They do not test it against `5f3caa8`, because the
necessary features are outside that branch’s scope. A trancher-inclusive audit bundle should include
the named additions and freeze their reconciled revision; a V2.5-only bundle should make no claim to
cover the trancher.
