# Task 124 — Binance Spot WebSocket transport

Status: READY (dispatch pending; worktree must be clean)
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Target Route: gpt-6-luna / xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Plan: `docs/agents/plans/2026-10-28-binance-spot-websocket-reads.md`
Plan Steps: 124
Acceptance Criteria: a standalone, injectable transport that sends one request frame and returns the parsed reply

## 1. Dispatch Compliance
Spawn an `implementation_executor` with both model `gpt-6-luna` and effort `xhigh` supplied explicitly. No inherited route.
Dispatch Route Status: PENDING
Requested Model: gpt-6-luna
Requested Effort: xhigh
Observed Effective Model: unavailable
Observed Effective Effort: unavailable

## 2. Objective
Create `BinanceSpotWebSocketTransport` for `wss://ws-api.binance.com:443/ws-api/v3` (fixed; not configurable by callers except through the injectable connector used by tests). It does not sign, does not know credentials and does not know routes.

Required public surface (names are the contract T125 depends on):
- `abstract interface class BinanceSpotPrivateTransport { Future<BinanceWsReply> send({required String method, required Map<String, Object> params, CancelToken? cancelToken}); void close(); void dispose(); }` (`CancelToken` from `package:dio/dio.dart`).
- `class BinanceWsReply { final int status; final Object? result; final int? errorCode; final String? errorMessage; final List<Map<String, Object?>> rateLimits; final String? retryAfter; }` where `retryAfter` is the reply's `retryAfter` value as a string (or null).
- `class BinanceSpotTransportException implements Exception { final BinanceSpotTransportFailure kind; }` with `enum BinanceSpotTransportFailure { timeout, network, cancelled, closed }`. `toString()` and any message carry no frame text.
- `class BinanceSpotWebSocketTransport implements BinanceSpotPrivateTransport` with a constructor taking an optional connector (a function from `Uri` to an object exposing a stream of text frames, a sink and close), `requestTimeout` (default 15 s) and `idleTimeout` (default 60 s). The default connector uses `WebSocketChannel.connect` from `web_socket_channel`.

Behavior: lazy shared connection opened on first `send`; unique request ids (concurrent requests must not collide); replies are matched by id; per-request timeout gives `timeout`; unparsable frames are ignored and never echoed; an unsolicited `serverShutdown` event or a closed connection fails in-flight requests with `network` (or `closed` after `dispose`) and the next `send` reconnects; idle close after `idleTimeout` with no in-flight request; `close()` fails in-flight requests with `closed` and allows a later reconnect; `dispose()` is final; a cancelled token fails that request with `cancelled` and ignores its late reply; a failed connect gives `network`. Replies with `status` outside 200..299 are returned, not thrown; the caller decides.

## 3. Preconditions
Predecessors: none. Decisions D-014..D-016 approved. `web_socket_channel` is already a dependency.

## 4. Allowed Scope
Source: new `lib/core/network/binance_spot_ws_transport.dart`.
Tests: new `test/core/network/binance_spot_ws_transport_test.dart`.

## 5. Forbidden Scope
No protected configuration/environment files read or modified. No `pubspec.yaml`, lock or build change. No reader, history scan, route registry, request coordinator, UI, OKX or Futures change. No logging of request frames, keys, secrets or signatures. No Git state changes. Do not edit canonical plans/tasks or telemetry. No live network calls to Binance in tests.

## 6. Executor Contract
1. Write the tests first and show them failing (the transport type does not exist).
2. Implement the smallest complete transport.
3. Use fake connectors and `fakeAsync` or short durations in tests; no real sockets.
4. Never log or throw frame content.

## 7. External Configuration / Environment Actions
None. Blocks verification: NO. Live Binance behavior and iOS Safari stay unverified and must not be claimed.

## 8. Tests
Cover: reply parsing for success, error (`code`, `msg`) and `rateLimits`; `retryAfter` for 429 and 418; two concurrent requests answered out of order; timeout; idle close then reconnect on the next send; `serverShutdown`; connection closed with requests in flight; connect failure; cancel before and after the reply; dispose; `close()` then reuse; unparsable and unknown-id frames ignored; exception and reply text never contain the params values (use sentinel key, signature and body text).

## 9. Mandatory Verification
### RED — RED-124
Command: `rtk flutter test --no-pub test/core/network/binance_spot_ws_transport_test.dart`
Expected before the change: compile failure because `binance_spot_ws_transport.dart` does not exist.
Actual: PENDING
Status: PENDING

### GREEN — GREEN-124
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
Return `BLOCKED` if the surface above cannot be implemented with `web_socket_channel` alone, or if files outside section 4 must change.

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
