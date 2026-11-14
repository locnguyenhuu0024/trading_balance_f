# Small Change Plan: Account selector in the header on every screen

Status: APPROVED
Approval: "Duyệt, commit, làm" (user, chat, 2026-11-14, on this revision; includes commit on PASS)
Date: 2026-11-14
Tier: S
Plan ID: PLAN-20261114-header-account-selector
Domain: mobile (Flutter).

## Objective

Every screen that shows the account selector (`ScopeBar`) shows it as the compact pill in the title row, next to the reload button, as the Assets page already does (T134). The separate full-width selector row is removed.

## Decisions (user request 2026-11-14: "Trong cái trang Quản lý lệnh, tôi cũng cần đưa cái nút chọn tài khoản lên trên header cạnh bên nút reload. mà áp dụng điều này cho toàn bộ trang đi")

- D-021: Reuse `ScopeBar(compact: true)` from T134 with no change to `ScopeBar` or the picker.
  - Title rows with a reload button follow the Assets order: `Expanded(title)` → `SizedBox(width: 8)` → `Flexible(child: ScopeBar(compact: true))` → the existing action icons → reload.
  - Screens with no reload button get `Expanded(title)` → `SizedBox(width: 8)` → `Flexible(ScopeBar(compact: true))`.
  - Title text, back buttons, action icons, refresh keys and everything below the header stay unchanged.
  - The non-compact `ScopeBar` branch stays in the code for now, with its tests. After this change no screen uses it.

## Evidence and Scope

OBS-017: the screens that still use the full `ScopeBar()` row:

| Screen | File | Header today |
|---|---|---|
| Lệnh | `lib/features/orders/presentation/orders_screen.dart:276-327` | `Lệnh`, login icon, reload; `ScopeBar()` row below |
| Thị trường | `lib/features/market/presentation/market_screen.dart:139-163` | `Thị trường`, reload; `ScopeBar()` row below |
| BMAG | `lib/features/fractal_tracker/presentation/fractal_screen.dart:100-138` | back, `BMAG`, search, reload; coin button; `ScopeBar()` row |
| Hỗ trợ / kháng cự | `lib/features/support_resistance/presentation/support_resistance_screen.dart:90-115` | `ScopeBar()` **above** the title row (back, title, reload) |
| Cài đặt | `lib/features/settings/presentation/settings_screen.dart:423-445` | back, `Cài đặt`, reload; `ScopeBar()` below |
| Công cụ | `lib/features/tools/tools_screen.dart:21-30` | `Công cụ` title, then `ScopeBar()`, no reload |
| Đang đổi tài khoản | `lib/features/connections/scope_switch_gate.dart:51-60` | title, then `ScopeBar()`, no reload (shown while switching accounts) |

The Assets page is already done (T134). The Unrealized PnL details, Strategy and trade-access pages have reload buttons but no selector, and are out of scope.

Allowed files: the 7 screens above, plus these tests:
- `test/features/orders/orders_binance_view_test.dart`
- `test/features/market/market_screen_test.dart`
- the new `test/features/connections/header_scope_bar_test.dart`

## Implementation Step — P08

For each screen:
1. Move the selector into the title row as in D-021, as `Flexible(child: ScopeBar(compact: true))` placed before the action icons.
2. Remove the old selector row and its padding. Keep one existing vertical gap under the header so the content does not touch it.

Worked expectations:
- W24 (all 7 files, source check): each file contains `ScopeBar(compact: true)` and no `ScopeBar()`.
- W25 (Lệnh, widget test): `ScopeBar` is compact. It shares a `Row` with `Key('orders-manual-refresh')` and sits to its left. The full-width row is gone.
- W26 (Thị trường, widget test): the same with `Key('market-manual-refresh')`.
- W27: the existing tests still pass, including tapping `ScopeBar` to open the picker, the account-switch screen, and the 320 px / text-scale tests.

RED: W24–W26 fail on the current code.
GREEN: the touched test files pass, then V4 `flutter test --no-pub` (the whole suite, because 7 screens change).
Task buildability gate: `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub`.

## Planning Workstreams

Fan-out Required: NO. Skip Reason: SINGLE_MATERIAL_WORKSTREAM (mobile UI only).

## Task

T138: `tasks/task_138_header_account_selector.md`. E2, `gpt-6.1-terra / medium`.

## Approval Gate

- [x] no material ambiguity (D-021)
- [x] scope bounded
- [x] RED then GREEN defined
- [x] build command defined
- [x] user approval obtained before implementation
- [x] no protected configuration needed
