# Design Specification: Monochrome Minimalism

Status: IMPLEMENTED
Date: 2026-10-03
Tier: M
Decision Ledger: ../decisions/2026-10-03-monochrome-decisions.md

## Objective and observed state
Remake every Flutter screen and overlay using a reusable monochrome design system. Before implementation, `lib/main.dart` supplied only a blue-seed light theme; older screens managed colors independently and newer screens inherited Material themes. There are eight main destinations and subordinate detail screens, dialogs and risk views.

## Requirements and acceptance
- REQ-001 / AC-001: Light and Dark themes use only neutral grayscale colors, with white/near-black backgrounds, readable text, thin borders and consistent moderate radii. New screens inherit component themes.
- REQ-002 / AC-002: Explicit theme preference and live system brightness agree across root, screens, navigation and overlays.
- REQ-003 / AC-003: All existing presentation surfaces adopt semantic palette/tokens; preserve signs, direction/status labels and warning icons. Candles distinguish rising/falling through hollow/filled bodies and direction descriptions.
- REQ-004 / AC-004: Preserve navigation preferences, callbacks, validation, authentication, data precision, currency/timezone, payloads and business flow. Responsive layout and scrollable overlays remain usable with compact viewport and large text.

## Design contract
Add `lib/core/theme/app_theme.dart`: `AppPalette.of(BuildContext)`, `AppPalette.forBrightness(bool isDark)`, getters `background`, `surface`, `raised`, `ink`, `muted`, `border`, `positive`, `negative`, `warning`, `onStrong`; strong action background is `ink`. `AppTokens` provides shared spacing, radius and motion constants. `AppTheme.light` and `.dark` define explicit neutral schemes, typography with tabular figures, and inherited component themes for inputs, buttons, cards, dialogs, sheets, menus, selection, controls, feedback and progress. Use existing sans-serif resources; no dependency/configuration edits.

Add `lib/core/theme/platform_brightness_provider.dart` with reactive `platformBrightnessProvider`; retain existing `isDarkModeProvider` import compatibility and wire system mode to it. Color-filter coin imagery only; never filter the entire app. Preserve existing navigation geometry/keys/preferences and pure black/white navigation surfaces. Migrate hardcoded colors locally with correct paired foreground/background roles. Maintain contrast of at least 4.5:1 for body/secondary text. Ordinary supporting text should be at least 12 logical pixels where natural-height/scrolling layout supports it; dense chart axes/time labels may remain compact. Use 48-pixel primary touch targets without breaking dense data layouts.

## Invariants, edges and failure semantics
INV-001: No backend/domain/data/provider contract changes, except reactive visual brightness resolution.
INV-002: No protected configuration content access or writes; no external service, dependency installation, deployment, commit or push.
EDGE-001: System brightness changes while app stays open update root and legacy screens; explicit mode overrides platform changes.
EDGE-002: Empty/loading/error/disabled state labels and actions remain available.
EDGE-003: Small viewport, large text and keyboard preserve scrolling and action reachability.
Failure messages, retries and submit gating retain their existing behavior. Data/API/schema/performance changes: N/A.

## Verification and traceability
RED-001: Explicit dark mode with light platform must never produce a light root; system mode must not remain stale after a platform change.
GREEN-001: Root and legacy provider agree in Light, Dark and live System mode; monochrome palette and text contrast tests pass.
RED-002: Gains/losses, long/short, severity and candle direction must remain distinguishable without color.
GREEN-002: Existing feature tests plus focused presentation tests prove callbacks, numerical formatting and layout retain behavior.
REQ-001/002 -> AC-001/002 -> P01 -> T66 -> RED/GREEN-001.
REQ-003/004 -> AC-003/004 -> P02/P03 -> T66 -> RED/GREEN-002.
Final gate: affected test suite, permitted source inspection and `flutter build web --no-pub` after last executable change. Report visual evidence limits honestly.

## Rollout and rollback
Local source change only; restore only task-owned source/test files if regression requires rollback. No persistence migration or external configuration action.
