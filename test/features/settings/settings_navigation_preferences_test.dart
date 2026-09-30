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
  _SettingsStorage({
    this.failNavigationSave = false,
    this.failTextScaleSave = false,
  }) : super(const FlutterSecureStorage());

  final bool failNavigationSave;
  final bool failTextScaleSave;
  NavigationPreferences? savedNavigationPreferences;
  double? savedAppTextScale;

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

  @override
  Future<double> getAppTextScale() async => 1.0;

  @override
  Future<void> saveAppTextScale(double scale) async {
    if (failTextScaleSave) throw StateError('write failed');
    savedAppTextScale = scale;
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

  testWidgets('offers a control to choose visible navigation pages', (
    tester,
  ) async {
    await tester.pumpWidget(settingsApp(_SettingsStorage()));

    expect(
      find.byKey(const Key('settings-navigation-visibility')),
      findsOneWidget,
    );
  });

  testWidgets(
    'shows edge selection only for floating navigation and saves it',
    (tester) async {
      final storage = _SettingsStorage();
      await tester.pumpWidget(settingsApp(storage));

      expect(
        find.byKey(const Key('settings-navigation-mode-select')),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('settings-navigation-appearance')));
      await tester.pumpAndSettle();
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

    await tester.tap(find.byKey(const Key('settings-navigation-appearance')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-navigation-mode-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nút nổi').last);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('settings-floating-edge-select')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('settings-navigation-dialog-save-error')),
      findsOneWidget,
    );
  });

  testWidgets('exposes navigation appearance and text size selectors', (
    tester,
  ) async {
    final storage = _SettingsStorage();
    await tester.pumpWidget(settingsApp(storage));

    expect(
      find.byKey(const Key('settings-navigation-appearance')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('settings-navigation-size-select')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('settings-navigation-opacity-select')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('settings-app-text-scale-select')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('settings-navigation-appearance')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-navigation-size-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lớn').last);
    await tester.pumpAndSettle();

    expect(storage.savedNavigationPreferences?.buttonScale, 1.1);

    await tester.tap(
      find.byKey(const Key('settings-navigation-opacity-select')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rõ (75%)').last);
    await tester.pumpAndSettle();

    expect(storage.savedNavigationPreferences?.buttonOpacity, 0.75);

    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-app-text-scale-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rất lớn').last);
    await tester.pumpAndSettle();

    expect(storage.savedAppTextScale, 1.3);
  });

  testWidgets('keeps Settings locked and saves visibility changes', (
    tester,
  ) async {
    final storage = _SettingsStorage();
    await tester.pumpWidget(settingsApp(storage));

    await tester.tap(find.byKey(const Key('settings-navigation-visibility')));
    await tester.pumpAndSettle();

    for (final id in [
      'home',
      'bmag',
      'orders',
      'market',
      'settings',
      'risk',
      'support',
    ]) {
      expect(
        find.byKey(Key('settings-navigation-visible-$id')),
        findsOneWidget,
      );
    }

    final settingsCheckbox = tester.widget<CheckboxListTile>(
      find.byKey(const Key('settings-navigation-visible-settings')),
    );
    expect(settingsCheckbox.value, isTrue);
    expect(settingsCheckbox.onChanged, isNull);

    await tester.tap(find.byKey(const Key('settings-navigation-visible-bmag')));
    await tester.pumpAndSettle();

    expect(
      storage.savedNavigationPreferences?.enabledDestinationIds,
      isNot(contains('bmag')),
    );
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const Key('settings-navigation-visible-bmag')),
          )
          .value,
      isFalse,
    );
  });

  testWidgets('restores visibility after a failed save', (tester) async {
    await tester.pumpWidget(
      settingsApp(_SettingsStorage(failNavigationSave: true)),
    );
    await tester.tap(find.byKey(const Key('settings-navigation-visibility')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings-navigation-visible-bmag')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const Key('settings-navigation-visible-bmag')),
          )
          .value,
      isTrue,
    );
    expect(
      find.byKey(const Key('settings-navigation-dialog-save-error')),
      findsOneWidget,
    );
  });

  testWidgets('rolls back app text size when persistence fails', (
    tester,
  ) async {
    final storage = _SettingsStorage(failTextScaleSave: true);
    await tester.pumpWidget(settingsApp(storage));

    await tester.tap(find.byKey(const Key('settings-app-text-scale-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lớn').last);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<DropdownButton<double>>(
            find.byKey(const Key('settings-app-text-scale-select')),
          )
          .value,
      1.0,
    );
    expect(
      find.text('Không lưu được cỡ chữ ứng dụng. Vui lòng thử lại.'),
      findsOneWidget,
    );
  });
}
