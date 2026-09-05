# Design Specification: Seamless Selection and Floating Navigation

**Date:** 2026-09-05

**Status:** Implemented; verification recorded in Task 11

**Canonical plan:** [Adaptive Navigation Modes](../plans/2026-09-05-adaptive-navigation-modes.md)

**Execution checklist:** [Task 11](../../../tasks/task_11_adaptive-navigation-modes.md)

## 1. Intended Outcome

Support two navigation presentations with the same five destinations and selection state:

1. **Fixed bar:** a full-width, square-edged bottom bar. The selected circular icon rises above it and blends into its top edge through two smooth lateral shoulders.
2. **Floating buttons:** five separate buttons positioned together along the top, bottom, left, or right edge of the application's usable content area. The user chooses this mode and its edge in Settings.

The existing fixed bottom bar remains the default. Floating mode initially uses the bottom edge. Preferences apply immediately and survive an application restart or browser reload.

## 2. Inspected Repository Context

| Component | Current behavior | Design implication |
| --- | --- | --- |
| `lib/core/navigation/trading_navigation_bar.dart` | Five destinations; a 60 logical-pixel bar; a 46-pixel circle whose selected top is at -16; separate rectangular and circular fills | Replace the abrupt circle-to-rectangle junction with a continuous silhouette. |
| `lib/core/navigation/main_navigation_shell.dart` | Owns `_selectedIndex`; supplies one active destination and one bottom navigation bar | Keep a single owner of selection and add presentation switching around the active page. |
| `lib/features/settings/presentation/settings_screen.dart` | Contains appearance controls, Riverpod state, automatic preference saves, and API text controllers | Add typed navigation controls without remounting Settings or resetting its form. |
| `lib/core/security/secure_storage_helper.dart` | Persists native preferences through `FlutterSecureStorage` | Add a dedicated navigation preference record. |
| `lib/main.dart` | Loads startup preferences; defines `WebStorageHelper` using `SharedPreferences` | Implement the new preference in both storage paths and hydrate it before the first shell frame. |
| Destination screens | Each has its own `Scaffold`/AppBar; list bodies use explicit padding; Orders also has fixed filter controls | Floating placement must respect AppBars and explicitly handle content clearance. Changing `MediaQuery.padding` alone is insufficient. |
| Existing navigation tests | Check destinations, colors, dimensions, and indicator bounds | Add actual paint and pointer coverage; bounds alone cannot prove transparency or usability. |

The working tree was clean when inspected. Tasks 01–10 are historical and remain unchanged.

## 3. Fixed Bar: Seamless Selected Shape

### 3.1 Geometry

All measurements below are logical pixels at the default text scale.

| Property | Target |
| --- | --- |
| Bar width | Full viewport width; backgrounds extend to the sides, controls respect system side insets. |
| Bar content height | 60; bottom system-safe padding is additional and is not part of this height. |
| Bar outer corners | Square. |
| Selected circular core | 46 diameter; top protrudes 16 above the flat bar edge. |
| Unselected icon centers | On one line, 30 below the bar's flat top edge. |
| Shoulder reach | Initially about 12 beyond each side of the circular core, reduced when necessary to fit the destination slot and screen edge. |
| Surface | The bar, circular core, and shoulders share one opaque theme-derived fill. |

The shoulder is a curved transition, not an enlarged oval. On each side, a concave curve joins the circle's upper contour to the horizontal bar edge. Curve tangents align at the joins so neither a corner nor a thin seam is visible.

Construct a shared path for the bar and raised contours and paint it as one silhouette. Do not add an independent shadow, outline, or differently colored seam between the selected core and the bar. A transparent interaction layer may sit above this painted surface.

At the first and last destinations, reduce the shoulder reach within the available cell. Keep the icon centered over its destination and the circular core undistorted. The painted path must remain inside the screen horizontally.

### 3.2 Transparency and Layout Contract

- The fixed bar reserves **60 plus bottom safe inset** in the page layout. Its 16-pixel crest is visual overlap, not additional reserved height.
- Above the flat top edge, only the crest and its two shoulders are filled. All surrounding pixels reveal the actual page beneath.
- No rectangular background, scrim, blur panel, or opaque Material may cover the transparent region around the crest.
- Taps in that transparent region reach the underlying page. A tap on the visible raised button is handled by that navigation destination rather than a page control beneath it.
- Paint geometry and interaction geometry are separate responsibilities: `Clip.none` alone does not make overflowing widgets receive taps.

