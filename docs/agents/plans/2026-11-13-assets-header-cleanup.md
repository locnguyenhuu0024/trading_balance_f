# Small Change Plan: Assets header and info cleanup

Status: APPROVED
Approval: "Duyệt, commit, làm" (user, chat, 2026-11-13, on this revision)
Date: 2026-11-13
Tier: S
Plan ID: PLAN-20261113-assets-header-cleanup
Supersedes: D-005 in `docs/agents/plans/2026-11-13-assets-account-unrealized-pnl.md`, where the `Ước tính Spot · Margin` line was kept as a breakdown.
Domain: mobile (Flutter). Web F0–F3 does not apply.

## Objective

On the Assets page, three things change:

- The estimate line, `Phạm vi dữ liệu` and `Tiền tệ hiển thị` are gone.
- The account selector becomes a compact pill in the title row, next to the reload button.

## Decisions (user request 2026-11-13 with screenshot; the details are recommendations confirmed by approving this plan)

- D-014: Remove from the Assets page:
  - the `Ước tính Spot · Margin: … / ≈ … đ / Tính trên N/M tài sản` block;
  - the `Phạm vi dữ liệu` and `Tiền tệ hiển thị` rows.

  Keep `PartialAccountNotice` (`Chưa đầy đủ`), the divider and `Tài sản chi tiết`. The estimate is still computed and still feeds the headline and `Vốn gốc` (T132). Only its separate line goes. Known consequence: the `Tính trên N/M tài sản` coverage hint is no longer shown. Each asset row still shows its own state (`Chưa tính`, `Chưa đủ dữ liệu giá vốn`).
- D-015: Compact selector, used only on the Assets page. Other screens keep the full `ScopeBar`; this can follow later if wanted. It reuses `ScopeBar` with a `compact` flag, so the same picker sheet, provider and semantics label (`<label>, Chính`) are kept for every exchange.
  - Pill shape: `palette.surface` background, `palette.border` side, radius 20, minimum height 40.
  - Content: a 22×22 square in `palette.ink` with the first letter in `palette.onStrong`, then `profile.label` at 14 bold with one line and ellipsis, then `Icons.expand_more` at 18.
  - The `/ Chính` suffix and the product line (`USDⓈ-M · Spot · Margin`) are not shown in compact mode. Data availability stays visible through `Chưa đầy đủ`.
- D-016: Title row order: `Tài sản` (Expanded) → compact selector (Flexible, so it can shrink and ellipsize) → reload → show/hide balance. The separate `ScopeBar` row below the title is removed from the Assets page. Nothing overflows at width 320 with text scale 2.0.

## Evidence and Scope

- OBS-009: `portfolio_screen.dart:233-272`. The title row is `Tài sản`, `ManualRefreshButton` and the visibility `IconButton`, with `ScopeBar()` in its own row below. `:420-470` holds the summary `Builder` and the two `_infoRow` calls.
- OBS-010: `lib/core/widgets/scope_bar.dart` (`ScopeBar`) is used on eight screens. `scope_bar_test.dart` checks its default height (more than 54) and its picker.
- Allowed files:
  - `lib/features/portfolio/presentation/portfolio_screen.dart`
  - `lib/core/widgets/scope_bar.dart`
  - `test/features/portfolio/portfolio_scope_test.dart`
  - `test/features/connections/account_state_test.dart`
  - `test/features/connections/scope_bar_test.dart`
- Out of scope: other screens' `ScopeBar`, the picker sheet, estimate math, the headline (T132), asset rows, OKX data.
- Preserved behavior:
  - the default `ScopeBar` looks and behaves exactly as today (its existing tests stay unchanged);
  - tapping the compact selector opens the same `ScopePicker`;
  - the headline and `Vốn gốc` values from T132 do not change;
  - hiding balances, pull to refresh, the reload button and its key `portfolio-manual-refresh`;
  - `_infoRow` is deleted if it becomes unused.

## Implementation Step — P04

1. `ScopeBar({super.key, this.compact = false})`. When `compact` is true, build the D-015 pill. The non-compact branch stays unchanged.
2. `portfolio_screen.dart`: place `const ScopeBar(compact: true)` in the title row per D-016, and remove the `ScopeBar` padding row. Remove the summary `Builder` and the info `Column`. `estimatedSummary` must still be computed for `baseEquity` and the headline.
3. Tests: update the expectations that look for removed text. Do not weaken unrelated assertions.

Worked expectations:

- W14: Binance Assets with an estimate. `Ước tính Spot · Margin`, `Tính trên`, `Phạm vi dữ liệu` and `Tiền tệ hiển thị` are all `findsNothing`. The T132 W6 headline `-$20.50` and `(-41.00%)` are still shown.
- W15: the compact selector shows `Binance`, not `Binance / Chính` and not `USDⓈ-M · Spot · Margin`. It sits in the same `Row` as `portfolio-manual-refresh`, to its left. Tapping it shows the picker (`OKX / Chính` visible when an OKX connection exists, as in `account_state_test.dart:236-238`).
- W16: at width 320 and text scale 2.0 with a long label (`Binance Futures Account 01`), there is no exception and the label ellipsizes.
- W17: the default `ScopeBar` still has a height greater than 54 (existing test).

RED: on the current code, W14 fails (`Phạm vi dữ liệu` is found) and W15 fails (the `compact` parameter does not exist, or `Binance / Chính` is shown).
GREEN: the three test files pass, then V3 runs `test/features/portfolio` and `test/features/connections`.
Verification ceiling: V3.

Task buildability gate: YES, a compile check on the host: `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub`. A build meant for deployment needs `--release --dart-define=BINANCE_PROXY_URL=…`.
Stop if: the change needs another screen, the picker, or files outside the list.

## External Verification / Configuration

None. The user checks visually after deploying.

## Planning Workstreams

Fan-out Required: NO. Skip Reason: SINGLE_MATERIAL_WORKSTREAM (one client screen plus a shared widget variant). The Sol advisor was not used because sharing is not authorized.

## Task

T134: `tasks/task_134_assets_header_cleanup.md`. E2, `gpt-6.1-terra / medium`.

## Approval Gate

- [x] no material ambiguity (D-014 to D-016, confirmed by plan approval)
- [x] scope bounded
- [x] RED then GREEN defined
- [x] build command defined
- [x] user approval obtained before implementation
- [x] no protected configuration needed
