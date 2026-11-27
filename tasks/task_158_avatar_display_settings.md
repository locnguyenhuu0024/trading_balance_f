# Task 158 — Avatar Settings: framing choice and size slider

Status: READY (after T157 PASS)
Agent Role: implementation_executor
Executor Class: E3
Target Model: gpt-6.2-sol
Target Effort: medium
Target Route: gpt-6.2-sol / medium
Routing Policy: EXECUTOR_ROUTING_POLICY.json v3 (OptCodex v1.5.1)
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-11-22-pnl-avatar-3d-design.md` (Revision 5)
Plan: `docs/agents/plans/2026-11-22-pnl-avatar-3d.md` (Revision 5, PLAN-20261127-pnl-avatar-3d-r5)
Requirements: REQ-236
Acceptance Criteria: AC-237, AC-238
Decisions: D-047, D-048, CD-20

## 1. Dispatch Compliance
The CCB dispatcher passes `--model gpt-6.2-sol` and `model_reasoning_effort=medium`. `UNVERIFIABLE` is a valid state.

## 2. Objective
Users choose "Nửa người"/"Toàn thân" and the avatar size in Settings; home and the customize preview follow, and the choices persist.

## 3. Preconditions
T156, T157 PASS. Executor sandbox cannot run Flutter: write complete code, report RED/GREEN `NOT_RUN`, buildability `BLOCKED` with that reason.

## 4. Allowed Scope (exact files)
New: `lib/features/avatar/domain/avatar_display.dart`, `test/features/avatar/avatar_display_test.dart`.
Modify: `lib/core/security/secure_storage_helper.dart`, `lib/main.dart`, `lib/features/avatar/presentation/avatar_renderer.dart`, `lib/features/avatar/presentation/avatar_renderer_native.dart`, `lib/features/avatar/presentation/avatar_renderer_web.dart`, `lib/features/avatar/presentation/avatar_view.dart`, `lib/features/avatar/presentation/floating_avatar.dart`, `lib/features/settings/presentation/settings_screen.dart`, `lib/features/settings/presentation/settings_avatar_customize_page.dart`, `lib/features/portfolio/presentation/portfolio_screen.dart`, `test/features/avatar/floating_avatar_test.dart`, `test/features/settings/settings_avatar_toggle_test.dart`, `test/features/settings/settings_avatar_customize_page_test.dart`, `test/features/settings/settings_avatar_model_picker_test.dart`, `test/features/portfolio/portfolio_avatar_test.dart`, `test/core/widgets/app_startup_test.dart`.

## 5. Forbidden Scope
Protected files; `assets/**`, `tools/**`; PnL math; unrelated settings.

## 6. Executor Contract
1. `avatar_display.dart`: `enum AvatarFraming {half('half','Nửa người',Size(160,220)), full('full','Toàn thân',Size(150,300))}` with `wireName`, `label`, `baseSize`, `static fromWire(String?)` (null/unknown → full). `abstract final class AvatarScale {min 60, max 160, step 10, defaultPercent 100; static int normalize(Object? raw)}` (parse, round to step, clamp; invalid → 100). `avatarFramingProvider` (default full), `avatarScalePercentProvider` (default 100).
2. Storage: keys `AVATAR_FRAMING`, `AVATAR_SCALE`; `getAvatarFraming`/`saveAvatarFraming(String)`, `getAvatarScale`/`saveAvatarScale(int)`; `WebStorageHelper` overrides (`StateError` on failed save). `AppStartupData.avatarFraming`/`avatarScalePercent` preloaded each in its own try/catch; provider overrides.
3. Renderer: `void setFraming(AvatarFraming)` → `{'type':'setFraming','mode':wireName}`. Native: store and include with the initial messages (before model streaming). Web: store, replay on ready after `setOutfit`.
4. `AvatarView`: `framing` param (default full); send in `initState` and in `didUpdateWidget` only when changed and not failed.
5. `FloatingAvatar`: `framing`, `scalePercent` params. Target = baseSize × scale/100 × (width<360 ? 0.8 : 1); fit f = min(1, maxW/w, maxH/h) keeping aspect. When the size changes and a position exists, shift by (oldSize − newSize) to keep the bottom-right corner, then clamp. `AvatarView` key unchanged (no renderer recreation on resize).
6. Home: pass `avatarFramingProvider` and `avatarScalePercentProvider`.
7. Settings (after the credit line, before the divider): "Khung hình" with a `SegmentedButton<AvatarFraming>` below the title (key `settings-avatar-framing`, 48 dp); "Kích thước nhân vật" with trailing `N%` and a `Slider` below (key `settings-avatar-scale-slider`, 60..160, 10 divisions, label/semantic value `N%`). Both disabled when the avatar is off. Framing: optimistic provider, save, on failure restore + SnackBar "Không lưu được cài đặt". Slider: `onChanged` updates the provider only; `onChangeEnd` saves; coalesce (one save in flight, latest value saved after); on failure revert to the last persisted value only if the provider still holds the failed value, + SnackBar.
8. Customize page: preview uses `avatarFramingProvider` and the framing's aspect ratio (full height `(h*0.45).clamp(300,420)`, half unchanged); slider not applied.
9. Tests (`RED-158`/`GREEN-158`): normalize/fromWire edge cases and round trip; startup restore + read failure → full/100; FloatingAvatar sizes per framing at 60/100/160 and small-screen factor, aspect kept when constrained, bottom-right kept and in bounds after resize, renderer not recreated on scale change, `setFraming` sent once on init and only on change; settings rows disabled when off, framing save + failure rollback, slider live provider updates with one save per drag, slider failure rollback; customize preview receives framing; home resizes live from the provider. Update `FakeAvatarRenderer` with recorded framings.

## 9. Mandatory Verification (host, coordinator)
### RED — RED-158
`flutter test --no-pub test/features/avatar/avatar_display_test.dart test/features/avatar/floating_avatar_test.dart test/features/settings/settings_avatar_toggle_test.dart test/core/widgets/app_startup_test.dart --plain-name "RED-158"`.
### GREEN — GREEN-158
Same files plus `test/features/settings/settings_avatar_customize_page_test.dart`, `test/features/portfolio/portfolio_avatar_test.dart`, `--plain-name "GREEN-158"`.
### Task Buildability Gate
Command: `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub`
Result: PENDING
