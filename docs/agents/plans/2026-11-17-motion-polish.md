# Implementation Plan: Motion polish

Status: APPROVED
Approval: "Duyệt, commit, làm" (user, chat, 2026-11-17, on this revision; includes commit on PASS)
Date: 2026-11-17
Tier: M
Plan ID: PLAN-20261117-motion-polish
Spec: `docs/agents/specs/2026-11-17-motion-polish-design.md`
Domain: mobile (Flutter)
Branch: `codex/multi-platform-view-only` (current branch, per user)

## 1. Objective

Professional page transitions, a branded startup screen with a smooth hand-off, skeleton loaders and a staggered card entrance on every screen (REQ-101..108, D-022..D-025).

## 2. Preconditions

- Clean checkout on `codex/multi-platform-view-only` at `a84d1a3` (T138).
- OptCodex personal 1.4.0 lock verified (`compat.verify_compatibility` OK, 2026-11-17).

## 3. Repository Impact

| Task | Files |
|---|---|
| T139 | `lib/core/theme/app_theme.dart` (tokens only), `lib/core/widgets/app_page_transition.dart`, `lib/core/widgets/app_startup.dart`, `lib/main.dart` (`BiometricAuthScreen` checking branch only); tests `test/core/navigation/app_page_transition_test.dart`, `test/core/widgets/app_startup_test.dart`, `test/core/widgets/app_startup_preview_test.dart` |
| T140 | new `lib/core/widgets/app_motion.dart`; `portfolio_screen.dart`, `portfolio_details_screen.dart`, `orders_screen.dart`, `orders/presentation/widgets/responsive_order_grid.dart`, `market_screen.dart`, `fractal_screen.dart`; tests: new `test/core/widgets/app_motion_test.dart`, `test/features/portfolio/portfolio_loading_test.dart`, `test/features/orders/orders_binance_view_test.dart`, `test/features/fractal_tracker/fractal_screen_price_formatting_test.dart`, `test/features/market/market_screen_test.dart` |
| T141 | `strategy_screen.dart`, `support_resistance_screen.dart`, `tools_screen.dart`, `settings_screen.dart`, `connections_screen.dart`; new test `test/core/widgets/app_motion_screens_test.dart` |

## 4. External Configuration / Environment Actions

None. No dependency, no `pubspec.yaml`, no native launch files.

## Planning Workstream Decomposition

- Workstreams: mobile UI/motion (material). Backend, data, API: none.
- Fan-out Required: NO. Skip Reason: `SINGLE_MATERIAL_WORKSTREAM`.
- Sol planning advisor: not used — no data-sharing authorization was given for this plan; coordinator planned directly.
- Research performed by coordinator: current transitions (OBS-101), startup (OBS-102/103), asset bundling (OBS-104), every loader (OBS-105), dependent tests (OBS-109). Approach chosen from native Flutter primitives (Ponytail: platform before dependency; reuse `AppPageTransitions.reduceMotion`, `AppTokens`, `AppPalette`).

## 5. Dependency Graph

```
T139 (tokens, transitions, startup) ──► T140 (motion widgets + 5 main screens) ──► T141 (5 remaining screens)
```
Serial: one writer per checkout; T140 uses T139 tokens; T141 uses T140 widgets.

## 6. Ordered Implementation Steps

### P01 — Tokens, transitions, startup (T139)
REQ-101..105. Add tokens; non-Apple route = fade + 12 px rise; tab = fade + scale 0.985; `AppBrandMark` + new startup view + cross-fade hand-off; biometric checking uses startup view.

### P02 — Motion widgets + main screens (T140)
REQ-106..108. Create `AppSkeleton`, `AppEntranceScope`, `AppEntrance`; apply to Portfolio, Portfolio details, Orders (positions + orders), Market, BMAG.

### P03 — Remaining screens (T141)
REQ-107..108. Strategy (skeleton for first load + entrance on strategy cards), Support-resistance (coin cards entrance + instrument picker skeleton), Tools cards, Settings cards, Connections list (skeleton + entrance).

## 7. Test and Verification Plan

| Level | Command |
|---|---|
| V1 per task | the task's focused `flutter test --no-pub <files>` |
| V4 final (each task, since shared widgets change) | `flutter test --no-pub` |
| Buildability | `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub` |

The executor sandbox cannot run Flutter; the coordinator runs RED then GREEN and the build on the host, as in T134–T138.

Manual visual check after T141 (coordinator, host): `flutter run -d chrome` — cold start, tab switch, open Portfolio details, pull-to-refresh; then with reduced motion.

## 8. Migration / Data Plan
N/A.

## 9. Performance Verification
Review: one controller per skeleton, entrance controllers per visible item (≤ 8 animate), all disposed. No profiling run planned (V-level not needed for opacity/translate only).

## 10. Risks
- RISK-101: Tests that pump fixed frames may now see mid-animation states. Mitigation: tests use `pumpAndSettle` where a skeleton is not present (skeleton shimmer repeats, so loading-state tests must use `pump(duration)` not `pumpAndSettle`).
- RISK-102: Cross-fade at the root has no `MediaQuery` above it. Mitigation: read reduced motion from `MediaQueryData.fromView(View.of(context))`.
- RISK-103: Stagger replays on reload for `skipLoadingOnReload: false` screens — accepted (EDGE-104).

## 11. Rollout / Rollback
Per-task commits on this branch only after the user approves commits. Revert per task.

## 12. Decision/Assumption Dependency Registry
D-022 → P01; D-023 → P01; D-024 → P02, P03; D-025 → P02, P03.

## 13. Task Decomposition

| Task | Steps | Class | Route |
|---|---|---|---|
| T139 `tasks/task_139_motion_transitions_startup.md` | P01 | E3 | gpt-6.1-terra / high |
| T140 `tasks/task_140_motion_skeleton_main_screens.md` | P02 | E3 | gpt-6.1-terra / high |
| T141 `tasks/task_141_motion_remaining_screens.md` | P03 | E2 | gpt-6.1-terra / medium |

3 tasks (Tier M target 1–3). Split reason: different write surfaces and verification paths; T141 is mechanical reuse of T140 widgets.

### Task Buildability Plan
Each task ends with `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub` passing. No compile coupling across tasks (T139 tokens are additive; T140 widgets are new).

## 14. Completion Gate
- [ ] T139, T140, T141 PASS
- [ ] V4 + web build green after T141
- [ ] manual visual check done
- [ ] no protected file read or changed

## 15. Change Log
- 2026-11-17: created.
