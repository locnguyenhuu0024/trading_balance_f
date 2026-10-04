# Task 80 — Red close-all button
Status: PASS
Plan: docs/agents/plans/2026-10-04-red-close-all-button.md#P01
Agent Role: implementation_executor
Executor Class: E0
Target Model: gpt-6-luna
Target Effort: high
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE

Implement AC-001/002 exactly. Local style only for TradeAccountControls close-all TextButton.icon. Reuse PnlColors.lightNegative/darkNegative via import; select actual theme brightness. Add red foreground and BorderSide(color:red,width:1); preserve existing button type/dimensions/disabled logic and prior uncommitted work. Disabled text may dim via disabledForegroundColor red with alpha .38; outline red remains.
Allowed writes: lib/features/orders/presentation/widgets/trade_account_controls.dart close-all styling/import only; test/features/orders/position_actions_test.dart focused close-all assertions/test, minimal theme helper input as needed. No other files.
Meaningful RED before source edit then GREEN; focused existing action suite. Final Flutter build web --release --no-pub after final executable edit. Exact commands/results required.
Protected config/manifests/locks forbidden reads/writes. No Git mutations, child agents, telemetry/doc/task writes. RTK first when eligible; SDK bootstrap permission raw retry as necessary. No external services. Return evidence and protected-boundary confirmation. Effective route unknown unless exposed.
Coordinator audit PASS.

RED: targeted color assertion exit 1 on old styling. GREEN: position_actions_test.dart 30 passed, exit 0. Final flutter build web --release --no-pub exit 0 after final source/test edit.
