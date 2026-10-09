import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/navigation/navigation_preferences.dart';
import 'package:trading_balance_f/core/navigation/navigation_preferences_provider.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';

Future<void> _scrollUntilVisibleInDialog(
  WidgetTester tester,
  Finder target, {
  required double delta,
}) async {
  final dialog = find.byType(AlertDialog);
  final reorderableList = find.descendant(
    of: dialog,
    matching: find.byType(ReorderableListView),
  );
  final listScrollable = find
      .descendant(of: reorderableList, matching: find.byType(Scrollable))
      .first;

  await tester.scrollUntilVisible(
    target,
    delta,
    scrollable: listScrollable,
    maxScrolls: 10,
  );
  await tester.pumpAndSettle();
}

class _SettingsStorage extends SecureStorageHelper {
  _SettingsStorage({
    this.failNavigationSave = false,
    this.failTextScaleSave = false,
    this.navigationSaveGate,
    this.pendingApiKeyRead = true,
  }) : super(const FlutterSecureStorage());

  final bool failNavigationSave;
  final bool failTextScaleSave;
  final Completer<void>? navigationSaveGate;
  final bool pendingApiKeyRead;
  NavigationPreferences? savedNavigationPreferences;
  double? savedAppTextScale;

  // Keep the initial legacy read pending so opening the access page does not
  // depend on a platform secure-storage implementation in this widget test.
  @override
  Future<String?> getOkxApiKey() => pendingApiKeyRead
      ? Completer<String?>().future
      : Future<String?>.value(null);

  @override
  Future<String?> getOkxSecretKey() async => null;

