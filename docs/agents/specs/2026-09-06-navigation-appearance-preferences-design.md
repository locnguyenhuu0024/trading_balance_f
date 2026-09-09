# Navigation and Typography Appearance Preferences

**Status:** Draft

## 1. Objective

Make the selected fixed-navigation circle translucent, expose navigation button
size and opacity controls in Settings, and add a persisted application text-size
preference that applies consistently across the app. The existing navigation
mode/edge behavior, destination order, storage safety, and overlay semantics
must remain intact.

## 2. Current Behavior

- `TradingNavigationBar` renders the selected indicator with the same opaque
  black/white color as the fixed bar surface.
- `FloatingNavigationButtons` hard-codes a 52-pixel target slot, 52-pixel
  selected circle, 44-pixel unselected circle, and opaque button surfaces.
- `NavigationPreferences` version 1 stores only `displayMode` and
  `floatingEdge` in `NAVIGATION_PREFERENCES`; startup hydration and native/Web
  persistence already exist.
- Settings exposes navigation mode and floating edge, but not button geometry
  or opacity.
- `TradingBalanceApp` does not apply an app-owned text scaler. Individual
  widgets use explicit font sizes and otherwise rely on the platform
  `MediaQuery` scale.

## 3. Product Decisions

### 3.1 Navigation button size

Use three typed presets so the setting is easy to understand and cannot accept
an invalid arbitrary value:

| Internal scale | Settings label | Meaning |
| --- | --- | --- |
| `0.9` | `Nhỏ` | Compact visual buttons |
| `1.0` | `Chuẩn` | Existing geometry |
| `1.1` | `Lớn` | Enlarged visual buttons |

The scale applies to both fixed and floating presentations. Visual geometry and
spacing scale together, while every interactive slot remains at least 48 by
48 pixels. The fixed bar keeps its 60-pixel content footprint; enlarged
controls may use the existing raised crest space but must not enlarge the page
reservation or introduce an opaque strip.

### 3.2 Navigation button opacity

Use typed opacity presets with a default of `0.5`:

| Internal opacity | Settings label |
| --- | --- |
| `0.35` | `Mờ` |
| `0.5` | `Mặc định (50%)` |
| `0.75` | `Rõ (75%)` |
| `1.0` | `Đục (100%)` |

The setting controls navigation button surfaces. In fixed mode, the selected
circle uses the configured opacity over the raised contour; the bar and
shoulders remain opaque so the navigation block remains a single surface. In
floating mode, each circular button and its selected label surface use the
configured opacity. Icons retain the existing theme-derived foreground colors,
tooltips, semantics, and hit targets.

The default therefore makes the selected fixed circle exactly 50% opaque, as
requested, while still allowing the user to choose a different button opacity.

### 3.3 Application text size

Use four typed presets persisted independently from navigation presentation:

| Internal scale | Settings label | Meaning |
| --- | --- | --- |
| `0.9` | `Nhỏ` | Slightly smaller app text |
| `1.0` | `Mặc định` | Existing app text size |
| `1.15` | `Lớn` | Larger app text |
| `1.3` | `Rất lớn` | High-readability app text |

The selected value is applied at the `MaterialApp` root through
`MediaQuery.textScaler`, multiplying the platform's current baseline scale so
OS accessibility scaling is not discarded. The default is neutral and leaves
the platform scale unchanged. Existing explicit `TextStyle.fontSize` values
therefore respond uniformly without a screen-by-screen typography rewrite.

## 4. Scope

- Extend the typed navigation preference record with button scale and opacity,
  retaining version 1 and treating the new JSON fields as optional for older
  records.
- Add normalization, option catalogs, equality, encoding, and decoding for
  the new navigation fields.
- Pass the preferences from the shell/host into both navigation renderers.
- Scale fixed and floating button geometry while preserving minimum accessible
  hit targets, alignment, safe insets, compact scrolling, and transparent
  overlay gaps.
- Render the fixed selected circle with the configured alpha, defaulting to
  `0.5`.
- Add typed Settings dropdowns for navigation size and opacity.
- Add a core application text-scale provider and option catalog.
- Add native secure-storage and Web `SharedPreferences` read/write methods for
  the text scale under `APP_TEXT_SCALE`.
- Hydrate the text scale before `runApp`, override the provider at startup, and
  apply it in `TradingBalanceApp`.
- Add immediate optimistic Settings updates with a single in-flight save,
  rollback, and recoverable feedback for text-scale writes.
- Preserve existing navigation mode/edge persistence and all unrelated
  preference keys.

## 5. Explicit Non-goals

- Do not change the navigation destination list, mode/edge semantics, overlay
  layering, page content clearance, or order of buttons.
