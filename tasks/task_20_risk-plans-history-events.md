# Task 20 — Local action plans history and risk events

Status: PASS
Executor: implementation executor (configured target gpt-5.6-luna / max; verify effective routing)
Specification: `docs/agents/specs/2026-09-10-isolated-margin-risk-dashboard-design.md`
Plan: `docs/agents/plans/2026-09-10-isolated-margin-risk-dashboard.md`
Plan Steps: P03
Requirements: REQ-007, REQ-008, REQ-009, REQ-011
Acceptance Criteria: AC-007, AC-008, AC-009, AC-011

## 1. Objective

Complete the single auditable outcome in canonical plan §5 P03. Done when the referenced ACs and required negative/success scenarios are observed, scope is audited and coordinator verdict is PASS. Do not substitute a summary for repository evidence.

## 2. Preconditions

Predecessors: T19 = PASS.
Required decisions: D-001–005, A-001. Explicit execution approval of the presented plan is mandatory before dispatch. Coordinator confirms Definition of Ready and reads execution/audit rules. Inspect applicable AGENTS and context optimization profile; preserve existing user changes. Read only relevant specification sections and P03, not all framework/templates.

## 3. Allowed Scope

- `lib/features/portfolio/domain/risk/action_plan.dart`
- `lib/features/portfolio/domain/risk/risk_history.dart`
- `lib/features/portfolio/domain/risk/risk_events.dart`
- `lib/features/portfolio/data/risk/risk_local_store.dart`
- `lib/features/portfolio/application/risk_monitor_bridge.dart`
- `lib/features/portfolio/domain/risk/risk_models.dart (persistence DTO extensions only)`
- `lib/features/portfolio/domain/risk/risk_policy.dart (documented persistence validation only)`
- `test/features/portfolio/risk/action_plan_test.dart`
- `test/features/portfolio/risk/risk_history_test.dart`
- `test/features/portfolio/risk/risk_events_test.dart`
- `test/features/portfolio/risk/risk_local_store_test.dart`

Synthetic fixtures may be created under `test/features/portfolio/risk/fixtures/`. No real account payloads. Executor reports evidence to coordinator; coordinator owns planning/audit metadata and task allocation.

## 4. Forbidden Scope

No unrelated refactors, generated Orders DTO changes, trading API writes, dependency changes, deployment, Git mutations, real credential reads or private API calls. No external services beyond explicitly authorized official OKX documentation. No product-semantic decisions outside the specification. Return BLOCKED if required work exceeds the write surface.

## 5. Executor Contract

Follow canonical P03 in order. Use specification formulas/defaults and missing-data behavior exactly. Domain functions are pure and platform code must reuse them. Honor all applicable INV/EDGE entries called out by P03. Incomplete API data uses specified quality states; do not invent neutral or zero values. User-authored plan text remains text, never a trading command.

Before handoff inspect the diff, scope, changed symbols and test evidence. Do not claim runtime/native verification from mocks. If effective executor model is explicitly reported different from configured target, report BLOCKED.

## 6. Tests

Test files above implement RED-003/GREEN-003 prefixes and independently derived expectations below. Use injected time, storage, HTTP and platform interfaces. Narrow diagnostics first; do not run broad suites during each edit. Existing compatibility checks are listed in the canonical plan.

## 7. Mandatory Verification

### RED — RED-003

Scenario and expected outcome: Repeated same-state sample/restart/jitter produces zero duplicate events. Unknown True Exit makes its rule unknown, not false. Corrupt future-schema record is not overwritten; failed write produces no OS delivery intent. A new account or reopened episode cannot load the prior active plan.

Command: `flutter test test/features/portfolio/risk/action_plan_test.dart test/features/portfolio/risk/risk_history_test.dart test/features/portfolio/risk/risk_events_test.dart test/features/portfolio/risk/risk_local_store_test.dart --plain-name RED-003 --reporter compact`
Actual: Coordinator observed 6/6 pass after the final implementation/test-support change.
Status: PASS

### GREEN — GREEN-003

Scenario and expected outcome: Create/save/reload rules and zones; one real crossing produces one event, two safe samples rearm, confirmed improvement produces one event. Buffer 40% to 31% across 6h yields -1.5pp/h. Freeze previous-check baseline. First observation at 14:00 creates one actual 14:00 summary, no invented 08:00 sample. Retention and local timezone boundaries pass.

