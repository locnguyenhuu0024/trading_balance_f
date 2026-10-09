# Task 100 — Remove Risk

Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE
Specification: docs/agents/specs/2026-10-09-app-simplification-design.md
Plan: docs/agents/plans/2026-10-09-app-simplification.md
Plan Steps: P01
Requirements/Acceptance: REQ-001 / AC-001
Frontend Level: F1

## Scope and contract

Implement P01 exactly, predecessors none, user authorized execution. Allowed: Risk-only portfolio application/data/domain/presentation modules and tests; old core/services/background_service.dart shutdown shim; main.dart; core/security/secure_storage_helper.dart bus removal only; navigation destination/shell/preferences source and affected tests; settings_screen.dart service probe removal only; request coordinator migration to core/network/request_coordinator.dart and test/core/network/request_coordinator_test.dart; shared ticker/support/strategy source/test imports/types; widget/navigation/settings/crypto-icon test fixtures required by deletion; focused service retirement tests. No other product change. Inspect source consumers before deletion; preserve Strategy risk scoring/trade safeguards and backend session fences. No secret storage bulk deletion.

Old onStart(ServiceInstance) URI/signature stays as stopSelf-only callback for saved handles. Native retirement helper stops existing service via stopService and disables autoStart/autoStartOnBoot through plugin configuration without starting anything; no local-notification dependency use. If exact existing plugin API differs, use permitted dependency source API inspection, never config. Main error message generic.

Forbidden: protected config/manifests/lock/environment content reads or writes; backend edits; unrelated cleanup/dependency changes; commit/push/task status/telemetry writes; subagents. RTK first eligible output; exact raw source/diff exception. Read baseline/framework profile/Ponytail/execution and pinned interface checklist as applicable.

## Verification

RED-001: old saved navigation containing risk drops removed ID with valid remaining destinations; retired callback stops and never constructs monitor; shared scheduler 429 blocks queued adapter work. GREEN-001: seven destinations navigate incl Support/Strategy indices 6/7; scheduler coalesces/spacing/cooldown unchanged; shutdown helper never starts service. Add meaningful tests and observe an initial failure for no-Risk expectation if practical, then formal negative RED cases before success GREEN cases when implementation ready. Preserve migrated scheduler behavioral suite.

V3 ceiling affected navigation/settings/ticker/support/strategy tests. Exact Flutter test commands/names recorded in terminal report. Task buildability YES: Flutter app, `flutter build web --no-pub` after last source/test edit. Android `flutter build apk --debug --no-pub` once if SDK available; if absent report native unverified. No protected regeneration; use --no-pub. External configuration actions none required; inert plugin declarations left protected.

Stop for material unresolved contract/protected write requirement/routing failure. Return compact changed paths, RED then GREEN exact commands/outcomes, build command/status/freshness, safe limitations, telemetry envelope with effective route unavailable. Coordinator owns audit/status.

## Checklist / audit

- [x] implementation complete
- [x] ordered RED/GREEN observed
- [x] affected tests and build pass
- [x] independent coordinator audit PASS

Audit: PASS. Coordinator independently inspected source/test diffs and removed-path scope, native shutdown shim, shared consumers, migrated scheduler behavioral tests, no retained Risk references, no protected changed paths. Executor explicitly bound E1 gpt-6-luna/xhigh, effective route UNVERIFIABLE. Initial negative navigation and backend-429 tests failed as expected before fixes; subsequent navigation37, scheduler3, service3, ticker6, Support22, Strategy155 (market7 rerun), Settings12, icons4 and widget5 passed. `flutter build web --no-pub` exit0 after final executable changes. Native device behavior unverified; source shim fake tests do not prove OS service retirement. No external config actions. Detailed evidence: docs/agents/audits/2026-10-09-app-simplification.md.

## AUD-100-001 — preserve rate-limit contract through backend gateway

Coordinator-authorized bounded remediation within shared scheduler migration: an existing Support repository 429 test fails because BackendDataClient normalizes DioException into BackendDataException, while the moved coordinator only recognizes DioException. Add BackendDataException statusCode and retryAfter handling to RequestCoordinator using the existing parser/backoff logic; preserve non-429 propagation and all Dio behavior. Allowed write surface already includes coordinator and migrated test plus affected Support test (do not weaken it). Add backend-429 queued-request suppression/cooldown tests. Formal negative RED first, then success GREEN; rerun scheduler/Support consumer evidence and task build after this edit. No backend client implementation change. User authorized autonomous fixes within affected app contracts. E1 route unchanged.
