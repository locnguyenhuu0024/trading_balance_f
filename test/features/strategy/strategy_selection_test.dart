import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/strategy/domain/strategy_calculator.dart';
import 'package:trading_balance_f/features/strategy/domain/strategy_models.dart';
import 'package:trading_balance_f/features/strategy/domain/strategy_selection.dart';

void main() {
  group('StrategyLevelCalculator', () {
    test('uses the newest 500 H12 candles for strict swing levels', () {
      final candles = List.generate(501, (index) {
        final timestamp = DateTime.utc(2024).add(Duration(hours: index * 12));
        final isSupportSwing = index == 3;
        return StrategyCandle(
          timestamp: timestamp,
          open: 100,
          high: 110,
          low: isSupportSwing ? 80 : 90,
          close: 100,
          interval: StrategyInterval.h12,
        );
      });

      final analysis = const StrategyLevelCalculator().calculate(
        candles: candles,
        referencePrice: 100,
      );

      expect(analysis.supports.map((level) => level.price), contains(80));
      expect(analysis.referencePrice, 100);
    });
  });

  group('StrategySelection', () {
    test('rejects more than 20 selected levels', () {
      final levels = List.generate(
        21,
        (index) => StrategySelectedLevel(
          side: StrategySide.long,
          price: 99 - index.toDouble(),
        ),
      );

      expect(
        () => StrategySelection.validate(
          instrumentId: 'BTC-USDT-SWAP',
          interval: StrategyInterval.h6,
          referencePrice: 100,
          selectedLevels: levels,
          entryBySide: {StrategySide.long: 99},
        ),
        throwsA(isA<StrategySelectionException>()),
      );
    });

    test('rejects an entry farther from price than another selected level', () {
      expect(
        () => StrategySelection.validate(
          instrumentId: 'BTC-USDT-SWAP',
          interval: StrategyInterval.h6,
          referencePrice: 100,
          selectedLevels: const [
            StrategySelectedLevel(side: StrategySide.long, price: 99),
            StrategySelectedLevel(side: StrategySide.long, price: 80),
          ],
          entryBySide: {StrategySide.long: 80},
        ),
        throwsA(isA<StrategySelectionException>()),
      );
    });

    test('rejects Spot and inverse-looking instruments', () {
      for (final instrument in ['BTC-USDT', 'BTC-USD-SWAP']) {
        expect(
          () => StrategySelection.validate(
            instrumentId: instrument,
            interval: StrategyInterval.h6,
            referencePrice: 100,
            selectedLevels: const [
              StrategySelectedLevel(side: StrategySide.long, price: 99),
            ],
            entryBySide: {StrategySide.long: 99},
          ),
          throwsA(isA<StrategySelectionException>()),
        );
      }
    });
  });

  test('a delayed quote is stale and cannot be labeled current', () {
    final receivedAt = DateTime.utc(2026, 10, 1, 8);
    final quote = StrategyTicker(
      instrumentId: 'BTC-USDT-SWAP',
      lastPrice: 65000,
      observedAt: receivedAt,
    );

    expect(quote.isFreshAt(receivedAt.add(const Duration(seconds: 2))), isTrue);
    expect(
      quote.isFreshAt(receivedAt.add(const Duration(seconds: 5))),
      isFalse,
    );
  });
}
