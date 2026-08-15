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
the waterfall, async redemption and sanctions handling. They compile against
[`v2-protocol@e88e799`](https://github.com/wildcat-finance/v2-protocol/commit/e88e799), the pinned V2.5
revision containing the singleton admission and hook surfaces required by the trancher. `Fork.t.sol`
deploys that stack on mainnet block `25,758,381`, creates the singleton market and tranching hook,
registers the canonical wrapper, deploys the predicted manager, funds both tranches and settles their
queued exit through the market's expiry path.

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
  TRANCHER_LOGIC_REPORT.md     accounting, lifecycle and parameter design
  TRADFI_OUTREACH_PRIMER.md    first-conversation guide for credit and allocator outreach
  bd/README.md                 lender and borrower field kit
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
The factory also rejects a zero V2.5 delinquency fee: that protocol configuration does not advance
the observable delinquency counter used by this facility's objective wind-down rule.

The local suite covers deposit, exit, recovery and terminal accounting. The factory records a
nonzero immutable terminal recipient and rejects the predicted manager itself as that recipient.
When the final tranche shares burn, the facility closes permanently and queues every remaining
wrapper share or market token. Once every request has been claimed and custody and senior reserve
are clear, anyone may settle proven surplus to that term recipient (or its sanctions escrow).

The pinned fork suite proves the
deployment, hook wiring, base-asset entry and a two-step queued settlement: an initial shortfall
puts a later senior request ahead of earlier junior requests, then later recovery settles junior to
the recorded claimant. That shortfall makes the market delinquent at execution and leaves accrued
interest in its batch. A second fork path proves a frozen mark, entry refusal, live-mark refresh after a
delinquency cure, and the objective wind-down threshold.

Tranche identity is derived from the bound market symbol and market address: `sr-<market symbol>-<market id>` and
`jr-<market symbol>-<market id>`. The manager contains no access-policy state beyond immutable gate addresses.
The fork suite proves that a gate can refuse deposit and transfer acquisition but cannot veto an
existing holder's exit. It also runs the real sentinel and escrow path for a sanctioned holder and
the manager-sanction deferral path for an authenticated market withdrawal.

## Read the design

Start with [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the contract topology and invariants,
then read [`docs/TRANCHER_LOGIC_REPORT.md`](docs/TRANCHER_LOGIC_REPORT.md) for the accounting and
lifecycle. The lender and borrower material starts at [`docs/bd/README.md`](docs/bd/README.md).