- Do not change the fixed bar's square outer corners, full-width footprint, or
  bar/shoulder theme colors.
- Do not rewrite every screen's typography or replace the platform text-scale
  accessibility model.
- Do not add a free-form slider, drag positioning, auto-hide behavior, remote
  synchronization, account settings API, or new third-party dependency.
- Do not alter OKX data, authentication timestamps, trading behavior, time-zone
  behavior, release scripts, deployment, or generated model files.
- Do not commit or push.

## 6. Technical Design

### 6.1 Navigation preference model and compatibility

Modify `lib/core/navigation/navigation_preferences.dart`:

- Add `buttonScale` and `buttonOpacity` fields.
- Set defaults to `1.0` and `0.5`.
- Add the typed option records used by Settings.
- Encode the fields into the existing version-1 JSON record:

  ```json
  {"version":1,"mode":"bar","edge":"bottom","buttonScale":1.0,"buttonOpacity":0.5}
  ```

- Decode missing fields as defaults so records written by the previous build
  preserve their mode and edge.
- Treat non-numeric, non-finite, or out-of-range values as the field default;
  preserve valid sibling fields. Continue falling back to the complete default
  for malformed JSON or unsupported record versions.
- Include both fields in `copyWith`, equality, hash code, and diagnostics.

The existing `NAVIGATION_PREFERENCES` key and controller write serialization
remain the single source of truth. Add controller setters for size and opacity;
they use the same optimistic update/rollback path and disable only navigation
controls while a write is pending.

### 6.2 Fixed navigation rendering

Modify `TradingNavigationBar` and its host call site:

- Accept `buttonScale` and `buttonOpacity` as required rendering inputs.
- Derive visual target/indicator sizes, icon size, title metrics, and the
  unselected vertical offset from the normalized scale while keeping the
  interactive slot at least 48 pixels.
- Keep all unselected icon centers on one horizontal line and keep the selected
  title centered under its icon.
- Use `surfaceColor.withValues(alpha: buttonOpacity)` for the selected circle;
  leave the bar surface and contour painter on the opaque theme surface color.
- Keep the current animation controller and reduced-motion behavior, driving
  scaled geometry from the same progress so size changes do not detach the
  crest or title.
- Preserve the real hit bounds above the bar and the painter's transparent
  pass-through region.

### 6.3 Floating navigation rendering

Modify `FloatingNavigationButtons` and its host call site:

- Accept the same scale and opacity values.
- Scale target slots, circle sizes, label slots, gaps, and icon/title metrics,
  with a minimum 48-pixel interactive target.
- Recompute horizontal/vertical fit and the existing same-axis scroll fallback
  from the scaled dimensions; keep all five destinations reachable at small
  viewports.
- Apply the configured alpha to each button surface and selected label surface;
  keep ordinary gaps hit-test transparent and retain tooltips/semantics.
- Recompute anchors on text-scale, size, inset, rotation, and keyboard changes
  without changing the saved edge.

### 6.4 Application text-scale module

Create a small core module, for example
`lib/core/typography/app_text_scale.dart`, containing:

- an immutable option catalog and `normalize` helper;
- `appTextScaleProvider`, defaulting to `1.0`;
- a helper that combines the platform baseline scale with the selected app
  multiplier for `MediaQuery`.

Modify `SecureStorageHelper` and `WebStorageHelper`:

- Add `APP_TEXT_SCALE`, `getAppTextScale()`, and `saveAppTextScale(...)`.
- Native storage uses secure storage; Web uses its existing
  `SharedPreferences` instance and surfaces a failed `setString`.
- Normalize missing, malformed, non-finite, or unsupported values to `1.0`.

Modify `main.dart` and `TradingBalanceApp`:

- Read the text scale with a safe default before `runApp`; keep this read
  independent enough that a storage failure cannot prevent app startup.
- Override `appTextScaleProvider` in the production `ProviderScope`.
- Make `TradingBalanceApp` watch the provider and wrap the app child in a
  copied `MediaQuery` whose `textScaler` is the platform baseline multiplied
  by the selected app scale.

Modify `SettingsScreen`:

- Hydrate the provider along with existing settings without replacing a newer
  value selected by the user while the asynchronous load is pending.
- Add a `Cỡ chữ ứng dụng` dropdown with key
  `settings-app-text-scale-select`.
- Add `Kích thước nút` and `Độ trong suốt nút` dropdowns with keys
  `settings-navigation-size-select` and
  `settings-navigation-opacity-select`.
- Keep these controls readable at narrow widths by using concise selected
  labels and one control per row. They remain available in both navigation
  modes; the floating-edge row remains conditional as it is today.