### 3.3 Selection and Animation

- Retain the existing upward/downward selection motion with a target duration of 220 ms and an ease-out curve.
- Drive icon elevation and shoulder geometry from the same selection progress. The previous contour settles into the bar as the new contour rises; at rest there is exactly one raised contour.
- Intermediate contours may coexist during the transition but must remain joined to the bar. They must not become detached circles or cover an entire horizontal strip.
- On rapid repeated selections, continue from the current visual progress toward the newest selection.
- Only the selected title is visible inside the bar. It remains centered under its icon, contrasted against the surface, and does not move the unselected icons.
- Respect reduced-motion settings by applying the final geometry without the movement animation.

## 4. Floating Button Mode

### 4.1 Presentation

The proposed interpretation of “a floating row of buttons” is five separate circular button surfaces, with no shared bar or pill behind them. This is a configurable in-app overlay, not an operating-system overlay.

- Preserve destination order: Trang chủ, BMAG, Lệnh, Thị trường, Cài đặt.
- Use 52-by-52 target slots with a minimum interactive size of 48-by-48. Start with a 44-pixel unselected circle and a 52-pixel selected circle.
- Keep approximately 8 pixels between target slots and a minimum 12-pixel gap from the usable edge, after system insets.
- Use a restrained shadow on each button. Selection is indicated by the larger circle, filled icon, and selected-only title; it must also have semantic selected state.
- In a horizontal row, show the selected title toward the interior of the screen: below the row at the top, above it at the bottom. In a vertical column, place the selected title directly below its icon inside the active item. Titles remain horizontal.
- Measure the title as part of the group's layout. Allow the active vertical item to grow along the column; do not overlap adjacent buttons. For long or enlarged text, constrain the visual title to the safe viewport and provide the full label through tooltip and semantics.
- Position changes animate within the available content rectangle. During mode transitions, only the active presentation receives input or exposes navigation semantics.

### 4.2 Edge Mapping

“Top” means the top of the usable page body, immediately below the active page's AppBar. It must not obscure the title, back button, balance visibility action, or system status area.

| Saved edge | Arrangement | Anchor | Reading order |
| --- | --- | --- | --- |
| `top` | Horizontal row | Top center, below AppBar and safe inset | Left to right |
| `bottom` | Horizontal row | Bottom center, above home indicator or keyboard | Left to right |
| `left` | Vertical column | Left center of usable body | Top to bottom |
| `right` | Vertical column | Right center of usable body | Top to bottom |

These are physical edges; choosing left or right is not automatically reversed by text direction. V1 positioning is selected in Settings, with no drag gesture or free-form coordinates.

### 4.3 Content and Pointer Behavior

- Floating mode removes the fixed bottom bar and its reserved space. The page background extends behind the floating group.
- Only buttons and their local labels/shadows are painted. Ordinary gaps and the surrounding overlay pass pointer events to the page.
- The overlay belongs to the main route and sits below dialogs, dropdown menus, and modal sheets.
- Apply edge-aware clearance inside page content where required to protect fixed controls and to make the final scroll item/action reachable. This is content padding, not a painted navigation lane.
- Explicitly integrate this clearance in the five screen bodies. Protect Portfolio summary controls, Orders filters, and Settings form actions as well as scrollable lists; do not rely solely on automatic ListView safe padding.
- Compute Orders breakpoints from the usable width after any side clearance, using the existing responsive column rules.
- Ensure feedback such as the Settings save Snackbar remains visible and actionable above or clear of the overlay.

Floating buttons necessarily cover their own occupied pixels. The guarantee is that no full-screen/edge scrim is added, ordinary empty areas remain interactive, and essential content controls do not become permanently hidden.

### 4.4 Small Viewports, Rotation, and Keyboard

Use available layout constraints, system insets, measured labels, and the active AppBar/body geometry rather than device-type detection or a hard-coded global toolbar height.

