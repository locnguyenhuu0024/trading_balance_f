# Design specification: Multi-user OKX and Binance expansion

Status: READY_FOR_PLAN — proposal under user-delegated choices; execution not approved
Date: 2026-10-10
Tier: L
Revision: 1
Decision Ledger: `docs/agents/decisions/2026-10-10-multi-user-okx-binance-decisions.md`
Frontend Brief: `docs/agents/specs/2026-10-10-multi-user-okx-binance-frontend-brief.md`

## 1. Objective and boundaries

Evolve the personal Flutter/Python trading application into a tenant-isolated application for independent users connecting OKX and Binance accounts. Preserve the single backend data boundary, server-proven trade outcomes and current native UI. Make account selection obvious, response times measurable and resource usage bounded.

This revision authorizes no implementation. It describes the complete target and a staged beta. The beta includes tenant-safe OKX, Binance Spot read-only data and standard Binance USD-M reads plus gated One-way regular-order actions. Binance Hedge/algo/strategy parity is a later capability gate, not an implied beta promise. Combined overview is read-only. No custody, withdrawal, transfer, pooled trading, organizations, social login, billing, public registration or profitability claim.

## 2. Current state: source evidence, not runtime proof

| ID | Source / location | Observation and consequence |
|---|---|---|
| OBS-001 | `backend/app.py:33`; `backend/service.py:166` | One service and one OKXClient are created from backend runtime settings. Multiple sessions currently share this exchange context. |
| OBS-002 | `backend/store.py:16`, `:31`, `:36` | Singleton auth/TOTP state; sessions lack user ownership; operations lack explicit tenant/connection owner. Authentication alone cannot enforce future isolation. |
| OBS-003 | `backend/store.py:48`, `:74`, `:82`, `:91` | Strategies/preferences/reservations use account fingerprints; monitor lease is singleton. These are useful primitives but not a multi-user authorization boundary. |
| OBS-004 | `backend/service.py:269`, `:399`, `:1049` | Account fingerprints depend on session signing key, session reads use a transaction, pending-operation conflict search needs account partitioning. Stable connection IDs and indexed owner queries are necessary. |
| OBS-005 | `backend/service.py:1370`, `:1401`, `:1719`; `backend/store.py:260`, `:310` | Process-local mutation lock and operation status handling must become durable claims before multiple API processes. SQLite DELETE journal / immediate transactions serialize writers. |
| OBS-006 | `backend/strategy_worker.py:1025`, `:1037`, `:918` | Worker places orders and sets leverage; it is not read-only. Preserve write markers and fence every mutation and reconciliation. |
| OBS-007 | `backend/strategy.py:4005`, `:4021` | Listing strategies synchronously reconciles account strategies. Multi-user list endpoints need paginated persisted projections rather than per-row upstream calls. |
| OBS-008 | `backend/data_gateway.py:164`, `:531`, `:927`, `:1189` | Existing allowlisted gateway, single-flight/cache and identity protection can be reused with explicit connection scope. |
| OBS-009 | `lib/core/network/backend_data_session.dart:34`; `lib/core/network/backend_data_client.dart:40` | Existing generation fencing is reusable; frontend route mappings still encode OKX semantics. |
| OBS-010 | `lib/features/orders/data/trade_api_client.dart:124`, `:337`; `lib/main.dart:387` | Login/session lacks app-user and connection IDs; browser stores singleton OKX credentials. Connection onboarding must replace this storage explicitly. |
| OBS-011 | `lib/core/network/okx_websocket_service.dart:34`, `:59`; `lib/features/market/presentation/providers/market_provider.dart:9` | Quote service polls backend; coin-only map keys cannot distinguish exchange/product. No existing realtime benefit is assumed. |
| OBS-012 | `lib/core/theme/app_theme.dart:25`, `:38`, `:66`; trade confirmation dialog `:59` | Reuse current tokens, 48px targets and session-sensitive confirmations. |

No latency baseline, production topology, live schema, dependency installation, actual permission or device behavior was verified. Earlier gateway memory only guided inspection; current source owns these observations. No protected configuration was read.

## 3. Requirements and acceptance criteria

