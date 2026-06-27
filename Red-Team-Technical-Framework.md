# Wildcat Tranching: Technical Framework for Red-Team Review

This document is written for an autonomous agent (or security engineer) tasked with adversarially reviewing the Wildcat in-house tranching layer. It describes the system precisely, states the properties that must hold, names the trust boundaries and external dependencies, and lists the specific weaknesses worth probing. It is deliberately candid about where the conservative-but-imprecise behaviour lives, so review effort goes where it matters.

The target is the Solidity code under `build/src/`. Treat everything below as the as-built specification, then try to break it.

---

## 1. Mission and rules of engagement

**Goal:** find any way that one party can take value it is not owed, that an invariant can be violated, that funds can be permanently stranded, or that the loss/priority ordering can be subverted. Economic and mechanism-level attacks count, not only memory-safety bugs.

**In scope:** `TrancheController.sol`, `WaterfallMath.sol`, `TrancheToken.sol`, `TrancheFactory.sol`, `interfaces/IExternal.sol`, and the economic model they implement.

**Assume as given (out of scope to re-audit, in scope to challenge the *assumptions* about):** the Wildcat market, the ERC-4626 wrapper (`v-wmtUSDC`), USDC, the sanctions sentinel, and the arch controller. You should not audit their internals, but you *should* test what happens to the tranche layer if any of them behaves at the edges of its documented interface.

**Deliverable:** for each finding, state the attacker, the precondition, the exact call sequence, the invariant or party harmed, and the magnitude. Use the severity rubric in section 16.

---

## 2. Build and run

Foundry project rooted at `build/`.

```
cd build
FOUNDRY_DISABLE_NIGHTLY_WARNING=true ~/.foundry/bin/forge test
FOUNDRY_DISABLE_NIGHTLY_WARNING=true ~/.foundry/bin/forge test --match-contract ForkTest -vvv
```

- `forge-std` and `solady` are vendored under `build/lib` (remapping `solady/=`).
- Fork RPC: `https://eth-main.hinterlight.net`.
- Live contracts: wrapper `v-wmtUSDC` = `0xF65460B84c13eeb911303336Ab0f9D63CC79839f`; its market is read via `wrapper.market()`; USDC = `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`.
- The reference Wintermute market behind the wrapper is the ~$69.65M, 8.5% APR facility. A second, smaller market exists at `0x50ebdf73a0df61b782cea489e8102b3bfde0bda6` and is a different facility.

Reach for fork tests when an attack depends on real market mechanics (withdrawal-queue semantics, `convertToAssets` behaviour, packed `MarketState` decoding). Reach for the mock suite when you need to drive prices, delinquency, and time directly.

---

## 3. System overview

The tranching layer is a lender-side vault layered on top of an unchanged Wildcat market. The market is undercollateralized private credit: a named borrower owes USDC, lenders hold a rebasing claim, and exits run through a batched withdrawal queue. Wildcat already wraps the rebasing claim into a non-rebasing ERC-4626 token, `v-wmtUSDC`. The tranche controller holds `v-wmtUSDC` and issues two claims against it.

```
USDC  ->  Wildcat market (wmtUSDC)  ->  ERC-4626 wrapper (v-wmtUSDC)  ->  TrancheController  ->  sr-/jr-wmtUSDC
        rebasing credit token        non-rebasing share              holds + waterfall      two tranche tokens
```

| Contract | Role |
|---|---|
| `WaterfallMath` | Pure functions: senior accrual, value/loss split, subordination math, ToU default predicate. No state. The economic core. |
| `TrancheController` | The brain. Holds the wrapper shares, runs deposits, the async redemption queue, valuation, default detection and wind-down, subordination gating, sanctions/escrow, and bounded governance. `ReentrancyGuard`, `SafeTransferLib`. |
| `TrancheToken` | Senior and junior share tokens. Solady ERC20 + EIP-2612 permit. Controller-only mint/burn. Transfers gated through the controller. Exposes an ERC-4626 *view* surface only (redemption is async, not synchronous 4626). |
| `TrancheFactory` | Protocol-level deployer, registered at the `WildcatArchController`, gated on `isRegisteredMarket`. One tranche set per market. |
| `IExternal` | Lean interfaces for the market, wrapper, sentinel, arch controller, and ERC20. The `MarketState` struct is an exact field-order mirror of the live market so `currentState()` decodes on a fork. |

