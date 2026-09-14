# Implementation Plan: Multi-position Risk Dashboard, 429 resilience, and Vietnamese UI

Status: BLOCKED_ON_CLARIFICATION
Date: 2026-09-13
Tier: L
Specification: `docs/agents/specs/2026-09-13-multi-position-risk-dashboard-429-vietnamese-design.md`
Decision Ledger: `docs/agents/decisions/2026-09-13-multi-position-risk-dashboard-429-vietnamese-decisions.md`

## 1. Objective

Implements: REQ-001 through REQ-005
Acceptance: AC-001 through AC-012

## 2. Preconditions

Decisions/assumptions: D-001, D-002, D-003; no authorized assumptions.
Predecessor/environment/repository state:
- Task 23 screen split is present in the current working tree and must remain intact.
- Preserve all current user-owned changes; never restore/rewrite the working tree wholesale.
- Existing formulas, eligibility rules, storage keys, and notification privacy contracts remain authoritative.
- No protected configuration content is required.

## 3. Repository Impact

| Area | File | Symbol | Change Type |
|---|---|---|---|
| Request control | `lib/features/portfolio/data/risk/risk_request_coordinator.dart` | keyed lanes, pacing, retry/backoff | ADD |
| Position data | `lib/features/portfolio/data/risk/risk_repository.dart` | batch discovery/enrichment, resumable ledger | MODIFY |
| Market data | `lib/features/portfolio/data/risk/risk_market_repository.dart` | shared caches/batch load/Retry-After | MODIFY |
| Provider wiring | `lib/features/portfolio/presentation/providers/risk_dashboard_provider.dart` | shared coordinator/repository wiring | MODIFY |
| Monitor | `lib/features/portfolio/application/risk_monitor.dart` | per-episode contexts and aggregate capture | MODIFY |
| State protocol | `lib/features/portfolio/application/risk_monitor_bridge.dart` | per-position state and wire codec | MODIFY |
| Runtime | `lib/features/portfolio/application/risk_monitor_runtime.dart` | aggregate state parity/ownership | MODIFY |
| Notification | `lib/features/portfolio/application/risk_notification_sink.dart` | per-position delivery context | MODIFY |
| Dashboard | `lib/features/portfolio/presentation/risk_dashboard_screen.dart` | aggregate collapsible sections | MODIFY |
| Risk widgets | `lib/features/portfolio/presentation/widgets/risk/*.dart` | per-position composition and Vietnamese copy | MODIFY |
| Localization | `lib/features/portfolio/presentation/risk_vietnamese_formatter.dart` | typed/legacy Vietnamese formatter | ADD |
| Repository tests | `test/features/portfolio/risk/risk_repository_test.dart` | batch/ledger/request bounds | MODIFY |
| Market tests | `test/features/portfolio/risk/risk_market_repository_test.dart` | shared cache/batch/backoff | MODIFY |
| Request tests | `test/features/portfolio/risk/risk_request_coordinator_test.dart` | pacing/single-flight/lane behavior | ADD |
| Monitor tests | `test/features/portfolio/risk/risk_monitor_test.dart` | all-position isolation/fairness | MODIFY |
| Runtime tests | `test/features/portfolio/risk/risk_runtime_test.dart` | aggregate wire/ownership parity | MODIFY |
| Notification tests | `test/features/portfolio/risk/risk_notification_test.dart` | per-position delivery/privacy | MODIFY |
| Store/history/event tests | existing risk test files as explicitly listed in T25 | compatibility/isolation assertions | MODIFY IF REQUIRED |
| Dashboard/editor tests | `test/features/portfolio/risk/risk_dashboard_test.dart`, `risk_editors_test.dart` | accordion and Vietnamese UI | MODIFY |
| Copy audit | `test/features/portfolio/risk/risk_vietnamese_copy_test.dart` | allowlisted English-literal guard | ADD |

New files: `risk_request_coordinator.dart`, its test, `risk_vietnamese_formatter.dart`, and its source-audit test.
Explicitly not modified: protected configuration/environment files, dependency/build/CI/deployment files, Portfolio/Orders/Market domain behavior, financial formulas, unsupported position semantics, navigation, and trading APIs.

