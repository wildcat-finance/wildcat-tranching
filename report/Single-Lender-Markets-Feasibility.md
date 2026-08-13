# Single-Lender Markets for Tranche Facilities — Feasibility & Roadmap

*Wildcat's in-house tranching product issues a senior and a junior claim over a position in a Wildcat credit market. Because Wildcat markets treat all lenders equally, a tranche set deployed against an ordinary market does not make the senior claim senior over the facility — it makes it senior only over the tranche vehicle's own share of a pool it competes in. This report assesses a proposal to fix that by requiring such markets to have exactly one lender, enforced in Wildcat's hooks system. It is written to be read without prior briefing: §1 establishes the system, §2 states the proposal, and everything after that is analysis.*

*Protocol facts are cited against `wildcat-finance/v2-protocol` at `release/v2.5` (commit `dec36d2`) unless marked V1, which refers to `wildcat-finance/wildcat-protocol`. Tranche-layer facts are cited against this repository at `800c0eb`. Line references are of the form `File.sol:123`.*

---

## Summary of findings

1. **The problem is real and is currently unaddressed.** Wildcat markets pay lenders strictly pro-rata with no notion of rank. A tranche set on a shared market subordinates junior to senior only *within the vehicle's slice*; against every other lender in the market, both classes are ordinary equals. The tranche layer's own design record rules out two tranche sets on one market for exactly this reason but never generalises the argument to the market's other lenders (§3).

2. **The hooks system is the right place to fix it.** Hooks in Wildcat v2 are purely restrictive by design — they can veto a market action but not alter it. An exclusivity rule only ever vetoes, so it needs no change to market bytecode. Critically, a hooks template can force its own enforcement points to be active regardless of what the borrower requests, which is what makes the guarantee structural rather than a configuration (§4).

3. **No configuration of the deployed templates can achieve it.** Four independent paths admit an additional lender, and the borrower controls all four. Two of them require no borrower transaction at all (§5).

4. **The proposal is V1-shaped.** Wildcat V1 held an enumerable list of authorised lenders with a count, so "does this market have exactly one lender?" was a single call. V2 replaced that list with pluggable credential providers and, in doing so, removed the list. The rule as proposed asks a V1 question of a V2 system (§6).

5. **That diagnosis yields the recommended design.** The replacement template should carry the V1-style list as its own state rather than attempt to police V2's credential machinery. Doing so makes it a strict superset of today's borrower-approved behaviour — an ordinary whitelist for ordinary borrowers, a lock at one lender when exclusivity is declared — and makes the proposed rule directly expressible (§9).

6. **Replacing the existing template is worth doing but cannot carry the guarantee alone.** Disabling a hooks template blocks new *instances* of it, not new *markets*: an instance is a durable market factory, so every borrower already holding one keeps deploying markets under the old rules afterwards. Three deployed templates share the permissive behaviour, not one. The guarantee therefore has to be asserted where a tranche set is created, in addition to the swap (§7.3).

7. **Detecting "is this a tranche vehicle?" inside the hook is unsound.** The rule as proposed arms only when a whitelist momentarily holds exactly one lender, so authorising several lenders first defeats it; and detection is evadable by interposing a holder contract. Both problems disappear if the borrower simply declares exclusivity at market creation and the tranche factory verifies it (§7.4).

8. **The strongest form of the guarantee is incompatible with the ERC-4626 wrapper the tranche layer depends on.** Wildcat's wrapper factory refuses to deploy a wrapper against a transfer-disabled market. Choosing airtight exclusivity therefore reopens a previously settled architectural decision about how the tranche vehicle holds its position. This is the largest open question in the report (§9.4).

9. **Nothing can be retrofitted to a deployed market.** A market's hooks configuration is immutable. Existing markets can only be served by tranche-layer measures — dilution telemetry, a deployment precondition, a deposit halt, and accurate language — which require no protocol change and can ship independently (§10, Phase 0).

---

## 1. Orientation

This section exists so the rest can be read cold. Readers familiar with Wildcat v2 and the tranching prototype can skip to §2.

### 1.1 Wildcat markets

Wildcat is an undercollateralised on-chain credit protocol. A **borrower** — a legally identified entity — deploys a **market** against an asset such as USDC. **Lenders** deposit that asset and receive a market token in return; the borrower draws the deposits and pays interest set by parameters the borrower controls (APR, capacity, a reserve ratio, a delinquency grace period). The market token rebases: a lender's claim grows through a monotonically increasing `scaleFactor`, so a lender's balance is stored as a *scaled* amount and multiplied by the current factor to obtain what they are owed.

Withdrawals are not instant. A lender queues a withdrawal, which joins a time-limited **batch**; when the batch expires it is paid out of whatever liquidity the market has, and any shortfall rolls into a FIFO queue of unpaid batches to be filled by later repayments.

Two properties matter throughout this report:

- **All lenders rank equally.** Within a batch, each lender is paid strictly in proportion to their share of that batch. There is no seniority, tier, or priority between lenders.
- **The borrower controls who may lend.** Access is enforced by a hooks contract (§1.2), and the borrower configures it.

A separate protocol-level contract, the **ArchController**, maintains registries of approved borrowers, deployed markets, and the factories permitted to create them. **Wildcat Labs** builds the protocol and the **Wildcat Foundation** holds the privileged owner role on the ArchController; both are bound to neutrality with respect to individual facilities, which is a live constraint on several options in this report.

