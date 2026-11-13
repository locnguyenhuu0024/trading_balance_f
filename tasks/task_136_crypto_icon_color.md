# Task 136 — Coin icons in original color

Status: READY
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6.1-terra
Target Effort: low
Target Route: gpt-6.1-terra / low
Routing Policy: EXECUTOR_ROUTING_POLICY.json v2 (OptCodex v1.4.0)
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Plan: `docs/agents/plans/2026-11-13-crypto-icon-color.md`
Plan Steps: P06
Decisions: D-018

## 1. Dispatch Compliance

The CCB dispatcher passes `--model gpt-6.1-terra` and `model_reasoning_effort=low` on your command line, and your prompt states the route. This is the explicit binding. `UNVERIFIABLE` is a valid state; do not stop for it.

Dispatch Route Status: UNVERIFIABLE
Requested Model: gpt-6.1-terra
Requested Effort: low

## 2. Objective

`CryptoIcon` shows coin logos in their original colors.

Done when: W20 from the plan passes, and V3 passes.

## 3. Preconditions

Predecessors: T135 = PASS (82652df). Clean checkout.

## 4. Allowed Scope

- `lib/core/widgets/crypto_icon.dart`
- `test/features/crypto_icon_urls/crypto_icon_url_test.dart`

## 5. Forbidden Scope

- Do not read or change protected configuration, `backend/` or Git state.
- Do not change the palette, URLs, the fallback chain, the letter fallback or any other file.

## 6. Executor Contract

1. In `crypto_icon.dart`, replace the `ColorFiltered(colorFilter: const ColorFilter.matrix([...]), child: Image.network(...))` expression with that same `Image.network(...)` expression, unchanged. Nothing else changes.
2. In `crypto_icon_url_test.dart`, add `import 'package:flutter/material.dart';` and, inside the existing group, a `testWidgets('network icon keeps original colors', …)` that pumps `MaterialApp(home: Center(child: CryptoIcon(symbol: 'BTC', size: 24, backgroundColor: Colors.white, textColor: Colors.black, textSize: 12)))`, then expects `find.byType(ColorFiltered)` findsNothing and `find.byType(Image)` findsOneWidget. Pump once only, then `await tester.pumpWidget(const SizedBox.shrink());`.

## 7. External Configuration / Environment Actions

None.

## 8. Tests

- TEST-136-1 (W20): the new widget test.

## 9. Mandatory Verification

### RED — RED-136
Scenario: the new test on the code before the change.
Command: `flutter test --no-pub test/features/crypto_icon_urls/crypto_icon_url_test.dart`
Expected: fails because `ColorFiltered` is found.
Status: PENDING

### GREEN — GREEN-136
Scenario: the same command after the change, then V3 `flutter test --no-pub test/features/crypto_icon_urls test/features/orders test/features/portfolio test/features/market`.
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
