# Single-Lender Markets for Tranche Facilities — Feasibility & Roadmap

*A tranche set deployed against an ordinary Wildcat market does not make senior senior. It makes senior senior **over the controller's own slice** of a pari-passu lender pool. This document establishes how large that gap is, whether the hooks system can close it, and what the implementation actually costs. The short answer: the mechanism is feasible, the hooks system is the correct home for it, and Wildcat v2.5 already ships most of the primitives — but two of the three moves in the originating proposal should be changed, and the strongest form of the guarantee is structurally incompatible with the 4626 wrapper the tranche layer currently depends on. Protocol facts are cited against `wildcat-finance/v2-protocol` at `release/v2.5` (`dec36d2`); tranche-layer facts against this repo at `800c0eb`. Companions: `Design-Risk-Specification.md` Q1/Q18/Q20, `Deployment-Access-Governance-Notes.md` §2/§4.*

---

## Decisions outstanding

| # | Decision | What hangs on it | Owner |
|---|---|---|---|
| S1 | **Is exclusivity a product requirement or a product option?** If senior is sold as senior, it is a requirement and Phase 1 blocks the first facility. If it is a per-facility disclosure, Phase 0 alone ships | Determines whether a protocol change gates the first placement | Desk + Foundation |
| S2 | **Custody model under exclusivity** (§6.4): allowlisted-transfer exclusivity keeps the 4626 wrapper and the audited valuation core; transfer-disabled exclusivity is airtight but forces Q18(d) direct custody and a rewrite of the valuation core against `scaleFactor` | The single largest engineering fork in this document. Phase 1's scope doubles under the second option | Desk + engineering |
| S3 | **Foundation appetite for a fourth hooks template.** Registration is a routine owner action (one per factory kind), but the template is protocol surface the Foundation must be willing to carry, and as proposed it exists to serve one product — §4.2 argues for a general primitive partly to improve this answer | Blocks Phase 1 entirely. There is no way to do this from the tranche side | Foundation |
| S4 | **Whether the protocol may know what a tranche controller is** (§4.2). Recommendation: no — the hook enforces exclusivity as a general primitive, the tranche factory checks for it | Shapes the template's interface. Cheap now, expensive later | Foundation + engineering |
| S5 | **Dilution policy for non-exclusive facilities** (§7, Phase 0): the threshold at which the controller halts new senior deposits, and whether the trigger is advisory or hard | Needed for Phase 0, which is the only thing available to existing markets | Desk, per facility |

Settled by this analysis, no decision left: do not deregister `OpenTermHooks` (§4.3 — it is one-way, it does not achieve the goal, and it breaks every future borrower); do not police `grantRole` (§4.1 — four independent bypasses); protocol fees stay senior and are accepted as facility terms (§6.5).

---

## 1. The problem, stated precisely

Wildcat markets are pari passu among lenders, and this repo has already established what that does to tranching — but only for the special case of two tranche controllers. `Design-Risk-Specification.md` Q20 rules out concurrent tranche sets on one market because "at the market layer, two controllers are pari-passu lenders whose withdrawal claims fill pro-rata from the same batches. Under stress, one set's *senior* would compete on equal footing with another set's *junior* for the same cash." That argument is correct and it was never generalised. Replace "another set's junior" with "any other lender in the market" and it survives intact. The general case is strictly worse than the special case Q20 rejected, because other lenders are not a rare governance event — they are the default state of every market Wildcat has ever deployed.

The mechanism is confirmed at the code level. Within a withdrawal batch, payment is strictly pro-rata on scaled amount with no per-lender ordering, priority, tier or timestamp weighting:

```solidity
// src/market/WildcatMarketWithdrawals.sol:265-269
uint128 newTotalWithdrawn = uint128(
  MathUtils.mulDiv(batch.normalizedAmountPaid, status.scaledAmount, batch.scaledTotalAmount)
);
```

The only seniority the market layer recognises is temporal — earlier batches drain before later ones from a FIFO queue (`WildcatMarketWithdrawals.sol:353`), and `normalizedUnclaimedWithdrawals` outranks everything. Nothing about *who* a lender is affects what they get. For a single pooled controller this is exactly the right property: it means all subordination logic can live inside the controller. For a controller sharing a market, it means the market's pro-rata fill happens *before* the controller's waterfall runs, and the waterfall only ever gets to allocate the controller's share.

