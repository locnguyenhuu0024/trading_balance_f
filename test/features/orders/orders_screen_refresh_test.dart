import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/currency/currency_display_mode.dart';
import 'package:trading_balance_f/features/orders/data/okx_order_model.dart';
import 'package:trading_balance_f/features/orders/presentation/orders_screen.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/order_provider.dart';
import 'package:trading_balance_f/features/portfolio/presentation/portfolio_screen.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';

void main() {
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
