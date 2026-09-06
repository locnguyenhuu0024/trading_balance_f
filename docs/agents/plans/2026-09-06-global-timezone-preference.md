# Global Time Zone Preference

**Status:** Implemented; verification completed

**Design specification:** [`../specs/2026-09-06-global-timezone-preference-design.md`](../specs/2026-09-06-global-timezone-preference-design.md)

## Objective

Introduce a persisted, globally reactive IANA time-zone setting and route every
existing user-visible date/time value through it. Fractal Tracker will use the
selected zone for calendar period boundaries, labels, and ranges; Order
Management will use it for order creation timestamps. Missing or invalid
preferences fall back to UTC, while OKX transport/authentication timestamps
remain UTC by contract.

## Repository Context

The repository currently mixes UTC and device-local behavior:

- `lib/features/fractal_tracker/presentation/providers/fractal_provider.dart`
  builds D1/W1/M1/Y1 boundaries in UTC, labels M1/Y1 sub-candles in UTC, and
  converts quarter starts to device local time.
- `lib/features/fractal_tracker/presentation/fractal_screen.dart` formats the
  quarter values with `intl` and calculates progress from the local `DateTime`.
- `lib/features/orders/presentation/orders_screen.dart` formats `cTime` with
  the device's local zone.
- `lib/core/network/okx_interceptor.dart` creates the UTC ISO timestamp required
  for signed OKX requests; it must not consume the UI preference.
- `SettingsScreen` already hydrates settings from `SecureStorageHelper`, and
  `WebStorageHelper` mirrors those reads/writes through `SharedPreferences`.
- `timezone` is already present transitively in `pubspec.lock` (version
  `0.11.1`), but it is not a direct application dependency.

## Scope

- Promote the existing `timezone` package to a direct dependency and initialize
  its embedded IANA database at application startup.
- Add a shared core catalog/conversion API and a Riverpod provider for the
  selected IANA zone.
- Persist the zone independently under `TIME_ZONE_ID` for mobile secure storage
  and web local storage.
- Add the settings selector, optimistic update, persistence, rollback, and
  error feedback.
- Refactor Fractal Tracker and Order Management to use the shared API.
- Add unit, widget, storage, and regression tests for conversion and reactive
  behavior.

## Explicit Non-goals

- Do not alter OKX request signing, WebSocket payloads, Unix epoch storage, or
  the `1Dutc`/`1Mutc` bar IDs.
- Do not synthesize exchange candles aligned to a local zone; raw OKX candle
  definitions remain API-defined. Only app calendar boundaries and presentation
  use the selected location.
- Do not modify Market or Portfolio UI files because they currently display no
  date/time values.
- Do not add OS location permissions, automatic device-zone detection, or a
  searchable all-world-zone picker.
- Do not change currency, navigation, security, release scripts, or generated
  model files.
- Do not commit or push.

## Technical Design

### Core time-zone module

Create `lib/core/timezone/app_time_zone.dart` containing:

- an immutable option record with IANA ID and user-facing label;
- the curated catalog from the design spec, with `Etc/UTC` as the default;
- safe lookup/normalization that maps missing, malformed, and unsupported IDs to
  `Etc/UTC`;
- one-time timezone database initialization;
- conversion from an epoch millisecond instant to a `TZDateTime` in the chosen
  location;
- selected-zone `now` with an injectable instant for deterministic tests;
- calendar boundary helpers for start/end of day, ISO week (Monday), month, and
  year, returning epoch milliseconds for API filtering;
- a shared epoch formatter used by order cards and future date/time UI.

Keep the stored value as a string IANA ID so it is stable across DST changes.
Use `timezone/data/latest.dart` and `timezone/timezone.dart`; do not duplicate a
time-zone database or derive offsets manually.

