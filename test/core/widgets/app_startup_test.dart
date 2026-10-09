import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/navigation/navigation_preferences.dart';
import 'package:trading_balance_f/core/navigation/navigation_preferences_provider.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/core/theme/app_theme.dart';
import 'package:trading_balance_f/core/timezone/app_time_zone.dart';
import 'package:trading_balance_f/core/typography/app_text_scale.dart';
import 'package:trading_balance_f/core/widgets/app_startup.dart';
import 'package:trading_balance_f/main.dart' as app;
import 'package:trading_balance_f/features/portfolio/presentation/portfolio_screen.dart'
    show hideBalanceProvider;
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart'
    show currencyProvider, themeModeProvider;

class _StartupStorage extends SecureStorageHelper {
  _StartupStorage({
    this.failBiometricRead = false,
    this.biometric = true,
    this.hideBalance = true,
    this.theme = 'dark',
    this.currency = 'VND',
    this.timeZoneId = 'Asia/Ho_Chi_Minh',
    this.textScale = 1.25,
    this.navigation = NavigationPreferences.defaults,
    this.calls,
  }) : super(const FlutterSecureStorage());

  final bool failBiometricRead;
  final bool biometric;
  final bool hideBalance;
  final String theme;
  final String currency;
  final String timeZoneId;
  final double textScale;
  final NavigationPreferences navigation;
  final List<String>? calls;

  @override
  Future<bool> getBiometricAuth() async {
    calls?.add('biometric');
    if (failBiometricRead) {
      throw StateError('private storage failure detail');
    }
    return biometric;
  }

  @override
  Future<bool> getHideBalanceDefault() async {
    calls?.add('hideBalance');
    return hideBalance;
  }

  @override
  Future<String> getThemeMode() async {
    calls?.add('theme');
    return theme;
  }

  @override
  Future<String> getCurrency() async {
    calls?.add('currency');
    return currency;
  }

  @override
  Future<String> getTimeZoneId() async {
    calls?.add('timeZone');
    return timeZoneId;
  }

  @override
  Future<double> getAppTextScale() async {
    calls?.add('textScale');
    return textScale;
  }

  @override
  Future<NavigationPreferences> getNavigationPreferences() async {
    calls?.add('navigation');
    return navigation;
  }
}

void main() {
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

  testWidgets('reduced motion keeps startup progress static and labeled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            disableAnimations: true,
            accessibleNavigation: true,
          ),
          child: const AppStartupStatusView(isLoading: true),
        ),
      ),
    );

    expect(find.text('Đang khởi tạo ứng dụng…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.hourglass_empty), findsOneWidget);
    final progressSemantics = tester.widget<Semantics>(
      find.byKey(const Key('app-startup-progress-semantics')),
    );
    expect(progressSemantics.properties.label, 'Đang khởi tạo ứng dụng');
    expect(progressSemantics.properties.liveRegion, isTrue);
  });

  test(
    'legacy read failure does not block independent text-scale/navigation reads',
    () async {
      final calls = <String>[];
      const navigation = NavigationPreferences(
        displayMode: NavigationDisplayMode.floating,
        floatingEdge: NavigationEdge.top,
        buttonScale: 1,
        buttonOpacity: 1,
        enabledDestinationIds: ['home', 'settings'],
        destinationOrderIds: ['home', 'settings'],
      );
      final storage = _StartupStorage(
        failBiometricRead: true,
        textScale: 1.2,
        navigation: navigation,
        calls: calls,
      );

      final startup = await app.initializeAppStartup(
        isWeb: false,
        createNativeStorage: () => storage,
        initializeTimeZone: () {},
        retireLegacyBackgroundService: () async {},
      );

      expect(calls, ['biometric', 'textScale', 'navigation']);
      expect(startup.requireBiometrics, isFalse);
      expect(startup.hideBalanceDefault, isFalse);
      expect(startup.themeMode, ThemeMode.system);
      expect(startup.currency, 'USD');
      expect(startup.timeZoneId, AppTimeZone.defaultId);
      expect(startup.appTextScale, 1.2);
      expect(startup.navigationPreferences, navigation);
    },
  );

  testWidgets(
    'initialized values retain provider overrides and native biometric gate',
    (tester) async {
      final storage = _StartupStorage(
        navigation: NavigationPreferences.defaults.copyWith(
          displayMode: NavigationDisplayMode.floating,
        ),
      );
      final startup = app.AppStartupData(
        secureStorage: storage,
        requireBiometrics: true,
        hideBalanceDefault: true,
        themeMode: ThemeMode.dark,
        currency: 'VND',
        timeZoneId: 'Asia/Ho_Chi_Minh',
        appTextScale: 1.25,
        navigationPreferences: storage.navigation,
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
                Text(
                  'navigation:${ref.watch(navigationPreferencesInitialProvider).displayMode.name}',
                ),
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
      expect(find.text('navigation:floating'), findsOneWidget);
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
