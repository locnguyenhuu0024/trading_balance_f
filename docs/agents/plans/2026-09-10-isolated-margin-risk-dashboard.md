# Implementation Plan: Isolated Margin Risk Dashboard

Status: COMPLETE
Date: 2026-09-10
Tier: L
Specification: `docs/agents/specs/2026-09-10-isolated-margin-risk-dashboard-design.md`
Decision Ledger: `docs/agents/decisions/2026-09-10-isolated-margin-risk-dashboard-decisions.md`

## 1. Objective

Implement REQ-001–011 and AC-001–011 across the full user brief. Canonical formulas/defaults/visual contract are in the specification; this plan owns execution scope, dependency order and audit gates.

## 2. Preconditions

D-001–005 and A-001 resolved. Execution approval is still required after this plan is presented. Read the current EXECUTION_AUDIT_RULES before first dispatch. Use strict coordinator/executor/auditor separation and serial bounded tasks: configured executor target `gpt-5.6-luna`, reasoning `max`, with a bounded non-full-history prompt. Do not claim runtime model without evidence; explicitly reported mismatch blocks execution.

Planning inspected repository and official public OKX documents only. No private API calls, runtime tests or device tests have been performed. Flutter executable is present at `/Users/locnguyen/development/flutter/bin/flutter`; installed packages expose the required interfaces. Verify toolchain once before execution and record genuine blockers without repeated broad retries.

Baseline includes user-modified AGENTS/framework/templates, deleted older specs/plans and new context-optimization profile. Preserve these; they are not changes from this feature. RTK is available; use it for noisy test/build output while retaining raw evidence when exactness matters. No other external service is approved beyond official OKX documentation/existing integration.

## 3. Repository Impact

New files (exact planned source paths; executor may not expand surface without coordinator decision):

| Step | Paths / symbols | Change |
|---|---|---|
| P01 | `lib/features/portfolio/domain/risk/risk_models.dart` — observation, metric, quality, evaluation, scenario types | ADD |
| P01 | `lib/features/portfolio/domain/risk/risk_policy.dart` — versioned validated policy/defaults | ADD |
| P01 | `lib/features/portfolio/domain/risk/risk_engine.dart` — normalize, evaluate position/recovery/overall, stress/map | ADD |
| P01 | `lib/features/portfolio/data/risk/okx_risk_dto.dart`, `risk_repository.dart` — GET data and strict cost/mode/currency mapping | ADD |
| P02 | `lib/features/portfolio/domain/risk/market_risk_engine.dart`, `lib/features/portfolio/data/risk/risk_market_repository.dart` | ADD |
| P03 | `lib/features/portfolio/domain/risk/action_plan.dart`, `risk_history.dart`, `risk_events.dart` | ADD |
| P03 | `lib/features/portfolio/data/risk/risk_local_store.dart` | ADD |
| P03 | `lib/features/portfolio/application/risk_monitor_bridge.dart` — protocol/commands/state interfaces, not platform runtime | ADD |
| P04 | `lib/features/portfolio/presentation/providers/risk_dashboard_provider.dart` | ADD |
| P04 | `lib/features/portfolio/presentation/widgets/risk/risk_overview.dart`, `risk_market_card.dart`, `risk_stress_view.dart`, `risk_recovery_view.dart`, `risk_plan_editor.dart`, `risk_history_view.dart`, `risk_settings_sheet.dart`, `risk_price_map.dart` | ADD |
| P04 | `lib/features/portfolio/presentation/portfolio_details_screen.dart` | ADD (move existing opt-in balance/details rendering) |
| P04 | `lib/features/portfolio/presentation/portfolio_screen.dart` | MODIFY (risk Home, preserve exported providers) |
| P05 | `lib/features/portfolio/application/risk_monitor.dart`, `risk_monitor_runtime.dart`, `risk_notification_sink.dart` | ADD |
| P05 | `lib/core/services/background_service.dart`, `lib/main.dart`, `lib/core/security/secure_storage_helper.dart`, `lib/features/portfolio/presentation/providers/risk_dashboard_provider.dart` | MODIFY (owner lifecycle/bridge/credential invalidation only) |

