# Time Zone Settings Info Icon

**Status:** Implemented; verification completed

## Objective

Remove the long time-zone explanatory subtitle from the Settings row so the
row remains readable on narrow screens. Preserve the explanation behind a
question/help icon that opens a compact, accessible dialog on demand.

## Repository Context

`SettingsScreen` currently renders the explanation
`Áp dụng cho toàn bộ mốc thời gian trong ứng dụng.` as a `ListTile.subtitle`
beside the time-zone dropdown. The subtitle competes with the dropdown's
trailing width and can overflow. The existing selector already has the stable
key `settings-timezone-select`; the new help affordance needs its own key for
widget coverage.

## Scope

- Remove the time-zone `ListTile.subtitle`.
- Add a compact question/help icon beside the `Múi giờ` title.
- Open an `AlertDialog` (or equivalent Material dialog) containing the same
  explanation and a dismiss action when the icon is tapped.
- Keep the timezone selector, persistence, provider updates, and labels
  unchanged.
- Update the timezone Settings widget test to verify the icon and dialog.

## Explicit Non-goals

- Do not change the selected timezone catalog or stored `TIME_ZONE_ID` value.
- Do not alter Fractal, Orders, navigation, currency, or release behavior.
- Do not change the text meaning; only move it behind the on-demand affordance.
- Do not add a new dependency or change application-wide typography.

## Technical Approach

1. Replace the timezone tile's title `Text` with a compact `Row` containing
   `Múi giờ` and an `IconButton` using `Icons.help_outline_rounded`.
2. Give the button key `settings-timezone-info-button`, a semantic tooltip, and
   an `onPressed` callback that shows an `AlertDialog` with the existing
   explanation and `Đóng` button.
3. Keep the dropdown as the tile's trailing control; use `mainAxisSize: min`
   and compact icon constraints so the title/help affordance cannot consume
   the selector's space.
4. Update the existing timezone widget test to tap the help button, assert the
   dialog copy and dismiss action, then continue to cover selection persistence
   and rollback.

## Affected Files

### Modify

- `lib/features/settings/presentation/settings_screen.dart`
- `test/features/settings/settings_timezone_option_test.dart`

### Create

- `tasks/task_15_timezone-settings-info-icon.md`

## Verification Strategy

- Run `dart format --set-exit-if-changed` on the touched Dart files.
- Run the focused timezone Settings widget test.
- Run the full `flutter test` suite to catch existing Settings layout and
  navigation regressions.
- Run `flutter analyze` and record any existing informational findings.
- Run `git diff --check` and review the final diff.

## Risks and Controls

- **Narrow layouts:** Keep the help icon compact and remove the subtitle so the
  dropdown retains its existing layout space; verify with the widget test's
  dialog interaction.
- **Accessibility:** Provide a tooltip/semantic label and a clearly labeled
  dismiss button; keep the explanation available without relying on hover.
- **Regression:** Do not touch the dropdown callback or timezone persistence
  path; retain the existing selector key and tests.

## Acceptance Criteria

- The Settings timezone row no longer renders the long explanatory subtitle in
  the tile, eliminating the reported overflow.
- A visible `?`/help icon appears next to `Múi giờ` and opens the explanation
  when tapped; the dialog can be dismissed.
- Timezone selection and persistence behavior remain unchanged.
- Focused and full tests pass, with analyzer findings recorded honestly.

## Verification Results

- `dart format --set-exit-if-changed` passed for the touched Dart files.
- Focused Settings timezone widget tests passed: **3 tests**.
- Complete Flutter test suite passed: **72 tests**.
- `flutter analyze` reported no errors; the command still exits non-zero because
  of **12 pre-existing informational lints** in existing code.
- `git diff --check` passed. No commit or push was performed.
