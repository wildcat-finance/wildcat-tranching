# Wildcat tranching: parameter discovery guide

## How to use this

Use this worksheet to learn what a borrower, senior lender or junior provider would accept. It is not a
term sheet and does not create amendment rights. Record a preferred value, an acceptable range, the
reason for the range, and the person who actually controls the deployed setting.

Start by separating four buckets:

1. borrower-selected tranche terms, fixed when the manager is deployed;
2. underlying market terms, some of which have later Wildcat-authorised update paths;
3. hook and protocol settings controlled outside the tranching factory; and
4. rules fixed or derived by the contracts.

## A. Borrower-selected tranche terms

The market borrower supplies every row below when attaching the manager. There are no economic
defaults and no manager setter after deployment.

| Question | Contract bound | Borrower range | Senior range | Junior range | Agreed discussion range |
| --- | --- | --- | --- | --- | --- |
| Senior target rate | 0 to 10,000 bips |  |  |  |  |
| Minimum junior percentage | 500 to 9,000 bips |  |  |  |  |
| Extra delinquency window | More than 0; no more than 90 days |  |  |  |  |
| Senior entry gate | Zero for open entry, otherwise contract |  |  |  |  |
| Junior entry gate | Zero for open entry, otherwise contract |  |  |  |  |
| Terminal-surplus recipient | Nonzero; cannot be manager |  |  |  |  |

Questions to settle:

- Is the senior target intended as a fixed nominal accounting rate, and is everyone clear that it is
  neither the market APR nor a guaranteed return?
- Is the junior percentage measured against capital at formation, a risk limit used by an institution,
  or both? The contract checks it on senior entry and active junior exit; it does not restore it after
  loss.
- What behaviour should the extra delinquency window express? The manager uses market grace plus this
  window as an objective one-way wind-down threshold.
- Who owns or administers each proposed gate contract? Can its policy change? What happens to an account
  that ceases to qualify after acquiring tokens?
- Is the terminal recipient the borrower, a treasury, a foundation, or another fixed address? This
  recipient receives only proven surplus after every holder claim and custody position has cleared.

## B. Underlying Wildcat market terms

These terms belong to the market formed before the manager attaches. Do not describe them as set by
`TrancheFactory`.

| Market item | Current source and bound | Later authority | Discussion range or requirement |
| --- | --- | --- | --- |
| Capacity | Borrower input; `uint128` | Market borrower can update while permitted |  |
| Lender APR | 0 to 10,000 bips | Market borrower can update while permitted |  |
| Initial reserve ratio | 0 to 10,000 bips | Later behaviour travels with APR changes and OpenTerm constraints |  |
| Delinquency fee | 0 to 10,000 bips generally; trancher requires 1 to 10,000 | Fixed market term |  |
| Delinquency grace | 0 to 90 days | Fixed market term |  |
| Withdrawal-batch duration | 0 to 365 days | Fixed market term |  |
| Asset | ERC-20 with at least six decimals for this manager | Fixed market binding |  |

Questions to settle:

- What market APR and capacity make sense beside the tranche mix rather than in isolation?
- Which borrower APR or capacity changes require advance notice, lender consent outside the contract,
  or a fresh commercial review?
- What reserve behaviour and repayment cadence should be assumed in normal operation?
- How long can treasury teams tolerate a withdrawal sitting in a batch before liquidity is available?
- Which delinquency fee and grace period create a useful warning and cure period without confusing the
  later manager wind-down threshold?

## C. Hook and protocol settings

| Item | Initial authority | What can change | Question for the call |
| --- | --- | --- | --- |
| Upstream minimum deposit | Borrower supplies in market hook data; zero means none | Current hook administrator can change it | Is there a minimum ticket above the manager's fixed first-class minimum? |
| Market-token transfers | Borrower supplies `transfersDisabled` at creation | No setter in the pinned hook | It must be false for the trancher; is that understood? |
| Fresh-deposit access | Current hook administrator | Can block or unblock manager deposits | Who holds this role, and what operating policy governs it? |
| Hook administrator | Initially registered borrower principal | Transferable under Wildcat's two-step rules | Who may receive the role later? |
| Protocol-fee rate | ArchController owner chooses the Wildcat hook-template rate | ArchController owner can update the template; HooksFactory can then propagate the configured rate to an open market, capped at 1,000 bips of base lender interest | What rate should cost analysis assume, and how is change disclosed? |
| Protocol-fee recipient | ArchController owner chooses the hook-template recipient for new markets | Fixed for an existing market | Which address is recorded? |
| Origination fee | ArchController owner chooses the hook-template asset and amount | Paid at market creation | Is it included in the borrower's all-in economics? |

