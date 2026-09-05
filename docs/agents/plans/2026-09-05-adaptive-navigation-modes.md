# Implementation Plan: Adaptive Navigation Modes

**Date:** 2026-09-05

**Status:** Implemented; verification completed

**Design:** [Seamless Selection and Floating Navigation](../specs/2026-09-05-adaptive-navigation-modes-design.md)

**Execution ledger:** [Task 11](../../../tasks/task_11_adaptive-navigation-modes.md)

## 1. Objective and Constraints

Implement the spec's fixed-bar shoulder contour and an optional five-button floating presentation at four selectable edges. Preferences must apply live and persist on native and Web backends.

Preserve the existing fixed-bar default, 60-pixel bar footprint, same-color selected crest, square outer corners, five destinations, selected-only labels, and unselected icon alignment. Keep the transparent area around the raised contour and avoid an input-blocking overlay.

This is the single canonical implementation plan. Earlier completed tasks and their documents are historical. The plan was approved and implemented through Task 11.

## 2. Affected Components

New file names below define the proposed component boundaries; implementation may consolidate small helpers without changing responsibilities or adding dependencies.

| File or area | Planned work |
| --- | --- |
| `lib/core/navigation/navigation_destination_data.dart` | Move the existing five destination descriptors into shared data used by both renderers. Preserve a compatibility alias if needed for existing callers. |
| `lib/core/navigation/navigation_preferences.dart` | Typed modes/edges, defaults, equality, versioned JSON decoding and encoding. |
| `lib/core/navigation/navigation_preferences_provider.dart` | Seeded controller state, immediate preview, single in-flight save, rollback and error state. |
| `lib/core/navigation/navigation_geometry.dart` | Pure shoulder paths/progress and floating placement/clearance calculations. Split into two focused helpers if necessary. |
| `lib/core/navigation/trading_navigation_bar.dart` | Replace the circle/rectangle junction with a unified silhouette and synchronized animation. |
| `lib/core/navigation/floating_navigation_buttons.dart` | Edge-aware button layout, selected title, local Material feedback, focus and compact scrolling fallback. |
| `lib/core/navigation/navigation_presentation_host.dart` | Navigation layer with real paint/hit bounds, fixed reservation, mode transitions, and route-local layering. |
| `lib/core/navigation/navigation_content_frame.dart` | Always-present page-body integration for measured content bounds and edge clearance; no-op outside the shell. |
| `lib/core/navigation/main_navigation_shell.dart` | Consume preferences, retain selection/page identity, select the active renderer and supply shared layout context. |
| `lib/core/security/secure_storage_helper.dart` | Dedicated native read/write methods for `NAVIGATION_PREFERENCES`. |
| `lib/main.dart` | Implement Web overrides and load the record before `runApp`; seed the new provider. |
| `lib/features/settings/presentation/settings_screen.dart` | Appearance subsection, typed controls, saving/error feedback, stable form state and content frame. |
| Portfolio, Orders, Market, and BMAG screen files | Add only the content-frame/clearance integration needed for safe floating placement. |
| `lib/features/orders/presentation/widgets/responsive_order_grid.dart` | Change only if scroll-content insets must be forwarded here; retain the current width-to-column resolver. |
| `test/core/navigation/`, `test/core/security/`, `test/features/settings/`, `test/widget_test.dart` | Behavioral coverage described below. |

There is one new local preference key. No API/schema migration, package upgrade, code generation, deployment, or release-script change is planned.

## 3. Ordered Work Packages

### P1. Preference Model, Storage, and First-frame State

1. Add `NavigationDisplayMode`, `NavigationEdge`, and immutable `NavigationPreferences` with `bar`/`bottom` defaults.
2. Encode a single record with `version: 1`, `mode`, and `edge`. Implement tolerant decoding as specified; never rewrite storage during reads.
3. Add `getNavigationPreferences` and `saveNavigationPreferences` to the native helper and override both in `WebStorageHelper`. Check failed Web writes rather than assuming a resolved future means success.
4. Keep the new record separate from `saveAppPreferences`, avoiding changes to the existing theme/currency/biometric signature and unrelated mocks.
5. Add a seeded provider/controller with confirmed values, current values, saving state, and recoverable error state. Only one save may be active; optimistic changes roll back on failure.
6. Load navigation preferences in startup using an independent guarded read, then initialize the provider before rendering the first shell. Do not make Settings responsible for hydration.

**Validation:** Model round trips and field fallbacks; native/Web reads and writes; failed writes; default initialization; retained last edge; existing preference/credential keys unchanged. This establishes AC-08/09 and the state foundation for AC-05/07.

### P2. Shared Destinations and Stable Navigation Host

