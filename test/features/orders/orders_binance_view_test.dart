import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/exchange/exchange_models.dart';
import 'package:trading_balance_f/core/exchange/exchange_registry.dart';
import 'package:trading_balance_f/core/exchange/exchange_scope.dart';
import 'package:trading_balance_f/exchanges/binance/binance_adapter.dart';
import 'package:trading_balance_f/features/orders/presentation/orders_screen.dart';
import 'package:trading_balance_f/features/orders/presentation/widgets/order_cancellation_control.dart';
import 'package:trading_balance_f/features/portfolio/presentation/portfolio_screen.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';
import '../../support/fake_exchange_adapter.dart';

class _Fake extends FakeExchangeAdapter {
  @override
  ExchangeCapabilities get capabilities =>
      const ExchangeCapabilities(readableProducts: ['SWAP', 'SPOT', 'MARGIN']);
  @override
  Future<List<ExchangePosition>> readPositions(
    Ref ref,
    ExchangeScope scope,
  ) async => [
    const ExchangePosition(
      key: InstrumentKey(
        exchange: ExchangeId.binance,
        product: 'SWAP',
        nativeId: 'BTCUSDT',
        base: 'BTC',
        quote: 'USDT',
      ),
      productLabel: 'SWAP',
    ),
  ];
  @override
  Future<AccountSnapshot> readAccount(Ref ref, ExchangeScope scope) async =>
      const AccountSnapshot(
        balances: [AssetBalance(wallet: 'Spot', asset: 'UNKNOWN', total: '1')],
        marginRows: [
          MarginAccountRow(asset: 'BTC', net: '2', borrowed: '1'),
          MarginAccountRow(
            key: InstrumentKey(
              exchange: ExchangeId.binance,
              product: 'MARGIN',
              nativeId: 'BTCUSDT',
              base: 'BTC',
              quote: 'USDT',
            ),
            baseNet: '3',
            indexPrice: '4',
          ),
        ],
      );
}

void main() {
  for (final web in [false, true]) {
    testWidgets('Binance positions and filters web=$web', (tester) async {
      final container = ProviderContainer(
        overrides: [
          selectedConnectionIdProvider.overrideWith((ref) => 'fake'),
          exchangeRegistryProvider.overrideWith(
            (ref) => [
              ExchangeRegistration(
                profile: const ConnectionProfile(
                  connectionId: 'fake',
                  exchange: ExchangeId.binance,
                  label: 'Binance',
                ),
                adapter: _Fake(),
              ),
            ],
          ),
          binanceIsWebProvider.overrideWithValue(web),
          vndExchangeRateProvider.overrideWith((ref) async => 25400),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: OrdersScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('BTC/USDT'), findsWidgets);
      expect(find.text('BTCUSDT'), findsNothing);
      expect(find.text('Tất cả'), findsOneWidget);
      expect(find.text('USDⓈ-M'), findsOneWidget);
      expect(find.text('Spot'), web ? findsNothing : findsOneWidget);
      expect(find.text('Margin'), web ? findsNothing : findsOneWidget);
      expect(find.textContaining('Cross Margin'), findsOneWidget);
      expect(find.textContaining('Isolated Margin'), findsOneWidget);
      expect(find.textContaining('—'), findsWidgets);
      expect(find.byType(OrderCancellationControl), findsNothing);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    });
  }
  testWidgets('missing Binance total and unpriced asset are visible', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        selectedConnectionIdProvider.overrideWith((ref) => 'fake'),
        exchangeRegistryProvider.overrideWith(
          (ref) => [
            ExchangeRegistration(
              profile: const ConnectionProfile(
                connectionId: 'fake',
                exchange: ExchangeId.binance,
                label: 'Binance',
              ),
              adapter: _Fake(),
            ),
          ],
        ),
        vndExchangeRateProvider.overrideWith((ref) async => 25400),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PortfolioScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('—'), findsWidgets);
    expect(find.text('Chưa định giá'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });
}
