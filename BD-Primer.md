# Wildcat Risk Tranching: A Primer for Credit Desks and BD

*A plain-English summary for business-development and traditional-finance desk operators. Branded PDF: `report/Wildcat-Tranching-BD-Primer.pdf`.*

## The one-liner
Take a single private-credit facility, say Six Seven Ltd borrowing USDC on Wildcat, and split the lender side into two pieces. A senior tranche earns a priority, target coupon protected by a first-loss buffer. A junior tranche takes the first loss in exchange for leveraged excess spread. Same borrower, same loan, two risk/return profiles, settled and enforced entirely by smart contract. From the borrower's seat nothing changes; it stays a single line of credit ("unitranche to the borrower").

## 1. The structure, in terms you already use
| Structured-credit concept | How it shows up here |
|---|---|
| Senior / junior tranches | Two transferable tokens, `sr-abcUSDC` and `jr-abcUSDC`, each a claim on the same facility |
| Attachment / subordination | Junior ≥ **20% of capital**, so senior sits behind a 20% first-loss cushion; senior leverage capped ~4× |
| Interest waterfall | Facility interest pays the senior's target coupon first; residual ("excess spread") to junior |
| Loss waterfall | Losses hit junior to zero before senior is touched: strict first-loss, enforced in code |
| Over-collateralisation / credit enhancement | The junior buffer *is* the enhancement; no external guarantor or wrap |
| NAV / mark | Each tranche valued on-chain every block from realised facility value: live, auditable |
| Event of default | Mirrors the facility's own legal default (90 days past grace) on-chain, triggering an orderly senior-first wind-down |

## 2. Lifecycle
- **Subscribe.** A KYC'd lender deposits into senior or junior and gets the token. Deposits are taken in the market token or its wrapped `v-` form; a raw market-token deposit is wrapped on the way in. Junior is restricted to qualified first-loss providers.
- **Accrue.** The senior token accretes toward its target coupon. Junior captures everything above it, levered, because it earns the spread on the whole facility against a thin slice.
- **Redeem.** Exits run through the facility's redemption queue (request/claim), not instant daily liquidity; partial proceeds pay senior first.
- **Default & recovery.** On a facility default, the senior's accrued claim freezes and the structure winds down. Recoveries, including off-chain legal enforcement, distribute senior-first, with junior absorbing the shortfall.

## 3. The two products
**Senior · `sr-abcUSDC`** is for capital preservation. A priority coupon set as a share of the facility APR (around 6.8% at an 8.5% facility rate), with a 20% junior buffer beneath. Loss only after junior is wiped. Queue-based, first in line on exit. *Buyers: treasuries, conservative credit, cash-plus.*

**Junior · `jr-abcUSDC`** is levered first-loss "equity". Excess spread amplified (~4× the slice), no protection, first dollar of loss, can go to zero. Queue-based, paid after senior. *Buyers: credit funds, prop desks, yield-seekers.*

## 4. Why it appeals
- **Senior buyer:** a defined priority coupon on a name you can underwrite, behind a hard 20% first-loss buffer, with collateral and waterfall visible on-chain in real time. Higher than bills/MMF, with an explicit subordination level.
- **Junior buyer:** a clean way to express a credit view and harvest carry. Levered spread with programmatic, predictable attach/detach mechanics, and no fund wrapper.
- **Desk / originator / BD:** widen the buyer base without touching the borrower's terms. Place senior with capital that can't take first-loss and junior with capital that wants it. This deepens the facility, tightens blended cost, and lets one mandate be placed as two.

## 5. How it's different
**vs. traditional securitisation:** no SPV/trustee/servicer (deploy a contract per facility in minutes, no ongoing intermediary fees), live per-block transparency instead of remittance reports, atomic settlement, transferable/composable tokens. Trade-offs: smart-contract & stablecoin risk, thinner secondary depth, and recovery still relies on off-chain legal enforcement.

**vs. other on-chain tranching (Strata / Royco / Pareto):** those tranche *liquid* yield, where loss is a smoothly-falling price. Wildcat's is built for undercollateralised private credit, where loss is a discrete credit event. So the loss trigger is tied to the facility's *actual* default definition, and the layer is owned by Wildcat: no third-party dependency or revenue share, and tokens integrate into the same KYC'd deposit flow.

## 6. Be clear-eyed about
- **Semi-liquid**, not a daily-liquidity fund: exits queue, fill partially in stress, senior-first.
- **Single-name concentration**: one borrower per tranche set; diversification is across facilities, not within.
- **Junior is genuine first-loss**: can be written to zero before senior loses a cent.
- **Recovery is part on-chain, part legal**: the contract distributes recoveries senior-first, but ultimate recovery depends on off-chain enforcement.
- **Smart-contract & asset risk**: standard DeFi caveats; the system is audited before mainnet use.

*Implemented and tested: 55 tests, including mainnet-fork validation against a live facility and 128k-call stateful invariants (conservation, junior-first-loss, no over-distribution). Two independent three-pass agentic review cycles have been run, with every actionable finding fixed and pinned by a regression test; no human audit engagement has been performed yet — one precedes any real capital. Final per-facility terms (coupon, attachment, liquidity schedule) are set at deployment.*
