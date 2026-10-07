# Backend-owned application data

Status: READY_FOR_PLAN
Date: 2026-10-07
Tier: L
Decision Ledger: docs/agents/decisions/2026-10-07-backend-data-gateway.md

## Objective and observed state

All production Flutter OKX account/market reads must reach the existing backend HTTPS origin. Reduce repeated exchange work and connection setup while preserving calculations, risk ownership, order confirmation and fresh terminal proof. Current evidence: portfolio_repository.dart and order_repository.dart request OKX routes; Fractal creates an OKX Dio; okx_websocket_service.dart opens an OKX socket; background_service.dart constructs signed/public OKX clients. backend/okx.py opens/closes one HTTPSConnection per call; TradeService._fetch_snapshot performs sequential reads; StrategyService._list repeats account and SWAP observations per strategy.

No latency percentage or production deployment claim is justified by static inspection. Static media and notification integrations are outside financial-data transport scope. The user explicitly added the existing CoinGecko USDT/VND rate to backend-owned data.

## Decisions and scope

D1: The user confirmed exactly one existing backend OKX account. Backend session authentication is required for all private reads; no client exchange credential fallback.
D2: The user chose shared polling now and deferred realtime push. No SSE/WebSocket infrastructure or dependency/configuration change.
D3: User authorized a new branch from main, planning followed by immediate task execution. No commit/push/deployment authorization.
D8: User explicitly authorized moving the existing CoinGecko VND conversion rate through backend as well; preserve conversion math and existing frontend fallback.

## Requirements

- REQ-001: An explicit GET-only gateway exposes the registry below. Unknown paths, methods, keys, repeated query values, oversized/malformed queries fail before exchange access. No arbitrary forwarding URL, method, headers or exchange credentials.
- REQ-002: Every private request validates the existing backend session, including cache hits. A validated account fingerprint fences private cache generations; identity changes/unavailability invalidate private observations. Misses verify identity before/after acquiring private data. Cached identity may be reused for at most one second. No expired private response is returned as fresh.
- REQ-003: Preserve upstream numeric strings, rows, ordering and one-page pagination semantics in `{code:"0",msg:"",data:[...],dataMeta:{fetchedAt,expiresAt,source:"backend",cacheHit}}`. Account config exposes only uid,mgnIsoMode,acctLv,posMode,autoLoan. All balance currencies are retained. Invalid upstream data produces an error, never fabricated empty positions. Map sanitized upstream rate-limit errors to HTTP 429 with Retry-After.
- REQ-004: Successful read caching has monotonic deadlines, deep-copy outputs, canonical normalized query keys, per-key single-flight, at most 256 entries/32 distinct in-flight keys/four concurrent display upstream reads per service instance. Errors never populate cache. No network work occurs under the global cache lock. Service-instance bounds are explicit; no cross-process cache guarantee.
- REQ-005: Reuse bounded HTTPS connections with exclusive leasing. Discard connections after transport/protocol/oversize failures; preserve signing, injectable transport and response limits. Do not replay any write. Reserve capacity for uncached write preflight; do not serialize every request through a single connection.
- REQ-006: Flutter uses existing TRADE_API_BASE_URL validation and browser cookie adapter. All migrated production clients reject unconfigured/insecure endpoints and redirects; strip/block exchange auth headers. Private session changes/expiry fence in-flight responses and invalidate private views. Public reads work without login.
- REQ-007: Portfolio prices use one bounded backend ticker polling service with subscription union, overlap guards, disposal cancellation, reconnect/backoff, and stale-response fencing. Only active consumers generate polls. Preserve the current selected-screen refresh policy and ALL throttle. No hidden-page polling expansion. Failed/expired price observations cannot silently remain current.
- REQ-008: Risk foreground/background transports use backend sessions, with explicit acknowledged in-memory Android session handoff, monotonically fenced generations and expiry/logout invalidation. No bearer persistence in ordinary preferences, logs, state/ack payloads or notifications. Android ownership is not granted before handoff acknowledgement. Existing calculations, history, episode persistence, notifications and exclusive ownership remain unchanged. Authentication failures remain distinct from zero positions.
- REQ-009: Strategy list state refresh remains sequential and unchanged in semantics, followed by one fresh uncached SWAP observation shared across surviving results and account identity pre/postchecks. No display cache participates in prepare/execute/delete/completion proof. Preserve active/corrupt queue exceptions, recovery, replacement cleanup, scope/hedge semantics and order scan freshness.
- REQ-010: Public GET `/v1/data/currency/usdt-vnd` accepts no query. Backend alone calls fixed CoinGecko host/path/query `/api/v3/simple/price?ids=tether&vs_currencies=vnd`, with no redirects or exchange/session credentials. Validate tether.vnd is numeric, positive and finite (not boolean). Cache successful rates for 60 seconds with existing bounds/single-flight. Gateway data is `[{instId:"USDT-VND",rate:<numeric string>,source:"CoinGecko"}]`; failures are sanitized 502, never fabricated fallback. Existing frontend 25400 local fallback and currency calculations remain.