1. Recompute the anchored group on resize, rotation, or text-scale changes; preserve the saved edge and selected destination.
2. Move the bottom group above the visible keyboard and fit side groups into the remaining body area. Use the body's already-resized bounds or explicit keyboard insets once, not both.
3. If all five targets cannot fit along the chosen edge, reduce inter-item gaps to a minimum of 4 pixels, retaining accessible target sizes.
4. If they still cannot fit, use a bounded one-axis scrollable group on that same edge. Keep the active item visible and allow all five destinations to be reached. Do not silently persist a different edge or remove destinations.
5. Only in that compact scrolling fallback, gestures inside the small scroll viewport are owned by the navigation group. Areas outside it still pass through.

## 5. Settings Experience

Add a “Thanh điều hướng” subsection within “HIỂN THỊ & GIAO DIỆN”.

| Control | UI text | Values | Behavior |
| --- | --- | --- | --- |
| Display-mode select | “Kiểu hiển thị” | “Thanh cố định”, “Nút nổi” | Always visible. |
| Floating-edge select | “Vị trí nút nổi” | “Trên”, “Dưới”, “Trái”, “Phải” | Visible only in floating mode. |
| Helper text | “Thay đổi được áp dụng và lưu tự động.” | — | Explains that a separate save action is unnecessary. |

Use typed dropdown values so these controls cannot be confused with the existing currency dropdown in tests or persistence code. At narrow widths, labels and fields may stack instead of overflowing a ListTile trailing area.

When the user selects a value:

1. Keep Settings active and update the navigation presentation immediately.
2. Save the complete navigation preference record. Disable just the two new selects while this save is in flight to prevent out-of-order writes.
3. On success, retain the selected presentation and re-enable controls.
4. On failure, restore the previous confirmed navigation preference and show an inline message: “Không lưu được tùy chọn điều hướng. Vui lòng thử lại.”

Changing the mode or edge must preserve the Settings scroll position, API text controllers, and unsaved form contents. The state holder for the active page must not be replaced with a different subtree just because the navigation presentation changed.

Switching back to the fixed bar preserves the last chosen floating edge. Returning to floating mode restores that edge. Navigating between destinations continues to follow the existing screen lifecycle; caching all five pages is not part of this change.

## 6. Preferences and Startup

### 6.1 Domain Values

- `NavigationDisplayMode`: `bar`, `floating`.
- `NavigationEdge`: `top`, `bottom`, `left`, `right`.
- Immutable `NavigationPreferences`: display mode and saved floating edge.
- Default: `bar` plus `bottom`.

### 6.2 Storage Contract

Store both values in one versioned JSON string under the new key `NAVIGATION_PREFERENCES`:

```json
{"version":1,"mode":"bar","edge":"bottom"}
```

- Native backend: add read/write methods to `SecureStorageHelper`.
- Web backend: override both methods in `WebStorageHelper`, using its existing `SharedPreferences` instance. A Web write reporting failure must be surfaced to the caller.
- Use the same encoder/decoder for both backends. Do not allow Web to fall through to the native secure-storage implementation.
- Missing record: default settings. Invalid JSON or unsupported version: default settings. Invalid mode/edge within version 1: default the invalid field while preserving any valid field.
- Reads do not rewrite storage. Existing installations need no migration or reset.
- Navigation writes affect only this new key. Theme, currency, biometric options, balance visibility, and credentials retain their existing storage contract.

### 6.3 Ownership and Hydration

Read the navigation preference before `runApp`, seed a dedicated navigation preference controller/provider, and use its state for the first authenticated shell frame. Guard this read independently so an unrelated existing preference-read failure does not skip navigation hydration.

The same controller serves Settings and the shell. Entering Settings must not reload and overwrite this navigation state from a stale asynchronous `_loadSavedKeys` call. Defaults also work in tests that construct the shell without production startup.

Treat these as device/browser-local display preferences. No server synchronization, account preference API, new package, generated code, or change to authentication is required.

## 7. Rendering and Integration Design

Separate the implementation into shared destination data, typed preferences/controller, fixed-bar geometry/rendering, floating-button rendering, and a shell presentation host.

The host should provide a stable active-page subtree plus a navigation layer whose real layout bounds include the raised crest or floating buttons. Fixed-mode page reservation remains 60 plus safe inset even if the interaction layer extends above it. Decorative painters must explicitly pass through hits outside their intended shape.