Tests listed in §6 are allowed new files; existing Portfolio dual-currency test is updated in P04, and `test/widget_test.dart` may update fake runtime injection in P05 only. Planning evidence and audit notes update within these new artifacts. No changes to Orders generated DTOs, order/trade endpoints, navigation layout implementation, dependency versions, API secrets, native entitlements, hosting or CI configuration. Additional test fixtures remain inside `test/features/portfolio/risk/fixtures/` and must be synthetic.

## 4. Dependency Graph

`P01/T18 -> P02/T19 -> P03/T20 -> P04/T21 -> P05/T22 -> final integration audit`

One executor at a time. Coordinator audits repository ground truth and returns PASS/REWORK/BLOCKED. Only PASS unlocks dependent tasks. Remediation returns to a bounded executor; coordinator does not patch failed implementations.

## 5. Ordered Implementation Steps

### P01 — Coherent position risk, costs and stress

Implements REQ-001,002,003,005,006 / AC-001,002,003,005,006.

1. Add nullable unit/time/quality DTOs and policy contract (spec §6,8.1,8.5,8.6); isolate from legacy Orders models.
2. Add read-only position/config/instrument/rate/fee/interest adapter, strict account/episode identity and supported-mode normalization. Dedicated Dio uses existing interceptor but no sensitive request/response logging. Reject futures/short/zero records correctly.
3. Implement E from margin+upl, trade vs collateral sensitivity, reconciled debt, cost coverage and True Exit/partial estimate distinction. Never silently treat unknown lifetime costs as zero.
4. Implement policy validation, position/hard floors, recovery/max overall aggregation with an explicit market input, stress scenarios/map levels. Unknown market input is partial, not NORMAL.
5. Add synthetic fixtures for F1/F2, old/new modes, missing/malformed values, exact boundaries and user-reference sensitivity. Assert endpoint GET-only and source freshness metadata.

Allowed files: P01 rows in §3 plus `test/features/portfolio/risk/risk_engine_test.dart`, `risk_repository_test.dart`, fixtures. No runtime network or UI integration yet.

RED-001 then GREEN-001, commands in §6. Expected results in spec §6.4/§13. Preserve INV-001–004,007; EDGE-001–003,006. Stop if any API meaning cannot be handled by the documented unavailable/reconciliation contract. Do not invent a financial fallback.

### P02 — Explainable market environment

Implements REQ-004,005 / AC-004,005; depends T18 PASS.

1. Add public GET candles/funding/OI adapters and exact asset/BTC/SWAP mapping. Preserve authentication separation, per-source timestamps, interval validation and candle completion.
2. Implement volatility, EMA/support/volume structure, four OI quadrants, normalized funding conjunctions, BTC modifier and partial-component aggregation per spec §8.2–8.5.
3. Inject historical OI samples as data (persistence is P03); no synthetic delta during first 4 hours.
4. Wire market evaluation into existing pure overall calculation; reasons carry observed values/windows/sources, improvements clear actual factors only.

Allowed: P02 rows; P01 domain types/engine only to complete typed market integration; `test/features/portfolio/risk/market_risk_engine_test.dart`, `risk_market_repository_test.dart`, fixtures. No widget, storage or platform changes.

RED-002 then GREEN-002; preserve INV-001,002,004,007; EDGE-004. Stop on needed external vendor/new unapproved scope. Missing instrument/data uses specified partial behavior.

### P03 — Durable user plans, history and event reducer

Implements REQ-007,008,009,011 / AC-007,008,009,011; depends T19 PASS.