### 1.1 Two distinct harms, and the one that actually bites

**The economic harm.** Let the controller hold fraction *f* of the market's scaled supply. On a shortfall, the market pays the controller *f* × (recovery), and only then does the senior/junior waterfall apply. Senior's first-loss protection is the junior cushion — but that cushion only absorbs losses on the controller's *f* of the book. It does nothing about the other lenders competing for the same batch cash. Concretely, on a facility with a 20% junior cushion where the controller is 30% of the market: senior is protected against the first 20% of loss on its own slice, and is otherwise an ordinary pro-rata lender. A senior buyer who believes they hold a claim that is senior across the facility holds something materially different.

**The confusion harm.** This is the one that matters, and it bites whether or not a loss ever occurs. The token is called `sr-abcUSDC`. The documentation, the BD primer, and the deck all say "senior". A treasury allocator or a compliance desk reading "senior tranche" will read it as seniority over the facility, because that is what the word means everywhere else in credit. On an open market it means seniority over a subset of the facility whose size is a function of who else happened to deposit — a quantity that moves without the senior holder's knowledge or consent, and that the borrower controls unilaterally. Senior's protection is not merely thinner than advertised; it is *non-stationary*, and nothing in the current stack surfaces it.

That reframes the problem. This is a disclosure and product-integrity matter before it is a mechanism matter, which is why §7 puts telemetry and a deposit halt in Phase 0, ahead of the protocol change: those address the confusion harm on existing markets, today, with no Foundation ceremony. The protocol change addresses the economic harm on new markets, later.

### 1.2 Why the borrower cannot simply be trusted not to

The originating observation is right: a market can be deployed with the controller as its only credentialed lender, and the borrower can then add more. Nothing prevents it, nothing announces it, and there is a standing incentive to do it — a borrower who has placed a tranche facility and then wants more capacity will find that credentialing a direct lender is faster and cheaper than growing the junior cushion. The dilution is not adversarial; it is the path of least resistance. Depending on borrower restraint for a property the product is *named after* is the thing to avoid.

---

## 2. What v2.5 already provides

More than expected. The v2.5 access-layer refactor (`BaseAccessControls` + `OpenTermHooks` / `FixedTermHooks` / `PeriodicTermHooks`) shipped four primitives that a single-lender market needs, plus one pattern that shows the integration shape is already sanctioned.

**Hooks are purely restrictive, which is exactly the right shape.** The protocol's own documentation is explicit: "Hooks can not modify internal behavior of the market and do not have any privileged access to its state; rather, they are designed to be *reactive to* and *restrictive of* market actions" (`docs/hooks/How Hooks Work.md`). An exclusivity hook only ever reverts. It needs no new market bytecode, no state access, and no exception to the hooks model. This repo's own effort assessment already anticipated it in passing — "Hooks can assist (for example, restricting a market so only the tranche vault may deposit), but that is optional" (`Wildcat-Tranching-Effort-Assessment.md:64`). The idea is not novel; it was noted and deferred.

**A hook can force its own enforcement points on.** This is the load-bearing fact for feasibility, and it is not obvious. Each template declares an *optional* and a *required* flag set, and the market's final config is computed as `final = (borrowerRequested AND optional) OR required`:

```solidity
// src/types/HooksConfig.sol:141
let mergedFlags := and(0xffff, or(and(configFlags, _optionalFlags), _requiredFlags))
```

A flag in `requiredFlags` is forced on regardless of what the borrower asked for. All three shipped templates leave `useOnDeposit` and `useOnTransfer` *optional* — meaning a borrower can today deploy an `OpenTermHooks` market with both gates off and get a fully permissionless market. A template that places `Bit_Enabled_Deposit`, `Bit_Enabled_Transfer` and `Bit_Enabled_QueueWithdrawal` in `requiredFlags` cannot be configured out of its own invariant. The guarantee lives in the template's `immutable config` and in `mergeFlags`, neither of which the borrower touches.

**A market-wide transfer kill switch already exists.** `HookedMarket.transfersDisabled` is read once from `hooksData` at market creation, has no setter anywhere in `src/`, and makes every `onTransfer` revert unconditionally (`OpenTermHooks.sol:338-340`). Immutable, and immutable in the right direction.

