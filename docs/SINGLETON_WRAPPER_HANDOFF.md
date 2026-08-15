# Singleton Role Provider: Canonical Wrapper Handoff

## Exact request

Make the sealed singleton hook compatible with the canonical V2.5 ERC-4626 wrapper without adding
a new transfer-policy mode.

1. Remove PR #124's requirement that a singleton market have `transfersDisabled == true`.
2. Keep `useOnTransfer` and transfer access checks mandatory.
3. In the existing recipient check, allow the transfer when the recipient is the market's nonzero
   `registeredWrapper()`.
4. For every other recipient, run the existing singleton credential check unchanged.
5. Keep provider mutation sealed and keep the manager as the only credentialed lender.

Conceptually:

```solidity
address wrapper = market.registeredWrapper();
if (wrapper != address(0) && to == wrapper) return;
_requireSingletonCredential(to);
```

Fit this into the repository's actual hook/error conventions; the snippet is not intended as a
drop-in patch.

## Why this is sufficient

The canonical wrapper deposits by moving market tokens from the manager to itself. It therefore
needs to pass the recipient check. On redemption the recipient is the manager, which already has
the sole credential. No separate caller/from/to policy and no `CanonicalWrapperOnly` enum are
needed.

This preserves the existing constraints:

- the transfer hook still runs and remains access-required;
- every ordinary recipient still needs the singleton credential;
- only the canonical wrapper factory can register `market.registeredWrapper()`;
- wrapper registration does not give the wrapper a deposit credential;
- the provider cannot later admit another lender;
- the TrancheManager exposes no arbitrary approval or market-token transfer method.

The wrapper factory currently rejects a market reported as globally transfer-disabled, so merely
special-casing `onTransfer` while retaining that flag is insufficient.

## Creation-order requirement

The market exists before its canonical wrapper. Do not require a wrapper address in the hook
constructor or market deployment inputs. Read `market.registeredWrapper()` live on each transfer
and require it to be nonzero before granting the exception.

EOA ceremony:

1. predict the TrancheManager address from `(EOA, salt)`;
2. deploy market/hooks with the predicted manager as sole lender;
3. call `wrapperFactory.createWrapper(market)`;
4. deploy and initialize the manager;
5. verify all bindings.

Safe ceremony, using MultiSend delegatecall:

1. predict the manager from `(Safe, salt)`;
2. deploy market/hooks;
3. create the canonical wrapper;
4. deploy and initialize the manager;
5. run a reverting verifier as the last batched call.

Sometimes the wrapper must be deployed in the same ceremony: use the Safe batch when atomicity is
an operational requirement. The EOA gap is otherwise inert because the only lender credential
belongs to an undeployed manager. The manager address must be predictable without knowing the
wrapper address.

## Verifier changes

The singleton verifier used by the tranching factory should prove:

- provider lender equals the predicted/deployed manager;
- provider mutation is sealed;
- deposit and transfer hook dispatch/access requirements are enabled;
- the market does **not** report global transfers disabled;
- `market.registeredWrapper()` is nonzero after the wrapper step;
- `wrapperFactory.wrapperForMarket(market) == market.registeredWrapper()`;
- the wrapper is bound to the same market;
- the manager owns all wrapper shares after funding.

The wrapped supply identity is:

```text
market.scaledTotalSupply
  == market.scaledBalanceOf(manager)
   + market.scaledBalanceOf(wrapper)
   + market.scaledPendingWithdrawals
```

The manager balance may be nonzero transiently while wrapping, unwrapping or queueing.

## Required tests

1. A singleton market can be created before its wrapper.
2. The canonical wrapper can be created and registered afterward.
3. Manager-to-wrapper wrapping passes the hook.
4. Wrapper-to-manager redemption passes through the manager's existing credential.
5. A transfer to an uncredentialed stranger still reverts.
6. A fake or merely wrapper-shaped address receives no exception.
7. `registeredWrapper() == address(0)` exempts nobody.
8. Wrapper registration does not permit the wrapper to deposit as a lender.
9. Provider and hook mutations remain impossible.
10. The Safe ceremony succeeds atomically and a failing final verification reverts every step.

## Non-request

Do not introduce a transfer-mode enum, a constructor-supplied wrapper, a mutable wrapper allowlist,
or bespoke checks that hard-code the wrapper as caller and the manager as sender. The canonical
registered-wrapper recipient exception plus the existing credential logic is the intended scope.
