import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/strategy/domain/strategy_calculator.dart';
import 'package:trading_balance_f/features/strategy/domain/strategy_models.dart';

void main() {
  const calculator = StrategyLevelCalculator();

  test('medians and directional tick rounding keep exact decimal text', () {
    final analysis = calculator.calculate(
      candles: _candles(
        lows: const ['94', '94', '90.11', '94', '94', '90.22', '94', '94'],
        highs: const ['99', '99', '100.11', '99', '99', '100.22', '99', '99'],
      ),
      referencePrice: 95,
      referencePriceText: '95.000',
      tickSizeText: '0.10',
    );

    expect(analysis.supports, hasLength(1));
    expect(analysis.resistances, hasLength(1));
    expect(analysis.supports.single.priceText, '90.1');
    expect(analysis.resistances.single.priceText, '100.2');
    expect(analysis.supports.single.id, startsWith('low_'));
    expect(analysis.resistances.single.id, startsWith('high_'));
  });

  test('rounded equal prices retain distinct source IDs', () {
    final candles = _candles(
      lows: const [
        '94',
        '94',
        '90.1',
        '94',
        '94',
        '90.5',
        '94',
        '94',
        '90.9',
        '94',
        '94',
      ],
      highs: const [
        '99',
        '99',
        '100.1',
        '99',
        '99',
        '100.5',
        '99',
        '99',
        '100.9',
        '99',
        '99',
      ],
    );
    final analysis = calculator.calculate(
      candles: candles,
      referencePrice: 95,
      referencePriceText: '95',
      tickSizeText: '1.0',
    );
    final repeated = calculator.calculate(
      candles: candles,
      referencePrice: 95,
      referencePriceText: '95',
      tickSizeText: '1.0',
    );

    expect(analysis.supports.map((level) => level.priceText), ['90', '90']);
    expect(analysis.resistances.map((level) => level.priceText), [
      '101',
      '101',
    ]);
    expect(analysis.supports.map((level) => level.id).toSet(), hasLength(2));
    expect(analysis.resistances.map((level) => level.id).toSet(), hasLength(2));
    expect(
      analysis.supports.map((level) => level.id),
      repeated.supports.map((level) => level.id),
    );
    expect(
      analysis.resistances.map((level) => level.id),
      repeated.resistances.map((level) => level.id),
    );
    expect(
      [
        ...analysis.supports,
        ...analysis.resistances,
      ].every((level) => RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(level.id)),
      isTrue,
    );
  });
}

List<StrategyCandle> _candles({
  required List<String> lows,
  required List<String> highs,
}) {
  if (lows.length != highs.length) {
    throw ArgumentError('Candle price fixture lengths must match.');
  }
  final base = DateTime.utc(2030, 1, 1);
  return List.generate(lows.length, (index) {
    final lowText = lows[index];
    final highText = highs[index];
    return StrategyCandle(
      timestamp: base.add(Duration(hours: index * 6)),
      open: 95,
      high: double.parse(highText),
      low: double.parse(lowText),
      close: 95,
      interval: StrategyInterval.h6,
      exactOpenText: '95.000',
      exactHighText: highText,
      exactLowText: lowText,
      exactCloseText: '95.000',
    );
  });
}