Everything is denominated in underlying-asset terms (USDC value) internally, via a realised-only valuation. There is no oracle and no forward mark-to-market.

---

## 4. Trust model and roles

| Actor | Trust | Powers | Notes for review |
|---|---|---|---|
| `governance` | Trusted, bounded | Propose senior share (timelocked, capped), pause deposits (cannot block exits), set junior whitelist, set `defaultDeclarer`, force default. | Bounded by code. Enumerate worst-case behaviour; confirm no gov path moves user funds or breaks the waterfall. |
| `defaultDeclarer` | Trusted for the legal-default path | Call `declareDefault()` to force irreversible wind-down. | Represents the off-chain Loan-Agreement / legal default override. Forcing is one-way. |
| `borrower` | Untrusted (the credit risk) | None on the controller. Identity used for sanctions/escrow scoping. | The whole point is that the borrower can default; that path must be safe. |
| Senior LP | Untrusted | Deposit (if market-approved + not sanctioned), request redeem, claim. | Should never be able to extract beyond `seniorOwed` or jump ahead of the waterfall in reverse. |
| Junior LP | Untrusted, whitelisted | Deposit (if whitelisted + not sanctioned), request redeem, claim. | First-loss. Must not be able to dodge loss or extract ahead of senior. |
| Keeper / anyone | Untrusted | Call `accrue()`, `checkDefault()`, `pokeRecovery()`, `executeSeniorShareBips()` (after eta). | All permissionless. Assume an adversary calls these at the worst possible time and frequency. |
| Market / wrapper / sentinel / arch | Trusted at the interface | Provide state, queue mechanics, sanctions, registration. | In scope to challenge the *assumptions*: what if `convertToAssets` moves oddly, `currentState` returns edge values, a queue fills partially, `createEscrow` reverts? |

Key stance: governance is trusted but bounded, and the design intent is that **no actor, including governance, can break conservation, first-loss ordering, or senior priority, or seize user funds.** A finding that contradicts that is high severity even if it requires the governance key.

---

## 5. External dependencies and failure assumptions

The controller reads and calls external contracts. For each, the assumption and the thing to challenge:

- **`market.currentState()`** (view, projected to `block.timestamp`). Source of `isDelinquent`, `timeDelinquent`, `annualInterestBips`, `isClosed`, `scaleFactor`. Assumption: honest, non-manipulable within a transaction (scaleFactor is time/state-based, not pool-ratio-based). Challenge: any way to make it return attacker-favourable values, or any reentrancy path where it reads stale state mid-operation.
- **`market.delinquencyGracePeriod()`** feeds the default predicate. Assumption: stable, `<= 90 days` (asserted on fork). Challenge: behaviour if it changes between accrual and default checks.
- **`market.queueWithdrawal` / `executeWithdrawal`** drive async redemption. Assumption: queued market tokens redeem to roughly par USDC when liquidity exists; partial fills are possible. Challenge: non-par recovery, batch-expiry edge cases, double-execute, executing someone else's batch.
- **`wrapper.convertToAssets` / `convertToShares` / `redeem`** drive valuation and exit. Assumption: `convertToAssets` is a faithful, non-manipulable price for the wrapper share. Challenge: rounding asymmetry between `convertToAssets` and `redeem`, donation effects, any first-depositor inflation surface.
- **`sentinel.isSanctioned` / `createEscrow`** drive compliance. Assumption: deterministic escrow per (borrower, account, asset); `isSanctioned` is a cheap view. Challenge: a reverting or griefing sentinel blocking claims; escrow-address collisions.
- **`archController.isRegisteredMarket`** gates deployment only. Low surface.
- **USDC** is the claim currency for redemptions. Assumption: standard ERC20, no fee-on-transfer, no callback. (`SafeTransferLib` tolerates non-standard returns.)