| Requirement | Required behavior / failure contract | Acceptance criterion |
|---|---|---|
| REQ-001 Identity | Invitation-only user activation, username/password, per-user TOTP replay protection and single-use recovery codes. Session has immutable owner and expiry/revocation generation. Operator manages invites, not trading permissions for another user. Missing/expired/revoked auth → 401; no private payload. | AC-001: Two users can sign in independently; replayed TOTP/recovery code fails atomically; logout/recovery revokes appropriate sessions. Public data remains separately available. |
| REQ-002 Ownership/vault | Every connection, private query, operation, strategy, reservation, audit record and worker claim has user/connection scope. Backend encrypts credentials; ordinary recent step-up required for connection changes, enabling trading and MFA/security changes outside the restricted recovery flow in §6. No plaintext credential persistence/logging/response. | AC-002: User B's reads, actions, list pages, result lookup and worker events cannot access or affect A, including guessed IDs; return indistinguishable 404. Rotation/revocation fences queued work and stale reads. |
| REQ-003 Exchange contracts | Adapters normalize domain data and intents with explicit exchange/product/environment/native units/mode/capabilities. Preserve OKX behavior; Binance starts read-only, then USD-M One-way regular actions. Unsupported feature → 422 `capability_unsupported`, zero writes. | AC-003: Contract fixtures and exchange demo cases prove correct decimals, quantities, filters, mode mapping, partial fill/cancel and unsupported paths; no Spot position-close semantics. |
| REQ-004 Safe commands | Prepare binds owner, connection, credential/permission versions, metadata/mode, expiry and targets. Execute uses durable CAS claim/lease and pre-send ledger. Unknown outcome triggers reconciliation, never automatic resubmission. | AC-004: Concurrent execute, execute/result race, crash-after-send, revoked permission and expired confirmation produce at most one submission attempt; eventual status is proven or remains UNKNOWN without fake success. |
| REQ-005 UX/UI | Follow F2 brief; explicit account context, immediate switch fencing, clear connection states, capability-aware actions, localized format, accessible native interaction. Browser exchange secrets are removed only through a user-triggered migration flow. | AC-005: Delayed A response/401 cannot appear in B; 360/1440px, text 200%, keyboard/screen reader, 48px targets and all critical states pass rendered review. |
| REQ-006 Performance | Share public data; bound private account contexts, query fan-out, queue depth, retries and credential decrypt lifetime. Fair scheduler and layered exchange/IP budgets; page data locally; adaptive foreground polling. | AC-006: Spec §11 load targets pass with semantic parity and zero tenant leaks/duplicate submits; overloaded load is rejected predictably; inactive views do not poll. |
| REQ-007 Migration/release | Explicit offline ownership mapping, old session revocation, freeze/drain/reconcile writes, validate PostgreSQL migration and restore. No implicit adoption of an unknown legacy account or replay of old jobs. | AC-007: Representative migration dry run preserves counts/decimals/terminal states, quarantines ambiguous records, rejects unsafe resume and passes rollback rehearsal before beta. |

## 4. Data contract and ownership

An app user is the security tenant. An exchange connection is a user-owned credential relationship to a verified remote account and environment. A product is a venue-specific market within that relationship. None are inferred from a display nickname or bearer token hash.

