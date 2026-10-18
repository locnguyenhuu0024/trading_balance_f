# Task 112 — Direct OKX transport

Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE
Observed Effective Model/Effort: unavailable
Specification: docs/agents/specs/2026-10-14-direct-okx-reads-design.md
Plan: docs/agents/plans/2026-10-14-direct-okx-reads.md
Plan Steps: P01
Requirements: REQ-001,002
Acceptance Criteria: AC-001,002
Frontend Level: F0

## Objective / Preconditions
Add a tested, buildable native OKX GET client for next-stage display migration. No predecessor. User immediate execution authorized in D-001. Preserve all current consumer contracts until T113.

## Allowed Write Surface
`lib/core/network/okx_data_client.dart` (new), `lib/core/network/okx_interceptor.dart`, `lib/core/network/dio_client.dart`, `lib/core/security/secure_storage_helper.dart`, credential-save/clear overrides only in `lib/main.dart`, `test/core/network/okx_data_client_test.dart` (new), `test/core/security/okx_credential_generation_test.dart` (new). Do not change planning/tasks/telemetry.

## Forbidden Scope
All protected configuration/environment/dependency/build files unreadable/non-writable; no source secrets, external uploads, dependencies, backend changes, unrelated UI/storage changes, Git mutations. Never read manifests/lockfiles. Native Flutter commands may consume them opaquely. No child spawning.

## Exact Contract
1. New `OkxDataClient.get(path,{queryParameters,cancelToken})` uses `https://www.okx.com` on all platforms. Injectable Dio/storage/coordinator for tests. No .dio escape seam needed for consumers. Use route allowlist for `/api/v5/public/instruments`, `/market/ticker`, `/market/tickers`, `/market/candles`, `/market/history-candles`, `/public/funding-rate`, `/public/open-interest`, `/account/balance`, `/account/positions`, `/trade/orders-pending`, `/trade/orders-history`, `/account/config`, `/account/instruments`, `/account/trade-fee`, `/account/interest-rate`, `/account/interest-accrued` (all prefix `/api/v5`). Private account/trade routes signed; public routes never get credentials. No synthetic quotes/VND routes or exchange write routes.
2. Reuse native HMAC timestamp + uppercase method + exact encoded path/query + empty GET body signing logic. Capture immutable credential snapshot for each private request, reject absent/empty fields and storage rotation before send, fixed GET/no redirects. Block caller/later interceptor destination or method manipulation, backend bearer Authorization, userinfo/fragments, altered signed request/query at final adapter boundary (including Dio.fetch bypass tests when possible through injected Dio). Do not trust mutable extra as sole authorization record. Preserve cancel token. Do not log signed headers/private bodies or interpolate raw credential-bearing errors.
3. Observable credential generation belongs to SecureStorageHelper credential lifecycle: increment/fence at save/clear start, mark rotation in progress, finish/increment on success or failure; notifications cover WebStorageHelper overrides as well. Add a safe explicit notifier/listenable API reusable by client and private providers, no stored secret output. Public reads must not load credential storage. If concurrent writes occur, do not mark rotation ended until all finish. No persistence UX changes. Reject late private successes AND errors after generation changed. Invalidate read clients/providers on generation changes through Riverpod seam. Dispose only own listeners/clients, not injected shared storage.
4. Public repository scheduling stays outside client; private reads use shared authenticated RequestCoordinator with keys containing credential generation + canonical path/query. Avoid nested shared scheduler deadlocks. Distinct owners' cancellation must not corrupt single-flight results; credential rotation resets private backoff for next generation while old queued work stays fenced.
5. Sanitize failures through compatible BackendDataException fields or a compatible typed direct error understood by later provider scheduling. Missing credentials -> `okx_credentials_required`; rotation/stale -> `credentials_changed`; cancelled -> `request_cancelled`; auth -> safe API-key message with 401 status without touching TradeSession. Preserve status/retry-after/network errors. Translate OKX envelope 50011 rate-limit into HTTP-like 429 before coordinator sees it; nonzero envelope failure sanitized. Private client never invokes backend unauthorized handlers.
6. Harden/stop unsafe LogInterceptor on legacy dio seam if reused; do not add unused second credential/signing implementation when existing signer can be adapted safely. Public/private headers remain isolated.

## RED / GREEN / Verification
RED-001: tests for missing credentials (zero sends), foreign destination/method/Authorization/redirect/query mutation denied, rotation mid-queue/in-flight rejects stale results, rate-limit envelope/backoff. Expected independently from fixed-origin/read-only/credential-generation contract.
GREEN-001: public GET succeeds without storage/backend session; signed GET receives valid HMAC for exact encoded query using fixture keys; current generation succeeds. Web storage lifecycle shares notifications.
Inner loop narrow tests. Formal final RED tests FIRST then GREEN tests with exact --plain-name names recorded. V2 new test files plus affected storage tests if changed behavior warrants. Build gate YES Flutter app: `flutter build web --no-pub` after last executable edit. RTK-first noisy output, exact source fallback allowed. One safe escalation retry for toolchain permission issue; request necessary sandbox approval rather than repeated retries. Never modify config to fix tooling.
External configuration actions: none. Live key/browser connectivity not required or claimed.

## Stop / Report
Return BLOCKED on unresolved contract, protected requirement or scope overflow. Do not self-escalate route. Return compact changed files, formal exact RED then GREEN results, test counts, exact fresh build command/status, limitations, no protected access/modification, telemetry envelope logical `E1-T112-01`, requested gpt-6-luna/xhigh, effective unavailable unless runtime exposes it. Coordinator alone updates task status.

## Coordinator Audit
Verdict: PASS — see docs/agents/validation/2026-10-14-direct-okx-transport-audit.md
