import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/currency/currency_display_mode.dart';
import 'package:trading_balance_f/features/orders/data/okx_order_model.dart';
import 'package:trading_balance_f/features/orders/data/okx_position_model.dart';
import 'package:trading_balance_f/features/orders/presentation/orders_screen.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/order_provider.dart';
import 'package:trading_balance_f/features/portfolio/presentation/portfolio_screen.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';

void main() {
  testWidgets('renders position notional in dual currency and masks it', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        orderFilterProvider.overrideWith((ref) => 'SWAP'),
        orderTabProvider.overrideWith((ref) => OrderTab.positions),
        positionsFutureProvider.overrideWith(
          (ref) async => const [
            OkxPosition(
              instId: 'BTC-USDT-SWAP',
              posSide: 'long',
              lever: '5',
              notionalUsd: '100',
            ),
          ],
        ),
        currencyProvider.overrideWith((ref) => CurrencyDisplayMode.usdtVnd),
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
    await tester.pump();
    await tester.pump();

    expect(find.text('Giá trị vị thế:'), findsOneWidget);
    expect(find.text('100.00 USDT'), findsOneWidget);
    expect(find.text('≈ 2.540.000 đ'), findsOneWidget);

    container.read(hideBalanceProvider.notifier).state = true;
    await tester.pump();

    expect(find.text('******'), findsNWidgets(2));
  });

  testWidgets('renders a filled order notional', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderFilterProvider.overrideWith((ref) => 'SWAP'),
          orderTabProvider.overrideWith((ref) => OrderTab.history),
          ordersFutureProvider.overrideWith(
            (ref) async => const [
              OkxOrder(
                instId: 'ETH-USDT-SWAP',
                instType: 'SWAP',
                side: 'buy',
                state: 'filled',
                fillNotionalUsd: '250',
              ),
            ],
          ),
          currencyProvider.overrideWith((ref) => CurrencyDisplayMode.usd),
          vndExchangeRateProvider.overrideWith((ref) async => 25400),
          themeModeProvider.overrideWith((ref) => ThemeMode.light),
        ],
        child: const MaterialApp(home: OrdersScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Giá trị đã khớp:'), findsOneWidget);
    expect(find.text(r'$250.00'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