### 1.2 The hooks system

In Wildcat v2, market policy is externalised into a **hooks contract**. The mechanism has three levels, and keeping them distinct is essential to reading §7:

| Level | What it is |
|---|---|
| **Template** | A stored blob of contract creation code, registered on a factory by the Foundation. Defines a *kind* of policy. Three exist: `OpenTermHooks`, `FixedTermHooks`, `PeriodicTermHooks`. |
| **Instance** | A live contract deployed from a template by a borrower. Belongs to that borrower permanently. **One instance can serve unlimited markets.** |
| **Market's configuration** | A single immutable word on the market holding the instance's address plus one bit per hook indicating whether that hook is called. Fixed at market creation, forever. |

When a lender deposits, transfers, or queues a withdrawal, the market calls the corresponding hook on its instance *if the corresponding bit is set*. The protocol's documentation states the model's limit plainly: hooks "can not modify internal behavior of the market and do not have any privileged access to its state; rather, they are designed to be *reactive to* and *restrictive of* market actions" (`docs/hooks/How Hooks Work.md`). A hook can refuse an action. It cannot redirect one.

Access control in all three shipped templates is credential-based. Rather than a list of permitted lenders, the borrower registers **role providers** — external contracts that vouch for addresses. Providers come in two flavours: *push* providers call the hooks contract to grant a credential, and *pull* providers are queried by the hooks contract when a lender acts. Credentials carry expiry times. This machinery is flexible by design: it accommodates Merkle allowlists, soulbound tokens, and third-party attestation schemes.

### 1.3 The tranching prototype

This repository holds a prototype, not a deployed product. It is unaudited and has not taken capital.

A **`TrancheController`** holds a position in one Wildcat market and issues two token classes against it: **senior** (`sr-`), which has a priority claim on value, and **junior** (`jr-`), which absorbs losses first. A **`TrancheFactory`** deploys one controller per market. Losses are recognised only when realised, and redemption is asynchronous, routed through the market's own withdrawal queue senior-first.

The controller currently holds its position indirectly, through Wildcat's audited **ERC-4626 wrapper** — a contract that converts the market's rebasing token into a fixed-quantity share token. The entire valuation core of the tranche layer (its price watermark, its behaviour while the market is delinquent, its redemption sizing) is written against wrapper shares. Reusing that audited wrapper rather than handling rebasing directly was a deliberate risk-reduction decision, recorded as Q1 and reaffirmed as Q18 in `Design-Risk-Specification.md`. Those Q-numbers are referenced below where relevant; each is a numbered design decision in that document with its alternatives and rationale.

**The subordination is internal to the controller.** Senior's priority is a rule the controller applies when distributing what the controller receives. The market knows nothing about it.

---

## 2. The proposal under assessment

The proposal, stated in full:

> A tranche facility works best when the market it sits on has exactly one lender — the tranche controller — using a market whose access policy is borrower-approval. The problem is that the borrower can subsequently approve others. So replace the borrower-approval hook with one that says: if there is already one approved address, and it happens to be a tranche controller, no further addresses may be approved. This would mean deregistering the existing borrower-approval hook. Markets already deployed would remain able to host a tranche set under the old rules, which is accepted.

Three distinct claims are in play, assessed separately below:

- **(a)** A hook can enforce that a market with a single tranche-controller lender admits no others. → §7.1, §7.2, §7.4
- **(b)** Achieving this going forward requires deregistering the existing borrower-approval template. → §7.3
- **(c)** Existing markets are grandfathered under the old behaviour. → correct and unavoidable; see immediately below.

**(c) is settled by the architecture.** A market's hooks configuration is `immutable`, assigned once in the constructor (`WildcatMarketBase.sol:59`, `:236`), and no setter exists anywhere in `src/market/`. Neither the instance address nor the per-hook bits can change after deployment. **No protocol change can ever alter the behaviour of an already-deployed market.** This is not a limitation of the proposal; it is a fact that constrains every option in this report, and it is why §10 separates measures that help existing markets from measures that only apply to new ones.

---

## 3. Why the problem matters

### 3.1 The mechanism

Wildcat pays lenders in proportion to their share of a withdrawal batch, and nothing else:

```solidity
// src/market/WildcatMarketWithdrawals.sol:265-269
uint128 newTotalWithdrawn = uint128(
  MathUtils.mulDiv(batch.normalizedAmountPaid, status.scaledAmount, batch.scaledTotalAmount)
);
```

The only ordering the market recognises is temporal: earlier batches drain before later ones from a FIFO queue (`WildcatMarketWithdrawals.sol:353`), and amounts already processed but not yet collected outrank everything. Who a lender *is* has no bearing on what they receive.

For a market with a single pooled lender this is exactly the right property, because it means all subordination logic can live inside the tranche controller. For a controller sharing a market, it means the market's pro-rata split happens *before* the controller's waterfall runs. The waterfall then allocates only what arrived.

The tranche layer's design record already contains this argument, applied to a narrower case. `Design-Risk-Specification.md` Q20 prohibits two concurrent tranche sets on one market because "at the market layer, two controllers are pari-passu lenders whose withdrawal claims fill pro-rata from the same batches. Under stress, one set's *senior* would compete on equal footing with another set's *junior* for the same cash." Substitute "any other lender in the market" for "another set's junior" and the argument holds unchanged — and the general case is the more pressing one, because other lenders are not an unusual event. They are the normal state of every market Wildcat has deployed.