- Update providers immediately, disable only the relevant control during its
  write, persist the value, and restore the previous value with a Vietnamese
  error SnackBar if the write fails.

## 7. Affected Files

### Create

- `docs/agents/specs/2026-09-06-navigation-appearance-preferences-design.md`
- `lib/core/typography/app_text_scale.dart`
- `test/core/typography/app_text_scale_test.dart`
- `tasks/task_16_navigation-appearance-preferences.md`

### Modify

- `docs/agents/plans/2026-09-06-navigation-appearance-preferences.md`
- `lib/core/navigation/navigation_preferences.dart`
- `lib/core/navigation/navigation_preferences_provider.dart`
- `lib/core/navigation/navigation_presentation_host.dart`
- `lib/core/navigation/trading_navigation_bar.dart`
- `lib/core/navigation/floating_navigation_buttons.dart`
- `lib/core/security/secure_storage_helper.dart`
- `lib/main.dart`
- `lib/features/settings/presentation/settings_screen.dart`
- `test/core/navigation/navigation_preferences_test.dart`
- `test/core/navigation/navigation_preferences_provider_test.dart`
- `test/core/navigation/floating_navigation_buttons_test.dart`
- `test/core/security/biometric_auth_default_test.dart`
- `test/features/settings/settings_navigation_preferences_test.dart`
- `test/widget_test.dart` (or a focused navigation widget test file if the
  existing root tests are cleaner to extend)

## 8. Verification Matrix

| Area | Required evidence |
| --- | --- |
| Preference compatibility | Old mode/edge-only JSON decodes with scale `1.0` and opacity `0.5`; new records round-trip; malformed and out-of-range fields fall back safely. |
| Controller behavior | Size/opacity setters preview immediately, serialize one write at a time, and roll back after a failed write. |
| Fixed rendering | Default selected indicator alpha is `0.5`; selected/unselected icons remain aligned; scaled first/middle/last controls retain hit targets and transparent surroundings. |
| Floating rendering | Scale and opacity affect button visuals; all four edges preserve ordering, minimum targets, labels, compact scrolling, and keyboard/inset behavior. |
| Settings | Three new selectors render without narrow-width overflow, update the corresponding provider, persist values, and show rollback feedback. |
| Text scaling | `TradingBalanceApp` combines platform and app scale; all app text responds after a provider change; root startup restores persisted Web/native values. |
| Storage | `APP_TEXT_SCALE` round-trips on Web and invalid/missing values normalize to default; existing keys remain unchanged. |
| Regression | Existing navigation mode/edge, timezone, currency, order, portfolio, and widget tests continue to pass. |
| Quality | Formatting, analyzer review, focused/full tests, `git diff --check`, and final diff review complete. |

## 9. Risks and Controls

- **Fixed-bar geometry overflow:** limit presets to the defined range, retain a
  48-pixel interactive slot, and test 320-pixel and desktop widths.
- **Opacity reduces contrast over page content:** keep theme-derived icon/title
  colors, preserve tooltips/semantics, and make the opaque bar/contour the
  visual anchor in fixed mode.
- **Older persisted records:** keep version 1 and default only missing/invalid
  new fields rather than discarding valid mode/edge values.
- **Async Settings hydration overwrites a new choice:** only hydrate while the
  provider still has its initial value, or use an explicit loaded guard; add a
  delayed-storage regression test.
- **Text scaler recursion or lost system accessibility:** compute the platform
  baseline from the pre-override `MediaQuery` in `MaterialApp.builder` and
  multiply it once.
- **Out-of-order writes:** reuse the existing navigation controller's single
  in-flight guard and add an equivalent guard for text-scale writes.
- **Web persistence appears successful but is not durable:** check the boolean
  result of `SharedPreferences.setString` and throw on failure.

## 10. Acceptance Criteria

- The default fixed selected circle is visibly translucent with alpha `0.5`,
  while the navigation bar/shoulders remain one opaque full-width surface.
- Settings exposes working selectors for navigation button size, navigation
  button opacity, and app text size; each change applies immediately and is
  persisted on native and Web backends.
- Size changes preserve minimum 48-pixel targets, unselected alignment, labels,
  insets, edge anchoring, and constrained scrolling in both navigation modes.
- App text-size changes affect the complete app through the root text scaler
  and preserve the platform accessibility scale.
- Missing/legacy/invalid persisted values use safe defaults without changing
  existing mode/edge or unrelated preference records.
- Failed saves roll back to the last confirmed value and provide recoverable
  feedback; no stale asynchronous load overwrites a newer user selection.
- Focused tests, full tests, analyzer review, formatting, and diff checks are
  run and their observed results are recorded in the new task checklist.