## 4. External Configuration / Environment Actions

Required actions: none.

## 5. Dependency Graph

```text
T24 / P01 -> T25 / P02 -> T26 / P03 -> T27 / P04 -> final audit
```

## 6. Ordered Implementation Steps

### P01 — Build bounded request and batch repository foundations

Objective: remove request bursts and expose rate-safe batch position/market data.
Implements: REQ-001, AC-001 through AC-003
Files: request coordinator, position/market repositories, provider wiring, focused repository tests.
Symbols: `RiskRepository`, `_fetchInterestLedger`, `RiskMarketRepository`, new request lanes/batch contracts.
Dependencies: none.

Required changes:
1. Add an injected clock/delay request coordinator with authenticated/public lanes, keyed single-flight, one active request per lane, >=250 ms spacing, immediate lane closure on 429, 30/60/120/300-second backoff, and longer `Retry-After` precedence.
2. Split position discovery/normalization from enrichment so one capture obtains all eligible positions with one positions request.
3. Make ledger pagination incremental: two pages total per monitor batch, fair cursor rotation, cache completed pages, stop at trustworthy episode-start boundary, and never replay completed pages absent invalidation.
4. Add market batch/cache behavior: unique asset/timeframe keys, BTC candle sharing, one funding/OI request per derivative when due, stale-while-revalidate quality, and no per-position `Future.wait` burst.
5. Preserve endpoint/status/retry metadata without payload/header leakage.

Must preserve: INV-001, INV-003 through INV-007, INV-010.
Must NOT: change eligibility, formulas, endpoint meanings, dependencies, or configuration.
Edge cases: EDGE-001, EDGE-002.
Tests: TEST-001 through TEST-003.

RED verification:
- scenario: RED-001 request burst/backoff fixture.
- command/method: `flutter test test/features/portfolio/risk/risk_request_coordinator_test.dart test/features/portfolio/risk/risk_repository_test.dart test/features/portfolio/risk/risk_market_repository_test.dart --plain-name "RED-001 rate-safe risk request batch" --reporter compact`
- expected: bounded counts, lane-stop, resume, shared BTC/cache, and no-replay assertions fail before implementation.

GREEN verification:
- scenario: rate-safe batch adapters.
- command/method: same files with `--plain-name "GREEN-001 rate-safe risk request batch"`.
- expected: exact request-count/order/backoff/fairness assertions pass.

Stop conditions:
- safe batching requires changing financial/eligibility semantics;
- repository evidence requires a storage migration or protected configuration change.

### P02 — Refactor the single owner into aggregate per-episode monitoring

Objective: evaluate, persist, and alert all eligible positions simultaneously without duplicate owners.
Implements: REQ-001 through REQ-003, AC-003 through AC-006
Files: monitor, bridge, runtime, notification sink, and focused monitor/runtime/store/event/history/notification tests.
Symbols: `RiskMonitor`, `RiskMonitorViewState`, new `RiskPositionMonitorViewState`, wire codecs, episode context map.
Dependencies: P01.

Required changes:
1. Replace singular episode working fields with a map keyed by episode while retaining account-wide settings and one owner/timer/work queue.
2. Run one batch discovery then fairly update each active context; publish immutable ordered entries and aggregate request/owner status.
3. Load/save/reduce/deliver independently per episode; flush closed contexts without deleting retained records; start reopened episodes clean.
4. Make refresh one coalesced global batch that respects active lane backoff and never clears stable caches/ledger progress.
5. Round-trip all aggregate/per-position fields through foreground and Android service wire paths.
6. Retain a temporary legacy primary-position projection until P03 consumes the aggregate list so T25 is independently buildable.

Must preserve: INV-001 through INV-007, INV-010.
Must NOT: spawn one monitor per position, combine risk ratings, merge alerts, or leak episode data.
Edge cases: EDGE-001 through EDGE-004.
Tests: TEST-004 through TEST-007.

RED verification:
- scenario: RED-002 multi-position isolation/429 continuation fixture.
- command/method: `flutter test test/features/portfolio/risk/risk_monitor_test.dart test/features/portfolio/risk/risk_runtime_test.dart test/features/portfolio/risk/risk_notification_test.dart --plain-name "RED-002 aggregate multi-position monitor" --reporter compact`
- expected: current singular state cannot publish/round-trip/isolate three simultaneous episodes.

