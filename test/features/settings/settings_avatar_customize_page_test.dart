import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/features/avatar/domain/avatar_colors.dart';
import 'package:trading_balance_f/features/avatar/domain/avatar_mood.dart';
import 'package:trading_balance_f/features/avatar/domain/avatar_outfit.dart';
import 'package:trading_balance_f/features/avatar/presentation/avatar_renderer.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_avatar_customize_page.dart';

import '../avatar/floating_avatar_test.dart' show FakeAvatarRenderer;

const _red = Color(0xffad1020);
const _green = Color(0xff228833);
const _blue = Color(0xff224499);
const _pixiv = 'pixiv-sample';
const _donut = 'donut-chan';
const _dress = 'donut-chan:outfit';
const _shoes = 'donut-chan:shoes';
final _savedHair = AvatarColors.empty.withPart(AvatarPart.hair, _blue);
final _otherModel = AvatarColors.empty.withPart(AvatarPart.accessory, _green);

void main() {
  testWidgets('RED-156 Donut-Chan customization has no tabs', (tester) async {
    await _open(tester, modelId: _donut);
    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(HueRingPicker), findsOneWidget);
  });

  testWidgets(
    'GREEN-156 equipping a dress changes the preview and colour parts',
    (tester) async {
      final fixture = await _open(tester);
      final semantics = tester.ensureSemantics();
      addTearDown(semantics.dispose);
      expect(find.text('Áo'), findsOneWidget);
      expect(find.text('Quần/Váy'), findsOneWidget);
      await tester.tap(find.text('Áo'));
      await tester.pump();

      await _tapText(tester, 'Phối đồ');
      expect(find.byType(TabBarView), findsNothing);
      expect(find.bySemanticsLabel('Trang phục: Đồ gốc'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Trang phục: Váy Donut-Chan'),
        findsOneWidget,
      );
      await _tapText(tester, 'Váy Donut-Chan');
      expect(fixture.renderer.outfits, [
        <String>[],
        [_dress],
      ]);
      await _tapText(tester, 'Màu sắc');

      expect(find.text('Áo'), findsNothing);
      expect(find.text('Quần/Váy'), findsNothing);
      expect(find.text('Váy'), findsOneWidget);
      expect(find.text('Nơ & huy hiệu'), findsOneWidget);
      expect(find.bySemanticsLabel('Chọn màu Tóc'), findsOneWidget);
      await _tapText(tester, 'Váy');
      expect(
        tester.widget<HueRingPicker>(find.byType(HueRingPicker)).pickerColor,
        const Color(0xfff7bdc0),
      );
    },
  );

  testWidgets('GREEN-156 one save persists the outfit and borrowed colour', (
    tester,
  ) async {
    final fixture = await _open(
      tester,
      pixivColors: _savedHair.withPart(AvatarPart.top, _green),
    );
    await _tapText(tester, 'Phối đồ');
    await _tapText(tester, 'Váy Donut-Chan');
    await _tapText(tester, 'Màu sắc');
    await _tapText(tester, 'Váy');
    await _changeColor(tester, _red);
    await tester.tap(find.text('Lưu'));
    await tester.pump();

    expect(fixture.storage.writes, ['outfits', 'colors']);
    final outfits = decodeAvatarOutfits(fixture.storage.outfitJson);
    expect(outfits, {
      _pixiv: [_dress],
    });
    final expected = _savedHair.withPart(AvatarPart.dress, _red);
    expect(
      decodeAvatarColorsWithOutfits(
        fixture.storage.writtenJson,
        outfits,
      )[_pixiv],
      expected,
    );
    expect(fixture.container.read(avatarColorsProvider)[_pixiv], expected);
    expect(fixture.container.read(avatarOutfitsProvider), outfits);

    fixture.storage.pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(SettingsAvatarCustomizePage), findsNothing);
  });

  for (final failOutfits in [true, false]) {
    testWidgets(
      'RED-156 ${failOutfits ? 'outfit' : 'colour'} write failure rolls back both providers',
      (tester) async {
        final fixture = await _open(
          tester,
          outfits: const {
            _pixiv: [_shoes],
          },
          failOutfits: failOutfits,
        );
        await _tapText(tester, 'Phối đồ');
        await _tapText(tester, 'Váy Donut-Chan');
        await _tapText(tester, 'Màu sắc');
        await _changeColor(tester, _red);
        await tester.tap(find.text('Lưu'));
        await tester.pump();
        if (!failOutfits) {
          expect(fixture.container.read(avatarOutfitsProvider)[_pixiv], [
            _shoes,
            _dress,
          ]);
          expect(
            fixture.container.read(
              avatarColorsProvider,
            )[_pixiv]?[AvatarPart.hair],
            _red,
          );
          fixture.storage.pending.completeError(StateError('write failed'));
        }
        await tester.pumpAndSettle();

        expect(fixture.container.read(avatarOutfitsProvider), {
          _pixiv: [_shoes],
        });
        expect(fixture.container.read(avatarColorsProvider), {
          _pixiv: _savedHair,
          _donut: _otherModel,
        });
        expect(
          fixture.storage.writes,
          failOutfits ? ['outfits'] : ['outfits', 'colors', 'outfits'],
        );
        if (!failOutfits) {
          expect(decodeAvatarOutfits(fixture.storage.outfitJson), {
            _pixiv: [_shoes],
          });
        }
        expect(find.text('Không lưu được cài đặt'), findsOneWidget);
        expect(find.byType(SettingsAvatarCustomizePage), findsOneWidget);
      },
    );
  }

  testWidgets('RED-156 an outfit-only draft triggers the discard dialog', (
    tester,
  ) async {
    final fixture = await _open(tester);
    await _tapText(tester, 'Phối đồ');
    await _tapText(tester, 'Váy Donut-Chan');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Bỏ thay đổi?'), findsOneWidget);
    await _tapText(tester, 'Bỏ thay đổi');
    expect(find.byType(SettingsAvatarCustomizePage), findsNothing);
    expect(fixture.storage.writes, isEmpty);
  });

  testWidgets(
    'GREEN-156 resetting colours preserves outfit until confirmed clear',
    (tester) async {
      final fixture = await _open(
        tester,
        outfits: const {
          _pixiv: [_dress],
        },
      );
      await _tapText(tester, 'Khôi phục mặc định');
      await _tapText(tester, 'Khôi phục');
      expect(fixture.renderer.colors.last, AvatarColors.empty);
      expect(fixture.renderer.outfits, [
        [_dress],
      ]);
      expect(find.text('Váy'), findsOneWidget);

      await _tapText(tester, 'Phối đồ');
      await _tapText(tester, 'Bỏ phối đồ');
      expect(find.text('Bỏ phối đồ?'), findsOneWidget);
      await _tapText(tester, 'Hủy');
      expect(fixture.renderer.outfits, [
        [_dress],
      ]);
      await _tapText(tester, 'Bỏ phối đồ');
      await tester.tap(find.widgetWithText(TextButton, 'Bỏ phối đồ'));
      await tester.pumpAndSettle();
      expect(fixture.renderer.outfits, [
        [_dress],
        <String>[],
      ]);
      expect(fixture.renderer.colors.last, AvatarColors.empty);
    },
  );

  testWidgets('RED-154 the unset Donut-Chan picker starts at original hair', (
    tester,
  ) async {
    await _open(tester, modelId: _donut);
    expect(
      tester.widget<HueRingPicker>(find.byType(HueRingPicker)).pickerColor,
      const Color(0xffc4b68b),
    );
  });

  testWidgets('GREEN-154 Donut-Chan shows ordered parts and original swatches', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _open(tester, modelId: _donut, donutColors: AvatarColors.empty);

    final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
    expect(
      chips.map((chip) => ((chip.label as ExcludeSemantics).child! as Text).data),
      [
        'Tóc',
        'Mắt',
        'Váy',
        'Nơ & huy hiệu',
        'Tất',
        'Giày',
        'Miếng dán',
        'Phụ kiện',
      ],
    );
    expect(
      chips.map((chip) {
        final swatch = chip.avatar! as DecoratedBox;
        return (swatch.decoration as BoxDecoration).color;
      }),
      const [
        Color(0xffc4b68b),
        Color(0xff415130),
        Color(0xfff7bdc0),
        Color(0xfff8a5b0),
        Color(0xfff5b4bd),
        Color(0xfff0bec4),
        Color(0xffd6cac6),
        Color(0xffe5d9b6),
      ],
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Màu Váy')).value,
      'Mặc định',
    );

    await tester.tap(find.text('Váy'));
    await tester.pump();
    expect(
      tester.widget<HueRingPicker>(find.byType(HueRingPicker)).pickerColor,
      const Color(0xfff7bdc0),
    );
    semantics.dispose();
  });

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

