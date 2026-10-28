# Plan: Binance Spot private reads over the WebSocket API (web)

Status: APPROVED (user, chat, 2026-10-28: "Duyệt"); T124 and T125 not yet executed
Date: 2026-10-28
Tier: L (new network transport on a credential-bearing path; security-sensitive)
Parent plan: `docs/agents/plans/2026-10-25-binance-direct-reads.md` (COMPLETE)
Related: `docs/agents/plans/2026-10-28-binance-failure-visibility.md` (COMPLETE)

## 1. Objective
In the Flutter web build, Binance Spot account, open-order and order-history reads work. Native builds, Binance Futures, OKX and all public Binance reads stay as they are.

## 2. Why (evidence, 2026-10-28)
- User screenshot of the web build: OKX and Binance Futures "OK", Binance Spot "Unavailable" with "Cannot reach Binance from this browser…".
- curl, no credentials: every Spot REST host (`api`, `api1..api4`, `api-gcp.binance.com`) answers the CORS preflight for `X-MBX-APIKEY` with `access-control-allow-origin: *` and `allow-methods: GET, HEAD, OPTIONS` but no `access-control-allow-headers`. `fapi.binance.com` returns `allow-headers: *`. Under the CORS rules a browser blocks signed Spot REST reads, which carry that header. Not yet reproduced inside Safari.
- Public Spot REST reads (`/time`, `/exchangeInfo`, `/ticker/24hr`) carry no custom header and send `access-control-allow-origin: *`, so they keep working.
- WebSocket connections are not subject to CORS. A handshake with `Origin: https://example.com` to `wss://ws-api.binance.com:443/ws-api/v3` returned `101 Switching Protocols`.
- Probe with a dummy key over that socket: `time` returned `status 200` with `rateLimits`; `account.status` with `apiKey` inside `params` was parsed (Binance validated the key format: `status 400`, error `-1100`). So the apiKey belongs in `params`, as in the official examples, despite a sentence in the account-requests page that says "headers".

## 3. Verified Binance facts (official docs, read 2026-10-28)
- Endpoint `wss://ws-api.binance.com:443/ws-api/v3`. Request frame `{"id","method","params"}`; response `{"id","status","result"|"error":{"code","msg"},"rateLimits":[…]}`. `id` must be unique among in-flight requests.
- Methods needed: `account.status` (weight 20; result has `balances[{asset,free,locked}]`), `openOrders.status` (weight 6 with `symbol`, 80 without), `allOrders` (weight 20; `symbol` required, `limit` max 1000, default 500).
- HMAC auth: `apiKey`, `timestamp`, optional `recvWindow` (default 5000, max 60000) and `signature` in `params`. Signature = hex HMAC-SHA256 of all params except `signature`, sorted by name, joined `name=value&…` (so `apiKey` is part of the signed payload, unlike REST). `session.logon` needs Ed25519 keys and is not usable with the app's HMAC keys.
- Limits: 300 connection attempts per 5 minutes per IP; connecting costs 2 weight; request weight is per IP and shared across connections. Status 429 and 418 carry `retryAfter`. A connection lives at most 24 hours; the server sends `serverShutdown` first; ping every 20 s (browsers answer automatically).
- `rateLimits` reports `REQUEST_WEIGHT` per MINUTE (observed limit 6000).
- Unverified: whether `result` for these three methods is field-for-field identical to the REST bodies the reader parses; needs a real read-only key. Unverified: behavior in iOS Safari.

## 4. Planning workstreams and route
One material workstream (Flutter client network layer). Fan-out Required: NO. Skip reason: `SINGLE_MATERIAL_WORKSTREAM`. Coordinator: Claude Sonnet 5.5 High (effective route not claimed). Executors: T124 E1 `gpt-6-luna`/`xhigh`; T125 E2 `gpt-6-luna`/`max`; explicit model and effort, inheritance forbidden, no Terra trial. No Sol advisory requested for this plan.

