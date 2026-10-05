import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'single-type polling remains one second and skips an active load',
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
      expect(find.text('Đóng tất cả vị thế'), findsNothing);

      final statusRect = tester.getRect(
        find.byKey(const Key('order-tab-select')),
      );
      final typeRect = tester.getRect(
        find.byKey(const Key('order-type-select')),
      );
      final closeAllRect = tester.getRect(find.byTooltip('Đóng tất cả vị thế'));
      expect(statusRect.top, typeRect.top);
      expect(statusRect.right, lessThan(typeRect.left));
      expect(typeRect.right, lessThan(closeAllRect.left));
      expect(closeAllRect.width, 48);
      expect(closeAllRect.height, 48);
      expect(closeAllRect.center.dy, closeTo(typeRect.center.dy, 2));
      expect(closeAllRect.right, lessThanOrEqualTo(width));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

Widget _ordersScreen({
  required String filter,
  required List<Completer<List<OkxOrder>>> requests,
  required VoidCallback onLoad,
}) {
  return ProviderScope(
    overrides: [
      orderFilterProvider.overrideWith((ref) => filter),
      orderTabProvider.overrideWith((ref) => OrderTab.pending),
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
        (ref) async => TradePositionsSnapshot(
          accountIdentifier: 'test-account',
          positions: const [],
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
    state = TradeSessionState(
      session: TradeSession(
        bearerToken: 'test-token',
        accountIdentifier: 'test-account',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
  }
}
