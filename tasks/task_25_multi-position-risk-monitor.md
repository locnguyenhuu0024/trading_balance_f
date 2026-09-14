# Task 25 — Aggregate multi-position Risk monitor

Status: PENDING
Executor: implementation executor
Executor Class: E2
Target Route: Luna Max
Specification: `docs/agents/specs/2026-09-13-multi-position-risk-dashboard-429-vietnamese-design.md`
Plan: `docs/agents/plans/2026-09-13-multi-position-risk-dashboard-429-vietnamese.md`
Plan Steps: P02
Requirements: REQ-001-REQ-003
Acceptance Criteria: AC-003-AC-006

## 1. Objective

Refactor the single owner to monitor, persist, and alert every eligible open isolated-margin episode simultaneously.

Done when: aggregate state contains all positions, each episode is isolated through lifecycle/persistence/events/notifications, refresh respects shared backoff, and service/foreground wire parity passes.

## 2. Preconditions

Predecessors: T24 = PASS.
Required decisions/assumptions: D-001; none.
Required repository/environment state: use T24 batch contracts and preserve existing records/schema.

## 3. Allowed Scope

- `lib/features/portfolio/application/risk_monitor.dart`
- `lib/features/portfolio/application/risk_monitor_bridge.dart`
- `lib/features/portfolio/application/risk_monitor_runtime.dart`
- `lib/features/portfolio/application/risk_notification_sink.dart` only for per-position routing, not translation
- `lib/features/portfolio/domain/risk/risk_models.dart` only for aggregate typed state support if required
- `lib/features/portfolio/data/risk/risk_local_store.dart` only if compatible multi-episode orchestration requires a non-schema API addition
- `test/features/portfolio/risk/risk_monitor_test.dart`
- `test/features/portfolio/risk/risk_runtime_test.dart`
- `test/features/portfolio/risk/risk_notification_test.dart`
- `test/features/portfolio/risk/risk_local_store_test.dart`
- `test/features/portfolio/risk/risk_events_test.dart`
- `test/features/portfolio/risk/risk_history_test.dart`
- shared synthetic fixtures under `test/features/portfolio/risk/fixtures/` if required

## 4. Forbidden Scope

Do not read/modify protected configuration; change formulas, thresholds, eligibility, storage schema/keys, UI copy/layout, dependencies, trading APIs, or unrelated files. Do not create one owner/timer/repository per position.

## 5. Executor Contract

Follow P02:
1. Introduce `RiskPositionMonitorViewState` and episode-keyed runtime contexts under one owner/timer/serialized queue.
2. Fairly update every active eligible position from one batch and publish an immutable ordered list plus aggregate request status.
3. Preserve per-episode plan/history/latch/event/sample/summary/previous-check/market state and durable-before-delivery ordering.
4. Flush/remove closed positions without deleting history; reopened episodes start clean.
5. Make manual refresh global/coalesced and unable to bypass T24 backoff.
6. Round-trip all entries through service wire codec and retain a temporary legacy primary projection for current UI buildability.

Required invariants: INV-001-INV-007, INV-010.
Required edge behavior: EDGE-001-EDGE-004.
Preserved behavior: single owner, notification privacy, formulas, account isolation, current platform ownership.

## 6. External Configuration / Environment Actions

Planned action: none.
Discovered additional action: none expected; otherwise `BLOCKED`.
Blocks verification until user applies: NO.

## 7. Tests

- TEST-004: fair all-position monitoring and isolated failure/last-good state.
- TEST-005: independent episode storage/history/plan/latch lifecycle including close/reopen.
- TEST-006: one durable privacy-safe alert per event/episode.
- TEST-007: populated aggregate foreground/service wire parity and no duplicate owner.

## 8. Mandatory Verification

### RED — RED-002
Scenario: BTC NORMAL, ETH WATCH, SUI HIGH across lifecycle/failure/wire fixtures.
Command/method: `flutter test test/features/portfolio/risk/risk_monitor_test.dart test/features/portfolio/risk/risk_runtime_test.dart test/features/portfolio/risk/risk_notification_test.dart --plain-name "RED-002 aggregate multi-position monitor" --reporter compact`
Expected: current singular state cannot satisfy aggregate/isolation assertions.
Actual: PENDING
Status: PENDING

### GREEN — GREEN-002
Scenario: simultaneous monitoring, isolated events, and open/close/reopen.
Command/method: same files with `--plain-name "GREEN-002 aggregate multi-position monitor"`.
Expected: AC-004-AC-006 pass with no cross-episode writes or duplicate owner.
Actual: PENDING
Status: PENDING

Verification ceiling: V3.
Escalate only if: schema migration or UI change is required to make the task buildable.

### Task Buildability Gate

Required: YES
Affected canonical build unit: Flutter application
Exact secret-free build command: `flutter build web --no-pub`
Executed after final task-local change: NO
Result: PENDING
Exit/status: PENDING
Compiler/parser/type/reference/link/build errors: PENDING

### External Verification

Required: NO
Subtype: N/A
Exact secret-free user-run command: N/A
Proves: N/A
Expected returned evidence: N/A
Task/verification blocked until returned: NO

## 9. Stop Conditions

Return `BLOCKED` for schema/config dependency, cross-episode leakage, duplicate ownership, changed risk semantics, scope expansion, or unavailable verification.

## 10. Execution Ledger

- [ ] inspect referenced symbols
- [ ] implement P02
- [ ] add/update tests
- [ ] execute formal RED then GREEN
- [ ] run task buildability gate
- [ ] confirm protected configuration boundary

## 11. Coordinator Audit

Scope: PENDING
Acceptance criteria: PENDING
Test quality: PENDING
RED evidence: PENDING
GREEN evidence: PENDING
RED-before-GREEN: PENDING
Architecture/contract conformance: PENDING
Task buildability gate: PENDING
Verdict: PENDING