### 3.2 Two harms, and the one that binds sooner

**Economic.** Let the controller hold fraction *f* of the market's scaled supply. On a shortfall the market pays the controller *f* × recovery; only then does the senior/junior waterfall apply. Junior's first-loss cushion absorbs losses on the controller's slice and does nothing about the other lenders drawing on the same batch liquidity. On a facility with a 20% junior cushion where the controller is 30% of the market, senior is protected against the first 20% of loss on its own slice and is otherwise an ordinary pro-rata lender.

**Disclosure.** This binds whether or not a loss ever occurs, and is the more immediate exposure. The instrument is named `sr-` and described as senior throughout the product material. A credit allocator or compliance function reading "senior tranche" will understand seniority over the facility, because that is what the term means in credit generally. On a shared market it means seniority over a portion of the facility whose size depends on who else has deposited — a quantity that changes without the senior holder's knowledge or consent, and which the borrower alone controls. Senior's protection is not merely thinner than the name implies; it is **non-stationary**, and no part of the current stack surfaces it.

The second harm is the reason §10 places telemetry, a deployment precondition, and language changes in Phase 0, ahead of any protocol work: those apply to markets that already exist and require no coordination with the Foundation.

### 3.3 Why borrower restraint is not a substitute

A market can be deployed with the controller as its only approved lender today; nothing then prevents the borrower approving others, nothing announces it, and there is a standing incentive to do it. A borrower who has placed a tranche facility and wants further capacity will find approving a direct lender faster and cheaper than raising additional junior capital. The dilution need not be adversarial to occur — it is the path of least resistance. Relying on restraint for the property the instrument is named after is the specific thing to avoid.

---

## 4. What v2.5 already provides

Several of the primitives an exclusivity rule needs are already in the protocol.

**Hooks are purely restrictive, which matches the requirement exactly.** An exclusivity rule only ever refuses. It needs no new market bytecode, no state access, and no exception to the hooks model. The tranche layer's own effort assessment anticipated this in passing: "Hooks can assist (for example, restricting a market so only the tranche vault may deposit), but that is optional" (`Wildcat-Tranching-Effort-Assessment.md:64`).

**A template can force its own enforcement points to be active.** This is the load-bearing fact for feasibility and it is not obvious from the outside. Each template declares an *optional* and a *required* set of hook flags, and a market's final configuration is computed as `final = (borrowerRequested AND optional) OR required`:

```solidity
// src/types/HooksConfig.sol:141
let mergedFlags := and(0xffff, or(and(configFlags, _optionalFlags), _requiredFlags))
```

A flag in `requiredFlags` is switched on regardless of what the borrower asked for. All three shipped templates leave the deposit and transfer hooks *optional*, which means a borrower can deploy an `OpenTermHooks` market today with both gates off and obtain a fully permissionless market. A template that places the deposit, transfer, and queue-withdrawal flags in `requiredFlags` cannot be configured out of its own invariant: the guarantee lives in the template's immutable configuration and in the merge logic above, neither of which the borrower can reach.

**A market-wide transfer prohibition already exists.** A `transfersDisabled` flag is read once from deployment data at market creation, has no setter anywhere in `src/`, and makes every transfer hook call revert unconditionally (`OpenTermHooks.sol:338-340`).

**There is precedent for one contract querying a hooks instance about a market's policy.** `IMarketTransferPolicy.isMarketTransferDisabled(market)` exists for that purpose, and its documentation frames the answer as a forward commitment: "A `false` response is a compatibility promise that the hook will not later transition the market to a universally transfer-disabled state." An exclusivity assertion needs the same interface shape, and this one is already consumed in production by the wrapper factory.

**The sanctions path does not create an additional holder.** In v2.5, quarantining a sanctioned lender queues an ordinary withdrawal in that lender's own name rather than moving market tokens to an escrow contract (`WildcatMarket.sol:307-335`); the escrow receives the underlying asset later, at execution. An analysis based on pre-v2.5 behaviour would have concluded otherwise.

**All transfers pass through one point.** Both `transfer` and `transferFrom` reach `_transfer`, whose only gate is the transfer hook (`WildcatMarketToken.sol:89`), called before balances move.

**The market already has a "single special address, set once, immutable" pattern.** `registeredWrapper()` is a dedicated storage slot writable only by the wrapper factory and only once (`WildcatMarketConfig.sol:65-70`). A per-market exclusivity declaration has the same shape.

---

## 5. Why no deployed configuration closes the gap

Four independent paths admit an additional approved lender. The borrower controls all four, and two require no borrower transaction.

1. **The borrower is a permanent credential provider.** The shared access-control base registers the borrower as a push provider with a maximum-value expiry in its constructor (`BaseAccessControls.sol:94-105`). The borrower can therefore credential any address at any time, indefinitely.
2. **Adding providers is unconditional.** `addRoleProvider` is borrower-only and has no cap, no seal, and no one-way freeze (`:165-167`). A borrower who removes every provider, including themselves, can re-add themselves in the next block.
3. **Pull providers credential arbitrary addresses with no borrower transaction.** When a lender acts without a live credential, the hooks contract loops every registered pull provider and accepts the first acceptable timestamp returned (`_loopTryGetCredential`, `:640-652`). One permissive pull provider silently reopens the market.
4. **The "known lender" flag is sticky and never cleared.** It is set on first deposit *and* on receiving a transfer while credentialed (`:806-815`), and no code anywhere in `src/` ever sets it back to false. In the transfer hook it short-circuits the entire access-control block, including the borrower's own block-list (`OpenTermHooks.sol:343-345`). Once an address has been a lender on a market it can receive market tokens forever — after its credential is revoked, and after being blocked.

