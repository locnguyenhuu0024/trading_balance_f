# Task 125 — Route Binance Spot private reads through the WebSocket transport on web

Status: READY (T124 must be PASS and committed first)
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6-luna
Target Effort: max
Target Route: gpt-6-luna / max
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Plan: `docs/agents/plans/2026-10-28-binance-spot-websocket-reads.md`
Plan Steps: 125
Acceptance Criteria: Spot signed reads use the transport when one is configured, everything else is unchanged

## 1. Dispatch Compliance
Spawn an `implementation_executor` with both model `gpt-6-luna` and effort `max` supplied explicitly. No inherited route.
Dispatch Route Status: PENDING
Requested Model: gpt-6-luna
Requested Effort: max
Observed Effective Model: unavailable
Observed Effective Effort: unavailable

## 2. Objective
`BinanceDataClient` gains an optional `BinanceSpotPrivateTransport? spotPrivateTransport` (T124 interface). When it is non-null and the route is a Spot signed route, the client sends through the transport instead of Dio:
- Method map (exact): `/api/v3/account` -> `account.status`; `/api/v3/openOrders` -> `openOrders.status`; `/api/v3/allOrders` -> `allOrders`.
- Params: the canonical query already validated by `acceptsQuery`, plus `apiKey`, `recvWindow` (5000) and `timestamp` (same server-offset time source as REST). `signature` = lower-case hex HMAC-SHA256 with the secret over all params except `signature`, sorted by name, joined `name=value&name=value`. `apiKey` is part of the signed payload.
- The reply is shaped into the same `Response` the REST path produces: `data` = `result` on success, or the map `{code, msg}` on error; `statusCode` = reply `status`; a synthetic header `x-mbx-used-weight-1m` from the `REQUEST_WEIGHT`/`MINUTE` `rateLimits` entry; `retry-after` from `retryAfter`. It then goes through the existing `observeResponse` and `_validateResponse`, so 429, 418, `-1021` (one retry), `-2014`/`-2015` and the other codes map exactly as for REST.
- Transport failures map to existing codes: `timeout` -> `binance_timeout`, `network` -> `binance_network_error`, `cancelled` and `closed` -> `request_cancelled`.
- Credential generation fences, dispose and cancel behave as for REST. A credential generation change or `dispose` calls `close()`/`dispose()` on the transport. The client never closes a transport it was not given... except that `binanceDataClientProvider` creates a `BinanceSpotWebSocketTransport` only when `kIsWeb` is true and disposes it with the client.
- The 2-weight connection cost is not modelled separately; the request weight stays `route.weightFor(query)`.
- With `spotPrivateTransport == null` (native and all existing tests) behavior is byte-for-byte as today.
- Futures routes and all public routes never use the transport.

## 3. Preconditions
Predecessors: T124 = PASS and committed. `lib/core/network/binance_spot_ws_transport.dart` exists and defines `BinanceSpotPrivateTransport`, `BinanceWsReply` and `BinanceSpotTransportException`; read it, do not edit it (it is outside the allowed write scope on purpose). Do not treat its absence from the allowed files as a missing predecessor. Decisions D-014..D-017 approved.

## 4. Allowed Scope
Source: `lib/core/network/binance_data_client.dart`.
Tests: `test/core/network/binance_data_client_test.dart`.

## 5. Forbidden Scope
No protected configuration/environment files read or modified. No `pubspec.yaml`, lock or build change. No reader, history scan, route registry, request coordinator, UI, OKX or Futures change. No logging of request frames, keys, secrets or signatures. No Git state changes. Do not edit canonical plans/tasks or telemetry. No live network calls to Binance in tests.

## 6. Executor Contract
1. Write the tests first with a fake `BinanceSpotPrivateTransport` and show them failing.
2. Implement the smallest complete change in the one source file.
3. Keep all existing tests green without weakening them.
4. The signature test must assert a literal payload string built by hand and an HMAC computed independently in the test from fixed key, secret and timestamp.
5. Leave the Dio `X-MBX-APIKEY` header path unchanged for non-transport requests.

## 7. External Configuration / Environment Actions
None. Blocks verification: NO. Live Binance behavior and iOS Safari stay unverified and must not be claimed.

## 8. Tests
Cover: the three routes call the transport with the exact method and params; signature equals the HMAC of the literal sorted payload; Futures and public reads never call the transport; transport null keeps REST (existing tests); success body equals `result`; synthetic weight header reaches the coordinator; 429 and 418 with `retryAfter` map to `binance_rate_limited` and `binance_ip_banned`; `-1021` retries once with a time resync; `-2014`/`-2015` map to `binance_authentication_failed`; transport `timeout`, `network`, `cancelled`, `closed` map as above; credential change before or during a request is rejected and the transport is closed; dispose closes it; sentinel key, secret and signature never appear in thrown errors or `toString()`.

## 9. Mandatory Verification
### RED — RED-125
Command: `rtk flutter test --no-pub test/core/network/binance_data_client_test.dart`
Expected before the change: the new transport cases fail because the client does not accept or use a transport (compile failure or the transport is never called); existing cases pass or are unaffected.
Actual: PENDING
Status: PENDING

### GREEN — GREEN-125
Same command. Expected: all pass.
Actual: PENDING
Status: PENDING

Regression (V3): `rtk flutter test --no-pub test/core/exchange test/core/network test/features/portfolio test/features/orders`

### Task Buildability Gate
Required: YES
Affected canonical build unit: full Flutter application
Exact secret-free build command: `rtk flutter build web --no-pub`
Executed after the last task-local change: PENDING
Result: PENDING

### External Verification
Required: NO

## 10. Stop Conditions
Return `BLOCKED` if T124's interface is missing, if the change needs files outside section 4, or if REST behavior with no transport cannot be kept identical.

## 11. Execution Ledger
- [ ] dispatch role, class, model and effort match; no inherited route
- [ ] RED observed before the change
- [ ] GREEN observed
- [ ] V3 regression run
- [ ] task build after last change
- [ ] compact executor report returned
- [ ] no protected content read or modified

## 12. Coordinator Audit
PENDING
