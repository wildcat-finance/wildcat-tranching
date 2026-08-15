# Wildcat tranching BD field kit: delivery runbook

## Objective

Turn the implementation-grounded study into a repository-native field kit for lender and borrower
conversations. The work is documentation and static SVG only. It does not alter contracts, deployment
configuration or the pinned V2.5 source.

The steps are stacked from `main`. Each step must preserve the existing test baseline and keep every
commercial claim traceable to code, tests or a named public source.

## Step 1: Scaffold the BD field kit and research source

**Goal.** Establish the field-kit index and commit the source-grounded study and delivery runbook in a
reviewable location.

**Entry.** `main` at `b90a155f257c76f96e50cf2fa29872e1735f8bd8`.

**Exit.** `docs/bd/` exists with an index, the full research report and the delivery runbook. The index
states the reviewed commit, prototype status, intended audiences, authority split and reading order.
Every code path and external standard named in the report has a usable pointer. `forge fmt --check` and
the non-fork conventional/fuzz/view/release suites complete with their actual results recorded.

**Files.** Create `docs/bd/README.md`, `docs/bd/RESEARCH_REPORT.md` and
`docs/bd/DELIVERY_RUNBOOK.md`.

**Tests.** Run the bundled prose lint over all three files. Run `forge fmt --check` and
`forge test --no-match-path test/Fork.t.sol`; record the dependency diagnostic separately if Foundry
emits it again.
## Step 2: Write the counterparty conversation pack

**Goal.** Give BD concise material for explaining the facility, asking about acceptable terms and
answering common lender and borrower questions without making unsupported claims.

**Entry.** The pushed branch from Step 1.

**Exit.** The field kit contains a plain-language primer, one-page meeting brief, parameter discovery
guide and question-and-answer and claims guide. Together they cover both crypto-native and traditional
credit vocabulary; lender and borrower perspectives; protocol fees; controlled transferability;
asynchronous exits; delinquency and wind-down; sanctions escrow; terminal settlement; and the exact
borrower, market, protocol and code authority split. Worked prompts use hypothetical numbers and label
them as illustrations.

**Files.** Create `docs/bd/PRIMER.md`, `docs/bd/MEETING_BRIEF.md`,
`docs/bd/PARAMETER_DISCOVERY.md` and `docs/bd/FAQ_AND_CLAIMS.md`; update `docs/bd/README.md`.

**Tests.** Lint every changed prose file. Check internal links. Search the pack for prohibited shorthand
such as guaranteed yield, principal protection, instant redemption, immutable allowlist, audited and
production-ready, then inspect any contextual hits. Run the non-fork test baseline.

## Step 3: Add the infographic set and verify the complete kit

**Goal.** Add reusable visuals and prove that a BD colleague can navigate the field kit from one index.

**Entry.** The pushed branch from Step 2.

**Exit.** Six static SVGs render locally and on GitHub-compatible viewers: one-market/two-claims,
priority waterfall, parameter authority, healthy lifecycle, distress lifecycle, and cost/yield bridge.
`docs/bd/INFOGRAPHICS.md` supplies captions, alt text and reuse notes. The former
`docs/TRADFI_OUTREACH_PRIMER.md` points to the complete kit while retaining its existing purpose. The
demo path opens `docs/bd/README.md`, reaches every document and visual, and the final formatting,
non-fork, stateful, fork and release-evidence commands run with their actual results recorded.

**Files.** Create `docs/bd/INFOGRAPHICS.md` and six files under `docs/bd/assets/`; update
`docs/bd/README.md` and `docs/TRADFI_OUTREACH_PRIMER.md`.

**Tests.** Parse each SVG as XML, check its view box and embedded text, render each to PNG for visual
inspection, and validate internal Markdown links. Run the prose lint over all field-kit Markdown. From
`build/`, run `forge fmt --check`, the conventional/fuzz/view/release suites, the configured stateful
suite, the seven pinned fork paths and the release-evidence test. Report every command that ran and any
environmental failure without upgrading it into a successful result.
