# Design Specification: Direct OKX reads

Status: READY_FOR_PLAN
Date: 2026-10-14
Tier: L
Decision Ledger: docs/agents/decisions/2026-10-14-direct-okx-reads-decisions.md

## 1. Objective
Remove the backend data gateway from exchange display reads and their login requirement while preserving backend authority for trading and strategy application resources.

## 2. Current State
OBS-001: `backend_data_client.dart` maps exchange paths onto backend data routes and private reads require backend sessions.
OBS-002: Portfolio and Orders providers AND screens block reads/refresh during backend session restoration or logout.
OBS-003: `dio_client.dart` has a native direct OKX signer, but web uses same-origin URLs and logging includes sensitive headers/payloads.
OBS-004: The quote service polls a synthetic backend quotes route; native OKX uses tickers.
OBS-005: Position action identity/eligibility are authoritative backend fields. Raw OKX display models do not carry them.
OBS-006: VND uses a CoinGecko-backed gateway with existing 25400 fallback.
Evidence: source/test reads only; no protected configuration inspected. No measured latency baseline.

## 3. Scope
In scope: direct exchange GET transport, credential-change fencing, exchange repositories/pollers, signed-out read/refresh UX, action-triggered backend position selection, direct CoinGecko VND rate, affected tests.
Out of scope: backend service implementation, strategy business logic, credential persistence redesign, dependency/configuration changes, commits/push/deployment, visual redesign.

## 4. Decisions
D-001: User requests new branch and immediate execution after planning; overrides repository requirement for another approval turn.
D-002: User selected direct CoinGecko with existing fallback.
A-001: User authorizes proposing and proceeding on implementation choices. Preserve authenticated strategy application resources and mutation preflight reads because they are not exchange display data.

## 5. Requirements
REQ-001: All exchange display reads use native HTTPS OKX routes on every platform, including web. Public reads need neither credentials nor backend login. Private reads use existing locally stored OKX credentials. No fallback through backend.
REQ-002: Private read transport is GET-only, route-allowlisted, fixed to `https://www.okx.com`, denies redirects, backend Authorization and destination/method mutation at the final adapter boundary, and does not log credentials/account bodies. Credential save/clear invalidates queued/in-flight results and private read caches independently of backend login. Empty/missing credentials and rotation in progress fail before send. Authentication failures do not expire backend login.
REQ-003: Preserve cancellation, deduplication, bounded retries/backoff, freshness and candle validation. Positions/pending ALL omit instType; history ALL queries SPOT/MARGIN/SWAP/FUTURES, sequentially with shared authenticated scheduling, returns complete merged newest-first data or fails atomically. Preserve existing first-page history depth, no new pagination scope.
REQ-004: Visible balances/positions/orders and refresh do not read or wait for backend sessions. Backend login enables trading actions and strategy management only. Position actions obtain authoritative backend positions only after explicit action entry; direct display identity is never promoted to trading authority. Present an explicit backend account/target selection dialog reusing existing authoritative PositionActionControls and prepare/confirm/execute. Do not infer that local OKX credentials and backend account are identical. Close-all remains backend account-wide. Mutation callbacks refresh direct data.
REQ-005: Public strategy market analysis reads OKX; saved strategy/list/draft/results/retry/execution stay backend and authenticated. VND calls CoinGecko `/api/v3/simple/price?ids=tether&vs_currencies=vnd` through a separate credential-free client; invalid/rate-limited/network responses retain 25400 fallback.

## 6. Data Contract
Native OKX envelope `code/msg/data` and existing string decimal DTOs remain unchanged. Quote service fetches one SPOT tickers envelope per poll and filters only active canonical USDT instruments with valid positive prices and age <=15 seconds. No synthetic quotes route. Stable position keys include native posId/instrument/type/side/margin/currency rather than empty backend identity. VND requires positive finite `tether.vnd`.

## 7. Cross-Layer Mapping
UI read -> repository -> direct OKX GET. UI trade action entry -> authoritative backend account/position selection -> existing prepare/confirm/execute. Strategy app resources -> existing StrategyApi. Currency -> separate CoinGecko client.

