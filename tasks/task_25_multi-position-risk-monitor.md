# Task 25 — Aggregate multi-position Risk monitor

Status: PASS
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
Required decisions/assumptions: D-001, D-004; none.
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
7. Keep position direction explicit or preserve an equivalent extension seam for future short isolated-margin support; do not implement or infer short formulas in this task.

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
Actual: The executor did not observe a failing pre-change RED-002 run. Post-change execution passes, but this is not substituted for missing pre-change evidence.
Status: NOT OBSERVED — process evidence gap recorded; no failure is fabricated.

### GREEN — GREEN-002
Scenario: simultaneous monitoring, isolated events, and open/close/reopen.
Command/method: same files with `--plain-name "GREEN-002 aggregate multi-position monitor"`.
Expected: AC-004-AC-006 pass with no cross-episode writes or duplicate owner.
Actual: Coordinator observed 1/1 matching GREEN-002 test pass after the final remediation; the full Risk test directory passed 107/107.
Status: PASS

Verification ceiling: V3.
Escalate only if: schema migration or UI change is required to make the task buildable.

### Task Buildability Gate

Required: YES
Affected canonical build unit: Flutter application
Exact secret-free build command: `flutter build web --no-pub`
Executed after final task-local source change: YES. The later final change affected test assertions only and did not invalidate the source build.
Result: PASS — `✓ Built build/web`; existing non-blocking WASM compatibility warnings only.
Exit/status: 0
Compiler/parser/type/reference/link/build errors: none

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

- [x] inspect referenced symbols
- [x] implement P02
- [x] add/update tests
- [ ] execute formal RED then GREEN — GREEN observed; pre-change RED failure was not observed and is recorded as a process evidence gap
- [x] run task buildability gate
- [x] confirm protected configuration boundary

## 11. Coordinator Audit

Scope: PASS — product/source/test changes stayed within T25 write surfaces; coordinator-only planning, task, decision, and telemetry updates are separately authorized framework evidence.
Acceptance criteria: PASS — aggregate long isolated-margin monitoring, episode isolation, close/reopen, durable pending retry, global backoff/coalescing, and service wire parity are covered.
Test quality: PASS — includes 1/3-position aggregate flows, isolated failures, discovery failure, 429 recovery/reset, coalescing, exact pending plan/event/OI retention, close/reopen, notification routing, and deep foreground/service wire parity.
RED evidence: NOT OBSERVED — no failing pre-change RED-002 execution was captured; post-change RED-named test results are not treated as RED evidence.
GREEN evidence: PASS — final GREEN-002 1/1; full Risk suite 107/107; final pending-event audit test 1/1; scoped analyzer clean.
RED-before-GREEN: NOT OBSERVED — transparent process exception; behavioral and regression evidence passed independently.
Architecture/contract conformance: PASS — one owner/timer/serialized queue, episode-keyed contexts, immutable ordered aggregate state, legacy projection, and explicit long direction seam; no short formulas introduced.
Task buildability gate: PASS — web build exit 0 after final source change; final test-only assertion change does not affect application buildability.
Independent audit: Three REWORK reviews identified pending-state retention, aggregate discovery/backoff/coalescing coverage, deep wire parity, recovery backoff reset, analyzer cleanliness, and the final pending-event evidence gap. All findings were remediated and the final narrow change was verified by coordinator source inspection and focused tests.
Verdict: PASS WITH RECORDED PROCESS EVIDENCE GAP — product contract and required build/tests pass; missing pre-change RED observation is retained explicitly and was not reconstructed or fabricated.
