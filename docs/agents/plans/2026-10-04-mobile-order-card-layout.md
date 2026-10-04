# Small Change Plan: Mobile order card layout
Status: COMPLETE
Date: 2026-10-04
Tier: S

## Objective
Keep pending order cards compact and readable on phones within the current monochrome design.

## Evidence and Scope
OBS-001: orders_screen.dart:_buildOrderCard switches body to stacked columns below 380px; _buildNotionalRow also stacks below effective width 380px.
Allowed: _buildOrderCard and order-only helpers in lib/features/orders/presentation/orders_screen.dart; focused order-card widget regression tests.
Preserve: history cards, position cards, formatting, masking, currency modes, cancellation/authentication behavior, grid, navigation, palette, borders and button actions.
Protected configuration is unreadable/non-writable; no configuration action required.
A-001: User authorized autonomous choices and execution after successful planning. Apply the requested header to pending order cards only, per user clarification. History cards must remain unchanged. Right group contains coin icon, full instrument identifier, instrument type; left group contains MUA/BÁN and optional leverage. Preserve order state in a compact body row.

## Planning Workstreams
Frontend order-card layout: material, atomic single workstream. Backend/data/security: non-material, unchanged.
Fan-out Required: NO; required/actual planning reasoning agents: 0/0.
Fan-out Compliance: EXCEPTION; skip reason: SINGLE_MATERIAL_WORKSTREAM.
Coordinator route: C1; runtime main selection fixed, effective route unavailable.

## Implementation Step — P01
AC-001: Header places side/leverage left and coin/instrument/type right. No wrapping or truncation of ordinary identifiers at phone widths.
AC-002: Body uses explicit single-line rows for timestamp, state, price, quantity and notional. Label and value remain on same row; dual currency may occupy its existing two amount lines. Use locally constrained scale-down only when content exceeds row width; preserve full values and semantics, never ellipsis numeric content. No fixed card height.
AC-003: Current footer cancellation widget and actions remain intact; pending, buy/sell, missing leverage/type/notional, hidden balances and dual currency remain supported.
AC-004: No layout overflow at widths 320/375/390/430px, text scales 1/1.3/2, light/dark; retain desktop grid behavior at 1200px.
Implement an order-specific notional row without altering shared position behavior. Keep existing typography/styles, card padding/radii. Responsive fitted rows can shrink only when necessary. Retain timestamp/timezone and price/quantity formatting unchanged.
Tests: focused geometry/value/overflow tests in test/features/orders/presentation/orders_screen_mobile_layout_test.dart plus existing order presentation/cancellation tests.
RED: boundary missing notional/leverage/type and large-number/dual-currency fixtures run first, assert no exception/full value presence and correct same-row geometry; meaningful pre-fix reproduction preferred.
GREEN: regular SUI pending order at listed sizes/scales, assert header left/right geometry and same-line label/value placement; footer retained.
Verification ceiling V2: focused new and existing order presentation/cancellation groups; no full suite.
Task Buildability Gate: YES. Canonical unit: Flutter web app.
Exact build command: flutter build web --release --no-pub
Final repository build gate: same canonical web build, reusable after final source changes; no deployment.
Stop if protected config or scope expansion is required.

## Task and Approval
T77 implements P01. E1, gpt-6-luna/xhigh, explicit binding, parent inheritance forbidden.
User's current request explicitly preauthorizes execution after planning and autonomous choices; no additional approval required.
External Verification: none anticipated.
External Configuration / Environment Action: none.
