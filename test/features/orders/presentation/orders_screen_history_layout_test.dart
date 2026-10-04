import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/currency/currency_display_mode.dart';
import 'package:trading_balance_f/core/timezone/app_time_zone.dart';
import 'package:trading_balance_f/core/widgets/crypto_icon.dart';
import 'package:trading_balance_f/features/orders/data/okx_order_model.dart';
import 'package:trading_balance_f/features/orders/presentation/orders_screen.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/order_provider.dart';
import 'package:trading_balance_f/features/portfolio/presentation/portfolio_screen.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';

Widget _historyApp(OkxOrder order, double textScale) {
  return ProviderScope(
    overrides: [
      orderFilterProvider.overrideWith((ref) => 'SWAP'),
      orderTabProvider.overrideWith((ref) => OrderTab.history),
      ordersFutureProvider.overrideWith((ref) async => [order]),
      currencyProvider.overrideWith((ref) => CurrencyDisplayMode.usd),
      vndExchangeRateProvider.overrideWith((ref) async => 25400),
      appTimeZoneProvider.overrideWith((ref) => 'Asia/Ho_Chi_Minh'),
      themeModeProvider.overrideWith((ref) => ThemeMode.light),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: const OrdersScreen(),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'history headers group compact instrument, type, side, and leverage across phone sizes and scales',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;

      const scenarios = [
        (
          width: 320.0,
          textScale: 1.0,
          side: 'buy',
          state: 'filled',
          instType: 'SWAP',
          lever: '10',
        ),
        (
          width: 375.0,
          textScale: 1.3,
          side: 'sell',
          state: 'canceled',
          instType: 'SWAP',
          lever: '5',
        ),
        (
          width: 430.0,
          textScale: 2.0,
          side: 'buy',
          state: 'filled',
          instType: '',
          lever: '3',
        ),
      ];

      for (final scenario in scenarios) {
        tester.view.physicalSize = Size(scenario.width, 900);
        await tester.pumpWidget(
          _historyApp(
            OkxOrder(
              instId: 'BTC-USDT-SWAP',
              instType: scenario.instType,
              ordId: 'history-order-1',
              ordType: 'limit',
              side: scenario.side,
              px: '65000',
              sz: '2',
              state: scenario.state,
              lever: scenario.lever,
              cTime: '1767225600000',
              fillNotionalUsd: '1000',
            ),
            scenario.textScale,
          ),
        );
        await tester.pump();
        await tester.pump();

        final header = find.byKey(const Key('history-order-header'));
        final left = find.byKey(const Key('history-order-header-left'));
        final right = find.byKey(const Key('history-order-header-right'));
        final pair = find.descendant(
          of: header,
          matching: find.text('BTCUSDT'),
        );
        final sideLabel = scenario.side == 'buy' ? 'MUA' : 'BÁN';
        final side = find.descendant(
          of: header,
          matching: find.text(sideLabel),
        );
        final leverage = find.descendant(
          of: header,
          matching: find.text('${scenario.lever}x'),
        );
        final type = find.byKey(const Key('history-order-instrument-type'));
        final state = scenario.state.toUpperCase();

        expect(header, findsOneWidget);
        expect(left, findsOneWidget);
        expect(right, findsOneWidget);
        expect(pair, findsOneWidget);
        expect(side, findsOneWidget);
        expect(leverage, findsOneWidget);
        expect(
          scenario.instType.isEmpty
              ? type
              : find.descendant(of: header, matching: type),
          scenario.instType.isEmpty ? findsNothing : findsOneWidget,
        );
        expect(find.text(state), findsOneWidget);
        expect(
          find.descendant(of: header, matching: find.text(state)),
          findsNothing,
        );

        final headerRect = tester.getRect(header);
        expect(tester.getRect(left).left, closeTo(headerRect.left, 1));
        expect(tester.getRect(right).right, closeTo(headerRect.right, 1));
        for (final finder in [
          find.byType(CryptoIcon),
          pair,
          side,
          leverage,
          if (scenario.instType.isNotEmpty) type,
        ]) {
          expect(headerRect.contains(tester.getRect(finder).center), isTrue);
        }
        expect(
          tester.getRect(find.byType(CryptoIcon)).center.dx,
          lessThan(tester.getRect(pair).center.dx),
        );
        if (scenario.instType.isNotEmpty) {
          expect(
            tester.getRect(pair).center.dx,
            lessThan(tester.getRect(type).center.dx),
          );
        }
        expect(
          tester.getRect(side).center.dx,
          lessThan(tester.getRect(leverage).center.dx),
        );
        expect(find.text('BTC-USDT-SWAP'), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}
