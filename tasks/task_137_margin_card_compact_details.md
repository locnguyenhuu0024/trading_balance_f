# Task 137 — Compact Margin card details, 2 decimals

Status: PASS
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6.1-terra
Target Effort: medium
Target Route: gpt-6.1-terra / medium
Routing Policy: EXECUTOR_ROUTING_POLICY.json v2 (OptCodex v1.4.0)
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Plan: `docs/agents/plans/2026-11-13-crypto-icon-color.md`
Plan Steps: P07
Decisions: D-019, D-020

Not dispatched for remediation. The user granted a task-specific coordinator override for T137 / AUD-137-01 and AUD-137-02 (chat, 2026-11-13, "Cho Claude tự sửa"). Both come from contract gaps. The coordinator changed one test line and removed one import, and nothing else.

## 1. Dispatch Compliance

The CCB dispatcher passes `--model gpt-6.1-terra` and `model_reasoning_effort=medium` on your command line, and your prompt states the route. This is the explicit binding. `UNVERIFIABLE` is a valid state; do not stop for it.

Dispatch Route Status: UNVERIFIABLE
Requested Model: gpt-6.1-terra
Requested Effort: medium

## 2. Objective

The part of `MarginAccountCard` under the divider is a compact table plus one summary line, and every number there uses 2 decimals.

Done when: W21–W23 from the plan pass, and V3 passes.

## 3. Preconditions

Predecessors: T136 = PASS. Clean checkout.

## 4. Allowed Scope

- `lib/features/orders/presentation/widgets/margin_account_card.dart`
- `test/features/orders/orders_binance_view_test.dart`

## 5. Forbidden Scope

- Do not read or change protected configuration, `backend/` or Git state.
- Do not change anything above the `Divider`: the header, PnL amount, %, `Lãi/lỗ ước tính` and `Giá vốn TB` lines.
- Do not change the constructor, `MarginAccountRow`, the estimate math, `orders_screen.dart` or any other file.
- No new dependency.

## 6. Executor Contract

1. Add a private top-level formatter `String _num(String? text)` in `margin_account_card.dart`:
   - `null` or empty returns `—`.
   - If `double.tryParse(text)` is null or not finite, return `text` unchanged.
   - `0` returns `0.00`.
   - If `|x| >= 0.01`, return `x.toStringAsFixed(2)`.
   - Otherwise (`0 < |x| < 0.01`), return `x.toStringAsFixed(d)`, where `d = (1 - (log10(|x|)).floor()).clamp(2, 8)`. Use `dart:math`'s `log(x) / ln10`. So `0.00123` gives `0.0012`.
2. Replace everything after the `Divider(...)` (the `if (isolated) …` / `else …` details and the `Mức ký quỹ`, `Giá thanh lý` and `Giá chỉ số` lines) with:
   - A `Table` with `columnWidths: {0: IntrinsicColumnWidth(), 1: FlexColumnWidth(), 2: FlexColumnWidth(), 3: FlexColumnWidth()}` and `defaultVerticalAlignment: TableCellVerticalAlignment.middle`.
     - Header row:
       - an empty `SizedBox.shrink()`;
       - then `Text('Net')`, `Text('Vay')`, `Text('Lãi vay')`, each right-aligned, fontSize 11, `palette.muted`.
     - Data rows:
       - Isolated: `[key.base ?? '—', row.baseNet, row.baseBorrowed, row.baseInterest]` and `[key.quote ?? '—', row.quoteNet, row.quoteBorrowed, row.quoteInterest]`.
       - Cross: `[row.asset ?? '—', row.net, row.borrowed, row.interest]`.
     - Cells:
       - The first cell is a bold `Text` at fontSize 12 in `palette.ink`, padded right 8.
       - Each number cell is its own `Text(_num(v), textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis)`, at fontSize 12 in `palette.ink`, with `fontFeatures: [FontFeature.tabularFigures()]`.
       - Add `Padding(vertical: 2)` around the cells.
   - `const SizedBox(height: 6)`.
   - A `Wrap(spacing: 4, runSpacing: 2)` of muted fontSize 12 `Text`s:
     - `'Mức ký quỹ ${_num(row.marginLevel)}'`;
     - if isolated, also `'·'`, `'Giá thanh lý ${_num(row.liquidation)}'`, `'·'`, `'Giá chỉ số ${_num(row.indexPrice)}'`.
