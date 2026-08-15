# TrancheManager Logic Runbook

## Objective

Turn the deterministic singleton deployment into a working end-to-end tranching prototype without
changing the waterfall by accident.

[`TRANCHER_LOGIC_REPORT.md`](TRANCHER_LOGIC_REPORT.md) defines the design behind this sequence.

## Working rules

1. Keep one manager per market and one canonical wrapper per manager.
2. Keep the base asset as the only user deposit asset.
3. Keep senior-first recovery between classes and FIFO within each class.
4. Do not add an upgrade path, arbitrary call, asset rescue destination or governance-controlled
   custody movement.
5. Treat every change to valuation, `seniorOwed`, queue face or recovered cash as an accounting
   change, even when the code diff looks small.
6. Run the local suite after each accounting commit and the pinned integration suite after each
   protocol-facing commit.

## Stage 0: freeze the prototype terms

Write a short decision record before changing manager accounting. It should answer:

| Decision | Proposed prototype answer |
|---|---|
| Senior return | Fixed `seniorRateBips`, with checkpoint-before-change and the existing 2-day delay. |
| User deposit asset | Base asset only. |
| Ordinary deposits while delinquent | Revert for both classes. A junior rescue deposit, if wanted, is a separate later design. |
| Minimum junior ratio | Immutable per manager and bounded as it is now. |
| Recovery ordering | Senior-first between classes, FIFO within each class. |
| Default | Closed market, grace plus penalty window, or authorised declaration; one-way wind-down. |
| Manager replacement | None in the lifecycle prototype. Supersession needs its own specification. |
| Governance recovery | None in the lifecycle prototype. |
| Terminal dust | Decide before deployment; test in Stage 4. |

Exit condition: each answer is either accepted or replaced by another explicit answer. No code
should infer one from an unstated assumption.

## Stage 1: prove the real lifecycle

The deployment-only fork test is already present. Extend `build/test/Fork.t.sol` with one complete
path against the same pinned V2.5 stack.

### Deposit path

1. Predict the manager address.
2. Deploy the singleton provider, hooks and market with the predicted manager as the sole lender.
3. Create and register the canonical wrapper.
4. Deploy and initialise the manager through `TrancheFactory`.
5. Allow one junior account and fund junior first.
6. Deposit junior base assets through `TrancheManager.depositJunior`.
7. Deposit senior base assets through `depositSenior` up to the chosen subordination floor.
8. Check balances and approvals after each deposit.

Required assertions:

```text
baseAsset.balanceOf(manager) == 0
market.balanceOf(manager) == 0
wrapper.balanceOf(manager) == wrapper.totalSupply()
market.balanceOf(wrapper) + market.scaledPendingWithdrawals() accounts for manager custody
seniorValue + juniorValue == realisedValue
```

Use the real contract getters where their units differ from the sketch above. The assertion should
compare scaled amounts if normalized market-token balances can round.

### Exit path

1. Request a partial senior redemption.
2. Confirm tranche shares burn before the request is queued.
3. Confirm wrapper shares fall and the manager queues the market tokens actually received.
4. Advance to the real batch expiry.
5. Fund or close the batch using the pinned market's supported path.
6. Call `pokeRecovery` from an account other than the request owner.
7. Call `claim` from another account and confirm payment still goes to the recorded owner.
8. Repeat with a junior request after the senior path works.

Required assertions:

- the request face matches observed market tokens, subject to the wrapper's documented rounding;
- `recoveredUSDC == baseAsset.balanceOf(manager) + totalClaimedOut`;
- claimable cash never exceeds the request face or recovered cash;
- no wrapper or market tokens remain in an unintended account;
- a second claim pays zero.

Exit condition: one base-asset deposit and one async exit pass against the pinned real stack. Keep
the deployment proof as a separate test so a lifecycle failure is easy to locate.

## Stage 2: lock the base-asset accounting

The manager invests base assets before minting tranche shares. Its accounting must be tested against
the wrapper shares actually received rather than inferred from nominal input.

### Delinquent-entry rule

If Stage 0 adopts the proposed answer, add an explicit delinquency check in `_deposit` after
`accrue()` and before moving assets. Test:

- healthy senior and junior deposits still work;
- both revert while `market.currentState().isDelinquent` is true;
- cure reopens deposits if the manager has not entered wind-down;
- `depositsPaused` and sanctions retain their current behaviour;
- wind-down remains closed regardless of cure.

If deposits are instead allowed during delinquency, specify and test the price used for:

- value credited to the entrant;
- shares minted;
- senior obligation added;
- post-deposit subordination;
- recognition of live penalty appreciation already embedded in the wrapper price.

Do not use `_invest`'s return value as the specification.

### Rounding and custody

Add differential tests around the wrapper's real `previewDeposit`, `deposit`, `previewRedeem` and
`redeem` behaviour. Cover:

- minimum initial deposit at the market's actual decimals;
- deposits which mint one share and deposits which round to zero;
- a full senior or junior exit;
- repeated small entries and exits;
- a direct wrapper-share donation to the manager;
- zero idle market tokens and zero residual approvals after normal calls.

Exit condition: the tests state how every observed amount is converted and who receives each unit
of rounding. There is no path where nominal input is treated as observed output.

## Stage 3: exercise the loss and recovery states

Build scenario tests around the state transitions, not individual functions.

### Healthy shortfall

- queue senior and junior requests in more than one batch;
- recover less than total queued face;
- prove senior fills before junior;
- prove FIFO within each class;
- call `sync()` after executing the market withdrawal directly, without `pokeRecovery`;
- transfer base assets directly to the manager and prove `sync()` accounts for them once.

### Delinquency

- checkpoint a healthy mark, then move the live wrapper price above it and mark the market
  delinquent;
