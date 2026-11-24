import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/core/exchange/exchange_scope.dart';
import 'package:trading_balance_f/core/timezone/app_time_zone.dart';
import 'package:trading_balance_f/core/typography/app_text_scale.dart';
import 'package:trading_balance_f/core/widgets/app_startup.dart';
import 'package:trading_balance_f/features/avatar/domain/avatar_colors.dart';
import 'package:trading_balance_f/features/avatar/domain/avatar_model.dart';
import 'package:trading_balance_f/features/avatar/domain/avatar_outfit.dart';
import 'package:trading_balance_f/main.dart' as app;
import 'package:trading_balance_f/features/portfolio/presentation/portfolio_screen.dart'
    show hideBalanceProvider;
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart'
    show avatarEnabledProvider, currencyProvider, themeModeProvider;

class _StartupStorage extends SecureStorageHelper {
  _StartupStorage({
    this.failBiometricRead = false,
    this.textScale = 1.25,
    this.calls,
    this.selection = 'okx-default',
    this.failSelection = false,
    this.failAvatarRead = false,
    this.failAvatarModelRead = false,
    this.avatarModelId,
    this.avatarColorsJson,
    this.failAvatarColorsRead = false,
    this.failAvatarOutfitsRead = false,
  }) : super(const FlutterSecureStorage());

  final bool failBiometricRead;
  final double textScale;
  final List<String>? calls;
  final String selection;
  final bool failSelection;
  final bool failAvatarRead;
  final bool failAvatarModelRead;
  final String? avatarModelId;
  final String? avatarColorsJson;
  final bool failAvatarColorsRead;
  final bool failAvatarOutfitsRead;

  @override
  Future<String?> getAvatarOutfitsJson() async {
    if (failAvatarOutfitsRead) throw StateError('unreadable avatar outfits');
    return null;
  }

  @override
  Future<String?> getAvatarColorsJson() async {
    if (failAvatarColorsRead) throw StateError('unreadable avatar colours');
    return avatarColorsJson;
  }

  @override
  Future<String?> getAvatarModelId() async {
    if (failAvatarModelRead) throw StateError('unreadable avatar model');
    return avatarModelId;
  }

  @override
  Future<bool> getAvatarEnabled() async {
    if (failAvatarRead) throw StateError('unreadable avatar preference');
    return false;
  }

  @override
  Future<String> getSelectedConnectionId() async {
    if (failSelection) throw StateError('unreadable selection');
    return selection;
  }

  @override
  Future<bool> getBiometricAuth() async {
    calls?.add('biometric');
    if (failBiometricRead) {
      throw StateError('private storage failure detail');
    }
    return true;
  }

  @override
  Future<bool> getHideBalanceDefault() async {
    calls?.add('hideBalance');
    return true;
  }

  @override
  Future<String> getThemeMode() async {
    calls?.add('theme');
    return 'dark';
  }

  @override
  Future<String> getCurrency() async {
    calls?.add('currency');
    return 'VND';
  }

  @override
  Future<String> getTimeZoneId() async {
    calls?.add('timeZone');
    return 'Asia/Ho_Chi_Minh';
  }

  @override
  Future<double> getAppTextScale() async {
    calls?.add('textScale');
    return textScale;
  }
}

