# Floating Navigation Overlay Design

## Intent

When floating navigation is selected, the five navigation buttons are a visual and interactive overlay anchored to one screen edge. They must sit above the destination page without reserving a layout lane or changing the page's usable width/height. The fixed bottom navigation bar keeps its existing body reservation.

## Behavior

- `NavigationPresentationHost` owns the overlay layer in its existing `Stack`; the destination page remains the first, full-size child.
- Floating controls are positioned with `Positioned` and remain the only hit-testable region they visually occupy. Decorative gaps and the rest of the page pass pointer events to the destination.
- `NavigationContentFrame` is a no-op for floating mode. It applies bottom safe-area plus bar height only for fixed-bar mode.
- Content may visually continue beneath floating controls; this is intentional and matches the overlay presentation. The controls retain opaque per-button surfaces, labels, shadows, and contrast so covered content remains legible.
- Keyboard and system insets continue to affect the overlay's anchor position, but they do not become body padding in floating mode.

## Accessibility and Interaction

Each floating button keeps its semantic label, selected state, tooltip, minimum target, and keyboard activation. Removing body padding must not add a full-screen gesture detector or reduce the destination's hit-test area outside the actual buttons.

## Responsive Constraints

The existing horizontal/vertical group sizing and compact same-axis scrolling remain unchanged. Buttons may overlap page content at all four edges, including narrow windows; their own bounded group must still avoid system insets and remain usable.

## Verification Evidence

- Widget tests assert no floating padding for top, bottom, left, and right modes.
- Fixed mode still asserts the 60-pixel bar plus bottom inset reservation.
- Host tests verify the destination remains full-size behind a floating group and the overlay group is positioned above it.
- Run focused navigation tests, the full Flutter test suite, and analyzer as appropriate; no production deployment is required.
