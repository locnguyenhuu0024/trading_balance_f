# Task 114 — Keep OKX guards through disposal

Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE
Requested Model/Effort: gpt-6-luna / xhigh (reused explicitly bound E1 executor)
Observed Effective Model/Effort: unavailable
Specification: docs/agents/specs/2026-10-14-direct-okx-reads-design.md
Plan: docs/agents/plans/2026-10-14-direct-okx-reads.md
Plan Steps: P03
Requirements: REQ-002
Acceptance Criteria: AC-002
Frontend Level: F0

## Finding / Authorization
AUD-transport-lifecycle-01: injected Dio adapter/signer restored immediately by dispose while managed gets remain awaiting credentials, shared coordinator or a later interceptor. Dio selects its current adapter at dispatch; signed request can therefore bypass final destination/method validation after disposal. Current owned production Dio is force-closed; the approved injection seam still violates REQ-002. R2 independent auditor confirmed source control flow and Dio implementation. No real credential exposure observed. This remediation is within approved origin/lifecycle contract and automatic under execution/audit rules; no new product decisions or approval required.

## Preconditions / Write Surface
Predecessor: T113 terminal result and coordinator acceptance; serialize shared Flutter tests/builds. No concurrently writing source/test executor.
Allowed: `lib/core/network/okx_data_client.dart`, `test/core/network/okx_data_client_test.dart` only. No consumers, docs/tasks/telemetry, other source/tests, dependencies, configs or Git changes. Protected configuration/environment contents unreadable and non-writable; native commands may consume opaque settings using --no-pub. No nested agents/external uploads.

## Exact Remediation Contract
1. Count active client-managed `get` pipelines synchronously from entry before any await, with try/finally through terminal response/error. Explicitly await public send and private coordinator future inside this lifecycle boundary so finally cannot clean up early.
2. Dispose sets closed immediately. Owned Dio may close(force:true) immediately. For injected Dio, retain installed final adapter/signer until all managed pipelines drain; only then remove this client's interceptor and restore its delegate if this client's adapter is still installed. Do not close shared/injected Dio or remove unrelated interceptors. Cleanup is idempotent.
3. Reject disposed work after credential loading, before scheduled send, in signer/final adapter validation, and before publishing any late response/error. Use sanitized `OkxDataException(code: 'request_cancelled', message: 'The OKX read client was closed.')` or existing equivalent cancellation semantics. Disposed work must not return success or cause stale rate-limit state. Existing credential fences/header/method/query/origin/no-redirect guards remain intact.
4. A request already sent to approved origin before dispose can finish at its trusted delegate, but its late result must be rejected. No new delegate send after dispose. Raw caller use of restored injected Dio after all client pipelines have drained is outside the closed client's managed pipeline; ordinary shared Dio remains usable.
5. Deterministic tests: pause later interceptor AFTER signing, close client, mutate path/POST/header then release -> zero delegate sends; delay credential loading then dispose -> zero sends; queue second private request with controlled scheduler.delay, dispose before release -> no second send; late pre-sent response never published. Verify injected Dio is restored/usable after drain and other interceptors retained. Use fixture credentials only and controlled completers, no sleep-based synchronization.
6. No new injected timeout policy: null timeout semantics are caller-owned test seam, owned production client already bounded. No architecture/API/signature changes beyond internal lifecycle.

## Verification
RED-114: disposed asynchronous signed request cannot send to foreign origin/POST; delayed credentials/queue/late result rejected. Independently expected zero new sends and typed cancellation.
GREEN-114: normal current-generation public/private requests still succeed; injected Dio can be reused after active pipelines drain without credentials inherited and without being closed.
Final formal checkpoint RED first, then GREEN; run existing RED-001 before GREEN-001 as shared security basis changed. Exact commands/counts/status recorded.
V2 full direct-client test file. V3 invalidate and rerun consumer private-scope, quote-cancellation, signed-out Orders refresh and Portfolio loading tests (exact paths supplied at dispatch from T113 result). Do not rerun unaffected strategy/business tests solely for ritual. Full Flutter suite V4 may run once at final integration because the shared client lifecycle changed after the broad migration; coordinate ownership to avoid duplicate full suite.
Task buildability YES, canonical Flutter app: `rtk flutter build web --no-pub` after last executable edit. RTK-first noisy commands; exact security source evidence raw allowed. SDK/cache sandbox escalation allowed within reviewed Flutter commands; never modify config for tooling.

## Completion / Report
Return exact RED then GREEN/V2/V3/build commands and actual results, changed files, no protected access/modification, external configuration actions none, telemetry logical E1-T114-01, explicit requested route/effective unavailable. Coordinator alone updates artifacts/status and final verdict. Return BLOCKED on contract/scope contradiction.

Coordinator Audit: PASS

## Accepted Evidence
Initial RED-114 failed all four against old behavior; final ordered client file checkpoints `--plain-name RED-114` 4, GREEN-114 2, RED-001 10, GREEN-001 3 passed. Full client file 19 passed. Commands used `rtk flutter test <path> --no-pub` with selectors where stated. Affected ticker polling 7, Orders refresh 8, Portfolio loading 7 passed. Fresh `rtk flutter build web --no-pub` exit0 Built build/web, 24.2s after final executable changes. Coordinator inspected source active-pipeline try/finally, await boundaries, disposed checks/typed cancellation, delayed guard restoration and all added deterministic tests; disposal boundary accepted. No protected paths modified. Final full suite remains coordinator-owned.
