# Task 139 — Motion tokens, page/tab transitions and startup screen

Status: APPROVED
Agent Role: implementation_executor
Executor Class: E3
Target Model: gpt-6.1-terra
Target Effort: high
Target Route: gpt-6.1-terra / high
Routing Policy: EXECUTOR_ROUTING_POLICY.json v2 (OptCodex v1.4.0)
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Plan: `docs/agents/plans/2026-11-17-motion-polish.md`
Spec: `docs/agents/specs/2026-11-17-motion-polish-design.md`
Plan Steps: P01
Requirements: REQ-101..REQ-105
Decisions: D-022, D-023

## 1. Dispatch Compliance

The CCB dispatcher passes `--model gpt-6.1-terra` and `model_reasoning_effort=high` on your command line, and your prompt states the route. This is the explicit binding. `UNVERIFIABLE` is a valid state; do not stop for it.

Dispatch Route Status: pending
Requested Model: gpt-6.1-terra
Requested Effort: high

## 2. Objective

Add motion tokens, change the non-Apple route transition to fade + 12 px rise, change the tab transition to fade + scale, give the startup screen a code-drawn brand mark with a cross-fade into the app, and reuse the startup view while biometrics are checked.

Done when: AC-101..AC-105 hold, RED-139 then GREEN-139 pass, and the buildability gate passes.

## 3. Preconditions

Predecessors: T138 = PASS (`a84d1a3`). Clean checkout.

## 4. Allowed Scope

- `lib/core/theme/app_theme.dart` (the `AppTokens` class only)
- `lib/core/widgets/app_page_transition.dart`
- `lib/core/widgets/app_startup.dart`
- `lib/main.dart` (only the `_isChecking` branch of `_BiometricAuthScreenState.build` and the import it needs)
- `test/core/navigation/app_page_transition_test.dart`
- `test/core/widgets/app_startup_test.dart`
- `test/core/widgets/app_startup_preview_test.dart`

## 5. Forbidden Scope

- Protected configuration (`pubspec.yaml`, lockfiles, `android/`, `ios/`, `web/`, `macos/`), `backend/`, Git state.
- Any file not listed. No new dependency. No asset use.
- Do not change palette colors, startup initialization logic, retry logic, error copy, biometric auth logic.

## 6. Executor Contract

1. `AppTokens` — add (keep existing values):
   ```dart
   static const motionMedium = Duration(milliseconds: 280);
   static const motionLong = Duration(milliseconds: 420);
   static const motionStagger = Duration(milliseconds: 40);
   static const motionEntranceOffset = 12.0;
   static const Curve motionEnter = Curves.easeOutCubic;
   static const Curve motionExit = Curves.easeInCubic;
   ```
2. `AppPageTransitions`: `routeDuration = AppTokens.motionMedium`. `destinationDuration` stays `motionStandard` (220 ms; was `motionShort`).
3. `AppFadePageTransitionsBuilder.buildTransitions`: keep the reduced-motion / `settledAnimation` / `IgnorePointer` / `ExcludeSemantics` logic and all existing keys. Inside the `FadeTransition(key: app-route-fade)`, wrap the child in an `AnimatedBuilder` → `Transform.translate(key: const Key('app-route-slide'), offset: Offset(0, AppTokens.motionEntranceOffset * (1 - curved.value)))`, where `curved = enteringAnimation.drive(CurveTween(curve: AppTokens.motionEnter))`. Opacity uses the same curve. Use `CurvedAnimation`/`CurveTween` with `reverseCurve`/same curve — reverse must look like the forward played backward.
4. `AppCupertinoPageTransitionsBuilder`: unchanged.
5. `AppDestinationTransition`: curve → `AppTokens.motionEnter`; add `ScaleTransition(key: const Key('app-destination-scale'), scale: Tween(begin: 0.985, end: 1.0).animate(curved))` inside the existing `FadeTransition`. Keep the generation/post-frame/reduced-motion logic exactly.
6. `app_startup.dart`:
   - New public `AppBrandMark({double size = 64})`: `Container` size×size, `BorderRadius.circular(AppTokens.radiusLarge)`, color `palette.ink`; centered `Row` of 3 bars (width `size*0.11`, heights `size*0.22`, `size*0.36`, `size*0.5`, gap `size*0.08`, bottom aligned, radius 2) in `palette.onStrong`. Wrap in `ExcludeSemantics`.
   - `AppStartupStatusView` becomes a `StatefulWidget` (same constructor). Layout top→bottom: `AppBrandMark(key: Key('app-startup-brand-mark'))`, 20 px, title "Crypto Portfolio" (18, w600, ink), 6 px, status line, then:
     - loading: 16 px gap + `SizedBox(width: 120, height: 2)` `ClipRRect(radius 1)` `LinearProgressIndicator(color: ink, backgroundColor: palette.border)`, inside the existing `Semantics(key: app-startup-progress-semantics, label: 'Đang khởi tạo ứng dụng', liveRegion: true)` + `ExcludeSemantics`;
     - status line text: loading "Đang khởi tạo ứng dụng…" (13, muted); failure "Chưa thể khởi tạo ứng dụng." (16, w600, ink) + existing "Vui lòng thử lại." + retry `FilledButton` (unchanged).
     - The mark is shown in both states. The old 32 px `Icons.error_outline` is removed; on failure a 20 px `Icons.error_outline` (warning color) sits inline before the failure text in a `Row(mainAxisSize: MainAxisSize.min)`.
   - Entrance (not reduced motion): one `AnimationController(duration: AppTokens.motionLong)` started in `initState` (post-frame not needed). Mark: fade 0→1 + scale 0.92→1 over interval 0.0–1.0 with `motionEnter`. Text block + progress: fade over `Interval(0.3, 1.0, curve: motionEnter)`. Reduced motion (`AppPageTransitions.reduceMotion(MediaQuery.of(context))`): controller value = 1, no progress bar.
   - Hand-off in `_AppStartupState.build`: return an `AnimatedSwitcher(key: const Key('app-startup-handoff'), duration: AppTokens.motionMedium, switchInCurve: AppTokens.motionEnter, switchOutCurve: AppTokens.motionExit, layoutBuilder: (current, previous) => Stack(alignment: Alignment.center, children: [...previous, if (current != null) current]))`. Child is `KeyedSubtree(key: const ValueKey('app'), child: widget.builder(...))` when `_hasValue`, else `KeyedSubtree(key: const ValueKey('startup'), child: <existing startup MaterialApp>)`. The startup `MaterialApp` keeps its theme setup.
   - Reduced motion at the root: there is no `MediaQuery` above. Compute `final data = MediaQueryData.fromView(View.of(context)); final reduce = data.disableAnimations || data.accessibleNavigation;` and use `Duration.zero` when `reduce`.
   - The app builder must still be called for exactly one app subtree (existing test "delayed initialization hands off to the app exactly once").
