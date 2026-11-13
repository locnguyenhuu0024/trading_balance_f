# Task 135 — Hide "Chưa đầy đủ" on Assets

Status: READY
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6.1-terra
Target Effort: low
Target Route: gpt-6.1-terra / low
Routing Policy: EXECUTOR_ROUTING_POLICY.json v2 (OptCodex v1.4.0)
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Plan: `docs/agents/plans/2026-11-13-assets-hide-partial-label.md`
Plan Steps: P05
Decisions: D-017

## 1. Dispatch Compliance

The CCB dispatcher passes `--model gpt-6.1-terra` and `model_reasoning_effort=low` on your command line, and your prompt states the route. This is the explicit binding. `UNVERIFIABLE` is a valid state; do not stop for it.

Dispatch Route Status: UNVERIFIABLE
Requested Model: gpt-6.1-terra
Requested Effort: low

## 2. Objective

The Assets page does not show `Chưa đầy đủ`. Other screens and the specific failure lines are unchanged.

Done when: W18 and W19 from the plan pass, and V3 passes.

## 3. Preconditions

Predecessors: T134 = PASS (071edd9). Clean checkout.

## 4. Allowed Scope

- `lib/core/widgets/account_state_view.dart`
- `lib/features/portfolio/presentation/portfolio_screen.dart`
- `test/features/connections/account_state_test.dart`

## 5. Forbidden Scope

- Do not read or change protected configuration, `backend/` or Git state.
- Do not change Orders, the details screen, or how `isPartial` is computed.
- No file outside the list.

## 6. Executor Contract

1. In `PartialAccountNotice`, add `this.showPartialLabel = true` to the const constructor and a `final bool showPartialLabel` field. Change `if (account.isPartial) const Text('Chưa đầy đủ')` to `if (account.isPartial && showPartialLabel) const Text('Chưa đầy đủ')`. Nothing else changes.
2. In `portfolio_screen.dart`, add `showPartialLabel: false` to the existing `PartialAccountNotice(...)` call. Nothing else changes.
3. In `account_state_test.dart`, inside `partial wallet results on … proxy=…`, change `expect(find.text('Chưa đầy đủ'), findsOneWidget);` to `expect(find.text('Chưa đầy đủ'), details ? findsOneWidget : findsNothing);`. Nothing else changes.

## 7. External Configuration / Environment Actions

None.

## 8. Tests

- TEST-135-1 (W18/W19): the updated loop covers home (hidden) and details (shown), with both proxy values.

## 9. Mandatory Verification

### RED — RED-135
Scenario: the updated test on the code before the change.
Command: `flutter test --no-pub test/features/connections/account_state_test.dart`
Expected: the `home` cases fail because `Chưa đầy đủ` is found.
Status: PENDING

### GREEN — GREEN-135
Scenario: the same command after the change, then V3 `flutter test --no-pub test/features/connections test/features/portfolio test/features/orders`.
Expected: all pass.
Status: PENDING

Verification ceiling: V3.

### Verification environment

The executor sandbox cannot run `flutter test` or compile. Write the complete change. Report `red` and `green` as `NOT_RUN` with the tests named in RED then GREEN order. Set `buildability` to `BLOCKED` with that reason, and `status` to `COMPLETED`.

### Task Buildability Gate

Required: YES
Exact secret-free build command: `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub`
Result: PENDING

## 10. Stop Conditions

Return `BLOCKED` if the change needs a file outside the list.

## 11. Coordinator Audit

Verdict: PENDING