Future<void> _tapText(WidgetTester tester, String text) async {
  final target = find.text(text);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
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
_open(
  WidgetTester tester, {
  String modelId = _pixiv,
  AvatarColors? pixivColors,
  AvatarColors? donutColors,
  Map<String, List<String>> outfits = const {},
  bool failOutfits = false,
}) async {
  final storage = _Storage(failOutfits: failOutfits);
  final renderer = FakeAvatarRenderer();
  addTearDown(storage.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        avatarOutfitsProvider.overrideWith((ref) => outfits),
        avatarColorsProvider.overrideWith(
          (ref) => {
            _pixiv: pixivColors ?? _savedHair,
            _donut: donutColors ?? _otherModel,
          },
        ),
        avatarRendererFactoryProvider.overrideWithValue((_) => renderer),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsAvatarCustomizePage(modelId: modelId),
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
  _Storage({required this.failOutfits}) : super(const FlutterSecureStorage());

  final bool failOutfits;
  final pending = Completer<void>();
  final writes = <String>[];
  String? writtenJson;
  String? outfitJson;

  @override
  Future<void> saveAvatarOutfitsJson(String json) async {
    writes.add('outfits');
    if (failOutfits) throw StateError('write failed');
    outfitJson = json;
  }

  @override
  Future<void> saveAvatarColorsJson(String json) {
    writes.add('colors');
    writtenJson = json;
    return pending.future;
  }
}
