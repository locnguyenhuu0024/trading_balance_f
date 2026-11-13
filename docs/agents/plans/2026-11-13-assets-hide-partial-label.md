# Small Change Plan: Hide "Chưa đầy đủ" on Assets

Status: COMPLETE
Approval: "Duyệt, commit, làm" (user, chat, 2026-11-13, on this revision; includes commit on PASS)
Date: 2026-11-13
Tier: S
Plan ID: PLAN-20261113-assets-hide-partial-label
Domain: mobile (Flutter).

## Objective

The Assets page no longer shows the generic `Chưa đầy đủ` line.

## Decisions (user request 2026-11-13; the details are recommendations confirmed by approving this plan)

- D-017: Only the generic `Chưa đầy đủ` line (`account.isPartial`) is hidden, and only on the Assets page. The specific lines stay, because each appears only when something actually failed and tells the user what is missing:
  - `Không thể tải ví …` (a wallet failed);
  - `Spot và Margin chỉ có trên ứng dụng` (web without proxy).

  `PartialAccountNotice` gets a `showPartialLabel` flag that defaults to true. Orders and the Unrealized PnL details screen keep the line. This works the same for any exchange, because the flag reads only `AccountSnapshot`.

## Evidence and Scope

- OBS-011: `lib/core/widgets/account_state_view.dart:76-105`. `PartialAccountNotice` shows `Chưa đầy đủ` when `isPartial` is true, then the failed wallets, then the web line. It is used by `portfolio_screen.dart:424`, `orders_screen.dart:452` and `portfolio_details_screen.dart:251`.
- OBS-012: `test/features/connections/account_state_test.dart:132-185`, the test `partial wallet results on home|details`, expects `Chưa đầy đủ` on both screens.
- Allowed files:
  - `lib/core/widgets/account_state_view.dart`
  - `lib/features/portfolio/presentation/portfolio_screen.dart`
  - `test/features/connections/account_state_test.dart`
- Out of scope: Orders, the details screen, how `isPartial` is computed.

## Implementation Step — P05

1. `PartialAccountNotice({…, this.showPartialLabel = true})`: show `Chưa đầy đủ` only when `account.isPartial && showPartialLabel`.
2. On the Assets page, pass `showPartialLabel: false`.

Worked expectations:

- W18: Assets, `isPartial: true`, Cross Margin unavailable. `Chưa đầy đủ` is `findsNothing`. `Không thể tải ví Margin chéo` is `findsOneWidget`. The web line follows the proxy flag as today.
- W19: details screen with the same data. `Chưa đầy đủ` is `findsOneWidget`, unchanged.

Test: in the existing loop, change the `Chưa đầy đủ` expectation to `details ? findsOneWidget : findsNothing`. Everything else stays.
RED: the home case fails on the current code (`Chưa đầy đủ` is found).
GREEN: `account_state_test.dart` passes, then V3 `test/features/connections test/features/portfolio test/features/orders`.

Task buildability gate: YES, the host compile check `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub`.

## Planning Workstreams

Fan-out Required: NO. Skip Reason: SINGLE_MATERIAL_WORKSTREAM.

## Task

T135: `tasks/task_135_assets_hide_partial_label.md`. E1, `gpt-6.1-terra / low`.

## Approval Gate

- [x] no material ambiguity (D-017, confirmed by plan approval)
- [x] scope bounded
- [x] RED then GREEN defined
- [x] build command defined
- [x] user approval obtained before implementation
- [x] no protected configuration needed
