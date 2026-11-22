# Task 150 — Avatar model catalog, Settings picker and model switching

Status: PENDING
Agent Role: implementation_executor
Executor Class: E3
Target Model: gpt-6.2-sol
Target Effort: medium
Target Route: gpt-6.2-sol / medium
Routing Policy: EXECUTOR_ROUTING_POLICY.json v3 (OptCodex v1.5.1)
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-11-22-pnl-avatar-3d-design.md` (Revision 2)
Plan: `docs/agents/plans/2026-11-22-pnl-avatar-3d.md` (Revision 2, PLAN-20261122-pnl-avatar-3d-r2)
Plan Steps: P05
Requirements: REQ-218 (Flutter side), REQ-219
Acceptance Criteria: AC-221, AC-222
Decisions: D-038, D-039, CD-5, CD-6

## 1. Dispatch Compliance

The CCB dispatcher passes `--model gpt-6.2-sol` and `model_reasoning_effort=medium`. `UNVERIFIABLE` is a valid state.

Dispatch Route Status: PENDING

## 2. Objective

Let the user pick the avatar model in Settings (thumbnail list), persist the choice, and make the home avatar load the chosen model.

Done when: RED-150 then GREEN-150 pass on host and buildability passes.

## 3. Preconditions

Predecessors: T149 PASS (assets `assets/avatar/{pixiv-sample,donut-chan}.{vrm,png}` exist; page accepts `?model=<id>`). The executor sandbox cannot run Flutter: write complete code, report RED/GREEN `NOT_RUN`, buildability `BLOCKED` with that reason.

## 4. Allowed Scope (exact files)

- `lib/features/avatar/domain/avatar_model.dart` (new): `class AvatarModel {id, name, file, thumbnail, credit, licenseText}`; `const avatarModels` = [pixiv-sample: name `Pixiv Sample`, file `pixiv-sample.vrm`, thumbnail `assets/avatar/pixiv-sample.png`, credit `VRM1_Constraint_Twist_Sample © 2022 pixiv Inc. (VRM Public License 1.0)`; donut-chan: name `Donut-Chan`, file `donut-chan.vrm`, thumbnail `assets/avatar/donut-chan.png`, credit `Donut-Chan by Kana Fuyuko (Public Domain)`]; `const defaultAvatarModelId = 'pixiv-sample'`; `AvatarModel avatarModelById(String? id)` (unknown/null → default); `final avatarModelIdProvider = StateProvider<String>((ref) => defaultAvatarModelId)`.
- `lib/features/avatar/avatar_licenses.dart`: keep three.js and three-vrm entries; one `LicenseEntryWithLineBreaks(['<name> (VRM model)'], licenseText)` per catalog model.
- `lib/core/security/secure_storage_helper.dart`: `_avatarModelId = 'AVATAR_MODEL_ID'`, `Future<String?> getAvatarModelId()`, `Future<void> saveAvatarModelId(String)` (same pattern as AVATAR_ENABLED).
- `lib/main.dart`: `AppStartupData.avatarModelId` (default `defaultAvatarModelId`), own try/catch read, override `avatarModelIdProvider` with `avatarModelById(startup.avatarModelId).id`; `WebStorageHelper` overrides (SharedPreferences key `AVATAR_MODEL_ID`, `StateError` on failed save).
- `lib/features/settings/presentation/settings_screen.dart`: load the stored id in `_loadSavedPreferences` (guarded like the avatar switch); replace the hardcoded credit block with a `ListTile` (Key `settings-avatar-model-button`, title `Chọn nhân vật`, subtitle = selected model name, trailing chevron, `enabled: avatarEnabled`) that pushes the picker page; keep a credit `Text` (Key `settings-avatar-credit`) showing the selected model's credit, visible regardless of the switch.
- `lib/features/settings/presentation/settings_avatar_model_page.dart` (new): `Scaffold`/`AppBar('Chọn nhân vật')`, styled like the other settings sub-pages; one row per model (Key `avatar-model-<id>`): `Semantics(selected:, button: true)`, min height 56, leading 48×48 rounded `Image.asset(thumbnail, errorBuilder → Icon(Icons.view_in_ar))`, title name, subtitle credit (no maxLines), trailing `Icons.check_circle` when selected; tap → optimistic provider update + `saveAvatarModelId`, rollback + SnackBar `Không lưu được cài đặt` on failure; rows disabled while saving.
- `lib/features/avatar/presentation/avatar_renderer.dart`: `typedef AvatarRendererFactory = AvatarRenderer Function(AvatarModel model)`; provider default `createPlatformAvatarRenderer`.
- `lib/features/avatar/presentation/avatar_renderer_native.dart`: `createPlatformAvatarRenderer(AvatarModel model)`; load `rootBundle.load('assets/avatar/${model.file}')`.
- `lib/features/avatar/presentation/avatar_renderer_web.dart`: iframe src `assets/assets/avatar/index.html?model=${Uri.encodeQueryComponent(model.id)}` (instance closure instead of the static factory).
- `lib/features/avatar/presentation/floating_avatar.dart`: `required AvatarModel model`; pass it to the factory.
- `lib/features/portfolio/presentation/portfolio_screen.dart`: watch `avatarModelIdProvider`; `FloatingAvatar(key: ValueKey('home-avatar-${model.id}'), model: model, mood: ...)`.
- Tests: `test/features/avatar/avatar_model_test.dart` (new), `test/features/settings/settings_avatar_model_picker_test.dart` (new), and update `test/features/avatar/floating_avatar_test.dart`, `test/features/portfolio/portfolio_avatar_test.dart`, `test/features/settings/settings_avatar_toggle_test.dart`, `test/core/widgets/app_startup_test.dart` for the new factory signature/credit.

## 5. Forbidden Scope

Protected files; `assets/**`, `tools/**`; PnL math; other settings behaviour.

## 6. Invariants / edges

INV-211, INV-212, INV-214 preserved. Unknown stored id → default (no crash, no path built from raw input). Switching while loading disposes the old renderer. Missing thumbnail → icon.

## 7. External Configuration

None.

## 9. Mandatory Verification (host, coordinator)

### RED — RED-150
`flutter test --no-pub test/features/avatar/avatar_model_test.dart test/features/settings/settings_avatar_model_picker_test.dart test/core/widgets/app_startup_test.dart --plain-name "RED-150"`: unknown/null id → default; startup read failure or unknown stored id → `pixiv-sample`; save failure rolls back + SnackBar; missing thumbnail renders the fallback icon; picker row disabled while avatar off.

### GREEN — GREEN-150
Same files plus `test/features/portfolio/portfolio_avatar_test.dart`, `--plain-name "GREEN-150"`: picker lists both names and credits; tapping Donut-Chan saves `donut-chan` and updates the provider; selected row has check icon and `Semantics.selected`; stored `donut-chan` restores on native and web; credit line follows the selection; changing the provider on home disposes the first fake renderer and creates one with `donut-chan`.

Verification ceiling: V2 (final integration V4 by coordinator).

### Task Buildability Gate
Command: `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub`
Result: PENDING

## 10. Stop Conditions

A required API change outside §4 → BLOCKED.

## 12. Coordinator Audit

Verdict: PENDING
