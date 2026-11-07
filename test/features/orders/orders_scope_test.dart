import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/backend_features.dart';
import 'package:trading_balance_f/core/exchange/exchange_models.dart';
import 'package:trading_balance_f/core/exchange/exchange_registry.dart';
import 'package:trading_balance_f/core/exchange/exchange_scope.dart';
import 'package:trading_balance_f/exchanges/okx/okx_adapter.dart';
import 'package:trading_balance_f/features/orders/data/okx_order_model.dart';
import 'package:trading_balance_f/features/orders/data/okx_position_model.dart';
import 'package:trading_balance_f/features/orders/presentation/orders_screen.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/order_provider.dart';
import 'package:trading_balance_f/features/orders/presentation/widgets/order_cancellation_control.dart';
import 'package:trading_balance_f/features/orders/presentation/widgets/trade_account_controls.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';

import '../../support/fake_exchange_adapter.dart';

const _key = InstrumentKey(
  exchange: ExchangeId.binance,
  product: 'SWAP',
  nativeId: 'FAKE-USDT-SWAP',
);

class _Fake extends FakeExchangeAdapter {
  @override
  Future<List<ExchangePosition>> readPositions(
    Ref ref,
    ExchangeScope scope,
  ) async => [
    const ExchangePosition(key: _key, productLabel: 'SWAP', side: 'long'),
  ];
  @override
  Future<List<ExchangeOrder>> readOrders(Ref ref, ExchangeScope scope) async =>
      [
        const ExchangeOrder(
          id: 'fake',
          key: _key,
          productLabel: 'SWAP',
          side: 'buy',
        ),
      ];
}

void main() {
  for (final tab in [OrderTab.positions, OrderTab.pending]) {
    testWidgets('late OKX ${tab.name} do not render under fake exchange', (
      tester,
    ) async {
      final positions = Completer<List<OkxPosition>>();
      final orders = Completer<List<OkxOrder>>();
      final container = ProviderContainer(
        overrides: [
          exchangeRegistryProvider.overrideWith(
            (ref) => [
              const ExchangeRegistration(
                profile: ConnectionProfile(
                  connectionId: 'okx-default',
                  exchange: ExchangeId.okx,
                  label: 'OKX',
                ),
                adapter: OkxAdapter(),
              ),
              ExchangeRegistration(
                profile: const ConnectionProfile(
                  connectionId: 'fake',
                  exchange: ExchangeId.binance,
                  label: 'Fake',
                ),
                adapter: _Fake(),
              ),
            ],
          ),
          orderTabProvider.overrideWith((ref) => tab),
          positionsFutureProvider.overrideWith((ref) => positions.future),
          ordersFutureProvider.overrideWith((ref) => orders.future),
          vndExchangeRateProvider.overrideWith((ref) async => 25400),
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
      container.read(selectedConnectionIdProvider.notifier).state = 'fake';
      await tester.pump();
      positions.complete([
        const OkxPosition(instId: 'LATE-USDT-SWAP', instType: 'SWAP'),
      ]);
      orders.complete([
        const OkxOrder(instId: 'LATE-USDT-SWAP', instType: 'SWAP'),
      ]);
      await tester.pump();
      await tester.pump();
      expect(find.text('FAKEUSDT'), findsOneWidget);
      expect(find.text('LATEUSDT'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets(
    'fake positions pending and history render without backend controls',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          selectedConnectionIdProvider.overrideWith((ref) => 'fake'),
          exchangeRegistryProvider.overrideWith(
            (ref) => [
              ExchangeRegistration(
                profile: const ConnectionProfile(
                  connectionId: 'fake',
                  exchange: ExchangeId.binance,
                  label: 'Fake',
                ),
                adapter: _Fake(),
              ),
            ],
          ),
          backendFeaturesEnabledProvider.overrideWith((ref) => true),
          vndExchangeRateProvider.overrideWith((ref) async => 25400),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: OrdersScreen()),
        ),
      );
      for (final tab in OrderTab.values) {
        container.read(orderTabProvider.notifier).state = tab;
        await tester.pump();
        await tester.pump();
        expect(find.text('FAKEUSDT'), findsOneWidget);
        expect(find.byType(TradeAccountControls), findsNothing);
        expect(find.byType(OrderCancellationControl), findsNothing);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
