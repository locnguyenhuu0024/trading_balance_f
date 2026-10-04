# All Trade Card Header Order Audit
Date: 2026-10-04
Tasks: T81, T82
Branch: main
Verdict: PASS (header scope)

## Acceptance / Scope
AC-001/002: pending instrument flex5 group left, side/leverage flex2 group right; compact label and pending body/footer untouched. Focused geometry 3 passed; earlier presentation/cancellation 41 passed. T81 unrelated indentation finding AUD-001 restored; final T81 build exit0.
AC-003/004: history and position icon/compact pair/type group left and side/leverage right. Position LONG/SHORT/VI THE semantics, side badge and missing-leverage placeholder retained. History state remains visible in body. All underlying IDs, action behavior, metadata/body/footer content preserved. Red close-all style unchanged.
Source diff independently inspected: changes limited to card header helper/header code and former history body side label now state. Geometry tests/expected display updates match compact labels, fixture IDs remain unchanged. No diagnostic instrumentation remains. Final selected diff check exited0; status changes fully explained by source/tests and coordinator documents/telemetry.

## Verification
T82 RED: `flutter test test/features/orders/presentation test/features/orders/position_actions_test.dart test/features/orders/order_cancellation_flow_test.dart --no-pub`, exit1, 70 passed/3 expected old-header failures before source changes.
T82 GREEN/regression: same command, exit0, 73 passed.
Task/final repository build: `flutter build web --release --no-pub`, exit0 after final source/test edits; no executable edits followed. Fresh exact executor build evidence reused. Existing Wasm/Cupertino font warnings did not prevent build.
Position full-page geometry covers320/1,375/1.3,430/2 across LONG/SHORT/NET plus missing type/leverage. Pending/history tests and action/cancellation regression preserved.
Known unrelated limitation: full-page position320px/scale2 has a51px RenderFlex overflow in unchanged DropdownButtonFormField<OrderTab> InputDecorator (order-tab-select), outside card header. Header geometry itself passed; no filter source changed or error suppressed. That full-page scenario is not claimed fixed; scoped header acceptance remains PASS.

## Safety / Routing
No protected configuration/manifests content accessed or changed. Native tool consumption opaque. SDK cache bootstrap permission failures recovered via raw escalated retries. No external configuration action.
T81 explicit E0 gpt-6-luna/high and T82 explicit E1 gpt-6-luna/xhigh; effective routes unexposed (UNVERIFIABLE). Terminal results adopted, no immediate follow-ups; runtime has no release/close primitive.
No commit/push/deployment performed for this refinement.