GREEN verification:
- scenario: GREEN-002 BTC/ETH/SUI lifecycle.
- command/method: same files with `--plain-name "GREEN-002 aggregate multi-position monitor"`.
- expected: all entries, isolation, fair progress, close/reopen, durable delivery, and bridge parity pass.

Stop conditions:
- aggregate state cannot remain backward compatible at the T25 build boundary;
- one failed episode necessarily blocks all others beyond account-wide auth/backoff semantics.

### P03 — Render compact collapsible per-position dashboards

Objective: expose every active eligible position, not only warning positions, without network work from UI expansion.
Implements: REQ-004, AC-007 through AC-009
Files: dashboard screen, required risk widgets, dashboard/editor tests.
Symbols: `_DashboardBody`, `_MonitorStatus`, `_PositionContext`, new position accordion composition.
Dependencies: P02.

Required changes:
1. Render all active entries in deterministic existing position order with each section collapsed on a new visit.
2. Show compact summary identity/state/buffer/leverage/quality/freshness/error subject to privacy.
3. Lazily compose the current full detail/editor/history tree only for expanded entries; allow independent expansion and collapse.
4. Keep global monitor/backoff status distinct from per-position quality/errors and remove the temporary legacy UI projection if no longer needed.
5. Prove mobile/desktop/large-text/privacy/accessibility behavior and zero command/request side effects from accordion interaction.

Must preserve: INV-001, INV-006 through INV-010.
Must NOT: filter out NORMAL positions, sort by warning alone, or fetch on expansion.
Edge cases: EDGE-004, EDGE-005.
Tests: TEST-008, TEST-009.

RED verification:
- scenario: RED-003 compact multi-position boundary.
- command/method: `flutter test test/features/portfolio/risk/risk_dashboard_test.dart test/features/portfolio/risk/risk_editors_test.dart --plain-name "RED-003 collapsible all-position dashboard" --reporter compact`
- expected: the current one-evaluation UI cannot show all collapsed entries or isolate expanded detail.

GREEN verification:
- scenario: GREEN-003 independent expansion.
- command/method: same files with `--plain-name "GREEN-003 collapsible all-position dashboard"`.
- expected: all summaries stay reachable, one detail tree expands correctly, no commands fire, and layout/privacy assertions pass.

Stop conditions:
- expansion requires monitor mutation/network access;
- existing per-position editor contracts cannot be scoped without changing product semantics.

### P04 — Localize every Risk Dashboard surface into Vietnamese

Objective: complete D-003 only after P01-P03 are audited PASS.
Implements: REQ-005, AC-010 through AC-012
Files: Vietnamese formatter, Risk Dashboard/widgets, and affected rendered-copy tests.
Symbols: UI literals, label helpers, reason/error/event/history formatting, semantics/tooltips/validation.
Dependencies: P03.

Required changes:
1. Add a centralized typed Vietnamese catalog/formatter used by Risk Dashboard presentation surfaces.
2. Translate all dashboard headers, summaries, details, sheets, dialogs, actions, validation, snackbars, empty/error/stale/partial/backoff states, in-dashboard history, semantics, and tooltips.
3. Translate generated/known legacy reason and event templates at the presentation boundary; render unknown upstream prose as a safe generic Vietnamese message with status/source metadata.
4. Preserve user-authored text verbatim and allowlist technical identifiers, units, coin/instrument/source names, and stable wire/storage values.
5. Add source-audit and rendered-state tests that detect new unapproved English copy.

Must preserve: INV-009, INV-010 and all functional P01-P03 behavior.
Must NOT: translate/mutate persistence or wire values, user text, financial units, API paths, or unrelated screens.
Edge cases: EDGE-006 plus all prior UI/failure states.
Tests: TEST-010 through TEST-012.

RED verification:
- scenario: RED-004 English-copy audit after functional tasks pass.
- command/method: `flutter test test/features/portfolio/risk/risk_dashboard_test.dart test/features/portfolio/risk/risk_editors_test.dart test/features/portfolio/risk/risk_vietnamese_copy_test.dart --plain-name "RED-004 Vietnamese Risk Dashboard" --reporter compact`
- expected: current English headings/dynamic states violate the Vietnamese contract.

