import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/fractal_tracker/presentation/providers/fractal_provider.dart';

void main() {
  group('fractal tracker OKX candle alignment', () {
    test('uses UTC-aligned OKX bars for month and year sub-candles', () {
      expect(fractalBarForTimeframe('M1'), '1Dutc');
      expect(fractalBarForTimeframe('Y1'), '1Mutc');
    });

    test('labels UTC-aligned sub-candles by their UTC calendar date', () {
      final julyFirstUtc = DateTime.utc(2026, 7, 1).millisecondsSinceEpoch;
      final januaryUtc = DateTime.utc(2026, 1, 1).millisecondsSinceEpoch;

      expect(fractalSubCandleLabel('M1', julyFirstUtc), '1');
      expect(fractalSubCandleLabel('Y1', januaryUtc), '1');
    });
  });
}
