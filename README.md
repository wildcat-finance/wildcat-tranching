# Wildcat tranching prototype

This repository is an implementation sketch for issuing senior and junior claims over one Wildcat
market. The target architecture is deliberately narrow:

```text
senior and junior holders
            |
            v
      TrancheManager
            |
            v
canonical v- ERC-4626 wrapper
            |
            v
singleton-admission Wildcat market
```

`TrancheManager` is the only economic lender. The market's singleton role provider admits the
manager, while the canonical wrapper is the sole exception to the normal recipient-credential
check. Tranche holders never hold the Wildcat market token or the wrapper share.

The contracts under [`build/`](build/) are a runnable prototype, not a deployment candidate. They
cover deterministic manager deployment, singleton and wrapper binding checks, base-asset custody,
the waterfall, async redemption and sanctions handling. They compile against the V2.5 singleton
branch plus the narrow hook-specialisation change in
[`v2-protocol@e88e799`](https://github.com/wildcat-finance/v2-protocol/commit/e88e799),
which is proposed in V2 PR #129 on top of PR #124. `Fork.t.sol` deploys that pinned protocol stack
on mainnet block `25,758,381`, then creates the singleton market and tranching hook, registers the
canonical wrapper, deploys the predicted manager and checks the exact close callback.

## Design rules

1. One `TrancheManager` serves one registered Wildcat market.
2. One live tranche set exists per market; no concurrent managers compete for the same recovery.
3. All custody is measured through the market's canonical `v-` ERC-4626 wrapper.
4. The manager is the only admitted depositor and the only holder of wrapper shares.
5. The transfer hook remains access-required; only the canonical registered wrapper bypasses the
   normal recipient-credential check.
6. Senior is a priority claim, not a guaranteed claim. Junior absorbs loss first.
7. Redemptions follow the Wildcat withdrawal queue. The tranche layer never promises synchronous
   liquidity that the market does not have.
8. Entry policy may reject deposits or incoming transfers, but no policy can block burning tranche
   shares or claiming recovered assets.
9. Deployment is deterministic, verifiable and usable by an EOA or a Safe without changing the
   resulting market invariants.
10. Prototype code makes no audit, production-readiness or legal-compliance claim.

## Repository map

```text
build/src/
  TrancheFactory.sol          deterministic deployment and binding verifier
  TrancheManager.sol          per-market custody, accounting and settlement
  TrancheOpenTermHooks.sol    singleton admission with an exact close checkpoint
  TrancheToken.sol            senior/junior share token
  interfaces/IEnterGate.sol   class-specific acquisition policy
  libraries/WaterfallMath.sol pure waterfall helpers

build/test/
  Tranche.t.sol               behavior and lifecycle tests
  Fuzz.t.sol                  pure waterfall math properties
  Invariant.t.sol             stateful custody and recovery properties
  ViewProps.t.sol             tranche-token value-view properties
  Fork.t.sol                  pinned V2.5 market, wrapper and manager deployment
  Mocks.sol                   local test doubles

docs/
  ARCHITECTURE.md              target topology, trust boundaries and invariants
  IMPLEMENTATION_RUNBOOK.md    build order, interfaces, events, tests and deployment flows
  SINGLETON_WRAPPER_HANDOFF.md handoff for the singleton-role-provider implementation
```

## Run the prototype

```sh
git submodule update --init --recursive
cd build
forge test --no-match-path test/Fork.t.sol
```

The fork tests require an Ethereum RPC endpoint accepted by the test configuration:

```sh
cd build
forge test --match-path test/Fork.t.sol -vv
```

Set `MAINNET_RPC_URL` to override the default endpoint. The fork test is pinned to block
`25,758,381`; it deploys the V2.5 contracts from the pinned submodule rather than relying on a live
V2.5 deployment.

## Current edge

The manager has fixed economics, call-independent senior accrual, objective wind-down, a complete
distress reserve and one immutable entry-gate address per class. A zero gate leaves that class open.
A nonzero gate is consulted only when an account acquires exposure: on deposit and on the receiving
side of an ordinary transfer. It cannot block a burn, withdrawal request, recovery execution or
claim. Recovery from the permissionless market executor is recorded by withdrawal expiry, so an
older batch cannot make a later request claimable.

The local suite covers deposit, exit and recovery accounting. The pinned fork suite now proves the
deployment, hook-wiring and base-asset deposit path. A real-stack queued exit and settlement remain
the next stage. Terminal dust handling and a production settlement policy are deliberately not
included.

## Read before implementing

Start with [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md), then follow
[`docs/IMPLEMENTATION_RUNBOOK.md`](docs/IMPLEMENTATION_RUNBOOK.md). The wrapper-aware singleton
recipient exception is a prerequisite, not an optional polish item; the exact request to the singleton
workstream is isolated in
[`docs/SINGLETON_WRAPPER_HANDOFF.md`](docs/SINGLETON_WRAPPER_HANDOFF.md).
