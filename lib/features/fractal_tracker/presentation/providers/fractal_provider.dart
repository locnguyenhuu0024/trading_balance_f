// File Name: fractal_provider.dart
// File Path: lib/features/fractal_tracker/presentation/providers/fractal_provider.dart

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/timezone/app_time_zone.dart';
import '../../data/fractal_model.dart';

final selectedMonthProvider = StateProvider<DateTime>((ref) {
  final timeZoneId = ref.watch(appTimeZoneProvider);
  final now = AppTimeZone.now(timeZoneId);
  return DateTime(now.year, now.month);
});

final selectedYearProvider = StateProvider<int>((ref) {
  final timeZoneId = ref.watch(appTimeZoneProvider);
  return AppTimeZone.now(timeZoneId).year;
});

// THÊM MỚI: Provider quản lý Coin đang chọn, mặc định là BTC
final selectedCoinProvider = StateProvider<String>((ref) => 'BTC');

String fractalBarForTimeframe(String timeframe) {
  return switch (timeframe) {
    'D1' => '1H',
    'W1' => '4H',
    'M1' => '1Dutc',
    'Y1' => '1Mutc',
    _ => throw ArgumentError.value(timeframe, 'timeframe'),
  };
}

String fractalSubCandleLabel(
  String timeframe,
  int timestampMs, {
  String timeZoneId = AppTimeZone.defaultId,
}) {
  final dt = AppTimeZone.fromEpochMilliseconds(timeZoneId, timestampMs);
  return switch (timeframe) {
    'M1' => dt.day.toString(),
    'Y1' => dt.month.toString(),
    _ => throw ArgumentError.value(timeframe, 'timeframe'),
  };
}

int fractalQuarterIndex({
  required String timeframe,
  required int candleTimestampMs,
  required int startMs,
  required int endMs,
}) {
  final representativeMs = timeframe == 'Y1'
      ? _yearMonthlyCandleMidpointMs(candleTimestampMs)
      : candleTimestampMs;
  final quarterDuration = (endMs - startMs) / 4;
  final index = ((representativeMs - startMs) / quarterDuration).floor();

  return index.clamp(0, 3);
}

@immutable
class FractalPeriodBounds {
  const FractalPeriodBounds({
    required this.startMs,
    required this.endMs,
    required this.isCurrentPeriod,
  });

  final int startMs;
  final int endMs;
  final bool isCurrentPeriod;
}

FractalPeriodBounds fractalPeriodBounds({
  required String timeframe,
  required String timeZoneId,
  DateTime? targetDate,
  DateTime? instant,
}) {
  final localNow = AppTimeZone.now(timeZoneId, instant: instant);
  late AppTimeZoneRange range;
  var isCurrentPeriod = false;

  switch (timeframe) {
    case 'D1':
      range = AppTimeZone.dayRange(timeZoneId, date: localNow);
      isCurrentPeriod = true;
      break;
    case 'W1':
      range = AppTimeZone.currentWeekRange(timeZoneId, instant: instant);
      isCurrentPeriod = true;
      break;
    case 'M1':
      final date = targetDate ?? localNow;
      range = AppTimeZone.monthRange(
        timeZoneId,
        year: date.year,
        month: date.month,
      );
      isCurrentPeriod =
          date.year == localNow.year && date.month == localNow.month;
      break;
    case 'Y1':
      final date = targetDate ?? localNow;
      range = AppTimeZone.yearRange(timeZoneId, year: date.year);
      isCurrentPeriod = date.year == localNow.year;
      break;
    default:
      throw ArgumentError.value(timeframe, 'timeframe');
  }

  return FractalPeriodBounds(
    startMs: range.startMillisecondsSinceEpoch,
    endMs: range.endMillisecondsSinceEpoch,
    isCurrentPeriod: isCurrentPeriod,
  );
}

int _yearMonthlyCandleMidpointMs(int candleTimestampMs) {
  final candleStart = DateTime.fromMillisecondsSinceEpoch(
    candleTimestampMs,
    isUtc: true,
  );
  final nextMonth = DateTime.utc(candleStart.year, candleStart.month + 1);
  return candleStart.millisecondsSinceEpoch +
      (nextMonth.millisecondsSinceEpoch - candleStart.millisecondsSinceEpoch) ~/
          2;
}

final fractalDataProvider = FutureProvider.autoDispose<List<FractalData>>((
  ref,
) async {
  final dio = Dio(BaseOptions(baseUrl: 'https://www.okx.com'));

  final targetMonth = ref.watch(selectedMonthProvider);
  final targetYear = ref.watch(selectedYearProvider);
  final targetCoin = ref.watch(selectedCoinProvider); // THÊM MỚI
  final timeZoneId = ref.watch(appTimeZoneProvider);

  final results = await Future.wait([
    _fetchAndProcess(
      dio,
      'D1',
      fractalBarForTimeframe('D1'),
      24,
      null,
      targetCoin,
      timeZoneId,
    ),
    _fetchAndProcess(
      dio,
      'W1',
      fractalBarForTimeframe('W1'),
      42,
      null,
      targetCoin,
      timeZoneId,
    ),
    _fetchAndProcess(
      dio,
      'M1',
      fractalBarForTimeframe('M1'),
      31,
      targetMonth,
      targetCoin,
      timeZoneId,
    ),
    _fetchAndProcess(
      dio,
      'Y1',
      fractalBarForTimeframe('Y1'),
      12,
      DateTime(targetYear),
      targetCoin,
      timeZoneId,
    ),
  ]);

  return results.whereType<FractalData>().toList();
});

