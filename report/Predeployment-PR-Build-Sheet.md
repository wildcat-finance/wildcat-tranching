# Pre-Deployment PR — Build Sheet

*Every question the pre-deployment PR has to answer, written out. The what-and-why is settled in `Design-Risk-Specification.md` §IX and `Deployment-Access-Governance-Notes.md`; this sheet is the implementation-level list — the decisions an engineer hits while building. These are now locked as decisions rather than recommendations, bar the ones flagged as needing answers from outside the PR. Nothing here touches the waterfall.*

---

## Answers needed from outside the PR

These block specific commits; everything else can be built while they resolve.

| # | Needed | Blocks | From |
|---|---|---|---|
| X1 | Exact ABI names: the wrapper factory's market→wrapper getter, its deploy entrypoint, the market's `borrower()` getter, and the market's deposit function signature + return semantics | D, F | 15 minutes against the deployed contracts |
| X2 | Foundation sign-off on the borrower-gated, ownerless factory posture | D | Foundation |
| X3 | Legal answer on ToU/MLA acceptance for tranche-only buyers (does a tranche deposit constitute acceptance, or does the tranche layer need its own papering?) | F (merge/ship, not build) | Legal |
| X4 | Confirmation that junior must always be gated (no zero junior gate) — assumed below | B6 | Desk, one word |

---

## A. Per-market token metadata

- **A1. Decided: derived on-chain.** The controller reads `IERC20(market).symbol()` at construction and mints `"Senior Tranched <SYM>"` / `sr-<SYM>` and `"Junior Tranched <SYM>"` / `jr-<SYM>`. `DeployParams` carries no name or symbol field, which is one less caller-supplied input and one less way for two facilities to end up with the same ticker.
- **A2. Validation.** Require a non-empty market symbol at construction; no length cap (wallets truncate fine). A market with a broken `symbol()` fails deployment loudly, which is the right outcome.
- **A3. Decimals** stay a params field, default 18. No change.

## B. Entry gates

- **B1. Which interface, exactly?** Import Morpho Midnight's `IEnterGate` verbatim and call only `canIncreaseCredit(receiver)`; `canIncreaseDebt` goes unused (there is no borrower side here).
  *Decision: verbatim import, unused function documented. A bespoke one-function interface would cost the shared-gate-deployment property for zero gain.*
- **B2. Where checked?** `_deposit` on the receiver, and `beforeTrancheTransfer` on the recipient. Never on the sender, never in `requestRedeem` or `claim` — mint/burn already bypass the transfer hook, which is what makes exits structurally ungateable. One check per exposure-increasing edge, no more.
- **B3. Revert handling?** Plain call (the hook is `view`, so the gate call is naturally static) — a reverting gate blocks entry and secondary transfers but never exits.
  *Decision: plain call, no try/catch. Guarding belongs in the gate implementation (the role-provider gate already fail-closes per provider); double-guarding in the controller hides gate bugs. Document for gate authors: return `false`, don't revert.*
- **B4. Junior whitelist migration.** Remove `juniorAllowed` and `setJuniorAllowed` from the controller entirely; ship a minimal `WhitelistGate` (owner-managed mapping implementing `IEnterGate`) as the default junior gate.
  *Note: this removes a power from the controller's governance table — whitelist management moves to the gate's owner. The spec's Q16 power inventory needs the corresponding edit on merge.*
- **B5. Mutability.** Both gate pointers immutable, set in the constructor from `Params`. Policy mutability lives inside the gate.
- **B6. May junior be ungated?** No — require `juniorGate != address(0)` at construction (X4 to confirm). Senior gate zero = open, which is today's behaviour.
- **B7. Is hardening `WildcatRoleProviderGate` in scope?** No. This PR needs only the interface, the two checks, and the trivial `WhitelistGate`. Productionising the role-provider gate is its own workstream (it also serves the Midnight integration) and should not gate this merge.

## C. `claimMany`

- **C1. Signature & behaviour.** `claimMany(uint256[] calldata ids) returns (uint256 total)` — per-id logic identical to `claim`, zero-claimable ids skipped silently (no revert), total summed.
- **C2. Bounds?** None needed: each claim is O(1) and calldata is gas-bounded. No ownership check needed either — `claim` already pays the request's owner regardless of caller.
- **C3. Escrow path.** Unchanged per-claim; a sanctioned owner's ids each route to escrow exactly as single `claim` does.

## D. Factory rework

- **D1. Access.** `deployTranches(market, …)` requires `msg.sender == market.borrower()` (getter name from X1).
- **D2. Wrapper resolution.** Query the wrapper factory's registry (name from X1); if absent, deploy via its permissionless entrypoint in the same transaction. Fallback if no registry getter exists: accept a wrapper argument but require `wrapperFactory.isWrapper(w) && w.market() == market`.
- **D3. Sentinel.** Immutable constructor parameter of the *factory* (the canonical singleton), never caller-supplied per deployment.
- **D4. Where do bounds live?** In the controller's constructor, where they already are. The factory adds access, resolution, and registry only — no duplicated requires, one source of truth.
- **D5. Ownership.** Delete `owner`, `pendingOwner`, `transferOwner`, `acceptOwner`. The factory has no privileged role.
- **D6. Registry.** `controllerForMarket[market]` points at the *current* controller; `allControllers` keeps full history.
- **D7. Failure handling.** A wrapper-factory revert (e.g. unregistered market) bubbles; no catch-and-continue anywhere in deployment.

