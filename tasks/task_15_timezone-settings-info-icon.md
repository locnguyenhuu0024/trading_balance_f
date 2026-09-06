# Task 15: Time Zone Settings Info Icon

**Status:** Completed; checklist locked

**Canonical plan:** [`../docs/agents/plans/2026-09-06-timezone-settings-info-icon.md`](../docs/agents/plans/2026-09-06-timezone-settings-info-icon.md)

## Approval Gate

- [x] User explicitly authorizes execution of this plan and checklist.

## Checklist

- [x] Replace the overflowing time-zone subtitle with a compact help/question
  icon beside `Múi giờ`.
- [x] Show the existing global-application explanation in a dismissible,
  accessible dialog when the icon is tapped.
- [x] Preserve the existing time-zone dropdown and persistence behavior.
- [x] Update widget coverage for the help icon, dialog copy, and dismissal.
- [x] Run formatting, focused/full tests, analyzer review, `git diff --check`,
  and final diff review.
- [x] Update this checklist with exact verification results and report without
  committing or pushing.

## Scope Notes

- The stored timezone IDs and `TIME_ZONE_ID` persistence contract remain
  unchanged.
- No Fractal, Orders, navigation, currency, dependency, or release changes are
  included.

## Verification Results

- `dart format --set-exit-if-changed` passed for the touched Dart files.
- Focused Settings timezone widget tests: **3 passed**.
- Full `flutter test`: **72 passed**.
- `flutter analyze`: no errors; 12 pre-existing informational lints remain, so
  the command exits non-zero for those existing findings.
- `git diff --check`: passed.
- No commit or push was performed.

## Completion Lock

This checklist is complete and immutable. Any follow-up or scope change
requires a new task checklist.
