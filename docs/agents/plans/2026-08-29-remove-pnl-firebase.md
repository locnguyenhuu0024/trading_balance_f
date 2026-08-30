# Implementation Plan: Remove Realized PnL Recording and Firebase

**Date:** 2026-08-29  
**Status:** Proposed; awaiting execution approval  
**Design:** [`../specs/2026-08-29-remove-pnl-firebase-design.md`](../specs/2026-08-29-remove-pnl-firebase-design.md)

## Objective

Remove the Firebase/Firestore realized PnL recording capability, its UI, its navigation destination, Firebase startup initialization, and direct Firebase dependencies while preserving all OKX-derived portfolio/order PnL display.

## Current Repository Context

- `lib/main.dart` imports `firebase_core` and awaits `Firebase.initializeApp`; Android currently receives null options and cannot load Firebase resources.
- `lib/features/pnl_history/` owns the entire Firestore-backed PnL flow.
- `PortfolioScreen` imports the input sheet and supplies the `Ghi PnL` FAB.
- `MainNavigationShell` includes a fourth `Nhật ký` destination and imports `PnlHistoryScreen`.
- `pubspec.yaml` directly depends on `firebase_core` and `cloud_firestore`.
- The current worktree includes completed Task 02 implementation changes and a user-owned `android/gradle.properties` modification. This task must not discard or overwrite them.

## Scope

### In scope

- Delete all realized-PnL/Firestore source files.
- Remove PnL entry/history UI and its navigation destination.
- Remove Firebase initialization and direct package dependencies.
- Update dependency lockfile and affected tests.
- Verify a Firebase-free app build.

### Out of scope

- Deleting remote Firebase project configuration or Firestore data.
- Removing OKX unrealized/realized PnL values elsewhere in the app.
- Modifying unrelated Android settings or existing completed Task 02 implementation.
- Commit, push, or deployment.

## Expected Affected Files

- `lib/main.dart`
- `lib/core/navigation/main_navigation_shell.dart`
- `lib/features/portfolio/presentation/portfolio_screen.dart`
- `lib/features/pnl_history/data/pnl_model.dart` (delete)
- `lib/features/pnl_history/data/pnl_repository.dart` (delete)
- `lib/features/pnl_history/presentation/pnl_history_screen.dart` (delete)
- `lib/features/pnl_history/presentation/pnl_input_sheet.dart` (delete)
- `lib/features/pnl_history/presentation/providers/pnl_provider.dart` (delete)
- `pubspec.yaml`
- `pubspec.lock`
- `test/core/navigation/main_navigation_shell_test.dart`
- Add or update focused tests as needed to prove Firebase-free bootstrap/navigation behavior.

## Ordered Implementation Steps

1. Add/update regression tests for the three-destination navigation and absence of PnL UI.
2. Remove Firebase bootstrap imports/initialization and remove direct Firebase dependencies.
3. Remove the PnL navigation destination and convert the shell indexes to Home, BMAG, and Orders.
4. Remove the Home PnL FAB/import.
5. Delete the self-contained `pnl_history` source feature.
6. Run `flutter pub get` to update the lockfile after dependency removal.
7. Search the repository to confirm no PnL-history, Firestore, or Firebase Core runtime references remain.
8. Format changed Dart files; run focused tests, static analysis, the complete test suite, and a production web build.
9. Review the final diff, update Task 03, and report results without committing or pushing.

## Testing and Verification Strategy

- Widget test that the root navigation has Home, BMAG, and Orders only and each destination switches correctly.
- Verify Home no longer contains the `Ghi PnL` action and no PnL journal labels/tooltips are present.
- Search verification that application runtime source has no `Firebase.initializeApp`, `FirebaseFirestore`, `firebase_core`, `cloud_firestore`, or `pnl_history` references.
- `flutter pub get` after dependency removal.
- `flutter analyze --no-fatal-infos`, complete `flutter test`, and `flutter build web`.
- Reinstall/run Android manually after implementation to confirm the Firebase options exception is no longer reachable; device validation is environment-specific.

## Risks and Mitigations

- **Removing PnL too broadly:** distinguish realized Firestore PnL feature names from OKX `upl`/`pnl` values that must remain.
- **Stale imports after deletion:** use repository-wide search and compiler/test verification.
- **Lockfile inconsistencies:** regenerate it exclusively with the configured Flutter package manager command.
- **External historical Firestore data:** retain it untouched and document that it is no longer used.
- **Dirty worktree:** inspect final diff carefully and preserve Task 02/user-owned changes.

## Rollback Considerations

Rollback restores the deleted feature directory, Firebase dependencies, startup initialization, Home FAB, and fourth navigation destination from source control. No remote data rollback is required because this task does not alter Firebase data.

## Acceptance Criteria

- All linked design acceptance criteria pass.
- No Firebase or realized-PnL recording source remains in the application runtime.
- The app's existing non-Firebase data and UI flows remain functional.
- Verification commands are observed to pass or limitations are reported precisely.

