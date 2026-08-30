# Remove Realized PnL Recording and Firebase Design

**Date:** 2026-08-29  
**Status:** Proposed; awaiting execution approval

## Context

The application has a Firebase/Cloud Firestore-backed realized PnL workflow:

- Home exposes a `Ghi PnL` floating action button and entry sheet.
- A `Nhật ký` destination in the main navigation opens a Firestore-backed PnL history page.
- The `pnl_history` feature contains its model, repository, provider, input sheet, and history screen.
- `main.dart` initializes Firebase before starting the application.
- `firebase_core` and `cloud_firestore` are direct runtime dependencies.

The user no longer wants to use realized PnL recording or Firebase. The current Android Firebase initialization error is a direct consequence of this unwanted startup dependency.

## User Outcome

The app starts and operates without Firebase. The realized-PnL input/history workflow is absent from the UI and source tree, and no Firebase package is retained as a direct dependency.

## Design Decisions

### Remove the realized PnL feature completely

- Delete `lib/features/pnl_history/`, including the data model, Firestore repository, Riverpod stream provider, input sheet, and history screen.
- Remove the `Ghi PnL` floating action button and its import from Home.
- Remove the `Nhật ký` navigation destination and its screen import from the root navigation shell.
- Reduce the primary navigation to three destinations, in order: `Trang chủ`, `BMAG`, and `Lệnh`.
- Update navigation tests to assert the three destinations and remove Firestore stream overrides.

### Remove Firebase initialization and packages

- Remove `firebase_core` import and `Firebase.initializeApp(...)` call from `main.dart`.
- Remove `firebase_core` and `cloud_firestore` from `pubspec.yaml` and regenerate `pubspec.lock` using `flutter pub get`.
- Do not remove or alter unrelated background-service PnL notifications, Portfolio unrealized PnL, or Orders unrealized PnL. These use OKX account data and not Firebase/Firestore.

### Native configuration and external data

- The repository currently has no checked-in `google-services.json`, `GoogleService-Info.plist`, or generated `firebase_options.dart`; therefore there is no native Firebase configuration file to delete.
- Do not change the user-owned `android/gradle.properties` modification, which is unrelated to this scope.
- Do not delete Firestore collections or Firebase Console project configuration. External data deletion requires separate, explicit authorization and is not needed for the app to stop using Firebase.

## State, Compatibility, and Migration

- Existing Firestore documents remain untouched but are no longer read or written by the app.
- No data migration is needed because the feature and its dependencies are removed rather than transformed.
- Existing local preferences, API credentials, Web storage behavior, biometric authentication, market data, orders, and portfolio display remain unchanged.
- On a fresh build, Android no longer attempts to load Firebase resource options at app startup.

## Non-Goals

- Removing OKX-derived realized/unrealized PnL fields from order, position, portfolio, or background-service views.
- Deleting or modifying Firebase cloud data or project settings.
- Redesigning the remaining three navigation destinations.
- Changing Firebase-related Android configuration outside this repository if one is introduced later for a different feature.

## Acceptance Criteria

- The app has no `pnl_history` source feature and no PnL entry/history UI.
- The navigation bar shows only Home, BMAG, and Orders; no PnL journal destination remains.
- `main.dart` contains no Firebase initialization or Firebase imports.
- `pubspec.yaml` and `pubspec.lock` contain no direct `firebase_core` or `cloud_firestore` dependency.
- Existing Home, BMAG, Orders, Portfolio balance masking, market/settings routes, and OKX-derived PnL views retain their behavior.
- `flutter pub get`, `flutter analyze`, complete `flutter test`, and `flutter build web` succeed, subject only to documented pre-existing project limitations.