## Gateway registry and validation

Prefix `/v1/data/`; upstream prefix `/api/v5/`. Registry maps suffix constants, never caller-provided upstream URLs.

| Suffix | Scope | Accepted query fields | TTL seconds |
|---|---|---|---:|
| public/instruments | public | instType: SPOT,MARGIN,SWAP,FUTURES; optional instId | 60 |
| market/ticker | public | required instId | 1 |
| market/tickers | public | required instType: SPOT,SWAP,FUTURES | 1 |
| market/quotes | public | required instIds, 1..100 distinct SPOT ids; derived by filtering cached SPOT tickers | 1 |
| market/candles; market/history-candles | public | required instId; bar,limit,after,before | 15 |
| public/funding-rate | public | required SWAP instId | 15 |
| public/open-interest | public | required SWAP instId,instType=SWAP | 15 |
| account/balance | private | optional ccy | 1 |
| account/positions | private | required instType: MARGIN,SWAP,FUTURES,ALL; optional instId | 1 |
| trade/orders-pending; trade/orders-history | private | required instType: SPOT,MARGIN,SWAP,FUTURES,ALL | 1 |
| account/config | private | none | 1 |
| account/instruments; account/trade-fee | private | required instType=MARGIN,instId | 60 |
| account/interest-rate | private | required ccy | 60 |
| account/interest-accrued | private | required instId,mgnMode=isolated; ccy,limit,after,before | 15 |
| currency/usdt-vnd | public | none; fixed CoinGecko transport, not OKX mapping | 60 |

Query length <=4096 bytes; identifiers uppercase bounded ASCII `[A-Z0-9]+(?:-[A-Z0-9]+){1,3}`, <=100 chars; currency `[A-Z0-9]{1,20}`; bars 1H,4H,6Hutc,1Dutc,1Wutc; limit decimal 1..300 (interest-accrued <=100); cursors decimal <=32 digits, forwarded without reinterpretation. Default limit/bar preserve upstream/default existing consumer behavior. Required field absence rejects. ALL is backend-only fan-out: positions MARGIN,SWAP,FUTURES; orders SPOT,MARGIN,SWAP,FUTURES; concatenate in that order, stable newest-first order sorting in the frontend. Any failed subread fails the aggregate. Quotes filter complete full instrument identities, not substring symbols. Existing origin/CORS policy remains.

Quotes wire encoding is one comma-delimited `instIds` value, e.g. `BTC-USDT,ETH-USDT`, URI-encoded normally by the client. Deduplicate full ids; batches contain at most 100. Missing ticker ids are absent, not fabricated; frontend removes/marks absent prices stale.

