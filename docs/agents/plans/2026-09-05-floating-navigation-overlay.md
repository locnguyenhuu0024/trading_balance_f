# Floating Navigation Overlay

**Status:** Implemented; verification completed

## Objective

Correct floating navigation so the button group is a true overlay that does not consume page layout space, while preserving fixed-bar clearance, edge anchoring, touch behavior, and accessibility.

## Current Behavior and Root Cause

`NavigationPresentationHost` already renders `FloatingNavigationButtons` as a `Positioned` child above the full-size destination in a `Stack`. However, `NavigationContentFrame` adds 80 pixels of horizontal-edge padding or 88 pixels of side padding whenever floating mode is active. Every destination screen wraps its body in this frame, so the page is resized before the overlay is painted.

## Scope

- Make floating mode return the child without layout padding.
- Retain fixed-bar body reservation and safe-area handling.
- Update regression tests and comments to describe overlay semantics.
- Preserve the current overlay placement, per-button surfaces, selection animation, semantics, and compact scrolling behavior.

## Non-goals

- Do not redesign button geometry, colors, labels, or edge preferences.
- Do not remove system-inset adjustments from the floating group's own `Positioned` anchors.
- Do not change destination screen data logic or the completed Task 11 checklist.
- Do not add deployment or release-script changes.

## Implementation Steps

1. Simplify `NavigationContentFrame` so only fixed-bar mode applies bottom clearance; floating mode returns the destination child unchanged.
2. Replace the outdated floating-clearance comments and focused test expectations with all-edge no-padding assertions while retaining fixed-mode coverage.
3. Run formatting on touched Dart files and execute focused navigation tests, then the full test suite and analyzer if the focused checks pass.
4. Review the diff for accidental layout or hit-test changes, update Task 13, and report without committing or pushing.

## Verification Strategy

- `flutter test test/core/navigation/navigation_content_frame_test.dart test/core/navigation/navigation_presentation_host_test.dart test/core/navigation/floating_navigation_buttons_test.dart`
- `flutter test`
- `flutter analyze`
- Inspect widget sizes/padding for all four floating edges and fixed mode under non-zero bottom inset.

## Risks and Controls

- Content can be visually covered by floating controls; this is intentional, so button surfaces must remain opaque and their own hit bounds must stay intact.
- Removing padding could expose content under system UI if the overlay anchor is changed accidentally; retain the existing `viewPadding`/`viewInsets` calculations in `FloatingNavigationButtons`.
- Existing destination tests may rely on frame padding only through the focused frame test; update that contract explicitly rather than altering individual screens.

## Acceptance Criteria

- In floating mode at top, bottom, left, and right, `NavigationContentFrame` does not change the child's constraints or padding.
- The destination page remains full-size and the floating group is rendered above it in the host stack.
- Fixed mode still reserves the navigation bar footprint and bottom safe inset.
- Focused tests, full tests, and analyzer pass, or any environment limitation is reported with its exact result.

## Verification Results

- `flutter test test/core/navigation/navigation_content_frame_test.dart test/core/navigation/navigation_presentation_host_test.dart test/core/navigation/floating_navigation_buttons_test.dart`: passed, 12 tests.
- `flutter test`: passed, 56 tests.
- `flutter analyze`: no analyzer errors; command reported 12 pre-existing informational lints in unrelated files and exited non-zero because the project treats those infos as findings.
- `git diff --check`: passed.
- The combined release script was not run because it performs a production Vercel deployment.
