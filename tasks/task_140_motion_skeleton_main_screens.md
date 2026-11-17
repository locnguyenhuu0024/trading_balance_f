# Task 140 — Skeleton loader, staggered entrance, main screens

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
Plan Steps: P02
Requirements: REQ-106, REQ-107, REQ-108
Decisions: D-024, D-025

## 1. Dispatch Compliance

The CCB dispatcher passes `--model gpt-6.1-terra` and `model_reasoning_effort=high` on your command line, and your prompt states the route. This is the explicit binding. `UNVERIFIABLE` is a valid state; do not stop for it.

Dispatch Route Status: pending
Requested Model: gpt-6.1-terra
Requested Effort: high

## 2. Objective

Create `AppSkeleton`, `AppEntranceScope`, `AppEntrance` and use them on Portfolio, Portfolio details, Orders, Market and BMAG.

Done when: AC-106 and AC-107 hold for these screens, RED-140 then GREEN-140 pass, buildability passes.

## 3. Preconditions

Predecessors: T139 = PASS (tokens `motionMedium`, `motionLong`, `motionStagger`, `motionEntranceOffset`, `motionEnter` exist). Clean checkout.

## 4. Allowed Scope

- `lib/core/widgets/app_motion.dart` (new)
- `lib/features/portfolio/presentation/portfolio_screen.dart`
- `lib/features/portfolio/presentation/portfolio_details_screen.dart`
- `lib/features/orders/presentation/orders_screen.dart`
- `lib/features/orders/presentation/widgets/responsive_order_grid.dart`
- `lib/features/market/presentation/market_screen.dart`
- `lib/features/fractal_tracker/presentation/fractal_screen.dart`
- `test/core/widgets/app_motion_test.dart` (new)
- `test/features/portfolio/portfolio_loading_test.dart`
- `test/features/orders/orders_binance_view_test.dart`
- `test/features/market/market_screen_test.dart`
- `test/features/fractal_tracker/fractal_screen_price_formatting_test.dart`

## 5. Forbidden Scope

- Protected configuration, `backend/`, Git state, any file not listed, new dependencies.
- No change to providers, refresh logic, `skipLoadingOnReload` values, texts, keys, error views, layout spacing.
- Small inline spinners (refresh button, row actions, dialogs, positions-action busy states) stay.

## 6. Executor Contract

1. `app_motion.dart` (import `app_page_transition.dart` for `AppPageTransitions.reduceMotion`, `app_theme.dart` for tokens/palette):
   - `AppSkeleton({Key? key = const Key('app-skeleton'), int itemCount = 6, double itemHeight = 72, String caption = 'Đang tải dữ liệu…', EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 8)})`. Stateful, one `AnimationController(duration: 1200 ms)..repeat()` unless reduced motion (then stopped at 0 and no shimmer). Build: `ListView(physics: const AlwaysScrollableScrollPhysics(), padding: padding)` so `RefreshIndicator` parents still work, children: caption `Semantics(liveRegion: true, child: Text(caption, style: 12, muted))`, 8 px, then `itemCount` placeholders separated by 8 px. Placeholder: `Container(height: itemHeight, decoration: surface fill, radius radiusMedium, border palette.border 1 px)` with padding 12 holding a `Row`: 32 px circle + `Expanded(Column)` of two bars (heights 10 and 8, widths 60 % and 35 %, radius 4, color `palette.border`). Wrap all placeholders in one `ExcludeSemantics` and one `ShaderMask(blendMode: BlendMode.srcATop)` driven by an `AnimatedBuilder` whose `LinearGradient` (colors: transparent, `palette.raised` at 0.55 opacity, transparent; stops 0.35/0.5/0.65) is shifted by `GradientTransform` translating x by `(controller.value * 2 - 1) * bounds.width`. React to reduced-motion changes in `didChangeDependencies`.
   - `AppEntranceScope({required Widget child})`: Stateful; records `startFrame = SchedulerBinding.instance.currentFrameTimeStamp` at its first build (frame time, not wall clock, so widget tests advance it with `pump`). Expose via an `InheritedWidget` `_AppEntranceScopeData(window: AppTokens.motionLong + AppTokens.motionStagger * 8, startFrame: Duration)`. Public `static bool canAnimate(BuildContext)` returns true when a scope exists and `currentFrameTimeStamp - startFrame <= window`.
   - `AppEntrance({required int index, required Widget child})`: Stateful. In `initState` decide once: `animate = index < 8 && scope allows && !reduceMotion` (read scope/MediaQuery in `didChangeDependencies` the first time only). If not animating: return `child` unchanged (no extra transition widgets). If animating: one `AnimationController` with duration `motionMedium + motionStagger * index`, started with `forward()` in the first `didChangeDependencies`; drive `t` with `CurvedAnimation(parent: controller, curve: Interval(delay / total, 1, curve: AppTokens.motionEnter))` where `delay = motionStagger * index`. No `Timer`/`Future.delayed`. Output: `FadeTransition` + `AnimatedBuilder` → `Transform.translate(offset: Offset(0, motionEntranceOffset * (1 - t)))`. Never wrap in `IgnorePointer`.