Live quote freshness: upstream ticker ts must be valid and no older than 15 seconds; expire displayed live prices independently of a pending/hung poll. One bounded expiry timer per polling service is sufficient; test clock/age seams are allowed. Cancel active HTTP requests on zero subscriptions/disposal and recheck generation before every batch, including after failed awaits.

Aggregated private/normalized display responses retain child monotonic freshness metadata. Verify deadlines at final publication, allow at most one bounded refresh of expired child observations, then return sanitized 503/data_stale if a fresh complete response cannot be assembled. Bound normalized-position executor admission as well as upstream reads. Authentication errors crossing worker boundaries retain 401; identity rate limiting retains 429/Retry-After. The compatible Flutter Dio seam validates destination, GET route, redirects and forbidden headers at the final adapter send boundary, including raw fetch/options or later-interceptor mutation.

Android handoff generation is a service protocol watermark, separate from a UI-local request generation. Handshake/ack expose only the applied watermark; a recreated proxy allocates a larger generation, serializes handoffs and rechecks current session before Start. Reject older/conflicting replay. Immediate monitor credential fencing must not invoke the existing automatic-restart invalidation command on logout/expiry/401; stop/auth-block instead. Reconnect ownership/restart requires a fresh acknowledged active session.

## Freshness and safety

Display TTLs are engineering choices bounded by existing page cadences, not promises about exchange freshness. Upstream timestamps remain authoritative for market freshness. Normalized `/v1/positions` may reuse gateway display reads and parallel independent groups, but `_fetch_snapshot`'s default action path remains fresh. Account metadata caching must not change write preflight. Error outputs contain no credentials/payloads/raw exception text. Pool/read saturation returns bounded sanitized errors; no unbounded thread/lock growth.

After authorized action execution or strategy POST processing, invalidate private display observations in a finally path, including ambiguous outcomes: increment/fence the private generation and clear identity/entries so pre-action in-flight data cannot repopulate caches. Immediate user-action-driven reload must not reintroduce a pre-action position/order snapshot. Actual execution/worker proof stays uncached. Gateway exposes a bounded invalidate_private() operation for this purpose.

Strategy list: refresh each selected record in existing order, reread surviving records after all refreshes, fresh account check, one raw validated SWAP positions fetch for noncandidates, fresh account postcheck, then project. Empty/candidate-only lists do not request positions. Preserve `_basic_result`, `_can_delete_hint`, `_delete`, worker fencing and placement guards.

## Acceptance and verification

- AC-001: Gateway allowlist/auth/query parity, all-currency balance, all-type aggregate completeness and rate-limit propagation verified with fake upstream transport.
- AC-002: Concurrent equal reads share one upstream result; TTL expiry refreshes; failures release waiters; bounds/eviction/deep-copy and account isolation verified.
- AC-003: Connection reuse/exclusive leasing/discard and no ambiguous POST replay verified without real exchange calls.
- AC-004: Production Flutter wiring reaches only backend for listed OKX reads. Public reads need no session; missing/expired/revoked private sessions cause zero unauthorized transport calls; logout midflight discards results.
- AC-005: Poll subscription changes/disposal/failures/idle pages have deterministic request-count and stale-state coverage. Financial DTO and candle/history calculations remain unchanged.
- AC-006: Foreground and Android Risk use backend auth, acknowledged generation-fenced handoff, expiry/logout fencing and no exchange fallback; existing ownership/notification tests pass.
- AC-007: Strategy list call counts are constant for shared observations, all reconciliation precedes position acquisition, and terminal/queue/replacement/account-change negative tests pass.
- AC-008: VND provider calls backend without login; successful positive rate preserves math; malformed/unavailable rate uses existing local fallback. Currency upstream fake verifies fixed path, no credentials, strict numeric validation and 60-second cache/single-flight.

Focused tests precede one final backend discovery and Flutter suite. Final canonical builds: `python3.12 -m compileall -q backend` and `flutter build web --no-pub`. Native Android build/runtime coverage is reported separately; no production API/OKX calls or deployment are authorized by this plan.
