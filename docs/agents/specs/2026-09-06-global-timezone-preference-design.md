# Global Time Zone Preference Design

## Intent

Add one persisted application time-zone preference and use it consistently for
all user-visible calendar values and application-owned period calculations.
The first implementation covers the existing time-aware screens: Fractal
Tracker and Order Management. The shared core API is the only approved path
for adding future date/time presentation.

## Evidence from the Current Implementation

The current behavior is mixed rather than tied to one configured time zone:

- `fractal_provider.dart` calls `DateTime.now().toUtc()` and creates D1, W1,
  M1, and Y1 query boundaries with `DateTime.utc(...)`.
- Fractal month/year sub-candle labels are derived with
  `DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: true)`, so those
  labels use UTC calendar fields.
- Fractal quarter start times are converted with `.toLocal()` and formatted by
  `DateFormat`, so the displayed quarter ranges use the device's local time
  zone. On the inspected host, the local zone is UTC+07:00, but another device
  may produce a different result.
- `selectedMonthProvider` and `selectedYearProvider` seed from
  `DateTime.now()`, which also follows the device's local zone.
- `orders_screen.dart` calls
  `DateTime.fromMillisecondsSinceEpoch(timestampMs)` without `isUtc: true`, so
  order timestamps are formatted in the device's local zone.
- `okx_interceptor.dart` deliberately generates the UTC ISO timestamp required
  by OKX authentication. This is a transport/security contract, not a UI time
  zone, and must remain UTC.

Therefore the current Fractal Tracker is UTC for API period boundaries and
sub-candle calendar labels, but local-device time for quarter labels and
progress display. It is not correct to describe the current app as using only
UTC or only UTC+07:00.

## User Experience

- Add a `Múi giờ` selector in the existing **HIỂN THỊ & GIAO DIỆN** settings
  card.
- Show the selected region name and IANA identifier in the dropdown. Use a
  curated list of common trading regions rather than exposing an unsearchable
  list of every IANA location.
- Initial catalog entries:
  - `Etc/UTC` — UTC
  - `Asia/Ho_Chi_Minh` — Hồ Chí Minh
  - `Asia/Singapore` — Singapore
  - `Asia/Tokyo` — Tokyo
  - `Asia/Kolkata` — Kolkata
  - `Europe/London` — London
  - `Europe/Paris` — Paris
  - `America/New_York` — New York
  - `America/Chicago` — Chicago
  - `America/Los_Angeles` — Los Angeles
  - `Australia/Sydney` — Sydney
- Use the IANA database so regions with daylight-saving transitions are
  converted correctly for the instant being displayed. The setting stores the
  stable IANA identifier, not a one-time numeric offset.
- Default missing, malformed, or unsupported values to `Etc/UTC`. UTC keeps
  the existing OKX/Fractal aggregation contract deterministic across devices;
  users can select Hồ Chí Minh or another region explicitly.
- Applying a new selection updates visible screens immediately, invalidates
  Fractal data so current-period calculations use the new zone, and persists
  the choice. A failed write restores the last confirmed selection and shows a
  user-visible error.

## Time Semantics and Boundaries

### Application and exchange layers

The feature has two explicit layers:

1. **Exchange/transport layer:** Unix epoch milliseconds, OKX request
   timestamps, HMAC signing, and the `1Dutc`/`1Mutc` bar identifiers remain
   UTC/API-defined. The preference must never alter authentication headers or
   reinterpret the server's raw instant values.
2. **Application/calendar layer:** current day/week/month/year boundaries,
   Fractal labels and ranges, order timestamps, and any future user-visible
   date/time values are converted through the selected IANA location.

For Fractal data, a selected-zone calendar boundary is converted back to epoch
milliseconds before filtering the UTC candle payload. This lets a user inspect
the same instants according to their chosen day/week/month/year while keeping
OKX's candle contract intact. The app does not synthesize new exchange candles
or change the server's UTC bar alignment.

### Shared conversion rules

Create a core `AppTimeZone` catalog/service that provides:

- supported options, labels, default ID, and safe ID normalization;
- `locationFor(id)` and `fromEpochMilliseconds(id, timestampMs)` helpers;
- a selected-zone `now` helper that accepts an optional instant for deterministic
  tests;
