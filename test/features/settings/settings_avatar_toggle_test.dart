import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/features/avatar/domain/avatar_display.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';

class _AvatarStorage extends SecureStorageHelper {
  _AvatarStorage({this.enabled = false}) : super(const FlutterSecureStorage());

  final bool enabled;
  final pendingSave = Completer<void>();
  final pendingFraming = Completer<void>();
  final scaleWrites = <(int, Completer<void>)>[];
  bool? requestedValue;
  String? requestedFraming;

  @override
  Future<String?> getOkxApiKey() => Completer<String?>().future;

  @override
  Future<bool> getAvatarEnabled() async => enabled;

  @override
  Future<void> saveAvatarEnabled(bool enabled) {
    requestedValue = enabled;
    return pendingSave.future;
  }

  @override
  Future<void> saveAvatarFraming(String framing) {
    requestedFraming = framing;
    return pendingFraming.future;
  }

  @override
  Future<void> saveAvatarScale(int percent) {
    final result = Completer<void>();
    scaleWrites.add((percent, result));
    return result.future;
  }
}

final _avatarSwitch = find.byKey(const Key('settings-avatar-switch'));
final _framing = find.byKey(const Key('settings-avatar-framing'));
final _scale = find.byKey(const Key('settings-avatar-scale-slider'));

Slider _slider(WidgetTester tester) => tester.widget<Slider>(_scale);

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

  testWidgets('RED-158 framing and size controls are disabled when off', (
    tester,
  ) async {
    final storage = _AvatarStorage();
    await _showSettings(tester, storage);
    final framing = tester.widget<SegmentedButton<AvatarFraming>>(_framing);
    expect(framing.selected, {AvatarFraming.full});
    expect(framing.onSelectionChanged, isNull);
    expect(tester.getSize(_framing).height, greaterThanOrEqualTo(48));
    expect(_slider(tester).onChanged, isNull);
    expect(_slider(tester).onChangeEnd, isNull);
    expect(tester.getSize(_scale).height, greaterThanOrEqualTo(48));
    expect(find.text('100%'), findsOneWidget);
  });

  for (final fails in [false, true]) {
    testWidgets(
      '${fails ? 'RED' : 'GREEN'}-158 framing saves and rolls back on failure ($fails)',
      (tester) async {
        final storage = _AvatarStorage(enabled: true);
        final container = await _showSettings(tester, storage);
        final half = find.text('Nửa người');
        await tester.ensureVisible(half);
        await tester.pumpAndSettle();
        await tester.tap(half);
        await tester.pump();
        expect(storage.requestedFraming, 'half');
        expect(container.read(avatarFramingProvider), AvatarFraming.half);
        if (fails) {
          storage.pendingFraming.completeError(StateError('save failed'));
        } else {
          storage.pendingFraming.complete();
        }
        await tester.pumpAndSettle();
        final expected = fails ? AvatarFraming.full : AvatarFraming.half;
        expect(container.read(avatarFramingProvider), expected);
        expect(
          tester.widget<SegmentedButton<AvatarFraming>>(_framing).selected,
          {expected},
        );
        expect(
          find.text('Không lưu được cài đặt'),
          fails ? findsOneWidget : findsNothing,
        );
      },
    );
  }

  testWidgets('GREEN-158 slider updates live and saves once at release', (
    tester,
  ) async {
    final storage = _AvatarStorage(enabled: true);
    final container = await _showSettings(tester, storage);
    await tester.ensureVisible(_scale);
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(tester.getCenter(_scale));
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    final first = container.read(avatarScalePercentProvider);
    expect(first, greaterThan(100));
    await gesture.moveBy(const Offset(85, 0));
    await tester.pump();
    final latest = container.read(avatarScalePercentProvider);
    expect(latest, greaterThan(first));
    expect(_slider(tester).label, '$latest%');
    expect(
      _slider(tester).semanticFormatterCallback!(latest.toDouble()),
      '$latest%',
    );
    expect(storage.scaleWrites, isEmpty);
    await gesture.up();
    await tester.pump();
    expect(storage.scaleWrites.single.$1, latest);
    storage.scaleWrites.single.$2.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('RED-158 slider failures respect newer values and roll back', (
    tester,
  ) async {
    final storage = _AvatarStorage(enabled: true);
    final container = await _showSettings(tester, storage);
    void endAt(double percent) {
      final slider = _slider(tester);
      slider.onChanged!(percent);
      slider.onChangeEnd!(percent);
    }

    endAt(110);
    storage.scaleWrites[0].$2.complete();
    await tester.pump();
    endAt(120);
    endAt(130);
    endAt(140);
    expect(storage.scaleWrites.map((write) => write.$1), [110, 120]);
    storage.scaleWrites[1].$2.completeError(StateError('older save failed'));
    await tester.pump();
    expect(container.read(avatarScalePercentProvider), 140);
    expect(storage.scaleWrites.map((write) => write.$1), [110, 120, 140]);
    storage.scaleWrites[2].$2.completeError(StateError('latest save failed'));
    await tester.pumpAndSettle();
    expect(container.read(avatarScalePercentProvider), 110);
    expect(_slider(tester).value, 110);
    expect(find.text('Không lưu được cài đặt'), findsOneWidget);
  });

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
