# Task 03: Remove Realized PnL Recording and Firebase

**Status:** Completed; checklist locked  
**Canonical plan:** [`../docs/agents/plans/2026-08-29-remove-pnl-firebase.md`](../docs/agents/plans/2026-08-29-remove-pnl-firebase.md)

## Approval Gate

- [x] User explicitly authorizes execution of this plan and checklist.

## Checklist

- [x] Update navigation/UI regression tests for the three-destination, PnL-free app.
- [x] Remove Firebase bootstrap logic and direct Firebase dependencies.
- [x] Remove the PnL destination and update navigation selection/index behavior.
- [x] Remove the Home PnL entry action.
- [x] Delete the Firestore-backed `pnl_history` feature source files.
- [x] Regenerate `pubspec.lock` with `flutter pub get`.
- [x] Verify no realized-PnL/Firebase runtime references remain while retaining OKX PnL views.
- [x] Format changed Dart files and run focused tests.
- [x] Run static analysis, complete tests, and production web build.
- [x] Review final diff, lock this checklist, and report without committing or pushing.

## Completion Lock

Once every checklist item is completed and the task is marked complete, this file is immutable. Follow-up scope must use the next task sequence.
