# Task 147 — Avatar mood mapping, setting persistence and licenses

Status: READY
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6.2-sol
Target Effort: low
Target Route: gpt-6.2-sol / low
Routing Policy: EXECUTOR_ROUTING_POLICY.json v3 (OptCodex v1.5.1)
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-11-22-pnl-avatar-3d-design.md`
Plan: `docs/agents/plans/2026-11-22-pnl-avatar-3d.md`
Plan Steps: P02
Requirements: REQ-210, REQ-211, REQ-215
Acceptance Criteria: AC-210, AC-211, AC-212, AC-216
Decisions: D-031, D-032

## 1. Dispatch Compliance

The CCB dispatcher passes `--model gpt-6.2-sol` and `model_reasoning_effort=low`. `UNVERIFIABLE` is a valid state.

Dispatch Route Status: PENDING
Requested Model: PENDING
Requested Effort: PENDING
Observed Effective Model: unavailable
Observed Effective Effort: unavailable

## 2. Objective

Add the pure mood mapping, the persisted `AVATAR_ENABLED` setting (native + web, startup-loaded), the Settings switch with credit line, and license registration. No new package dependency.

Done when: RED-147 then GREEN-147 pass and buildability passes.

## 3. Preconditions

Predecessors: none (T146 may run before; no coupling). No pubspec change required.

## 4. Allowed Scope

- `lib/features/avatar/domain/avatar_mood.dart` (new): `enum AvatarMood { strongHappy, mildHappy, neutral, mildSad, strongSad }` with `String get wireName` = enum name; `AvatarMood avatarMoodFor(double? ratioPercent, {required bool hidden})` exactly per REQ-210.
- `lib/features/avatar/avatar_licenses.dart` (new): `void registerAvatarLicenses()` adding three `LicenseEntryWithLineBreaks` (packages `three.js`, `@pixiv/three-vrm`, `VRM1_Constraint_Twist_Sample (VRM model)`) with MIT texts and "VRM1_Constraint_Twist_Sample (c) 2022 pixiv Inc. Licensed under VRM Public License 1.0 (https://vrm.dev/licenses/1.0/)."; idempotent (guard with a static bool).
- `lib/core/security/secure_storage_helper.dart`: `static const String _avatarEnabled = 'AVATAR_ENABLED';`, `Future<bool> getAvatarEnabled()` (`== 'true'`), `Future<void> saveAvatarEnabled(bool)`; follow the `saveAppTextScale` pattern (do not change `saveAppPreferences`).
- `lib/main.dart`: `AppStartupData.avatarEnabled` (default false); load in its own try/catch in `initializeAppStartup` (failure → false); override `avatarEnabledProvider` in `buildInitializedApp`; `WebStorageHelper` overrides for both new methods using SharedPreferences key `AVATAR_ENABLED`; call `registerAvatarLicenses()` in `main()` before `runApp`.
- `lib/features/settings/presentation/settings_screen.dart`: `final avatarEnabledProvider = StateProvider<bool>((ref) => false);` beside existing providers; load in `_loadSavedPreferences`; `SwitchListTile` (key `settings-avatar-switch`) title `Nhân vật 3D`, subtitle `Hiển thị nhân vật biểu cảm theo lãi/lỗ`, styled like the hide-balance tile, placed in the "BẢO MẬT & TRẢI NGHIỆM" card after hide-balance; on change: set provider optimistically, `await saveAvatarEnabled`, on exception revert provider and show SnackBar `Không lưu được cài đặt`; below it a `Text` (key `settings-avatar-credit`) `Nhân vật 3D: VRM1_Constraint_Twist_Sample © 2022 pixiv Inc. (VRM Public License 1.0)` at fontSize 12 muted palette colour.
- Tests: `test/features/avatar/avatar_mood_test.dart` (new), `test/features/settings/settings_avatar_toggle_test.dart` (new, fake `SecureStorageHelper` subclass like `settings_currency_option_test.dart`), `test/core/widgets/app_startup_test.dart` (add cases).

## 5. Forbidden Scope

Protected files (pubspec.yaml, lockfiles, platform configs) — no read/write. No changes to PnL math, portfolio screen, other settings behavior, `saveAppPreferences` signature. No new dependencies.

## 6. Executor Contract

Steps in §4 order. Invariants: INV-214. Edges: EDGE-210, EDGE-211.

## 7. External Configuration / Environment Actions

None.

## 8. Tests

- TEST-147: mood boundary table; startup restore native/web; read failure → false; toggle persists; save failure reverts + SnackBar; credit text present; license registry contains the three packages.

## 9. Mandatory Verification

### RED — RED-147
Command: `flutter test --no-pub test/features/avatar/avatar_mood_test.dart test/features/settings/settings_avatar_toggle_test.dart test/core/widgets/app_startup_test.dart --plain-name "RED"`
Expected: `avatarMoodFor(6, hidden:true)`, `(null)`, `(double.nan)`, `(1.0)`, `(-1.0)` → neutral; startup getter throws → `avatarEnabled == false`; save throws → switch back to off + SnackBar text.
Status: READY

### GREEN — GREEN-147
Command: same files, `--plain-name "GREEN"`
Expected: 1.0001 → mildHappy; 4.99 → mildHappy; 5 → strongHappy; 12 → strongHappy; −1.0001 → mildSad; −4.99 → mildSad; −5 → strongSad; −20 → strongSad; fresh storage → switch off; toggle on → `saveAvatarEnabled(true)` called and provider true; native and web startup with stored `'true'` → provider true; credit text found; `LicenseRegistry.licenses` includes `three.js`, `@pixiv/three-vrm`, `VRM1_Constraint_Twist_Sample (VRM model)`.
Status: READY

Executor sandbox cannot run Flutter: write complete code, report RED/GREEN `NOT_RUN` (order named), buildability `BLOCKED` with that reason. Coordinator runs them on host.
Verification ceiling: V2.

### Task Buildability Gate
Required: YES
Affected build unit: Flutter app
Command: `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub`
Result: PENDING

### External Verification
Required: NO

## 10. Stop Conditions

Existing settings tests break in ways requiring changes outside §4 → BLOCKED.

## 11. Execution Ledger

- [ ] route confirmed explicit
- [ ] implement §4
- [ ] tests
- [ ] report

## 12. Coordinator Audit

Verdict: PENDING

## 13. Remediation R01 (coordinator audit attempt 1 → REWORK)

Attempt 1 (`05daf9a6…`) is committed as the starting point. Host evidence: settings + startup RED-147/GREEN-147 pass; V2 `flutter test --no-pub test/features/settings test/core/widgets/app_startup_test.dart` 45/45 pass; source review OK.
AUD-147-1 (Must): `test/features/avatar/avatar_mood_test.dart` does not compile — `const cases = {1.0001: …}` uses `double` keys in a constant map (`const_map_key_not_primitive_equality`, 8 analyzer errors). Change that declaration from `const` to `final`. Nothing else.
Allowed write files (exact): `test/features/avatar/avatar_mood_test.dart`.
RED-147-R01: before editing, record `grep -n "const cases" test/features/avatar/avatar_mood_test.dart` (matches).
GREEN-147-R01: `grep -n "final cases" …` matches; coordinator runs `flutter analyze` and the tests on host.
