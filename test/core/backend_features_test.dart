import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trading_balance_f/core/backend_features.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/features/orders/data/trade_api_client.dart';
import 'package:trading_balance_f/features/orders/presentation/orders_screen.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/order_provider.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/trade_session_provider.dart';
import 'package:trading_balance_f/features/orders/presentation/widgets/order_cancellation_control.dart';
import 'package:trading_balance_f/features/orders/presentation/widgets/order_filter_controls.dart';
import 'package:trading_balance_f/features/orders/presentation/widgets/trade_account_controls.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_trade_access_page.dart';
import 'package:trading_balance_f/features/strategy/data/strategy_api_client.dart';
import 'package:trading_balance_f/main.dart' show WebStorageHelper;

void main() {
  test('disabled API providers fail before any backend request', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(backendFeaturesEnabledProvider), isFalse);

    final tradeApi = container.read(tradeApiProvider);
    expect(tradeApi, isA<DisabledTradeApi>());
    await expectLater(
      tradeApi.restoreSession(),
      throwsA(
        isA<TradeApiException>().having(
          (error) => error.code,
          'code',
          'backend_disabled',
        ),
      ),
    );

    final strategyApi = container.read(strategyApiProvider);
    expect(strategyApi, isA<DisabledStrategyApi>());
    await expectLater(
      strategyApi.listStrategies(''),
      throwsA(
        isA<StrategyApiException>().having(
          (error) => error.code,
          'code',
          'backend_disabled',
        ),
      ),
    );
  });

  testWidgets('Settings hides the backend entry only while the gate is false', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final storage = WebStorageHelper(preferences);

    for (final enabled in [false, true]) {
      await tester.pumpWidget(
        ProviderScope(
          key: ValueKey(enabled),
          overrides: [
            backendFeaturesEnabledProvider.overrideWith((ref) => enabled),
            secureStorageProvider.overrideWithValue(storage),
            vndExchangeRateProvider.overrideWith((ref) async => 25400),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('settings-trade-access-button')),
        enabled ? findsOneWidget : findsNothing,
      );
      expect(find.text('Ẩn số dư mặc định'), findsOneWidget);
      expect(find.text('Khoá sinh trắc học'), findsOneWidget);
    }
  });

  testWidgets(
    'gate false avoids backend requests from Orders and trade access',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final storage = WebStorageHelper(preferences);
      final adapter = _CountingAdapter();
      final api = _BrowserTradeApi(adapter);
      final container = ProviderContainer(
        overrides: [
          backendFeaturesEnabledProvider.overrideWith((ref) => false),
          tradeApiProvider.overrideWithValue(api),
          secureStorageProvider.overrideWithValue(storage),
          positionsFutureProvider.overrideWith((ref) async => const []),
          ordersFutureProvider.overrideWith((ref) async => const []),
          vndExchangeRateProvider.overrideWith((ref) async => 25400),
          themeModeProvider.overrideWith((ref) => ThemeMode.light),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: OrdersScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final ordersRequestCount = adapter.requestCount;
      final ordersShowsLoginStatus =
          find.byTooltip('Đã đăng nhập').evaluate().isNotEmpty ||
          find.byTooltip('Chưa đăng nhập').evaluate().isNotEmpty;
      final filtersRemain = find.byType(OrderFilterControls).evaluate().length;
      final cancelControls = find
          .byType(OrderCancellationControl)
          .evaluate()
          .length;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SettingsTradeAccessPage()),
        ),
      );
      await tester.pumpAndSettle();
      final settingsRequestCount = adapter.requestCount;
      final settingsShowsTradeControls = find
          .byType(TradeSessionControls)
          .evaluate()
          .isNotEmpty;

      expect(
        {
          'ordersRequests': ordersRequestCount,
          'settingsRequests': settingsRequestCount,
          'ordersLoginStatus': ordersShowsLoginStatus,
          'orderFilterControls': filtersRemain,
          'orderCancelControls': cancelControls,
          'settingsTradeControls': settingsShowsTradeControls,
        },
        {
          'ordersRequests': 0,
          'settingsRequests': 0,
          'ordersLoginStatus': false,
          'orderFilterControls': 1,
          'orderCancelControls': 0,
          'settingsTradeControls': false,
        },
      );
    },
  );
}

class _BrowserTradeApi extends TradeApiClient {
  _BrowserTradeApi(_CountingAdapter adapter)
    : super(
        baseUrl: 'https://trade.example.com',
        dio: Dio()..httpClientAdapter = adapter,
      );

  @override
  bool get supportsSessionRestoration => true;
}

class _CountingAdapter implements HttpClientAdapter {
  int requestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    return ResponseBody.fromString(
      jsonEncode({
        'token': 'test-token',
        'expiresAt': DateTime.utc(2030).toIso8601String(),
        'accountIdentifier': 'test-account',
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
