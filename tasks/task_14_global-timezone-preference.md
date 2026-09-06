# Task 14: Global Time Zone Preference

**Status:** Completed; checklist locked

**Canonical plan:** [`../docs/agents/plans/2026-09-06-global-timezone-preference.md`](../docs/agents/plans/2026-09-06-global-timezone-preference.md)

**Design specification:** [`../docs/agents/specs/2026-09-06-global-timezone-preference-design.md`](../docs/agents/specs/2026-09-06-global-timezone-preference-design.md)

## Approval Gate

- [x] User explicitly authorizes execution of this plan and checklist.

## Checklist

- [x] Promote the existing `timezone` package to a direct dependency and add the
  shared IANA catalog, provider, initialization, conversion, calendar-boundary,
  and formatting APIs.
- [x] Add core time-zone unit tests for normalization/defaults, UTC and Hồ Chí
  Minh conversion, calendar boundaries, and a DST transition.
- [x] Add `TIME_ZONE_ID` persistence to mobile secure storage and web
  `SharedPreferences`, including round-trip and invalid-value coverage.
- [x] Initialize the timezone database and hydrate the sanitized provider during
  app startup without changing OKX UTC authentication behavior.
- [x] Add the Settings `Múi giờ` selector with global-application copy,
  optimistic update, persistence, rollback, and error feedback.
- [x] Refactor Fractal Tracker period boundaries, labels, quarter times, and
  progress to use the selected timezone while preserving OKX bar IDs and raw
  epoch semantics.
- [x] Refactor Order Management timestamp rendering to use the selected
  timezone and preserve malformed-value fallback behavior.
- [x] Add/update Fractal, Settings, Order, startup/storage, and widget regression
  tests for reactive timezone changes.
- [x] Run formatting on touched Dart files, focused tests, the full Flutter test
  suite, analyzer review, `git diff --check`, and final diff review.
- [x] Update this checklist with exact verification results and report without
  committing or pushing.

## Scope Notes

- Missing, malformed, or unsupported stored IDs resolve to `Etc/UTC`.
- The curated catalog initially includes UTC, Hồ Chí Minh, Singapore, Tokyo,
  Kolkata, London, Paris, New York, Chicago, Los Angeles, and Sydney.
- OKX request signing, WebSocket values, Unix timestamps, and
  `1Dutc`/`1Mutc` exchange candle definitions remain UTC/API-defined.
- Market and Portfolio files remain unchanged because they currently expose no
  user-visible date/time values.

## Verification Results

- `dart format --set-exit-if-changed` passed for all touched Dart files.
- Focused time-zone, storage, Fractal, Settings, and Order tests: **19 passed**.
- Full `flutter test`: **72 passed**.
- `flutter analyze`: no errors; 12 pre-existing informational lints remain, so
  the command exits non-zero for those existing findings.
- `flutter build web --release`: passed (`build/web`).
- `flutter build apk --release --no-pub`: passed
  (`build/app/outputs/flutter-apk/app-release.apk`, 55.6 MB).
- `git diff --check`: passed.
- No commit or push was performed.

## Completion Lock

This checklist is complete and immutable. Any follow-up or scope change
requires a new task checklist.