The 1,000-bip protocol-fee cap means no more than 10% of the base lender rate, not 10% of principal. At
a 10% lender APR, the maximum setting adds one percentage point: 10% lender APR plus 1% protocol APR
gives 11% running base-interest cost before origination or delinquency charges. The manager adds no
separate fee in the current code.

## D. Code-set and derived rules

These are not negotiation fields in the current prototype:

| Rule | Current behaviour | What to ask instead |
| --- | --- | --- |
| Waterfall | Senior receives the lesser of realised value and senior owed; junior gets the remainder | Is that priority acceptable in the proposed scenarios? |
| Recovery | Senior first across classes; FIFO within a class | What reporting and liquidity planning does each side need? |
| Delinquency mark | Upside capped at last healthy mark; live losses still count | What mark and market-state reporting should be supplied? |
| Wind-down | One-way at market close, or when a manager checkpoint observes the current delinquency counter at grace plus tranche window | Who calls permissionless `checkDefault` during delinquency, and does legal documentation need a separate event or remedy? |
| Holder sanctions | Acquisition checks; sanctioned holder can exit through canonical escrow | Who handles escalation and proof of release? |
| Manager sanctions | Withdrawal execution reverts before batch execution is recorded, deferring recovery for everyone until clearance and retry | Who monitors manager status and retries the batch? |
| Terminal settlement | Fixed recipient after supply, custody, reserves and requests clear | Is the recipient acceptable and operationally controlled? |
| First class deposit | Credited value at least `1e6` base-asset units | Does rounding or asset precision create a practical ticket issue? |

## E. Scenario prompts

Use amounts only as illustrations. Replace them with agreed ranges after the call.

### Scenario 1: ordinary performance

Suppose junior contributes 100 and senior contributes 300. The manager value later reaches 420 while
senior is owed 315. Senior is valued at 315 and junior at 105.

Ask:

- Is 25% initial junior capital enough for senior?
- Does the junior expected residual compensate for its loss position?
- How should any difference between market APR and senior target be explained?

### Scenario 2: junior loss

With senior still owed 315, manager value falls to 340. Senior remains 315 and junior falls to 25.

Ask:

- Which monitoring threshold should trigger a credit or treasury conversation?
- Does anyone incorrectly expect the contract to restore the original junior percentage?
- Which exits remain practical while the junior floor constrains active junior withdrawal?

### Scenario 3: senior impairment and delayed cash

Manager value falls to 280 and the market cannot pay every queued request at once. Junior is exhausted;
senior is valued at 280. Recovery pays senior request face first and FIFO within senior.

Ask:

- What delayed or partial recovery can each side tolerate?
- What information is needed about the Wildcat batch and borrower repayment plan?
- Which legal or offchain rights, if any, sit outside the manager and require counsel?

### Scenario 4: delinquency and cure

The market becomes delinquent before the objective threshold. Deposits stop and recognised upside is
held at the last healthy mark, but live losses count. The borrower cures before grace plus the tranche
window, so the mark can refresh and entry can reopen. If the current counter reaches the threshold,
someone must call the permissionless `checkDefault` before cure for irreversible wind-down to be
recorded; historical crossings are not reconstructed.

Ask:

- Is the chosen extra window long enough to permit a credible cure?
- Who is responsible for checkpointing the current counter during delinquency?
- What status update should each class receive during the window?
- Should offchain documents use the same threshold, or keep a separate legal concept?

## F. Decision record

Before turning discussion into implementation, record:

- the exact market address, asset, manager's stored borrower principal, market's current borrower
  principal, any difference between the two, hook template and canonical wrapper;
- each tranche term, its bound, chosen value and approving owner;
- the live market APR, capacity, reserve behaviour, batch duration, fee, grace and protocol charges;
- gate addresses, administrators, eligibility policy and change process;
- terminal recipient and sanctions-escrow operating contacts;
- normal, junior-loss, senior-impairment and delinquency scenarios reviewed; and
- open legal, tax, regulatory, credit, operations and reporting questions.

No answer in this worksheet changes the deployed contracts. It records commercial preferences for a
later formation decision.
