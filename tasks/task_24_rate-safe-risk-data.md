# Task 24 — Rate-safe Risk data batching

Status: PASS
Executor: implementation executor
Executor Class: E2
Target Route: Luna Max
Specification: `docs/agents/specs/2026-09-13-multi-position-risk-dashboard-429-vietnamese-design.md`
Plan: `docs/agents/plans/2026-09-13-multi-position-risk-dashboard-429-vietnamese.md`
Plan Steps: P01
Requirements: REQ-001
Acceptance Criteria: AC-001-AC-003

## 1. Objective

Replace burst-prone single-position repository access with bounded, reusable batch/request foundations.

Done when: exact fake-adapter evidence proves one position discovery per batch, paced/single-flight lanes, immediate 429 stop, `Retry-After`, global two-page resumable ledger progress, cache reuse, and shared BTC market requests.

## 2. Preconditions

Predecessors: none.
Required decisions/assumptions: T24 preserves the existing eligibility semantics and is independent of open question Q-004; no assumptions.
Required repository/environment state: preserve current Task 23 working-tree changes; use synthetic adapters only.
Execution authorization: T24 only, granted by the user on 2026-09-14.

## 3. Allowed Scope

- `lib/features/portfolio/data/risk/risk_request_coordinator.dart`
- `lib/features/portfolio/data/risk/risk_repository.dart`
- `lib/features/portfolio/data/risk/risk_market_repository.dart`
- `lib/features/portfolio/presentation/providers/risk_dashboard_provider.dart`
- `test/features/portfolio/risk/risk_request_coordinator_test.dart`
- `test/features/portfolio/risk/risk_repository_test.dart`
- `test/features/portfolio/risk/risk_market_repository_test.dart`
- shared synthetic fixtures under `test/features/portfolio/risk/fixtures/` only if required

## 4. Forbidden Scope

Do not read or modify protected configuration/environment files; change financial formulas/eligibility; edit monitor/UI/notification behavior; add dependencies; use live credentials/services; perform unrelated refactors or Git mutations. If required work exceeds scope, return `BLOCKED`.

## 5. Executor Contract

Follow P01 exactly:
1. Implement injected authenticated/public request lanes with keyed single-flight, concurrency one per lane, >=250 ms spacing, immediate 429 lane closure, capped exponential backoff, and longer `Retry-After` precedence.
2. Add shared position discovery/normalization for all eligible positions with one positions request per capture batch.
3. Make ledger pagination stop at episode boundary and resume fairly without replay, with two pages total across the monitor batch.
4. Share market cache/request keys, including BTC candles once per due batch, without all-position `Future.wait` bursts.

Required invariants: INV-001, INV-003-INV-007, INV-010.
Required edge behavior: EDGE-001, EDGE-002.
Preserved behavior: existing DTO parsing, quality, formula, cache invalidation, credential fencing, and GET-only access.

## 6. External Configuration / Environment Actions

Planned action: none.
Discovered additional action: none expected; otherwise `BLOCKED`.
Blocks verification until user applies: NO.

## 7. Tests

- TEST-001: lane pacing/single-flight/429/Retry-After repository blocking.
- TEST-002: one discovery and globally bounded resumable ledger cursor with episode-boundary stop.
- TEST-003: unique-asset caching and one shared BTC candle request per due batch.

## 8. Mandatory Verification

### RED — RED-001
Scenario: ten positions, multi-page ledger, and deterministic 429.
Command/method: `flutter test test/features/portfolio/risk/risk_request_coordinator_test.dart test/features/portfolio/risk/risk_repository_test.dart test/features/portfolio/risk/risk_market_repository_test.dart --plain-name "RED-001 rate-safe risk request batch" --reporter compact`
Expected: pre-change adapters violate new exact request-count/order/backoff/no-replay assertions.
Actual: PASS — before the hard-limit guard, the scenario failed with 4 ledger requests for `maxLedgerPages=2`; after remediation, the regression guard passed. Coordinator re-ran the selector first during final audit and observed 2 passing tests.
Status: PASS

### GREEN — GREEN-001
Scenario: the same workload through bounded batch contracts.
Command/method: same files with `--plain-name "GREEN-001 rate-safe risk request batch"`.
Expected: all AC-001-AC-003 assertions pass.
Actual: PASS — executor and coordinator runs both passed; coordinator final audit observed all 3 GREEN selector tests passing after RED.
Status: PASS

Verification ceiling: V2.
Escalate only if: repository/API contract evidence invalidates the approved batch interface.

### Task Buildability Gate

Required: YES
Affected canonical build unit: Flutter application
Exact secret-free build command: `flutter build web --no-pub`
Executed after final task-local change: YES
Result: PASS — `flutter build web --no-pub` built `build/web`; existing non-blocking WASM compatibility warnings remain.
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

Return `BLOCKED` for contract mismatch, protected-config dependency, financial-semantic change, live-service requirement, exceeded scope, or unavailable necessary verification.

## 10. Execution Ledger

- [x] inspect referenced symbols
- [x] implement P01
- [x] add/update tests
- [x] execute formal RED then GREEN
- [x] run task buildability gate
- [x] confirm no protected configuration content was read or modified

## 11. Coordinator Audit

Scope: PASS — changed product/test files remain within the T24 allowlist.
Acceptance criteria: PASS — AC-001 through AC-003 are covered, including the cross-batch ledger hard limit.
Test quality: PASS — deterministic tests cover 1/3/10-position fairness, no replay, shared market cache/BTC requests, queued/cooldown suppression, capped backoff, and longer `Retry-After`.
RED evidence: PASS — executor observed the pre-fix failure; coordinator final audit re-ran the RED selector first and observed both regression guards pass.
GREEN evidence: PASS — coordinator observed all 3 GREEN selector tests pass.
RED-before-GREEN: PASS
Architecture/contract conformance: PASS — one shared coordinator, batch discovery, bounded ledger cursor, and market cache foundation preserve current eligibility/formulas.
Task buildability gate: PASS — exit 0 after the final task-local source/test change.
Verdict: PASS