7. `main.dart` `BiometricAuthScreen`: replace `CircularProgressIndicator(color: palette.ink)` in the `_isChecking` branch with `const AppStartupStatusView(isLoading: true)` returned as the whole body (no `Scaffold` nesting issue: `AppStartupStatusView` already has a `Scaffold`; return it directly from `build` when `_isChecking`). Keep everything else.
8. Tests:
   - `app_page_transition_test.dart`: add `RED-139a`: push a route on `TargetPlatform.android`, `pump(140 ms)`; the `Transform` under `Key('app-route-slide')` has `0 < dy < 12`; after `pumpAndSettle` dy == 0. Add a reduced-motion variant where dy == 0 right after the first pump. Add `RED-139b`: tab switch, mid-way the `ScaleTransition` keyed `app-destination-scale` has `0.985 <= scale < 1`. Update any existing duration-based expectations to the new durations; do not delete tests.
   - `app_startup_test.dart`: `RED-139c`: startup pending shows `Key('app-startup-brand-mark')`, the text "Crypto Portfolio" and a `LinearProgressIndicator`; `RED-139d`: after initialization completes, mid cross-fade (`pump(140 ms)`) both startup text and the app child exist, after `pumpAndSettle` only the app. Keep the existing reduced-motion test, updated: no `LinearProgressIndicator`, brand mark present, semantics label unchanged.
   - `app_startup_preview_test.dart`: line ~138 update: reduced motion → `find.byType(LinearProgressIndicator)` findsNothing and brand mark findsOneWidget (replace the `hourglass_empty` expectation). Keep golden/capture calls as they are.
   - Loading-state tests must use `pump(duration)` not `pumpAndSettle` while the indeterminate bar is visible (it never settles).

## 7. External Configuration / Environment Actions

None.

## 8. Tests

TEST-139-1 (RED-139a), TEST-139-2 (RED-139b), TEST-139-3 (RED-139c), TEST-139-4 (RED-139d), plus the existing tests in the three files.

## 9. Mandatory Verification

### RED — RED-139
Command: `flutter test --no-pub test/core/navigation/app_page_transition_test.dart test/core/widgets/app_startup_test.dart test/core/widgets/app_startup_preview_test.dart` with the new tests on the old `lib/`.
Expected: RED-139a..d fail (no `app-route-slide`, no `app-destination-scale`, no brand mark, no cross-fade).

### GREEN — GREEN-139
Same command after the change: all pass. Then V4 `flutter test --no-pub`: all pass.
Verification ceiling: V4 (shared transition code affects every screen test).

### Task Buildability Gate
Required: YES
Command: `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub`
Expected: 0 errors; issue count not above the current baseline (156).

### Verification environment
The executor sandbox cannot run `flutter test` or compile. Write the complete change. Report `red` and `green` as `NOT_RUN` with the tests named in RED then GREEN order. Set `buildability` to `BLOCKED` with that reason, and `status` to `COMPLETED`. The coordinator runs RED, GREEN and the gate on the host.

## 10. Stop Conditions

Return `BLOCKED` if: a file outside §4 is needed; reduced motion cannot be honored at the root without `MediaQuery`; an existing test would have to be deleted or weakened beyond the updates named in §6.8.

## 11. Execution Ledger
(coordinator fills)

## 12. Coordinator Audit
(coordinator fills)
