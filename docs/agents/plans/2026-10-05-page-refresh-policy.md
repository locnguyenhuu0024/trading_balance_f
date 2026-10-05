# Page refresh policy

Status: COMPLETE
Workflow: WF-20261005-REFRESH-007
Authorization: User authorized autonomous planning, implementation, commit and push.

## Contract

Only Portfolio (including its details), Fractal Tracker and Orders retain automatic live updates. Portfolio uses a one-second tick with a loading guard. Preserve existing Orders ALL-filter throttling and Fractal request guards. Other pages load on entry, explicit refresh, changed inputs or completed user actions only.

Strategy removes one-second quote and twenty-second status timers and automatic lifecycle reloads. Each explicit/initial list load takes one bounded quote snapshot per eligible distinct instrument; await this within the coalesced load future. Preserve session ownership, exact quote validation, out-of-order protection and freshness checks. Visibility changes may mark old metrics stale but never send requests. Manual and action-driven reloads remain. Remove obsolete polling retries rather than suppressing manual retry.

Support/Resistance removes its minute timer, retaining initial/selection/manual loads. Market uses its fetched ticker snapshot and no live-price subscription. Make shared live-price and WebSocket providers auto-dispose and cancel the stream listener so Portfolio connections cease when their consumers leave. Guard Portfolio deferred subscriptions after disposal.

Independent opt-in risk monitoring and backend strategy execution workers are not page refresh loops and retain their safety behavior. No backend, configuration, dependency, deployment or SDK changes. No claim that all upstream 429 errors are eliminated.

## Planning and dispatch

One material frontend request-lifecycle workstream, including UI, providers and local socket ownership. Backend/runtime worker is non-material unchanged. Fan-out Required: NO; required/actual reasoning agents: 0/1; compliance EXCEPTION, SINGLE_MATERIAL_WORKSTREAM. R2-REFRESH-PLAN-001 explicitly dispatched read-only gpt-6.1-sol/medium; evidence adopted. Coordinator route fixed by runtime, effective route unavailable. Child binding EXPLICIT, inheritance FORBIDDEN, effective route UNVERIFIABLE. Runtime has no safe child close/release primitive.

T92 implementation_executor E1, gpt-6-luna/xhigh EXPLICIT. Allowed writes: lib/features/strategy/presentation/providers/strategy_dashboard_provider.dart; lib/features/support_resistance/presentation/support_resistance_screen.dart; lib/features/market/presentation/market_screen.dart; lib/features/market/presentation/providers/market_provider.dart; lib/core/network/okx_websocket_service.dart; lib/features/portfolio/presentation/portfolio_screen.dart; related tests under test/features/strategy, test/features/support_resistance, test/features/market, test/features/portfolio. Do not change protected files. Add meaningful request-count/lifecycle tests, observe RED before implementation, then GREEN. Test prolonged idle and hide/resume without requests, manual refresh and quote validity, support-resistance idle/manual refresh, Market no socket, Portfolio loading guard and socket disposal.

Coordinator audits explicit diffs, collects independent read-only audit, runs full Flutter tests and release web build, then commits/pushes. External VPS deployment remains user-owned.

## Verification

T92 completed with formal RED before source changes and focused GREEN: 71 tests passed. Regression coverage includes a virtual minute without Strategy quote requests, no lifecycle reload, coalesced awaited snapshots, multi-instrument session revocation, Support/Resistance idle/manual requests, Market idle/manual requests without sockets, Portfolio pending-request suppression and listener-driven socket disposal. Independent R2-REFRESH-AUDIT-001 final verdict PASS after explicit 401 termination was added; coordinator adopted the audit and checked allowlisted diffs.

Full Flutter suite: 492 tests passed. Release web build succeeded. Targeted six-source-file analysis reported one existing unused-catch warning and one existing const-literal info, confirmed in HEAD; no new diagnostics. Explicit diff whitespace check passed. Backend behavior and protected configuration remain unchanged. Deploy updated build/web to the existing Nginx frontend directory to activate this policy; no VPS deployment performed. Git integration branch: feat/page-refresh-policy.
