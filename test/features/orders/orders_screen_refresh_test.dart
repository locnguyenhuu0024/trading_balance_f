import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/network/backend_data_client.dart';
import 'package:trading_balance_f/core/currency/currency_display_mode.dart';
import 'package:trading_balance_f/features/orders/data/okx_order_model.dart';
import 'package:trading_balance_f/features/orders/data/okx_position_model.dart';
import 'package:trading_balance_f/features/orders/data/trade_api_client.dart';
import 'package:trading_balance_f/features/orders/presentation/orders_screen.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/order_provider.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/trade_session_provider.dart';
import 'package:trading_balance_f/features/orders/presentation/widgets/trade_account_controls.dart';
import 'package:trading_balance_f/features/portfolio/presentation/portfolio_screen.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';

void main() {
  testWidgets('pending tab keeps its trade control in the body', (
    tester,
  ) async {
    final requests = <Completer<List<OkxOrder>>>[];
    await tester.pumpWidget(
      _ordersScreen(filter: 'ALL', requests: requests, onLoad: () {}),
    );
    await tester.pump();

    expect(find.byKey(const Key('order-tab-select')), findsOneWidget);
    expect(find.byType(TradeAccountControls), findsOneWidget);
    expect(find.byTooltip('Đóng tất cả vị thế'), findsNothing);
    expect(find.byTooltip('Làm mới dữ liệu'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('ALL polling waits five seconds and skips an active load', (
    tester,
  ) async {
    final requests = <Completer<List<OkxOrder>>>[];
    var loadCount = 0;

    await tester.pumpWidget(
      _ordersScreen(
        filter: 'ALL',
        requests: requests,
        onLoad: () => loadCount++,
      ),
    );
    await tester.pump();
    expect(loadCount, 1);
    requests.first.complete(const []);
    await tester.pump();
    await tester.pump();

    await tester.pump(const Duration(seconds: 4));
    expect(loadCount, 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(loadCount, 2);

    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(loadCount, 2);
    expect(find.text('Không có lệnh nào đang chờ khớp.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'single-type polling waits five seconds and skips an active load',
    (tester) async {
      final requests = <Completer<List<OkxOrder>>>[];
      var loadCount = 0;

      await tester.pumpWidget(
        _ordersScreen(
          filter: 'MARGIN',
          requests: requests,
          onLoad: () => loadCount++,
        ),
      );
      await tester.pump();
      expect(loadCount, 1);
      requests.first.complete(const []);
      await tester.pump();
      await tester.pump();

      await tester.pump(const Duration(seconds: 4));
      expect(loadCount, 1);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(loadCount, 2);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(loadCount, 2);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('positions filters and close-all stay aligned without overflow', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final width in [320.0, 390.0, 800.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpWidget(_positionsOrdersScreen());
      await tester.pumpAndSettle();

      expect(find.byType(TradeAccountControls), findsOneWidget);
      expect(find.byTooltip('Đóng tất cả vị thế'), findsOneWidget);
      expect(find.byTooltip('Làm mới dữ liệu'), findsOneWidget);
      expect(find.text('Đóng tất cả vị thế'), findsNothing);

      final statusRect = tester.getRect(
        find.byKey(const Key('order-tab-select')),
      );
      final typeRect = tester.getRect(
        find.byKey(const Key('order-type-select')),
      );
      final closeAllRect = tester.getRect(find.byTooltip('Đóng tất cả vị thế'));
      final refreshRect = tester.getRect(
        find.byKey(const Key('orders-manual-refresh')),
      );
      expect(statusRect.top, typeRect.top);
      expect(statusRect.right, lessThan(typeRect.left));
      expect(typeRect.right, lessThan(closeAllRect.left));
      expect(closeAllRect.width, 48);
      expect(closeAllRect.height, 48);
      expect(closeAllRect.center.dy, closeTo(typeRect.center.dy, 2));
      expect(closeAllRect.right, lessThanOrEqualTo(width));
      expect(refreshRect.width, 48);
      expect(refreshRect.height, 48);
      expect(refreshRect.right, lessThanOrEqualTo(width));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('RED-102 signed-out orders keeps refresh visible and disabled', (
    tester,
  ) async {
    final api = TradeApiClient(baseUrl: 'https://trade.example');
    var reads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderFilterProvider.overrideWith((ref) => 'ALL'),
          orderTabProvider.overrideWith((ref) => OrderTab.positions),
          tradeApiProvider.overrideWithValue(api),
          tradeSessionProvider.overrideWith(
            (ref) => TradeSessionController(api),
          ),
          positionsFutureProvider.overrideWith((ref) async {
            reads++;
            return [];
          }),
          themeModeProvider.overrideWith((ref) => ThemeMode.light),
          currencyProvider.overrideWith((ref) => CurrencyDisplayMode.usd),
          vndExchangeRateProvider.overrideWith((ref) async => 25400),
        ],
        child: const MaterialApp(home: OrdersScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final refresh = find.byTooltip('Làm mới dữ liệu');
    expect(refresh, findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('orders-manual-refresh')))
          .onPressed,
      isNull,
    );
    final readsBeforeTap = reads;
    await tester.tap(refresh);
    await tester.pump();
    expect(reads, readsBeforeTap);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('manual refresh reloads the active positions provider only', (
    tester,
  ) async {
    final api = TradeApiClient(baseUrl: 'https://trade.example');
    var positionLoads = 0;
    var orderLoads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderFilterProvider.overrideWith((ref) => 'MARGIN'),
          orderTabProvider.overrideWith((ref) => OrderTab.positions),
          tradeApiProvider.overrideWithValue(api),
          tradeSessionProvider.overrideWith(
            (ref) => _AuthenticatedTradeSessionController(api),
          ),
          tradePositionsProvider.overrideWith((ref) async {
            positionLoads++;
            return const TradePositionsSnapshot(
              accountIdentifier: 'test-account',
              positions: [],
            );
          }),
          ordersFutureProvider.overrideWith((ref) async {
            orderLoads++;
            return const [];
          }),
          themeModeProvider.overrideWith((ref) => ThemeMode.light),
          currencyProvider.overrideWith((ref) => CurrencyDisplayMode.usd),
          vndExchangeRateProvider.overrideWith((ref) async => 25400),
        ],
        child: const MaterialApp(home: OrdersScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(positionLoads, 1);

    await tester.tap(find.byKey(const Key('orders-manual-refresh')));
    await tester.pumpAndSettle();

    expect(positionLoads, 2);
    expect(orderLoads, 0);
    expect(find.text('MARGIN'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('automatic polling stops after a terminal configuration error', (
    tester,
  ) async {
    final api = TradeApiClient(baseUrl: 'https://trade.example');
    var loadCalls = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderFilterProvider.overrideWith((ref) => 'MARGIN'),
          orderTabProvider.overrideWith((ref) => OrderTab.pending),
          tradeApiProvider.overrideWithValue(api),
          tradeSessionProvider.overrideWith(
            (ref) => _AuthenticatedTradeSessionController(api),
          ),
          ordersFutureProvider.overrideWith((ref) async {
            loadCalls++;
            throw const BackendDataException(
              code: 'api_not_configured',
              message: 'Not configured.',
            );
          }),
          themeModeProvider.overrideWith((ref) => ThemeMode.light),
          currencyProvider.overrideWith((ref) => CurrencyDisplayMode.usd),
          vndExchangeRateProvider.overrideWith((ref) async => 25400),
        ],
        child: const MaterialApp(home: OrdersScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(loadCalls, 1);

    await tester.pump(const Duration(seconds: 30));
    expect(loadCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('old positions are hidden while a replacement session loads', (
    tester,
  ) async {
    final api = _PendingTradePositionsApi();
    final session = _AuthenticatedTradeSessionController(api);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderFilterProvider.overrideWith((ref) => 'ALL'),
          orderTabProvider.overrideWith((ref) => OrderTab.positions),
          tradeApiProvider.overrideWithValue(api),
          tradeSessionProvider.overrideWith((ref) => session),
          themeModeProvider.overrideWith((ref) => ThemeMode.light),
          currencyProvider.overrideWith((ref) => CurrencyDisplayMode.usd),
          vndExchangeRateProvider.overrideWith((ref) async => 25400),
        ],
        child: const MaterialApp(home: OrdersScreen()),
      ),
    );

    await tester.pump();
    expect(api.requests, hasLength(1));
    api.requests.first.complete(
      const TradePositionsSnapshot(
        accountIdentifier: 'test-account',
        positions: [],
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Không có vị thế nào đang mở.'), findsOneWidget);

    session.replace(accountIdentifier: 'replacement-account');
    await tester.pump();
    await tester.pump();
    expect(api.requests, hasLength(2));
    expect(find.text('Không có vị thế nào đang mở.'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    api.requests.last.complete(
      const TradePositionsSnapshot(
        accountIdentifier: 'replacement-account',
        positions: [],
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Không có vị thế nào đang mở.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Widget _ordersScreen({
  required String filter,
  required List<Completer<List<OkxOrder>>> requests,
  required VoidCallback onLoad,
}) {
  final api = TradeApiClient(baseUrl: 'https://trade.example');
  return ProviderScope(
    overrides: [
      orderFilterProvider.overrideWith((ref) => filter),
      orderTabProvider.overrideWith((ref) => OrderTab.pending),
      tradeApiProvider.overrideWithValue(api),
      tradeSessionProvider.overrideWith(
        (ref) => _AuthenticatedTradeSessionController(api),
      ),
      ordersFutureProvider.overrideWith((ref) {
        onLoad();
        final request = Completer<List<OkxOrder>>();
        requests.add(request);
        return request.future;
      }),
      themeModeProvider.overrideWith((ref) => ThemeMode.light),
      currencyProvider.overrideWith((ref) => CurrencyDisplayMode.usd),
      vndExchangeRateProvider.overrideWith((ref) async => 25400),
    ],
    child: const MaterialApp(home: OrdersScreen()),
  );
}

Widget _positionsOrdersScreen() {
  final api = TradeApiClient(baseUrl: 'https://trade.example');
  return ProviderScope(
    overrides: [
      orderFilterProvider.overrideWith((ref) => 'MARGIN'),
      orderTabProvider.overrideWith((ref) => OrderTab.positions),
      tradeApiProvider.overrideWithValue(api),
      tradeSessionProvider.overrideWith(
        (ref) => _AuthenticatedTradeSessionController(api),
      ),
      tradePositionsProvider.overrideWith(
        (ref) async => const TradePositionsSnapshot(
          accountIdentifier: 'test-account',
          positions: [],
        ),
      ),
      themeModeProvider.overrideWith((ref) => ThemeMode.light),
      currencyProvider.overrideWith((ref) => CurrencyDisplayMode.usd),
      vndExchangeRateProvider.overrideWith((ref) async => 25400),
    ],
    child: const MaterialApp(home: OrdersScreen()),
  );
}

class _AuthenticatedTradeSessionController extends TradeSessionController {
  _AuthenticatedTradeSessionController(super.api) {
    replace();
  }

  void replace({String accountIdentifier = 'test-account'}) {
    state = TradeSessionState(
      session: TradeSession(
        bearerToken: 'test-token-$accountIdentifier',
        accountIdentifier: accountIdentifier,
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
  }
}

class _PendingTradePositionsApi extends TradeApiClient {
  _PendingTradePositionsApi() : super(baseUrl: 'https://trade.example');

  final List<Completer<TradePositionsSnapshot>> requests = [];

  @override
  Future<TradePositionsSnapshot> getPositions(String bearerToken) {
    final request = Completer<TradePositionsSnapshot>();
    requests.add(request);
    return request.future;
  }

  @override
  Future<TradePositionsSnapshot> getPositionsCancellable(
    String bearerToken, {
    required CancelToken cancelToken,
  }) => getPositions(bearerToken);
}