GREEN verification:
- scenario: GREEN-004 complete Vietnamese experience.
- command/method: same files with `--plain-name "GREEN-004 Vietnamese Risk Dashboard"`.
- expected: all translated surfaces pass while identifiers/user content/privacy remain unchanged.

Stop conditions:
- a required string cannot be distinguished from user-authored or source identity data;
- translation would require changing storage/wire compatibility.

## 7. Test and Verification Plan

| Test | Proves | Level | Command/Method |
|---|---|---|---|
| TEST-001 | paced keyed request lanes and Retry-After | unit | request coordinator tests |
| TEST-002 | single batch discovery and resumable global ledger budget | repository | risk repository tests |
| TEST-003 | shared BTC/asset market caches and no burst | repository | market repository tests |
| TEST-004 | aggregate context fairness and last-good preservation | unit/integration | monitor tests |
| TEST-005 | episode plan/history/latch/persistence isolation | integration | monitor + store/history/event tests |
| TEST-006 | one durable notification per event/episode | integration | notification tests |
| TEST-007 | foreground/service aggregate wire parity | integration | runtime tests |
| TEST-008 | every position summary visible and independently expandable | widget | dashboard tests |
| TEST-009 | no-fetch expansion, responsive/privacy/a11y | widget | dashboard/editor tests |
| TEST-010 | all rendered Risk UI copy is Vietnamese | widget | dashboard/editor tests |
| TEST-011 | dynamic/legacy events rendered in the dashboard are Vietnamese | unit/widget | dashboard/formatter tests |
| TEST-012 | new unapproved English literals fail | static source | Vietnamese copy audit test |

Inner-loop diagnostics: narrowest changed test file with fake clocks/adapters; no live authenticated calls.
Formal checkpoint: each task runs its RED selector, then GREEN selector, after final task-local implementation/test-support changes.
Later changes: rerun affected task pairs only; T27 copy changes invalidate localization evidence but not request-count evidence unless functional code changes.

Verification ladder: V1 focused pair -> V2 task files -> V3 affected risk set -> V4 full repository.
Task verification ceiling: T24 V2; T25 V3; T26 V2; T27 V3.
Final integration ceiling: V4.
Escalate when: bridge/shared state affects root integration, privacy/notification behavior changes outside focused tests, or source changes invalidate prior request-count evidence.

### External verification constraints

Known environment constraint: none.
User-executed verification required: NO.
Exact secret-free command: N/A.
Proves: N/A.
Evidence required back: N/A.
Completion blocked until evidence supplied: NO.

Full-suite ownership: CODEX_ONCE — aggregate bridge/runtime and shared dashboard state have broad regression potential.

Regression coverage: existing single-position formulas, risk editor/history behavior, notification privacy/dedup, navigation, Portfolio separation, account isolation, and all current Risk tests.
Other checks: changed-source `flutter analyze`, `flutter build web --no-pub`, `git diff --check`, and final `flutter test --reporter compact` if V3 passes.

## 8. Migration / Data Plan

No forward schema migration is planned. Existing account settings and per-episode records remain the source of truth and are loaded for every active episode. Legacy English messages remain stored unchanged and are translated on output. If implementation proves a schema change necessary, stop and create a plan-validation report before proceeding.

Rollback preserves all existing episode records because no destructive migration is allowed.

## 9. Performance Verification

Use fake-clock recording adapters for 1, 3, and 10 positions. Assert exact upper bounds from specification §14, zero overlap, fair cursor rotation, cache hits, BTC sharing, immediate lane stop on 429, and no requests during cooldown. Widget tests assert lazy expanded detail and zero UI-driven commands. Live exchange capacity is not claimed.

## 10. Risks