Command: `flutter test test/features/portfolio/risk/action_plan_test.dart test/features/portfolio/risk/risk_history_test.dart test/features/portfolio/risk/risk_events_test.dart test/features/portfolio/risk/risk_local_store_test.dart --plain-name GREEN-003 --reporter compact`
Actual: Coordinator observed 11/11 pass after the final RED checkpoint.
Status: PASS

Execute RED before GREEN at the formal checkpoint. After implementation/test-support changes restart the pair under the governing direct-user AGENTS instruction. Verification ceiling: V2. Escalation only for an evidenced shared-surface regression or missing AC evidence. Final full-suite ownership belongs to coordinator integration, not each task.

## 8. Stop Conditions

Return BLOCKED for missing material contract, incompatible API semantics beyond explicit unavailable handling, scope expansion, failed prerequisite, unavailable necessary verification or an explicit model mismatch. Include evidence, affected IDs and needed coordinator decision. Do not silently reduce full scope.

## 9. Execution Ledger

- [x] Definition of Ready and authorization confirmed
- [x] Referenced symbols inspected
- [x] Assigned P03 implemented within allowed scope
- [x] Required tests/fixtures added or updated
- [x] Formal RED executed and observed
- [x] Formal GREEN executed and observed afterward
- [x] Verification ceiling respected
- [x] Compact report: changed files, behavior, commands/results, unresolved limits

## 10. Coordinator Audit

Scope: PASS — implementation and remediation stayed within T20 paths; no T21 work was introduced.
Acceptance criteria: PASS — AC-007, AC-008, AC-009 and AC-011 are satisfied.
Test quality: PASS — independent boundary, failure, persistence, idempotency, edit-reseed and hysteresis coverage is present.
RED evidence: PASS — RED-003 6/6.
GREEN evidence: PASS — GREEN-003 11/11.
RED-before-GREEN: PASS — coordinator ran the final RED checkpoint before the final GREEN checkpoint.
Additional verification: focused T20 suite 17/17; scoped Flutter analyzer clean; `git diff --check` clean.
Architecture/contract conformance: PASS
Evidence reuse vs rerun: Final evidence was rerun after the last test-support change.
Independent audit: PASS — AUD-T20-001 through AUD-T20-011 resolved.
Verdict: PASS

Audit findings:

- AUD-T20-001: Implement the action metric as mark price versus the current verified dynamic True Exit, with above/below semantics and independent mark/T fixtures. Do not compare True Exit itself with a static threshold.
- AUD-T20-002: Preserve asset structure, funding class and OI delta in history conversion and previous-check comparison. The current conversion stores the aggregate market assessment label and drops funding/OI.
- AUD-T20-003: Never confirm risk improvement from partial/incomplete evidence. Track improvement confirmation independently per overall/position/market/recovery component so simultaneous improvements do not overwrite each other.
- AUD-T20-004: Match buffer boundary endpoints exactly, aggregate multiple new factors from one observation into one event, and apply metric-specific user-rule rearm margins: buffer percentage points, leverage 0.2x, ratio 10pp where applicable, price/zone 0.5%, debt/cost 1%.
- AUD-T20-005: Reject trend/velocity claims across any internal sample gap greater than 30 minutes; do not infer a continuous six-hour velocity from endpoint samples alone.
- AUD-T20-006: Validate every persisted numeric field for finiteness before encoding and keep JSON encoding failures inside the typed save-result path so notification delivery remains blocked.
- AUD-T20-007: Debt and daily holding-cost thresholds must be strictly positive, including range endpoints; zero is invalid.
- AUD-T20-008: Duplicate command ids must return the original command outcome while exposing replay separately, and immutable view state must defensively freeze collection fields.
- AUD-T20-009: Detect action-rule and zone definition edits independently of policy-version changes. Reseed edited definitions without emitting market-crossing events; configuration edits remain configuration events.
- AUD-T20-010: Add independent event-reducer coverage for every metric-specific rearm margin, mirrored operators, inclusive ranges, the two-sample/30-second rearm requirement, and values just inside each margin.
- AUD-T20-011: Add explicit validation coverage proving zero debt and holding-cost thresholds are rejected for scalar and range endpoints.

Second audit note: AUD-T20-010 remains open until user-rule buffer/leverage and inclusive-range behavior for every metric-specific margin are tested directly on both safe sides, including just-inside values and two samples at least 30 seconds apart. AUD-T20-011 remains open until upper-zero debt/cost assertions target the strict-positive validation error independently of range ordering.
