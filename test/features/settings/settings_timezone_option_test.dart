import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/core/timezone/app_time_zone.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';

class _TimeZoneSettingsStorage extends SecureStorageHelper {
  _TimeZoneSettingsStorage({this.failTimeZoneSave = false})
    : super(const FlutterSecureStorage());

  final bool failTimeZoneSave;
  String? savedTimeZoneId;

  @override
  Future<String?> getOkxApiKey() => Completer<String?>().future;

  @override
  Future<void> saveTimeZoneId(String timeZoneId) async {
    if (failTimeZoneSave) throw StateError('write failed');
    savedTimeZoneId = timeZoneId;
  }
}

Widget _settingsApp(_TimeZoneSettingsStorage storage) {
  return ProviderScope(
    overrides: [
      secureStorageProvider.overrideWithValue(storage),
      appTimeZoneProvider.overrideWith((ref) => AppTimeZone.defaultId),
      vndExchangeRateProvider.overrideWith((ref) async => 25400),
    ],
    child: const MaterialApp(home: SettingsScreen()),
  );
}

void main() {
  testWidgets('exposes the global time-zone selector and its options', (
    tester,
  ) async {
    await tester.pumpWidget(_settingsApp(_TimeZoneSettingsStorage()));

    final selector = find.byKey(const Key('settings-timezone-select'));
    final infoButton = find.byKey(const Key('settings-timezone-info-button'));
    expect(selector, findsOneWidget);
    expect(infoButton, findsOneWidget);
    expect(
      find.text('Áp dụng cho toàn bộ mốc thời gian trong ứng dụng.'),
      findsNothing,
    );

    await tester.tap(infoButton);
    await tester.pumpAndSettle();

    expect(
      find.text('Áp dụng cho toàn bộ mốc thời gian trong ứng dụng.'),
      findsOneWidget,
    );
    expect(find.text('Đóng'), findsOneWidget);

    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();
    expect(
      find.text('Áp dụng cho toàn bộ mốc thời gian trong ứng dụng.'),
      findsNothing,
    );

    await tester.tap(selector);
    await tester.pumpAndSettle();

    expect(find.text('Hồ Chí Minh (Asia/Ho_Chi_Minh)'), findsOneWidget);
    expect(find.text('UTC (Etc/UTC)'), findsNWidgets(2));
  });

  testWidgets('persists a selected time zone', (tester) async {
    final storage = _TimeZoneSettingsStorage();
    await tester.pumpWidget(_settingsApp(storage));

    await tester.tap(find.byKey(const Key('settings-timezone-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hồ Chí Minh (Asia/Ho_Chi_Minh)').last);
    await tester.pumpAndSettle();

    expect(storage.savedTimeZoneId, 'Asia/Ho_Chi_Minh');
    expect(
      tester
          .widget<DropdownButton<String>>(
            find.byKey(const Key('settings-timezone-select')),
          )
          .value,
      'Asia/Ho_Chi_Minh',
    );
  });

  testWidgets('rolls back the selector when persistence fails', (tester) async {
    await tester.pumpWidget(
      _settingsApp(_TimeZoneSettingsStorage(failTimeZoneSave: true)),
    );

    await tester.tap(find.byKey(const Key('settings-timezone-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hồ Chí Minh (Asia/Ho_Chi_Minh)').last);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<DropdownButton<String>>(
            find.byKey(const Key('settings-timezone-select')),
          )
          .value,
      AppTimeZone.defaultId,
    );
    expect(
      find.text('Không lưu được múi giờ. Vui lòng thử lại.'),
      findsOneWidget,
    );
  });
}
