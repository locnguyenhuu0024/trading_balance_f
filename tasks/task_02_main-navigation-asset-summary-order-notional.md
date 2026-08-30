# Task 02: Main Navigation, Asset Summary, and Order Notional

**Status:** Completed and locked  
**Canonical plan:** [`../docs/agents/plans/2026-08-29-main-navigation-asset-summary-order-notional.md`](../docs/agents/plans/2026-08-29-main-navigation-asset-summary-order-notional.md)

## Approval Gate

- [x] User explicitly authorizes execution of this plan and checklist.

## Checklist

- [x] Add focused navigation and order-notional tests for the approved behavior.
- [x] Add the four-destination root navigation shell and route both launch paths through it.
- [x] Remove duplicate BMAG, PnL, and Orders actions from the Home AppBar while preserving Market, visibility, and Settings.
- [x] Replace the total-asset card with a responsive frameless summary that retains all current values and masking behavior.
- [x] Parse and generate the required OKX order/position notional fields.
- [x] Resolve notional values safely, including SPOT/MARGIN fallback and derivative-unavailable behavior.
- [x] Display position/order notional in the active currency mode and respect hidden balances.
- [x] Preserve current colors, typography, Material icons, filters, refresh behavior, and loading/error states.
- [x] Format changed Dart files and run focused tests.
- [x] Run `flutter analyze`, the complete `flutter test` suite, and `flutter build web`.
- [x] Review the final diff against the approved plan and acceptance criteria.
- [x] Mark this checklist complete and report results without committing or pushing.

## Verification

- `flutter test` passed: 28 tests.
- `flutter analyze --no-fatal-infos` completed with no errors or warnings. It reports 16 pre-existing informational lints outside this task's scope.
- `flutter build web` succeeded. Flutter reported existing WebAssembly compatibility findings for `flutter_secure_storage_web` and a Cupertino icon-font warning; neither prevented the web build.

## Completion Lock

Once every checklist item is completed and the task is marked complete, this file is immutable. Follow-up scope must use the next task sequence.