| Entity / fields | Contract / indexes |
|---|---|
| users | `user_id` UUID, normalized unique username, salted password hash, status, auth_version, created_at. No public user directory. Username ASCII 3–64 chars; password uses existing ≥16-character policy, permit paste/password managers. |
| user_mfa / recovery / invites | Per-user encrypted TOTP seed, last accepted counter; salted/hashed recovery codes with atomic consumed_at; hashed invite token, expiry, one-use activation. Invite validity 24h; rate-limit enrollment/login/recovery. |
| sessions | Hashed opaque token, user_id FK, created_at, expires_at, last_seen_at, revoked_at, auth_version; idle tracking debounced, not a write on every read. 30-minute inactivity / 12-hour absolute expiry; step-up grants last 5 minutes and never outlive session. |
| exchange_connections | connection_id UUID, user_id FK, exchange enum, product capabilities, environment live/demo, supported API region enum, nickname, status, remote_identity_digest, credential_version, permission_version, timestamps. Unique canonical remote identity per exchange/environment/region domain, including revoked tombstones and unresolved work. Same-owner relink retains connection_id and safety barriers; owner transfer unsupported in v1. Identity discovered through documented authoritative account metadata; never fabricate from API key or balances. |
| encrypted_credentials | connection_id FK, credential_version, key_id, AEAD nonce/ciphertext/tag; associated data binds owner, connection, exchange and version. Versioned vault key independent of session key and remote-identity digest key. |
| operations / order ledger | user_id, connection_id, product, operation_id, idempotency_key, request_hash, status, claim/fence/lease, confirmation digest/expiry, pre-send marker, per-target result, native/client order IDs. Unique `(user_id, connection_id, idempotency_key)`; conflict lookup uses connection+instrument+side. |
| strategies / reservations / preferences | Stable connection ownership replaces auth-key-derived fingerprint; product/instrument/position mode/side scope explicit. Index `(user_id, connection_id, status, updated_at, id)` for pagination. Reservations enforce position-scope conflicts, not just symbol strings. |
| worker claims / audit | Per-connection execution lease and monotonic fence, due-job indexes, safe audit events with owner and result transitions. No secrets/raw signed requests. |

Private scopes always contain user_id, connection_id, exchange, environment, product and credential/permission generation. Market-data keys contain exchange, region/environment feed class, product, canonical instrument and query. Live/demo public data is shared only when the adapter explicitly proves the feed semantics identical.

Use Decimal on backend and decimal strings in APIs for prices/quantities/money. Keep `nativeQuantity`, `quantityUnit=base|contracts`, `baseQuantity` (nullable when not valid), contract value/type, settlement asset, tickSize, lotStep, minQuantity and metadataVersion. Unsupported or missing values are null/unavailable, never zero. Timestamp fields are UTC ISO-8601; exchange event time and server fetch time are distinct. Local timezone remains a presentation preference.

Independent conversion example: a fixture with contract value 0.01 BTC and native size 3 contracts has baseQuantity 0.03 BTC; a Binance base-size fixture 0.03 BTC has nativeQuantity 0.03. They share exposure but cannot share a raw order payload. A 0.003 step rounds a desired 0.010 base quantity downward to 0.009, not by counting decimal places. For inverse contracts baseQuantity requires the specified price and formula; otherwise leave null.

## 5. Architecture and cross-layer mapping

```text
Flutter native UI / Riverpod
  -> UserSession + selected ConnectionScope + generation
  -> one BackendDataClient / TradeApiClient (normalized v2 DTOs)
  -> Python API: auth -> ownership -> capability -> admission
  -> bounded AccountContext registry + ExchangeAdapter
       -> OKX adapter / Binance Spot adapter / Binance USD-M adapter
       -> shared public data cache / isolated private snapshot
  -> PostgreSQL command ledger + user/connection state
  -> fair bounded worker -> per-account lease/fence -> exchange
  -> reconciliation -> durable projection -> UI status reads
```

Keep WSGI request handling initially. Adapters wrap existing OKX transport, pooling and behavior; do not rename all source files to create architecture. Extract a storage contract with SQLite-compatible staging, then a PostgreSQL implementation with equivalent transactions. Public feed coordinator is shared; private account contexts are lazy, bounded and evictable only when no active claim/flight exists. Idle credentials are not retained indefinitely in a client object.

| Semantic | Persistence | API/DTO | Frontend consumer |
|---|---|---|---|
| User/session | users/sessions/mfa | `/v2/session`, userId/sessionVersion/expiry | trade session provider |
| Connection | owned connection/vault | `/v2/connections`, opaque ID/status/capabilities | connection manager/header |
| Instrument | adapter metadata cache | exchange/product/instrument/native units | market/order/strategy repositories |
| Snapshot | scoped cache/projection | scope/asOf/fetchedAt/stale/complete/data | portfolio/order providers |
| Operation | durable ledger/targets | operationId/status/item outcomes | existing confirmation/result flows |
| Strategy | scoped rows/reservations | paginated persisted projection | strategy dashboard |

## 6. API and internal interfaces

