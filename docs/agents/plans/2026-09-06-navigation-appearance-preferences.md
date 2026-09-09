# Navigation and Typography Appearance Preferences

**Status:** Implemented; verification completed

**Design specification:** [`../specs/2026-09-06-navigation-appearance-preferences-design.md`](../specs/2026-09-06-navigation-appearance-preferences-design.md)

## Objective

Add user controls for navigation button size/opacity and global app text size,
with safe persistence and immediate updates. Make the fixed selected circle
50% opaque by default while preserving the existing seamless bar, floating
overlay, accessibility, and storage contracts.

## Repository Context

The fixed renderer currently uses an opaque selected indicator and the floating
renderer hard-codes its geometry and opaque circles. `NavigationPreferences`
already owns mode/edge persistence in a version-1 JSON record, so the new
navigation appearance values can be optional fields in that record without
breaking existing installs. Settings is already the owner of user preference
controls and startup hydrates providers before `runApp`. There is currently no
app-owned text-scale provider or root `MediaQuery` override.

## Scope

- Extend navigation preferences with normalized button scale and opacity,
  defaulting to `1.0` and `0.5`, and expose typed Settings presets.
- Pass these values to the fixed and floating renderers, scaling visual/layout
  geometry and applying opacity without changing the bar footprint or overlay
  hit-test behavior.
- Add an app text-scale module/provider with typed presets, native/Web storage,
  startup hydration, and root `MediaQuery` composition with the platform scale.
- Add Settings dropdowns, optimistic saves, rollback feedback, and delayed-load
  protection for the new values.
- Extend focused widget/unit/storage tests and run the repository verification
  matrix.

## Explicit Non-goals

- No destination, navigation mode/edge, overlay, page clearance, trading,
  timezone, currency, release-script, deployment, or dependency redesign.
- No free-form sliders, drag positioning, auto-hide, server synchronization,
  screen-by-screen typography rewrite, commit, or push.

## Ordered Implementation Steps

1. Create the app text-scale core module and extend `NavigationPreferences` with
   defaults, option catalogs, normalization, compatible encoding/decoding, and
   controller setters.
2. Add secure-storage and Web-storage methods for `APP_TEXT_SCALE`, keeping
   existing keys and Web failure handling intact; add model/storage tests.
3. Wire startup hydration and the root `MediaQuery.textScaler` in `main.dart`,
   preserving the platform baseline scale and safe defaults.
4. Update `NavigationPresentationHost`, `TradingNavigationBar`, and
   `FloatingNavigationButtons` to consume scale/opacity, retain minimum hit
   targets, preserve alignment/animation, and keep transparent overlay gaps.
5. Add the three typed Settings selectors, optimistic persistence/rollback, and
   async hydration guards without disturbing existing timezone/currency/API
   controls.
6. Add or extend navigation, Settings, root text-scale, provider, and storage
   tests for defaults, compatibility, persistence, rollback, rendering,
   responsive constraints, accessibility, and platform-scale composition.
7. Format touched Dart files and run focused tests followed by the full Flutter
   suite, analyzer, and `git diff --check`; inspect the final diff for scope and
   regression risks.
8. Record exact verification outcomes in Task 16 and mark it complete/immutable
   only after all acceptance criteria are evidenced. Do not commit, push, or
   run deployment/release scripts.

## Affected Components

### New

- `lib/core/typography/app_text_scale.dart`
- `test/core/typography/app_text_scale_test.dart`
- `tasks/task_16_navigation-appearance-preferences.md`

### Modified

- Navigation preference model/controller/host/renderers under
  `lib/core/navigation/`
- `lib/core/security/secure_storage_helper.dart`
- `lib/main.dart`
- `lib/features/settings/presentation/settings_screen.dart`
- Existing navigation, storage, Settings, and root widget tests required by the
  verification matrix

## Verification Strategy

Run after authorization and implementation:

1. `dart format --set-exit-if-changed` on all touched Dart files.
2. Focused model/provider/storage/text-scale tests.
3. Focused navigation renderer and Settings widget tests.
4. `flutter test` for the complete suite.
5. `flutter analyze`, recording any pre-existing informational findings
   separately from errors.
6. `git diff --check` and a final `git diff`/status review.

The focused tests must demonstrate legacy preference compatibility, default
selected-circle alpha, scaled target geometry, four-edge floating behavior,
Settings save/rollback, Web/native text-scale persistence, and composition of
app scale with the platform text scaler. Release builds are not required for
this UI/settings-only change unless separately requested.

## Verification Results

- `dart format --set-exit-if-changed` passed for all 16 touched Dart files.
- Focused navigation, Settings, storage, and text-scale tests passed: **36
  tests** in the initial focused run; the final navigation/root subset passed
  **17 tests** after the transparent fixed-bar cutout was added.
- Full `flutter test` passed: **84 tests**.
- `flutter analyze` reported no errors and the same **12 pre-existing
  informational findings** in unrelated legacy code.
- `flutter build web --release --no-wasm-dry-run` succeeded and produced
  `build/web`.
- `git diff --check` passed. No commit, push, deployment, or release-script
  execution was performed.

## Risks and Rollback

Keep scale presets within the renderer's safe geometry range and preserve the
existing minimum target sizes. Treat missing/invalid new fields as defaults so
old records remain usable. Keep fixed bar/shoulder paint opaque and only apply
opacity to button surfaces. If the change must be rolled back later, remove
only the new appearance fields/module/UI and leave existing mode/edge records
and unrelated preferences untouched.

## Acceptance Criteria

- Default selected fixed indicator renders with alpha `0.5`.
- Settings can change navigation size, navigation button opacity, and app text
  size, with immediate application, durable native/Web persistence, and failed
  save rollback.
- Both navigation modes remain responsive, accessible, aligned, and transparent
  outside their real controls at all existing tested viewport sizes.
- Root app text scaling affects all app text while retaining platform scaling.
- Existing tests and behavior outside this appearance scope remain intact, and
  Task 16 records observed verification results before completion.
