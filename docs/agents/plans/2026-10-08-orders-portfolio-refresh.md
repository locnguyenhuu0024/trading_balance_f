# Orders and Portfolio refresh plan

Status: COMPLETE
Date: 2026-10-08
Tier: M
Specification: docs/agents/specs/2026-10-08-orders-portfolio-refresh.md

## Scope and P01
Implement REQ/AC001-004 in one compile-complete task T98. DAG: T98 -> coordinator audit -> final build.
Allowed production surfaces: lib/core/network/foreground_read_gate.dart (new); lib/core/network/backend_data_client.dart (optional retry metadata and HTTP mapping only); lib/features/orders/data/trade_api_client.dart (optional exception metadata and GET response mapping only); lib/features/orders/data/order_repository.dart; lib/features/portfolio/data/portfolio_repository.dart; lib/features/orders/presentation/providers/order_provider.dart; lib/features/orders/presentation/providers/trade_session_provider.dart (tradePositionsProvider only plus gate provider integration); lib/features/portfolio/presentation/providers/portfolio_provider.dart; lib/features/orders/presentation/orders_screen.dart; lib/features/portfolio/presentation/portfolio_screen.dart.
Allowed tests: test/core/network/foreground_read_gate_test.dart (new); test/core/network/backend_data_client_test.dart; test/features/orders/trade_api_retry_test.dart (new); test/features/orders/orders_screen_refresh_test.dart; test/features/orders/order_repository_all_test.dart; test/features/portfolio/portfolio_dual_currency_screen_test.dart; test/features/portfolio/portfolio_loading_test.dart (new).
Forbidden: backend changes, generated model changes, dependencies, protected configuration/environment access or writes, deployment, Git mutations, unrelated UI redesign.

## Planning workstreams
| Workstream | Material | Independent | Requested route | Logical run | Result |
|---|---|---|---|---|---|
| Request scheduling and backend read evidence | YES | YES | R2/gpt-6.1-sol/medium | R2-refresh-001 | COMPLETE/USED |
| Portfolio loading and recovery UI | YES | YES | R1/gpt-6.1-sol/low | R1-loading-001 | COMPLETE/USED |
Fan-out Required: YES. Required Reasoning Agents:2. Actual Reasoning Agents:2. Fan-out Compliance:PASS. Skip Reason:N/A.
Coordinator synthesis: client scheduling mitigates the identified backend amplification without changing identity/security semantics; loading only applies while work is pending. Effective child routes unavailable; explicit dispatch bindings UNVERIFIABLE. Coordinator C1 intended route; runtime-fixed route not overridden or inferred. Child close/release primitive unavailable; completed results collected, no further child turns planned.

## Execution and verification
1. Preserve typed status/Retry-After for GET reads; add session-scoped coalescing/cooldown gate.
2. Integrate gated foreground reads, selective authentication watches and5s timers.
3. Add Portfolio no-data pending-state spinner guard.
4. Add request-count, lifecycle,429/session/loading regressions; preserve existing financial/action assertions.
Formal RED001 negatives precede GREEN001 successful data/recovery checks. Focused cases -> relevant files V2; V3 only for changed shared GET transport regression surfaces. Full suite not required absent new broad regression evidence.
Task buildability: YES, Flutter web application, `flutter build web --no-pub`, after final executable edit.
Final fresh repository build: `flutter build web --no-pub`; unchanged backend verification may reuse observed prior evidence, no backend build changes. Tests/builds consume configuration opaquely; no inspection. Build/environment failures remain BLOCKED; source failures get delegated remediation.
External verification/configuration actions: none. No production-rate-limit elimination claim without observed production evidence.

## Dispatch and approval
T98 implementation_executor E1, gpt-6-luna/xhigh, EXPLICIT, parent inheritance FORBIDDEN. Requested/effective route recorded at dispatch. Coordinator alone writes planning/task status and telemetry.
- [x] Evidence and workstream results reconciled
- [x] Contract, failure cases and write boundaries defined
- [x] RED/GREEN and canonical build command defined
- [x] User authorizes this presented plan — 2026-10-08: Thực hiện tasks đi
- [x] T98 and independent audit PASS
- [x] Fresh final build PASS

## Completion evidence
T98 PASS; coordinator source/test/scope reconciliation PASS.56 focused tests passed. Fresh final Flutter web build exit0 (25.6s) and backend compileall exit0. No protected repository configuration/environment content accessed or modified; no external configuration action, deployment or Git history mutation. Existing wasm dry-run and CupertinoIcons warnings remain non-blocking for the standard web build. Runtime close/release operation unavailable; all child terminal results collected.