**There is precedent for an external integration querying a hooks instance for a property assertion.** `IMarketTransferPolicy.isMarketTransferDisabled(market)` exists precisely so that other contracts can ask a hooks instance about a market's policy, and its doc comment frames the answer as a forward commitment: "A `false` response is a compatibility promise that the hook will not later transition the market to a universally transfer-disabled state." That is the same interface shape an exclusivity assertion needs, already blessed and already consumed in production by the wrapper factory.

**Sanctions no longer create a second market-token holder.** In v2.5 `nukeFromOrbit` queues an ordinary withdrawal in the sanctioned account's own name rather than moving market tokens to an escrow (`WildcatMarket.sol:307-335`); the escrow receives the *underlying asset* later, at execution. So the sanctions path cannot mint a competing claimant. A pre-v2.5 reading of this would have concluded otherwise.

**Every transfer funnels through one choke point.** `transfer` and `transferFrom` both reach `_transfer`, whose only gate is `hooks.onTransfer` (`WildcatMarketToken.sol:89`), called before balances move. One hook covers the entire transfer surface.

**And the market already has a "one canonical special address, set once, immutably" pattern.** `registeredWrapper()` is a dedicated storage slot, writable only by the wrapper factory, only once (`WildcatMarketConfig.sol:65-70`). A designated-lender slot is the same shape.

---

## 3. The one hole, and why nothing deployed can close it

No configuration of the shipped templates yields a closed lender set. Four independent paths admit a new credentialed lender, and the borrower controls all four:

1. **The borrower is a permanent push provider.** `BaseAccessControls`' constructor registers the borrower as a role provider with `type(uint32).max` TTL (`:94-105`), so `grantRole(account, timestamp)` from the borrower credentials anyone, forever.
2. **`addRoleProvider` is `onlyBorrower` and unconditional** (`:165-167`). There is no seal, no cap, and no one-way freeze. Even a borrower who removes every provider including themselves can re-add themselves the next block.
3. **Pull providers credential arbitrarily, with no borrower transaction at all.** On any gated action without a live credential, `_tryValidateAccessInner` loops every registered pull provider (`_loopTryGetCredential`, `:640-652`) and accepts the first non-zero, non-future timestamp. A single permissive pull provider re-opens the market silently.
4. **`isKnownLenderOnMarket` is a sticky, never-revoked bypass.** It is set to `true` on first deposit *and on receipt of a transfer while credentialed* (`:806-815`, called with `canSetKnownLender: true` from both `onDeposit` and `onTransfer`), and no code anywhere in `src/` ever writes `false` to it. In `onTransfer` it short-circuits the entire check block including the blocked-from-deposits check (`OpenTermHooks.sol:343-345`). Once an address has ever been a lender on a market it can receive market tokens forever, after revocation and after being blocked.

Point 4 is why a naive count of *currently credentialed* addresses is worthless: revoking lender A and credentialing lender B does not reduce the claimant count, because A still holds tokens, still accrues interest, and still has an unrevokable path to receive more. Any correct invariant must be monotonic over the market's whole history, not a snapshot.

And there is nothing to count anyway. There is no lender set, no lender counter, and no enumerable holder list in the protocol — `_accounts` is a bare mapping, `MarketState` tracks only aggregates, and `isKnownLenderOnMarket` has no counter and no removal. **The exclusivity invariant therefore cannot be checked against stored state; it must be enforced prospectively, asserted per-action.** That is a design constraint rather than a blocker, but it decides the mechanism.

---

## 4. Assessment of the proposal as stated

The proposal has three moves: (a) a hook that refuses to admit a second lender when the first is a tranche controller, (b) deregistration of the existing borrower-approval hook, (c) acceptance that existing markets are grandfathered. (c) is correct and unavoidable — the market's `HooksConfig` is `immutable`, assigned once in the constructor (`WildcatMarketBase.sol:59`, `:236`), with no setter anywhere, so **no change can ever retrofit an existing market.** (a) has the right instinct and the wrong control point. (b) should not be done.

### 4.1 "If there's already one approved, you can't add another" — right instinct, wrong control point

Policing the credential machinery means intercepting `grantRole`, `grantRoles`, `addRoleProvider`, `createRoleProvider`, and the pull-provider loop, and then still handling the sticky known-lender flag from §3, item 4. Every one of those is a separate override with its own bypass analysis, and the pull-provider loop is the awkward one: it grants credentials inside `_tryValidateAccessInner` with no distinct entry point to guard.

