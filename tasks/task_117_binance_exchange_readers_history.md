# Task 117 — Neutral exchange readers and history scan

Status: PASS
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6-luna
Target Effort: max
Target Route: gpt-6-luna / max
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-10-25-binance-direct-reads-design.md`
Plan: `docs/agents/plans/2026-10-25-binance-direct-reads.md`
Plan Steps: P02
Requirements / Acceptance: REQ-002,003,005 / AC-002,003,005
Frontend Level: F0
Frontend Design Brief: N/A — no material redesign

## 1. Dispatch / Definition of Ready
Explicit user approval of the presented plan and predecessors T116 = PASS are required. No unresolved product decision may be delegated. Spawn with the exact model AND effort above, role implementation_executor, no inherited route. Requested route: gpt-6-luna / max (E2-T117-001); effective route: unavailable; dispatch status: UNVERIFIABLE. Record MATCH or UNVERIFIABLE only from actual dispatch evidence. Mismatch stops mutation; unavailable binding is BLOCKED_ROUTE. Follow repository baseline, Ponytail minimal-complete rules and RTK-first/context profile. No nested agents.

## 2. Objective and Contract
Revision: 2 — account views only (D-007).
Implement only P02 using P01 interfaces. Keep all existing production consumers/DTOs buildable. Native OKX wrapper retains original DTO provenance; Binance neutral rows carry none. Inject adapters/clock. Host public/private budget is shared, history one-in-flight and interleaved behind interactive work; cancellation and in-memory resume are generation-scoped. No persisted account-history cache or symbol-universe shortcuts. Existing Strategy quote facade remains intact.

Specification section 6 fixes route versions/auth, parameter-dependent weight/query policy, budget reserves, native history coverage and conditional linkage. Consume that verified registry rather than choosing new endpoints. Test 20/21/100-symbol ticker-weight boundaries, missing budget metadata and actualOrderId linkage. Candle routes/readers, trading-day statistics, merged Top 50, Fractal, support/resistance and watchlist changes are excluded by D-007. Registry or native-response contradictions return to coordinator validation.

Done when referenced AC and all verification/build gates pass; related production consumers remain buildable. Preserve specification INV-001..005 and approved D-001..007.

## 3. Allowed Write Surface
Source files only:
- `lib/core/exchange/exchange_models.dart (new)`
- `lib/core/exchange/exchange_readers.dart (new)`
- `lib/core/exchange/okx_exchange_reader.dart (new)`
- `lib/core/exchange/binance_exchange_reader.dart (new)`
- `lib/core/exchange/exchange_quote_service.dart (new)`
- `lib/core/exchange/exchange_providers.dart (new)`
- `lib/core/exchange/binance_history_scan.dart (new)`
- `lib/core/exchange/binance_read_routes.dart (bounded endpoint/weight completion)`
- `lib/core/network/binance_request_coordinator.dart (scanner integration, preserve T116 contracts)`

Test files only:
- `test/core/exchange/exchange_readers_test.dart`
- `test/core/exchange/binance_history_scan_test.dart`
- `test/core/exchange/exchange_quote_service_test.dart`
- `test/core/exchange/exchange_models_test.dart`

Test globs mean non-configuration Dart behavioral tests only. New required support files outside this explicit surface require coordinator scope review before writes.

## 4. Forbidden Scope
Never inspect/read/search/diff protected repository configuration/environment files or change them. No dependency/lock/build/CI/runtime settings changes, credential retrieval, backend/Strategy behavior changes, native generated DTO regeneration, unrelated refactors, Git state/history mutation, external code/log upload or deployment. Do not change canonical plans/tasks/status or append telemetry; coordinator owns those. Return BLOCKED if required change exceeds this contract or reveals missing semantics.

## 5. External Configuration
None planned. Existing build settings are opaque inputs. Keys are user-entered through application UX. If a new protected setting becomes necessary, stop and report the exact non-secret target/location/semantics needed; never inspect it.

## 6. RED then GREEN
Meaningful negative verification, named `RED-117` cases:
Identical IDs across exchanges/markets/kinds, hedge sides, invalid decimal/currency, missing quote, one failed symbol, unbounded/stale callbacks, generation change, exhausted IP budget and 429/418. Never count failed/pending symbols as complete, mix source prices or retain obsolete private rows.

Primary success verification, named `GREEN-117` cases:
Scan synthetic catalog containing USDT and non-USDT Spot pairs sequentially, limit=500 per native recent page, report accurate progress/resume and stable ordering. Read distinct ordinary/conditional futures orders and normalized balances/positions. Validate source-specific account-valuation batch quote expiry; existing OKX analytical readers/providers remain unchanged. Fixture futures equity includes PnL exactly once.

During diagnostics use the narrowest check. Once implementation is ready, formal RED precedes GREEN. Expected values derive from the spec/independent fixtures, never the implementation's output. Named prefixes must cover the relevant test files so commands exercise the entire scenario set.

RED command: `rtk flutter test --no-pub test/core/exchange/exchange_readers_test.dart test/core/exchange/binance_history_scan_test.dart test/core/exchange/exchange_quote_service_test.dart test/core/exchange/exchange_models_test.dart --plain-name RED-117`
GREEN command: `rtk flutter test --no-pub test/core/exchange/exchange_readers_test.dart test/core/exchange/binance_history_scan_test.dart test/core/exchange/exchange_quote_service_test.dart test/core/exchange/exchange_models_test.dart --plain-name GREEN-117`
Then run complete relevant files/groups from plan section 7. Ceiling: V3, never full suite per task. Escalate only for demonstrated shared-surface regression/missing contract evidence. Later edits invalidate only affected evidence; repeat both if their shared basis changes. Capture concise actual command/result/counts and RED-before-GREEN order.

## 7. Buildability Gate
Required: YES. Affected canonical build unit: full Flutter application.
Exact command: `rtk flutter build web --no-pub`.
Run after the last task-local executable/test change; report exact target and exit/status. Focused test compilation is insufficient. Additive/backward-compatible boundary is required; no later task may repair this task's build. Changed-source build error -> REWORK; genuine pre-build toolchain failure -> BLOCKED_ENVIRONMENT. No dependency installation or protected-file diagnosis.

## 8. Frontend / Audit Handoff
Reuse existing AppPalette, typography, forms, cards and locale formatting. No analytical/watchlist consumer changes or visual redesign; account adapter behavior is verified through deterministic tests.
Return changed source/test paths, AC mapping, formal RED/GREEN evidence, relevant regression results, fresh build evidence, limitations and sanitized telemetry envelope. Do not claim live private API or device/CORS verification from mocks/web compilation.

## 9. Checklist
- [x] Approval and predecessor PASS confirmed by coordinator
- [x] Explicit role/model/effort dispatch; no inherited route
- [x] Bounded source/test implementation and relevant regression tests
- [x] Formal RED observed before GREEN
- [x] Relevant file/group checks within planned ceiling
- [x] Fresh task-local full Flutter web build PASS
- [x] No protected content accessed/changed; no unapproved external/Git action
- [x] Compact evidence report returned to coordinator

## 10. Coordinator Audit
Scope / AC / minimality / units / source isolation / action authority: PENDING.
RED-before-GREEN / tests / buildability / route compliance: PENDING.
External configuration and live verification limitations: PENDING.
Verdict: PENDING (PASS | REWORK | BLOCKED).

## 11. Coordinator early implementation review
Existing-contract inner-loop corrections before formal checkpoint (not scope expansion): cold-start exchangeInfo bootstrap before private account reads; retain successful Futures equity with explicit position/config issues; clear history private rows on generation change; preserve conditional parent's native metadata; unknown product/side and unsupported settlement never guessed; remove cancelled quote-batch identity before new-owner reuse; revalidate cached/early batch freshness at final snapshot publication; explicit recent seven-day Futures coverage; remember observed open-order symbols in same-generation universe. Add corresponding deterministic regressions before named RED/GREEN.
Coordinator verified official allAlgoOrders native example is a top-level array (official Trade reference, 2026-10-25); no envelope parser change authorized/needed.
Independent read-only R2-T117-AUDIT-001 runs during implementation; final verdict awaits post-test final source. Requested explicit gpt-6.1-sol/medium on previously bound auditor; effective unavailable UNVERIFIABLE. No close/release API exists.

## 12. Final Coordinator Audit — PASS
AC-002/003/005 satisfied by neutral models/native adapters, generation-aware sequential first-page scans and source-specific quote service. Coordinator inspected source contracts and reviewed reader/history/quote implementation and focused tests; independent R2-T117-AUDIT-001 reviewed every final allowed file and confirmed all early corrections resolved. Only the approved new exchange sources and four tests changed; T116 source contracts and all production analytical/backend consumers unchanged.

Final executor evidence reused after test-quality/freshness reconciliation: exact section6 commands named RED-117 19 passed then GREEN-117 18 passed; `rtk flutter test --no-pub test/core/exchange` 37 passed (V3); `rtk flutter build web --no-pub` full Flutter application exit0 after last executable change, built build/web with warning-only Wasm/Cupertino output. `git diff --check -- lib/core/exchange test/core/exchange` clean. No later code changes at acceptance. Explicit E2 gpt-6-luna/max requested, effective unavailable UNVERIFIABLE; no inherited route. External configuration actions none, live/private/device/CORS evidence not claimed. Protected paths observed name/status only unchanged. No close/release primitive exposed for terminal children.
Verdict: PASS. Task Buildability Gate: PASS. Route fit: FIT.
