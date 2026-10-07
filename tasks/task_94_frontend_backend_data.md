# Task 94 — Foreground backend transport and shared ticker polling

Status: PASS
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6-luna
Target Effort: max
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: docs/agents/specs/2026-10-07-backend-data-gateway.md
Plan: docs/agents/plans/2026-10-07-backend-data-gateway.md
Requirements: REQ-006..007; Acceptance: AC-004..005
Predecessors: none; frozen API registry permits independent implementation/testing

Dispatch Route Status: UNVERIFIABLE
Requested Model: gpt-6-luna
Requested Effort: max
Observed Effective Model/Effort: unavailable

## Allowed writes

lib/core/network/backend_data_client.dart (new); lib/core/network/backend_data_session.dart (new); lib/core/network/okx_websocket_service.dart (compatibility class may retain name but no direct socket); lib/features/orders/data/trade_api_client.dart; lib/features/orders/presentation/providers/trade_session_provider.dart; lib/features/orders/data/order_repository.dart; lib/features/orders/presentation/providers/order_provider.dart; lib/features/orders/presentation/orders_screen.dart; lib/features/portfolio/data/portfolio_repository.dart; lib/features/portfolio/presentation/providers/portfolio_provider.dart; lib/features/portfolio/presentation/portfolio_screen.dart; lib/features/market/presentation/market_screen.dart; lib/features/market/presentation/providers/market_provider.dart; lib/features/fractal_tracker/presentation/providers/fractal_provider.dart; lib/features/strategy/data/strategy_market_repository.dart; lib/features/support_resistance/data/market_repository.dart; lib/features/support_resistance/presentation/support_resistance_screen.dart; corresponding tests under test/core/network,test/features/orders,test/features/portfolio,test/features/market,test/features/fractal_tracker,test/features/strategy,test/features/support_resistance. No Risk repository/runtime/background edits (T95).

No protected config/manifests/dio_client.dart/operational settings read/write; no external services, telemetry/task changes, Git mutation or children. Presentation/repository/client Dart implementation is non-protected behavior; reuse existing compile definition via tradeApiBaseUrl, do not add settings.

Additional explicit source surface: lib/features/support_resistance/presentation/providers/watchlist_provider.dart. Its production repository factory constructs a direct OKX Dio and must use the same backend factory. This is part of REQ-006, not an additional feature.

Authorized extension D8, REQ-010/AC-008: lib/features/settings/presentation/settings_screen.dart only vndExchangeRateProvider and necessary import; corresponding rate provider tests. This is presentation behavior source, not operational configuration. Public backend currency/usdt-vnd response supplies positive finite rate string; preserve existing local 25400 fallback and currency math. No other settings/credential controls/state changes.

## Contract

Create reusable backend Dio factory: validate same HTTPS constraints as TradeApiClient, redirect denial, browser credentials adapter, explicit legacy-path-to-registry mapping `/api/v5/x` -> `v1/data/x` preserving backend base path; reject unknown/absolute routes and exchange headers. Inject fake Dio adapter/seams for tests. Preserve existing DTO APIs where useful so financial tests still exercise their calculations. Production provider wiring must use factory, never OKX fallback.

Provide `BackendDataSession` shared injectable memory state with token/accountIdentifier/expiresAt/generation; update/clear only on semantic session changes, expose synchronous session-change notification plus Stream<void> `changes`, and reject inactive sessions/results from earlier generations. Riverpod provider observes tradeSessionProvider; avoid circular imports by putting session state/provider wiring in separate files as needed within allowed paths. Session class must support construction outside Riverpod for T95 isolate. Its exported contract: update(TradeSession?), generation, current active session getter, changes, dispose. private Dio requests take this object, on 401 expire only matching generation and current foreground controller, reject old responses even if transport succeeds. Do not log/persist bearer. Private view providers watch backend session identity/loading state and clear on login/logout/expiry. Public requests work without session. Vietnamese missing/expired-auth reasons are visible; keep account controls accessible.

Use backend ALL read aggregation in production OrderRepository without frontend multi-type network fan-out; preserve ordering and SPOT empty-position behavior. Preserve normalized trade-position/action path; stop legacy fallback on unauthenticated positions. One public polling ticker service replaces OKX WS API: active subscription union, GET market/quotes batches <=100 ids, 1-second cadence, overlap and generation guards, disposal cancellation, bounded retry/backoff and failures clear/mark prices stale. Preserve existing selected-screen automatic refresh and ALL five-tick policy; no new Strategy/Market/SupportResistance idle requests. Do not poll until subscribed. Public catalog/candle/history clients preserve queries/calculations and existing request coordinator.

## Verification

RED: no/expired session sends zero private requests; logout midflight discards data; insecure/unconfigured base or absolute/unknown route rejects; subscription disposal stops polls; upstream error does not publish stale current prices. Execute negative cases before GREEN.
GREEN: all factory/provider production clients hit backend URLs with compatible payloads; same-key polls share bounded work; ALL uses one request; public no-login reads, base-path/browser auth and financial/fractal/candle parity pass. Meaningful failing baseline before implementation when feasible; do not weaken existing tests, adapt fixtures to new backend contract.
Focused V3 Flutter tests for changed consumers; no full suite per task. Buildability YES/Flutter app: `flutter build web --no-pub` after final executable edits. Native service integration is successor T95, and task must already compile independently.

Return exact ordered evidence/commands/exits/counts, changed paths, build status, exported T95 session/factory interface, external actions, telemetry logical frontend-executor-94 E2 gpt-6-luna/max; effective unavailable if unexposed. Do not mark status.

## Bounded review corrections

Resolve AUD94-1..3 in docs/agents/audits/2026-10-07-backend-data-gateway-review.md: per-batch cancellation/disposal/generation fences, independent 15-second upstream-timestamp quote expiry, and final adapter-boundary destination/route/redirect/header validation for raw Dio and later interceptor mutation. Same source surface/route; rerun affected negative RED before GREEN and build after final fix.