A useful adversarial lens: the controller is only as safe as the weakest *documented edge* of these dependencies. Push each to its edge and see what the tranche layer does.

---

## 6. State machine

Two states, on `TrancheController.status`:

- **`Active`** (initial). Deposits allowed; senior accrues; subordination enforced on senior deposit and junior withdrawal; redemptions allowed.
- **`WindDown`**. Entered via `_syncDefault()` when `defaultReached()` is true. Deposits revert (`NOT_ACTIVE`); senior accrual halts; `seniorOwed` frozen and snapshotted to `seniorOwedAtDefault`; junior-withdraw subordination check is skipped; redemptions continue, senior-first.

`defaultReached()` is true when any of: `forcedDefault == true`, `market.currentState().isClosed`, or `timeDelinquent >= delinquencyGracePeriod + defaultPenaltyWindow` (the ToU §6.2 mirror; `defaultPenaltyWindow` defaults to 90 days, capped at 90 days).

Transition properties to verify:

- The transition is **one-way**. There is no `WindDown -> Active`. Even if the borrower cures and `defaultReached()` becomes false again, the vault stays wound down. This is intentional (default is sticky), but confirm there is no unintended way back and reason about griefing via a single transient threshold crossing.
- `forcedDefault` is **irreversible**. Once set, `defaultReached()` is permanently true.
- The transition is **lazy**. Nothing happens until someone calls `accrue()`, `checkDefault()`, or `declareDefault()`. Detection is live-on-read (`defaultReached()` is a view), but commitment requires a transaction. Confirm nothing unsafe happens in the window between the threshold being crossed and the first commit.

---

## 7. Asset, valuation, and accrual model

**Units.** Internal accounting (`seniorOwed`, `realisedValue`, tranche values) is in underlying-asset terms via `convertToAssets`. `PPS_UNIT = 1e18`. `BIPS = 1e4`. Tranche share decimals are set at deploy (`shareDecimals`): the factory hardcodes `18`; the fork test uses `6`. The unit tests use `18`. **The decimals mismatch between configs is itself worth probing** (rounding-to-zero, inflation surface) at 6-dp shares.

**Realised-only valuation.** `realisedValue() = balanceOf(wrapper) * effPps / 1e18`, where `effPps` is:

- healthy: `convertToAssets(1e18)` (live).
- delinquent: `min(convertToAssets(1e18), markPps)`, i.e. frozen at the high-watermark, except it still recognizes a genuine drop below the watermark.

`markPps` advances (to current) only while the market is not delinquent (`_refreshMark`). The rule is one-directional: **freeze unrealised gains during delinquency, recognize losses immediately.** A borrower paying penalty interest while delinquent makes `convertToAssets` rise; the controller refuses to book that. If the wrapper share price genuinely falls below the watermark, that loss flows through on the next read.

**Tranche split.** `WaterfallMath.split(realised, seniorOwed)`: `seniorValue = min(realised, seniorOwed)`, `juniorValue = realised - seniorValue`. Junior is the residual and absorbs all loss until zero before senior is impaired.

**Senior accrual.** `seniorOwed` grows in `accrue()` by `accrueSeniorOwed(seniorOwed, currentSeniorRateBips(), dt)`, a linear-per-update formula: `owed + owed * rateBips * dt / (BIPS * YEAR)`. The rate is derived live: `currentSeniorRateBips() = annualInterestBips * seniorShareBips / BIPS`, capped at `annualInterestBips`. It reads the base APR only, never the penalty rate. Intent: senior tracks the facility rate, capped so junior bears credit risk, not rate risk.

**Accrual compounds on update (expected, matches the base protocol).** `seniorOwed` is updated in place, so the next accrual builds on the new, larger value. Repeated `accrue()` calls therefore compound rather than stay linear: N updates over a period approach continuous compounding `e^(r*t)` instead of `1 + r*t`. This is by design and mirrors the Wildcat market itself, where the borrower's realised APR depends on how often state is updated and compounding happens on each market state update. The senior leg deliberately tracks that same update-driven compounding. It has been the live protocol behaviour for over a year without being ground in practice. Treat it as accepted (see section 12), not as a vulnerability, unless you can show it breaks an invariant in section 9 (conservation, first-loss, or senior <= owed) rather than merely producing a small, expected economic drift.