Gate at the point of use instead. Store a designated lender per market and have `onDeposit` revert unless the depositor is that address. Credentials then become **irrelevant to the guarantee** — the borrower may add providers, grant roles, and credential the whole world, and none of it produces a second market-token holder, because the deposit hook does not consult credentials for the exclusivity decision. One assertion, in one place, on the action that actually creates a claim. This also aligns with §3's conclusion that the invariant must be prospective: an assertion per action is the only available shape, so the design should lean into it rather than fight it.

The same applies to the "if it happens to be a tranche controller" condition, which should be dropped for a second reason — see below.

### 4.2 Do not teach the protocol what a tranche controller is

The proposal conditions the restriction on the approved address *being* a tranche controller. Invert the dependency. The hook enforces **exclusivity** — a general, self-contained property: "this market has exactly one designated lender, fixed, forever." The tranche factory then **checks for** exclusivity before deploying a set. Three reasons, in increasing order of importance:

- *Layering.* A hooks template that imports a tranche-controller registry couples the protocol's release cycle to a product's. The dependency should point the other way, as it already does for the wrapper factory consuming `IMarketTransferPolicy`.
- *Reusability.* "This market has one lender and always will" is a sellable primitive on its own — bilateral facilities, single-counterparty SPV structures, a fund lending against one borrower. Registered once, it serves cases beyond tranching, which materially improves the answer to S3.
- *Neutrality.* Wildcat Labs and the Foundation are bound to neutrality, and `Deployment-Access-Governance-Notes.md` §1 already rejected the owner-gated factory on exactly this ground. A hooks template in the protocol that names one specific product is the same problem in a worse location. An exclusivity primitive that the tranche layer happens to require is neutral; a tranche-controller-aware hook is an endorsement cast in bytecode.

**Verification must check template provenance, not just the interface.** This is the subtle part. If the tranche factory merely calls `exclusiveLenderOf(market)` on the market's hooks instance, any borrower can deploy a contract that answers correctly and enforces nothing. The instance *is* the enforcement, so the factory must confirm the instance came from a known-good template:

```
market.factory()                                       // immutable, WildcatMarketBase.sol:68
market.hooks()                                         // HooksConfig, top 160 bits = instance
  → factory.getHooksTemplateForInstance(instance)      // public mapping, HooksFactory.sol:92
  → assert template ∈ {allowlisted exclusivity template addresses}
  → assert IExclusiveLender(instance).exclusiveLenderOf(market) == controller
```

Three details make or break this check.

- **Resolve the factory from the market, do not hardcode it.** `market.factory()` is immutable on the market. There are two live factory *kinds* — `HooksFactory` and `HooksFactoryRevolving` — with completely independent template registries, and several historical factory generations stay registered on the ArchController forever (no `removeController` has ever been run on testnet). `getHooksTemplateForInstance` is per-factory storage, so querying the wrong one returns zero.
- **Allowlist template *addresses*, not version strings.** `getHooksTemplateForInstance` returns the init-code-storage contract address, which is an identity, not a type tag. The tempting shortcut is `IHooks.version()`, which returns a literal like `'OpenTermHooks'` — but that string is supplied by the instance itself, so a hostile instance can return anything. `version()` is a labelling aid (the lens uses it for display, `HooksConfigData.sol:71-81`); the template address is the authenticated primitive.
- **`isRegisteredMarket` is revocable.** The ArchController has `removeMarket` and `removeBorrower`, both owner-callable, so the registration check `TrancheFactory` already performs is a point-in-time assertion rather than a standing guarantee. Worth knowing; not worth defending against.

### 4.3 Do not deregister `OpenTermHooks`

Three independent reasons, any one sufficient.

**It does not achieve the goal.** `disableHooksTemplate` gates `deployHooksInstance` only (`HooksFactory.sol:358`). `deployMarket` never reads `templateDetails.enabled` — it checks only that the instance is known:

```solidity
// src/HooksFactory.sol:601-605
address hooksTemplate = getHooksTemplateForInstance[hooksInstance];
if (hooksTemplate == address(0)) {
  revert HooksInstanceNotFound();
}
HooksTemplate memory templateDetails = _templateDetails[hooksTemplate];
```

