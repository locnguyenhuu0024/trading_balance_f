# Task 122 — T116 remediation R01: Settings gate and proof of hidden actions

Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6.1-terra
Target Effort: low
Target Route: gpt-6.1-terra / low
Routing Policy: EXECUTOR_ROUTING_POLICY.json v2 (OptCodex v1.4.0)
Route Rationale: Removing one wrong condition and adding focused tests with explicit expected behavior.
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-11-07-multi-platform-view-only-design.md`
Plan: `docs/agents/plans/2026-11-07-multi-platform-view-only.md`
Plan Steps: P01
Requirements: REQ-002, REQ-012
Acceptance Criteria: AC-002
Ledger Task ID: T122 (separate remediation contract for T116)

## 1. Dispatch Compliance

Spawn with both Target Model and Target Effort explicitly supplied. Omitting either or inheriting a route is prohibited.

Dispatch Route Status: PENDING
Requested Model: PENDING
Requested Effort: PENDING
Observed Effective Model: unavailable
Observed Effective Effort: unavailable

## 2. Objective

Resolve AUD-116-01 and AUD-116-02 in `tasks/task_116_view_only_fixed_navigation.md`.

Done when: with the gate false, `Ẩn số dư mặc định` and the biometric switch are visible and the backend entry is not; a real pending limit order and a real position show no backend controls.

## 3. Preconditions

Predecessor: T116 attempt committed as work in progress so the checkout is clean.

## 4. Allowed Scope

- `lib/features/settings/presentation/settings_screen.dart`
- `test/core/backend_features_test.dart`

## 5. Forbidden Scope

Do not read or change protected configuration, `backend/` or Git state. Do not write any file not listed. No refactors.

Read access is not limited to the write surface. Non-protected source and tests may be read as needed, starting with:
- `test/features/orders/order_cancellation_flow_test.dart:22` (`OkxOrder` fixture) and `:101` (`OkxPosition` fixture)
- `test/features/orders/presentation/orders_screen_mobile_layout_test.dart:51` (`orderTabProvider` override)
- `lib/features/orders/presentation/providers/order_cancellation_flow_provider.dart:44` (`isActiveLimitOrder`: limit type, state live or partially filled)

## 6. Executor Contract

1. In `settings_screen.dart`, remove the `backendFeaturesEnabled` condition from the card that holds `Ẩn số dư mặc định` and biometric switches, so it always renders. Keep the condition on the card holding `settings-trade-access-button`.
2. In `backend_features_test.dart`, extend the Settings test: both switches present for gate true and false.
3. In the same file, add an Orders test using one active limit order on the pending tab and one position on the positions tab. With the gate false, expect no `OrderCancellationControl` and no `TradeAccountControls`, and the rows themselves still visible. With the gate true, expect both controls present.

## 7. External Configuration / Environment Actions

Planned action: none.

## 8. Tests

- TEST-122-1: Settings switches independent of the gate.
- TEST-122-2: Orders rows with and without the gate.

## 9. Mandatory Verification

### RED — RED-122
Scenario: TEST-122-2 with the gate true must find `OrderCancellationControl` on the active limit order and `TradeAccountControls` on the positions tab, and with the gate false must find neither while both rows stay visible. Show it can fail by first asserting the controls absent with the gate true.
Command/method: `rtk flutter test --no-pub test/core/backend_features_test.dart --plain-name '<name>'`
Expected: the deliberately inverted assertion fails with the gate true, proving the fixture really renders the controls. TEST-122-1 RED already observed in attempt 1.
Actual: PENDING
Status: PENDING

### GREEN — GREEN-122
Scenario: TEST-122-1 and TEST-122-2 after step 1.
Command/method: `rtk flutter test --no-pub test/core/backend_features_test.dart`
Expected: all pass.
Actual: PENDING
Status: PENDING

Verification ceiling: V2 for this file, then V3 for `test/features/settings`.

### Task Buildability Gate

Required: YES
Affected canonical build unit: Flutter app `lib/` and `test/`
Exact secret-free build command: `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub`
Result: PENDING

## 10. Stop Conditions

Return `BLOCKED` if a fix needs any other file.

## 11. Execution Ledger

- [ ] confirm route binding
- [ ] execute RED, then implement, then GREEN
- [ ] run buildability gate after last change
- [ ] return compact executor report

## 12. Coordinator Audit

Attempt 7872ecba73cf4370806f91f3cdfb7ce2: REWORK. Step 1 and the Settings part of step 2 are correct and verified by the coordinator (250 tests, analyzer 0 errors, web build pass). Step 3 was not done: the original section 5 read as forbidding reads outside the write surface, which is a contract defect, not a route failure, so the route is unchanged.

Remaining for the next attempt: step 3 only. Do not redo steps 1 and 2.

Attempt b176ff4524174194bdb75d2d963b4972: dispatcher REVIEW_REQUIRED, write surface in scope. The test renders a real active limit order and a real position in `OrdersScreen`, for gate false and true, and both rows stay visible. The executor reported the inverted assertion failing with the gate true (RED) before the final test passed; the test structure is consistent with that, and coordinator-observed tests pass. Coordinator-observed: V3 set 251 passed, analyzer 0 errors, web build pass.
Dispatch route compliance: UNVERIFIABLE (requested gpt-6.1-terra/low, explicit).
Parent route inheritance: NO
Task buildability gate: PASS
Verdict: PASS. AUD-116-01 and AUD-116-02 closed.
