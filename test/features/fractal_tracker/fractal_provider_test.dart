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

    test('labels the same instant in the selected time zone', () {
      final lateUtc = DateTime.utc(2026, 7, 1, 23, 30).millisecondsSinceEpoch;

      expect(fractalSubCandleLabel('M1', lateUtc), '1');
      expect(
        fractalSubCandleLabel('M1', lateUtc, timeZoneId: 'Asia/Ho_Chi_Minh'),
        '2',
      );
    });

    test('builds current day and week ranges in the selected time zone', () {
      final instant = DateTime.utc(2026, 7, 1, 16, 30);

      final day = fractalPeriodBounds(
        timeframe: 'D1',
        timeZoneId: 'Asia/Ho_Chi_Minh',
        instant: instant,
      );
      final week = fractalPeriodBounds(
        timeframe: 'W1',
        timeZoneId: 'Asia/Ho_Chi_Minh',
        instant: instant,
      );

      expect(day.isCurrentPeriod, isTrue);
      expect(day.startMs, DateTime.utc(2026, 6, 30, 17).millisecondsSinceEpoch);
      expect(day.endMs, DateTime.utc(2026, 7, 1, 17).millisecondsSinceEpoch);
      expect(week.isCurrentPeriod, isTrue);
      expect(
        week.startMs,
        DateTime.utc(2026, 6, 28, 17).millisecondsSinceEpoch,
      );
      expect(week.endMs, DateTime.utc(2026, 7, 5, 17).millisecondsSinceEpoch);
    });

    test('builds selected month and year ranges in the chosen time zone', () {
      final month = fractalPeriodBounds(
        timeframe: 'M1',
        timeZoneId: 'Asia/Ho_Chi_Minh',
        targetDate: DateTime(2026, 7),
        instant: DateTime.utc(2026, 8, 1),
      );
      final year = fractalPeriodBounds(
        timeframe: 'Y1',
        timeZoneId: 'Asia/Ho_Chi_Minh',
        targetDate: DateTime(2026),
        instant: DateTime.utc(2027, 1, 1),
      );

      expect(month.isCurrentPeriod, isFalse);
      expect(
        month.startMs,
        DateTime.utc(2026, 6, 30, 17).millisecondsSinceEpoch,
      );
      expect(month.endMs, DateTime.utc(2026, 7, 31, 17).millisecondsSinceEpoch);
      expect(year.isCurrentPeriod, isFalse);
      expect(
        year.startMs,
        DateTime.utc(2025, 12, 31, 17).millisecondsSinceEpoch,
      );
      expect(year.endMs, DateTime.utc(2026, 12, 31, 17).millisecondsSinceEpoch);
    });

    test(
      'assigns a year monthly candle to the quarter it mostly belongs to',
      () {
        final startMs = DateTime.utc(2026).millisecondsSinceEpoch;
        final endMs = DateTime.utc(2027).millisecondsSinceEpoch;
        final julyMonthlyCandleMs = DateTime.utc(
          2026,
          7,
        ).millisecondsSinceEpoch;

        expect(
          fractalQuarterIndex(
            timeframe: 'Y1',
            candleTimestampMs: julyMonthlyCandleMs,
            startMs: startMs,
            endMs: endMs,
          ),
          2,
        );
      },
    );
  });
}
