import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/features/avatar/domain/avatar_model.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_avatar_model_page.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';

class _AvatarModelStorage extends SecureStorageHelper {
  _AvatarModelStorage({this.enabled = true})
    : super(const FlutterSecureStorage());

  final bool enabled;
  final pendingSave = Completer<void>();
  String? savedId;

  @override
  Future<bool> getAvatarEnabled() async => enabled;

  @override
  Future<String?> getAvatarModelId() async => savedId;

  @override
  Future<void> saveAvatarModelId(String id) async {
    await pendingSave.future;
    savedId = id;
  }
}

class _MissingThumbnailBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key.endsWith('.png')) throw FlutterError('Missing image: $key');
    return rootBundle.load(key);
  }
}

final _entry = find.byKey(const Key('settings-avatar-model-button'));
final _pixivRow = find.byKey(const Key('avatar-model-pixiv-sample'));
final _donutRow = find.byKey(const Key('avatar-model-donut-chan'));

Future<ProviderContainer> _mount(
  WidgetTester tester,
  _AvatarModelStorage storage, {
  Widget home = const SettingsScreen(),
  AssetBundle? bundle,
}) async {
  addTearDown(storage.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        vndExchangeRateProvider.overrideWith((ref) async => 25400),
      ],
      child: DefaultAssetBundle(
        bundle: bundle ?? rootBundle,
        child: MaterialApp(home: home),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byWidget(home)));
}

bool? _selected(WidgetTester tester, Finder row) =>
    tester.widget<Semantics>(row).properties.selected;

void main() {
  FlutterSecureStorage.setMockInitialValues({});

  testWidgets('RED-150 failed save rolls back and reports the error', (
    tester,
  ) async {
    final storage = _AvatarModelStorage();
    final container = await _mount(
      tester,
      storage,
      home: const SettingsAvatarModelPage(),
      bundle: _MissingThumbnailBundle(),
    );
    await tester.tap(_donutRow);
    await tester.pump();
    expect(container.read(avatarModelIdProvider), 'donut-chan');
    for (final row in [_pixivRow, _donutRow]) {
      final tile = find.descendant(of: row, matching: find.byType(ListTile));
      expect(tester.widget<ListTile>(tile).enabled, isFalse);
    }

    storage.pendingSave.completeError(StateError('save failed'));
    await tester.pumpAndSettle();

    expect(container.read(avatarModelIdProvider), 'pixiv-sample');
    expect(_selected(tester, _pixivRow), isTrue);
    expect(find.text('Không lưu được cài đặt'), findsOneWidget);
  });

  testWidgets('RED-150 a missing thumbnail shows a fallback icon', (
    tester,
  ) async {
    await _mount(
      tester,
      _AvatarModelStorage(),
      home: const SettingsAvatarModelPage(),
      bundle: _MissingThumbnailBundle(),
    );
    expect(
      find.descendant(of: _donutRow, matching: find.byIcon(Icons.view_in_ar)),
      findsOneWidget,
    );
  });

  testWidgets('RED-150 the picker entry is disabled while the avatar is off', (
    tester,
  ) async {
    await _mount(tester, _AvatarModelStorage(enabled: false));
    await tester.ensureVisible(_entry);
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(_entry).enabled, isFalse);
    expect(find.byKey(const Key('settings-avatar-credit')), findsOneWidget);
    await tester.tap(_entry, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsAvatarModelPage), findsNothing);
  });

  testWidgets('GREEN-150 selecting Donut-Chan saves it and updates Settings', (
    tester,
  ) async {
    final storage = _AvatarModelStorage();
    final container = await _mount(
      tester,
      storage,
      bundle: _MissingThumbnailBundle(),
    );
    await tester.ensureVisible(_entry);
    await tester.pumpAndSettle();
    await tester.tap(_entry);
    await tester.pumpAndSettle();

    expect(find.text('Pixiv Sample'), findsOneWidget);
    expect(find.text('Donut-Chan'), findsOneWidget);
    expect(
      find.text(
        'VRM1_Constraint_Twist_Sample © 2022 pixiv Inc. (VRM Public License 1.0)',
      ),
      findsOneWidget,
    );
    const donutCredit = 'Donut-Chan by Kana Fuyuko (Public Domain)';
    expect(find.text(donutCredit), findsOneWidget);
    expect(_selected(tester, _pixivRow), isTrue);

    await tester.tap(_donutRow);
    await tester.pump();
    storage.pendingSave.complete();
    await tester.pumpAndSettle();

    expect(storage.savedId, 'donut-chan');
    expect(container.read(avatarModelIdProvider), 'donut-chan');
    expect(_selected(tester, _donutRow), isTrue);
    expect(_selected(tester, _pixivRow), isFalse);
    expect(
      find.descendant(of: _donutRow, matching: find.byIcon(Icons.check_circle)),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    final credit = tester.widget<Text>(
      find.byKey(const Key('settings-avatar-credit')),
    );
    expect(credit.data, donutCredit);
    expect(find.text('Donut-Chan'), findsOneWidget);
  });
}
