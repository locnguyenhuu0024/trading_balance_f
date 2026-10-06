import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/strategy/domain/strategy_settings.dart';

void main() {
  test('typed settings parse and serialize the full default wire object', () {
    const expected = StrategySettings(
      limitOrderSubmissionMode: 'sequential',
      jevScreeningThresholds: StrategyJevScreeningThresholds.defaults,
    );
    final decoded = StrategySettings.tryParse(expected.toJson());

    expect(decoded, expected);
    expect(expected.toJson(), {
      'limitOrderSubmissionMode': 'sequential',
      'jevScreeningThresholds': {
        'minStructuralQuality': 4,
        'minEntrySuitabilityProbability': 0.6,
        'maxFailureRiskProbability': 0.4,
      },
    });
  });

  test('API thresholds require exact keys and bounded numeric values', () {
    expect(
      StrategyJevScreeningThresholds.tryParseApi({
        'minStructuralQuality': 0,
        'minEntrySuitabilityProbability': 0.0,
        'maxFailureRiskProbability': 1.0,
      }),
      const StrategyJevScreeningThresholds(
        minStructuralQuality: 0,
        minEntrySuitabilityProbability: 0,
        maxFailureRiskProbability: 1,
      ),
    );
    for (final invalid in [
      {
        'minStructuralQuality': 4.0,
        'minEntrySuitabilityProbability': 0.6,
        'maxFailureRiskProbability': 0.4,
      },
      {
        'minStructuralQuality': 6,
        'minEntrySuitabilityProbability': 0.6,
        'maxFailureRiskProbability': 0.4,
      },
      {
        'minStructuralQuality': 3,
        'minEntrySuitabilityProbability': double.nan,
        'maxFailureRiskProbability': 0.4,
      },
      {
        'minStructuralQuality': 3,
        'minEntrySuitabilityProbability': 0.6,
        'maxFailureRiskProbability': 1.01,
      },
      {
        'minStructuralQuality': 3,
        'minEntrySuitabilityProbability': 0.6,
        'maxFailureRiskProbability': 0.4,
        'extra': 1,
      },
    ]) {
      expect(StrategyJevScreeningThresholds.tryParseApi(invalid), isNull);
    }
  });

  test(
    'snapshot thresholds accept custom values and integral legacy doubles',
    () {
      expect(
        StrategyJevScreeningThresholds.tryParseSnapshot({
          'minStructuralQuality': 3.0,
          'minEntrySuitabilityProbability': 0.55,
          'maxFailureRiskProbability': 0.45,
        }),
        const StrategyJevScreeningThresholds(
          minStructuralQuality: 3,
          minEntrySuitabilityProbability: 0.55,
          maxFailureRiskProbability: 0.45,
        ),
      );
      expect(
        StrategyJevScreeningThresholds.tryParseSnapshot({
          'minStructuralQuality': 3.5,
          'minEntrySuitabilityProbability': 0.55,
          'maxFailureRiskProbability': 0.45,
        }),
        isNull,
      );
    },
  );

  test('percentage input accepts comma decimals and inclusive bounds', () {
    expect(StrategyJevScreeningThresholds.parsePercentage('55,5'), 55.5);
    expect(StrategyJevScreeningThresholds.parsePercentage('0'), 0);
    expect(StrategyJevScreeningThresholds.parsePercentage('100'), 100);
    for (final invalid in [
      '',
      '  ',
      '-1',
      '100.01',
      'NaN',
      'Infinity',
      '1,2.3',
    ]) {
      expect(StrategyJevScreeningThresholds.parsePercentage(invalid), isNull);
    }
  });
}