## E. Supersession

- **E1. The predicate.** Replacement allowed when the incumbent's `status == WindDown`, **or** both tranche supplies are zero. An incumbent in wind-down keeps paying claims forever — replacement never touches it; the registry pointer is the only thing that moves.
  *The exact "empty" definition is the fiddliest call in this PR. Supplies-zero is clean and sufficient [no supply, so no new claims can originate], but note a request can exist with both supplies zero and unclaimed cash — shares burn at request time — so claims must stay payable on the retired controller regardless. They do: `claim` has no status gate.*
- **E2. Who calls.** The borrower, same gate as D1.
- **E3. Does the incumbent get a flag?** No forced state change on the old controller. Retirement is a registry fact, not a controller state — WindDown already froze deposits where it matters, and an empty-Active incumbent has nothing at stake.

## F. USDC front door *(build now, merge/ship behind X3)*

- **F1. Entry shape.** One pair of entrypoints with an asset-kind enum: `depositSenior(AssetKind kind, uint256 amount, address receiver)` where `AssetKind ∈ {WrapperShares, MarketToken, USDC}` — over six near-identical functions.
  *Existing `depositSenior/Junior(underlyingShares, receiver)` can stay as thin wrappers for back-compat or be removed pre-deployment; nothing live depends on them. Decision: remove — cleaner surface, and there is no deployed integrator to break.*
- **F2. Approvals.** Exact-amount approve per call via `SafeTransferLib` (handles USDC's non-standard return); no standing max allowances from the controller.
- **F3. Measuring what arrived.** Use the market deposit's return value if it returns minted tokens, else balance-delta (X1 pins this). Wrap-to-`v-` uses the wrapper's returned share count — the existing valuation path from there down is untouched.
- **F4. Capacity.** Let the market revert and bubble a wrapped error (`MARKET_AT_CAPACITY`) rather than pre-checking headroom — pre-checks race with other depositors in the same block.
- **F5. Controller credentialing under the market's hooks** is operational (deploy runbook), not code. A missed step reverts deposits loudly.
- **F6. Valuation.** `dV` computed from wrapper shares actually minted, exactly as today. No changes to `_effPps`, the watermark, or sizing.
- **F7. Ship gating.** Build and test now; the commit merges when X3 answers. If legal wants papering at the tranche layer, the enforcement point is the entry gates (B), not new code here.

## G. Governance recovery + declarer retirement

- **G1. Recovery existence.** `borrowerRecovery` immutable bool in `Params`. Window: 30-day constant, not a parameter — one fewer knob, and no facility has argued for a different number.
- **G2. Veto.** Explicit `cancelReclaim()` `onlyGovernance` — a single call kills the pending reclaim. No implicit auto-cancel on other governance activity (simple beats clever; an active-but-inattentive governance *should* have to notice).
- **G3. Completion.** After the window, the borrower calls `finalizeReclaim()`, which sets `pendingGovernance = next` — the successor still must `acceptGovernance()`, so recovery can't land on a call-incapable address.
- **G4. Events.** `ReclaimProposed(next, eta)` / `ReclaimCancelled()` / `ReclaimFinalized(next)` — the proposal event is the one monitoring alerts key off.
- **G5. Declarer retirement.** Explicit `clearDefaultDeclarer()` `onlyGovernance` (keeps the zero-guard on `setDefaultDeclarer` intact rather than special-casing zero through it).
- **G6. State interactions.** Reclaim is legal in any status including WindDown (governance still holds pause/declarer powers there); `declareDefault` via a mid-reclaim governance is unaffected.

## H. Cross-cutting

- **H1. Tests.** Per feature: unit + a named regression in the style of `AuditPoC.t.sol`. The invariant suites re-run unchanged (nothing touches the waterfall). Fork suite gains: a USDC front-door round trip against the live market (deposit → wrap → tranche mint), and a hooks-credentialing revert case.
- **H2. Audit sequencing.** This PR reopens the controller and factory surface — the human audit engagement should scope the *post*-PR code. Merge first, then commission; don't run them in parallel.
- **H3. Doc updates on merge.** Spec §IX items flip from "pending build" to amended into Q1–Q16; Q16's power table drops `setJuniorAllowed` (B4) and gains the recovery/veto and `clearDefaultDeclarer`; the mechanisms report's "settled, pending build" line and the infographic's F8 row update.
- **H4. Gas note.** One static gate call per deposit and per transfer-in; zero on the exit path. Not worth optimising.

---

## Suggested commit order

1. **A + C** (symbols, `claimMany`) — no dependencies, mechanical.
2. **B** (gates + `WhitelistGate`, whitelist migration) — needs X4's one-word confirm.
3. **G** (recovery + declarer) — independent.
4. **D + E** (factory + supersession) — needs X1 names and X2 posture sign-off.
5. **F** (front door) — needs X1's deposit signature; merges behind X3.

Each commit lands with its regressions; the PR is mergeable after 4 with F held back if legal is slow, since F is additive entrypoints only.

---

*Companions: `Design-Risk-Specification.md` §IX (the decisions these questions implement), `Deployment-Access-Governance-Notes.md` (deployment/governance rationale and the O-register), `Six-Seven-Mechanisms-Report.md` (the facility this unblocks).*
