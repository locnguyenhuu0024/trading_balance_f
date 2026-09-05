import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/navigation/navigation_preferences.dart';
import 'package:trading_balance_f/core/navigation/navigation_preferences_provider.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';

class _SettingsStorage extends SecureStorageHelper {
  _SettingsStorage({this.failNavigationSave = false})
    : super(const FlutterSecureStorage());

  final bool failNavigationSave;
  NavigationPreferences? savedNavigationPreferences;

  // Keeping the initial legacy read pending isolates this test from platform
  // background-service calls while leaving the seeded navigation state intact.
  @override
  Future<String?> getOkxApiKey() => Completer<String?>().future;

  @override
  Future<void> saveNavigationPreferences(
    NavigationPreferences preferences,
  ) async {
    if (failNavigationSave) throw StateError('write failed');
    savedNavigationPreferences = preferences;
  }
}

void main() {
  Widget settingsApp(_SettingsStorage storage) {
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        navigationPreferencesInitialProvider.overrideWithValue(
          NavigationPreferences.defaults,
        ),
        vndExchangeRateProvider.overrideWith((ref) async => 25400),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    );
  }

  testWidgets(
    'shows edge selection only for floating navigation and saves it',
    (tester) async {
      final storage = _SettingsStorage();
      await tester.pumpWidget(settingsApp(storage));

      expect(
        find.byKey(const Key('settings-navigation-mode-select')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('settings-floating-edge-select')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const Key('settings-navigation-mode-select')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nút nổi').last);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('settings-floating-edge-select')),
        findsOneWidget,
      );
      expect(
        storage.savedNavigationPreferences,
        const NavigationPreferences(
          displayMode: NavigationDisplayMode.floating,
          floatingEdge: NavigationEdge.bottom,
        ),
      );
    },
  );

  testWidgets('restores the confirmed option and exposes save feedback', (
    tester,
  ) async {
    final storage = _SettingsStorage(failNavigationSave: true);
    await tester.pumpWidget(settingsApp(storage));

    await tester.tap(find.byKey(const Key('settings-navigation-mode-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nút nổi').last);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('settings-floating-edge-select')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('settings-navigation-save-error')),
      findsOneWidget,
    );
    expect(
      find.text('Không lưu được tùy chọn điều hướng. Vui lòng thử lại.'),
      findsOneWidget,
    );
  });
}
