# Task 27 — Vietnamese Risk Dashboard

Status: PASS
Executor: implementation executor
Executor Class: E1
Target Route: Luna XHigh
Specification: `docs/agents/specs/2026-09-13-multi-position-risk-dashboard-429-vietnamese-design.md`
Plan: `docs/agents/plans/2026-09-13-multi-position-risk-dashboard-429-vietnamese.md`
Plan Steps: P04
Requirements: REQ-005
Acceptance Criteria: AC-010-AC-012

## 1. Objective

Translate every application-generated rendered Risk Dashboard surface into Vietnamese after functional Tasks 24-26 pass.

Done when: rendered/static tests find no unapproved English user-facing copy while technical identifiers, persistence/wire values, units, source names, privacy, and user-authored text remain unchanged.

## 2. Preconditions

Predecessors: T26 = PASS; therefore T24 and T25 are also PASS.
Required decisions/assumptions: D-003; none.
Required repository/environment state: functional multi-position accordion is frozen for translation-only work.

## 3. Allowed Scope

- `lib/features/portfolio/presentation/risk_vietnamese_formatter.dart`
- `lib/features/portfolio/presentation/risk_dashboard_screen.dart` for copy/formatter calls only
- `lib/features/portfolio/presentation/widgets/risk/*.dart` for copy/formatter calls only
- `test/features/portfolio/risk/risk_dashboard_test.dart`
- `test/features/portfolio/risk/risk_editors_test.dart`
- `test/features/portfolio/risk/risk_vietnamese_copy_test.dart`
- focused domain/application tests only when rendered generated-message compatibility requires assertions, without changing functional semantics

## 4. Forbidden Scope

Do not read/modify protected configuration; change behavior/formulas/thresholds/cadences/API/storage schema/wire enum values; translate user-authored rule/zone text, identifiers, coin/instrument/source names, or approved units; edit Portfolio Details/other screens; add dependencies.

## 5. Executor Contract

Follow P04:
1. Centralize Vietnamese typed labels and known current/legacy generated-message formatting.
2. Translate dashboard/accordion/detail/sheets/dialogs/actions/validation/snackbars/empty-error-stale-partial-backoff/history/tooltip/semantics copy.
3. Translate known current/legacy dynamic messages at the presentation boundary; unknown upstream prose becomes a safe generic Vietnamese explanation with status/source metadata.
4. Preserve all technical/user-owned values exactly and retain privacy behavior.
5. Add an explicit allowlist source audit plus representative rendered-state tests.

Required invariants: INV-009, INV-010 and all T24-T26 invariants.
Required edge behavior: EDGE-006 and all prior failure/UI states.
Preserved behavior: functional multi-position monitoring, alerts, persistence, and UI interactions.

## 6. External Configuration / Environment Actions

Planned action: none.
Discovered additional action: none expected; otherwise `BLOCKED`.
Blocks verification until user applies: NO.

## 7. Tests

- TEST-010: rendered dashboard/editor/failure/accessibility text is Vietnamese.
- TEST-011: dynamic/legacy event formatting in the dashboard is Vietnamese and privacy-safe.
- TEST-012: allowlist source audit rejects new unapproved English literals.

## 8. Mandatory Verification

### RED — RED-004
Scenario: English-copy audit after functional work.
Command/method: `flutter test test/features/portfolio/risk/risk_dashboard_test.dart test/features/portfolio/risk/risk_editors_test.dart test/features/portfolio/risk/risk_vietnamese_copy_test.dart --plain-name "RED-004 Vietnamese Risk Dashboard" --reporter compact`
Expected: existing application-generated English copy violates the Vietnamese contract.
Actual: Executed test-first during remediation before product-source changes; the scenario ran and failed on untranslated generated event/Price Map/error copy, the True Exit formatter defect, and the missing `trueExitPrice` catalog entry.
Status: PASS

### GREEN — GREEN-004
Scenario: complete Vietnamese dashboard/history/editor experience.
Command/method: same files with `--plain-name "GREEN-004 Vietnamese Risk Dashboard"`.
Expected: AC-010-AC-012 pass; technical/user content and privacy remain unchanged.
Actual: PASS; exact selector passed after remediation, and the full dashboard/editor/localization suite passed 35 tests.
Status: PASS

Verification ceiling: V3.
Escalate only if: a string cannot be safely distinguished from user/source content or translation exposes a functional regression.

### Task Buildability Gate

Required: YES
Affected canonical build unit: Flutter application
Exact secret-free build command: `flutter build web --no-pub`
Executed after final task-local change: YES
Result: PASS
Exit/status: 0
Compiler/parser/type/reference/link/build errors: none; only non-blocking existing Wasm compatibility warnings.

### External Verification

Required: NO
Subtype: N/A
Exact secret-free user-run command: N/A
Proves: N/A
Expected returned evidence: N/A
Task/verification blocked until returned: NO

## 9. Stop Conditions

Return `BLOCKED` for persistence/wire mutation, ambiguous user/source text, functional-scope changes, protected-config dependency, or unavailable verification.

## 10. Execution Ledger

- [x] inspect referenced symbols
- [x] implement P04
- [x] add/update tests
- [x] execute formal RED then GREEN
- [x] run task buildability gate
- [x] confirm protected configuration boundary

## 11. Coordinator Audit

Scope: PASS — copy/formatter and focused test surfaces only; no functional, layout, wire/storage, dependency, configuration, or generated-artifact scope creep.
Acceptance criteria: PASS — AC-010-AC-012 and REQ-005 verified.
Test quality: PASS — rendered states, current/legacy dynamic messages, privacy preservation, generated-versus-user copy, catalog coverage, and explicit source allowlist are covered.
RED evidence: PASS — executing failures were observed before the corresponding product-source remediations.
GREEN evidence: PASS — exact GREEN selector passed; full focused suite passed 35 tests.
RED-before-GREEN: PASS
Architecture/contract conformance: PASS — localization remains presentation-only; technical identifiers, units, source names, user-authored text, and T24-T26 behavior are preserved.
Task buildability gate: PASS — `flutter build web --no-pub`, exit 0 after the final change.
Verdict: PASS