1. Implement rule/zone validation/evaluation, custom stress levels and settings serialization.
2. Add versioned scoped local store with serialized writes, schema validation, corruption/write-failure outcomes and retention. Inject storage/clock; no raw credentials or response payloads.
3. Implement last-check lifecycle, trend/velocity, daily summary/timezone, OI ring buffer and event/latch reducer. Apply exact rearm/materiality/gap rules.
4. Define monitor bridge protocol, immutable UI state, command idempotency and in-memory fake owner so P04 can render/test end-to-end interactions without platform startup.
5. Test restart/dedup, account/episode change, same-pair reopen, retention, timezone, stale sources, storage failure and rule unknown state.

Allowed: P03 rows; P01 policy/models only for documented persistence DTO extensions; `test/features/portfolio/risk/action_plan_test.dart`, `risk_history_test.dart`, `risk_events_test.dart`, `risk_local_store_test.dart`, fixtures.

RED-003 then GREEN-003. Preserve INV-002,004,006,007; EDGE-003,005,006. No OS notification delivery yet. Store failed => no delivery intent; corrupted schema cannot be silently overwritten.

### P04 — Complete Flutter Risk Home and editors

Implements REQ-006,007,008,010 / AC-006,007,008,010; depends T20 PASS.

1. Build spec §21 visual hierarchy against typed bridge state. Above-fold priority: Overall/qualifier/trend, buffer, leverage, debt, True Exit, -10 scenario and plan status.
2. Implement each real drill-down: market inputs/reasons, exposure/sensitivity, recovery/costs, full scenarios/custom prices, sorted map, action CRUD, policy editor, since-last-check, event/history/daily summary.
3. Move existing balances/details behind explicit Portfolio Details with PnL hidden and session opt-in; preserve global privacy, currency formatting and exported providers.
4. Cover loading/error/no-position/unsupported/partial/stale/offline/permission/storage states, mobile/desktop/large text, keyboard input/focus and screen-reader hidden values. No fake functional buttons.
5. Capture synthetic light/dark widget screenshots for visual inspection at 390x844, 1280x900, and boundary 320px/200% text. Store screenshots under `/tmp/risk-dashboard-review/` (not product assets). Coordinator inspects screenshots; do not use real account data.

Allowed: P04 rows; `test/features/portfolio/risk/risk_dashboard_test.dart`, `risk_editors_test.dart`, `test/features/portfolio/portfolio_dual_currency_screen_test.dart`, fixtures. No style/navigation refactor or runtime service mutation.

RED-004 then GREEN-004. Preserve INV-001–007, EDGE-005–007. Layout can adapt within spec; materially different hierarchy requires coordinator review. No external ImageGen/service upload needed for this native code-target redesign.

### P05 — One monitor, risk notifications and final integration

Implements REQ-009,011 / AC-009,011 (integrates all ACs); depends T21 PASS.

1. Implement shared serialized monitor: coherent source fetch/caches -> pure engines -> persisted events/latches -> published state -> notification sink.
2. Wire foreground owner for iOS/web/desktop and Android-service owner via typed bridge; no competing foreground poller. Explicit start failure handling, shutdown, reconnect, command ack/idempotency and late-response invalidation.
3. Replace existing 1-second balance/PnL service loop with bounded risk polling and generic persistent service status. Initialize native event channel/sink using installed plugin signatures; permission denied retains event center. Web does not call native plugins.
4. Update bootstrap/credential save-clear invalidation and app lifecycle only as needed for this owner contract; keep authentication/biometric preferences and navigation intact. On credential mutation stop old generation before consuming new account data.
5. Test real adapter orchestration with fake HTTP/storage/clock/platform interfaces; assert one notification per durable event and no notification if persist fails. Verify no PnL strings/numbers or private payloads in risk OS messages.
6. Complete integration checks in §6 once scoped tests pass. Native runtime limitations are reported, never claimed verified from a fake sink.

Allowed: P05 rows; `test/features/portfolio/risk/risk_monitor_test.dart`, `risk_runtime_test.dart`, `risk_notification_test.dart`, `test/widget_test.dart` fake-bootstrap adjustment; no extra native permissions/dependencies without revised approval.

