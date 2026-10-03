# Task 63 — Ten-order Admission Frontend

Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Target Route: gpt-6-luna / xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-10-03-strategy-limit-cap-resubmission-design.md`
Plan: `docs/agents/plans/2026-10-03-strategy-limit-cap-resubmission.md`
Plan Steps: P02
Requirements: REQ-002,003,004
Acceptance Criteria: AC-002,003,004

## 1. Dispatch Compliance

Bind role, class, model and effort explicitly before mutation; coordinator remains non-writing for implementation. Dispatch Route Status: UNVERIFIABLE. Requested Model: gpt-6-luna. Requested Effort: xhigh. Observed Effective Model/Effort: unavailable. Explicit request without exposed effective route may be UNVERIFIABLE; mismatch stops mutation; unavailable binding is BLOCKED_ROUTE, never inherited fallback.

## 2. Objective

Apply the combined ten-order selection and confirmation limit without breaking historical twenty-row rendering.

Done when assigned acceptance tests, RED-before-GREEN, affected-unit build and independent coordinator audit all PASS.

## 3. Preconditions

Predecessors: T62 = PASS.
Decisions: D-001..004, A-001..002 in current decision ledger. Canonical plan must be presented and explicitly authorized after presentation before dispatch. Source baseline includes audited T61 diagnostics.

## 4. Allowed Scope

- `lib/features/strategy/domain/strategy_selection.dart`
- `lib/features/strategy/domain/strategy_models.dart`
- `lib/features/strategy/presentation/providers/strategy_dashboard_provider.dart`
- `lib/features/strategy/presentation/strategy_wizard_dialog.dart`
- `lib/features/strategy/presentation/strategy_screen.dart`
- `test/features/strategy/strategy_selection_test.dart`
- `test/features/strategy/strategy_wizard_dialog_test.dart`
- `test/features/strategy/strategy_dashboard_controller_test.dart`
- `test/features/strategy/strategy_screen_test.dart`

## 5. Forbidden Scope

No protected configuration content access or mutation, dependencies, manifests, env, Docker/scripts/CI/deployment settings, schema/store changes, live orders, external uploads, Git writes, canonical artifact/status/telemetry writes or opportunistic refactors. Listed explanatory Markdown is allowed documentation. Required work beyond this surface returns BLOCKED for coordinator replan.

## 6. Executor Contract

1. Bound domain/wizard selection to10 combined; display Đã chọn N/10 lệnh · Long B · Short S. Rejected11th toggle preserves previous selected IDs, entry choices and valid preview.
2. Add a new-submission validator max10 while retaining historical prepared/result/queue readers through20. Guard Next, preview, Save, prepare ACK, confirmation and controller execute admission.
3. Disable old oversized unstarted Apply with recreate guidance; respect existing canDelete, source ownership and session/action serialization.
4. Preserve historical progress20 and current ordinary recreate semantics. No retry API or dialog is introduced in this task.

Preserve specification INV-001..006 where affected. Requirements/architecture are coordinator-owned; report contradictions instead of inventing semantics or escalating routes.

## 7. External Configuration / Environment Actions

Planned actions: NONE. Additional unknown configuration requirements: BLOCKED; ask minimum safe fact via coordinator. No user-applied configuration required for offline verification.

## 8. Tests

TEST-63: Selection, wizard, dashboard controller and screen groups; spy call counts for forbidden Save/execute and stable selection after rejection.

## 9. Mandatory Verification

### RED — RED-002

Scenario: 11th toggle and forged11-order preview/prepared response cannot Save/confirm/execute; oversized unstarted card cannot Apply.
Method: offline focused cases within allowed test files; executor reports exact case names and RTK/native command before terminal report. Expected: all negative safety assertions PASS with explicit call/state counts. Actual/status: PASS; exact final commands below.

### GREEN — GREEN-002

Scenario: Mixed10 selection shows correct counter and supports one normal execute; historical20 progress still renders.
Method: separate offline focused cases after RED; exact command/case names recorded. Expected: successful behavior and preserved invariants PASS. Actual/status: PASS; exact final commands below.

Run formal RED then GREEN after readiness; RED is a passing negative scenario, not a deliberately failing suite. Narrow diagnostics during editing are not formal evidence. Later executable changes invalidate affected evidence only. Verification ceiling: V3 affected groups; V4 not required. Broaden only for a concrete regression/shared-path risk and record why. RTK-first; exact/raw fallback only with evidence/compatibility reason. WSGI loopback tests may require sandbox escalation; do not diagnose by opening config.

### Task Buildability Gate

Required: YES. Unit: Flutter web. Boundary: self-contained compatible change; no later task restores compilation.

```sh
/Users/locnguyen/.local/bin/rtk flutter build web --no-pub --release --dart-define=TRADE_API_BASE_URL=https://api.tradingbalancef.com
```

Run after final task-local executable/test edit. Result: PASS; exit0, no build errors; after final executable edit. Tests are not substitutes for canonical application build. Code failure => REWORK; genuine toolchain pre-build failure => BLOCKED_ENVIRONMENT. Consume configs only as opaque native-tool input.

### External Verification

Required: NO. Offline fake exchange only; production behavior is not verified.

## 10. Stop Conditions

Return BLOCKED for insufficient contract, ownership/lineage ambiguity, scope mismatch, predecessor invalidation, required protected facts or unavailable verification; report affected REQ/AC and concise evidence. Do not change architecture or broaden surface unilaterally.

## 11. Execution Ledger

- [x] Explicit dispatch and no parent inheritance verified.
- [x] Assigned step and tests implemented within surface.
- [x] Formal RED then GREEN PASS with exact names/commands/results.
- [x] V3 affected regressions sufficiently verified.
- [x] Final affected-unit build PASS after last executable edit.
- [x] No protected content access or modification; external actions NONE.
- [x] Compact terminal report and safe telemetry envelope returned; no runtime IDs persisted.

## 12. Coordinator Audit

Scope/AC/test quality/RED/GREEN/order/contract/build: PASS. Dispatch UNVERIFIABLE after explicit binding; inheritance NO. Executor evidence reused following independent diff/test review. Verdict: PASS. Coordinator records audit and canonical status; executor does not.

Final evidence: RED7 then GREEN4 PASS; affected53 PASS. Exact observed commands, each exit0 (native Flutter at /Users/locnguyen/development/flutter/bin/flutter; SDK cache write escalation used after RTK-first sandbox failures):

```sh
rtk flutter test test/features/strategy/strategy_selection_test.dart test/features/strategy/strategy_wizard_dialog_test.dart test/features/strategy/strategy_dashboard_controller_test.dart test/features/strategy/strategy_screen_test.dart --plain-name RED-002
rtk flutter test test/features/strategy/strategy_selection_test.dart test/features/strategy/strategy_wizard_dialog_test.dart test/features/strategy/strategy_dashboard_controller_test.dart test/features/strategy/strategy_screen_test.dart --plain-name GREEN-002
rtk flutter test test/features/strategy/strategy_selection_test.dart test/features/strategy/strategy_wizard_dialog_test.dart test/features/strategy/strategy_dashboard_controller_test.dart test/features/strategy/strategy_screen_test.dart
/Users/locnguyen/.local/bin/rtk flutter build web --no-pub --release --dart-define=TRADE_API_BASE_URL=https://api.tradingbalancef.com
```

Audit: `docs/agents/audits/2026-10-03-task63-ten-order-cap-audit.md`. Build/web produced; nonblocking Wasm and icon-font warnings. No later executable edits.
