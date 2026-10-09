# Task 107 — Startup loading and page continuity

Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE
Plan: docs/agents/plans/2026-10-09-forms-loading-direction.md
Specification: docs/agents/specs/2026-10-09-forms-loading-direction-design.md
Plan Steps: P03
Requirements/Acceptance: REQ-004/005 / AC-004/005
Frontend Level: F2
Frontend Design Brief: docs/agents/specs/2026-10-09-forms-loading-direction-frontend-brief.md
Predecessors: T106 = PASS

## Contract and scope

Allowed writes: lib/main.dart; new lib/core/widgets/app_startup.dart and app_page_transition.dart (or equivalent named source helpers); lib/core/navigation/main_navigation_shell.dart; web/index.html presentation markup/CSS/first-frame listener only; test/widget_test.dart, main startup/biometric/background tests, test/core/navigation and new widget tests. Theme pageTransitionsTheme may change only after T106 completed and if needed for Navigator continuity. No protected configuration/platform files, custom bootstrap config, dependencies, backend or other feature screen edits.

runApp immediately with real pending initialization UI; isolate current safe preference/storage restoration into testable async initializer. Preserve ProviderScope overrides, independent fallbacks, biometric requirement and background retirement. Failure outside recoverable preference reads shows safe retry without exposing account UI or logging secret values. No fake delay. Web static markup shows startup before engine, removes on Flutter first-frame; reduced-motion CSS and Flutter static/labeled loading. Existing bootstrap/base/manifest settings unchanged.

Destination transition 140/220ms opacity, zero when disableAnimations or accessibleNavigation. Preserve NavigationPresentationHost stable content state on preference-only edits. Rapid taps interrupt; outgoing page must not remain interactive/semantic-active nor keep late read behavior alive just for a fade. Prefer fade-in current destination rather than double mounted outgoing screens. Existing Navigator route behavior gets consistent reduced-motion-respecting transition if not already satisfied.

## Verification

RED-107 then GREEN-107: delayed/failing init never renders uninitialized app; retry safe; reduced-motion startup static; rapid nav and settings appearance edits retain correct identity/read guards. GREEN delayed init handoff creates initialized app exactly once, preserves overrides/biometric gate; destination and route transition completes. V3 ceiling startup/navigation/widget and affected tests. Real loading/mobile/desktop render evidence where possible. Buildability: flutter build web --no-pub after last executable edit. External config actions none.

No docs/tasks/telemetry/git changes or agents. RTK first eligible output, raw exact narrow exception. Stop for missing contract or protected dependency. Return exact commands/results/order, test/build/render paths and route metadata. Audit PENDING.


Observed caller extension FE107005: allowed lib/core/navigation/trading_navigation_bar.dart and its tests; floating_navigation_buttons.dart/tests only if needed to align both accessibility flags. Required real-shell test exposed preexisting duration-zero AnimatedSize label restarting its animation inside layout (RenderAnimatedSize.performLayout -> forward -> markNeedsLayout assertion). Minimal static label under reduced motion, normal animation otherwise; preserve bar interactions/selected state and page identity. Both motion flags must stop selection animation. Retain real-bar shell coverage; floating-only replacement does not satisfy the defect. Add affected existing bar/floating tests to V3. User-authorized full UI/motion scope includes this necessary caller fix; no protected configuration or approval expansion.



Final shared webbuildexit0 afterlastcode/tests closes taskbuildgate; finalauditPASS and532FluttertestsPASS. Exactevidence coordinatoraudit.
