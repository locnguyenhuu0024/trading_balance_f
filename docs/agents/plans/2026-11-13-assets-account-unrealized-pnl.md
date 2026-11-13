# Small Change Plan: Account-wide unrealized profit on Assets

Status: COMPLETE
Approval: "Duyệt, commit, làm" (user, chat, 2026-11-13, on this revision)
Date: 2026-11-13
Tier: S
Plan ID: PLAN-20261113-assets-account-pnl
Amends: `docs/agents/specs/2026-11-07-binance-estimated-pnl-design.md` risk row "never added to USDⓈ-M", for the Assets card headline only. Builds on `docs/agents/plans/2026-11-13-binance-margin-own-capital-pnl.md` (T131).

## Objective

On the Assets page (`Tài sản`) for Binance, `Lãi / lỗ chưa thực hiện` shows the whole account: USDⓈ-M plus the estimated Spot and Margin profit. Its percentage is calculated on `Vốn gốc`.

## Decisions (recommended to the user 2026-11-13; approving this plan confirms them)

- D-004: Headline amount = USDⓈ-M unrealized profit + `summary.profit` (Spot, Cross Margin, Isolated Margin). Headline percentage = headline amount ÷ `Vốn gốc` × 100, where `Vốn gốc` = total − headline amount (T131 already computes this). A `Vốn gốc` of 0 or below shows 0%, as the code does today.
- D-005: When combined, the label is `Lãi / lỗ chưa thực hiện` with no `· USDⓈ-M`. The line `Ước tính Spot · Margin: … · Tính trên N/M tài sản` stays below the card unchanged, as the breakdown. Assets with no cost basis count as 0.
- D-006: When there is no usable estimate (no summary, the cost view is loading or unavailable, web has no proxy, history failed, or `covered == 0`), keep today's behavior: label `· USDⓈ-M`, amount and percentage from USDⓈ-M only.
- D-007: The rule depends on the data, not on the exchange (user, 2026-11-13: multi-platform, "tương thích với toàn bộ cấu trúc dữ liệu đổ vào"). The headline is always Σ `AssetBalance.unrealizedPnl` as each adapter reports it (Binance: USDⓈ-M; OKX: unified `upl`), plus the estimated Spot and Margin profit when an estimate source exists for that connection and has `covered > 0`. Today only Binance has one, so OKX automatically falls back to D-006. No `isBinance` or `isOkx` check is added for this rule. The existing per-exchange label text stays for the fallback.
- D-008: Only the Assets page changes. `portfolio_details_screen.dart` (`Unrealized PnL · USDⓈ-M`) is out of scope.

## Evidence and Scope

- OBS-005: `portfolio_screen.dart:350-394`. `totalUnrealizedPnl` sums `unrealizedPnl` over balances, which on Binance is only USDⓈ-M. `pnlRatio` = that ÷ (USDⓈ-M wallet value − that). The label is at `:745`.
- OBS-006 (user screenshot after T131): total 27.53, USDⓈ-M 0, Spot·Margin −26.21. The headline shows `0.00 (+0.00%)`. Expected: `−26.21` and `−48.77%` (26.21 ÷ 53.74).
- Allowed files: `lib/features/portfolio/presentation/portfolio_screen.dart`, `test/features/portfolio/portfolio_scope_test.dart`.
- Out of scope: estimate math (`binance_estimated_pnl.dart`), the details screen, OKX, the Orders screen.
- Preserved behavior: every existing expectation in `portfolio_scope_test.dart`, including `(+0.00%)`, `(+5.26%)`, `(+10.00%)` and the `· USDⓈ-M` labels in the cases with no estimate, hide behavior, and the summary line text.

## Implementation Step — P02

1. Compute the headline amount and percentage from D-004 when the summary is available with `covered > 0`, using the summary already computed once in the build method. Otherwise use the current USDⓈ-M values (D-006).
2. Pass the label choice to `_buildAssetSummary`, so that it shows `Lãi / lỗ chưa thực hiện` when combined and the current Binance label otherwise. The color, arrow icon and percentage color follow the combined amount through the existing `resolvePnlColor`.

Worked figures, derived independently:

- W6: account total `29.5`, the T131 W1 isolated pair (profit −20.50), no USDⓈ-M balance, summary available. Headline `−$20.50`, `Vốn gốc` `$50.00`, percentage `(-41.00%)`, label `Lãi / lỗ chưa thực hiện`.
- W7: W6 plus a USDⓈ-M USDT balance with `total 100`, `valueUsdt 100`, `unrealizedPnl 5`, and account total `129.5`. Headline 5 − 20.5 = `−$15.50`. `Vốn gốc` = 129.5 + 15.5 = `$145.00`. Percentage = −15.5 ÷ 145 = `(-10.69%)`.
- W8: W7 while the cost view is loading. Label `Lãi / lỗ chưa thực hiện · USDⓈ-M`, headline `+$5.00`, percentage 5 ÷ 95 = `(+5.26%)`, `Vốn gốc` `$124.50`.

Tests: W6–W8 as widget tests in `portfolio_scope_test.dart`.
RED: run the new W6 and W7 tests on the current code. Expected failures: the label is `· USDⓈ-M`, and the headline is not `−$20.50`, because the current code shows 0.00 for W6 and +5.00 for W7.
GREEN: the whole `portfolio_scope_test.dart` passes.
Verification ceiling: V2 (`portfolio_scope_test.dart`). Escalate to V3 (`test/features/portfolio`) because `portfolio_screen.dart` is shared by several tests.

Task buildability gate: YES. Build unit: Flutter app at the repository root.
Command: `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub` (a compile check only; the coordinator runs it on the host. A deployable web build needs `--release --dart-define=BINANCE_PROXY_URL=…`, see `docs/deployment/binance-read-proxy.md`).
Stop if: the change needs a file outside the list, or a rule for the details screen or OKX.

## External Verification / Configuration

None. The user checks live after deploying.

## Planning Workstreams

Fan-out Required: NO. Skip Reason: SINGLE_MATERIAL_WORKSTREAM (one client screen). The Sol advisor was not used because sharing is not authorized.

## Task

T132: `tasks/task_132_assets_account_pnl.md`. E2, `gpt-6.1-terra / medium`. Independent of T133, with disjoint files. Runs serially, because there is one writer per checkout.

## Approval Gate

- [x] no material ambiguity (D-004 to D-008, confirmed by plan approval)
- [x] scope bounded
- [x] RED then GREEN defined
- [x] build command defined
- [x] user approval obtained before implementation
- [x] no protected configuration needed
