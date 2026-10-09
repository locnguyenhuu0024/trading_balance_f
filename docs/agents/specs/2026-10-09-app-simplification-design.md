# Design Specification: Remove Risk, remember trade password, manual refresh

Status: IMPLEMENTED_AND_VERIFIED_LOCALLY
Date: 2026-10-09
Tier: L
Decision Ledger: docs/agents/decisions/2026-10-09-app-simplification-decisions.md

## Objective and observed state

Remove the Risk feature completely, simplify trade sign-in, and expose manual refresh on every remaining page. Existing Risk startup runs from main.dart through core/services/background_service.dart. Risk navigation has stable ID `risk` and screen index 5. The request coordinator in portfolio/data/risk is also used by ticker polling, Support and Strategy. TradeSessionControls opens a password/TOTP dialog and authenticates after it closes. SecureStorageHelper already uses FlutterSecureStorage; WebStorageHelper overrides legacy OKX credentials with preferences, so new trade password methods must remain on secure storage. Existing pages have uneven manual refresh coverage.

Evidence: main.dart; core/navigation/{main_navigation_shell,navigation_destination_data,navigation_preferences}.dart; core/security/secure_storage_helper.dart; portfolio/application/risk_monitor_runtime.dart; orders/presentation/widgets/trade_account_controls.dart; page files listed in the plan. Configuration contents are not evidence.

## Requirements and acceptance

REQ-001 / AC-001: Risk destination, screens, monitoring, notifications, background service startup and feature-only implementation/tests are removed. A shutdown-only compatibility entrypoint at the old background_service.dart URI stops persisted native callbacks; native startup retires an existing service and disables autostart without starting any service or requesting notifications. Stored navigation containing `risk` normalizes safely. Other stable destination identities/indexes and trade safety checks remain valid. Shared request scheduling moves unchanged to core/network/request_coordinator.dart with neutral Request* names; its useful behavioral tests move to core/network.

REQ-002 / AC-002: Trade login has checkbox `Lưu mật khẩu trên thiết bị này`, default off without a saved password. Saved password loads obscured and editable; OTP is always empty, exactly six ASCII digits, accepts paste and leading zero. Keep dialog open during server authentication with loading, duplicate-submit prevention, show/hide password, inline generic errors and scrollable content. Clear OTP after each submitted attempt. Store password only after successful login with the same current session. No automatic authentication or OTP generation/persistence.

REQ-003 / AC-003: Use existing FlutterSecureStorage on mobile and web, never plaintext SharedPreferences for this new password. Scope by normalized validated backend endpoint via an optional TradeApi capability implemented by TradeApiClient; do not require unrelated fake clients to implement it. For clients without scope capability, remembering is unavailable with safe feedback. Unchecking removes the saved password immediately, including cancellation/failing later authentication; deletion failure is visible and cannot falsely report removal. Failed checked login does not replace an existing password. Successful login plus save failure stays logged in and reports generic save failure. Logout retains explicitly remembered password; opt-out deletes it. Storage operations never print secrets.

REQ-004 / AC-004: All seven remaining main pages plus PortfolioDetails and API/trade settings expose visible manual refresh labeled/tooltip `Làm mới dữ liệu`. Reuse existing buttons on BMAG, Support, Strategy; no duplicates. Refresh only page data/current Orders tab, preserve filters, drafts, privacy, preferences and navigation. Await relevant data and prevent duplicate pending refresh. Disabled controls remain visible when unauthenticated/unavailable. Refresh never executes trade mutations or automatic login. Settings refreshes exchange rate only; API settings refreshes saved summary while retaining editing mode/controllers and fencing stale completions.

## Invariants, edges and failure semantics

INV-001: Backend gateway/session fencing and prepare/execute/cancel confirmation flows remain unchanged. Strategy failureRiskProbability is unrelated and preserved.
INV-002: No password/OTP in logs, UI errors, telemetry or plaintext preferences. Password prefill is masked. Async storage/auth completions cannot overwrite disposed views, changed endpoint or newer session.
INV-003: No protected configuration/manifests/locks/build settings are read or edited; unused dependency declarations may remain inert. No deployment or live exchange action.

Edges: stale saved navigation drops only removed IDs; missing/corrupt/failed storage reads allow manual sign-in; failed deletes block a false opt-out acknowledgment; wrong OTP makes no auth request; failed auth clears submitted OTP for retry; canceled dialog saves nothing; refresh can recover errors without losing page state. Session or endpoint change during auth/save discards stale completion.

## Contracts and design

Existing backend auth/API/schema stays unchanged. Add only local storage methods and optional endpoint-scope capability. Store only password under endpoint-scoped secure key; absence means unchecked. Use repo Material controls, AppTokens, 48px icon targets, checkbox single hit area, field validation/focus, keyboard submit and native paste. F1 bounded extension; no aesthetic redesign or new dependencies.

## RED then GREEN

RED-001: legacy navigation with risk cannot expose Risk; obsolete monitor/bootstrap cannot run. GREEN-001: all remaining pages navigate and shared scheduler still coalesces/backoffs without behavioral changes.
RED-002: invalid OTP sends zero requests; unchecked delete and checked failed auth never save; duplicate pending submit sends once; stale/save/delete/read failures give safe outcomes. GREEN-002: checked successful auth saves, reopen prefills masked password with empty OTP; unchecked login removes password and still logs in.
RED-003: pending double refresh/signed-out actions cannot duplicate/authorize work; settings/API drafts and Orders selection survive refresh. GREEN-003: each remaining page button invokes intended read/provider once and updates rendered data.

Formal verification order RED before GREEN for each task; expected results above are independent of implementation.

## Rollout, rollback and security

Ship branch through normal user-owned deployment after local audit. No schema migration. Existing Risk stored records become unused; no destructive bulk storage deletion. Rollback is reverting scoped commits on request; new password key can be removed via opt-out before rollback. Build web locally; Android device validation remains separately bounded by available SDK. External configuration actions: none required for runtime removal/local web behavior. Protected dependency declarations are left intact.

## Traceability

REQ-001 -> AC-001 -> P01/T100 -> RED-001/GREEN-001.
REQ-002/003 -> AC-002/003 -> P02/T101 -> RED-002/GREEN-002.
REQ-004 -> AC-004 -> P03/T102 -> RED-003/GREEN-003.

Completion: every task audited PASS, ordered behavioral evidence, fresh final web build, unexplained changes absent, configuration boundary respected, commit and push verified.
