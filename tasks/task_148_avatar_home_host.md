# Task 148 — Floating avatar host on the home screen (native WebView + web iframe)

Status: VERIFYING
Agent Role: implementation_executor
Executor Class: E3
Target Model: gpt-6.2-sol
Target Effort: medium
Target Route: gpt-6.2-sol / medium
Routing Policy: EXECUTOR_ROUTING_POLICY.json v3 (OptCodex v1.5.1)
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-11-22-pnl-avatar-3d-design.md`
Plan: `docs/agents/plans/2026-11-22-pnl-avatar-3d.md`
Plan Steps: P03
Requirements: REQ-212, REQ-213 (Flutter side)
Acceptance Criteria: AC-213, AC-214, AC-215
Decisions: D-030, D-031, D-033, CD-1, CD-2, CD-4

## 1. Dispatch Compliance

The CCB dispatcher passes `--model gpt-6.2-sol` and `model_reasoning_effort=medium`. `UNVERIFIABLE` is a valid state.

Dispatch Route Status: PENDING
Requested Model: PENDING
Requested Effort: PENDING
Observed Effective Model: unavailable
Observed Effective Effort: unavailable

## 2. Objective

Show the avatar page (T146 assets) as a floating, draggable overlay on PortfolioScreen when `avatarEnabledProvider` (T147) is on, drive it with `avatarMoodFor` (T147), forward touches, pause on lifecycle, and hide on error.

Done when: RED-148 then GREEN-148 pass, buildability passes on web/Android/macOS/iOS-simulator, MAN-148 returned by the user.

## 3. Preconditions

Predecessors: T146 = PASS, T147 = PASS.
Resolved packages (from `.dart_tool/package_config.json`): `webview_flutter` 4.14.1, `web` 0.5.1 (`HTMLIFrameElement`, `EventStreamProviders` available). Model asset is `assets/avatar/avatar.vrm` (D-035).
User actions applied (spec §17): `webview_flutter: ^4.14.1`, `web: ^0.5.1`, `- assets/avatar/` in `pubspec.yaml`; `flutter pub get` succeeded. Coordinator confirms with the user (yes/no) before dispatch.

## 4. Allowed Scope

- `lib/features/avatar/presentation/avatar_renderer.dart` (new): `sealed class AvatarEvent` (`AvatarReady`, `AvatarModelLoaded`, `AvatarError(code,message)`, `AvatarInteraction(kind)`); `abstract class AvatarRenderer { Widget buildView(); void setMood(AvatarMood); void setPaused(bool); void setReducedMotion(bool); void sendPointer(String phase, double x, double y, int tMs); Stream<AvatarEvent> get events; void dispose(); }`; `typedef AvatarRendererFactory = AvatarRenderer Function();`; `final avatarRendererFactoryProvider = Provider<AvatarRendererFactory>((ref) => createPlatformAvatarRenderer);` with conditional import `avatar_renderer_native.dart` / `if (dart.library.js_interop) avatar_renderer_web.dart`; `encodeAvatarMessage(Map)` / `decodeAvatarEvent(Object?)` (unknown/malformed → null) shared by both.
- `lib/features/avatar/presentation/avatar_renderer_native.dart` (new): `WebViewController` with `JavaScriptMode.unrestricted`, `setBackgroundColor(Colors.transparent)` in try/catch, JavaScriptChannel `AvatarChannel`, `loadFlutterAsset('assets/avatar/index.html')`; queue outgoing messages until `ready`; on `ready` send `setReducedMotion`, latest `setMood`, then `loadModelChunk` from `rootBundle.load('assets/avatar/avatar.vrm')` in 512 KiB raw slices base64-encoded; outgoing via `runJavaScript('window.avatar.receive(${jsonEncode(jsonString)})')`; view = `IgnorePointer(child: WebViewWidget(...))`.
- `lib/features/avatar/presentation/avatar_renderer_web.dart` (new): `dart:ui_web` `platformViewRegistry.registerViewFactory` with unique viewType per instance; `package:web` `HTMLIFrameElement` src `assets/assets/avatar/index.html`, style `border:0;width:100%;height:100%;background:transparent;pointer-events:none` (no `allowTransparency`: obsolete IE-only attribute, absent from package:web; transparency comes from the transparent iframe and page backgrounds, verified in T146 audit); outgoing `iframe.contentWindow.postMessage(jsify(map), window.location.origin)` after `ready`; incoming via `web.EventStreamProviders.messageEvent.forTarget(web.window)` (package:web 0.5.1 has no `window.onMessage`) filtered by `origin == web.window.location.origin` and `source == iframe.contentWindow`; event `data` converted with `dartify()`; view = `HtmlElementView(viewType: ...)`.
- `lib/features/avatar/presentation/floating_avatar.dart` (new): `ConsumerStatefulWidget FloatingAvatar({required AvatarMood mood})`; creates renderer once in `initState` via factory provider; `didUpdateWidget` sends `setMood` only on change; `WidgetsBindingObserver` → `setPaused(state != resumed)`; `MediaQuery.disableAnimations` → `setReducedMotion` on change; `LayoutBuilder` + `Positioned` with offset state (default bottom-right 16 px), size 160×220 (×0.8 when `MediaQuery.size.width < 360`), clamp on drag; `GestureDetector`: `onLongPressStart/MoveUpdate/End` move widget (not forwarded); `Listener` `onPointerDown/Move/Up/Cancel` forward local CSS px + ms timestamp, moves throttled to ≥ 33 ms apart, suppressed while long-press drag active; events: `AvatarModelLoaded` → `AnimatedOpacity` 0→1 (250 ms, instant when reduced motion); `AvatarError` → hide (render `SizedBox.shrink`) for the widget's lifetime; `AvatarInteraction` → `HapticFeedback.lightImpact()`; `Semantics(label: 'Nhân vật 3D', image: true)`; dispose renderer and observer.
- `lib/features/portfolio/presentation/portfolio_screen.dart`: move the existing headline computation (~L340-402) unchanged into a private helper returning the values `_buildPortfolioData` needs (it keeps calling the helper; no numeric change); in `build`: `enabled = ref.watch(avatarEnabledProvider)`; `ratio = data present && no error ? helper(...).ratio : null`; `mood = avatarMoodFor(ratio, hidden: isBalanceHidden)`; wrap the `Column` under `NavigationContentFrame` in `Stack(children: [Column(...), if (enabled) FloatingAvatar(key: const ValueKey('home-avatar'), mood: mood)])`.
- Tests (new): `test/features/avatar/floating_avatar_test.dart`, `test/features/portfolio/portfolio_avatar_test.dart` using a `FakeAvatarRenderer` (records calls, exposes a `StreamController<AvatarEvent>`, view `SizedBox(key: Key('avatar-fake'))`) via `avatarRendererFactoryProvider` override; reuse override sets from `portfolio_loading_test.dart`.

## 5. Forbidden Scope

Protected files — no read/write (including `web/index.html`, plists, manifests, gradle). No change to `assets/avatar/**`, `tools/avatar/**` (T146), T147 files, PnL math, navigation shell. No new dependencies beyond the two the user added.

## 6. Executor Contract

Steps in §4 order. Invariants: INV-210, INV-211, INV-212. Edges: EDGE-211..EDGE-219.

## 7. External Configuration / Environment Actions

Planned (user-owned, must be applied before dispatch): spec §17 items 1–3. Blocks verification until applied: YES.

## 8. Tests

- TEST-148: off → no renderer; mood wiring; hidden/loading/error → neutral; refresh no recreate; lifecycle pause; clamp; error hides; interaction haptic; pointer forward; codec rejects malformed.

## 9. Mandatory Verification

### RED — RED-148
Command: `flutter test --no-pub test/features/avatar/floating_avatar_test.dart test/features/portfolio/portfolio_avatar_test.dart --plain-name "RED"`
Expected: setting off → factory call count 0 and no `avatar-fake`; portfolio loading → last mood neutral; error state → neutral; hidden with ratio 6 → neutral; three 5 s refresh ticks → factory count 1 and `setMood` count unchanged; `decodeAvatarEvent('{"v":2}')` and non-JSON → null; `AvatarError` → `avatar-fake` removed.
Status: PENDING

### GREEN — GREEN-148
Command: same files, `--plain-name "GREEN"`
Expected: setting on, payload with headline ratio 6% → exactly one `setMood(strongHappy)`; toggling hide → `setMood(neutral)`; `AppLifecycleState.paused` → `setPaused(true)`, `resumed` → `setPaused(false)`; long-press drag by (−5000, −5000) → widget fully inside frame; `AvatarInteraction('pat')` → `SystemChannels.platform` receives `HapticFeedback.vibrate` call; tap → forwarded `down` then `up`.
Status: PENDING

Executor sandbox cannot run Flutter: write complete code, report RED/GREEN `NOT_RUN`, buildability `BLOCKED` with reason. Coordinator runs on host.
Verification ceiling: V2.

### Task Buildability Gate
Required: YES
Affected build unit: Flutter app, all four targets
Command: `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub && flutter build apk --debug --no-pub && flutter build macos --debug --no-pub && flutter build ios --simulator --debug --no-pub`
Result: PENDING

### External Verification — MAN-148
Required: YES (user-run, after coordinator audit)
Checklist per platform (iOS simulator, Android device, macOS, Chrome): enable setting → avatar appears bottom-right with transparent background; PnL ≥ +5% (or simulated) happy bounce, ≤ −5% sad head down; hide balance → neutral; pat head, stroke head, poke body, swipe → reactions; drag moves and stays above nav bar; background app 30 s and return → still animating; disable setting → avatar gone; Android low-end: 2 min smooth, device not hot.
Evidence back: per platform PASS/FAIL + one-line note.
Blocks completion of AC-214/AC-215 (manual): YES.

## 10. Stop Conditions

User pubspec actions not confirmed → BLOCKED. A platform API in §4 does not exist in the installed package versions → BLOCKED with evidence (no workaround outside scope).

## 11. Execution Ledger

- [ ] route confirmed explicit
- [ ] implement §4
- [ ] tests
- [ ] report

## 12. Coordinator Audit

Verdict: PENDING

## 13. Coordinator decision after attempt 1 (BLOCKED, no files changed)

Attempt `149c5272…` correctly stopped: `HTMLIFrameElement.allowTransparency` does not exist in package:web 0.5.1. Contract §4 updated to drop it. Re-dispatch with the same scope and route.