  @override
  Future<String?> getOkxPassphrase() async => null;

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
  Widget settingsApp(_SettingsStorage storage, {double textScale = 1}) {
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        navigationPreferencesInitialProvider.overrideWithValue(
          NavigationPreferences.defaults,
        ),
        vndExchangeRateProvider.overrideWith((ref) async => 25400),
      ],
      child: MaterialApp(
        theme: ThemeData(
          fontFamily: 'Roboto',
          textTheme: ThemeData.light().textTheme.apply(fontFamily: 'Roboto'),
        ),
        builder: (context, child) => DefaultTextStyle.merge(
          style: const TextStyle(fontFamily: 'Roboto'),
          child: RepaintBoundary(
            key: _settingsPreviewKey,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
          ),
        ),
        home: const SettingsScreen(),
      ),
    );
  }

  testWidgets('settings selectors stay legible in narrow and desktop layouts', (
    tester,
  ) async {
    await tester.runAsync(_loadSettingsPreviewFonts);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final scenario in [
      (
        width: 320.0,
        textScale: 1.6,
        screenshot: 'settings-mobile-320-scale-1.6.png',
      ),
      (width: 1280.0, textScale: 1.0, screenshot: 'settings-desktop-1280.png'),
    ]) {
      tester.view.physicalSize = Size(scenario.width, 1000);
      await tester.pumpWidget(
        settingsApp(_SettingsStorage(), textScale: scenario.textScale),
      );
      await tester.pumpAndSettle();

      await _writeSettingsPreview(tester, scenario.screenshot);

      final timeZone = find.byKey(const Key('settings-timezone-select'));
      final theme = find.byType(DropdownButton<ThemeMode>);
      final currency = find.byKey(const Key('settings-currency-select'));
      final textScale = find.byKey(const Key('settings-app-text-scale-select'));
      for (final selector in [timeZone, theme, currency, textScale]) {
        await tester.ensureVisible(selector);
        await tester.pump();
        final rect = tester.getRect(selector);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(scenario.width));
        expect(rect.height, greaterThanOrEqualTo(48));
      }

      expect(
        tester.widget<DropdownButton<String>>(timeZone).style?.fontSize,
        14,
      );
      expect(
        tester.widget<DropdownButton<ThemeMode>>(theme).style?.fontSize,
        14,
      );
      expect(
        tester.widget<DropdownButton<String>>(currency).style?.fontSize,
        14,
      );
      expect(
        tester.widget<DropdownButton<double>>(textScale).style?.fontSize,
        14,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('API và giao dịch'), findsOneWidget);
    expect(find.text('Đang tải thông tin API đã lưu…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      find.byKey(const Key('settings-okx-credential-bundle')),
      findsNothing,
    );
    expect(find.text('API Key'), findsNothing);
    expect(find.text('Secret Key'), findsNothing);
    expect(find.text('Passphrase'), findsNothing);
    expect(find.text('Giao dịch riêng tư'), findsOneWidget);
    expect(find.byKey(const Key('settings-trade-access-button')), findsNothing);
  });

  testWidgets('opens the ready API and trade access subpage', (tester) async {
    await tester.pumpWidget(
      settingsApp(_SettingsStorage(pendingApiKeyRead: false)),
    );
    await tester.pump();

    final accessEntry = find.byKey(const Key('settings-trade-access-button'));
    await tester.ensureVisible(accessEntry);
    await tester.pumpAndSettle();
    await tester.tap(accessEntry);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const Key('settings-toggle-okx-entry-mode')));
    await tester.pump();

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
      'support',
      'strategy',
    ]) {
      final row = find.byKey(Key('settings-navigation-visible-$id'));
      await _scrollUntilVisibleInDialog(tester, row, delta: 200);
      expect(row, findsOneWidget);
    }

    final settingsRow = find.byKey(
      const Key('settings-navigation-visible-settings'),
    );
    await _scrollUntilVisibleInDialog(tester, settingsRow, delta: -200);
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
    await _scrollUntilVisibleInDialog(tester, bmagRow, delta: -200);
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

  testWidgets('reorders BMAG after Support from the navigation drag handle', (
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
    final supportRow = find.byKey(
      const Key('settings-navigation-visible-support'),
    );
    final dragDistance =
        tester.getTopLeft(supportRow).dy - tester.getCenter(bmagHandle).dy + 4;
    await tester.drag(bmagHandle, Offset(0, dragDistance));
    await tester.pumpAndSettle();

    expect(storage.savedNavigationPreferences, isNotNull);
    expect(storage.savedNavigationPreferences!.destinationOrderIds, [
      'home',
      'orders',
      'market',
      'settings',
      'support',
      'bmag',
      'strategy',
    ]);
    expect(
      tester
          .getTopLeft(find.byKey(const Key('settings-navigation-visible-bmag')))
          .dy,
      greaterThan(
        tester
            .getTopLeft(
              find.byKey(const Key('settings-navigation-visible-support')),
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
    final supportRow = find.byKey(
      const Key('settings-navigation-visible-support'),
    );
    final dragDistance =
        tester.getTopLeft(supportRow).dy - tester.getCenter(bmagHandle).dy + 4;
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
              find.byKey(const Key('settings-navigation-visible-support')),
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

const _settingsPreviewKey = ValueKey('settings-preview');

Future<void> _loadSettingsPreviewFonts() async {
  var directory = File(Platform.resolvedExecutable).absolute.parent;
  while (directory.path != directory.parent.path) {
    final fonts = Directory(
      '${directory.path}${Platform.pathSeparator}bin${Platform.pathSeparator}'
      'cache${Platform.pathSeparator}artifacts${Platform.pathSeparator}'
      'material_fonts',
    );
    if (await fonts.exists()) {
      for (final font in {
        'Roboto': 'roboto-regular.ttf',
        'MaterialIcons': 'materialicons-regular.otf',
      }.entries) {
        final file = File(
          '${fonts.path}${Platform.pathSeparator}${font.value}',
        );
        if (!await file.exists()) continue;
        final bytes = await file.readAsBytes();
        final loader = FontLoader(font.key)
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
      }
      return;
    }
    directory = directory.parent;
  }
}

Future<void> _writeSettingsPreview(WidgetTester tester, String filename) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_settingsPreviewKey),
  );
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
  expect(image, isNotNull);
  final capturedImage = image!;
  final png = await tester.runAsync(
    () => capturedImage.toByteData(format: ui.ImageByteFormat.png),
  );
  capturedImage.dispose();
  expect(png, isNotNull);
  final bytes = png!.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
  await tester.runAsync(() async {
    final directory = Directory('build/forms-preview');
    await directory.create(recursive: true);
    await File('${directory.path}/$filename').writeAsBytes(bytes, flush: true);
  });
}