Add `appTimeZoneProvider` (defaulting to the catalog's default ID) in the core
module or a neighboring provider file. Screens should watch this provider,
while startup and tests may override it with a sanitized ID.

### Persistence and startup

1. Add `TIME_ZONE_ID`, `getTimeZoneId()`, and `saveTimeZoneId(...)` to
   `SecureStorageHelper`.
2. Add matching `SharedPreferences` overrides to `WebStorageHelper` in
   `lib/main.dart`.
3. Keep `saveAppPreferences(...)` unchanged so existing settings doubles and
   persisted theme/currency/security records remain compatible.
4. In `main()`, initialize the database before constructing the app, read the
   stored ID with a UTC fallback, sanitize it, and override
   `appTimeZoneProvider` in the existing `ProviderScope`.
5. Catch initialization/read failures and continue with UTC; a corrupt setting
   must never prevent the app from starting.

### Settings behavior

Modify `lib/features/settings/presentation/settings_screen.dart`:

- hydrate the provider from `getTimeZoneId()` alongside existing settings;
- add a `Múi giờ` `DropdownButton<String>` with key
  `settings-timezone-select` to the first settings card;
- show the option label and a concise global-application subtitle;
- update the provider immediately when a valid item is selected, disable the
  selector while its write is in flight, persist the ID, and invalidate
  `fractalDataProvider` after a successful change;
- on write failure, restore the prior confirmed ID and show a clear snackbar or
  inline error consistent with existing settings feedback.

Do not import storage implementation details into other feature screens; they
should only watch `appTimeZoneProvider`.

### Fractal Tracker behavior

Modify `fractal_provider.dart` and `fractal_screen.dart`:

- make `fractalDataProvider` watch `appTimeZoneProvider` so a selection creates
  a new data computation;
- introduce a small testable period-boundary helper (or equivalent) that uses
  the selected location for current D1/W1 and target M1/Y1 ranges, then converts
  those calendar boundaries to epoch milliseconds before querying/filtering;
- preserve the current endpoint fallback order, limits, and bar IDs;
- pass the selected ID to sub-candle labeling so the same epoch can display a
  different local day/month as intended;
- convert quarter start instants with `AppTimeZone.fromEpochMilliseconds`
  instead of `.toLocal()`;
- use a selected-zone `now` for progress calculations while keeping duration
  math based on epoch instants;
- preserve month/year navigation as calendar selections; interpret their year
  and month fields in the selected location when building boundaries;
- keep the existing `fractalQuarterIndex` contract for epoch ranges, updating
  the year-month midpoint conversion only if required by the shared location
  helper.

### Order Management behavior

Modify `orders_screen.dart` and, if useful for testability, expose a small pure
formatter in the core time-zone module:

- watch `appTimeZoneProvider` in `OrdersScreen`;
- convert valid `OkxOrder.cTime` values through the shared formatter using the
  existing `dd/MM/yyyy HH:mm` pattern;
- keep `--` for null, empty, or malformed timestamps;
- leave API fetching, sorting, refresh timers, and order models unchanged.

## Ordered Implementation Steps

1. Add the direct `timezone` dependency and create the catalog, provider, safe
   lookup, initialization, conversion, boundary, and formatting APIs.
2. Add core time-zone unit tests first, covering catalog normalization, UTC and
   Hồ Chí Minh conversion, ISO week/month/year boundaries, and a DST transition
   in `America/New_York`.
3. Add storage methods and web overrides; add round-trip and invalid-value tests
   without changing the existing app-preference methods.
4. Wire database initialization and the sanitized startup provider override in
   `main.dart`; verify web storage still hydrates all existing settings.
5. Add and test the Settings dropdown, optimistic persistence, rollback, and
   Fractal invalidation behavior.
6. Refactor Fractal period construction, quarter rendering, progress, and
   sub-candle labels; extend `fractal_provider_test.dart` with deterministic
   selected-zone cases.
7. Refactor order timestamp rendering and add formatter/widget coverage for UTC,
   a non-UTC zone, and malformed input.
8. Format only touched Dart files, run focused tests, then the complete test
   suite and analyzer; inspect the final diff for UTC transport regressions.
9. Update the Task 14 checklist with observed verification results and report
   without committing or pushing.

## Affected Files

### Create

- `lib/core/timezone/app_time_zone.dart`
- `test/core/timezone/app_time_zone_test.dart`
- `test/features/settings/settings_timezone_option_test.dart`
- `test/features/orders/presentation/order_timezone_test.dart` (or the
  repository's chosen focused formatter test path)

### Modify

- `pubspec.yaml` (promote `timezone` to a direct dependency)
- `pubspec.lock` (generated by dependency resolution if it changes)
- `lib/main.dart`
- `lib/core/security/secure_storage_helper.dart`
- `lib/features/settings/presentation/settings_screen.dart`
- `lib/features/fractal_tracker/presentation/providers/fractal_provider.dart`
- `lib/features/fractal_tracker/presentation/fractal_screen.dart`
- `lib/features/orders/presentation/orders_screen.dart`
- `test/features/fractal_tracker/fractal_provider_test.dart`
- existing storage/widget tests only where required to preserve or extend
  coverage

## Verification Strategy

Run after implementation, in this order:

1. `flutter test test/core/timezone/app_time_zone_test.dart`
2. `flutter test test/features/fractal_tracker/fractal_provider_test.dart test/features/settings/settings_timezone_option_test.dart test/features/orders/presentation/order_timezone_test.dart`
3. Existing navigation/settings/storage/widget tests that exercise startup and
   screen composition.
4. `flutter test`
5. `flutter analyze` (record any pre-existing informational findings separately)
6. `git diff --check` and a final `git diff` review.

The focused tests must prove:

- UTC and Hồ Chí Minh render the same epoch with different calendar fields;
- selected-zone D1/W1/M1/Y1 boundaries produce the expected UTC epochs;
- DST-aware regions use the correct offset before and after a transition;
- missing/invalid storage records resolve to UTC;
- Settings writes and rolls back the selected ID correctly;
- changing the provider refreshes Fractal data and updates order timestamp
  rendering;
- OKX interceptor tests/behavior remain UTC and unchanged.

## Risks and Controls

- **Database initialization:** `timezone` initialization is global and must be
  completed before any `getLocation` call. Centralize it in startup/core code
  and fall back to UTC on failure.
- **DST boundary arithmetic:** Never add a hard-coded offset for IANA zones;
  construct calendar boundaries with `TZDateTime(location, ...)` and compare
  epoch milliseconds.
- **Raw exchange bars:** Local calendar boundaries can cut across UTC-aligned
  exchange candles. Keep the bar IDs and raw instants intact and document that
  the setting changes app grouping/presentation, not exchange candle synthesis.
- **Persistence races:** Disable the selector during a write and retain a
  confirmed value for rollback.
- **Bundle size:** The embedded IANA database may increase release artifacts;
  measure builds after implementation and do not replace it with a partial
  database without an explicit scope change.
- **Regression scope:** Keep all network authentication timestamps UTC and run
  existing navigation, portfolio, currency, security, and widget tests.

## Acceptance Criteria

- Settings exposes the curated IANA time-zone list under `Múi giờ` and persists
  the selected ID on mobile and web.
- A fresh install or invalid stored value starts in UTC; the app remains usable
  if storage or timezone initialization fails.
- Fractal current-period boundaries, month/year ranges, quarter labels,
  sub-candle labels, and progress all use the selected zone.
- Order creation timestamps use the selected zone and retain the existing
  format/fallback behavior.
- Market/Portfolio and OKX transport behavior are unchanged except that future
  date/time consumers can use the shared API.
- Focused tests, full `flutter test`, analyzer review, and diff checks are run
  and their exact results are recorded in the Task 14 checklist.

## Verification Results

- `dart format --set-exit-if-changed` passed for all touched Dart files.
- Focused time-zone, storage, Fractal, Settings, and Order tests passed: **19
  tests**.
- Complete Flutter test suite passed: **72 tests**.
- `flutter analyze` reported no errors; the command still exits non-zero because
  of **12 pre-existing informational lints** in unrelated/previously existing
  code (`okx_interceptor.dart`, `background_service.dart`, Fractal UI,
  `market_screen.dart`, and existing Settings switches).
- `flutter build web --release` passed and produced `build/web`.
- `flutter build apk --release --no-pub` passed and produced
  `build/app/outputs/flutter-apk/app-release.apk` (55.6 MB).
- `git diff --check` passed. No commit or push was performed.
