# Small Change Plan: Red close-all button
Status: COMPLETE
Date: 2026-10-04
Tier: S

## Objective / P01
Give authenticated position close-all button red text/icon and red 1px outline while retaining existing design, 48px hit target, shape/padding, tooltip/label and all authentication/operation/action conditions.
OBS: TradeAccountControls uses TextButton.icon foreground palette.warning, monochrome and no explicit side.
AC-001: when close-all is shown, enabled foreground and outline resolve to red (light #B42318 / dark #F87171, reuse existing PnlColors constants). Determine brightness from Theme.of(context).brightness. Apply local TextButton style only; shared palette remains unchanged. Disabled foreground may be dim red; preserve onPressed null conditions. No new fill required.
AC-002: no changes to close-all logic, availability, confirmation, pending controls, other buttons or earlier pending-card work.
Allowed: close-all local styling/import in lib/features/orders/presentation/widgets/trade_account_controls.dart; test/features/orders/position_actions_test.dart existing close-all fixture/tests only with minimal theme helper parameter if required.
Single material frontend workstream; fanout required NO; required/actual reasoning 0/0; EXCEPTION/SINGLE_MATERIAL_WORKSTREAM. Coordinator C1 fixed runtime.
RED: inspect resolved foreground/side via existing close-all fixture before source change; red expectation should fail. GREEN: same assertion after source change passes, including light/dark if helper supports it.
Regression: flutter test test/features/orders/position_actions_test.dart --no-pub.
Task/final build gate YES, Flutter web app: flutter build web --release --no-pub after final executable edit.
No external configuration/action. User authorized autonomous choices/execution after planning; this requested local refinement is authorized.
T80 E0 gpt-6-luna/high, explicit binding, no parent inheritance.
