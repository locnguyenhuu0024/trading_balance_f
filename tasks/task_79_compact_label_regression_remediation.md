# Task 79 — Pending label regression remediation
Status: PASS
Agent Role: implementation_executor
Executor Class: E0
Target Model: gpt-6-luna
Target Effort: high
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE
Plan: docs/agents/plans/2026-10-04-compact-pending-instrument-label.md
Finding: AUD-001
Reuse: same explicitly bound E0 executor for immediate remediation.

Allowed write: test/features/orders/presentation/orders_screen_position_layout_test.dart, existing pending/history loop around lines 450-510 only. Define expected display based on tab: pending BTCUSDT; history BTC-USDT-SWAP. Use for card finder and text assertion. Keep fixture instId and all other assertions unchanged. No product edits.
RED evidence: predecessor regression 40 pass/1 failure, unchanged fixture on final product.
GREEN: flutter test test/features/orders/presentation test/features/orders/order_cancellation_flow_test.dart --no-pub, 41 pass required.
Final build after final executable test change: flutter build web --release --no-pub.
Protected boundary applies. No config/Git/docs/telemetry changes. No external action.
Return exact verification/build status and protected confirmation.
Coordinator audit PASS.

Final acceptance/scope: PASS. Final regression 41/41 passed; final `flutter build web --release --no-pub` exit 0 after final test edit. No protected access/write or external action.