void main() {
  test(
    'RED-156 outfit read failure leaves model and colour restoration intact',
    () async {
      final storage = _StartupStorage(
        failAvatarOutfitsRead: true,
        avatarModelId: 'donut-chan',
        avatarColorsJson: '{"donut-chan":{"dress":"#aa3322"}}',
      );
      addTearDown(storage.dispose);
      final startup = await app.initializeAppStartup(
        isWeb: false,
        createNativeStorage: () => storage,
        initializeTimeZone: () {},
        retireLegacyBackgroundService: () async {},
      );
      expect(startup.avatarOutfits, isEmpty);
      expect(startup.avatarModelId, 'donut-chan');
      expect(
        startup.avatarColors['donut-chan']?[AvatarPart.dress],
        const Color(0xffaa3322),
      );
    },
  );

  for (final isWeb in [false, true]) {
    testWidgets(
      'GREEN-156 restores outfits and borrowed colours on ${isWeb ? 'web' : 'native'}',
      (tester) async {
        if (isWeb) {
          SharedPreferences.setMockInitialValues({});
        } else {
          FlutterSecureStorage.setMockInitialValues({});
          addTearDown(() => FlutterSecureStorage.setMockInitialValues({}));
        }
        Future<app.AppStartupData> start() => app.initializeAppStartup(
          isWeb: isWeb,
          initializeTimeZone: () {},
          retireLegacyBackgroundService: () async {},
        );

        final first = await start();
        addTearDown(first.secureStorage.dispose);
        expect(first.avatarOutfits, isEmpty);
        const json =
            '{"pixiv-sample":["donut-chan:outfit","donut-chan:shoes"]}';
        await first.secureStorage.saveAvatarOutfitsJson(json);
        await first.secureStorage.saveAvatarColorsJson(
          '{"pixiv-sample":{"hair":"#112233","dress":"#552299","plasters":"#123456"}}',
        );

        final restored = await start();
        addTearDown(restored.secureStorage.dispose);
        expect(restored.avatarOutfits, {
          'pixiv-sample': ['donut-chan:outfit', 'donut-chan:shoes'],
        });
        final restoredColors = restored.avatarColors['pixiv-sample']!;
        expect(restoredColors[AvatarPart.hair], const Color(0xff112233));
        expect(restoredColors[AvatarPart.dress], const Color(0xff552299));
        expect(restoredColors[AvatarPart.plasters], isNull);
        await tester.pumpWidget(
          app.buildInitializedApp(
            restored,
            home: Consumer(
              builder: (_, ref, _) =>
                  Text(encodeAvatarOutfits(ref.watch(avatarOutfitsProvider))),
            ),
          ),
        );
        expect(find.text(json), findsOneWidget);
      },
    );
  }

  for (final failRead in [false, true]) {
    test(
      'RED-152 startup tolerates ${failRead ? 'unreadable' : 'corrupt'} colours',
      () async {
        final storage = _StartupStorage(
          avatarModelId: 'donut-chan',
          avatarColorsJson: '{"donut-chan":',
          failAvatarColorsRead: failRead,
        );
        addTearDown(storage.dispose);
        final startup = await app.initializeAppStartup(
          isWeb: false,
          createNativeStorage: () => storage,
          initializeTimeZone: () {},
          retireLegacyBackgroundService: () async {},
        );
        expect(startup.avatarModelId, 'donut-chan');
        expect(startup.avatarColors, isEmpty);
      },
    );
  }

  for (final isWeb in [false, true]) {
    testWidgets(
      'GREEN-152 persists and restores avatar colours on ${isWeb ? 'web' : 'native'}',
      (tester) async {
        if (isWeb) {
          SharedPreferences.setMockInitialValues({});
        } else {
          FlutterSecureStorage.setMockInitialValues({});
          addTearDown(() => FlutterSecureStorage.setMockInitialValues({}));
        }

        Future<app.AppStartupData> start() => app.initializeAppStartup(
          isWeb: isWeb,
          initializeTimeZone: () {},
          retireLegacyBackgroundService: () async {},
        );

        final first = await start();
        addTearDown(first.secureStorage.dispose);
        expect(first.avatarColors, isEmpty);
        const json =
            '{"pixiv-sample":{"hair":"#22aadd"},'
            '"donut-chan":{"accessory":"#116633"}}';
        await first.secureStorage.saveAvatarColorsJson(json);

        final restored = await start();
        addTearDown(restored.secureStorage.dispose);
        expect(restored.avatarColors, decodeAvatarColorsMap(json));
        await tester.pumpWidget(
          app.buildInitializedApp(
            restored,
            home: Consumer(
              builder: (_, ref, _) =>
                  Text(encodeAvatarColorsMap(ref.watch(avatarColorsProvider))),
            ),
          ),
        );
        expect(find.text(json), findsOneWidget);
      },
    );
  }

  for (final failRead in [true, false]) {
    testWidgets(
      'RED-150 ${failRead ? 'failed read' : 'unknown id'} defaults to Pixiv Sample',
      (tester) async {
        final storage = _StartupStorage(
          failAvatarModelRead: failRead,
          avatarModelId: 'unknown',
        );
        addTearDown(storage.dispose);
        final startup = await app.initializeAppStartup(
          isWeb: false,
          createNativeStorage: () => storage,
          initializeTimeZone: () {},
          retireLegacyBackgroundService: () async {},
        );
        expect(startup.avatarModelId, 'pixiv-sample');

        await tester.pumpWidget(
          app.buildInitializedApp(
            startup,
            home: Consumer(
              builder: (_, ref, _) => Text(ref.watch(avatarModelIdProvider)),
            ),
          ),
        );
        expect(find.text('pixiv-sample'), findsOneWidget);
      },
    );
  }

  for (final isWeb in [false, true]) {
    testWidgets(
      'GREEN-150 persists and restores Donut-Chan on ${isWeb ? 'web' : 'native'}',
      (tester) async {
        if (isWeb) {
          SharedPreferences.setMockInitialValues({});
        } else {
          FlutterSecureStorage.setMockInitialValues({});
          addTearDown(() => FlutterSecureStorage.setMockInitialValues({}));
        }

        Future<app.AppStartupData> start() => app.initializeAppStartup(
          isWeb: isWeb,
          initializeTimeZone: () {},
          retireLegacyBackgroundService: () async {},
        );

        final first = await start();
        addTearDown(first.secureStorage.dispose);
        expect(first.avatarModelId, 'pixiv-sample');
        await first.secureStorage.saveAvatarModelId('donut-chan');

        final startup = await start();
        addTearDown(startup.secureStorage.dispose);
        expect(startup.avatarModelId, 'donut-chan');
        await tester.pumpWidget(
          app.buildInitializedApp(
            startup,
            home: Consumer(
              builder: (_, ref, _) => Text(ref.watch(avatarModelIdProvider)),
            ),
          ),
        );
        expect(find.text('donut-chan'), findsOneWidget);
      },
    );
  }

  test('RED-147 avatar read failure defaults to off', () async {
    final storage = _StartupStorage(failAvatarRead: true);
    addTearDown(storage.dispose);

    final startup = await app.initializeAppStartup(
      isWeb: false,
      createNativeStorage: () => storage,
      initializeTimeZone: () {},
      retireLegacyBackgroundService: () async {},
    );

    expect(startup.avatarEnabled, isFalse);
    expect(startup.appTextScale, 1.25);
  });

  for (final isWeb in [false, true]) {
    testWidgets(
      'GREEN-147 restores the stored avatar preference on ${isWeb ? 'web' : 'native'}',
      (tester) async {
        if (isWeb) {
          SharedPreferences.setMockInitialValues({'AVATAR_ENABLED': 'true'});
        } else {
          FlutterSecureStorage.setMockInitialValues({'AVATAR_ENABLED': 'true'});
          addTearDown(() => FlutterSecureStorage.setMockInitialValues({}));
        }

        final startup = await app.initializeAppStartup(
          isWeb: isWeb,
          initializeTimeZone: () {},
          retireLegacyBackgroundService: () async {},
        );
        addTearDown(startup.secureStorage.dispose);
        expect(startup.avatarEnabled, isTrue);

        await tester.pumpWidget(
          app.buildInitializedApp(
            startup,
            home: Consumer(
              builder: (_, ref, _) =>
                  Text('avatar:${ref.watch(avatarEnabledProvider)}'),
            ),
          ),
        );
        expect(find.text('avatar:true'), findsOneWidget);

        await startup.secureStorage.saveAvatarEnabled(false);
        expect(await startup.secureStorage.getAvatarEnabled(), isFalse);
      },
    );
  }

  testWidgets(
    'failed initialization keeps account UI hidden and retry waits for success',
    (tester) async {
      final retryResult = Completer<int>();
      var attempts = 0;

      await tester.pumpWidget(
        AppStartup<int>(
          initialize: () {
            attempts++;
            if (attempts == 1) {
              return Future<int>.error(
                StateError('private initialization detail'),
              );
            }
            return retryResult.future;
          },
          builder: (context, value) =>
              MaterialApp(home: Text('Account UI $value')),
        ),
      );
      expect(find.text('Đang khởi tạo ứng dụng…'), findsOneWidget);
      expect(find.textContaining('Account UI'), findsNothing);

      await tester.pump();
      expect(attempts, 1);
      expect(find.text('Chưa thể khởi tạo ứng dụng.'), findsOneWidget);
      expect(find.text('private initialization detail'), findsNothing);
      expect(find.textContaining('Account UI'), findsNothing);

      final retry = tester.widget<FilledButton>(find.byType(FilledButton));
      retry.onPressed!();
      retry.onPressed!();
      await tester.pump();
      expect(attempts, 2);
      expect(find.text('Đang khởi tạo ứng dụng…'), findsOneWidget);
      expect(find.textContaining('Account UI'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    },
  );

  testWidgets('delayed initialization hands off to the app exactly once', (
    tester,
  ) async {
    final initialization = Completer<int>();
    var builderCalls = 0;

    await tester.pumpWidget(
      AppStartup<int>(
        initialize: () => initialization.future,
        builder: (context, value) {
          builderCalls++;
          return MaterialApp(home: Text('Initialized app $value'));
        },
      ),
    );

    expect(find.text('Đang khởi tạo ứng dụng…'), findsOneWidget);
    expect(find.textContaining('Initialized app'), findsNothing);
    expect(builderCalls, 0);

    initialization.complete(7);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Initialized app 7'), findsOneWidget);
    expect(builderCalls, 1);
  });

  testWidgets('RED-139c pending startup shows brand and progress', (
    tester,
  ) async {
    final pending = Completer<int>();
    await tester.pumpWidget(
      AppStartup<int>(
        initialize: () => pending.future,
        builder: (_, value) => Text('$value'),
      ),
    );
    expect(find.byKey(const Key('app-startup-brand-mark')), findsOneWidget);
    expect(find.text('Crypto Portfolio'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('RED-139d startup cross-fades into the app', (tester) async {
    final pending = Completer<int>();
    await tester.pumpWidget(
      AppStartup<int>(
        initialize: () => pending.future,
        builder: (_, value) => MaterialApp(home: Text('Ready $value')),
      ),
    );
    pending.complete(7);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));
    expect(find.text('Crypto Portfolio'), findsOneWidget);
    expect(find.text('Ready 7'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Crypto Portfolio'), findsNothing);
    expect(find.text('Ready 7'), findsOneWidget);
  });

  testWidgets('reduced motion keeps startup progress static and labeled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            disableAnimations: true,
            accessibleNavigation: true,
          ),
          child: AppStartupStatusView(isLoading: true),
        ),
      ),
    );

    expect(find.text('Đang khởi tạo ứng dụng…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byKey(const Key('app-startup-brand-mark')), findsOneWidget);
    final progressSemantics = tester.widget<Semantics>(
      find.byKey(const Key('app-startup-progress-semantics')),
    );
    expect(progressSemantics.properties.label, 'Đang khởi tạo ứng dụng');
    expect(progressSemantics.properties.liveRegion, isTrue);
  });

  test(
    'legacy read failure does not block independent text-scale reads',
    () async {
      final calls = <String>[];
      final storage = _StartupStorage(
        failBiometricRead: true,
        textScale: 1.2,
        calls: calls,
      );

      final startup = await app.initializeAppStartup(
        isWeb: false,
        createNativeStorage: () => storage,
        initializeTimeZone: () {},
        retireLegacyBackgroundService: () async {},
      );

      expect(calls, ['biometric', 'textScale']);
      expect(startup.requireBiometrics, isFalse);
      expect(startup.hideBalanceDefault, isFalse);
      expect(startup.themeMode, ThemeMode.system);
      expect(startup.currency, 'USD');
      expect(startup.timeZoneId, AppTimeZone.defaultId);
      expect(startup.appTextScale, 1.2);
    },
  );

  test('selection restoration falls back when storage fails', () async {
    final storage = _StartupStorage(failSelection: true);
    final startup = await app.initializeAppStartup(
      isWeb: false,
      createNativeStorage: () => storage,
      initializeTimeZone: () {},
      retireLegacyBackgroundService: () async {},
    );
    expect(startup.selectedConnectionId, defaultConnectionId);
    storage.dispose();
  });

  test('selection restoration loads stored value', () async {
    final storage = _StartupStorage(selection: 'other');
    final startup = await app.initializeAppStartup(
      isWeb: false,
      createNativeStorage: () => storage,
      initializeTimeZone: () {},
      retireLegacyBackgroundService: () async {},
    );
    expect(startup.selectedConnectionId, 'other');
    storage.dispose();
  });

  testWidgets(
    'initialized values retain provider overrides and native biometric gate',
    (tester) async {
      final storage = _StartupStorage();
      final startup = app.AppStartupData(
        secureStorage: storage,
        requireBiometrics: true,
        hideBalanceDefault: true,
        themeMode: ThemeMode.dark,
        currency: 'VND',
        timeZoneId: 'Asia/Ho_Chi_Minh',
        appTextScale: 1.25,
        selectedConnectionId: 'other',
      );

      await tester.pumpWidget(
        app.buildInitializedApp(
          startup,
          home: Consumer(
            builder: (context, ref, child) => Column(
              children: [
                Text('theme:${ref.watch(themeModeProvider).name}'),
                Text('currency:${ref.watch(currencyProvider)}'),
                Text('hidden:${ref.watch(hideBalanceProvider)}'),
                Text('timezone:${ref.watch(appTimeZoneProvider)}'),
                Text('scale:${ref.watch(appTextScaleProvider)}'),
                Text('connection:${ref.watch(selectedConnectionIdProvider)}'),
                Text(
                  'same-storage:${identical(ref.watch(secureStorageProvider), storage)}',
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('theme:dark'), findsOneWidget);
      expect(find.text('currency:VND'), findsOneWidget);
      expect(find.text('hidden:true'), findsOneWidget);
      expect(find.text('timezone:Asia/Ho_Chi_Minh'), findsOneWidget);
      expect(find.text('scale:1.25'), findsOneWidget);
      expect(find.text('connection:okx-default'), findsOneWidget);
      expect(find.text('same-storage:true'), findsOneWidget);
      expect(
        tester
            .widget<app.TradingBalanceApp>(find.byType(app.TradingBalanceApp))
            .requireBiometrics,
        isTrue,
      );
    },
  );
}