RED-005 then GREEN-005. Preserve all invariants. If Android cannot establish exclusive ownership, show monitoring unavailable instead of silently racing a fallback. Do not read real keys or send authenticated private requests to test the pipeline.

## 6. Test and Verification Plan

Use synthetic fixtures, injected clock/storage/HTTP/sink; calculations expected independently from spec F1/F2. Test names start with `RED-00N` or `GREEN-00N` for explicit ordering; multiple cases may share the prefix. Commands run sequentially (not via parallel Promise calls).

| Task | Formal RED command, then analogous GREEN prefix | Relevant group / ceiling |
|---|---|---|
| T18 | `flutter test test/features/portfolio/risk/risk_engine_test.dart test/features/portfolio/risk/risk_repository_test.dart --plain-name RED-001 --reporter compact` then GREEN-001 | both files; V2 |
| T19 | `flutter test test/features/portfolio/risk/market_risk_engine_test.dart test/features/portfolio/risk/risk_market_repository_test.dart --plain-name RED-002 --reporter compact` then GREEN-002 | both files; V2 |
| T20 | `flutter test test/features/portfolio/risk/action_plan_test.dart test/features/portfolio/risk/risk_history_test.dart test/features/portfolio/risk/risk_events_test.dart test/features/portfolio/risk/risk_local_store_test.dart --plain-name RED-003 --reporter compact` then GREEN-003 | these four files; V2 |
| T21 | `flutter test test/features/portfolio/risk/risk_dashboard_test.dart test/features/portfolio/risk/risk_editors_test.dart --plain-name RED-004 --reporter compact` then GREEN-004 | both + portfolio currency tests; V3 |
| T22 | `flutter test test/features/portfolio/risk/risk_monitor_test.dart test/features/portfolio/risk/risk_runtime_test.dart test/features/portfolio/risk/risk_notification_test.dart --plain-name RED-005 --reporter compact` then GREEN-005 | these three + bootstrap; V3 |

Inner loop: narrow failing case only. Formal checkpoint after implementation ready. Every changed implementation/remediation verifies RED before GREEN. Direct user AGENTS contract requires restarting the pair after code/test-support changes; apply that stricter rule if it differs from later local framework guidance. Record commands, timestamps/order, expected and observed outcomes concisely, not huge passing logs.

Final integration ceiling V4, owned CODEX_ONCE because Home/bootstrap/service/shared state cross several features and no authoritative CI was found. Run `flutter test --reporter compact` once after all tasks pass; isolate any failure and distinguish pre-existing behavior. Run `flutter analyze` and `flutter build web --no-pub` as final cross-platform compile check; build outputs only after authorization. Run `flutter build apk --debug --no-pub` if Android SDK/JDK is available, to validate service compile; otherwise record unavailable environment and do not claim native compilation. Do not install dependencies or platforms to work around unavailable SDK without scope review.

Coordinator visually inspects P04 synthetic screenshot artifacts and checks accessibility/overflow tests. Emulator/device smoke, if locally available without actual credentials: permission denied, service restart, one risk event and resume. Without device availability, mocked native integration and build are separate evidence; native delivery remains unverified and is called out at handoff. No live PnL or actual account screenshots needed.

Escalate beyond a task ceiling only if a changed shared surface or unexplained regression affects another AC. Do not repeat passing full suites without relevant subsequent changes. RTK may reduce repetitive output but cannot replace actual scenario evidence.

## 7. Data / Migration Plan

New namespaced v1 keys only; preserve all existing preferences. Malformed/future records are read-only failures, user-confirmed reset only. Verify synthetic old-schema/future-schema and interrupted write; no migration silently drops user plans. Closed episode pruning follows spec. Credential changes never relabel another account's history. Account identity failure remains ephemeral, not a fallback account namespace.

## 8. Performance Verification

Fake clock + slow fake endpoints prove no overlapping fetch, 15s/60s position cadence, independent 60s market cadence and caching of hourly fee/rate/config. Count requests across 5 minutes and after pull-refresh/reconnect. Retention tests enforce bounded arrays. Verify monitor stop cancels timer/subscription and late data cannot write old-account storage.

