# Task 01: Portfolio USDT + VND Display

**Status:** Completed and locked

**Approved design:** Add a persisted `USDT + VND` setting while preserving existing USD-only and VNĐ-only modes. In dual mode, show USDT first and VND beneath it on the Portfolio/home screen only.

**Implementation reference:** `implementation_plan.md`

## Approval Gate

- [x] User explicitly says “execute tasks”, “proceed with coding”, “do the task”, or equivalent.

## Checklist

- [x] Add canonical `USD`, `VNĐ`, and `USDT_VND` display-mode definitions and tests.
- [x] Add a tested reusable Portfolio amount formatter/widget supporting single-line and dual-line output.
- [x] Add **USDT + VND** to the Settings currency dropdown.
- [x] Persist `USDT_VND` through the existing mobile secure-storage and web shared-preferences paths.
- [x] Show the USDT/VND exchange-rate subtitle for VNĐ and dual modes.
- [x] Render total balance in both currencies in dual mode.
- [x] Render original capital in both currencies in dual mode.
- [x] Render unrealized P&L, including its sign, in both currencies in dual mode.
- [x] Render every visible Portfolio asset value in both currencies in dual mode.
- [x] Obscure both lines when balance hiding is enabled.
- [x] Preserve USD-only and VNĐ-only behavior.
- [x] Leave Market, Orders, P&L History, and Fractal Tracker unchanged.
- [x] Format changed Dart files.
- [x] Run focused currency and Portfolio widget tests.
- [x] Run `flutter analyze` and the complete `flutter test` suite.
- [x] Verify selection persistence and all three display modes through widget acceptance tests and a production web build; live account/device storage remains environment-specific validation.
- [x] Report results without committing or pushing unless separately requested.

## Completion Lock

Once every checklist item is completed, this file is locked and must not be modified for future requirements. Any follow-up change must use the next numbered task file.