2. Screens — replace the full-screen first-load loader and wrap list items:
   - `portfolio_screen.dart`: both `Center(CircularProgressIndicator(color: textColor))` in the portfolio body (~L276–286) → `const AppSkeleton()`. In the data `ListView` (~L404) wrap the whole `ListView` in `AppEntranceScope`; wrap the asset summary in `AppEntrance(index: 0)` and each coin row from the inner `ListView.builder` in `AppEntrance(index: index + 1)`.
   - `portfolio_details_screen.dart`: loading (~L98) → `const AppSkeleton()`; data `ListView` (~L199) in `AppEntranceScope`, each top-level child in `AppEntrance(index: i)`.
   - `orders_screen.dart`: positions loading (~L410) and orders loading (~L544) → `const AppSkeleton(itemHeight: 112)`. Cards get the entrance via `ResponsiveOrderGrid` (next item). Any other non-grid card `ListView` on this screen with data cards: same scope + entrance pattern.
   - `responsive_order_grid.dart`: wrap the returned list in `AppEntranceScope`; wrap each child (1-column) or each row (multi-column, use the row index) in `AppEntrance(index: …)`. Same for the `cardExtent != null` branch.
   - `market_screen.dart`: loading (~L201) → `const AppSkeleton(itemHeight: 56)`; data `ListView.builder` in `AppEntranceScope`, rows in `AppEntrance(index: index)`.
   - `fractal_screen.dart`: loading (~L151) → `const AppSkeleton(caption: 'Đang tải dữ liệu fractal…', itemHeight: 96)`; data `ListView` (~L171) in `AppEntranceScope`, its top-level cards in `AppEntrance(index: i)`.
3. Tests:
   - New `app_motion_test.dart`:
     - RED-140a: `AppSkeleton` shows the caption, `itemCount` placeholders, and with `disableAnimations: true` no `ShaderMask` animation runs (`tester.hasRunningAnimations == false` after a pump).
     - RED-140b: inside `AppEntranceScope`, `AppEntrance(index: 0)` opacity < 1 after `pump(100 ms)` and == 1 after `pumpAndSettle`; `index: 9` has no `FadeTransition` ancestor of its child; reduced motion → no `FadeTransition`.
     - RED-140c: an `AppEntrance` mounted 1 s after its scope (pump 1 s, then rebuild with an extra item) is not animated.
     - RED-140d: `AppEntrance` without a scope renders the child directly.
   - `portfolio_loading_test.dart` ~L305: `CircularProgressIndicator` → `find.byType(AppSkeleton)` findsOneWidget.
   - `orders_binance_view_test.dart` ~L533: in the `loading` state expect `find.byType(AppSkeleton)` findsWidgets (replace the `CircularProgressIndicator` check only if it targeted the replaced loader).
   - `market_screen_test.dart`: add one check that the loading state shows `AppSkeleton` and the first row has an `AppEntrance` ancestor after data.
   - `fractal_screen_price_formatting_test.dart` ~L178: the caption text still exists (it is now the skeleton caption) — keep, add `find.byType(AppSkeleton)` findsOneWidget.
   - Any existing test that uses `pumpAndSettle` while a skeleton is visible will time out — switch those to `pump(const Duration(milliseconds: 300))`.

## 7. External Configuration / Environment Actions

None.

## 8. Tests

TEST-140-1..4 (RED-140a..d), TEST-140-5 (portfolio), TEST-140-6 (orders), TEST-140-7 (market), TEST-140-8 (fractal).

## 9. Mandatory Verification

### RED — RED-140
Command: `flutter test --no-pub test/core/widgets/app_motion_test.dart test/features/portfolio/portfolio_loading_test.dart test/features/orders/orders_binance_view_test.dart test/features/market/market_screen_test.dart test/features/fractal_tracker/fractal_screen_price_formatting_test.dart` with new tests on old `lib/`.
Expected: compile failure / failures because `AppSkeleton`, `AppEntrance` do not exist.

### GREEN — GREEN-140
Same command: all pass. Then V4 `flutter test --no-pub`: all pass.
Verification ceiling: V4.

### Task Buildability Gate
Required: YES
Command: `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub`
Expected: 0 errors; issue count not above the baseline recorded after T139.

### Verification environment
The executor sandbox cannot run Flutter. Write the complete change. Report `red`/`green` as `NOT_RUN` (RED then GREEN order named), `buildability` `BLOCKED` with that reason, `status` `COMPLETED`.

## 10. Stop Conditions

`BLOCKED` if a file outside §4 is needed, if a loader can only be replaced by changing provider/refresh behavior, or if the entrance would need `IgnorePointer`.

## 11. Execution Ledger
(coordinator fills)

## 12. Coordinator Audit
(coordinator fills)
