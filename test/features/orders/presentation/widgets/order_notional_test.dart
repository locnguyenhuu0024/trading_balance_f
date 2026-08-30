import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/orders/data/okx_order_model.dart';
import 'package:trading_balance_f/features/orders/data/okx_position_model.dart';
import 'package:trading_balance_f/features/orders/presentation/widgets/order_notional.dart';

void main() {
  test('parses notional values from OKX position and order payloads', () {
    final position = OkxPosition.fromJson(<String, dynamic>{
      'instId': 'BTC-USDT-SWAP',
      'notionalUsd': '1250.5',
    });
    final order = OkxOrder.fromJson(<String, dynamic>{
      'instId': 'BTC-USDT',
      'notionalUsd': '500',
      'fillNotionalUsd': '250',
      'avgPx': '100000',
      'accFillSz': '0.0025',
      'tradeQuoteCcy': 'USDT',
    });

    expect(position.notionalUsd, '1250.5');
    expect(order.notionalUsd, '500');
    expect(order.fillNotionalUsd, '250');
    expect(order.avgPx, '100000');
    expect(order.accFillSz, '0.0025');
    expect(order.tradeQuoteCcy, 'USDT');
  });

  test('uses the absolute USD notional supplied for an open position', () {
    final notional = resolvePositionNotional(
      const OkxPosition(notionalUsd: '-1250.5'),
    );

    expect(notional?.usdAmount, 1250.5);
    expect(notional?.source, TradeNotionalSource.position);
  });

  test('prefers the filled notional over an order estimate', () {
    final notional = resolveOrderNotional(
      const OkxOrder(
        instType: 'SWAP',
        fillNotionalUsd: '400',
        notionalUsd: '500',
      ),
    );

    expect(notional?.usdAmount, 400);
    expect(notional?.source, TradeNotionalSource.filledOrder);
  });

  test('uses an API order estimate when no fill notional is available', () {
    final notional = resolveOrderNotional(
      const OkxOrder(instType: 'FUTURES', notionalUsd: '275.25'),
    );

    expect(notional?.usdAmount, 275.25);
    expect(notional?.source, TradeNotionalSource.orderEstimate);
  });

  test('derives a notional only for spot and margin base quantities', () {
    final notional = resolveOrderNotional(
      const OkxOrder(instType: 'SPOT', px: '100', sz: '0.25'),
    );

    expect(notional?.usdAmount, 25);
    expect(notional?.source, TradeNotionalSource.spotMarginFallback);
  });

  test(
    'does not guess a derivatives notional from contract quantity and price',
    () {
      final notional = resolveOrderNotional(
        const OkxOrder(instType: 'SWAP', px: '100', sz: '0.25'),
      );

      expect(notional, isNull);
    },
  );

  test(
    'returns unavailable for empty, zero, and malformed monetary fields',
    () {
      expect(
        resolvePositionNotional(const OkxPosition(notionalUsd: 'invalid')),
        isNull,
      );
      expect(
        resolveOrderNotional(
          const OkxOrder(instType: 'SPOT', px: '0', sz: '1'),
        ),
        isNull,
      );
    },
  );
}
