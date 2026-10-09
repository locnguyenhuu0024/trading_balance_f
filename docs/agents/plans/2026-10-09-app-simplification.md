# Implementation Plan: App simplification

Status: COMPLETED
Date: 2026-10-09
Tier: L
Specification: docs/agents/specs/2026-10-09-app-simplification-design.md
Decision Ledger: docs/agents/decisions/2026-10-09-app-simplification-decisions.md

## Planning coverage and authorization

Coordinator C1, runtime-fixed current route; no effective-route claim. Independent material workstreams: Risk lifecycle/shared scheduler and frontend auth/refresh/security. Each dispatched R2 gpt-6.1-sol/medium explicitly, logical runs R2-RISK and R2-UI. Required/actual reasoning agents: 2/2. Results collected/reconciled; Fan-out Required YES, Compliance PASS. Backend is nonmaterial: no Risk endpoint exists, strategy risk scoring retained. Effective child routes unavailable/UNVERIFIABLE; parent inheritance forbidden.

User authorized execution after plan and autonomous choices, branch, commit/push in the originating request. Present plan then execute without a redundant approval gate.

Frontend F1: reuse Material/AppTokens, pinned Vercel web-design-guidelines skill/checklist loaded. Brief N/A, no open visual choice; review changed controls/forms/a11y/responsiveness. Actual screenshot status reported honestly; no React skills.

## Dependency graph and task decomposition

P01/T100 -> P02/T101 -> P03/T102 -> P04/T103 -> P05/T104 -> independent final audit -> final checks -> authorized commit -> push.
Serial writers avoid shared SecureStorageHelper, main/navigation test and Settings surfaces and Flutter build cache conflicts. Three independently auditable contracts with distinct RED/GREEN; each boundary builds.

### P01 — remove Risk (T100, E1 Luna/xhigh)

Delete portfolio Risk-only application, data/risk (after moving coordinator), domain/risk, presentation Risk files/widgets/provider and Risk-only tests. Replace core/services/background_service.dart with shutdown-only legacy callback and native retirement helper: stop old running service, configure no autostart/no boot autostart, callback only stopSelf; never start a service, create monitor, request permissions or notifications. Main calls retirement instead of initialization, catches generic failure. Remove bus and notifications, Settings background-service probes, navigation risk ID/destination/case. Preserve other indexes (Support 6, Strategy 7). Relocate scheduler and tests to core/network with neutral Request* names; update all source/test imports and shared consumers. Update navigation/settings/crypto-icon fixtures only as required by removal. No backend, Kotlin or protected manifest changes.

### P02 — password and login form (T101, E1 Luna/xhigh)

Scope: core/security/secure_storage_helper.dart; orders/data/trade_api_client.dart; orders/presentation/widgets/trade_account_controls.dart; targeted test/core/security and test/features/orders auth tests. Implement exact AC-002/003. Optional capability exposes normalized endpoint only, maintaining existing TradeApi fake compatibility. Add no dependencies or WebStorageHelper plaintext override.

### P03 — every-page refresh (T102, E1 Luna/xhigh)

Scope: presentation pages portfolio_screen.dart, portfolio_details_screen.dart, orders_screen.dart, market_screen.dart, fractal_screen.dart, support_resistance_screen.dart, strategy_screen.dart, settings_screen.dart, settings_trade_access_page.dart; targeted page tests. Small shared refresh widget allowed at core/widgets/manual_refresh_button.dart if it eliminates repeated async guard behavior. Reuse handlers; current Orders tab reads correct private provider. API summary refresh preserves controller/mode and generation-fences completion; settings dynamic-only refresh. No Risk page remains.

## Verification and buildability

Each task: V1 formal named RED then named GREEN, V2/V3 affected files/groups. Inner loop narrow diagnostics. Invalidated scenarios only rerun after subsequent edits. Each task runs `flutter build web --no-pub` after last executable edit. Final whole Flutter suite once justified by global navigation/startup/shared scheduler changes, `flutter analyze --no-pub`, fresh `flutter build web --no-pub`. Backend unchanged, no repeated backend suite needed. Known prior Android SDK absence is rechecked only if native build needed; no device/background claims from web evidence. Native tools consume configuration opaquely and must not regenerate protected manifests/locks. RTK first for eligible output, exact raw source/diff evidence exception.

RED/GREEN scenarios and independently expected outcomes: specification §RED then GREEN. New meaningful behavioral tests required for remembering/failure races and each refresh surface; migrate shared scheduler tests rather than delete coverage. Inapplicable feature-only tests removed with feature.

External configuration actions none. Rollout/rollback per specification. Risks: stale async login/save/session; stale API summary; shared scheduler accidental drift; navigation fixtures retaining removed IDs. Detect with behavioral tests and independent diff/consumer audit. Final scope check path-first, protected paths metadata only. Only coordinator updates task checklists/telemetry and commits/pushes.

AUD-100-001: existing gateway-normalized HTTP 429 bypassed scheduler status recognition; preserve intended rate-limit contract by recognizing BackendDataException statusCode/retryAfter in the migrated coordinator. Use existing parsing/backoff, retain non-429/Dio semantics, add focused queued-request/cooldown regression tests. Bounded affected-path remediation, no backend API/config change.

P04/T103 follows T102 before final integration (same E1 Luna/xhigh route, serialized writer): fix AUD-101-001 initial unavailable/pending storage must not block manual authentication. No save/delete until storage available or explicit opt-out; truthful saved-state unavailable message. Preserve actual opt-out deletion/error gate. This implements existing failed-read fallback requirement; no scope or backend change. New RED-004 combined read/delete failure and pending-read fallback before GREEN-004 normal remembered auth, fresh web build. T101 historical checkpoint remains immutable; final integration blocked until T103 PASS.

P05/T104 final analyzer cleanup AUD-104-001: mechanical E0 Luna/high implementation of existing invalidate+await read idiom on seven new unused_result sites, optional newly introduced null-aware/const diagnostics only. No unrelated lint cleanup; reuse fullsuite504 evidence with affected page checks and fresh task/final builds.