1. Share the existing destination labels/icons with both presentations; preserve `_selectedIndex` and the existing destination builder seam.
2. Keep the active page in one stable widget slot while changing navigation mode, position, padding, or keyboard geometry. Do not create a new all-page IndexedStack or duplicate active data subscriptions.
3. Introduce a route-local host whose layout includes raised controls. A practical arrangement is a stable page Scaffold plus a transparent Stack layer, with a layout-only bottom reservation in fixed mode.
4. Reserve only 60 plus the bottom safe inset for the fixed bar. Give the navigation interaction layer enough real space for the crest without adding that space to the page reservation.
5. Paint backgrounds and handle input in appropriately scoped children. Decorative layers return no hit outside their shape; no full-screen Material/GestureDetector absorbs ordinary page interaction.
6. Put page overlays below Navigator menus/dialogs and preserve a single active semantics tree during visual transitions.

**Validation:** A stateful injected page retains identity and text/scroll state across presentation changes; crest and empty-area pointer probes; exactly one navigation callback per tap. Covers AC-02/04/07 and part of AC-10/11.

### P3. Seamless Fixed-bar Rendering

1. Build a pure path function from bar bounds, circle radius, rise progress, destination centers, and available shoulder widths.
2. Join the flat top edge to the circular core with tangent-continuous cubic shoulders on both sides. Clamp the shoulders for first/last cells and narrow viewports without shifting icons.
3. Fill bar and contours in a unified path with the existing theme-derived surface color. Preserve square outer bar corners and a transparent region outside the path.
4. Use one coordinated animation source for contour rise, icon position, and selected-title transition. Rapid taps retarget from the current progress; reduced motion goes directly to the final state.
5. Preserve current public navigation keys where they still represent real controls. Replace implementation-specific color-widget assertions with behavior/paint assertions where the renderer changes.

**Validation:** Render a contrasting patterned page beneath the bar. Check painted shoulder pixels, preserved background pixels beside the crest, and input at those positions; inspect rendered output for seam-free joins. Exercise first/middle/last selection and rapid retargeting. Covers AC-01–04/12.

### P4. Four-edge Floating Buttons

1. Implement a bounded floating group from shared destinations, current selection, available body rectangle, saved edge, text measurements, and system/keyboard constraints.
2. Use horizontal rows at top/bottom and vertical columns at left/right, keeping order stable. Render per-button backgrounds/shadows and selected-only labels as defined in the spec.
3. Add minimum target sizes, theme contrast, tooltip/full semantic names, keyboard focus and Enter/Space activation.
4. Recompute placement on window/keyboard changes. Use already-resized body geometry or explicit keyboard subtraction once. Keep top/side controls clear of the active AppBar.
5. Implement gap reduction and bounded same-axis scrolling when the chosen edge cannot fit all targets; make the active item visible after resize/edge changes.
6. Ensure ordinary empty gaps pass pointer events through. Limit scroll capture to the compact fallback's actual viewport.

**Validation:** Four edge placements and correct ordering; selected titles; navigation callbacks; tap-through gaps; reduced motion; keyboard overlap; small-window fallback; focus and target sizes. Covers AC-06/10/12.

### P5. Settings and Content Integration

1. Add the two typed selects in the appearance section, with the edge field conditional on floating mode. Keep the layout readable at compact widths.
2. Wire changes to the dedicated controller, disabling only navigation preference controls while saving and displaying inline failure feedback with rollback.
3. Add an always-present `NavigationContentFrame` around each destination body. Keep each screen's existing Scaffold, AppBar, data logic, and controllers.
4. Supply the outer body geometry before navigation clearance to the host, notifying only on geometry changes, and apply necessary edge clearance to fixed headers/forms and list start/end padding. Avoid a measurement feedback loop and do not assume the explicit existing list paddings consume MediaQuery adjustments automatically.
5. Ensure the last Portfolio/Market/BMAG item, Orders filters/cards, and Settings save button can be reached at each edge. Continue calculating Orders columns from the final usable width.
6. Check Settings API-save Snackbar placement and BMAG dialogs with the floating overlay active. Any adjustment stays limited to overlay clearance/layering.
7. Confirm that toggling mode/edge inside Settings preserves active destination, entered text, scroll state, and other appearance choices.

**Validation:** Settings interaction and simulated storage failure; a delayed existing key-load future must not overwrite navigation choices; all-screen clearance smoke tests with fixture data. Covers AC-05/07/09/11.

### P6. Integrated Verification and Review

1. Complete the focused verification matrix below using deterministic fixtures and local storage doubles.
2. Format the touched Dart files. Run focused tests during development, followed by one full `flutter test` and `flutter analyze` after integration.
3. Compile `flutter build web --release --no-wasm-dry-run` and `flutter build macos --release`. Observe actual completion and exit status; resume running command sessions instead of launching duplicate builds.
4. Inspect real rendered navigation on mobile-sized, tablet-sized, and desktop-sized views with both themes. Verify all five edge/mode combinations: fixed bottom plus four floating edges.
5. Review the final tracked/untracked diff for scope, state retention, storage compatibility, transparent input handling, animation cost, and accessibility. Re-run only checks affected by subsequent edits or failures.
6. Record results and any limitation in Task 11 before marking it complete and immutable. Report the implementation without committing, pushing, or running `release_build.sh`.

