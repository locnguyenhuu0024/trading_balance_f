# Implementation Plan: Monochrome Minimalism

Status: COMPLETE
Date: 2026-10-03
Tier: M
Specification: ../specs/2026-10-03-monochrome-design.md
Decision Ledger: ../decisions/2026-10-03-monochrome-decisions.md
Authorization: direct user implementation request and delegated design decisions.

## Planning workstreams
| Workstream | Material | Independent | Route | Logical run | Adoption |
|---|---|---|---|---|---|
| Theme/root/navigation architecture | YES | YES | R2 / gpt-6.1-sol / medium | R2-THEME | COMPLETE / USED |
| Screen coverage/status/accessibility | YES | YES | R2 / gpt-6.1-sol / medium | R2-SCREENS | COMPLETE / USED |
| Backend/data | NO | N/A | N/A | N/A | No changes |

Fan-out Required: YES. Required Reasoning Agents: 2. Actual Reasoning Agents: 4 (2 original context-binding-invalid runs, 2 correctly bound revalidation runs). Fan-out Compliance: PASS after recovery. Effective child routes unavailable; original full-history combination is not accepted as valid binding. Coordinator runtime route fixed; no claimed model switch.
Synthesis: preserve navigation contracts, implement root dark/system synchronization, retain financial direction/status through explicit non-color cues, and migrate all screen colors rather than applying a global filter.

## Steps and execution DAG
P01/P02/P03 belong to one compile-coupled T66 task. The runtime initially rejected another child with `agent thread limit reached`; a later explicitly bound E1-CLASSIC dispatch succeeded after reasoning runs finished. Foundation retains P01/P03; classic owns P02 after acknowledged handoff (earlier visual brightness wiring preserved). No inherited/default executor fallback and no partial task PASS before integration build. Additional executor dispatch remained unavailable, so P03 stays with foundation.

Integration recovery: original children used full-history forks alongside explicit model/effort overrides, an unsupported context-binding combination. Effective routes were not exposed and are not claimed as matches. Stop prior mutation, preserve/audit source, and hand the remaining work to E1-INTEGRATION with `fork_turns=1`, `gpt-6-luna`, `xhigh` explicitly submitted. The integration executor alone owns final adoption/remediation/preview tests; coordinator remains non-writing for product sources. Earlier evidence stays available subject to dependency/freshness review.

Correctly bound independent workstream revalidation: R1-BOUND-THEME (`gpt-6.1-sol/low`, routine known-contract theme audit) and R2-BOUND-SCREENS (`gpt-6.1-sol/medium`, screen/status/layout audit), both partial-history forks with explicit model/effort and read-only role, COMPLETE/USED. Theme contract audit PASS; screen audit identified Fractal confluence/progress large-text rows, reconciled as bounded flexible/wrapping remediation under unchanged AC-004. Fan-out reconciliation is complete; product final PASS remains withheld pending remediation/tests/build. Original evidence remains historical, not proof of effective route binding.
- P01: Add theme/tokens/brightness source, wire root theme, update biometric UI, navigation surfaces and coin imagery. Add theme behavior/contrast tests.
- P02: Migrate Portfolio/details, Orders/widgets, Market, Fractal to tokens/palette. Replace legacy brightness snapshot with reactive provider. Preserve all numeric/layout/callback contracts; add candle direction encoding.
- P03: Migrate Settings/trade access, Risk dashboard/widgets, Strategy dialogs/screens and Support/Resistance. Inherited theme-only surfaces need no artificial edits. Verify risk/status labels and overlay controls.
- P04: Coordinator independently audits selected source diffs, scope and behavioral tests; final web build after last executable change.

## Verification
Focused tests first; final full Flutter suite justified by cross-cutting theme/root and presentation changes. Baseline suite already requested. Final commands: `flutter test --no-pub`, `flutter build web --no-pub`. Use RTK first with narrow raw diagnostic fallback where needed. No concurrent build/test jobs by executors; coordinator owns shared verification.
External configuration/environment actions: none. Protected files remain unread and unmodified. No deployment or Git writes.

Final audit: ../audits/2026-10-03-monochrome.md. Theme, mode synchronization, preserved financial formatting/flows, populated compact layouts and mock Portfolio previews verified. Full suite returned 425 passing / 6 failing; the two task-attributable Orders fixture assertions were corrected and all 7 Orders layout tests then passed. Four independently reproduced baseline navigation/settings failures remain. Final web build exited 0 after the last source/test edit. T66 scoped verdict PASS; full suite is not claimed clean.