Future<FractalData?> _fetchAndProcess(
  Dio dio,
  String timeframe,
  String barId,
  int limit,
  DateTime? targetDate,
  String coin,
  String timeZoneId,
) async {
  try {
    final period = fractalPeriodBounds(
      timeframe: timeframe,
      timeZoneId: timeZoneId,
      targetDate: targetDate,
    );
    final startMs = period.startMs;
    final endMs = period.endMs;
    final isCurrentPeriod = period.isCurrentPeriod;
    if (timeframe == 'M1') {
      final month = targetDate ?? AppTimeZone.now(timeZoneId);
      final monthStart = DateTime.utc(month.year, month.month);
      final monthEnd = DateTime.utc(month.year, month.month + 1);
      limit = monthEnd.difference(monthStart).inDays;
    } else if (timeframe == 'Y1') {
      limit = 12;
    }
    final quarterDuration = (endMs - startMs) / 4;

    List rawCandles = [];
    final afterTs = endMs.toString();

    // Hàm gọi API
    Future<void> fetchApi(String endpoint) async {
      try {
        final response = await dio.get(
          endpoint,
          queryParameters: {
            'instId': '$coin-USDT',
            'bar': barId,
            'limit': limit,
            'after': afterTs,
          },
        );
        if (response.data['code'] == '0') rawCandles = response.data['data'];
      } catch (_) {}
    }

    // THAY ĐỔI QUAN TRỌNG:
    // Nếu là khoảng thời gian hiện tại -> Gọi API lấy nến đang chạy (chứa nến của hôm nay/tháng này)
    // Nếu là quá khứ -> Gọi API History để lấy chính xác dữ liệu cũ
    if (isCurrentPeriod) {
      await fetchApi('/api/v5/market/candles');
      if (rawCandles.isEmpty) await fetchApi('/api/v5/market/history-candles');
    } else {
      await fetchApi('/api/v5/market/history-candles');
      if (rawCandles.isEmpty) await fetchApi('/api/v5/market/candles');
    }

    if (rawCandles.isEmpty) return null;

    final prefix = timeframe == 'Y1' ? 'Q' : '';
    List<QuarterData> quarters = [
      QuarterData('${prefix}1'),
      QuarterData('${prefix}2'),
      QuarterData('${prefix}3'),
      QuarterData('${prefix}4'),
    ];

    for (int i = 0; i < 4; i++) {
      quarters[i].startTime = AppTimeZone.fromEpochMilliseconds(
        timeZoneId,
        (startMs + i * quarterDuration).toInt(),
      );
    }

    double currentPrice = double.parse(rawCandles.first[4]);

    for (var c in rawCandles) {
      int ts = int.parse(c[0]);
      if (ts < startMs || ts >= endMs) continue;

      int qIndex = fractalQuarterIndex(
        timeframe: timeframe,
        candleTimestampMs: ts,
        startMs: startMs,
        endMs: endMs,
      );

      QuarterData q = quarters[qIndex];
      double open = double.parse(c[1]);
      double high = double.parse(c[2]);
      double low = double.parse(c[3]);
      double close = double.parse(c[4]);

      if (q.high == null || high > q.high!) q.high = high;
      if (q.low == null || low < q.low!) q.low = low;

      if (q.oldestTs == null || ts < q.oldestTs!) {
        q.oldestTs = ts;
        q.open = open;
      }

      if (q.newestTs == null || ts > q.newestTs!) {
        q.newestTs = ts;
        q.close = close;
      }
    }

    double maxHigh = -double.maxFinite;
    double minLow = double.maxFinite;
    int maxHighQ = -1;
    int minLowQ = -1;

    for (int i = 0; i < 4; i++) {
      if (!quarters[i].isEmpty) {
        if (quarters[i].high! > maxHigh) {
          maxHigh = quarters[i].high!;
          maxHighQ = i;
        }
        if (quarters[i].low! < minLow) {
          minLow = quarters[i].low!;
          minLowQ = i;
        }
      }
    }

    if (maxHighQ != -1) quarters[maxHighQ].hasAbsoluteHigh = true;
    if (minLowQ != -1) quarters[minLowQ].hasAbsoluteLow = true;

    // Parse dữ liệu các Nến nhỏ (SubCandles)
    List<SubCandle> subCandles = [];
    if (timeframe == 'M1' || timeframe == 'Y1') {
      final chronoCandles = rawCandles.reversed.toList();
      for (var c in chronoCandles) {
        int ts = int.parse(c[0]);
        if (ts < startMs || ts >= endMs) continue;

        final label = fractalSubCandleLabel(
          timeframe,
          ts,
          timeZoneId: timeZoneId,
        );

        subCandles.add(
          SubCandle(
            label,
            double.parse(c[1]),
            double.parse(c[2]),
            double.parse(c[3]),
            double.parse(c[4]),
          ),
        );
      }
    }

    return FractalData(
      timeframeLabel: timeframe,
      quarters: quarters,
      currentPrice: currentPrice,
      subCandles: subCandles,
    );
  } catch (e) {
    return null;
  }
}
