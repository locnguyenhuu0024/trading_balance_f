import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/support_resistance/domain/level_calculator.dart';
import 'package:trading_balance_f/features/support_resistance/domain/models.dart';

void main() {
  const calculator = SupportResistanceCalculator();

  test(
    'RED-28 excludes open and tied swings, then recategorizes a crossed level',
    () {
      final candles = _candles(
        count: 16,
        timeframe: SupportResistanceTimeframe.h1,
        now: DateTime.utc(2026, 9, 29, 16),
        highAt: const <int, double>{5: 103, 9: 110, 10: 110, 12: 1000},
        confirmedAt: const <int, bool>{12: false},
      );

      final belowTheLevel = calculator.calculate(
        candles: candles,
        referencePrice: 104,
      );
      expect(belowTheLevel.supports.map((level) => level.price), <double>[103]);
      expect(belowTheLevel.resistances, isEmpty);

      final crossedLevel = calculator.calculate(
        candles: candles,
        referencePrice: 102.5,
      );
      expect(crossedLevel.supports, isEmpty);
      expect(crossedLevel.resistances.map((level) => level.price), <double>[
        103,
      ]);
    },
  );

  test('GREEN-28 returns median clusters nearest-first, capped at five', () {
    final candles = _levelsFixture(
      timeframe: SupportResistanceTimeframe.h1,
      now: DateTime.utc(2026, 9, 29, 12),
    );
    final analysis = calculator.calculate(
      candles: candles,
      referencePrice: 100.3,
    );

    expect(analysis.supports.map((level) => level.price), <double>[
      98,
      97,
      96,
      95.2,
      94,
    ]);
    expect(analysis.resistances.map((level) => level.price), <double>[
      102,
      103.1,
      105,
      106,
      108,
    ]);
    final clusteredSupport = analysis.supports[3];
    expect(clusteredSupport.touchCount, 2);
    expect(clusteredSupport.firstTouchAt, candles[20].timestamp);
    expect(clusteredSupport.lastTouchAt, candles[40].timestamp);
    expect(clusteredSupport.side, SupportResistanceLevelSide.support);
    final clusteredResistance = analysis.resistances[1];
    expect(clusteredResistance.touchCount, 2);
    expect(clusteredResistance.firstTouchAt, candles[10].timestamp);
    expect(clusteredResistance.lastTouchAt, candles[30].timestamp);
    expect(clusteredResistance.side, SupportResistanceLevelSide.resistance);
    expect(analysis.supports, hasLength(5));
    expect(analysis.resistances, hasLength(5));
  });

  test('clusters do not grow through a transitive chain wider than 0.5%', () {
    final candles = _candles(
      count: 18,
      timeframe: SupportResistanceTimeframe.h1,
      now: DateTime.utc(2026, 9, 29, 18),
      highAt: const <int, double>{4: 102, 8: 102.4, 12: 102.8},
    );
    final analysis = calculator.calculate(
      candles: candles,
      referencePrice: 103,
    );

    expect(analysis.supports.map((level) => level.price), <double>[
      102.8,
      102.2,
    ]);
  });
}

List<SupportResistanceCandle> _levelsFixture({
  required SupportResistanceTimeframe timeframe,
  required DateTime now,
}) {
  return _candles(
    count: 300,
    timeframe: timeframe,
    now: now,
    highAt: const <int, double>{
      10: 103,
      30: 103.2,
      50: 105,
      70: 102,
      90: 110,
      110: 106,
      130: 108,
    },
    lowAt: const <int, double>{
      20: 95,
      40: 95.4,
      60: 97,
      80: 92,
      100: 98,
      120: 96,
      140: 94,
    },
  );
}

List<SupportResistanceCandle> _candles({
  required int count,
  required SupportResistanceTimeframe timeframe,
  required DateTime now,
  Map<int, double> highAt = const <int, double>{},
  Map<int, double> lowAt = const <int, double>{},
  Map<int, bool> confirmedAt = const <int, bool>{},
}) {
  final start = now.subtract(timeframe.duration * count);
  return List<SupportResistanceCandle>.generate(count, (index) {
    return SupportResistanceCandle(
      timestamp: start.add(timeframe.duration * index),
      open: 100,
      high: highAt[index] ?? 101,
      low: lowAt[index] ?? 99,
      close: 100,
      timeframe: timeframe,
      confirmed: confirmedAt[index] ?? true,
    );
  }, growable: false);
}
