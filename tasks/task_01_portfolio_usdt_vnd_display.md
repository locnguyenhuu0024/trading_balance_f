# Task 01: Portfolio USDT + VND Display

**Status:** Awaiting explicit execution approval

**Approved design:** Add a persisted `USDT + VND` setting while preserving existing USD-only and VNĐ-only modes. In dual mode, show USDT first and VND beneath it on the Portfolio/home screen only.

**Implementation reference:** `implementation_plan.md`

## Approval Gate

- [ ] User explicitly says “execute tasks”, “proceed with coding”, “do the task”, or equivalent.

## Checklist

- [ ] Add canonical `USD`, `VNĐ`, and `USDT_VND` display-mode definitions and tests.
- [ ] Add a tested reusable Portfolio amount formatter/widget supporting single-line and dual-line output.
- [ ] Add **USDT + VND** to the Settings currency dropdown.
- [ ] Persist `USDT_VND` through the existing mobile secure-storage and web shared-preferences paths.
- [ ] Show the USDT/VND exchange-rate subtitle for VNĐ and dual modes.
- [ ] Render total balance in both currencies in dual mode.
- [ ] Render original capital in both currencies in dual mode.
- [ ] Render unrealized P&L, including its sign, in both currencies in dual mode.
- [ ] Render every visible Portfolio asset value in both currencies in dual mode.
- [ ] Obscure both lines when balance hiding is enabled.
- [ ] Preserve USD-only and VNĐ-only behavior.
- [ ] Leave Market, Orders, P&L History, and Fractal Tracker unchanged.
- [ ] Format changed Dart files.
- [ ] Run focused currency and Portfolio widget tests.
- [ ] Run `flutter analyze` and the complete `flutter test` suite.
- [ ] Manually verify selection persistence and all three display modes.
- [ ] Report results without committing or pushing unless separately requested.

## Completion Lock

Once every checklist item is completed, this file is locked and must not be modified for future requirements. Any follow-up change must use the next numbered task file.