Proposed v2 contracts are additive. Legacy private v1 endpoints remain restricted to the mapped legacy owner in private development/migration only; disable them before external beta. Public v1 gateway routes may remain during staged frontend migration. There is no fallback from a v2 ownership failure to v1.

- `POST /v2/invites/activate`: invite, username, password → enrollment challenge; activation completes only after TOTP proof and recovery acknowledgment.
- `POST /v2/login`: username + password + TOTP → ordinary session; username + password + single-use recovery code → restricted MFA-recovery session. A code alone never replaces the password. Recovery atomically consumes the code, increments auth_version and revokes previous sessions; it grants enrollment/recovery routes only, not private exchange data, trading, connection/credential changes or step-up. New verified TOTP enrollment ends that restricted session and requires a fresh ordinary login before sensitive actions. Web uses Secure/HttpOnly/SameSite cookie with origin/CSRF protection for mutations; native uses securely stored opaque bearer. Never expose web bearer in persistent browser storage. `/v2/session`, `/v2/logout`, `/v2/step-up` manage session and recent authentication.
- `GET /v2/connections`: owner-filtered connection list, no secret fields. `POST /v2/connections`: typed credentials and desired live/demo/region, explicit consent → verify then encrypt/persist; failed verification does not create a ready connection. Step-up required. `/v2/connections/{id}/verify`, `/credentials`, `/revoke` support bounded revalidation/rotation/revocation; verification is rate-limited and connection-owned.
- `GET /v2/connections/{id}/balances|positions|orders?product=...&cursor=...&limit=...`: normalized paginated data and freshness/complete metadata. Default limit 50, max 200, cursor includes stable scope/query/snapshot; malformed cursor → 400, no spill into another scope.
- `GET /v2/market/...`: allowlisted exchange/product/instrument queries, no arbitrary proxy/URL. Explicit regional allowlist; no user-supplied API hostname (SSRF protection).
- `POST /v2/connections/{id}/actions/prepare`: typed close/cancel intent, target selection → bound operationId, safe preview, one-use confirmation, expiry (30s). Unsupported/revoked/stale prerequisites fail before ledger becomes executable.
- `POST /v2/connections/{id}/actions/execute`: operationId, confirmation, idempotencyKey → accepted/proven status. Repeated same key+same payload returns existing operation; key reused for different payload → 409. `GET .../actions/{operationId}` is owner-scoped.
- Strategies use the same owned connection path, mode/capability checks and command ledger. List endpoints read durable projections and do not reconcile every item in a request.

`ExchangeAdapter` contract: identify_account, read_capabilities, read_balances, read_positions, read_orders/page, instrument_metadata, fresh_preflight, place_order, cancel_order, close_position, lookup_order, classify_error; all take product/context/deadline and emit typed normalized outputs. Strategy-specific leverage/tier/algo methods are optional capabilities and fail closed. Clock offset/recvWindow and request signing are exchange-specific. An acknowledgment means accepted, not filled/canceled.

Authentication admission is independent of trading I/O: initially at most four concurrent scrypt verifications per API process with a finite waiting queue, and deployment-wide throttles by source and normalized username digest. Generic invalid-login responses do not disclose account existence. Web login/session JSON contains safe metadata, not the cookie bearer; native bearer delivery is a separate transport contract. MFA seeds use vetted AEAD with purpose-specific key derivation/AAD so a credential ciphertext cannot be substituted for a TOTP seed. Recovery authority follows the restricted flow above; new recovery codes require ordinary recent step-up. No user-directory search or password reset email service is introduced in beta.

Revocation never frees a remote identity for a new connection/owner. Reactivation verifies the same remote identity, keeps its stable connection_id, increments versions and inherits all unresolved intent/conflict/lease state; fresh execution remains blocked until that state is reconciled. Digest-key rotation must migrate existing identity mappings atomically/version-aware before new connections use the new key, so a different digest cannot bypass duplicate ownership protection.

## 7. Exchange capability matrix and research

