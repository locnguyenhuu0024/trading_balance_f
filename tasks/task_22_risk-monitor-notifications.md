# Task 22 — Risk monitoring notifications and integration

Status: PENDING
Executor: implementation executor (configured target gpt-5.6-luna / max; verify effective routing)
Specification: `docs/agents/specs/2026-09-10-isolated-margin-risk-dashboard-design.md`
Plan: `docs/agents/plans/2026-09-10-isolated-margin-risk-dashboard.md`
Plan Steps: P05
Requirements: REQ-009, REQ-011
Acceptance Criteria: AC-009, AC-011; integration of all ACs

## 1. Objective

Complete the single auditable outcome in canonical plan §5 P05. Done when the referenced ACs and required negative/success scenarios are observed, scope is audited and coordinator verdict is PASS. Do not substitute a summary for repository evidence.

## 2. Preconditions

Predecessors: T21 = PASS.
Required decisions: D-001–005, A-001. Explicit execution approval of the presented plan is mandatory before dispatch. Coordinator confirms Definition of Ready and reads execution/audit rules. Inspect applicable AGENTS and context optimization profile; preserve existing user changes. Read only relevant specification sections and P05, not all framework/templates.

## 3. Allowed Scope

- `lib/features/portfolio/application/risk_monitor.dart`
- `lib/features/portfolio/application/risk_monitor_runtime.dart`
- `lib/features/portfolio/application/risk_notification_sink.dart`
- `lib/core/services/background_service.dart`
- `lib/main.dart (risk bootstrap and WebStorageHelper credential invalidation only)`
- `lib/core/security/secure_storage_helper.dart (credential invalidation only)`
- `lib/features/portfolio/presentation/providers/risk_dashboard_provider.dart (runtime bridge wiring only)`
- `test/widget_test.dart (fake runtime injection only)`
- `test/features/portfolio/risk/risk_monitor_test.dart`
- `test/features/portfolio/risk/risk_runtime_test.dart`
- `test/features/portfolio/risk/risk_notification_test.dart`

Synthetic fixtures may be created under `test/features/portfolio/risk/fixtures/`. No real account payloads. Executor reports evidence to coordinator; coordinator owns planning/audit metadata and task allocation.

## 4. Forbidden Scope

No unrelated refactors, generated Orders DTO changes, trading API writes, dependency changes, deployment, Git mutations, real credential reads or private API calls. No external services beyond explicitly authorized official OKX documentation. No product-semantic decisions outside the specification. Return BLOCKED if required work exceeds the write surface.

## 5. Executor Contract

Follow canonical P05 in order. Use specification formulas/defaults and missing-data behavior exactly. Domain functions are pure and platform code must reuse them. Honor all applicable INV/EDGE entries called out by P05. Incomplete API data uses specified quality states; do not invent neutral or zero values. User-authored plan text remains text, never a trading command.

Before handoff inspect the diff, scope, changed symbols and test evidence. Do not claim runtime/native verification from mocks. If effective executor model is explicitly reported different from configured target, report BLOCKED.

## 6. Tests

Test files above implement RED-005/GREEN-005 prefixes and independently derived expectations below. Use injected time, storage, HTTP and platform interfaces. Narrow diagnostics first; do not run broad suites during each edit. Existing compatibility checks are listed in the canonical plan.

## 7. Mandatory Verification

### RED — RED-005

Scenario and expected outcome: Permission denial, native unavailable, service disconnect/restart, duplicated command, 401/429 and late prior-account response cause no PnL event, no extra owner and no wrong-account write. Failed durable latch write causes zero OS notifications. Stale/unchanged reconnect does not spam.

Command: `flutter test test/features/portfolio/risk/risk_monitor_test.dart test/features/portfolio/risk/risk_runtime_test.dart test/features/portfolio/risk/risk_notification_test.dart --plain-name RED-005 --reporter compact`
Actual: PENDING
Status: PENDING

### GREEN — GREEN-005

Scenario and expected outcome: Fake HTTP/clock/storage/sink pipeline persists one event before one delivery; restart reuses latch. Worsening and confirmed improvement both deliver once. Cadences stay bounded/no overlap. Native bridge and foreground owner publish equivalent state. Run final integration checks only after scoped verification is PASS.

Command: `flutter test test/features/portfolio/risk/risk_monitor_test.dart test/features/portfolio/risk/risk_runtime_test.dart test/features/portfolio/risk/risk_notification_test.dart --plain-name GREEN-005 --reporter compact`
Actual: PENDING
Status: PENDING

Execute RED before GREEN at the formal checkpoint. After implementation/test-support changes restart the pair under the governing direct-user AGENTS instruction. Verification ceiling: V3. Escalation only for an evidenced shared-surface regression or missing AC evidence. Final full-suite ownership belongs to coordinator integration, not each task.

## 8. Stop Conditions

Return BLOCKED for missing material contract, incompatible API semantics beyond explicit unavailable handling, scope expansion, failed prerequisite, unavailable necessary verification or an explicit model mismatch. Include evidence, affected IDs and needed coordinator decision. Do not silently reduce full scope.

## 9. Execution Ledger

- [ ] Definition of Ready and authorization confirmed
- [ ] Referenced symbols inspected
- [ ] Assigned P05 implemented within allowed scope
- [ ] Required tests/fixtures added or updated
- [ ] Formal RED executed and observed
- [ ] Formal GREEN executed and observed afterward
- [ ] Verification ceiling respected
- [ ] Compact report: changed files, behavior, commands/results, unresolved limits

## 10. Coordinator Audit

Scope: PENDING
Acceptance criteria: PENDING
Test quality: PENDING
RED evidence: PENDING
GREEN evidence: PENDING
RED-before-GREEN: PENDING
Architecture/contract conformance: PENDING
Evidence reuse vs rerun: PENDING
Verdict: PENDING