| Risk ID | Risk | Impact | Detection | Mitigation |
|---|---|---|---|---|
| RISK-001 | Per-position loops multiply API calls and worsen 429. | Monitoring stalls. | exact request-count/order tests | shared batch, global ledger budget, keyed caches, paced lanes |
| RISK-002 | Singular fields leak history/plan/latches across episodes. | Incorrect alerts/actions. | three-position isolation and reopen tests | episode-keyed runtime contexts |
| RISK-003 | Android wire drops aggregate fields. | UI/service divergence. | populated round-trip parity tests | explicit list codec with compatibility projection |
| RISK-004 | Collapsed cards stop monitoring or fetch on expand. | missed alerts or extra load | command/request spy widget tests | expansion is UI-only; owner always monitors |
| RISK-005 | Translation mutates persisted/protocol values or user text. | decode/data corruption | compatibility and verbatim-content tests | boundary formatter and allowlist |
| RISK-006 | Large position lists overflow or rebuild expensive detail trees. | unusable UI | 10-position/320 px/200% tests | lazy expanded bodies and scrollable summaries |

## 11. Rollout / Rollback

Sequence: T24 request foundation -> T25 aggregate monitor -> T26 accordion -> T27 Vietnamese copy -> one final integration audit.
Rollback trigger: any invariant breach, duplicate notification, unbounded request count, cross-episode leakage, privacy issue, or wire incompatibility.
Rollback steps: revert only affected task write surfaces in reverse order; preserve user changes and all existing storage records.

## 12. Decision/Assumption Dependency Registry

| Decision/Assumption | Used By | Evidence/Authorization | Invalidated By |
|---|---|---|---|
| D-001 | REQ-001-REQ-003, P01-P02, T24-T25 | user message 2026-09-13 | request to return to selection-only or include spot/unsupported positions |
| D-002 | REQ-004, P03, T26 | user message 2026-09-13 | request for selector or always-expanded presentation |
| D-003 | REQ-005, P04, T27 | user message 2026-09-13 | request for another locale/scope/order |
| D-004 | REQ-001-REQ-003, P01-P02, T24-T25 | user message 2026-09-14 | request for current short or non-USDT financial semantics |

## 13. Task Decomposition

| Task | Plan Steps | Requirements/AC | Depends On | Executor Class | Allowed Write Surface |
|---|---|---|---|---|---|
| T24 | P01 | REQ-001 / AC-001-AC-003 | — | E2 | request coordinator, risk repositories/provider, focused tests |
| T25 | P02 | REQ-001-REQ-003 / AC-003-AC-006 | T24 | E2 | monitor/bridge/runtime/notification and focused tests |
| T26 | P03 | REQ-004 / AC-007-AC-009 | T25 | E1 | dashboard/risk widgets and widget tests |
| T27 | P04 | REQ-005 / AC-010-AC-012 | T26 | E1 | formatter, rendered Risk UI copy, affected tests |

Handoff-cost review: P01 and P02 remain separate because request orchestration can be independently built/tested behind compatible repository contracts before the complex state refactor. P03 is an independently auditable UI consumer. P04 is deliberately last per D-003 and can be reviewed without mixing copy changes into functional diffs.

### Task Buildability Plan

| Task | Required | Affected Canonical Build Unit | Exact Secret-Free Build Command | Boundary Strategy |
|---|---|---|---|---|
| T24 | YES | Flutter application | `flutter build web --no-pub` | compatible repository API additions |
| T25 | YES | Flutter application | `flutter build web --no-pub` | temporary legacy state projection keeps current UI buildable |
| T26 | YES | Flutter application | `flutter build web --no-pub` | aggregate UI consumes T25 state |
| T27 | YES | Flutter application | `flutter build web --no-pub` | copy-only boundary over completed functional state |

## 14. Completion Gate

- [ ] every task PASS
- [ ] every task buildability gate PASS after final task-local executable change
- [ ] no compile-coupled intermediate state is marked PASS
- [ ] every affected AC has implementation/verification evidence
- [ ] RED precedes GREEN for every task
- [ ] relevant repository checks observed
- [ ] final diff matches approved scope and preserves Task 23/user changes
- [ ] final integration audit PASS
- [ ] no protected configuration/environment file was read or modified
- [ ] external configuration actions remain N/A

## 15. Change Log

| Revision | Change | Reason |
|---|---|---|
| 1 | Initial ready plan with four serial, independently buildable tasks. | D-001 through D-003 and repository inspection. |