Point 4 is why counting *currently credentialed* addresses is worthless. Revoking lender A and credentialing lender B leaves A holding tokens, still accruing interest, with a permanent route to receive more. **Any correct invariant must be monotonic over the market's entire history, not a snapshot.**

And there is nothing to count in any case. V2 has no lender set, no lender counter, and no enumerable holder list: accounts are a bare mapping, market state tracks only aggregates, and the known-lender flag has no counter and no removal.

---

## 6. The proposal is V1-shaped, and V2 removed the list

This explains why the rule seems as though it should be a one-line change and is not.

In V1, the lender whitelist was a genuine enumerable set held on the market controller:

```solidity
// V1: src/WildcatMarketController.sol:78
EnumerableSet.AddressSet internal _authorizedLenders;
```

with `authorizeLenders` and `deauthorizeLenders` (`:221`, `:308`), `isAuthorizedLender` (`:210`), `getAuthorizedLenders()` (`:189`), and — the relevant one — `getAuthorizedLendersCount()` (`:206`). Authorisation was *pushed* into each market by the controller: `WildcatMarket(market).updateAccountAuthorizations(lenders, _authorizedLenders.contains(lender))` (`:334-337`).

In that architecture, "does this market have exactly one whitelisted lender?" is literally `getAuthorizedLendersCount() == 1`, and the proposed rule is a small, natural addition.

V2 replaced the set with the role-provider credential model described in §1.2. The trade bought composable credentialing and **paid for it by removing the list**. There is no set to count, and credentials can now come into existence without the borrower acting at all (§5, item 3).

That diagnosis points directly at the fix, and it is a better fix than a bespoke single-lender slot: **have the replacement template carry the V1-style list as its own state** (§9.1).

**One V1 property carries over and constrains the rule.** In V1, de-authorising a lender removed it from the set but did nothing about market tokens it already held — V1 retained a withdraw-only role precisely because a de-authorised lender still has a claim to exit. The same holds in V2. A lock keyed on *current* membership is therefore defeated by de-authorise-then-authorise: the count returns to one, the lock re-arms, and the earlier holder remains an equal-ranking claimant. **The count must be of admissions ever granted, never of members currently held.**

---

## 7. Assessment of the proposal

### 7.1 The control point should be the deposit, not the approval

Policing the credential machinery means intercepting credential grants, batch grants, provider additions, provider creation, and the pull-provider query loop — and then still handling the sticky known-lender flag from §5. Each is a separate override with its own bypass analysis, and the pull-provider loop is the awkward one, because it grants credentials inside a shared internal routine with no distinct entry point to guard.

Enforce at the point of use instead: hold an explicit lender list as the template's own state, and have the deposit hook refuse any depositor not on it. Credentials then become **irrelevant to the guarantee** — the borrower may register providers and credential the entire world without producing a second market-token holder, because the deposit hook does not consult credentials when deciding. One assertion, in one place, on the action that actually creates a claim. This also matches §5's conclusion that the invariant can only be prospective, since there is no stored state to audit it against.

### 7.2 The hook should not be taught what a tranche controller is

The proposal conditions the restriction on the approved address *being* a tranche controller. The dependency should point the other way: the hook enforces **exclusivity** as a self-contained property — "this market has admitted exactly one lender and can never admit another" — and the tranche factory *checks for* that property before deploying a set. §7.4 gives the decisive argument. Three supporting ones:

- **Layering.** A hooks template that consults a tranche-controller registry couples the protocol's release cycle to a product's. The dependency already runs the correct direction elsewhere: the wrapper factory consumes `IMarketTransferPolicy`, not the reverse.
- **Reusability.** "This market has one lender and always will" is a useful primitive independent of tranching — bilateral facilities, single-counterparty structures, a fund lending against one borrower. A general primitive is much easier to justify registering than a product-specific one.
- **Neutrality.** Wildcat Labs and the Foundation are bound to neutrality, and `Deployment-Access-Governance-Notes.md` §1 already rejected an owner-gated tranche factory on that ground. A protocol template that names one product is the same problem in a more permanent location.

**Verification must check where the instance came from, not merely what it says.** If the tranche factory only asks a market's hooks instance whether it is exclusive, a borrower can supply a contract that answers correctly and enforces nothing. The instance *is* the enforcement, so provenance is the thing to verify:

```
market.factory()                                     // immutable, WildcatMarketBase.sol:68
market.hooks()                                       // top 160 bits = instance address
  → factory.getHooksTemplateForInstance(instance)    // public mapping, HooksFactory.sol:92
  → assert template ∈ {allowlisted exclusivity template addresses}
  → assert market is declared exclusive and admissionsEverGranted == 1
  → assert the single listed lender is this controller
```

Three details determine whether this check is sound:

- **Resolve the factory from the market rather than hardcoding it.** Two factory kinds exist — `HooksFactory` and `HooksFactoryRevolving` — with entirely independent template registries, and historical factory generations remain registered on the ArchController indefinitely. The instance-to-template mapping is per-factory storage, so querying the wrong factory returns zero.
- **Allowlist template addresses, not version strings.** The mapping returns the template's stored-creation-code contract address, which is an identity. The tempting shortcut is `IHooks.version()`, which returns a literal such as `'OpenTermHooks'` — but that string is supplied by the instance itself, so a hostile instance can return anything. It is a labelling aid used by the lens for display (`HooksConfigData.sol:71-81`); the template address is the authenticated primitive.
- **Market registration is revocable.** The ArchController has both `removeMarket` and `removeBorrower`. The registration check the tranche factory already performs is a point-in-time assertion, not a standing guarantee. Worth knowing; not worth engineering against.

### 7.3 Replacing the existing template is reasonable, and insufficient

The proposal's intent is a **swap, not an amputation**: the standard borrower-approval hook is replaced by one that behaves identically except for the lock. If the replacement is a strict superset of current behaviour — an ordinary whitelist for ordinary borrowers, plus a lock that arms only when exclusivity is declared — then disabling the old template removes no capability from future borrowers, and the obvious objection does not apply. §9.1 describes a template of that shape, and it is a better design than a tranche-specific variant would be.

Two facts nevertheless mean the swap cannot carry the guarantee by itself.

**Disabling a template is not a chokepoint on market creation.** The `enabled` flag is consulted only when deploying a new hooks *instance* (`HooksFactory.sol:358`). Market deployment never reads it:

```solidity
// src/HooksFactory.sol:601-605
address hooksTemplate = getHooksTemplateForInstance[hooksInstance];
if (hooksTemplate == address(0)) {
  revert HooksInstanceNotFound();
}
HooksTemplate memory templateDetails = _templateDetails[hooksTemplate];
```

Because an instance is a durable market factory rather than a per-market artifact, every borrower who already holds an `OpenTermHooks` instance — which is every borrower with a live market — continues deploying **new** markets under the old rules after the swap. This is distinct from the grandfathering in §2(c): it is that template disablement does not deliver "going forward". It closes the door only to borrowers who do not already hold a key.

**Three templates share the permissive behaviour, not one.** `OpenTermHooks`, `FixedTermHooks`, and `PeriodicTermHooks` all inherit the same access-control base and all permit unlimited credentialing. Mainnet currently has the first two registered. Replacing only the open-term template leaves the fixed-term route open — and fixed-term is arguably the better fit for a tranche facility, since a senior instrument with a defined term wants a market with one. A complete swap means three replacements, or a lock retrofitted into the shared base, which is option B in §8 and a substantially larger audit surface.

Two further properties of disablement, relevant if it is used as a cleanup tool: it is irreversible — "The template is only disabled, not removed: `exists` stays true, so it can not be re-added and there is no re-enable path" (`HooksFactory.sol:250-252`) — and it is soft in other respects, since fee updates and protocol-fee pushes continue to work on a disabled template, which also remains in the enumerable template list permanently.

**Conclusion: swap *and* check.** Register the new template additively, as every template rollout has been; disable the old ones if the replacement is a superset and the Foundation wishes to move the default; *and* have the tranche factory assert exclusivity when a set is created. The swap makes the correct configuration the default and the easy path. The consumer check is what makes it a guarantee. Neither substitutes for the other.

### 7.4 Detection inside the hook is unsound in two ways

The rule as proposed — if there is already one approved address and it happens to be a tranche controller, permit no others — is evaluated at approval time, which creates an **ordering gap**. If the borrower approves five lenders first and deploys the tranche set afterwards, there is never a moment at which the whitelist holds exactly one address, so the lock never arms. The market ends up with a tranche set and five equal-ranking co-lenders, every rule having behaved exactly as written.

Second, any hook-side attempt to *detect* that an address is a tranche controller is **evadable by interposition**, because the borrower chooses what to approve. Approve a thin holder contract that is not a registered controller and let the controller hold claims on that instead — precisely the relationship the ERC-4626 wrapper already has with the market — and the lock never arms again. Detection can be made costly but not sound, because the borrower controls the detector's input.

Both problems disappear at the tranche layer, where the question is asked in the other direction and at the right moment: at set creation, assert that the market's admission count is one and that the single admitted lender is this controller. The factory knows which controller it is deploying, so there is nothing to detect and nothing to spoof.

---

## 8. Design options

| | Option | Guarantee | Cost | Helps existing markets |
|---|---|---|---|---|
| **A** | **New template carrying an explicit lender list** (recommended) | Hard. No second market-token holder can come into existence | New protocol template, audit, registration | No |
| **B** | One-way lender-set seal on the shared access-control base | Hard, if the seal also covers pull providers | Modifies the contract all three templates inherit; re-audit of the whole access layer | No |
| **C** | Tranche layer only: telemetry, deployment precondition, dilution halt | None. Detection and disclosure, not prevention | Days, in this repository, no ceremony | **Yes** |
| **D** | A, plus transfers disabled and direct market-token custody | Airtight: provably one holder for the market's life | A, plus rewriting the tranche valuation core | No |

**B** merits an explanation of why it loses to **A** despite being more broadly useful. A one-way seal, after which no provider can be added and no credential granted, would work with all three existing templates and is a genuinely useful primitive. But it modifies the contract every deployed hooks instance inherits, so the audit surface becomes the entire access layer rather than one new leaf, and the pull-provider path must be neutralised inside a shared internal routine without disturbing credential semantics that live markets depend on. A new leaf template is strictly less risky for the same product outcome. If the seal is wanted for its own sake, it is separate work with a separate justification.