## 9. Risks

| ID | Risk | Detection / mitigation |
|---|---|---|
| RISK-001 | Old/new collateral accounting or liability interest ambiguity | F1/F2, documented reconciliation and partial states; never whole-account equity fallback. |
| RISK-002 | True Exit unavailable for historical/size-changed position | Explicit coverage metadata and `-`; secondary known-cost estimate does not trigger T rules. |
| RISK-003 | Heuristic ratings mistaken for exchange signals | Settings and reason drill-down expose method/source; hard position floors; no trade recommendations. |
| RISK-004 | Duplicate owner/notification or corrupted local data | Single owner bridge, persistent latches, idempotent commands, failure tests. |
| RISK-005 | OS suspend/permission or missing native toolchain | Capability matrix and visible last observation/gaps; report actual verification limits. |
| RISK-006 | Polling overload or stale context | Bounded serialized GET cadence, TTL/backoff, stale factors excluded from new alerts. |
| RISK-007 | Home/biometric/navigation regression | Preserve exports/settings, relocated details tests and one final full test run. |

## 10. Rollout / Rollback

No deployment/commit/push. Integrate serially after approval. Validate all ACs before claiming done. If wrong formulas, duplicated monitoring or privacy regressions remain, return REWORK/BLOCKED. Any user-authorized rollback affects only feature code and retains versioned risk records; never restore/reset unrelated user work.

## 11. Decision Dependencies

| Decision | Used by | Invalidation |
|---|---|---|
| D-001 full 36 sections | all P/T | user changes scope |
| D-002 OKX + missing `-` | P01,P02,P05 | unsupported documented source => partial; new vendor needs approval |
| D-003 accepted buffer boundaries | P01,P03,P04 | user changes policy defaults |
| D-004 overall header/floor | P01,P02,P04 | user changes aggregation |
| D-005 local plans/history | P03–P05 | request for cross-device/server sync |
| A-001 proposed configurable defaults | all P/T | user revises before/after plan approval; revise affected scope |

## 12. Task Checklist and Handoff Review

| Task | Outcome | Depends | Status |
|---|---|---|---|
| [T18](../../../tasks/task_18_risk-position-engine.md) | Position adapter, metrics, policy, recovery and stress | plan approval | PASS |
| [T19](../../../tasks/task_19_risk-market-engine.md) | Market factors and explainable aggregation | T18 PASS | PASS |
| [T20](../../../tasks/task_20_risk-plans-history-events.md) | Durable plans/history/summary/event reducer | T19 PASS | PASS |
| [T21](../../../tasks/task_21_risk-dashboard-home.md) | Full responsive Home and working drill-downs/editors | T20 PASS | PASS |
| [T22](../../../tasks/task_22_risk-monitor-notifications.md) | Single-owner runtime and risk notifications/integration | T21 PASS | PASS |

Five independently auditable units fit Tier L target. Adapter+formulas+stress stay together because they share accounting evidence. Market remains separate because market classification can fail independently. Persistence/events share temporal evidence and stay together. UI needs interaction/visual evidence. Runtime needs lifecycle/platform ownership evidence; merging it with UI would obscure those failures. Shared surfaces are serial, never concurrent writes. Coordinator owns task numbering and audit metadata.

## 13. Completion Gate

- [x] Explicit execution approval after presentation.
- [x] Every task PASS after independent repository audit.
- [x] Every AC traced to observed RED-before-GREEN evidence.
- [x] Relevant checks and final integration run observed.
- [x] Visual artifact inspection and platform limits reported.
- [x] Final diff explained against baseline, no user changes discarded.
- [x] No commit/push/deployment implied by completion.

## Execution Authorization

2026-09-10: User explicitly approved: "duyệt, bắt đầu đi". T18–T22 authorized; no commit/push/deployment. Initial execution worktree contained only this feature planning artifacts.