So every borrower who already holds an `OpenTermHooks` instance — which is every borrower with a live market — keeps deploying ordinary non-exclusive markets against it indefinitely. Disabling the template closes the door for new entrants only.

**It is irreversible.** The code says so in a comment: "The template is only disabled, not removed: `exists` stays true, so it can not be re-added and there is no re-enable path" (`HooksFactory.sol:250-252`). Recovery would require deploying and registering a fresh init-code storage contract.

**The collateral damage is the whole protocol.** `OpenTermHooks` is one of two templates registered on mainnet (`deployments/mainnet/deployments.json`, alongside `FixedTermHooks`). Disabling it removes the standard open-term access-controlled market from every future Wildcat borrower, to make one product's guarantee tidier. That trade is not close.

The additive alternative costs nothing and gives up nothing: register the exclusivity template alongside the existing two, and enforce the requirement at the consumer — the tranche factory refuses markets that do not assert exclusivity. The capability is added, no capability is removed, and the product gets its guarantee. This is exactly the shape every template rollout has taken; the `PeriodicTermHooks` checklist describes it as deploying "a new `PeriodicTermHooks` init-code storage contract, [registering] it on the target `HooksFactory`, and [deploying] a new `MarketLens`. It does not deploy a new hooks factory or new market bytecode."

Disabling `OpenTermHooks` is worth keeping in the toolbox for a different job — retiring a template that has been superseded — and it is worth knowing that disable is soft in other ways too: fee updates and protocol-fee pushes both continue to work on a disabled template, and the template stays in the enumerable list forever, so any integration listing templates must filter on `enabled` itself.

---

## 5. Design options

| | Option | Guarantee | Cost | Retrofits existing markets |
|---|---|---|---|---|
| **A** | **New template, per-market designated lender** (recommended) | Hard. No second market-token holder can ever exist | New protocol template + audit + one owner action | No |
| **B** | Lender-set seal on `BaseAccessControls` | Hard, if the seal covers pull providers | Touches the base contract all three templates inherit → re-audit of the whole access layer | No |
| **C** | Tranche layer only: telemetry, empty-market precondition, dilution halt | None. Detection and disclosure, not prevention | Days, in this repo, no ceremony | **Yes** |
| **D** | A + `transfersDisabled` + Q18(d) direct custody | Airtight: provably one token holder, forever | A, plus rewriting the valuation core against `scaleFactor` | No |

**B** deserves a note on why it loses to **A** despite being more reusable. A one-way `sealLenderSet()` on `BaseAccessControls` — after which `grantRole`, `addRoleProvider`, `createRoleProvider` and pull-provider grants all stop producing credentials — would work on all three existing templates and would be a genuinely useful primitive. But it modifies the contract that every deployed hooks instance inherits, which means the audit surface is the entire access layer rather than one new leaf, and the pull-provider path has to be neutered inside `_tryValidateAccessInner` without disturbing the credential semantics that live markets depend on. A new leaf template is strictly less risky for the same product outcome. If the Foundation wants the seal for its own sake, it is a separate piece of work with a separate justification.

**C is not an alternative to A; it is the thing that ships first.** It is also the only option that touches existing markets at all, and it addresses the confusion harm from §1.1 directly, which is the harm that exists today.

**D is the honest endgame, and §6.4 explains why it is not optional-in-spirit.**

Recommendation: **C now, A next, D as a deliberate v2 decision (S2).**

---

## 6. The recommended mechanism

### 6.1 Shape

A template — `ExclusiveLenderHooks` — inheriting `MarketConstraintHooks` for the APR-bound behaviour, but **deliberately not inheriting `BaseAccessControls`**. Per §3, the pull-provider loop and the sticky known-lender bypass are each independently sufficient to admit a second claimant, so the credential stack should be absent rather than constrained. This makes the template smaller and its audit narrower than the existing ones, which is a pleasant inversion of the usual trade.

State: one slot per market, `mapping(address market => address) internal _exclusiveLender`, written once in `_onCreateMarket`, never afterwards.

Hooks, with `Bit_Enabled_Deposit`, `Bit_Enabled_Transfer` and `Bit_Enabled_QueueWithdrawal` in `requiredFlags` so none can be configured off:

- `onDeposit` — revert unless `lender == _exclusiveLender[msg.sender]`.
- `onTransfer` — revert unless both `from` and `to` are in the market's allowed set (§6.4). Asserting on `from` as well as `to` is belt-and-braces: if a stray balance ever exists, it cannot move.
- `onQueueWithdrawal` — revert unless the lender is in the allowed set. Note the hazard: `nukeFromOrbit` routes through `_queueWithdrawal`, so this hook is a veto over sanctions quarantine (`WildcatMarket.sol:314-320`, and the comment there documents the behaviour as accepted). If no stray holder can exist, nothing is stranded; this is an argument for making stray holders impossible rather than merely stranded.
- `isMarketTransferDisabled` — **must** be implemented. The wrapper factory reverts `UnsupportedMarketTransferPolicy` against a hooks instance that does not answer (`Wildcat4626WrapperFactory.sol:102-112`), so omitting it is a compatibility break, not a hardening.
- `exclusiveLenderOf(address market) → address` — the assertion the tranche factory reads, per §4.2.

Everything else no-ops, as in the existing templates. One line must not be forgotten: `_onCreateMarket` needs `if (deployer != borrower) revert CallerNotBorrower();`. The factory does **not** check that a hooks instance belongs to the borrower deploying against it — `deployMarket` validates only that the caller is a registered borrower and that the instance is known. That guarantee lives in each template's `_onCreateMarket` (`OpenTermHooks.sol:140` and the equivalents), so a template omitting it lets any registered borrower attach markets to someone else's hooks instance.

### 6.2 One risk that deserves naming

`docs/Known Issues.md` records that a reverting enabled hook permanently bricks the corresponding market function, and classes it as known and unfixable. For an exclusivity template that is *the design* — reverting every non-designated deposit forever is the product. But it also means the template has no recovery path from a bug: the hooks instance is immutable, the market's pointer to it is immutable, and a template that reverts when it shouldn't leaves the market's deposit or withdrawal path dead with no remedy short of closing the market. The existing templates carry the same exposure, but they carry it on code paths that mostly *permit*; this one exists to deny. That raises the audit bar rather than changing feasibility, and it is an argument for the narrow, credential-free design in §6.1 — the less the template does, the less there is to get wrong.

### 6.3 Binding the controller address

The designated lender must be known when the market is created, but the controller does not exist until after the market does — the tranche factory checks `isRegisteredMarket` first. The circle breaks with CREATE2: the controller's address depends only on the factory and a salt, not on the market.

1. Borrower computes `controller = CREATE2(trancheFactory, salt)` off-chain.
2. Borrower deploys the market with `exclusiveLender = controller` in `hooksData`.
3. Borrower calls `deployTranches(salt, …)`, which deploys the controller to that exact address and asserts the provenance chain from §4.2.

Step 3's assertion is what makes the whole thing trustworthy: the factory refuses to create a set whose market does not already name it as the exclusive lender. This preserves the Q19 property that one borrower transaction brings up the stack, and it fails loudly rather than silently — a mismatch reverts at deployment rather than producing a set that quietly is not exclusive.

The alternative — a one-shot post-creation `setExclusiveLender` — avoids CREATE2 but moves the check after deployment, where the factory cannot enforce it. Prefer CREATE2.

### 6.4 The wrapper problem — the central architectural trade

The tightest invariant is `transfersDisabled = true`: no market-token transfer can ever occur, so the exclusive depositor is provably the only holder for the market's whole life. **That is mechanically incompatible with the 4626 wrapper**, and the incompatibility is enforced in production code:

```solidity
// src/vault/Wildcat4626WrapperFactory.sol:149
if (_isMarketTransferDisabled(market)) revert MarketTransfersDisabled(market);
```

A transfer-disabled market cannot have a wrapper. And the tranche layer needs one: `TrancheController` holds wrapper shares (`realisedValue()` reads `underlyingVault.balanceOf(address(this))`, `TrancheController.sol:187`) and exits via `underlyingVault.redeem(...)` followed by `market.queueWithdrawal(...)` (`:329-331`) — a wrapper-to-controller market-token transfer that a disabled transfer hook would revert. The entire audited valuation core (watermark, delinquency freeze, live-price exit sizing) is written against wrapper shares, which was the single largest de-risking decision in Q1 and was re-affirmed in Q18.

So exclusivity forces a choice, which is decision S2:

