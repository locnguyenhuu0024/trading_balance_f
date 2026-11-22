import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';

class _AvatarStorage extends SecureStorageHelper {
  _AvatarStorage() : super(const FlutterSecureStorage());

  final pendingSave = Completer<void>();
  bool? requestedValue;

  @override
  Future<String?> getOkxApiKey() => Completer<String?>().future;

  @override
  Future<bool> getAvatarEnabled() async => false;

  @override
  Future<void> saveAvatarEnabled(bool enabled) {
    requestedValue = enabled;
    return pendingSave.future;
  }
}

final _avatarSwitch = find.byKey(const Key('settings-avatar-switch'));

Future<ProviderContainer> _showSettings(
  WidgetTester tester,
  _AvatarStorage storage,
) async {
  addTearDown(storage.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        vndExchangeRateProvider.overrideWith((ref) async => 25400),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(_avatarSwitch);
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(_avatarSwitch));
}

void main() {
  FlutterSecureStorage.setMockInitialValues({});

  testWidgets('RED-147 failed save reverts the switch and shows feedback', (
    tester,
  ) async {
    final storage = _AvatarStorage();
    final container = await _showSettings(tester, storage);

    await tester.tap(_avatarSwitch);
    await tester.pump();
    expect(container.read(avatarEnabledProvider), isTrue);

    storage.pendingSave.completeError(StateError('save failed'));
    await tester.pumpAndSettle();

    expect(container.read(avatarEnabledProvider), isFalse);
    expect(tester.widget<SwitchListTile>(_avatarSwitch).value, isFalse);
    expect(find.text('Không lưu được cài đặt'), findsOneWidget);
  });

  testWidgets('GREEN-147 starts off, shows credit, and saves the toggle', (
    tester,
  ) async {
    final storage = _AvatarStorage();
    final container = await _showSettings(tester, storage);

    expect(tester.widget<SwitchListTile>(_avatarSwitch).value, isFalse);
    final credit = tester.widget<Text>(
      find.byKey(const Key('settings-avatar-credit')),
    );
    expect(
      credit.data,
      'VRM1_Constraint_Twist_Sample © 2022 pixiv Inc. '
      '(VRM Public License 1.0)',
    );

    await tester.tap(_avatarSwitch);
    await tester.pump();
    expect(storage.requestedValue, isTrue);
    expect(container.read(avatarEnabledProvider), isTrue);

    storage.pendingSave.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(_avatarSwitch).value, isTrue);
  });
}
