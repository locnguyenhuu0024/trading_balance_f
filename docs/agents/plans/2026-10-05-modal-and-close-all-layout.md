# Small Change Plan: Modal body and compact close-all control
Status: COMPLETE
Date: 2026-10-05
Tier: S

## Objective / P01
AC-001: Strategy details render directly inside the modal scroll body, without the outer detail Card or its 16px padding. Keep one body padding (20px horizontal, 4px top, 16px bottom), scrolling, contents and actions.
AC-002: Positions close-all is a 48x48 icon button alongside status/type filters, red 1px outline and foreground in light/dark themes, RoundedRectangleBorder with AppTokens.radiusMedium, existing warning icon, tooltip and accessible label. No visible text label. Narrow screens retain one row without overflow.
AC-003: Preserve authentication/configuration visibility, busy/unresolved-position-action disabling, confirmation flow, messages and operation lookup. Only one TradeAccountControls instance owns the positions action/state. Pending/history behavior remains intact.

Evidence: _StrategyDetailContent wraps its Column in Card/Padding(16); modal separately pads its scroll view. OrdersScreen builds filters above body and positions TradeAccountControls inside each body branch; close-all is TextButton.icon.
Allowed source: lib/features/strategy/presentation/strategy_screen.dart; lib/features/orders/presentation/orders_screen.dart; lib/features/orders/presentation/widgets/trade_account_controls.dart. Tests: test/features/strategy/strategy_screen_test.dart; test/features/orders/position_actions_test.dart; test/features/orders/order_filter_controls_test.dart; relevant existing orders screen tests if needed.
Implementation: remove detail wrapper; add optional filterControls slot to TradeAccountControls and render filters Expanded plus compact close-all in one Row. Move positions TradeAccountControls to screen filter area and remove body duplicates. Without slot retain standalone close-all support for existing callers/tests. Put messages below row, avoiding doubled horizontal padding when used in toolbar.
One material frontend workstream; backend/data/config non-material and unaffected. Fan-out required NO; required/actual reasoning 0/0; SINGLE_MATERIAL_WORKSTREAM. Optional handoff skipped due bounded mechanical evidence. Coordinator C1, fixed current runtime, effective route unavailable.
Task T83, E1 gpt-6-luna/xhigh, explicit route, no inheritance. Single serial task; no predecessors.
RED: new focused widget expectations fail against old layout before product changes. GREEN: same expectations pass after implementation; prove no outer Card in modal, single-row icon position/size/shape and preserved disabled/confirmation flows. Use existing fixtures; verification ceiling V2 relevant files.
Task and final build gates YES: Flutter root app; flutter build web --release --no-pub after last executable change. No config read/write; tools may consume config opaquely. No external service/verification/configuration actions. User explicitly authorized proposed answers and execution after planning on current main branch. No commit/push requested.
