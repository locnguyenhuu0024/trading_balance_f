# Small Change Plan: Margin profit percentage on own capital

Status: APPROVED
Approval: "Duyệt, làm đi" (user, chat, 2026-11-13, on this revision)
Date: 2026-11-13
Tier: S
Plan ID: PLAN-20261113-margin-own-capital-pnl
Amends: `docs/agents/specs/2026-11-07-binance-estimated-pnl-design.md` section 4, the percentage rule, and section 6, the summary. Every other rule in that specification stays.

## Objective

When a position uses borrowed money, the estimated percentage is the profit divided by the user's own capital, not by the whole position. "Vốn gốc" on the Assets card stops counting the estimated Spot and Margin profit as capital.

## Decisions (user, chat, 2026-11-13: "Đồng ý, viết plan")

- D-001: For an Isolated Margin pair, own capital = pair equity − estimated profit. Pair equity = `baseNet × indexPrice + quoteNet`, in USDT. This holds for long and short positions. If own capital is ≤ 0 or not finite, the percentage is hidden and the profit amount still shows.
- D-002: Cross Margin is out of scope. Borrowing there is pooled across the whole account, so it cannot be split per coin. Cross rows keep the percentage on cost. This is a known limitation.
- D-003: `Vốn gốc` = total assets − USDⓈ-M unrealized profit − estimated Spot and Margin profit. The estimate is subtracted only when the Spot and Margin summary is available and has at least one covered asset. The summary percentage uses the sum of each covered row's own capital. The USDⓈ-M line and its percentage do not change.

## Evidence and Scope

- OBS-001 (user screenshot, SOL/USDT Isolated): the position cost is 1.031967 × 103.76 ≈ 107.08 USDT. The loss is −26.08 USDT and is correct. The app shows −24.35%, which is −26.08 ÷ 107.08 and includes 53.56 USDT of borrowed money. Own capital is 81.18 − 53.70 + 26.08 ≈ 53.56 USDT, so the expected figure is about −48.7%.
- OBS-002: `binance_cost_basis.dart:147` sets `percentage = profit / (covered × average)`, and `estimatedPnlText` prints it.
- OBS-003: `binance_estimated_pnl.dart:21`. The summary percentage is profit ÷ Σ(covered × average).
- OBS-004: `portfolio_screen.dart:375`, `baseEquity = total − USDⓈ-M uPnL`. With USDⓈ-M at 0, `Vốn gốc` shows the current equity, 27.53, and not about 53.7.
- Allowed files: `lib/exchanges/binance/binance_estimated_pnl.dart`, `lib/features/portfolio/presentation/portfolio_screen.dart`, and the three existing test files listed in T131.
- Out of scope: Cross Margin capital, `binance_cost_basis.dart` (its `CostEstimate.percentage` and AC-201 stay), the USDⓈ-M line, OKX, the history reader, and text layout.
- Preserved behavior: Spot rows (own capital = cost, so the percentage does not change), every message state, hiding, OKX, the poll and run rules, and all T128–T130 tests apart from the expectations this plan changes.
- Protected configuration and environment files: agents may not read or write them, and none is needed.

## Implementation Step — P01

1. The row result carries the percentage to display. Spot and Cross rows use own capital = `covered × average`. Isolated rows use D-001, with `quoteNet` parsed from the row. `estimatedPnlText` prints that percentage, and leaves out ` (x%)` when capital is invalid.
2. The summary adds up each covered row's own capital. Its percentage is hidden when any covered row has invalid capital or when the total is ≤ 0.
3. `portfolio_screen.dart` subtracts `summary.profit` from `baseEquity` under D-003, using the same availability conditions as the summary line, except that hiding balances does not count. Hiding still masks the value.

Worked figures, derived by the coordinator independently of the code:

- W1, Isolated long: cost state quantity 1, cost 100, margin. `baseNet 1`, `indexPrice 80`, `quoteNet -50.5`, `quoteInterest 0.5`, `baseInterest 0`. Profit = −20 − 0.5 = −20.50. Equity = 80 − 50.5 = 29.5. Capital = 50. Text: `Giá vốn TB 100.00 · Ước tính -20.50 USDT (-41.00%)`. The current code prints `(-20.50%)`.
- W2, Isolated short: quantity −1, cost 100, margin. `baseNet -1`, `indexPrice 90`, `quoteNet 150`, interest 0. Profit = +10.00. Equity = 60. Capital = 50. Text ends in `(+20.00%)`. The current code prints `(+10.00%)`.
- W3, capital ≤ 0: same as W1 but `quoteNet -100.5`. Equity = −20.5, so capital = 0. Text: `Giá vốn TB 100.00 · Ước tính -20.50 USDT`, with no percentage.
- W4, summary: a Spot BTC row (quantity 1, cost 100, total 1, value 110), which gives profit +10 and capital 100, plus the W1 row. Summary: `-10.50 USDT (-7.00%)`. The current code prints `(-5.25%)`.
- W5, `Vốn gốc`: account total 29.5, only the W1 pair, USDⓈ-M 0, summary available. `Vốn gốc` = 50.00 USDT. While the cost view is loading, it is 29.50 USDT, the current behavior.

Tests: W1–W4 in `binance_estimated_pnl_test.dart`. W1 on the margin card in `orders_binance_view_test.dart`. W4 and W5 on the Assets screen in `portfolio_scope_test.dart`.
RED: run the new W1, W4 and W5 tests against the current code. Expected failures: `(-20.50%)` appears instead of `(-41.00%)`, `(-5.25%)` instead of `(-7.00%)`, and 29.50 instead of 50.00.
GREEN: the same tests and the three full test files pass, with the existing Spot `(+10.00%)` expectations unchanged.
Inner loop: narrow diagnostics only. The formal RED → GREEN check runs once.
Verification ceiling: V2, the three test files. Escalate to V3 (`test/features/portfolio`, `test/features/orders`, `test/exchanges/binance`) only if a shared provider or widget changes.

Task buildability gate: YES.
Affected canonical build unit: the Flutter app at the repository root.
Exact secret-free build command: `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub`. The coordinator runs it on the host, as in T130.
Stop if: the change needs `binance_cost_basis.dart`, any file not listed, or a rule for Cross Margin.

## External Verification

The user checks live in the app: the SOL/USDT card should show about −48.7%, and `Vốn gốc` should be about 53.6–53.7. This does not block PASS.

## External Configuration / Environment Action

None.

## Planning Workstreams

Fan-out Required: NO. Skip Reason: SINGLE_MATERIAL_WORKSTREAM. The change is client calculation and display only, with no backend or data change. The Sol advisor was not used because the user has not authorized sharing the packet.

## Task

T131 implements P01: `tasks/task_131_margin_own_capital_pnl.md`.
Executor Class: E2. Target Route: gpt-6.1-terra / medium, which is the default in validated policy v2.

## Approval Gate

- [x] no material ambiguity (D-001 to D-003)
- [x] scope is bounded
- [x] RED then GREEN defined
- [x] affected build unit + exact task build command defined
- [x] task boundary is buildable; single task
- [x] user approval obtained before implementation
- [x] protected configuration/environment contents are not required to be read
- [x] external configuration action is N/A
