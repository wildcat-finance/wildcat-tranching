# BD field kit review log

## Step 1, round 1 -- 15 August 2026

| id | severity | file | finding | status |
| --- | --- | --- | --- | --- |
| S1-R1-01 | high | `docs/bd/README.md`, `docs/bd/RESEARCH_REPORT.md` | The hook administrator was called fixed and was grouped with market-borrower powers. The role can transfer, and the two roles control different upstream settings. | fixed in `32cf3b3` |
| S1-R1-02 | high | `docs/bd/README.md`, `docs/bd/RESEARCH_REPORT.md` | Protocol-fee priority was stated as an unconditional first rung. Accrued fees reserve liquidity ahead of unprocessed withdrawals, but do not displace an already-processed unclaimed withdrawal. | fixed in `32cf3b3` |
| S1-R1-03 | high | `docs/bd/README.md`, `docs/bd/RESEARCH_REPORT.md` | The fee description omitted its basis, update authority, recipient immutability and the possible origination fee. The 1,000-bip cap applies to the base lender rate rather than principal. | fixed in `32cf3b3` |
| S1-R1-04 | high | `docs/bd/RESEARCH_REPORT.md` | The parameter map omitted material market bounds, the nonzero delinquency-fee requirement, the fixed first-deposit minimum, the asset-decimal floor and the absence of tranche-term defaults. | fixed in `32cf3b3` |
| S1-R1-05 | medium | `docs/bd/RESEARCH_REPORT.md` | The recorded test wording called selected suites the non-fork baseline even though no invariant campaign result or command exit status was produced. | fixed in `32cf3b3` |
| S1-R1-06 | medium | `docs/bd/RESEARCH_REPORT.md` | The source list omitted upstream files used for authority and ordering claims, and repository paths were not links. | fixed in `32cf3b3` |
| S1-R1-07 | medium | `docs/bd/RESEARCH_REPORT.md` | The wrapper glossary entry blurred the wrapper's market-token backing with the manager's custody of wrapper shares. | fixed in `32cf3b3` |

Leads not pursued: legal, tax and securities classification require counsel and remain expressly open;
public Wildcat documentation is mutable and is used only for general market behaviour; Investor.gov
rejected an automated request but remained available through ordinary browser/search access; the
untracked `build/foundry.lock` is outside the documentation diff; no Solidity security finding was
pursued because this step changes prose only.

## Step 1, round 2 -- 15 August 2026

| id | severity | file | finding | status |
| --- | --- | --- | --- | --- |
| S1-R2-01 | high | `docs/bd/RESEARCH_REPORT.md` | Relative links below the V2.5 submodule gitlink resolved locally but returned 404 on GitHub. | fixed in `260e14f` |
| S1-R2-02 | medium | `docs/bd/RESEARCH_REPORT.md` | The first-deposit minimum was attached to the tendered amount rather than its post-conversion credited value. | fixed in `260e14f` |
| S1-R2-03 | medium | `docs/bd/README.md`, `docs/bd/RESEARCH_REPORT.md` | The 11% fee example was described as borrower cost without excluding separate origination and delinquency charges. | fixed in `260e14f` |
| S1-R2-04 | low | `docs/bd/RESEARCH_REPORT.md` | One claims-boundary sentence said "fixed class gate" rather than distinguishing the fixed address from potentially mutable gate policy. | fixed in `260e14f` |

Leads not pursued: none.

## Step 1, round 3 -- 15 August 2026

| id | severity | file | finding | status |
| --- | --- | --- | --- | --- |
| S1-R3-01 | medium | `docs/bd/RESEARCH_REPORT.md` | The authority map omitted the borrower-supplied initial hook tuple, the differing mutability of its fields and the trancher's transfer-enabled requirement. | fixed in `0b96446` |
| S1-R3-02 | low | `docs/bd/README.md` | The short authority table grouped protocol-fee rate and recipient without preserving their differing mutability. | fixed in `0b96446` |

Leads not pursued: none.
