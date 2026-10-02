import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/strategy/domain/strategy_models.dart';
import 'package:trading_balance_f/features/strategy/domain/strategy_selection.dart';

void main() {
  group('StrategySelection', () {
    test('rejects more than 20 selected rows', () {
      final levels = List.generate(
        21,
        (index) => StrategySelectedLevel(
          side: StrategySide.long,
          price: 99 - index.toDouble(),
          levelId: 'long_$index',
        ),
      );

      expect(
        () => StrategySelection.validate(
          instrumentId: 'BTC-USDT-SWAP',
          interval: StrategyInterval.h6,
          referencePrice: 100,
          direction: StrategyDirection.long,
          selectedLevels: levels,
          entryLevelIdBySide: const {StrategySide.long: 'long_0'},
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
          direction: StrategyDirection.long,
          selectedLevels: const [
            StrategySelectedLevel(
              side: StrategySide.long,
              price: 99,
              levelId: 'long_near',
            ),
            StrategySelectedLevel(
              side: StrategySide.long,
              price: 80,
              levelId: 'long_far',
            ),
          ],
          entryLevelIdBySide: const {StrategySide.long: 'long_far'},
        ),
        throwsA(isA<StrategySelectionException>()),
      );
    });

    test('Both requires at least one selected level on each side', () {
      expect(
        () => StrategySelection.validate(
          instrumentId: 'BTC-USDT-SWAP',
          interval: StrategyInterval.h6,
          referencePrice: 100,
          direction: StrategyDirection.both,
          selectedLevels: const [
            StrategySelectedLevel(
              side: StrategySide.long,
              price: 99,
              levelId: 'long_1',
            ),
          ],
          entryLevelIdBySide: const {StrategySide.long: 'long_1'},
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
            direction: StrategyDirection.long,
            selectedLevels: const [
              StrategySelectedLevel(
                side: StrategySide.long,
                price: 99,
                levelId: 'long_1',
              ),
            ],
            entryLevelIdBySide: const {StrategySide.long: 'long_1'},
          ),
          throwsA(isA<StrategySelectionException>()),
        );
      }
    });

    test('serializes the canonical exact price and v2 IDs', () {
      final selection = StrategySelection.validate(
        instrumentId: 'BTC-USDT-SWAP',
        interval: StrategyInterval.h6,
        referencePrice: 100,
        referencePriceText: '100.0000',
        direction: StrategyDirection.long,
        selectedLevels: const [
          StrategySelectedLevel(
            side: StrategySide.long,
            price: 99.25,
            exactPriceText: '99.2500',
            levelId: 'low_1728000000',
          ),
        ],
        entryLevelIdBySide: const {StrategySide.long: 'low_1728000000'},
      );

      final request = selection.toRequestJson(
        totalMargin: '100.0',
        leverage: const {StrategySide.long: 5},
        sidePercent: const {},
        allocation: StrategyAllocation.equal,
      );

      expect(request['direction'], 'long');
      expect(request['selectedLevels'], [
        {'side': 'long', 'price': '99.25', 'levelId': 'low_1728000000'},
      ]);
      expect(request['entryBySide'], {'long': '99.25'});
      expect(request['entryLevelIdBySide'], {'long': 'low_1728000000'});
    });

    test('retains equal-price selected rows and explicitly selects by ID', () {
      final selection = StrategySelection.validate(
        instrumentId: 'BTC-USDT-SWAP',
        interval: StrategyInterval.h6,
        referencePrice: 100,
        direction: StrategyDirection.both,
        selectedLevels: const [
          StrategySelectedLevel(
            side: StrategySide.long,
            price: 90,
            exactPriceText: '90',
            levelId: 'low_1',
          ),
          StrategySelectedLevel(
            side: StrategySide.long,
            price: 90,
            exactPriceText: '90.0',
            levelId: 'low_2',
          ),
          StrategySelectedLevel(
            side: StrategySide.short,
            price: 110,
            exactPriceText: '110.00',
            levelId: 'high_1',
          ),
        ],
        entryLevelIdBySide: const {
          StrategySide.long: 'low_2',
          StrategySide.short: 'high_1',
        },
      );

      final request = selection.toRequestJson(
        totalMargin: '100',
        leverage: const {StrategySide.long: 5, StrategySide.short: 5},
        sidePercent: const {StrategySide.long: '50', StrategySide.short: '50'},
        allocation: StrategyAllocation.equal,
      );

      expect(request['direction'], 'both');
      expect(request['selectedLevels'], [
        {'side': 'long', 'price': '90', 'levelId': 'low_1'},
        {'side': 'long', 'price': '90', 'levelId': 'low_2'},
        {'side': 'short', 'price': '110', 'levelId': 'high_1'},
      ]);
      expect(request['entryLevelIdBySide'], {
        'long': 'low_2',
        'short': 'high_1',
      });
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