**C is not an alternative to A.** It is what ships first, it is the only option that reaches existing markets, and it addresses the disclosure harm in §3.2 — the harm that exists today.

**D** is the endgame; §9.4 explains why it is not merely a nicety.

Recommended sequence: **C now, A next, D as a deliberate decision when the tranche layer is next revised.**

---

## 9. The recommended mechanism

### 9.1 Shape: V1 whitelist semantics as a V2 template

A new template — `ListedLenderHooks` — inheriting the existing market-parameter-constraint base for APR bounds, but **deliberately not inheriting the credential-based access-control base**. Per §5, the pull-provider loop and the sticky known-lender flag are each independently sufficient to admit a second claimant, so the credential stack should be absent rather than constrained. The template is consequently smaller and its audit narrower than the existing three.

Its state is the V1 list, reintroduced per market:

```solidity
mapping(address market => EnumerableSet.AddressSet) internal _listedLenders;
mapping(address market => uint256) internal _admissionsEverGranted;   // monotonic, per §6
mapping(address market => bool)    internal _exclusive;               // declared at creation
```

The design's principal virtue is that it is a **strict superset** of the borrower-approval flow. A borrower wanting five lenders lists five, and the template behaves like today's `OpenTermHooks` without the pluggable providers. A borrower running a tranche facility declares exclusivity and lists one, after which no second admission is possible. One template, two modes, no product-specific logic — which is also what makes it defensible as protocol surface.

Because the list is real, the count is real, and the proposed rule becomes directly expressible — the thing V2 currently cannot do. Arm the lock on admissions ever granted, never on current membership (§6).

On the "and it happens to be a tranche controller" condition: per §7.4 the hook cannot soundly detect this and does not need to. Let the borrower **declare exclusivity at market creation** — one boolean in the deployment data, immutable thereafter, exactly as `transfersDisabled` already works. A borrower deploying a market for a tranche facility sets it; the tranche factory verifies it. The hook stays product-agnostic, and the guarantee strengthens, because it arms deterministically at creation rather than depending on the order in which lenders are approved.

Hooks, with the deposit, transfer, and queue-withdrawal flags in `requiredFlags` so none can be switched off:

- **Deposit** — refuse unless the depositor is listed for the calling market.
- **Transfer** — refuse unless both sender and recipient are within the market's permitted set (§9.4). Asserting on the sender as well as the recipient means that if a stray balance somehow exists, it cannot move.
- **Queue withdrawal** — refuse unless the lender is within the permitted set. Note the interaction: sanctions quarantine routes through the same internal withdrawal path, so this hook is a veto over quarantine (`WildcatMarket.sol:314-320`, where the comment records this as accepted behaviour). If no stray holder can exist, nothing is stranded — which argues for making stray holders impossible rather than merely immobile.
- **`isMarketTransferDisabled`** — **must** be implemented. The wrapper factory reverts against a hooks instance that does not answer (`Wildcat4626WrapperFactory.sol:102-112`), so omitting it is a compatibility break rather than a hardening.
- **View surface** — admissions count, exclusivity flag, and listed-lender accessor, for the tranche factory to read per §7.2.

Everything else no-ops, as in the existing templates. One line must not be omitted: the creation hook needs `if (deployer != borrower) revert CallerNotBorrower();`. The factory does **not** verify that a hooks instance belongs to the borrower deploying against it — it checks only that the caller is a registered borrower and that the instance is known. That guarantee lives in each template's own creation hook (`OpenTermHooks.sol:140` and equivalents), so a template omitting it would let any registered borrower attach markets to another borrower's hooks instance.

### 9.2 A risk that deserves naming

`docs/Known Issues.md` records that a reverting enabled hook permanently disables the corresponding market function, and classes this as known and unfixable. For an exclusivity template that is *the design* — refusing every non-listed deposit forever is the product. But it also means the template has no recovery path from a defect: the instance is immutable, the market's pointer to it is immutable, and a template that refuses when it should not leaves that market's deposit or withdrawal path dead with no remedy short of closing the market. The existing templates carry the same exposure, but they carry it on paths that mostly permit; this one exists to refuse. That raises the audit bar rather than changing feasibility, and it is a further argument for the narrow, credential-free design above.

### 9.3 Binding the controller's address

The controller must be listable as the market's sole lender, but it does not exist until after the market does, since the tranche factory requires a registered market. `CREATE2` breaks the circle, because a `CREATE2` address depends only on the deploying factory and a salt — not on the market:

1. The borrower computes the controller's future address from the tranche factory and a salt.
2. The borrower deploys the market, declaring exclusivity and listing that address.
3. The borrower calls the tranche factory, which deploys the controller to exactly that address and asserts the provenance chain from §7.2.

Step 3's assertion is what makes the arrangement trustworthy: the factory refuses to create a set whose market does not already list it as sole lender. This preserves the property recorded as Q19 — that one borrower transaction brings up the whole stack — and it fails loudly, reverting at deployment rather than producing a set that is quietly non-exclusive.

The alternative, a one-shot post-creation setter, avoids `CREATE2` but moves the binding after deployment, where the factory can no longer enforce it.

### 9.4 The wrapper conflict — the central architectural trade

The tightest available invariant is to disable transfers outright: no market-token transfer can ever occur, so the sole depositor is provably the only holder for the market's life. **This is mechanically incompatible with the ERC-4626 wrapper**, and the incompatibility is enforced in production code:

```solidity
// src/vault/Wildcat4626WrapperFactory.sol:149
if (_isMarketTransferDisabled(market)) revert MarketTransfersDisabled(market);
```

A transfer-disabled market cannot have a wrapper. And the tranche layer needs one: the controller holds wrapper shares (`realisedValue()` reads `underlyingVault.balanceOf(address(this))`, `TrancheController.sol:187`) and exits by redeeming wrapper shares and then queueing a market withdrawal (`:329-331`) — a wrapper-to-controller market-token transfer that a disabled transfer hook would refuse. As noted in §1.3, the whole valuation core is written against wrapper shares.

Exclusivity therefore forces a choice.

**Option (i) — permitted-pair exclusivity.** Keep the wrapper. The transfer hook permits transfers only within a fixed pair, controller and wrapper, resolved at market creation or on wrapper registration. Exclusivity then closes by derivation rather than by fiat: the wrapper enters the market only by *receiving* market tokens (`Wildcat4626Wrapper.sol:277` — it never deposits), so if only the controller can obtain market tokens, only the controller can ever mint wrapper shares, and no third party can acquire wrapper shares because none can acquire the input.

The cost is that the invariant now rests on a two-step argument rather than a single unconditional refusal, and the wrapper contributes no enforcement of its own — it has no depositor gate, and the safety comes entirely from market-token scarcity. That is sound, but it is exactly the kind of derived property that should be stated as an explicit invariant with a test rather than left implicit for an auditor to reconstruct.

**Option (ii) — transfer-disabled exclusivity.** Drop the wrapper: the controller holds the rebasing market token directly, and the valuation core is rewritten against `scaleFactor`. The invariant becomes one unconditional refusal, with no derivation, no permitted pair, and no wrapper in the trust path. Q1 and Q18 both rejected direct custody, on the grounds that it "rewrites that core against `scaleFactor` and reopens the audited surface for a benefit buyers can't see."

That reasoning deserves revisiting here, because under exclusivity the benefit is no longer invisible. The wrapper's purpose is to give *pooled* lenders a non-rebasing handle. With exactly one holder doing its own accounting, it has no beneficiary; it becomes a moving part retained to preserve a code path. This does not settle the question — reopening a valuation core is a real cost, and the tranche layer is an unaudited prototype, which cuts both ways — but the Q1/Q18 rationale predates exclusivity and should not be treated as having decided it.

Recommendation: build for option (i), which works with the code that exists and does not gate on reopening the valuation core; treat option (ii) as the target state if and when the tranche layer is revised for other reasons.

### 9.5 Residual claimants under either option

| Claimant | Status | Handling |
|---|---|---|
| **Protocol fee recipient** | Ranks ahead of unprocessed lender claims and cannot be blocked. Fee collection is permissionless, has no hook, and accrued fees are deducted before batch liquidity is computed (`MarketState.sol:142-148`, `WildcatMarketWithdrawals.sol:330-332`) | Accepted as facility terms — a servicing fee at the top of the waterfall is standard in structured credit. Disclose it. The invariant is "one *lender*", not "one claimant on assets" |
| **Sanctions escrow** | Not a market-token holder in v2.5 (§4); the claim stays in the sanctioned account's own name | No action. Note the quarantine-veto interaction in §9.1 |
| **Borrower, on market closure** | Receives only surplus over total debts (`WildcatMarket.sol:231-236`), and the closure hook can veto | No action |
| **A second market by the same borrower** | Same credit, two facilities, tranched separately — not a dilution of either | Covenant matter, not a code matter |

---

## 10. Roadmap

### Phase 0 — tranche layer, ships independently (days)

Everything here lives in this repository, needs no protocol change and no Foundation action, and is the **only** tier that reaches existing markets. It addresses the disclosure harm in §3.2.

1. **Dilution telemetry.** A view returning the controller's share of the market's scaled supply. The controller already reads market state for delinquency, so the input is available: compare its economic market-token position against the market's scaled total supply. Surface it wherever senior is described — interface, subgraph, term sheet. A senior buyer should be able to see "this facility is 34% of its market" without asking.
2. **Empty-market precondition at deployment.** One line in `TrancheFactory.deployTranches`: require the market's scaled total supply to be zero. This guarantees no incumbent lenders at the moment a set is created — cheap, unambiguous, and it rules out the worst case of a tranche set placed on top of an existing lender base.
3. **Dilution halt.** If the controller's share falls below a threshold fixed at deployment, close new senior deposits while leaving exits fully live. This mirrors the existing subordination gate — a set that cannot honour its senior claim stops selling senior rather than continuing to sell a diluted one — and respects the established rule that gates apply only where exposure increases, never to exits.
4. **Language.** Until exclusivity is enforceable, "senior" needs a qualifier in buyer-facing material: senior *within the facility*, equal-ranking at the market layer. The cheapest item here and probably the most valuable.

### Phase 1 — the template (protocol repository)

`ListedLenderHooks` per §9.1, with tests and an entry in the audit-delta record. Calibrating against `PeriodicTermHooks`, the closest precedent as a template added during v2.5 and rolled out additively: roughly 800 lines of contract, 1,800 lines of tests, and a runtime size of 17,978 bytes against the 24,576-byte limit. The new template should be materially smaller, since it omits the credential base — but size remains a live constraint, and the repository's own notes record that the high-optimisation build profile can push template storage over the limit, so use the deployment profile from the outset.