---

## 8. Function reference (external/public)

Access control, key preconditions, external calls, and reentrancy posture. All mutating entrypoints carry `nonReentrant` unless noted.

**`depositSenior / depositJunior -> _deposit`** (nonReentrant). Calls `accrue()` first. Requires `Active`, `!depositsPaused`, neither sender nor receiver sanctioned, junior receiver whitelisted (junior only). `dV = assetsOf(shares)`, must be > 0. First deposit per tranche: `shares = dV`, require `dV >= MIN_INITIAL (1e6)`. Otherwise `shares = dV * supply / valueBefore` (rounds down, favours pool), require `valueBefore > 0` else `TRANCHE_IMPAIRED`. External call `wrapper.safeTransferFrom` happens *after* share math but *before* mint; senior path then does `seniorOwed += dV` and enforces subordination. Probe: first-depositor/donation interaction (F4), `TRANCHE_IMPAIRED` liveness lock, ordering of `seniorOwed += dV` vs subordination check.

**`requestRedeem(isSenior, shares)`** (nonReentrant). Calls `accrue()`. `assetValue = shares * (sv|jv) / supply` (rounds down), must be > 0. Senior path reduces `seniorOwed` by `owedShare = shares * seniorOwed / supply`. Junior path in `Active` enforces `assetValue <= maxJuniorWithdraw(...)`; in `WindDown` that check is skipped. Burns shares (effects) before external calls `wrapper.redeem` and `market.queueWithdrawal`. Pushes a `Request{owner, isSenior, wmt, usdcClaimed=0, expiry}` and adds `wmt` to the senior or junior queued total. Probe: senior exit during impairment where `owedShare > assetValue` (F5); junior exit in WindDown ahead of senior (F13).

**`pokeRecovery(expiry)`** (nonReentrant, permissionless). `before = USDC balance`, `market.executeWithdrawal(this, expiry)`, `got = USDC balance - before`, `recoveredUSDC += got`. Probe: stray-USDC accounting (F7), executing arbitrary/again expiries, non-par recovery (F6).

**`claimable(id)`** (view). Senior-first cumulative pro-rata. Senior requests share a pool capped at `min(recoveredUSDC, totalSeniorWmtQueued)`, pro-rata by their `wmt`. Junior sees only `max(recoveredUSDC - seniorPool, 0)` capped at `totalJuniorWmtQueued`, pro-rata by their `wmt`. Returns `entitled - usdcClaimed`. **The pro-rata basis is `wmt` (market-token units) while the pool is USDC** (F6).

**`claim(id)`** (nonReentrant). `amt = claimable(id)`; `usdcClaimed += amt` (effects) before transfer. If owner sanctioned, `sentinel.createEscrow(...)` then transfer to escrow; else transfer to owner. Probe: reverting sentinel blocking a claim; escrow griefing.

**`accrue()`** (public, permissionless). `_refreshMark()`, `_syncDefault()`, then if `Active` accrue `seniorOwed` over `dt`. Note `_syncDefault()` runs before accrual, so the pre-default `dt` sliver is dropped on the commit that trips wind-down (F2). Compounds on each call, by design, mirroring the base protocol's update-driven compounding (accepted, section 12).

**`checkDefault()`** (permissionless) and **`declareDefault()`** (governance or declarer). The first commits a clock/closed default; the second forces one irreversibly.

