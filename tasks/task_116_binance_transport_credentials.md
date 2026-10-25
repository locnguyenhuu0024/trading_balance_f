# Task 116 — Binance transport and credentials

Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Target Route: gpt-6-luna / xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-10-25-binance-direct-reads-design.md`
Plan: `docs/agents/plans/2026-10-25-binance-direct-reads.md`
Plan Steps: P01
Requirements / Acceptance: REQ-001 / AC-001
Frontend Level: F0
Frontend Design Brief: N/A — no material redesign

## 1. Dispatch / Definition of Ready
Explicit user approval of the presented plan and predecessors none are required. No unresolved product decision may be delegated. Spawn with the exact model AND effort above, role implementation_executor, no inherited route. Requested route: gpt-6-luna / xhigh (E1-T116-001); effective route: unavailable; dispatch status: UNVERIFIABLE. Record MATCH or UNVERIFIABLE only from actual dispatch evidence. Mismatch stops mutation; unavailable binding is BLOCKED_ROUTE. Follow repository baseline, Ponytail minimal-complete rules and RTK-first/context profile. No nested agents.

## 2. Objective and Contract
Revision: 2 — account views only (D-007).
Implement only P01. Use existing HTTP/crypto/storage libraries without manifest reads/changes. Expose injected clock, transport and scheduling seams for deterministic tests. Keep original OKX storage keys. No credential values enter errors, telemetry or request keys. Prepare read-route registry only for specification-required endpoints.

Persist Binance as one strict versioned key/secret bundle in `BINANCE_CREDENTIAL_BUNDLE_V1`; serialize save/clear. Native exception or web false prevents a usable generation and disables current-session private reads until successful recovery. Reload may only use a complete valid single bundle, never mixed keys. The spec section 6 exact-route/weight/query registry is binding. No executor external-service lookup is needed to choose routes or weights.

Done when referenced AC and all verification/build gates pass; related production consumers remain buildable. Preserve specification INV-001..005 and approved D-001..007.

## 3. Allowed Write Surface
Source files only:
- `lib/core/network/binance_data_client.dart (new)`
- `lib/core/network/binance_request_coordinator.dart (new)`
- `lib/core/network/binance_read_scope.dart (new)`
- `lib/core/security/secure_storage_helper.dart`
- `lib/main.dart (Binance native/web storage support only)`
- `lib/core/network/request_coordinator.dart (backward-compatible protected transport/scheduling seams only if needed)`
- `lib/core/network/okx_data_client.dart (reject foreign Binance credential headers only; preserve OKX behavior)`
- `lib/core/network/okx_interceptor.dart (pure signing reuse only if needed)`
- `lib/core/network/okx_read_scope.dart (source isolation only if needed)`
- `lib/features/settings/domain/binance_credential_bundle.dart (new parser)`
- `lib/core/exchange/binance_read_routes.dart (new exact route/weight registry)`

Test files only:
- `test/core/network/binance_data_client_test.dart`
- `test/core/security/binance_credential_generation_test.dart`
- `test/core/network/okx_data_client_test.dart`
- `test/core/security/okx_credential_generation_test.dart`
- `test/features/settings/binance_credential_bundle_test.dart`
- `test/core/widgets/app_startup_test.dart`

Test globs mean non-configuration Dart behavioral tests only. New required support files outside this explicit surface require coordinator scope review before writes.

## 4. Forbidden Scope
Market, Fractal, support/resistance, Strategy and watchlist behavior remain OKX-only; no source/quote/persistence migration for those features.
Never inspect/read/search/diff protected repository configuration/environment files or change them. No dependency/lock/build/CI/runtime settings changes, credential retrieval, backend/Strategy behavior changes, native generated DTO regeneration, unrelated refactors, Git state/history mutation, external code/log upload or deployment. Do not change canonical plans/tasks/status or append telemetry; coordinator owns those. Return BLOCKED if required change exceeds this contract or reveals missing semantics.

## 5. External Configuration
None planned. Existing build settings are opaque inputs. Keys are user-entered through application UX. If a new protected setting becomes necessary, stop and report the exact non-secret target/location/semantics needed; never inspect it.

## 6. RED then GREEN
Meaningful negative verification, named `RED-116` cases:
Foreign origin/method/query/header mutation, missing keys, rotation during storage/queue/transport, disposal and timestamp/429/418 responses must reject, sanitize or pause locally. Assert zero forbidden adapter sends and no OKX/backend invalidation.

Include native storage exceptions and web false results before/after a single bundle write, malformed bundle/reload, and concurrent save/clear. Assert complete committed bundle or unusable private-read state, including reload; no old/new key mixing. Storage safety is owned by this task, not deferred to T118's UX tests.

Primary success verification, named `GREEN-116` cases:
Fixed-origin exact-query HMAC GET; public read uses no credential storage; independent native/web save/clear fences both sides of mutation; injected-Dio lifecycle stays guarded until completion.

During diagnostics use the narrowest check. Once implementation is ready, formal RED precedes GREEN. Expected values derive from the spec/independent fixtures, never the implementation's output. Named prefixes must cover the relevant test files so commands exercise the entire scenario set.

RED command: `rtk flutter test --no-pub test/core/network/binance_data_client_test.dart test/core/security/binance_credential_generation_test.dart test/core/network/okx_data_client_test.dart test/core/security/okx_credential_generation_test.dart test/features/settings/binance_credential_bundle_test.dart test/core/widgets/app_startup_test.dart --plain-name RED-116`
GREEN command: `rtk flutter test --no-pub test/core/network/binance_data_client_test.dart test/core/security/binance_credential_generation_test.dart test/core/network/okx_data_client_test.dart test/core/security/okx_credential_generation_test.dart test/features/settings/binance_credential_bundle_test.dart test/core/widgets/app_startup_test.dart --plain-name GREEN-116`
Then run complete relevant files/groups from plan section 7. Ceiling: V2, never full suite per task. Escalate only for demonstrated shared-surface regression/missing contract evidence. Later edits invalidate only affected evidence; repeat both if their shared basis changes. Capture concise actual command/result/counts and RED-before-GREEN order.

## 7. Buildability Gate
Required: YES. Affected canonical build unit: full Flutter application.
Exact command: `rtk flutter build web --no-pub`.
Run after the last task-local executable/test change; report exact target and exit/status. Focused test compilation is insufficient. Additive/backward-compatible boundary is required; no later task may repair this task's build. Changed-source build error -> REWORK; genuine pre-build toolchain failure -> BLOCKED_ENVIRONMENT. No dependency installation or protected-file diagnosis.

## 8. Frontend / Audit Handoff
Reuse existing AppPalette, typography, forms, cards and locale formatting. No visual redesign; source adapter behavior is verified through deterministic tests.
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

## 11. Bounded Remediation R1 (2026-10-25)
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Logical run: E1-T116-R1-001
Approved existing REQ-001 / AC-001 scope; no new product decision or external action.

- AUD-116-001: reject case-insensitive OK-ACCESS-* and x-simulated-trading in base and final transport headers. Tests cover defaults and late interceptors, public/private, zero forbidden adapter sends.
- AUD-116-002: generate timestamp/signature inside scheduled callback immediately before guarded dispatch, maintaining immutable exact query/origin authorization. Test initial and timestamp-retry sends after queue delays >5000ms.
- AUD-116-003: sanitize Dio transport failures inside scheduler callback before job completion/retention. Preserve safe HTTP status/cooldown/timestamp recovery, cancellation and generation semantics; assert no raw request options, headers, signed URL or private body crosses coordinator completion (instrument subclass if useful).
- AUD-116-004: actual rawRequests cost must govern admission and charge consistently (or remove unused multiple-cost API without losing contracts). Test 80% owner and 60% history limits.
- Complete negative coverage for native delete exception, web delete false before/after deletion, rotation while storage load pending, cancellation, repeated timestamp rejection (one retry only), auth failure (no retry).

Allowed surfaces remain exactly section 3. Preserve already passing storage/OKX behavior, no scope expansion. Repeat formal full named RED-116 then GREEN-116 because shared client/test basis changes; run full relevant V2 group and fresh `rtk flutter build web --no-pub` after last executable change. Use authorized SDK-cache-write escalation for Flutter commands; do not repeat known failing default bootstrap. Return exact evidence and final diff scope. Do not write task/status/telemetry.

Independent audit R2-T116-AUDIT-001: REWORK, source-reviewed security/lifecycle findings above; coordinator confirmed validators, prequeue signing, raw error rethrow and admission/charge mismatch from exact source. Previous 18 RED / 12 GREEN / 47 regression + successful web build apply only to pre-remediation state and cannot authorize task PASS.

## 12. Final Coordinator Audit — PASS
AC-001 satisfied by guarded client/registry, single-bundle storage and independent source generations. Coordinator inspected permitted source/test diffs and neutral route registry; read-only independent R2-T116-AUDIT-002 confirms AUD-116-001..004 resolved. All actual changes are within section3; omitted optional binance_read_scope.dart was unnecessary for this additive client boundary. No protected contents accessed/modified; pre-existing protected paths unchanged by name/status.

Final observed executor evidence, reused after exact source/test quality and freshness review: named RED-116 29 passed then named GREEN-116 12 passed; planned V2 group 58 passed; exact commands as section6/plan7 (absolute RTK executable), all exit0. Bundle/startup named scenarios included in formal groups. Fresh `rtk flutter build web --no-pub` exit0 after last executable change, full Flutter app; warning-only Wasm/Cupertino font output. Explicit E1 route compliant UNVERIFIABLE; no inherited route. No later executable edits at acceptance. External configuration actions none; live private/device/CORS evidence unavailable, not claimed. Independent audit terminal results collected; runtime has no child close/release primitive.
Verdict: PASS. Task boundary buildability: PASS. Route assessment FIT after one bounded remediation cycle.