Test surface, in the style of the existing access-control suites: the listed lender deposits; every other address is refused; refusal survives the borrower granting credentials, adding a permissive pull provider, and creating a provider through a factory; transfers outside the permitted set revert in both directions; required flags cannot be configured off; wrapper deployment behaves as intended for the chosen option in §9.4; and the sanctions-quarantine interaction is asserted explicitly rather than discovered.

### Phase 2 — registration (protocol; after Phase 1)

Additive registration following the established v2.5 rollout path (`script/deploy/v2-5/05-owner-actions.s.sol` is the current registrar; the older `DeployPeriodicTermHooksV21.sol` is marked deprecated and fails if run). Sequence: Sepolia fork rehearsal, Sepolia, mainnet fork rehearsal, then mainnet in plan mode, which emits a Safe transaction bundle rather than broadcasting, because the factory owner is the ArchController owner and on mainnet that is the Foundation Safe.

Two easily-missed scope items:

- **Register on both factory kinds.** The standard and revolving factories keep entirely independent template registries, and an instance minted by one can never be used by the other, since a hooks contract fixes its factory at construction. The v2.5 rollout registers each existing template on both. Mainnet currently runs only the standard factory with two templates registered, so a mainnet-only rollout is a single call — but Sepolia and any future revolving deployment need the pair.
- **Off-chain integration is part of the work.** `MarketLens` is redeployed as part of a template rollout, and `wildcat.ts`, `subgraph`, and `wildcat-app-v2` all need to recognise the new template or the market renders as an unknown type. This is concrete rather than hypothetical: `PeriodicTermHooks` carries a separate `templateVersion()` alongside `version()` specifically because the subgraph matches templates on the exact `version()` string.

### Phase 3 — tranche factory verification (this repository; after Phase 2)

The provenance check from §7.2 plus the address binding from §9.3, behind a per-facility flag so that a facility on a non-exclusive market can still be deployed with Phase 0's telemetry and halt rather than being blocked outright. Existing markets keep the Phase 0 treatment permanently.

### Phase 4 — optional

Direct market-token custody, transfers disabled, valuation core rewritten against `scaleFactor` (option (ii) in §9.4). Worth doing only as part of a tranche-layer revision undertaken for other reasons.

---

## 11. What this does not fix

- **Existing markets, ever.** A market's hooks configuration is immutable, so every deployed market remains permanently in Phase 0 territory. Because the tranche layer is not yet audited or placed, this is less costly now than it will ever be again — which argues for settling the open questions below before the first facility rather than after.
- **Protocol fees.** Accepted as facility terms (§9.5).
- **A borrower running two markets against the same credit.** Exclusivity is per market. Two exclusive markets under one borrower are two facilities against one credit, which is an underwriting and covenant question, not something a hook can observe.
- **Borrower conduct generally.** Exclusivity removes one specific unilateral lever. The borrower still sets APR, capacity, reserve ratio, and grace period, and still decides whether to repay. That is the Wildcat model, and the tranche layer's answer to it is the waterfall and the wind-down trigger, not the access policy.

---

## 12. What needs deciding, and by whom

Owners below are: **Desk** — whoever is commercially responsible for placing the facility and setting its terms; **Foundation** — the holder of the ArchController owner role, which is the only party able to register or disable a hooks template; **engineering** — whoever builds the template and the tranche-layer changes.

| # | Decision | What hangs on it | Owner |
|---|---|---|---|
| S1 | **Is exclusivity a product requirement or a product option?** If senior is sold as senior, it is a requirement and Phase 1 gates the first facility. If it is a per-facility disclosure, Phase 0 alone ships | Whether a protocol change blocks the first placement | Desk + Foundation |
| S2 | **Custody model under exclusivity** (§9.4): permitted-pair exclusivity keeps the ERC-4626 wrapper and the audited valuation core; transfer-disabled exclusivity is airtight but forces direct custody and a rewrite of the valuation core | The largest engineering fork in this report. Phase 1's scope roughly doubles under the second option | Desk + engineering |
| S3 | **Foundation appetite for the template, and whether it supersedes the existing ones.** Registration is a routine owner action. The open question is scope: register alongside, or also disable `OpenTermHooks` — and for a complete swap, `FixedTermHooks` too, since it has the same permissive behaviour (§7.3) | Blocks Phase 1 entirely; there is no way to do this from the tranche side | Foundation |
| S4 | **How exclusivity is triggered** (§7.4, §9.1). Recommendation: a borrower-declared flag at market creation, immutable thereafter, rather than the hook detecting controller-ness | Shapes the template's interface. Cheap now, expensive later | Foundation + engineering |
| S5 | **Dilution threshold and whether the halt is advisory or hard** (§10, Phase 0) | Needed for Phase 0, the only tier available to existing markets | Desk, per facility |

Settled by this analysis, with no decision left: replacing the borrower-approval template is worth doing but is not a chokepoint on market creation, so the tranche factory must assert exclusivity as well (§7.3, §7.4); the replacement carries its own explicit lender list rather than policing V2 credentials, whose four bypasses cannot be closed from outside (§5, §6, §9.1); the lock keys on admissions ever granted, never on current membership (§6); protocol fees remain senior and are accepted as facility terms (§9.5); and no change of any kind reaches an already-deployed market (§2).
