# Design Specification: Motion polish — page transitions, startup, loading and card entrance

Status: APPROVED
Date: 2026-11-17
Tier: M
Plan ID: PLAN-20261117-motion-polish
Domain: mobile (Flutter; also runs on web/desktop)
Branch: `codex/multi-platform-view-only` (user: "Làm trên branch hiện tại")

## 1. Objective

Make motion in the app feel deliberate and professional:
- page transitions (opening a sub-page, switching tabs);
- the first-launch startup screen and its hand-off to the app;
- loading states and the way cards and rows appear on every screen.

Non-goals: new colors, new layouts, new dependencies, native splash files, behavior changes.

## 2. Current State

### Observed Facts

- OBS-101: `lib/core/widgets/app_page_transition.dart` — Android/Web/Windows/Linux pushed routes use only a fade (`AppTokens.motionStandard` = 220 ms, `Curves.easeOut`). iOS/macOS use `CupertinoPageTransitionsBuilder`. Tab switches use `AppDestinationTransition`: fade only, 140 ms. Both respect reduced motion (`disableAnimations || accessibleNavigation`) and block input/semantics while a route is covered or entering.
- OBS-102: `lib/core/widgets/app_startup.dart` — the startup screen is a plain 32 px `CircularProgressIndicator` + "Đang khởi tạo ứng dụng…". The hand-off to the app is an instant swap (no transition).
- OBS-103: `lib/main.dart` `BiometricAuthScreen` — while checking it shows a bare centered spinner, so a biometric user sees: startup spinner → a different spinner → app.
- OBS-104: `assets/icon/app_icon.png` exists but is not bundled (absent from `build/web/assets`). Using it needs a `pubspec.yaml` edit (protected, user-owned).
- OBS-105: Full-screen first-load spinners: `portfolio_screen.dart` (two, ~L276–286), `portfolio_details_screen.dart` (~L98), `orders_screen.dart` (positions ~L410, orders ~L544), `market_screen.dart` (~L201), `fractal_screen.dart` (`FormPendingStatus` ~L151), `connections_screen.dart` (~L26), `support_resistance_screen.dart` (instrument picker ~L504), `strategy_screen.dart` (`FormPendingStatus` ~L162). Small inline spinners (buttons, refresh button, dialogs, `scope_switch_gate.dart`) are fine and stay.
- OBS-106: Cards/rows appear instantly with no entrance motion on any screen.
- OBS-107: `AppTokens` has only `motionShort` (140 ms) and `motionStandard` (220 ms). No shared curves.
- OBS-108: UI is monochrome (`AppPalette`: ink, muted, surface, raised, border, background).
- OBS-109: Tests that depend on the current loaders: `test/features/portfolio/portfolio_loading_test.dart:305`, `test/features/orders/orders_binance_view_test.dart:533`, `test/core/widgets/app_startup_preview_test.dart:138`, `test/core/widgets/app_startup_test.dart`, `test/features/fractal_tracker/fractal_screen_price_formatting_test.dart:178`.

## 3. Scope

### In Scope
Shared motion tokens; route and tab transitions; startup screen + hand-off; biometric checking state; a skeleton loader and a staggered entrance widget applied to every screen listed in OBS-105 plus Tools, Settings cards and the Strategy / Support-resistance card lists.

### Out of Scope
Native launch files (`launch_background.xml`, `LaunchScreen.storyboard`, `web/index.html`), `pubspec.yaml`, chart animations, dialogs and bottom sheets, numbers counting up, Hero animations.

## 4. Clarifications and Decisions (user, chat, 2026-11-17)

- D-022 Transitions: "Fade + trượt nhẹ". Pushed routes (non-Apple): fade + rise 12 px. Tab switch: fade + scale 0.985 → 1. iOS/macOS keep the native Cupertino slide and back-swipe.
- D-023 Startup: "Logo vẽ bằng code". A monochrome mark drawn in Flutter + app name, short entrance, thin progress bar, cross-fade into the app. No `pubspec.yaml` change.
- D-024 Loading/cards: "Skeleton + stagger". Skeleton replaces full-screen first-load spinners; cards fade + rise one after another on first appearance, not on data refresh.
- D-025 Scope: "Tất cả các trang".

## 5. Requirements

### REQ-101 — Motion tokens
One source for durations and curves in `AppTokens`: `motionShort` 140 ms (unchanged), `motionStandard` 220 ms (unchanged), new `motionMedium` 280 ms, `motionLong` 420 ms, `motionStagger` 40 ms, `motionEntranceOffset` 12.0 px, curves `motionEnter` = `Curves.easeOutCubic`, `motionExit` = `Curves.easeInCubic`.

