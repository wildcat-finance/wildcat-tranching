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
the waterfall, async redemption and sanctions handling. The protocol interfaces are still local
mirrors, and the fork test is read-only until a V2.5 market using PR #124 is deployed.

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
  TrancheToken.sol            senior/junior share token
  libraries/WaterfallMath.sol pure waterfall helpers

build/test/
  Tranche.t.sol               behavior and lifecycle tests
  Fuzz.t.sol                  pure waterfall math properties
  Invariant.t.sol             stateful custody and recovery properties
  ViewProps.t.sol             tranche-token value-view properties
  Fork.t.sol                  optional mainnet-fork ABI checks
  Mocks.sol                   local test doubles

docs/
  ARCHITECTURE.md              target topology, trust boundaries and invariants
  IMPLEMENTATION_RUNBOOK.md    build order, interfaces, events, tests and deployment flows
  SINGLETON_WRAPPER_HANDOFF.md handoff for the singleton-role-provider implementation
```

## Run the prototype

```sh
cd build
forge test --no-match-path test/Fork.t.sol
```

The fork tests require an Ethereum RPC endpoint accepted by the test configuration:

```sh
cd build
forge test --match-path test/Fork.t.sol -vv
```

## Read before implementing

Start with [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md), then follow
[`docs/IMPLEMENTATION_RUNBOOK.md`](docs/IMPLEMENTATION_RUNBOOK.md). The wrapper-aware singleton
recipient exception is a prerequisite, not an optional polish item; the exact request to the singleton
workstream is isolated in
[`docs/SINGLETON_WRAPPER_HANDOFF.md`](docs/SINGLETON_WRAPPER_HANDOFF.md).