**S2(i) — allowlisted-transfer exclusivity.** Keep the wrapper. `onTransfer` permits transfers only within a fixed pair, `{controller, wrapper}`, resolved at market creation or on first wrapper registration. The exclusivity chain then closes by derivation rather than by fiat: the wrapper enters the market only by *receiving market tokens* (`Wildcat4626Wrapper.sol:277` — it never calls `market.deposit`), so if only the controller can obtain market tokens, only the controller can ever mint wrapper shares. Nobody else can acquire the wrapper's shares either, because nobody else can acquire the input.

The cost is that the invariant now rests on a two-hop argument rather than a one-line one — "no third party can hold market tokens, therefore no third party can hold wrapper shares" — and the wrapper contributes no enforcement of its own. It has no depositor gate; the safety is entirely market-token scarcity. That is sound, and it is exactly the kind of derived property an auditor will want stated as an explicit invariant with a test rather than left implicit.

**S2(ii) — transfer-disabled exclusivity.** Drop the wrapper, per Q18(d): the controller holds the rebasing market token directly and the valuation core is rewritten against `scaleFactor`. The invariant becomes a single unconditional revert with no derivation, no allowlist, and no wrapper in the trust path. Q1 and Q18 both rejected direct custody on the grounds that it "rewrites that core against `scaleFactor` and reopens the audited surface for a benefit buyers can't see."

That rationale needs revisiting in this light, because the benefit is no longer invisible. Under exclusivity, the wrapper's original purpose — a non-rebasing 4626 handle for pooled lenders — has no beneficiary: there is exactly one holder, and it does its own accounting. The wrapper stops being a de-risking reuse and becomes a moving part that exists to preserve a code path. That does not settle S2 — reopening an audited valuation core is a genuine cost and the tranche layer is prototype work whose audit has not happened yet, which cuts both ways — but the Q1/Q18 reasoning was written before exclusivity was on the table and should not be treated as having decided this.

Recommendation: build Phase 1 for S2(i), because it works with the code that exists and does not gate on reopening the valuation core; treat S2(ii) as the target state to adopt if and when the tranche layer is rewritten for other reasons.

### 6.5 Residual claimants under either option

| Claimant | Status | Handling |
|---|---|---|
| **Protocol fee recipient** | Senior to unprocessed lender claims and unblockable. `collectFees` is permissionless, has no hook, and `withdrawableProtocolFees` is deducted before batch liquidity (`MarketState.sol:142-148`, `WildcatMarketWithdrawals.sol:330-332`) | Accepted as facility terms. Standard in structured credit (servicing fee at the top of the waterfall). Disclose it; the invariant is "one *lender*", not "one claimant on assets" |
| **Sanctions escrow** | Not a market-token holder in v2.5 (§2). The claim stays in the sanctioned account's own name | No action. Note the `onQueueWithdrawal` veto interaction in §6.1 |
| **The borrower, via `closeMarket`** | Receives surplus over total debts only (`WildcatMarket.sol:231-236`), and `onCloseMarket` can veto | No action |
| **A second market by the same borrower** | Same credit, two facilities, tranched separately. Not a dilution of either | Covenant matter, not a code matter |

---

## 7. Roadmap

### Phase 0 — tranche layer, ships independently (days)

Everything here lives in this repo, requires no protocol change and no Foundation action, and is the **only** tier that helps existing markets. It addresses the confusion harm from §1.1.

1. **Dilution telemetry.** A view on the controller returning its own share of the market's scaled supply. The controller already reads `market.currentState()` for delinquency, so the input is in hand: compare the controller's economic market-token position (via its wrapper holding) against `state.scaledTotalSupply`. Surface it as a first-class number wherever senior is described — frontend, subgraph, term sheet. A senior buyer should be able to read "this facility is 34% of its market" without asking.
2. **Empty-market precondition at deployment.** One line in `TrancheFactory.deployTranches`: require the market's scaled total supply to be zero. This guarantees no *incumbent* lenders at the moment the set is created, which is cheap, unambiguous, and rules out the worst case of a tranche set placed on top of an existing lender base.
3. **Dilution halt.** If the controller's share falls below a threshold fixed at deployment, close new senior deposits while leaving exits fully live. This mirrors the existing subordination gate — a set that cannot honour its senior claim stops selling senior rather than continuing to sell a diluted one — and reuses the established rule that gates apply only where exposure increases, never to exits. Threshold and hard-vs-advisory are decision S5.
4. **Language.** Until exclusivity is enforceable, "senior" needs a qualifier in buyer-facing material: senior *within the facility*, pari passu at the market layer. This is the cheapest item here and probably the most valuable.