A small, always-present content frame in each page body supplies usable body geometry and applies required clearance. Report the outer body rectangle before applying navigation clearance; using the padded child's bounds would create a placement/measurement feedback loop. Notify the host only when that rectangle changes. In a screen rendered without the main navigation shell, the frame behaves as a no-op. It must not create another Scaffold or duplicate existing AppBars.

Use Flutter's existing painting, animation, layout, and Riverpod facilities. A `CustomPainter` and a pure geometry helper are sufficient for the shoulders; bitmap assets and third-party navigation packages are unnecessary.

Keep animation rebuilds/repaints local to the navigation area. Live prices and expensive page bodies must not be rebuilt on every animation tick. Keep one semantic destination per item; decorative titles/painters do not introduce duplicate labels.

## 8. Theme and Accessibility

| App theme | Fixed surface / shoulders / floating buttons | Icon and title foreground |
| --- | --- | --- |
| Light | Black | White |
| Dark | White | Black |

Retain system-theme following through the existing theme provider. A visible title outside a button uses a small matching label surface so its contrast does not depend on market/chart colors beneath it.

- All destinations have tooltips, accessible names, button roles, and selected state.
- Support keyboard focus with a visible focus indicator and Enter/Space activation. Focus order follows destination order for each orientation.
- Keep at least 48-by-48 targets, no transparent full-screen pointer barrier, and one active navigation semantics tree during transitions.
- Check normal and enlarged text, reduced motion, and light/dark appearance. If layout must grow for text accessibility, measure and fit it without reducing target sizes.

## 9. Acceptance Criteria

| ID | Observable result |
| --- | --- |
| AC-01 | Fixed mode has visibly smooth left/right shoulders; the crest, shoulders, and bar read as one surface without seams. |
| AC-02 | The fixed bar remains full-width and square-edged with a 60-pixel content footprint; crest surroundings reveal the page. |
| AC-03 | Unselected fixed icons remain aligned; only the active title appears; selection remains coherent during rapid taps. |
| AC-04 | A tap on the raised selected button is handled by navigation; taps beside its shape reach the page. |
| AC-05 | Settings exposes both modes and four floating edges with the specified conditional controls. |
| AC-06 | Floating mode shows five separate buttons in the correct orientation and order, with no old bottom bar. |
| AC-07 | Edge/mode changes apply immediately while preserving the active Settings page, scroll position, and unsaved API fields. |
| AC-08 | Both native and Web storage restore choices after restart/reload; missing or malformed records fall back safely. |
| AC-09 | Failed saves restore the confirmed value and display recoverable feedback; no competing writes or unrelated preference changes occur. |
| AC-10 | Insets, AppBars, keyboard, rotation, and narrow windows keep navigation reachable; transparent gaps pass through except the documented compact scroll fallback. |
| AC-11 | Essential controls and final scroll items remain reachable on all five screens; menus, dialogs, and save feedback are usable. |
| AC-12 | Theme contrast, reduced motion, focus/keyboard operation, enlarged text, and semantic selection work in both modes. |

## 10. Scope Boundary

Implementation covers navigation rendering, local settings/storage/startup integration, lightweight page-content clearance, and meaningful regression coverage. It does not redesign the five destination pages, change trading behavior, reorder destinations, implement drag positioning or auto-hide gestures, alter the release script, or deploy builds.

The separate-button interpretation, fixed-bar default, initial bottom edge, and top placement below the AppBar are proposed product decisions for this plan. They are explicit so the plan can be reviewed without guessing how “floating” or “four edges” will behave.

## 11. Framework References

`Stack.clipBehavior` governs painting but does not extend the stack's pointer bounds; the host must account for raised buttons in its interaction layout. [Flutter Stack documentation](https://api.flutter.dev/flutter/widgets/Stack/clipBehavior.html), [RenderBox hit testing](https://api.flutter.dev/flutter/rendering/RenderBox/hitTest.html).

A decorative background painter can otherwise participate in hit testing over its whole area. Explicit shape/pass-through handling is required for the transparent portions. [CustomPainter hit testing](https://api.flutter.dev/flutter/rendering/CustomPainter/hitTest.html).

Use actual safe-area and viewport information, avoiding duplicate inset application when nested widgets already consume it. [Flutter SafeArea and MediaQuery](https://docs.flutter.dev/ui/adaptive-responsive/safearea-mediaquery).
