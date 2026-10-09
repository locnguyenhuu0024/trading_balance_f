# Decisions: Forms, motion and automatic strategy direction

Status: ACTIVE
Specification: docs/agents/specs/2026-10-09-forms-loading-direction-design.md
Plan: docs/agents/plans/2026-10-09-forms-loading-direction.md

## User decisions

- D-001: The user explicitly delegates unresolved design choices and requests execution after planning. Present the concrete plan, then execute without another approval round. This direct instruction overrides the baseline's later approval-message timing requirement for this task only.
- D-002: Create a new branch; commit and push completed reviewed code. No deployment or live exchange writes are authorized by this request.

## Authorized assumptions

- A-001: Preserve the existing monochrome theme, system font, app text-scale preference and 48px touch targets. Improve all current forms with shared sizing and responsive layout rather than introduce a new visual identity.
- A-002: Automatic direction is an allowed-side scope: Long permits only long/support candidates; Short permits only short/resistance candidates; Long&Short permits both, preserving the existing ability to materialize a qualified subset. Omission means both. Existing margin semantics remain 100% for one executable side and the current split for two.
- A-003: Startup loading tracks actual initialization, with no artificial timer. Native loading begins with the first Flutter frame; HTML loading covers web engine bootstrap. OS-native launch artwork and packaging are outside scope because they require protected platform/build configuration.

Authorization: user message granting independent proposals and implementation after planning. No material questions remain.

## D-003 — Preserve native Apple route gestures

During T107 independent review, local Flutter SDK evidence showed a plain fade builder on iOS/macOS removes Cupertino back-gesture detector. Adopt native Cupertino delegation on these platforms, with stable subtree topology and settled animations when either accessibility motion flag is true. This is a compatibility refinement within user-authorized independent design choices. Destination fade remains140ms everywhere; other platforms use exact220ms forward/reverse route fades. No extra approval or dependency/config changes.
