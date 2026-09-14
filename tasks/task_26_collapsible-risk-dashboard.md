# Task 26 — Collapsible all-position Risk Dashboard

Status: PASS
Executor: implementation executor
Executor Class: E1
Target Route: Luna XHigh
Specification: `docs/agents/specs/2026-09-13-multi-position-risk-dashboard-429-vietnamese-design.md`
Plan: `docs/agents/plans/2026-09-13-multi-position-risk-dashboard-429-vietnamese.md`
Plan Steps: P03
Requirements: REQ-004
Acceptance Criteria: AC-007-AC-009

## 1. Objective

Render every active eligible position as an independently collapsible, compact dashboard section.

Done when: every NORMAL/WATCH/HIGH/failed position is visible, details expand lazily without monitor/network commands, and responsive/privacy/accessibility tests pass.

## 2. Preconditions

Predecessors: T25 = PASS.
Required decisions/assumptions: D-001, D-002; none.
Required repository/environment state: aggregate state and legacy projection from T25 are buildable.

## 3. Allowed Scope

- `lib/features/portfolio/presentation/risk_dashboard_screen.dart`
- `lib/features/portfolio/presentation/widgets/risk/*.dart` only where per-position composition requires it
- `test/features/portfolio/risk/risk_dashboard_test.dart`
- `test/features/portfolio/risk/risk_editors_test.dart`
- shared synthetic fixtures under `test/features/portfolio/risk/fixtures/` if required

## 4. Forbidden Scope

Do not read/modify protected configuration; edit repositories/monitor/runtime/formulas/eligibility/notifications; translate copy yet; add dependencies; change unrelated screens/navigation; fetch or send commands on accordion interaction.

## 5. Executor Contract

Follow P03:
1. Render every aggregate entry in existing deterministic position order and collapsed by default per dashboard visit.
2. Put identity, overall state, buffer, leverage, quality/freshness, and error/alert indication in the compact header with privacy-safe semantics.
3. Lazily render the existing complete per-position details only after expansion; allow independent multiple expansion/collapse.
4. Separate aggregate monitoring/backoff status from per-position failures and remove temporary UI projection where safe.
5. Prove no filtering by severity, no request/command on expansion, no overflow, and no semantic numeric leak.

Required invariants: INV-001, INV-006-INV-010.
Required edge behavior: EDGE-004, EDGE-005.
Preserved behavior: all existing details/editors/history, theme, privacy, and Risk navigation destination.

## 6. External Configuration / Environment Actions

Planned action: none.
Discovered additional action: none expected; otherwise `BLOCKED`.
Blocks verification until user applies: NO.

## 7. Tests

- TEST-008: every severity/failure entry appears and expands independently.
- TEST-009: lazy/no-command expansion, mobile/desktop/large-text/privacy/a11y.

## 8. Mandatory Verification

### RED — RED-003
Scenario: multi-position collapsed dashboard at responsive/privacy boundaries.
Command/method: `flutter test test/features/portfolio/risk/risk_dashboard_test.dart test/features/portfolio/risk/risk_editors_test.dart --plain-name "RED-003 collapsible all-position dashboard" --reporter compact`
Expected: current single-evaluation UI fails aggregate accordion assertions.
Actual: Pre-implementation UI failed because `risk-position-header-btc` was absent; later regression-first checks also exposed legacy-primary drill-down selection, stale omission fallback, cross-account leakage, and missing LONG normalization before their fixes.
Status: PASS

### GREEN — GREEN-003
Scenario: expand ETH while BTC/SUI remain collapsed.
Command/method: same files with `--plain-name "GREEN-003 collapsible all-position dashboard"`.
Expected: AC-007-AC-009 pass and command/request spy count remains zero.
Actual: Exact selector passed after the final changes; ETH and SUI expanded independently, all summaries remained reachable, privacy/accessibility assertions passed, and expansion dispatch count stayed zero.
Status: PASS

Verification ceiling: V2.
Escalate only if: aggregate protocol is missing a field required by the approved summary/detail contract.

### Task Buildability Gate

Required: YES
Affected canonical build unit: Flutter application
Exact secret-free build command: `flutter build web --no-pub`
Executed after final task-local change: YES
Result: PASS
Exit/status: 0
Compiler/parser/type/reference/link/build errors: none; only non-fatal existing Wasm/font warnings

### External Verification

Required: NO
Subtype: N/A
Exact secret-free user-run command: N/A
Proves: N/A
Expected returned evidence: N/A
Task/verification blocked until returned: NO

## 9. Stop Conditions

Return `BLOCKED` for protocol mismatch, network/monitor mutation requirement, privacy/accessibility regression, scope expansion, or unavailable verification.

## 10. Execution Ledger

- [x] inspect referenced symbols
- [x] implement P03
- [x] add/update tests
- [x] execute formal RED then GREEN
- [x] run task buildability gate
- [x] confirm protected configuration boundary

## 11. Coordinator Audit

Scope: PASS — product/test changes are limited to the two authorized T26 files; coordinator-owned telemetry is the only additional changed path; no protected configuration path changed.
Acceptance criteria: PASS — AC-007, AC-008, and AC-009 independently audited PASS.
Test quality: PASS — distinct position/account fixtures prove deterministic order, fresh-visit collapse, independent lazy expansion, selected-episode details/plan/history, latest-known omission handling, same-key account isolation, zero expansion commands, responsive layout, semantic state transitions, and privacy redaction.
RED evidence: PASS — the pre-implementation aggregate selector failed on the absent BTC header; remediation-first tests also observed the isolated contract failures before source fixes.
GREEN evidence: PASS — exact GREEN-003 passed; full dashboard/editor V2 suite passed 25/25; the corrected cross-account same-episode test independently passed 1/1.
RED-before-GREEN: PASS — failures were observed before each corresponding implementation/remediation change, followed by passing final selectors.
Architecture/contract conformance: PASS — accordion state is presentation-only; reactive sheets select by verified account plus episode, fail closed across account boundaries, preserve the latest verified selected snapshot during temporary omission, and retain the long-only direction seam for future short support.
Task buildability gate: PASS — `flutter build web --no-pub` completed with exit 0 after the final task-local test change.
Verdict: PASS — independent final audit closed AUD-T26-001, AUD-T26-002, and AUD-T26-003.