### Phase 1 — the template (protocol repo; blocked on S1, S2, S3)

`ExclusiveLenderHooks` per §6.1, plus tests, plus an entry in the audit-delta document. Calibrating against `PeriodicTermHooks`, the closest precedent (a new template added during v2.5 and rolled out additively): ~800 lines of contract, ~1,800 lines of tests, runtime size 17,978 bytes against the 24,576-byte EIP-170 limit. `ExclusiveLenderHooks` should come in materially smaller — it omits `BaseAccessControls` entirely — but size stays a live constraint: the repo's own notes record that the high-run `ir` profile can push template storage over the limit, so build with the `deploy` profile from the outset.

Test surface, in the style of the existing `test/access/` suites: the exclusive lender deposits; every other address is refused; refusal survives the borrower granting roles, adding a permissive pull provider, and creating a provider via factory; transfers outside the allowed set revert in both directions; `requiredFlags` cannot be configured off; wrapper deployment behaves as intended for the chosen S2 option; the `nukeFromOrbit` interaction is asserted explicitly rather than discovered.

### Phase 2 — registration ceremony (protocol; blocked on Phase 1)

Additive registration, following the established v2.5 rollout path (`script/deploy/v2-5/05-owner-actions.s.sol`, which is the current registrar — the older `DeployPeriodicTermHooksV21.sol` is marked deprecated and fails if run). Sequence: Sepolia fork rehearsal, Sepolia, mainnet fork rehearsal, then mainnet in plan mode, which emits a Safe transaction bundle rather than broadcasting, because the `HooksFactory` owner is the ArchController owner and on mainnet that is the Foundation Safe.

Two scope items that are easy to miss:

- **Register on both factory kinds.** `HooksFactory` and `HooksFactoryRevolving` keep completely independent template registries, and a hooks instance minted by one can never be used by the other (`IHooks.factory` is fixed to `msg.sender` at construction). The v2.5 rollout registers each of the three existing templates on both, six calls in total. Mainnet currently runs only the standard factory with two templates registered (`OpenTermHooks`, `FixedTermHooks`, protocol fee 500 bips), so a mainnet-only rollout is one call — but Sepolia and any future revolving deployment need the pair.
- **Off-chain integration is part of the work, not after it.** `MarketLens` is redeployed as part of a template rollout, and `wildcat.ts`, `subgraph` and `wildcat-app-v2` all need to recognise the new template or the market renders as an unknown type. This is concrete rather than hypothetical: `PeriodicTermHooks` carries a separate `templateVersion()` alongside `version()` specifically because the subgraph matches templates on the exact `version()` string. Scope it with Phase 1.

### Phase 3 — tranche factory verification (this repo; blocked on Phase 2)

The provenance check from §4.2 plus the CREATE2 binding from §6.3, gated behind a per-facility flag so a facility on a non-exclusive market can still be deployed with Phase 0's telemetry and halt rather than being blocked outright. Existing markets keep the Phase 0 treatment permanently; there is no retrofit.

### Phase 4 — optional, S2(ii)

Direct market-token custody, `transfersDisabled = true`, valuation core against `scaleFactor`. Only worth doing as part of a tranche-layer v2 undertaken for other reasons.

---

## 8. What this does not fix

- **Existing markets, ever.** `HooksConfig` is `immutable` on the market with no setter. Every currently deployed market is permanently in Phase 0 territory. Given that the tranche layer has not yet been audited or placed, this is much less painful now than it will ever be again — which is an argument for settling S1 and S2 before the first facility rather than after.
- **Protocol fees.** Accepted as facility terms (§6.5).
- **A borrower running two markets on the same credit.** Exclusivity is per market. Two exclusive markets on one borrower are two facilities against one credit, which is an underwriting and covenant question, not something a hook can see.
- **Borrower conduct generally.** Exclusivity removes one specific unilateral lever. The borrower still sets APR, capacity, reserve ratio and grace, and still decides whether to repay. That is the Wildcat model, and the tranche layer's answer to it is the waterfall and the wind-down trigger, not the access policy.
