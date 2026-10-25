import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/exchange/exchange_models.dart';

void main() {
  group('RED-117', () {
    test(
      'rejects invalid decimal and currency values without zero defaults',
      () {
        expect(ExchangeAmount.tryParse('not-a-number'), isNull);
        expect(ExchangeAmount.tryParse('1e-8'), isNull);
        expect(ExchangeAmount.tryParse(double.infinity), isNull);
        expect(ExchangeMoney.tryParse('1.25', ''), isNull);
        expect(ExchangeMoney.tryParse('1.25', 'USDT/ USD'), isNull);
        expect(
          const ExchangeValue<ExchangeAmount>.unavailable('missing').value,
          isNull,
        );
      },
    );

    test('keeps same numeric IDs separate by exchange, product and kind', () {
      final rows = <ExchangeOrder>[
        _order(source: ExchangeSource.okx, product: ExchangeProduct.swap),
        _order(source: ExchangeSource.binance, product: ExchangeProduct.swap),
        _order(
          source: ExchangeSource.binance,
          product: ExchangeProduct.futures,
        ),
        _order(
          source: ExchangeSource.binance,
          product: ExchangeProduct.swap,
          kind: ExchangeOrderKind.conditional,
        ),
      ];

      expect(rows.map((row) => row.identityKey).toSet(), hasLength(4));
    });

    test('does not accept a missing or nonpositive valuation quote', () {
      final spot = _instrument('BTCUSDT');
      final key = ExchangeQuoteKey(
        source: ExchangeSource.binance,
        product: ExchangeProduct.spot,
        instrument: spot.symbol,
      );
      final zero = ExchangeQuote(
        key: key,
        price: ExchangeAmount.tryParse('0')!,
        quoteCurrency: 'USDT',
        observedAt: DateTime.utc(2026, 10, 25),
      );
      final infinite = ExchangeQuote(
        key: key,
        price: ExchangeAmount.tryParse(List<String>.filled(400, '9').join())!,
        quoteCurrency: 'USDT',
        observedAt: DateTime.utc(2026, 10, 25),
      );

      expect(zero.isPositiveFinite, isFalse);
      expect(infinite.isPositiveFinite, isFalse);
      expect(
        const ExchangeValue<ExchangeQuote>.unavailable('no source quote').value,
        isNull,
      );
    });
  });

  group('GREEN-117', () {
    test(
      'preserves decimal scale while exact multiplication and addition work',
      () {
        final amount = ExchangeAmount.tryParse('2.00')!;
        final price = ExchangeAmount.tryParse('10.0')!;
        final value = ExchangeAmount.multiply(amount, price);

        expect(amount.text, '2.00');
        expect(value.text, '20');
        expect(
          ExchangeAmount.add(value, ExchangeAmount.tryParse('30.000')!).text,
          '50',
        );
      },
    );

    test(
      'hedge sides remain distinct and net direction follows signed amount',
      () {
        final long = _position(side: ExchangePositionSide.long, amount: '1');
        final short = _position(side: ExchangePositionSide.short, amount: '-1');
        final netShort = _position(
          side: ExchangePositionSide.net,
          amount: '-2',
        );

        expect(long.identityKey, isNot(short.identityKey));
        expect(long.effectiveDirection, ExchangePositionSide.long);
        expect(short.effectiveDirection, ExchangePositionSide.short);
        expect(netShort.effectiveDirection, ExchangePositionSide.short);
      },
    );

    test('account fixture totals 195 without adding futures PnL twice', () {
      final spotUnits = ExchangeAmount.tryParse('2')!;
      final spotPrice = ExchangeAmount.tryParse('10')!;
      final spotValue =
          ExchangeMoney(
            amount: ExchangeAmount.multiply(spotUnits, spotPrice),
            currency: 'USDT',
          ).add(
            ExchangeMoney(
              amount: ExchangeAmount.tryParse('30')!,
              currency: 'USDT',
            ),
          );
      final okxEquity = ExchangeMoney(
        amount: ExchangeAmount.tryParse('100')!,
        currency: 'USD',
      ).convertTo(targetCurrency: 'USDT', rate: ExchangeAmount.tryParse('1')!);
      final futuresEquity = ExchangeMoney(
        amount: ExchangeAmount.tryParse('45')!,
        currency: 'USDT',
      );
      final futuresPnl = ExchangeMoney(
        amount: ExchangeAmount.tryParse('5')!,
        currency: 'USDT',
      );
      final total = okxEquity.add(spotValue).add(futuresEquity);

      expect(spotValue.toString(), '50 USDT');
      expect(futuresEquity.toString(), '45 USDT');
      expect(futuresPnl.toString(), '5 USDT');
      expect(total.toString(), '195 USDT');
    });
  });
}

ExchangeOrder _order({
  required ExchangeSource source,
  required ExchangeProduct product,
  ExchangeOrderKind kind = ExchangeOrderKind.ordinary,
}) => ExchangeOrder(
  source: source,
  product: product,
  kind: kind,
  symbol: 'BTCUSDT',
  nativeId: '7',
  side: 'buy',
  status: 'FILLED',
  quantity: ExchangeValue.available(ExchangeAmount.tryParse('1')!),
  executedQuantity: ExchangeValue.available(ExchangeAmount.tryParse('1')!),
  quoteAmount: ExchangeValue.available(
    ExchangeMoney(amount: ExchangeAmount.tryParse('100')!, currency: 'USDT'),
  ),
  createdAtMilliseconds: 1,
);

ExchangePosition _position({
  required ExchangePositionSide side,
  required String amount,
}) => ExchangePosition(
  source: ExchangeSource.binance,
  product: ExchangeProduct.swap,
  symbol: 'BTCUSDT',
  side: side,
  positionAmount: ExchangeValue.available(ExchangeAmount.tryParse(amount)!),
  entryPrice: const ExchangeValue.unavailable('unused'),
  markPrice: const ExchangeValue.unavailable('unused'),
  unrealizedPnl: const ExchangeValue.unavailable('unused'),
  marginMode: const ExchangeValue.unavailable('unused'),
  leverage: const ExchangeValue.unavailable('unused'),
  marginCurrency: const ExchangeValue.unavailable('unused'),
);

ExchangeInstrument _instrument(String symbol) => ExchangeInstrument(
  source: ExchangeSource.binance,
  product: ExchangeProduct.spot,
  symbol: symbol,
  baseAsset: const ExchangeValue.available('BTC'),
  quoteAsset: const ExchangeValue.available('USDT'),
  settlementAsset: const ExchangeValue.available('USDT'),
);
