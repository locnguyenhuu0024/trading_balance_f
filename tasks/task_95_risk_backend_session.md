# Task 95 — Risk and Android backend session ownership

Status: PASS
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6-luna
Target Effort: max
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: docs/agents/specs/2026-10-07-backend-data-gateway.md
Plan: docs/agents/plans/2026-10-07-backend-data-gateway.md
Requirements: REQ-008; Acceptance: AC-006
Predecessors: T94 PASS

## Allowed writes

lib/core/services/background_service.dart; lib/features/portfolio/data/risk/risk_repository.dart; lib/features/portfolio/data/risk/risk_market_repository.dart; lib/features/portfolio/presentation/providers/risk_dashboard_provider.dart; lib/features/portfolio/presentation/risk_dashboard_screen.dart; lib/features/portfolio/application/risk_monitor_runtime.dart; lib/features/portfolio/application/risk_monitor.dart only auth/read transport fences (no financial/state machine redesign); lib/features/portfolio/application/risk_monitor_bridge.dart only session channel integration if necessary; corresponding tests under test/features/portfolio/risk and test/core/services. Existing shared transport/session from T94 read-only; report interface insufficiency rather than patch outside surface.

No protected configuration/environment/manifests or secrets inspected/written; no external calls/Git changes/task/telemetry writes/children.

## Contract

Consume T94 BackendDataSession/factory. Foreground risk production providers use backend private/public clients, preserving request coordinator/caches, risk DTO normalization, interest page/cursor semantics and persistence. Replace exchange CredentialMutationBus listener with backend session changes so caches/inflight samples cannot outlive authorization. Keep stable monitor ownership rather than disposing/recreating it accidentally on ordinary session updates. Risk Start/Refresh remain visible and disabled with Vietnamese login/expiry reason in production; injected test bridge remains usable without real login.

Observed T94 export contract: BackendDataSession({TradeSession? initialSession}) has update(TradeSession?), generation, active current, synchronous ChangeNotifier notifications plus changes, matches(generation,expected), disposal fence. BackendDataClient({Dio? dio,String? baseUrl,onUnauthorized}) has get(path,{queryParameters,session,cancelToken}), isConfigured, and compatible Dio getter `dio`. For private direct Dio consumers, pass Options.extra[BackendDataClient.sessionExtraKey] = BackendDataSession. Compatible Dio preserves sanitized DioException status/message and BackendDataClient.errorCodeExtraKey; helper get normalizes to BackendDataException. Production RiskRepository can accept an optional backendSession alongside injected Dio, attach the extra in _get; offline legacy-Dio fixtures remain supported without enabling any production OKX fallback. Use existing provider exports after T94 PASS; verify actual source signatures before implementation.

Android service uses memory-only explicit session channel with monotonic generation, token/accountIdentifier/expiry input, sanitized acknowledgement containing generation/status only. Session handoff must be acknowledged before ownership Start/sample; no token in state/ack/handshake/log/notification. Replayed older generations rejected. On cleared/expired/401 session: fence pending samples immediately, clear private caches and stop/auth-block owner, with existing typed lifecycle behavior. Foreground adapter sends current session after handshake and updates/clears active service on session transitions; service without a handoff cannot request private data. Never read local OKX credentials or fallback to OKX; no new token persistence. Preserve exclusive owner arbitration, service death/reconnect safety, notifications and history.

Protocol details: add session-input/session-ack channel to RiskServiceOwnerController and handoffSession() to RiskServiceOwnerProxy. Validate payload/generation and immediately fence/replace memory session before the existing command queue can block it. Handshake/ack expose applied-generation watermark; recreated UI/proxy must allocate above it. Serialize pending handoffs; after acknowledgement recheck current foreground session before returning ownership/Start. Equal generation may only acknowledge identical already-applied state; older/conflicting payload is rejected. Existing invalidateCredentials command automatically restarts a running monitor, so do not use that command for logout/expiry/401: use immediate invalidateCredentials fence plus auth-stop without restart. Reconnect _lastStart must go through acknowledged active-session acquisition again. Add replay/proxy-recreation/delayed-capture/logout and token-free payload coverage.

Audit-derived state fencing: on foreground session changes, immediately publish existing typed sanitized stopped/unavailable state and suppress unauthorized service state. Stamp service state envelopes with non-secret appliedSessionGeneration; accept only matching acknowledged watermark and current foreground session context. A queued old-generation state must remain rejected even after the new acknowledgement. Apply managed-session gates in production while preserving explicitly injected no-session offline fixtures. No bearer in state/handshake/ack or financial state-machine redesign. Revalidate captured/current acknowledged authority immediately before dispatching queued sampling commands and after awaits.

## Verification

RED: missing/expired/unacknowledged or older handoff cannot start authorized reads; logout while service request in flight cannot publish; 401 does not become empty positions; acknowledgement/state payloads exclude token. Then GREEN: acknowledged current session uses backend-only factory, session refresh/logout fences correctly, single-owner/foreground/background and existing risk calculations pass. Fake channels and injected sessions, no device secrets/exchange calls. Meaningful baseline and focused V3 runtime/repository/monitor tests.
Buildability YES/Flutter app: `flutter build web --no-pub` after final edits. If available, `flutter build apk --debug --no-pub` additionally; distinguish source build errors from native toolchain/device limitations. Actual-device background check remains unverified without user device.

Return exact evidence/order/build/paths/external actions and telemetry risk-executor-95 E2 gpt-6-luna/max. No task-status mutation.
