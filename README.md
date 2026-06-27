# Wildcat In-House Tranching

Senior/junior credit-tranche vault over a Wildcat ERC-4626 market wrapper (`v-wmtUSDC`).
Conservative model: a senior target derived from the facility's base APR (a priority claim, not a guarantee), junior first-loss, a fixed
subordination floor, realised-only valuation, async redemption routed through the market's batched
withdrawal queue (senior-first), escrow on sanction, and a default trigger that mirrors Wildcat
**Terms of Use §6.2** (grace + 90-day penalty) on-chain.

The tranche tokens build on Solady's ERC20 (with EIP-2612 permit) and expose an ERC-4626 value-view
surface; redemption is asynchronous (ERC-7540 style), so there is no synchronous 4626 `withdraw`.
The controller uses reentrancy guards and safe transfers, and values its holdings realised-only. NAV
is held at a high-watermark while the market is delinquent, so unrealised penalty accrual is never
booked as profit.

> Not yet audited.

## Documentation
- [Tranching-Explained.md](Tranching-Explained.md) — plain-language explainer of the whole facility (also rendered to PDF under `report/`).
- [Design-Risk-Specification.md](Design-Risk-Specification.md) — the design and risk decisions behind the model.
- [Red-Team-Technical-Framework.md](Red-Team-Technical-Framework.md) — adversarial-review brief: trust model, invariants, and the candidate-weakness list.
- [BD-Primer.md](BD-Primer.md) — structured-credit framing for business development and trading desks.
- [Wildcat-Tranching-Effort-Assessment.md](Wildcat-Tranching-Effort-Assessment.md) — build effort and common-ground assessment vs Strata / Royco / Pareto.
- `report/` — branded PDFs (architecture, BD primer, explainer). `deck/` — slide decks.
- `frontend/index.html` — interactive model of the waterfall (open in a browser).

## Contracts (`build/`)
```
build/src/
  libraries/WaterfallMath.sol   # accrual, value/loss split, subordination, ToU default trigger
  TrancheController.sol         # brain: deposits, async redemption, default/wind-down, gating, gov
  TrancheToken.sol              # Solady ERC20 + permit + ERC-4626 views (sr-/jr-wmtUSDC)
  TrancheFactory.sol            # protocol-level, ArchController-gated, one set per market
  interfaces/IExternal.sol      # lean interfaces matching the Wildcat ABIs
build/test/
  Tranche.t.sol                 # unit/behaviour tests
  Fuzz.t.sol                    # property fuzz + stateful invariants (conservation, first-loss)
  Fork.t.sol                    # mainnet-fork tests vs the real v-wmtUSDC + market
  Mocks.sol                     # full-fidelity mocks (market, wrapper, sentinel, arch, USDC)
```

## Run
```bash
export FOUNDRY_DISABLE_NIGHTLY_WARNING=true

# everything (local + mainnet fork): 25 tests
cd build && forge test

# local only (unit + fuzz + invariants)
cd build && forge test --no-match-path test/Fork.t.sol

# mainnet fork only
cd build && forge test --match-path test/Fork.t.sol -vv
```
The fork suite deposits real `v-wmtUSDC`, decodes the live `MarketState`, and round-trips a
redemption through the real withdrawal queue. `forge-std` and `solady` are vendored under
`build/lib`, so the suite builds on clone.

## Explore (frontend)
Open `frontend/index.html` in a browser: a JS model of `WaterfallMath`. Deposit senior/junior,
add yield/loss, advance time, drive delinquency to the ToU default, and work the senior-first
redemption queue. Demo links: `frontend/index.html?demo=loss`, `frontend/index.html?demo=seniorfirst`.

## Audit scope
Independent review should focus on the credit-loss / redemption edge cases, the gas/DoS profile of
the `requests` array at scale (claim-batching), and ERC-4626 property conformance of the view surface.
See [Red-Team-Technical-Framework.md](Red-Team-Technical-Framework.md) for the full brief.