**`beforeTrancheTransfer(token, from, to, amount)`** (view, called by the token's `_beforeTokenTransfer`). Reverts if `from` or `to` sanctioned; if junior token, requires `to` whitelisted. **Senior transfers are sanction-gated only, not credential/KYC-gated** (F8). Mint/burn (from/to == 0) bypass the hook.

**Governance:** `proposeSeniorShareBips` (gov, `<= 1e4`), `executeSeniorShareBips` (permissionless after `RATE_TIMELOCK = 2 days`, calls `accrue()` first to lock in old-rate accrual), `setJuniorAllowed` (gov), `setDepositsPaused` (gov), `setDefaultDeclarer` (gov). Probe the full worst-case gov surface (F9).

**Factory `deployTranches`** (permissionless): derives market from wrapper, requires `isRegisteredMarket`, requires no existing set for that market, deploys with `shareDecimals = 18`.

---

## 9. Invariants that must hold

These are the load-bearing properties. A reproducible violation of any is at least high severity.

1. **Conservation.** `seniorValue + juniorValue == realisedValue` after every operation. (Tested as `invariant_conservation` and in unit `_inv()`.)
2. **First-loss ordering.** While `juniorValue > 0`, senior is unimpaired: `seniorValue == seniorOwed`. Junior reaches 0 before senior loses anything. (Tested as `invariant_juniorFirstLoss`.)
3. **Senior priority on cash.** Across the redemption queue, no junior request can claim USDC while any senior request remains unpaid relative to `totalSeniorWmtQueued`. Senior-first is cumulative, not per-batch.
4. **Senior is capped by what it is owed.** `seniorValue <= seniorOwed` always; senior cannot accrue or claim beyond its owed amount.
5. **Senior rate never exceeds the facility base rate.** `currentSeniorRateBips() <= annualInterestBips`. Junior bears credit risk, not rate risk.
6. **Subordination floor in Active.** After any senior deposit or junior withdrawal in `Active`, `juniorValue * BIPS >= minJuniorBips * TVL`.
7. **No phantom gains.** During delinquency, tranche values never rise on unrealised penalty accrual; `effPps` is frozen at `markPps` on the upside.
8. **Senior accrual stops at default.** Once `WindDown`, `seniorOwed` does not grow.
9. **No value seizure.** No actor (LP, keeper, governance, declarer) can withdraw more than their tranche value entitles, or strand another party's entitled value, modulo documented rounding dust that always favours the pool.

Try to construct sequences (deposits, redemptions, price moves, time, delinquency toggles, default, governance actions, repeated permissionless pokes) that break any of these.

---

## 10. Redemption queue and claim math (detailed)

This is the most intricate accounting and the most fertile ground.

- A redemption burns tranche shares immediately and records the *market tokens* (`wmt`) pulled from the wrapper into the market's withdrawal queue. The request stores `wmt` and `usdcClaimed`, not a USDC guarantee.
- `recoveredUSDC` accumulates the *measured* USDC delta from each `pokeRecovery`. Shortfalls (borrower under-funded the queue, partial fill) show up here as recovered < queued.
- `claimable` distributes `recoveredUSDC` strictly senior-first: senior pool is `min(recoveredUSDC, totalSeniorWmtQueued)`; junior pool is whatever recovery remains above the full senior queue. Each request draws pro-rata by its `wmt` share of its class total, minus what it already claimed.

Specific things to attack here:

- **wmt-vs-USDC basis (F6).** Pro-rata weights are in `wmt`, the pool is in USDC. The implicit assumption is `wmt:USDC ~ 1:1` at redemption. Construct a scenario (using real market semantics on a fork) where queued `wmt` does not map 1:1 to recovered USDC and show whether senior-first still holds in USD terms.
- **Interleaving classes and partial recoveries.** Multiple senior and junior requests, multiple pokes, with recovery crossing the senior-queue boundary mid-stream. Verify no junior claim precedes full senior coverage and no double-claim via `usdcClaimed`.
- **Rounding dust.** Integer pro-rata leaves wei-level remainders. Confirm dust is unclaimable-but-stuck (acceptable) rather than double-claimable (not).
- **Queue growth.** `requests` is unbounded but there is **no on-chain loop over it** (claim/claimable are O(1) by id). Confirm there is genuinely no iteration anywhere and that array growth cannot brick a path. The only real concern is off-chain enumeration.

---

## 11. Rounding and precision

- Share issuance and `assetValue` computations round **down**, favouring the pool / remaining holders.
- `_sharesOf` returns 0 when `effPps == 0` (fully impaired), which can make redemptions revert with `ZERO_VALUE`. Reason about liveness when a tranche is fully impaired.
- `MIN_INITIAL = 1e6` guards the first deposit per tranche. At `shareDecimals = 6` that is 1.0 share; at 18 it is 1e-12. Evaluate whether the guard is sufficient against inflation at both decimal settings.
- `convertToAssets` and `redeem` rounding may differ on the real wrapper; an attacker who can make one round against the controller is interesting. Probe on a fork.

---

## 12. Known and accepted conservative behaviours

These are deliberate. Do not report them as bugs unless you can show they are *exploitable* or *materially unfair*, in which case report that.

- **Senior accrual compounds on each `accrue()` (F1, expected).** `seniorOwed` is updated in place, so frequent permissionless calls compound it toward `e^(r*t)` versus a single linear `1 + r*t`. This is intended and mirrors the Wildcat market's own update-driven compounding, where realised borrower APR is a function of update frequency. It has been live protocol behaviour for over a year. The drift is small (order +0.36% of senior principal per year at 8.5% even under continuous calling) and is not considered worth defending against, since grinding it costs more gas than it yields. Out of scope as a vulnerability unless it can be shown to break a section 9 invariant.
- **Pre-default accrual sliver dropped (F2).** The `dt` between the last accrual and the default instant is not credited to senior on the commit that trips wind-down. Conservative toward junior/the pool.
- **WindDown is sticky and `forcedDefault` is irreversible.** Default does not auto-cure.
- **Stray funds are not sweepable (F7).** USDC sent directly, or recoveries beyond total queued, are stuck (not stolen).
- **Pause is deposit-only.** It never blocks senior or junior exits.
- **Realised-only freeze.** Upside during delinquency is intentionally not booked.

The honest open question worth real attention is the access-policy design (F8). The accrual compounding (F1) above is settled as accepted, do not spend effort trying to report it as novel.

---

## 13. Candidate weaknesses to validate

These are hypotheses, ranked roughly by how much they deserve scrutiny. Confirm or refute each with a concrete test.

- **F4. First-depositor / inflation / donation.** First deposit sets `shares = dV`; later deposits use `dV * supply / valueBefore` with `valueBefore` derived from `realisedValue = balanceOf(wrapper) * effPps`. A direct (donation) transfer of wrapper tokens to the controller inflates `realisedValue` without minting shares. Test the classic inflate-then-victim-rounds-to-zero sequence at `shareDecimals = 6`, and whether donations let an attacker grief or skim subsequent depositors.
- **F6. wmt-vs-USDC claim basis.** Senior-first pro-rata weighted in market-token units against a USDC pool. Show whether non-par recovery breaks USD-fair senior priority.
- **F5. Senior exit during impairment.** `seniorOwed` drops by full pro-rata `owedShare` while only impaired `assetValue` leaves. Verify remaining senior holders are treated fairly and invariants hold across partial senior exits when `realised < seniorOwed`.
- **F8. Senior credentialing on transfer.** Senior tokens transfer to any non-sanctioned address with no market-credential check. Determine whether non-credentialed parties can thereby gain senior exposure, and whether that matters given the market's own access policy. (This is an open design decision, not yet settled.)
- **F9. Governance worst case.** Enumerate what a malicious-but-bounded governance (plus declarer) can do: force irreversible wind-down, pause deposits, de-whitelist junior. Confirm none of it moves user funds or breaks the waterfall; confirm existing holders can always still exit (redeem paths ignore pause and whitelist).
- **F13. Junior exit in WindDown.** Subordination is skipped for junior redemptions in WindDown. Confirm junior still cannot realise value ahead of senior (residual `assetValue` should be 0 while senior is impaired, and `claimable` is senior-first regardless).
- **F2. Default-boundary interest stripping.** Can any actor manoeuvre the system to the default boundary to strip senior of legitimately earned interest, beyond the accepted conservative sliver?
- **F10. Mark / state manipulation.** Any path to make `convertToAssets`, `isDelinquent`, `timeDelinquent`, or `annualInterestBips` read attacker-favourable values within a transaction, including read-only reentrancy through the market or wrapper.
- **F11. Reentrancy (cross-function, read-only).** All entrypoints are `nonReentrant` with effects-before-interactions, but confirm: no view used mid-operation can be re-entered to a stale value; `sentinel.createEscrow` (the one external call with plausible custom logic) cannot reenter usefully; `accrue()` being public creates no nested surprise.
- **F7. Stranded funds.** Confirm stray/excess balances are merely stuck, never misattributed into `recoveredUSDC` or another holder's claim.

---

## 14. Existing test coverage and gaps

**Covered** (`build/test/`):

- `Tranche.t.sol` (unit/behaviour): deposit split and subordination; senior-deposit leverage cap; senior target funded by junior when there is no yield; junior leveraged residual; loss hits junior first then impairs senior; ToU default trigger halts accrual; `declareDefault` override; async redemption happy path; senior-first on shortfall; sanctioned claim routes to escrow; senior-share timelock; senior rate derived live from the market APR (tracks up and down); sanctions + whitelist on deposit; 4626 views; realised-only freeze during delinquency then recognition on cure; factory gating on registered market and single-set-per-market.
- `Fuzz.t.sol`: property fuzz on `split` (conservation, senior cap, junior-first), `maxSeniorDeposit` and `maxJuniorWithdraw` keep the floor, accrual monotonic. Stateful invariants (`invariant_conservation`, `invariant_juniorFirstLoss`) over random deposits/redemptions/price moves/time.
- `Fork.t.sol`: live `MarketState` decode, senior rate equals live base APR at 100% share, deposit valuation matches live `convertToAssets`, redemption round-trip against the real withdrawal queue.

**Known gaps to fill** (good red-team targets):

- No **inflation/donation** test, and no test at `shareDecimals = 6` for the share-math edge (F4).
- No **non-par recovery** test for the wmt-vs-USDC basis (F6).
- No **senior-exit-during-impairment** accounting test (F5).
- No **multi-request, multi-poke interleaving** stress on `claimable` senior-first across the senior/junior pool boundary.
- Invariant handler does not exercise **junior redemption, delinquency toggling, or default/wind-down**; extend it to keep invariants under those.
- No **read-only reentrancy** harness around the market/sentinel calls (F10, F11).
- No **a16z ERC-4626 property suite** against the view surface.

---

## 15. Parameters and bounds

| Parameter | Where | Bound | Default / example |
|---|---|---|---|
| `seniorShareBips` | per market, timelocked | `<= 1e4` | 8000 (=> ~6.8% senior target at an 8.5% facility) |
| `minJuniorBips` | immutable per market | `500 .. 9000` | 2000 (junior >= 20%, senior <= 4x) |
| `defaultPenaltyWindow` | immutable per market | `> 0 .. 90 days` | 90 days |
| `RATE_TIMELOCK` | constant | 2 days | governance share changes |
| `MIN_INITIAL` | constant | 1e6 (asset value) | first deposit per tranche |
| `shareDecimals` | per deploy | factory hardcodes 18; fork test uses 6 | mismatch worth probing |
| `MAX_SENIOR_SHARE_BIPS` | constant | 1e4 | senior <= 100% of base APR |

---

## 16. Finding output format and severity

For each finding, report:

- **Title** and **severity** (rubric below).
- **Attacker** and **preconditions** (who, what state, what they must control).
- **Call sequence** (exact, ideally as a Foundry PoC test).
- **Invariant or party harmed**, mapped to section 9 where possible.
- **Magnitude** (value at risk, or qualitative if it is a liveness/DoS issue).
- **Suggested fix** if you have one.

Severity rubric:

- **Critical:** direct theft or permanent loss of user funds; breaks conservation or first-loss with realistic preconditions.
- **High:** value transfer between parties beyond documented rounding; senior priority subvertible; funds strandable by an unprivileged actor; an invariant breakable.
- **Medium:** griefing, material-but-bounded unfairness, DoS with a recovery path, or a governance power that exceeds the stated bound.
- **Low / informational:** dust, conservative imprecision with no exploit, hygiene.

Start with F4 and F6, then the F8 access-policy question. They are where the as-built design is least certain.
