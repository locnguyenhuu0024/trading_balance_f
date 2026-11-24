import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/features/avatar/domain/avatar_colors.dart';
import 'package:trading_balance_f/features/avatar/domain/avatar_mood.dart';
import 'package:trading_balance_f/features/avatar/presentation/avatar_renderer.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_avatar_customize_page.dart';

import '../avatar/floating_avatar_test.dart' show FakeAvatarRenderer;

const _red = Color(0xffad1020);
const _green = Color(0xff228833);
const _blue = Color(0xff224499);
const _pixiv = 'pixiv-sample';
const _donut = 'donut-chan';
final _savedHair = AvatarColors.empty.withPart(AvatarPart.hair, _blue);
final _otherModel = AvatarColors.empty.withPart(AvatarPart.accessory, _green);

void main() {
  testWidgets('RED-152 Pixiv part chips exclude accessories', (tester) async {
    await _open(tester);
    expect(find.text('Tùy chỉnh Pixiv Sample'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNWidgets(5));
    expect(find.text('Phụ kiện'), findsNothing);
  });

  testWidgets('RED-152 save failure rolls back and keeps the draft', (
    tester,
  ) async {
    final fixture = await _open(tester);
    await _changeColor(tester, _red);
    await tester.tap(find.text('Lưu'));
    await tester.pump();

    expect(
      fixture.container.read(avatarColorsProvider)[_pixiv]![AvatarPart.hair],
      _red,
    );

    fixture.storage.pending.completeError(StateError('write failed'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(fixture.container.read(avatarColorsProvider), {
      _pixiv: _savedHair,
      _donut: _otherModel,
    });
    expect(find.text('Không lưu được cài đặt'), findsOneWidget);
    expect(
      tester.widget<HueRingPicker>(find.byType(HueRingPicker)).pickerColor,
      _red,
    );
    expect(find.byType(SettingsAvatarCustomizePage), findsOneWidget);
  });

  testWidgets('RED-152 unsaved back confirms before discarding', (
    tester,
  ) async {
    final fixture = await _open(tester);
    await _changeColor(tester, _red);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Bỏ thay đổi?'), findsOneWidget);

    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsAvatarCustomizePage), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bỏ thay đổi'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsAvatarCustomizePage), findsNothing);
    expect(fixture.storage.writtenJson, isNull);
    expect(fixture.container.read(avatarColorsProvider)[_pixiv], _savedHair);
  });

  testWidgets('GREEN-152 preview sends one trailing update per 100 ms window', (
    tester,
  ) async {
    final fixture = await _open(tester);
    final renderer = fixture.renderer;
    expect(renderer.moods, [AvatarMood.neutral]);
    expect(renderer.colors, [_savedHair]);

    await _changeColor(tester, _red);
    await tester.pump(const Duration(milliseconds: 75));
    await _changeColor(tester, _green);
    await tester.pump(const Duration(milliseconds: 24));
    expect(renderer.colors, [_savedHair]);

    await tester.pump(const Duration(milliseconds: 1));
    expect(renderer.colors.map((entry) => entry[AvatarPart.hair]), [
      _blue,
      _green,
    ]);
    await tester.pump(const Duration(milliseconds: 100));
    expect(renderer.colors, hasLength(2));
  });

  testWidgets('GREEN-152 save updates and persists only the edited model', (
    tester,
  ) async {
    final fixture = await _open(tester);
    await _changeColor(tester, _red);
    await tester.tap(find.text('Lưu'));
    await tester.pump();

    final expected = {
      _pixiv: _savedHair.withPart(AvatarPart.hair, _red),
      _donut: _otherModel,
    };
    expect(fixture.container.read(avatarColorsProvider), expected);
    expect(decodeAvatarColorsMap(fixture.storage.writtenJson), expected);

    fixture.storage.pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(SettingsAvatarCustomizePage), findsNothing);
    expect(fixture.container.read(avatarColorsProvider), expected);
  });

  testWidgets('GREEN-152 confirmed reset clears preview and saves defaults', (
    tester,
  ) async {
    final fixture = await _open(tester);
    final reset = find.text('Khôi phục mặc định');
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(find.text('Khôi phục mặc định?'), findsOneWidget);
    await tester.tap(find.text('Khôi phục'));
    await tester.pumpAndSettle();
    expect(fixture.renderer.colors, [_savedHair, AvatarColors.empty]);
    expect(fixture.container.read(avatarColorsProvider)[_pixiv], _savedHair);

    await tester.tap(find.text('Lưu'));
    await tester.pump();
    expect(decodeAvatarColorsMap(fixture.storage.writtenJson), {
      _donut: _otherModel,
    });
    fixture.storage.pending.complete();
    await tester.pumpAndSettle();
    expect(fixture.container.read(avatarColorsProvider), {_donut: _otherModel});
  });
}

Future<void> _changeColor(WidgetTester tester, Color color) async {
  tester
      .widget<HueRingPicker>(find.byType(HueRingPicker))
      .onColorChanged(color);
  await tester.pump();
}

Future<
  ({ProviderContainer container, FakeAvatarRenderer renderer, _Storage storage})
>
_open(WidgetTester tester) async {
  final storage = _Storage();
  final renderer = FakeAvatarRenderer();
  addTearDown(storage.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        avatarColorsProvider.overrideWith(
          (ref) => {_pixiv: _savedHair, _donut: _otherModel},
        ),
        avatarRendererFactoryProvider.overrideWithValue((_) => renderer),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const SettingsAvatarCustomizePage(modelId: _pixiv),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.text('Open')),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return (container: container, renderer: renderer, storage: storage);
}

class _Storage extends SecureStorageHelper {
  _Storage() : super(const FlutterSecureStorage());

  final pending = Completer<void>();
  String? writtenJson;

  @override
  Future<void> saveAvatarColorsJson(String json) {
    writtenJson = json;
    return pending.future;
  }
}
