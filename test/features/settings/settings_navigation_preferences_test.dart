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
    this.navigationSaveGate,
  }) : super(const FlutterSecureStorage());

  final bool failNavigationSave;
  final bool failTextScaleSave;
  final Completer<void>? navigationSaveGate;
  NavigationPreferences? savedNavigationPreferences;
  double? savedAppTextScale;

  // Keep the initial legacy read pending so opening the access page does not
  // depend on a platform secure-storage implementation in this widget test.
  @override
  Future<String?> getOkxApiKey() => Completer<String?>().future;

  @override
  Future<bool> getHideBalanceDefault() async => false;

  @override
  Future<bool> getBiometricAuth() async => true;

  @override
  Future<String> getThemeMode() async => 'system';

  @override
  Future<String> getCurrency() async => 'USD';

  @override
  Future<String> getTimeZoneId() async => 'Asia/Ho_Chi_Minh';

  @override
  Future<void> saveNavigationPreferences(
    NavigationPreferences preferences,
  ) async {
    if (navigationSaveGate != null) await navigationSaveGate!.future;
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

  testWidgets('opens the API and trade access subpage from Settings', (
    tester,
  ) async {
    await tester.pumpWidget(settingsApp(_SettingsStorage()));
    await tester.pump();

    expect(
      find.byKey(const Key('settings-trade-access-button')),
      findsOneWidget,
    );
    expect(find.text('API Key'), findsNothing);
    final accessEntry = find.byKey(const Key('settings-trade-access-button'));
    await tester.ensureVisible(accessEntry);
    await tester.pumpAndSettle();
    await tester.tap(accessEntry);
    await tester.pumpAndSettle();

    expect(find.text('API Key'), findsOneWidget);
    expect(find.text('Secret Key'), findsOneWidget);
    expect(find.text('Passphrase'), findsOneWidget);
    expect(find.text('Giao dịch riêng tư'), findsOneWidget);
    expect(find.byKey(const Key('settings-trade-access-button')), findsNothing);
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
      final row = find.byKey(Key('settings-navigation-visible-$id'));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      expect(row, findsOneWidget);
    }

    final settingsRow = find.byKey(
      const Key('settings-navigation-visible-settings'),
    );
    await tester.ensureVisible(settingsRow);
    await tester.pumpAndSettle();
    final settingsCheckbox = tester.widget<CheckboxListTile>(settingsRow);
    expect(settingsCheckbox.value, isTrue);
    expect(settingsCheckbox.onChanged, isNull);
    expect(
      tester
          .widget<ReorderableDragStartListener>(
            find.byKey(const Key('settings-navigation-drag-settings')),
          )
          .enabled,
      isTrue,
    );

    final bmagRow = find.byKey(const Key('settings-navigation-visible-bmag'));
    await tester.ensureVisible(bmagRow);
    await tester.pumpAndSettle();
    await tester.tap(bmagRow);
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

  testWidgets('reorders BMAG after Risk from the navigation drag handle', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final storage = _SettingsStorage();
    await tester.pumpWidget(settingsApp(storage));
    await tester.tap(find.byKey(const Key('settings-navigation-visibility')));
    await tester.pumpAndSettle();

    final bmagHandle = find.byKey(const Key('settings-navigation-drag-bmag'));
    final riskRow = find.byKey(const Key('settings-navigation-visible-risk'));
    final dragDistance =
        tester.getTopLeft(riskRow).dy - tester.getCenter(bmagHandle).dy + 4;
    await tester.drag(bmagHandle, Offset(0, dragDistance));
    await tester.pumpAndSettle();

    expect(storage.savedNavigationPreferences, isNotNull);
    expect(storage.savedNavigationPreferences!.destinationOrderIds, [
      'home',
      'orders',
      'market',
      'settings',
      'risk',
      'bmag',
      'support',
    ]);
    expect(
      tester
          .getTopLeft(find.byKey(const Key('settings-navigation-visible-bmag')))
          .dy,
      greaterThan(
        tester
            .getTopLeft(
              find.byKey(const Key('settings-navigation-visible-risk')),
            )
            .dy,
      ),
    );
  });

  testWidgets('keeps a hidden destination in its reordered slot', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final storage = _SettingsStorage();
    await tester.pumpWidget(settingsApp(storage));
    await tester.tap(find.byKey(const Key('settings-navigation-visibility')));
    await tester.pumpAndSettle();

    final bmagHandle = find.byKey(const Key('settings-navigation-drag-bmag'));
    final riskRow = find.byKey(const Key('settings-navigation-visible-risk'));
    final dragDistance =
        tester.getTopLeft(riskRow).dy - tester.getCenter(bmagHandle).dy + 4;
    await tester.drag(bmagHandle, Offset(0, dragDistance));
    await tester.pumpAndSettle();

    final savedOrder = storage.savedNavigationPreferences!.destinationOrderIds;
    await tester.tap(find.byKey(const Key('settings-navigation-visible-bmag')));
    await tester.pumpAndSettle();
    expect(
      storage.savedNavigationPreferences!.enabledDestinationIds,
      isNot(contains('bmag')),
    );

    await tester.tap(find.byKey(const Key('settings-navigation-visible-bmag')));
    await tester.pumpAndSettle();
    expect(
      storage.savedNavigationPreferences!.enabledDestinationIds,
      contains('bmag'),
    );
    expect(storage.savedNavigationPreferences!.destinationOrderIds, savedOrder);
    expect(
      tester
          .getTopLeft(find.byKey(const Key('settings-navigation-visible-bmag')))
          .dy,
      greaterThan(
        tester
            .getTopLeft(
              find.byKey(const Key('settings-navigation-visible-risk')),
            )
            .dy,
      ),
    );
  });

  testWidgets('disables reorder and checkbox actions during a save', (
    tester,
  ) async {
    final gate = Completer<void>();
    await tester.pumpWidget(
      settingsApp(_SettingsStorage(navigationSaveGate: gate)),
    );
    await tester.tap(find.byKey(const Key('settings-navigation-visibility')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings-navigation-visible-bmag')));
    await tester.pump();

    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const Key('settings-navigation-visible-home')),
          )
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<ReorderableDragStartListener>(
            find.byKey(const Key('settings-navigation-drag-bmag')),
          )
          .enabled,
      isFalse,
    );

    gate.complete();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
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
