# Implementation Plan: Strategy wizard search and margin input

Status: COMPLETE (approved and audited 2026-10-01)
Date: 2026-10-01
Tier: M
Specification: `docs/agents/specs/2026-10-01-strategy-wizard-search-and-margin.md`
Decision Ledger: `docs/agents/decisions/2026-10-01-strategy-wizard-input-decisions.md`

## Objective and repository state

Implement REQ-001/AC-001 and REQ-002/AC-002 in one bounded Flutter task. The T40/T41 product/test changes and planning artifacts from the prior cycle are present and uncommitted; preserve them. No backend/config/dependency/deployment change.

## Planning workstreams

| Workstream | Material | Independent | Route | Logical run | Status / adoption |
| --- | --- | --- | --- | --- | --- |
| Search picker interaction | YES | YES | R2 / gpt-6-sol / medium, explicit | R2-003 | COMPLETE / USED |
| Decimal input and Flutter-backend contract | YES | YES | R2 / gpt-6-sol / medium, explicit | R2-004 | COMPLETE / USED |

Fan-out Required: YES. Required Reasoning Agents: 2. Actual Reasoning Agents: 2. Fan-out Compliance: PASS. Skip Reason: N/A. The coordinator reconciled the workstreams: search is a local picker change; numeric normalization and string price serialization belong to the Flutter request boundary, while backend precision checks stay strict. Effective child routes were not exposed after explicit binding.

## Task and impact

```text
T42 (search + decimal request contract) -> final integration audit
```

One executor task is appropriate because both features touch `strategy_wizard_dialog.dart`, use the same wizard test harness, and must leave one buildable Flutter boundary. Allowed product/test writes: `lib/features/strategy/presentation/strategy_wizard_dialog.dart`, `lib/features/strategy/domain/strategy_selection.dart`, and focused Dart tests under `test/features/strategy/`. Protected configuration files and all backend files are excluded.

### P01 — searchable coin picker

Replace the current full-list dropdown with a selected-contract control that opens a searchable picker over `_instruments`. Filter by base or full ID, case-insensitively after trim. Keep selection and dependent state unchanged until a different contract is chosen. Use `_loadLevels` once on a new selection. Test matching, no-match, dismiss, choose, and existing disabled/loading behavior.

### P02 — normalized margin and precise request prices

Normalize one decimal comma to a dot for margin and Long percentage, validate positive/finite values and reject malformed/mixed separator input locally. Send the same normalized values from preview and save. Serialize level and entry prices as decimal strings in `StrategySelection.toRequestJson` while retaining backend float rejection. Test `100`, `100.0`, `100,0`, fractional percentage, malformed inputs, and matching selected/entry price strings.

## Verification and gates

| Task | RED then GREEN | Focused tests | Task buildability |
| --- | --- | --- | --- |
| T42 | RED-001 and RED-002 before source fix, then GREEN-001 and GREEN-002 | new/relevant wizard widget test and `test/features/strategy/strategy_selection_test.dart`; backend existing string fixture only if contract risk requires it | Flutter web app: `rtk flutter build web --release` after last task source/test change |

Run the narrowest new cases first (V1), then complete relevant file/group (V2); escalate to affected strategy tests (V3) only on concrete related failure. Formal RED precedes GREEN; code/test changes after a checkpoint invalidate only affected evidence. The final repository build gate uses `rtk flutter build web --release` after audit/remediation. Flutter SDK cache may require the same approved escalated build/test path as T40/T41. No external configuration action. No live OKX call or order placement.

## Risks and completion

- Picker search must not reset the selected strategy until the user chooses another contract.
- Converting level prices to strings must preserve entry/selected-level equality through backend normalization.
- `100,0` must mean 100.0 USDT, not a grouped integer; ambiguous grouping-style or mixed inputs are rejected.
- Audit the exact non-protected diff, RED/GREEN evidence, malformed-input coverage, task buildability, final build, and name-only protected-path status.

Execution requires user approval after this plan is presented. Commit, push, and deployment require separate authorization.

## Final integration audit

T42 passed with observed RED before GREEN. The changed code and test paths match the approved task; earlier uncommitted T40/T41 work was preserved. The final `rtk flutter build web --release` succeeded after T42 and produced `build/web`. The relevant nine focused tests passed, and `git diff --check` passed for tracked T42 paths. No protected configuration path was changed. Final verdict: PASS.
