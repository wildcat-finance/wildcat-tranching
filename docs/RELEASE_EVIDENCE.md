# Prototype release evidence

This is a demonstrable prototype, not a production deployment recommendation. The evidence below
is a repeatable release gate for the exact compiler profile committed in `build/foundry.toml`.

## What the code gate proves

`build/test/ReleaseEvidence.t.sol` refuses a build where any prototype contract exceeds the
EIP-170 runtime limit, or where the factory or manager exceeds the EIP-3860 initcode limit. The
manager is intentionally compiled with one optimizer run: it is 24,561 bytes, leaving 15 bytes
under EIP-170. Changing Solidity, dependencies, optimizer configuration or manager source means
rerunning this gate before describing the artefact as deployable.

The factory does not retain the manager creation code at runtime. At construction it records the
hash of `TrancheManager` creation code bound to that factory address. A deployment supplies those
same bytes once; the factory checks the hash before its small CREATE2 deployer creates and
initialises the manager. The manager address remains predictable before the market and wrapper
exist.

## Required local sequence

From `build/`:

```sh
forge fmt --check
forge clean && forge test --no-match-path test/Invariant.t.sol
FOUNDRY_INVARIANT_RUNS=256 FOUNDRY_INVARIANT_DEPTH=128 forge test --match-path test/Invariant.t.sol
forge test --match-path test/Fork.t.sol -vv
forge test --match-path test/ReleaseEvidence.t.sol -vv
```

The fork tests exercise the pinned V2.5 path, including singleton admission, canonical wrapper
custody, shortfall recovery, class priority, sanctions escrow and manager-sanction retry. The
stateful tests cover custody and recovery accounting across adversarial call sequences. The release
test is intentionally narrow: it checks deployability limits; it does not turn those tests into an
audit or legal opinion.

## Human sign-off still required

Before any production proposal, independently review the compiled artefacts and their hashes, the
factory bindings, the intended market's protocol fee terms, sanctions setup, entry policy and
operational keeper path. Confirm the exact V2.5 revision remains the one tested here. A fresh
external security review is required if the manager, its compiler settings or the upstream market
bundle changes.