## 8. Proposed Design
Add an independently testable OkxDataClient with injectable Dio, storage and coordinator; reuse native signing logic and existing error scheduling seams. Observable credential-change generation belongs to storage lifecycle and is propagated to client/read providers. Every save/clear, including web overrides, fences stale work before mutation begins and invalidates again on completion. Keep legacy backend transport for retained contracts/tests; migrate all production display consumers.

## 9. Interfaces
`OkxDataClient.get(path, queryParameters, cancelToken)`; route determines authentication, not caller flags. Public repositories retain their existing public RequestCoordinator wrappers; private direct reads use authenticated scheduling without nested coordinator deadlock. BackendDataException may remain a compatible sanitized error seam; its name does not imply backend routing. No protected file or new dependency required.

## 10. Invariants
INV-001: No exchange credential or bearer token crosses between OKX, CoinGecko and backend transports.
INV-002: No background/render polling of backend positions to decorate direct display.
INV-003: Trading authority, account locks, uncertainty/idempotency, confirmation ownership and backend session checks remain intact.

## 11. Edge Cases
Missing credentials: localized update-API-key error, zero private sends. Credential rotation: stale results rejected and provider cache invalidated. 401/auth envelope: direct credential error, backend session untouched. HTTP/OKX-envelope rate limit: shared lane backoff. One history type failure: fail complete ALL read. Stale quotes: remove prices on deadline even while next poll is pending. No authoritative backend target: dialog shows empty/error and sends no mutation.

## 12. Failure Semantics
Sanitized typed errors preserve cancellation/status/retry-after. No raw Dio credential-bearing error interpolation into user messages/logs. Browser CORS/network denial is surfaced without silently proxying. Live browser/private exchange verification is unavailable without user credentials; do not claim it passed.

## 13. RED / GREEN
RED-001: missing credentials, foreign destination/method/bearer, credential rotation during request, and rate-limit failure are rejected before private publish/send as applicable.
GREEN-001: valid fixed-origin signed GET uses full query signature; public reads succeed signed out.
RED-002: incomplete ALL history or stale quote rejected; backend session restoration does not trigger display reads; authoritative-action dialog aborts after session change.
GREEN-002: signed-out direct balance/positions/orders/refresh; native ALL and polling semantics; explicit backend action flow and strategy authentication preserved; direct VND positive result.
Formal RED before GREEN for each task.

## 14. Performance
Structural acceptance: remove intermediary HTTP hop and synthetic per-batch quote calls; one native SPOT ticker request per union poll. Keep existing scheduling limits. No live latency claim without measured evidence.

## 15. Compatibility
Preserve existing account models, filters, first-page history scope, strategy semantics and credential storage UX. Update obsolete backend-login read tests; preserve security/mutation tests. Native and JavaScript web compilation required.

## 16. Security
Direct read keys remain existing user-owned credentials. No generated/configured secrets and no exchange writes via direct client. Backend-action dialog clearly labels backend account and authoritative target; matching display fields is not proof of account equality.

## 17. Protected Configuration / Environment Actions
None planned. Protected contents never read or modified. Build tools may consume existing settings as opaque inputs.

## 18. Rollout / Rollback
Review branch diff, run focused checks and final web build, then user chooses release. Roll back code migration via a separately authorized Git operation; no schema/data migration. CORS failures must not introduce implicit backend fallback.

## 19. Acceptance Criteria
AC-001: direct public and signed private requests use exact OKX native endpoint; no backend login dependency.
AC-002: hostile routing, absent/changed credentials and auth failures preserve the transport/account boundary.
AC-003: native ALL history/pending/positions and one-request quote polling preserve complete/fresh data semantics.
AC-004: signed-out display/refresh works; backend authority and login remain for mutations/strategy.
AC-005: CoinGecko direct rate or existing fallback, with no shared credentials.

## 20. Traceability
REQ-001/002 -> AC-001/002 -> P01/T112 -> RED-001/GREEN-001.
REQ-003/004/005 -> AC-003/004/005 -> P02/T113 -> RED-002/GREEN-002.

## 21. Completion Gate
Resolved semantics, planning fan-out collected, no protected access, task buildability, RED/GREEN, affected regression tests, independent audit and final fresh web build required. Live credential/browser limitations must be reported.
