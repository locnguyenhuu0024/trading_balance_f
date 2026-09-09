# Task 16: Navigation and Typography Appearance Preferences

**Status:** Completed; checklist locked

**Canonical plan:** [`../docs/agents/plans/2026-09-06-navigation-appearance-preferences.md`](../docs/agents/plans/2026-09-06-navigation-appearance-preferences.md)

**Design:** [`../docs/agents/specs/2026-09-06-navigation-appearance-preferences-design.md`](../docs/agents/specs/2026-09-06-navigation-appearance-preferences-design.md)

## Approval Gate

- [x] User explicitly authorizes implementation of this plan and checklist.

## Execution Checklist

- [x] Add compatible navigation size/opacity fields, defaults, typed options,
  normalization, encoding/decoding, and controller setters.
- [x] Add app text-scale provider/options and native/Web persistence under
  `APP_TEXT_SCALE`.
- [x] Hydrate text scale at startup and apply it through the root `MediaQuery`
  while preserving the platform text scale.
- [x] Pass appearance values through the navigation host and update fixed and
  floating renderers with scaled geometry, default selected alpha `0.5`, and
  preserved minimum hit targets/transparent gaps.
- [x] Add Settings selectors for navigation size, button opacity, and app text
  size with immediate updates, persistence, rollback, and narrow-layout safety.
- [x] Extend focused unit, widget, provider, storage, and root-scaling tests.
- [x] Run formatting, focused/full tests, analyzer review, `git diff --check`,
  and final diff review.
- [x] Update this checklist with exact verification results and lock it only
  after acceptance criteria are met; do not commit or push.

## Scope Notes

- Navigation mode/edge behavior, page clearance, timezone, currency, trading
  logic, and release/deployment scripts are out of scope.
- The navigation preference JSON remains version 1; missing new fields default
  to existing geometry and 50% button opacity.
- The selected fixed circle's 50% alpha is the default and is controlled by the
  shared button-opacity setting.

## Verification Record

- `dart format --set-exit-if-changed` passed for all 16 touched Dart files.
- Focused navigation, Settings, storage, and text-scale tests: **36 passed**;
  final navigation/root subset after the transparent cutout: **17 passed**.
- Full `flutter test`: **84 passed**.
- `flutter analyze`: no errors; 12 pre-existing informational findings remain
  in unrelated legacy code, so the command reports those findings.
- `flutter build web --release --no-wasm-dry-run`: succeeded (`build/web`).
- `git diff --check`: passed.
- No commit, push, deployment, or release-script execution was performed.

## Completion Lock

All checklist items are complete. This task file is now immutable; any future
appearance changes require a new task checklist.