| Capability | OKX | Binance Spot | Binance standard USD-M |
|---|---|---|---|
| Balances/market/open orders | Preserve existing supported scope | Beta read-only | Beta reads |
| Positions / leverage | Preserve existing supported modes | Not applicable | Beta reads; mode-specific actions |
| Position close/cancel | Preserve after tenant audit | Cancel/trade deferred; selling is not position close | One-way regular orders after demo gate |
| Existing SWAP strategies | Preserve | Unsupported | Deferred until every used metadata/risk/mutation capability passes |
| Hedge / conditional/algo | Preserve only current tested support | Spot order-list semantics separate | Explicit later capability plan |
| Cross-account close-all | Unsupported | Unsupported | Unsupported |

Official documentation consulted 2026-10-10 (refresh relevant endpoint contracts before implementation):

- [OKX v5 API](https://www.okx.com/docs-v5/en/): signed credentials include passphrase; derivatives quantity/metadata and position modes require native mapping; budgets vary by endpoint. Regional domain and live/demo routing must be explicit.
- [OKX lifecycle guide](https://www.okx.com/docs-v5/trick_en/): order-channel subscription needs initial snapshot; cancellation acknowledgments need eventual order-state evidence.
- [Binance USD-M general information](https://developers.binance.com/en/docs/products/derivatives-trading-usds-futures/general-info): request weight is IP-scoped, order count account-scoped; some 503 responses leave execution unknown and require reconciliation. Demo endpoints are documented separately.
- [Binance USD-M trade API](https://developers.binance.com/en/docs/catalog/core-trading-derivatives-trading-usd-s-m-futures/api/rest-api/trade): One-way/Hedge parameters differ; conditional algo orders are distinct from regular orders. `closePosition` on conditional orders is not an immediate market-close command.
- [Binance Spot filters](https://developers.binance.com/en/docs/products/spot/filters) and [USD-M market metadata](https://developers.binance.com/en/docs/catalog/core-trading-derivatives-trading-usd-s-m-futures/api/rest-api/market-data): use actual tick/step/notional filters, not display precision.
- [Binance Spot REST](https://developers.binance.com/en/docs/products/spot/rest-api): signed calls and timing/error handling are product-specific.
- [Spot user streams](https://developers.binance.com/en/docs/products/spot/user-data-stream), [USD-M user streams](https://developers.binance.com/en/docs/catalog/core-trading-derivatives-trading-usd-s-m-futures/api/rest-api/user-data-streams): subscription/renewal differ; a common stream abstraction must retain product-specific lifecycle.
- [Spot demo](https://developers.binance.com/en/docs/products/spot/demo-mode/general-info) and [Spot testnet reset behavior](https://github.com/binance/binance-spot-api-docs/blob/master/testnet/general-info.md): simulated environments are useful contract gates, not live-performance evidence.

Architecture choices are our proposals derived from these contracts. An adapter cannot implement Binance by translating OKX field names. No numeric exchange rate limit is frozen in the plan: load current documented metadata and response budgets, with conservative local limits and shared egress accounting.

## 8. Invariants, edge cases and failures

- INV-001: Owner comes from validated server session, never a client-supplied userId. All private ID lookups, pagination, conflicts and worker claims enforce it.
- INV-002: All commands remain tied to the prepared connection/product/environment and credential/permission version. Changing selected account cannot retarget a command.
- INV-003: Display cache, client state and stream event are not sufficient authorization/proof for a write or terminal result.
- INV-004: A database lease/fence and attempt marker protect API and background mutations. A lost lease blocks further calls; already sent requests are reconciled, never considered rolled back.
- INV-005: Decimal units, position mode and native order type are preserved. Unsupported modes fail before an exchange write.
- INV-006: No secrets in telemetry/logs/UI/browser persistence. Encryption key is separate from session and remote-identity keys.

| Edge/failure | Response / state | Allowed effects / prohibited effects |
|---|---|---|
| Cross-user ID/cursor/result | 404 | No upstream account call, no owner disclosure. |
| Switch/logout while request in flight | Ignore stale generation | No stale data or stale 401 affecting new scope. |
| Duplicate remote connection / revoke then relink | 409 generic conflict for a different owner; same-owner controlled reactivation | No new UUID bypass of old UNKNOWN intents, no owner disclosure or automatic tail resume. |
| Credential/mode/permission changes after prepare | 409 reprepare or 403 | Clear confirmation; never submit with old version. |
| Credential revocation during accepted write | REVOKING / reconciliation-required | Stop new commands, preserve ledger. Owner must resolve orders on exchange if keys no longer permit querying. |
| Trade timeout/crash-after-send | UNKNOWN / reconciliation due | Query ID/events; never blind retry or mark FAILED solely from timeout. |
| Cancel races with fill | Per-target FILLED/PARTIAL/CANCELED/UNKNOWN | Preserve fills/exposure; do not delete order based on ACK. |
| Capacity exceeded / upstream 429 | 429 + Retry-After, 503 busy if local admission | Bounded queue/backoff/jitter; do not starve safety reconciliation or send retry storm. |
| Session DB/vault unavailable | 503 fail closed | No auth fallback, no write. Existing displayed private data marked unavailable and controls disabled. |
| Partial portfolio source | complete=false, unavailable source entries | No fabricated zero or misleading complete aggregate. |
| Legacy ownership ambiguous | QUARANTINED | Never run/adopt orders automatically. |

## 9. RED/GREEN contracts

Execute each negative/boundary scenario before its success case at formal task checkpoints. Baseline failing assertions where new behavior is absent are recorded separately from a negative scenario that correctly rejects unsafe input.

| Pair | RED expected result | GREEN expected result |
|---|---|---|
| RED/GREEN-001 | Two users race one recovery/TOTP counter; at most one succeeds, no shared counter. Missing/wrong password plus recovery code fails; restricted recovery session cannot read exchange data or change credentials/trade. | Independent ordinary sessions; successful password+code recovery revokes old sessions, reenrolls TOTP and requires fresh ordinary login. |
| RED/GREEN-002 | B guesses A IDs → 404/zero A calls. Rotation invalidates old work. Revoke/relink with UNKNOWN intent cannot escape conflict/lease barriers or transfer owner. | A lists/uses owned connections; same-owner reactivation keeps stable ID/barriers and permits new work only after reconciliation. |
| RED/GREEN-003 | Same BTC across exchanges/products, invalid lot/notional, unsupported mode → distinct cache keys / no submit. | Known contract/base-unit fixtures and OKX regression preserve normalized values. |
| RED/GREEN-004 | Two execute requests, result poll during lease and crash after send → one marker/submission, UNKNOWN until proven. | One allowed prepare/execute reconciles to exchange-proven terminal per-target state. |
| RED/GREEN-005 | Delay A response and 401 past B selection; expire confirmation; deny capability → no leak/wrong action. | Login/connect/switch/read/confirm supported action with accessible context and logout clearing. |
| RED/GREEN-006 | Noisy account, 429, full queue, duplicate worker lease → bounded resources/fairness/no duplicates. | 100-user profile meets latency targets while preserving fresh write checks. |
| RED/GREEN-007 | Unmapped legacy rows/UNKNOWN job/rollback attempt after new writes → quarantine or stop, no replay/loss. | Mapped offline migration preserves ownership/counts/decimals; recovery drill reconstructs ledger. |

## 10. Migration, compatibility and rollout

1. Baseline counts/status histograms and a restore-tested backup are operator-produced without exposing secrets. Freeze new API/worker writes; reconcile or quarantine in-flight/UNKNOWN operations. No dual writer against the same exchange account.
2. Map the old account to an explicitly identified legacy owner/connection and verified remote identity. Fingerprints tied to the old session key are migration inputs, not new IDs. Preserve IDs/statuses/native orders/precision and side reservations; ambiguous rows remain quarantined.
3. Import into new PostgreSQL schema in an offline transaction/batches with manifest counts and referential checks. Old login sessions and confirmation tokens are revoked, not copied as live authority. Credentials are re-entered/imported by operator through approved vault flow, never copied from protected files by agents.
4. Read-only shadow comparison with synthetic fixtures; demo smoke; owner-only OKX canary; invited read-only users; gated USD-M One-way canary; broader beta only after isolation/performance/device/audit gates.
5. Kill switches separately pause new placements, connection trading and workers, while allowing safe reconciliation/read operations subject to permission. Pause stops unsent work; it does not cancel already placed exchange orders. User-visible status must reflect that distinction.

Rollback before new writes: stop services, restore previous code/store and explicitly revoke new sessions. Rollback after new writes: freeze, reconcile both ledgers and restore only from a recovery point including accepted new commands; never point old code blindly at an old SQLite backup. If state parity cannot be proven, remain read-only and forward-fix. Launch gates include backup/decryption restore, process restarts, clock skew, exchange unavailability and revocation drill.

## 11. Performance and measurement contract

Targets are proposed acceptance gates, not measured results. First record existing baseline with identical synthetic public/private payloads, then measure new single-process and multi-process topology. Record hardware, Python/Flutter versions, DB topology, warm/cold cache, connection count, RTT, upstream stub delay, API process count and foreground lifecycle.

Reference local profile: 4 vCPU / 8GB API+worker budget, separate PostgreSQL service; 100 concurrent users, 1,000 linked / 200 actively refreshed connections, 20 strategy accounts, 50 positions + 100 open orders/active account, 500-row UI scroll fixture. Synthetic upstream p50 100ms / p95 500ms; client RTT 100ms; 15-minute steady state plus 2-minute 500-user burst. Fake exchanges only for load; never load-test live trade endpoints. Report achieved ceilings if reference hardware is unavailable instead of claiming PASS.

| Metric | Proposed threshold |
|---|---|
| Warm private snapshot/list endpoint | p95 ≤250ms, p99 ≤750ms, excluding client RTT |
| Cold supported snapshot | p95 ≤1.5s in synthetic upstream profile; bounded partial/degraded response if dependency fails |
| App switch feedback / first correct cached display / fresh data | p95 ≤100ms / ≤300ms / ≤2s under reference profile; never old-account private display |
| Error/ownership/duplicate submit | <1% unexpected 5xx under admitted load; zero tenant leaks / duplicate submission attempts |
| Coalescing | 50 concurrent identical public-cache-miss reads distributed across four API processes create one deployment-owned fetch, using DB lease plus bounded persisted public snapshot. Private misses allow one flight per exact scope/resource/process, maximum four fetches across the four-process profile, subject to deployment-wide account/IP budgets. |
| Resource bound | Combined API/worker RSS ≤6GB on reference machine; queue/admission remain finite; no sustained upward RSS trend and ≤10% retained-memory increase after 100 switch cycles following GC/idle stabilization |
| UI scrolling | p95 frame work ≤16.7ms on declared 60Hz reference device at 500 rows; validate 1,000-row stress and record degradation |
| Fairness | Reconciliation ready work from an admitted healthy account scheduled within 5s p95; a slow/429 account cannot block healthy accounts indefinitely |

Initial budget proposal: 64 active account contexts/process, global maximum 200 active accounts enforced across processes; account LRU idle eviction at 60s; 4 bounded I/O slots/account, process I/O limit 32, account mutation slot 1; queue 100 jobs/account and 1,000 globally. Contexts with live claims cannot be evicted. Persist budgets/claims in PostgreSQL so multiple processes cannot multiply limits; do not mistake process-local cache/limit for deployment-wide behavior. Admission reserves at least 25% worker slots for reconciliation/cancel/risk-reducing work. Tune only from recorded benchmark evidence; strict safety limits are not overridden to hit latency targets.

Public refresh leases/snapshots use a bounded PostgreSQL table keyed by exchange/feed/product/instrument/query, latest value only with TTL/cleanup; lease loss invalidates publication. Public request waiters reuse that snapshot instead of each process refetching. Private single-flight remains process-local in beta, with its explicitly bounded amplification above; do not claim deployment-wide private deduplication. A shared private snapshot/push design is phase-next if measured budgets require it.

Adaptive client polling: visible prices 1–2s, visible positions/orders 3–5s, balance 10–15s; immediate coalesced refresh after actions; inactive/private background UI polling off. Connection/account freshness must be explicit. Preserve current quote maximum age 15s for display; safety preflight requires a fresh uncached observation for relevant account/mode/order and rechecks versions before send. Server strategy workers remain active when UI is closed.

Phase-next realtime option: server exchange WS multiplex + snapshot/reconcile and per-user push over approved runtime. Spot and USD-M subscription/renewal differ. Add only after polling benchmarks justify it, with gap/reconnect sequencing, finite buffers, latest-value coalescing and independent launch approval. Redis is not initially required; evaluate shared public cache/event fan-out only when process duplication demonstrably exhausts the upstream budget.

## 12. Security and user-owned setup actions

No current protected file contents or deployed settings are known. The following are proposed **new** setup surfaces under A-010, not edits to inspected files. Agents may document these actions; only the user/operator may create/apply them after approving implementation and service setup. Before execution, verify dependency compatibility/releases through official package documentation and present an exact lock/pin proposal. No external service is activated now.

| Action | Proposed target / location / content | Scope / reason / validation |
|---|---|---|
| External database/vault runtime inputs | New `backend/.env.multiuser`, one key per line: `MULTIUSER_DATABASE_URL=<SET_BY_USER>`, `CREDENTIAL_VAULT_KEY=<SET_BY_USER_32_BYTE_BASE64>`, `CREDENTIAL_VAULT_KEY_ID=v1`, `REMOTE_IDENTITY_KEY=<SET_BY_USER_32_BYTE_BASE64>`, `SESSION_SIGNING_KEY=<SET_BY_USER>`, `MULTIUSER_ENABLED=false`, `MULTIUSER_TRADE_ENABLED=false`. Loader is an implementation proposal; operators may inject equivalent process variables instead. | Local test/staging then production; keep keys distinct, protect backups and rotate key IDs. PostgreSQL owner/app roles use least privilege; encryption keys are outside DB backup. Integration verification blocked until provisioned. Start API/worker with these opaque inputs; health checks return only readiness, not values; run isolated DB/vault fixture and backup-restore checks. |
| Dependency setup | New user-owned `backend/requirements-multiuser.txt`, dependency identifiers `psycopg[binary]` and `cryptography`; exact compatible versions/hashes established at execution preflight before installation. No agent reads/creates this manifest. | Backend DB/AES-GCM; both are new proposed dependencies. Offline mocks/source checks can proceed, canonical runtime verification cannot pass without installed approved versions. Pin review is a readiness gate, not permission to choose arbitrary package versions. |
| Local integration test input | New user-owned `backend/.env.multiuser.test`, `MULTIUSER_TEST_DATABASE_URL=<SET_BY_USER_ISOLATED_TEST_DB>`. | Dedicated test DB with no production data; only this explicit test variable may authorize schema reset. Missing variable → BLOCKED, never silently use production/default DSN. |
| Runtime ingress / exchange permissions | Operator chooses deployment host and TLS/cookie trusted-origin/egress settings during release preflight; no existing target/path is inferred. Allowlisted supported regional domains and live/demo API routes are code contracts; keys granted read or required trade permissions, never withdrawals. | Infrastructure actions are outside this implementation approval. A separate exact deployment runbook with user-confirmed target paths is required before launch; missing facts block deployment, not this research plan. Verify wrong Origin/CSRF/region/permission rejects safely. |

Security tests must include IDOR, forged cursor, CSRF, login/invite rate limit, TOTP replay, vault associated-data tamper, key rotation, wrong region, secret log redaction, account revoke during execution and stale-session response fencing. Use only fabricated credentials in tests.

## 13. Traceability and planning completion

| Requirement | AC | Design | Plan/task | Behavioral pair |
|---|---|---|---|---|
| REQ-001 | AC-001 | §3–6,12 | P01 / T110 | 001 |
| REQ-002 | AC-002 | §4–6,8,12 | P01–P02 / T110–T111 | 002 |
| REQ-003 | AC-003 | §4,6–7 | P03–P04 / T112–T113 | 003 |
| REQ-004 | AC-004 | §6,8–10 | P02,P04,P06 / T111,T113,T115 | 004 |
| REQ-005 | AC-005 | brief, §5–6 | P05 / T114 | 005 |
| REQ-006 | AC-006 | §11 | P06–P07 / T115–T116 | 006 |
| REQ-007 | AC-007 | §10,12 | P07 / T116 | 007 |

Planning completion: requirements, proposed defaults, edge/failure semantics, RED/GREEN, migration and measurement defined. Product assumptions are visible in the decision ledger. Setup/runtime facts are expressly unverified and gate execution/launch as described. User approval, implementation, tests/builds, independent audit, performance measurements and rendered review are PENDING.