### REQ-102 — Pushed-route transition (D-022)
Non-Apple platforms: entering route fades 0 → 1 and translates from +12 px (down) to 0 over `motionMedium` with `motionEnter`; reverse uses the same duration. The covered route stays still. iOS/macOS: unchanged native Cupertino. Reduced motion: no movement, settled immediately (current behavior). Existing input/semantics blocking stays.

### REQ-103 — Tab-switch transition (D-022)
`AppDestinationTransition`: new destination fades 0 → 1 and scales 0.985 → 1 over `motionStandard` with `motionEnter`. Old subtree is still disposed immediately (current invariant). Reduced motion: no animation.

### REQ-104 — Startup screen (D-023)
- A brand mark drawn in code (`AppBrandMark`): a 64 px rounded square (`radiusLarge`) in `palette.ink` holding three ascending bars in `palette.onStrong` (a balance/chart glyph). Below it the app name "Crypto Portfolio" (18 px, w600, ink) and the status line "Đang khởi tạo ứng dụng…" (13 px, muted).
- Entrance: mark fades in and scales 0.92 → 1 over `motionLong`, `motionEnter`; text fades in after a 120 ms delay.
- Loading: a 2 px high, 120 px wide indeterminate `LinearProgressIndicator` (ink on border color, rounded) under the text. Reduced motion: no entrance and no progress bar; the mark and the text are shown static (this replaces today's `Icons.hourglass_empty`). The semantics label stays "Đang khởi tạo ứng dụng".
- Failure state: same mark, warning text, retry button (current copy and behavior).
- Hand-off: when initialization completes, the startup view cross-fades into the app over `motionMedium`. No artificial minimum display time. Reduced motion: instant swap.

### REQ-105 — Biometric checking state
While `BiometricAuthScreen` is checking, it shows the same startup status view (mark + name + progress) instead of a bare spinner, so startup → biometric looks like one screen.

### REQ-106 — Skeleton loader (D-024)
`AppSkeleton` (shared widget):
- shows N placeholder cards (default 6) that match card geometry: rounded `radiusMedium`, `palette.surface` fill, 2–3 inner bars in `palette.border`;
- a soft shimmer sweeps left → right every 1200 ms using one `AnimationController` per skeleton (not per row);
- an optional visible caption above the placeholders (12 px, muted) that also serves as the live-region semantics label; default caption "Đang tải dữ liệu…";
- reduced motion: static placeholders, no shimmer;
- not focusable, excluded from semantics except the caption.
Replaces every full-screen first-load loader listed in OBS-105. Screens that show a specific caption today keep that text (e.g. "Đang tải dữ liệu fractal…", "Đang tải chiến thuật…", "Đang tải danh sách coin…").

### REQ-107 — Staggered entrance (D-024)
`AppEntrance` (shared widget) wraps one card/row with its `index`:
- fade 0 → 1 and rise 12 px → 0 over `motionMedium`, `motionEnter`, delay `index × motionStagger`;
- only indexes 0–7 animate; index ≥ 8 appears without animation;
- plays only once, when the item is first mounted inside a newly mounted list. An `AppEntranceScope` placed at the list root records its mount time; items mounted more than `motionLong + 8 × motionStagger` (740 ms) after that (e.g. scrolled into view later, or rebuilt by a data refresh that kept the list mounted) appear without animation;
- a data refresh that keeps showing data (no loading view in between) never replays the entrance;
- reduced motion: no animation;
- never blocks taps (no `IgnorePointer`).

### REQ-108 — Apply to all screens (D-025)
Every screen in OBS-105 uses REQ-106 for its first-load state and REQ-107 for its main cards/rows. Tools cards, Settings cards, Strategy cards, Support-resistance coin cards and the Connections list also get REQ-107.

## 6–7. Data Contract / Cross-Layer Mapping
N/A — UI only, no data or API change.

## 8. Proposed Design

New file `lib/core/widgets/app_motion.dart` holds `AppSkeleton`, `AppEntranceScope`, `AppEntrance`. `AppBrandMark` lives in `app_startup.dart`. Everything is native Flutter (`AnimationController`, `FadeTransition`, `Transform.translate`, `ShaderMask`). Reuse `AppPageTransitions.reduceMotion` everywhere.

## 9. Interfaces and Contracts

```dart
// app_motion.dart
class AppSkeleton extends StatefulWidget {
  const AppSkeleton({super.key, this.itemCount = 6, this.itemHeight = 72, this.caption = 'Đang tải dữ liệu…', this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 8)});
}
class AppEntranceScope extends StatefulWidget { const AppEntranceScope({super.key, required this.child}); }
class AppEntrance extends StatefulWidget { const AppEntrance({super.key, required this.index, required this.child}); }
// app_startup.dart
class AppBrandMark extends StatelessWidget { const AppBrandMark({super.key, this.size = 64}); }
```
Keys: `Key('app-skeleton')` on `AppSkeleton` root, `Key('app-entrance-<index>')` not required. Keep existing keys `app-route-fade`, `app-route-ignore-pointer`, `app-route-exclude-semantics`, `app-destination-fade`, `app-startup-progress-semantics`. New: `Key('app-route-slide')`, `Key('app-destination-scale')`, `Key('app-startup-brand-mark')`, `Key('app-startup-handoff')`.

`AppEntrance` with no `AppEntranceScope` above it renders the child without animation (safe default).

## 10. Invariants
- INV-101: Reduced motion → no movement, no shimmer, no stagger, anywhere.
- INV-102: Transitions never keep a disposed destination alive or let it receive input (current tab invariant).
- INV-103: No new dependency, no protected file change.
- INV-104: Entrance and skeleton never change layout size after settling (translate/opacity only).
- INV-105: No behavior, text, refresh or navigation change other than loaders and motion.

## 11. Edge Cases
- EDGE-101: Init finishes in < 1 frame → cross-fade still runs once, no flicker of a blank frame.
- EDGE-102: Init fails, user taps retry, then succeeds → cross-fade to app once.
- EDGE-103: Pull-to-refresh / timer refresh with data shown → no skeleton, no entrance replay.
- EDGE-104: `skipLoadingOnReload: false` screens (Portfolio, Orders) show the skeleton during a reload, then the entrance plays again — expected (data was hidden).
- EDGE-105: Long lists — only first 8 items animate; items scrolled in later appear instantly.
- EDGE-106: Tab switch while an entrance runs → old subtree disposed; controllers disposed without errors.
- EDGE-107: Text scale 200 % and 320 px width → skeleton and startup view do not overflow.

## 12. Failure Semantics
Motion never hides errors: error views (`AccountStateView`, retry texts) render as today, without skeleton.

## 13. RED / GREEN Behavioral Contract
- RED-139: route after 50 % of the push is translated (> 0 px, < 12 px) — fails today (no translate). Startup shows `app-startup-brand-mark` — fails today.
- GREEN-139: all transition/startup tests pass, reduced-motion tests still pass.
- RED-140 / RED-141: each converted screen shows `AppSkeleton` while loading and its first card has an `AppEntrance` ancestor — fails today.
- GREEN-140 / GREEN-141: same tests pass; full suite passes.

## 14. Performance Contract
One controller per skeleton; entrance controllers dispose on completion-independent unmount; no rebuild of whole lists per frame (use `FadeTransition`/`AnimatedBuilder` scoped to the item). No jank target change.

## 15. Compatibility
Android, iOS, web, macOS, Windows. Web uses the non-Apple route transition.

## 16. Security and Permissions
None.

## 17. Protected Configuration / Environment Actions
None. (Using the real app icon later would need a user-owned `pubspec.yaml` asset entry — not part of this change.)

## 18. Rollout / Rollback
Ships with the branch. Rollback = revert the three task commits.

## 19. Acceptance Criteria
- AC-101 (REQ-101): tokens exist with the listed values.
- AC-102 (REQ-102): non-Apple push is fade + 12 px rise over 280 ms; Cupertino unchanged; reduced motion settled.
- AC-103 (REQ-103): tab switch fade + scale; old subtree disposed immediately.
- AC-104 (REQ-104): startup shows brand mark, name, status, thin progress; cross-fades to the app; reduced motion static.
- AC-105 (REQ-105): biometric checking uses the startup view.
- AC-106 (REQ-106, REQ-108): every OBS-105 loader is an `AppSkeleton` with the listed caption.
- AC-107 (REQ-107, REQ-108): first 8 cards/rows animate once; refresh does not replay; reduced motion none.
- AC-108: `flutter analyze` clean of new issues, `flutter build web` passes, full `flutter test` passes.

## 20. Requirement Traceability
REQ-101..105 → AC-101..105 → P01 → T139. REQ-106..108 → AC-106..107 → P02 (Portfolio, Details, Orders, Market, BMAG) → T140; P03 (Strategy, Support-resistance, Tools, Settings, Connections) → T141. AC-108 → all.

## 21. Completion Gate
All tasks PASS, final V4 suite + web build observed, no protected file touched.

## 22. Change Log
- 2026-11-17: created from user decisions D-022..D-025.