## 5. Decisions requiring user approval (proposed by coordinator)
- D-014: on web only, the three Spot signed reads (`/api/v3/account`, `/api/v3/openOrders`, `/api/v3/allOrders`) go through the WebSocket API methods `account.status`, `openOrders.status`, `allOrders`. Native builds keep REST. Futures and public reads keep REST on every platform. The reader and screens are not changed.
- D-015: lifecycle. One shared connection, opened lazily, closed after 60 s idle, closed on client dispose and on a credential generation change; opened again on demand. Per-request timeout 15 s, the same as REST. A closed or shutdown connection fails the in-flight requests with the existing `binance_network_error`; the only automatic retry stays the single `-1021` timestamp retry. The 2-weight connection cost counts against the Spot host budget.
- D-016: security fence. Fixed endpoint; method and parameter allowlist matching the REST route policy (`acceptsQuery`); the API key and signature live only inside the request frame; no frame, key, secret or signature in logs, errors or state; the same credential-generation, dispose and cancel checks as REST. Exposure of the key to the browser is unchanged from today's design.
- D-017: the web build keeps the T123 browser copy for any remaining no-response failure. No new user-visible copy.

## 6. Scope
- T124 allowed: new `lib/core/network/binance_spot_ws_transport.dart`; new `test/core/network/binance_spot_ws_transport_test.dart`.
- T125 allowed: `lib/core/network/binance_data_client.dart`; `test/core/network/binance_data_client_test.dart`.
Out of scope: protected configuration, `pubspec.yaml` (`web_socket_channel` and `crypto` are already dependencies), route registry weights, the reader and history scan, request coordinator internals, OKX, Futures, UI, deployment configuration, Git actions, live Binance checks.

## 7. DAG and tasks
`T124 -> T125 -> independent audit -> final V4 once + fresh build`. Serial: T125 depends on the T124 interface.

| Task | Content | Route | Build unit |
|---|---|---|---|
| T124 | `BinanceSpotWebSocketTransport`: injectable connector, lazy shared connection, id multiplexing, 15 s request timeout, 60 s idle close, `serverShutdown` and close handling, cancel and dispose fences, reply parsing (`status`, `result`, `error`, `rateLimits`) | E1 `gpt-6-luna`/`xhigh` | full Flutter app |
| T125 | `BinanceDataClient` takes an optional private-transport; maps the three Spot routes to WS methods; builds and signs the WS params (sorted, `apiKey` included); shapes the reply into the same `Response` the REST path produces (body, status, synthetic `x-mbx-used-weight-1m`, `retry-after`); feeds `observeResponse` and `_validateResponse`; wires the transport only when `kIsWeb` | E2 `gpt-6-luna`/`max` | full Flutter app |

RED-124: the transport file and its tests do not exist; the new test file fails to compile against the missing type. GREEN-124: a fake connector proves id multiplexing, concurrent requests, timeout, idle close and reconnect, server shutdown, cancel, dispose, error and `rateLimits` parsing, and that no frame text appears in thrown errors.
RED-125: with a fake transport injected, a signed Spot read still goes through Dio (the test asserts the transport was called; it was not). GREEN-125: the three routes call the transport with the exact method and params; the signature equals the HMAC of the literal sorted payload asserted in the test; Futures and public reads never touch the transport; with no transport the REST behavior and all existing tests are unchanged; a 429 and a 418 with `retryAfter` map to the existing codes; `-1021` retries once; `-2014`/`-2015` map to `binance_authentication_failed`; credential generation change or dispose mid-request is rejected; no key, secret or signature in any error.
Ceiling V3: `rtk flutter test --no-pub test/core/exchange test/core/network test/features/portfolio test/features/orders`. Build: `rtk flutter build web --no-pub` (after `flutter pub get` if `.dart_tool` is missing).
Task buildability: YES for both, no deferral.
Stop if: the interface cannot be added without changing the route registry, the reader or the coordinator, or scope must grow past section 6.

## 8. External verification (user-owned, not claimed)
Required after merge and not done by the executors: with a real read-only Binance API key on the deployed web build, confirm Spot balances, open orders and history load, the amounts match the Binance app, and the behavior in iOS Safari. AUD-style parity of the `result` bodies with REST is unverified until then.

## 9. Deferred, not approved
Native-wide use of the WebSocket API; `userDataStream` subscriptions; Ed25519 `session.logon`; a backend proxy.

## 10. Approval gate
- [x] scope bounded, write surfaces explicit and serial
- [x] RED then GREEN defined, build unit and command defined
- [x] no protected configuration content needed
- [x] user approves D-014..D-017 and this plan (chat, 2026-10-28)
- [x] task files and manifests created and `task_ledger.py plan` recorded after approval
- [ ] worktree clean before each dispatch (user-approved commits)