3. Remove the now-unused `value` and `detail` helpers only if nothing else uses them. `detail` is still used above the divider, so keep it.
4. Tests in `orders_binance_view_test.dart`:
   - Line 408: change `find.textContaining('Lãi vay'), findsNWidgets(3)` to `findsNWidgets(2)`. Do not change anything else in that test.
   - Add `testWidgets('margin card details are compact with 2 decimals', …)` (W21). It pumps a `MarginAccountCard` with no estimate and the isolated SOL/USDT row from the plan:
     - `InstrumentKey(exchange: ExchangeId.binance, product: 'MARGIN', nativeId: 'SOLUSDT', base: 'SOL', quote: 'USDT')`.
     - It expects `find.text('1.03')`, `find.text('-53.70')`, `find.text('53.56')` and `find.text('0.18')` each `findsOneWidget`, and `find.text('0.00')` `findsWidgets`.
     - It expects `find.text('Mức ký quỹ 1.53')`, `find.text('Giá thanh lý 54.64')` and `find.text('Giá chỉ số 79.77')` each `findsOneWidget`.
     - It expects `find.text('Net')`, `find.text('Vay')` and `find.text('Lãi vay')` each `findsOneWidget`.
     - It expects `find.textContaining('1.031967')` and `find.textContaining('53.697')` to be `findsNothing`.
   - Add `testWidgets('margin card keeps tiny values and dashes', …)` (W22). It uses the same key, with `baseNet: '0.00123'` and `baseBorrowed` null. It expects `find.text('0.0012')` `findsOneWidget` and `find.text('—')` `findsWidgets`.
   - Do not delete or weaken other tests. The existing narrow 320 × text-scale-2 test (W23) must still pass.

## 7. External Configuration / Environment Actions

None.

## 8. Tests

- TEST-137-1 (W21), TEST-137-2 (W22): the new tests.
- TEST-137-3 (W23): the existing narrow test.
- The updated `Lãi vay` count at line 408.

## 9. Mandatory Verification

### RED — RED-137
Scenario: the new tests on the code before the change.
Command: `flutter test --no-pub test/features/orders/orders_binance_view_test.dart`
Expected: W21 and W22 fail (the raw `1.031967` is shown, and `1.03` is not found).
Status: OBSERVED (host)

### GREEN — GREEN-137
Scenario: the same command after the change, then V3 `flutter test --no-pub test/features/crypto_icon_urls test/features/orders test/features/portfolio test/features/market`.
Expected: all pass.
Status: PASS (host)

Verification ceiling: V3.

### Verification environment

The executor sandbox cannot run `flutter test` or compile. Write the complete change. Report `red` and `green` as `NOT_RUN` with the tests named in RED then GREEN order. Set `buildability` to `BLOCKED` with that reason, and `status` to `COMPLETED`.

Known Flutter pitfalls:
- `FontFeature` needs `dart:ui` (or `package:flutter/painting.dart`, which re-exports it through material).
- `Table` cells cannot be `Flexible`.

### Task Buildability Gate

Required: YES
Exact secret-free build command: `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub`
Result: PASS

## 10. Stop Conditions

Return `BLOCKED` if the change needs a file outside the list.

## 11. Coordinator Audit

Attempt 9a745874f658488bb357532d85d98f9d. The executor reported `BLOCKED` only because its sandbox cannot build. Audit verdict: REWORK (contract gaps), then the override above.
Scope: PASS. Two allowed files changed.
Contract: PASS.
- `_num` matches D-020 (`—`, raw non-numeric, `0.00`, 2 decimals, 2 significant digits below 0.01).
- The `Table` has a `Net`/`Vay`/`Lãi vay` header, isolated base and quote rows, a cross row, right-aligned tabular numbers, and the `Wrap` summary line.
- Nothing above the divider changed. No exchange-specific branch.

Findings:
- AUD-137-01 (contract gap): the existing `margin profit, missing capital, messages and sparse rows` test expected exactly one `—` for an empty Cross card. Each empty table cell is now its own `—`, so there are 5. Fixed by override: `findsNWidgets(5)`.
- AUD-137-02 (contract gap): the contract's pitfall note led to an unnecessary `dart:ui` import (analyzer info 156 → 157). Fixed by override: the import was removed.

RED (host, HEAD `margin_account_card.dart` with the new tests): failures in:
- `margin card details are compact with 2 decimals`;
- `margin card keeps tiny values and dashes` (`0.0012` not found);
- the three `Binance positions and filters` cases (`Lãi vay` found 3 times).

GREEN (host, after the override):
- `flutter test --no-pub test/features/orders/orders_binance_view_test.dart`: 22 passed.
- V3 `flutter test --no-pub test/features/crypto_icon_urls test/features/orders test/features/portfolio test/features/market`: 201 passed, exit 0.

Dispatch route compliance: UNVERIFIABLE (requested gpt-6.1-terra / medium, explicit). Parent route inheritance: NO.
Task buildability gate: PASS.
- `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings`: 0 errors, 156 issues (unchanged).
- `flutter build web --no-pub`: built.

Verdict: PASS