## 4. Verification Matrix

| Area | Essential scenarios | Evidence |
| --- | --- | --- |
| Preference decoding | Missing record; valid records; malformed JSON; unsupported version; unknown field values | Unit tests for normalized typed results. |
| Persistence | Both backends; restart/recreated provider; remembered edge; failed save; competing input during save | Storage/controller tests, including existing key preservation. |
| Startup | Stored floating/left appears on first frame; existing read failure does not bypass navigation read | Startup-state integration with injected storage; no authenticated network access. |
| Fixed shape | First/middle/last destination; narrow/wide widths; shoulders; no opaque strip | Focused paint/pixel tests plus rendered visual inspection, not only `getRect`. |
| Fixed interaction | Raised button receives a tap; transparent neighbor reaches a page target | Hit-test widget probes with an instrumented page. |
| Floating edges | Correct anchor, orientation, order, label, selected state for all four edges | Widget tests using layout bounds and destination callbacks. |
| State retention | Edit a Settings field and change navigation style/edge; scroll stays consistent | Integration test on a stable stateful page and Settings. |
| Insets and keyboard | Non-zero top/side/bottom safe insets; keyboard at bottom; rotation | Simulated MediaQuery/view changes with all targets visible/reachable. |
| Small windows | 320x568 portrait; 568x320 landscape; constrained side groups | No overflow; same-edge scroll fallback reaches all five destinations. |
| Large views | 768x1024 tablet; 1440x900 desktop | Centered bounded floating groups; fixed bar still full width. |
| Accessibility | Light/dark; 2x text scale; reduced motion; keyboard focus; semantics | Focus/semantics/target tests and visual inspection of focus/label bounds. |
| Content and overlays | Representative Portfolio, Orders, Market, BMAG, Settings content; BMAG dialog; Settings save feedback | Fixture-based reachability tests and manual smoke observations. |

Proposed focused test files include `navigation_preferences_test.dart`, `navigation_preferences_provider_test.dart`, `navigation_preferences_storage_test.dart`, `trading_navigation_bar_test.dart`, `floating_navigation_buttons_test.dart`, and `settings_navigation_preferences_test.dart`. Extend the existing shell and root widget tests for integration. Consolidate related cases instead of duplicating assertions across files.

If visual image fixtures are needed, keep them limited to representative shoulder/transparency regressions and use deterministic rendering. Do not generate a large per-device golden-image collection.

## 5. Dependencies and Ordering

The model/storage/controller work (P1) defines the contract used by the host (P2) and Settings (P5). Both renderers (P3/P4) use shared destinations and the host's geometry contract. P5 completes integration and content clearance before final verification (P6).

Execution is coordinated within this task. There is no requested subagent delegation.

## 6. Main Risks and Controls

| Risk | Required control |
| --- | --- |
| Paint looks correct but raised taps fail or reach the page | Real layout bounds for raised targets; pointer tests above the flat bar. |
| A transparent full-screen painter captures input | Explicit non-hit decorative layers and tap-through regression tests. |
| Settings remount loses pending API input | Stable page/widget position; no mode-dependent key; retention test. |
| Web settings appear saved but disappear on reload | Override both navigation storage methods in WebStorageHelper; recreate-provider/backend tests. |
| Reads/writes restore stale state | Startup hydration once; a single in-flight navigation save; confirmed-state rollback. |
| Floating controls cover filters, AppBars, or the last action | Measured content bounds plus explicit edge-aware body/list clearance; all-page reachability checks. |
| Narrow side layouts affect card columns | Compute breakpoints after clearance and verify narrow views using existing fixtures. |
| Keyboard inset applied twice | Choose a single inset owner and test resized body geometry. |
| Animated shoulders rebuild live pages | Navigation-local controller/repaint boundary and stable active page. |
| Build/runtime environment unavailable | Report the exact skipped check; do not equate passing geometry tests with visual/native validation. |

## 7. Compatibility and Rollback

Existing installs continue with the fixed bottom presentation. The new local record has no migration or remote dependency. Users can switch back to fixed mode in Settings while retaining the last floating edge.

If a code rollback is later authorized, remove only this feature's implementation changes. The unused preference record may remain; older code ignores it. No credential deletion, preference reset, Git history rewrite, or production redeploy is part of rollback by default.

## 8. Completion Definition

Implementation is complete when AC-01 through AC-12 in the linked specification have evidence, required checks have observed results, the final diff matches this scope, and Task 11 is updated with verification outcomes and locked. The current planning deliverable does not claim any new runtime behavior or test results.