- start/end boundaries for local calendar day, ISO week (Monday through the
  next Monday), month, and year;
- formatting of an epoch timestamp with the existing `intl` patterns after it
  has been converted to the selected `TZDateTime`.

All returned instants remain comparable by epoch milliseconds. A converted
`TZDateTime` is used only where calendar fields or `DateFormat` output are
needed.

## State and Persistence

- Add `appTimeZoneProvider` as a global Riverpod state provider whose value is
  the selected IANA ID string.
- Add a dedicated `TIME_ZONE_ID` storage key and
  `getTimeZoneId()`/`saveTimeZoneId(...)` methods to `SecureStorageHelper`.
- Implement the same methods in `WebStorageHelper` using
  `SharedPreferences`, preserving mobile secure storage and web local storage
  behavior.
- Keep the existing `saveAppPreferences(...)` contract unchanged. Time-zone
  writes are independent so old settings test doubles and persisted theme,
  currency, biometric, and hide-balance records remain compatible.
- During `main()` startup, initialize the timezone database, read and sanitize
  `TIME_ZONE_ID`, and override `appTimeZoneProvider` before `runApp`.
- `SettingsScreen` also reads the value when it is mounted so standalone screen
  tests and nonstandard entry points hydrate the same provider.

## Fractal Tracker Changes

- Make `fractalDataProvider` watch `appTimeZoneProvider`.
- Replace direct `DateTime.now()`, `DateTime.utc(...)`, `.toLocal()`, and raw UTC
  calendar extraction in period/label code with `AppTimeZone` helpers.
- Keep `fractalBarForTimeframe(...)` and OKX endpoint selection unchanged.
- Pass the selected zone into sub-candle labeling and quarter start conversion.
- Use a selected-zone instant for progress calculations while retaining epoch
  duration arithmetic, so changing the display zone does not change elapsed
  time.
- Preserve the existing month/year navigation values and behavior; they remain
  calendar selections and are interpreted in the selected zone when the query
  is built.

## Order Management Changes

- Read `appTimeZoneProvider` in `OrdersScreen`.
- Convert `OkxOrder.cTime` through the shared formatter before rendering the
  existing `dd/MM/yyyy HH:mm` string.
- Preserve `--` for missing or malformed timestamps.
- Do not change order API models, sorting, refresh timers, or authentication.

## Accessibility and Failure Handling

- Give the selector a stable key (`settings-timezone-select`) for tests and a
  clear label/subtitle explaining that it applies globally.
- Keep dropdown text readable in both themes and preserve the existing settings
  card layout.
- If the timezone database cannot initialize or a stored ID is invalid, use
  UTC and keep the app usable. Do not block startup on a corrupt preference.
- If persistence fails after a user selection, roll back the provider value,
  retain the previously confirmed zone, and show the existing style of inline
  or snackbar error feedback.

## Non-goals

- Do not change OKX authentication timestamps, WebSocket protocol values, Unix
  epoch storage, candle endpoint names, or exchange candle definitions.
- Do not add a device-location permission or attempt to infer an IANA region
  from the operating system in this task.
- Do not add a full searchable world-zone picker; the catalog can be extended in
  a later task without changing the stored ID format.
- Do not modify Market or Portfolio UI files because they currently expose no
  calendar/timestamp values. Future date/time UI must use the shared service.
- Do not change currency, navigation, security, release scripts, or generated
  model files.

## Verification Contract

- Unit tests prove catalog normalization, default fallback, selected-zone epoch
  conversion, DST-aware conversion for at least one supported region, and local
  day/week/month/year boundaries.
- Fractal tests prove the same timestamp receives different calendar labels in
  UTC and Hồ Chí Minh and that selected-zone day/week bounds are converted to
  the expected UTC epochs.
- Settings widget tests prove the selector is present, selection persistence is
  called, and a failed write restores the previous value.
- Order widget/formatter tests prove the displayed `cTime` follows the global
  selection and malformed values remain `--`.
- Startup/storage tests prove mobile and web helpers round-trip `TIME_ZONE_ID`
  and invalid records fall back to UTC.
- Existing navigation, currency, portfolio, and security tests must continue to
  pass.
