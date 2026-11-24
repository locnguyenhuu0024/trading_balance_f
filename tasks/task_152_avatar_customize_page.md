# Task 152 — Avatar colours: domain, storage, customize page, home wiring

Status: PASS
Agent Role: implementation_executor
Executor Class: E3
Target Model: gpt-6.2-sol
Target Effort: medium
Target Route: gpt-6.2-sol / medium
Routing Policy: EXECUTOR_ROUTING_POLICY.json v3 (OptCodex v1.5.1)
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-11-22-pnl-avatar-3d-design.md` (Revision 3)
Plan: `docs/agents/plans/2026-11-22-pnl-avatar-3d.md` (Revision 3, PLAN-20261124-pnl-avatar-3d-r3)
Requirements: REQ-223, REQ-224, REQ-225
Acceptance Criteria: AC-225, AC-226
Decisions: D-041, D-042, CD-10, CD-11, CD-12

## 1. Dispatch Compliance

The CCB dispatcher passes `--model gpt-6.2-sol` and `model_reasoning_effort=medium`. `UNVERIFIABLE` is a valid state.

## 2. Objective

Users customize per-part colours of each model on a page with a live 3D preview; saved colours apply to the home avatar.

Done when: RED-152 then GREEN-152 pass on host and buildability passes.

## 3. Preconditions

T151 PASS. User added `flutter_colorpicker: ^1.1.0` (commit 4a6ee8c); coordinator confirmed `flutter_colorpicker` 1.1.0 resolved in `.dart_tool/package_config.json`. Executor sandbox cannot run Flutter: write complete code, report RED/GREEN `NOT_RUN`, buildability `BLOCKED` with that reason.

## 4. Allowed Scope (exact files)

Create: `lib/features/avatar/domain/avatar_colors.dart`, `lib/features/avatar/presentation/avatar_view.dart`, `lib/features/settings/presentation/settings_avatar_customize_page.dart`, `test/features/avatar/avatar_colors_test.dart`, `test/features/settings/settings_avatar_customize_page_test.dart`.
Modify: `lib/features/avatar/domain/avatar_model.dart`, `lib/features/avatar/presentation/avatar_renderer.dart`, `lib/features/avatar/presentation/avatar_renderer_native.dart`, `lib/features/avatar/presentation/avatar_renderer_web.dart`, `lib/features/avatar/presentation/floating_avatar.dart`, `lib/features/settings/presentation/settings_avatar_model_page.dart`, `lib/features/portfolio/presentation/portfolio_screen.dart`, `lib/core/security/secure_storage_helper.dart`, `lib/main.dart`, `test/features/avatar/avatar_model_test.dart`, `test/features/avatar/floating_avatar_test.dart`, `test/features/settings/settings_avatar_model_picker_test.dart`, `test/core/widgets/app_startup_test.dart`, `test/features/portfolio/portfolio_avatar_test.dart`.

## 5. Forbidden Scope

Protected files; `assets/**`, `tools/**`; PnL math; unrelated settings.

## 6. Executor Contract

1. `avatar_colors.dart`: `enum AvatarPart {hair, eyes, top, bottom, shoes, accessory}` with `wireName` (= name) and `label` (Tóc, Mắt, Áo, Quần/Váy, Giày, Phụ kiện); immutable `AvatarColors` (`static const empty`, `withPart`, `withoutPart`, `restrictTo(parts)`, `toJson()` → `{"hair":"#rrggbb"}` lowercase, value `==`/`hashCode`); `decodeAvatarColorsMap(String? json)` → `Map<String, AvatarColors>` that never throws (non-JSON/non-map → `{}`, unknown model ids, unknown parts, non-`#rrggbb` values dropped); `encodeAvatarColorsMap`; `final avatarColorsProvider = StateProvider<Map<String, AvatarColors>>((ref) => const {})`.
2. `AvatarModel.parts`: pixiv-sample [hair, eyes, top, bottom, shoes]; donut-chan [+ accessory].
3. Storage: key `AVATAR_COLORS`; `getAvatarColorsJson()` / `saveAvatarColorsJson(String)` (native, AVATAR_MODEL_ID pattern) and `WebStorageHelper` overrides (`StateError` on failed save); `AppStartupData.avatarColors` loaded in its own try/catch, override `avatarColorsProvider`.
4. Renderer: `void setColors(AvatarColors colors)` on `AvatarRenderer`; native/web send `{'type':'setColors','colors': colors.toJson()}`, store the latest value and resend it after `ready` (with mood/reduced motion).
5. `avatar_view.dart`: extract from `FloatingAvatar` a non-floating `AvatarView({model, mood, colors, semanticsLabel})` owning renderer creation/disposal, lifecycle pause, reduced motion, fade-in, error hide, pointer forwarding and haptics; sends `setMood`/`setColors` only on change. `FloatingAvatar` keeps positioning and long-press drag, composes `AvatarView`, gains `colors`.
6. Home: pass `ref.watch(avatarColorsProvider)[model.id] ?? AvatarColors.empty` (restricted to `model.parts`).
7. Picker page: per row a trailing `IconButton` (`Icons.palette_outlined`, tooltip `Tùy chỉnh`, key `avatar-customize-<id>`) that pushes `SettingsAvatarCustomizePage(modelId: id)` without changing selection.
8. `SettingsAvatarCustomizePage`: `Scaffold` + `AppBar('Tùy chỉnh <name>')` with action `Lưu`; scrollable body: `AvatarView` preview (height `clamp(240, 0.4·screenHeight, 360)`, mood neutral, Semantics `Xem trước nhân vật 3D`), `Wrap` of `ChoiceChip`s for `model.parts` (swatch + label; Semantics `Màu <label>: <hex or Mặc định>`; ≥ 48 dp), `HueRingPicker` (`enableAlpha: false`, `displayThumbColor: true`) bound to the selected part, `OutlinedButton('Khôi phục mặc định')` with confirm dialog (clears the draft). Draft changes call the preview's colours with a 100 ms trailing throttle. `Lưu`: optimistic provider update for this model only, `saveAvatarColorsJson`; on failure rollback + SnackBar `Không lưu được cài đặt`; on success pop. `PopScope`: unsaved draft → confirm `Bỏ thay đổi?`.
9. Tests (RED-150 style names `RED-152` / `GREEN-152`) per §9.

## 9. Mandatory Verification (host, coordinator)

### RED — RED-152
`flutter test --no-pub test/features/avatar/avatar_colors_test.dart test/features/settings/settings_avatar_customize_page_test.dart test/core/widgets/app_startup_test.dart --plain-name "RED-152"`: corrupt JSON / list / bad hex / unknown part or model → dropped; corrupt stored value → startup succeeds with empty colours; save failure rolls back + SnackBar; pixiv chips exclude `Phụ kiện`; unsaved back shows the discard dialog.

### GREEN — GREEN-152
Same files plus `test/features/avatar/floating_avatar_test.dart`, `test/features/settings/settings_avatar_model_picker_test.dart`, `test/features/portfolio/portfolio_avatar_test.dart`, `test/features/avatar/avatar_model_test.dart`, `--plain-name "GREEN-152"`: JSON round-trip and equality; changing a colour sends one throttled `setColors` to the preview; `Lưu` persists only that model's entry and updates the provider; reset clears colours; customize button navigates with the right model and keeps the selection; startup restores native and web; home renderer receives the saved colours and only re-sends on change.

Verification ceiling: V2 (V4 at integration).

### Task Buildability Gate
Command: `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub`
Result: PENDING

## 10. Stop Conditions

`flutter_colorpicker` API differs from `HueRingPicker(pickerColor:, onColorChanged:, enableAlpha:, displayThumbColor:)` → use the closest equivalent from the installed 1.1.0 and report; anything beyond §4 → BLOCKED.

## 12. Coordinator Audit

Attempt `c211d70a…` (1 attempt).
Scope: PASS — exact allowlist.
Host evidence: analyze No issues; RED-152 7/7 then GREEN-152 10/10; V4 `flutter test --no-pub` 739/739; builds web ✓, apk debug ✓, iOS simulator ✓.
iOS Simulator (coordinator): picker rows show palette buttons; customize page for Donut-Chan shows live preview, part chips incl. "Phụ kiện", HueRingPicker; choosing Tóc + red recolors the preview at once and updates the chip swatch; "Lưu" saves and pops; home avatar shows the saved colours.
Findings outside this task's contract (follow-up T153):
- AUD-152-1 (Must, runtime mapping from T151/CD-9): Donut-Chan material names do not match visible parts — `N00_002_03_Tops_01_CLOTH_02` is the whole pink pinafore dress, `N00_007_01_Tops_01_CLOTH_01/02` the chest badge and bow, `Onepiece_00_CLOTH_03` the arm plasters. So "Áo" recolors the dress and "Quần/Váy" recolors the plasters. The T151 audit misattributed the plasters to the top texture.
- AUD-152-2 (Should, UX gap in contract): an unset part starts the colour wheel at black, so the first touch paints the part black.
Verdict: PASS (Flutter contract met; findings tracked in T153)
