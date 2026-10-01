# Task 36 — Reorder primary navigation destinations

Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Target Route: gpt-6-luna / xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE
Requested Model: gpt-6-luna
Requested Effort: xhigh
Observed Effective Model: unavailable
Observed Effective Effort: unavailable
Specification: `docs/agents/specs/2026-10-01-navigation-order-and-content-gap-design.md`
Plan: `docs/agents/plans/2026-10-01-navigation-order-and-content-gap.md`
Requirements: REQ-001/002
Acceptance Criteria: AC-001/002/003

## Objective and Preconditions

Add drag-handle ordering to the existing Settings visibility modal and persist the full order of seven stable IDs. User approval of this task/plan is required before any product/test edit. No predecessor task.

## Allowed Scope

`lib/core/navigation/navigation_preferences.dart`, `navigation_preferences_provider.dart`, `main_navigation_shell.dart`, `lib/features/settings/presentation/settings_screen.dart`, and focused tests in `test/core/navigation/` and `test/features/settings/`. No protected configuration/environment file may be read or changed. Do not alter T37's content-frame files, unrelated screens, dependencies, or Git history.

## Executor Contract

Implement P01–P02. Keep `enabledDestinationIds` as membership and Settings always enabled. Store independent `destinationOrderIds` in version-1 JSON; absent means canonical order. Normalize known IDs in first-seen order and append missing IDs canonically. Modal shows all seven rows in saved order with checkboxes and drag handles, including movable Settings and hidden rows. Bound modal height. Save automatically; disable reorder/checkbox during in-flight save; rollback on failure. Shell orders visible destinations by stored order and maps taps through stable screen IDs. Reorder never changes the selected screen. If repository evidence contradicts this contract, return BLOCKED to coordinator.

## Mandatory RED Then GREEN

- RED-001: Test drag of BMAG after Risk and expect modal/navigation order to change; before implementation this fails because no drag ordering exists. Observe RED before GREEN.
- GREEN-001: After implementation the drag updates bar and floating order, BMAG still opens BMAG, selection remains stable, and encode/decode or rehydration keeps order.
- Add focused checks for hidden-page position on reenable, Settings movement but locked checkbox, malformed/legacy order, and persistence failure rollback.
- Verification ceiling V2; escalate only for a concrete shared navigation regression.

## Buildability and Audit

After final executable/test edit, run `rtk proxy flutter build web --no-pub` for the Flutter web application and record exit/status. Run focused tests in formal RED→GREEN order. Flutter SDK cache permissions may require a sandbox escalation as in task 31; do not treat pre-test startup failure as behavioral RED. Return concise executor evidence, changed paths, no-config-change confirmation, and telemetry envelope. Coordinator independently audits before PASS. External configuration action: none.

## Coordinator Audit — PASS

- Scope: four planned source files and four focused test files changed; no protected configuration path changed.
- RED: focused drag test ran before implementation and failed on the absent drag handle. GREEN: the same scenario passed, with BMAG after Risk and saved order matching the expected sequence.
- Focused tests: preferences 9, provider 6, shell 5, Settings 11 passed. Hidden-page slot, rollback, Settings handle, in-flight save, and stable screen routing are covered.
- Task buildability: `rtk proxy flutter build web --no-pub` exited 0 after the final T36 code/test change; Flutter SDK cache permission needed an accepted escalation. Diff check passed.
- Route: E1 `gpt-6-luna / xhigh` explicitly requested; effective route unavailable (`UNVERIFIABLE`). Verdict: PASS. External configuration action: none.
