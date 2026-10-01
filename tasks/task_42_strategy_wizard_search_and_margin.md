# Task 42 — Search contracts and accept comma-decimal margin

Status: PASS (coordinator audit 2026-10-01)
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Target Route: gpt-6-luna / xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE (explicit model and effort binding; runtime did not expose effective route)
Specification: `docs/agents/specs/2026-10-01-strategy-wizard-search-and-margin.md`
Plan: `docs/agents/plans/2026-10-01-strategy-wizard-search-and-margin.md`
Plan Steps: P01, P02
Requirements: REQ-001, REQ-002
Acceptance Criteria: AC-001, AC-002

## Objective

Add local contract search and make positive integer/dot/comma margin values reach preview with precise decimal-string selected/entry prices.

## Scope

Allowed writes: `lib/features/strategy/presentation/strategy_wizard_dialog.dart`, `lib/features/strategy/domain/strategy_selection.dart`, focused Dart tests under `test/features/strategy/`.
Forbidden: backend, API schema, live orders, auth/session/market-data semantics, dependencies, protected configuration/environment files, Git mutations, existing T40/T41 changes.

## Implementation contract

1. Implement the picker state and UI exactly as REQ-001. Query is local, trimmed, case-insensitive, and matches base/full ID. Dismiss/search alone preserves current strategy state; select a different coin calls existing `_loadLevels` once.
2. Normalize margin and Long percentage decimal-comma input; reject malformed/mixed/grouping/suffix input locally. Preview/save share normalized strings. Send selected and entry prices as decimal strings via `StrategySelection.toRequestJson`. Do not change backend `_decimal`.
3. Add focused widget/domain coverage without weakening existing tests.

## Verification contract

- RED-001: focused search widget case fails before UI change because no search control exists.
- RED-002: focused request case shows `100,0` rejected locally and/or integer/dot margin sends floating-point level prices before source fix.
- GREEN-001/GREEN-002: new cases pass after source fix; relevant strategy test files pass.
- Task Buildability Gate: Flutter web app, exact command `rtk flutter build web --release`, observed exit 0 after final task-local executable/test edit.
- Verification ceiling V2; V3 only for concrete related regression. Final repository build is coordinator-owned.
- External configuration action: none.

Stop and return BLOCKED if a required behavior cannot be achieved within allowed scope or safe evidence contradicts the contract. Report exact RED/GREEN commands/results and build result; coordinator owns task status and audit.

## Audit result

AC-001 and AC-002 PASS. The new picker filters the loaded catalog locally and changes the instrument only after selection. Margin and Long percentage normalize a single decimal comma; preview and save use the same normalized strings. Selected-level and entry prices are sent as decimal strings; backend float rejection remains untouched. RED-001 failed on the absent picker and RED-002 failed on numeric price serialization and comma-margin preview before the source fix. Three wizard widget tests and six selection tests passed after the final edit. The task Flutter web build `rtk flutter build web --release` exited 0 after the last task-local code/test edit. The final coordinator build with the same command also exited 0. Changed paths match the allowed surface; no protected configuration path changed. External configuration actions: none.