- prove tranche values do not book the upside;
- redeem at the live wrapper price and prove the request face equals the frozen class claim rather
  than the live appreciation;
- prove junior allocation remains behind the full `seniorOwed`, including senior which has not
  queued;
- cure before default and confirm the stated recognition rule.

### Wind-down

- cross `delinquencyGracePeriod + defaultPenaltyWindow`;
- prove the final active accrual is booked before `seniorOwedAtDefault` is stored;
- prove future accrual stops;
- repeat through `declareDefault` and market closure;
- prove deposits remain closed while redemption, execution, `sync()` and claims remain callable;
- underfund recovery and prove junior cannot receive cash before senior is covered.

### Stateful properties

Broaden the stateful handler beyond happy-path actions. It should vary delinquency, cure, closure,
default declaration, wrapper price, deposits, requests, recoveries, direct cash arrival and claims.

Properties:

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
balance-derived recovery, late request ordering and accrual before wind-down.

## Stage 4: settle terminal accounting

Define terminal state using all four balances:

- senior tranche supply;
- junior tranche supply;
- outstanding request face and unpaid entitlement;
- manager-held wrapper shares and base assets.

The rule must handle at least:

1. both tranche supplies are zero but requests remain unpaid;
2. all requests are paid but wrapper dust remains;
3. direct base assets arrive after the final claim;
4. senior is fully paid and only junior residual remains;
5. both classes are impaired and the final conversion rounds down.

Prefer a deterministic final-recipient rule over a governance sweep. If a sweep is unavoidable, it
must be limited to a proven surplus and must not choose an arbitrary destination.

Exit condition: the final holder can leave no attributable value stranded, and no caller can sweep
cash or wrapper shares owed to a request.

## Stage 5: finish the entry and token surface

### Entry policy

Decide whether the manager-local `juniorAllowed` map is enough for the first facility. If policy
must be shared with other products, replace it with immutable gate addresses and check only exposure
increases:

- receiver on deposit;
- recipient on ordinary transfer;
- never sender on transfer;
- never burn, request, execution or claim.

Keep a zero senior gate as unrestricted if that is the chosen commercial policy. Decide whether
junior may ever have a zero gate.

### Sanctions

Test the real sentinel and escrow call shape using `market.borrowerPrincipal()`:

- borrower wallet rotation does not change the principal used for sanctions;
- a sanctioned holder can request an exit;
- claim value and queue position are unchanged;
- only the recipient changes to canonical escrow;
- a manager-level sanction or token-level blacklist has a written operational response.

### Token metadata and interface claims

Replace hard-coded `sr-wmt` and `jr-wmt` before more than one manager is user-facing. Derive names
from the market symbol or pass validated immutable metadata through the factory.

Keep the ERC-4626 methods explicitly view-only. Redemption is asynchronous and should not be
presented as a synchronous ERC-4626 vault. Decide whether an ERC-7540 interface is useful after the
request lifecycle is stable.

Exit condition: a holder can determine the tranche, underlying market, manager and entry policy
from on-chain data, and no policy contract can veto exit.

## Stage 6: specify replacement and governance operations

This stage is separate from the lifecycle prototype because it changes who can create a successor
and when.

### Supersession

Specify a factory transition with these properties:

- never two active managers for one market;
- replacement only when the incumbent manager is in wind-down or both tranche supplies are zero;
- requests and claims on the retired manager remain callable forever;
- `managerForMarket` points to the current manager while `allManagers` remains append-only;
- a request existing after both tranche supplies burn does not block claims on the retired manager;
- the successor receives a fresh singleton binding, or the protocol supplies a safe way to rotate
  the sealed binding.

A sealed singleton provider names one lender, so replacement may require a new market rather than a
second manager for the same market. Resolve this with the V2.5 hook design before writing factory
code.

### Governance

Retain two-step governance rotation and the existing pending-rate cancellation. Decide whether
`defaultDeclarer` can be cleared to zero. Record who holds the irreversible default power in the
facility terms.

If borrower recovery is required, specify the delay, incumbent veto and monitoring before adding
it. Test takeover attempts as well as lost-key recovery.

Exit condition: every governance operation has an event, a bound or delay where appropriate, and no
effect on custody or exit availability.

## Stage 7: review and release evidence

Run, in order:

1. formatter and compiler with the pinned toolchain;
2. local unit tests;
3. fuzz and invariant suites with recorded run counts;
4. the pinned V2.5 deployment and lifecycle fork tests;
5. storage, selector and bytecode-size checks;
6. an adversarial review of the final source;
7. a separate human review before any claim of production readiness.

Review the final CREATE2 factory, singleton validation and base-asset deposit path after Stages 1
through 6 which are in scope for the intended deployment.

Release evidence should include:

- the exact `v2-protocol` revision;
- the exact singleton-hook revision or merged PR;
- deployment addresses and CREATE2 inputs;
- configured rate, junior floor, default window, governance and declarer;
- the entry policy and legal acceptance path;
- test commands and results;
- unresolved limitations, including any conservative marking and terminal-dust behaviour.

## Suggested PR sequence

1. **Real-stack lifecycle:** deposit, queue, execute and claim on the pinned V2.5 stack.
2. **Delinquent-entry semantics:** explicit rule plus unit, fork and `TrancheInvariantTest` coverage.
3. **Recovery/stateful restoration:** distress, cure, wind-down and direct-recovery cases.
4. **Terminal accounting:** dust and final-request rule.
5. **Entry and metadata:** gates if needed, sanctions integration and unique tranche names.
6. **Operations:** declarer retirement, governance recovery if selected, and a resolved
   supersession design.

Each PR should change one accounting proposition at a time. A property test which states that
proposition belongs in the same commit.
