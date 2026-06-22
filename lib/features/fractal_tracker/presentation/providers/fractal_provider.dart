// File Name: fractal_provider.dart
// File Path: lib/features/fractal_tracker/presentation/providers/fractal_provider.dart

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/fractal_model.dart';

final selectedMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month);
});

final selectedYearProvider = StateProvider<int>((ref) {
  return DateTime.now().year;
});

final fractalDataProvider = FutureProvider.autoDispose<List<FractalData>>((ref) async {
  final dio = Dio(BaseOptions(baseUrl: 'https://www.okx.com'));
  
  final targetMonth = ref.watch(selectedMonthProvider);
  final targetYear = ref.watch(selectedYearProvider);

  final results = await Future.wait([
    _fetchAndProcess(dio, 'D1', '1H', 24, null),    
    _fetchAndProcess(dio, 'W1', '4H', 42, null),    
    _fetchAndProcess(dio, 'M1', '1D', 31, targetMonth),    
    _fetchAndProcess(dio, 'Y1', '1M', 12, DateTime(targetYear)), 
  ]);

  return results.whereType<FractalData>().toList();
});

Future<FractalData?> _fetchAndProcess(Dio dio, String timeframe, String barId, int limit, DateTime? targetDate) async {
  try {
    final now = DateTime.now().toUtc();
    DateTime startTime;
    DateTime endTime;
    
    // Kiểm tra xem khung thời gian đang xem có phải là thời điểm hiện tại không
    bool isCurrentPeriod = false;

    switch (timeframe) {
      case 'D1':
        startTime = DateTime.utc(now.year, now.month, now.day);
        endTime = startTime.add(const Duration(days: 1));
        isCurrentPeriod = true;
        break;
      case 'W1':
        final mondayOffset = now.weekday - 1;
        startTime = DateTime.utc(now.year, now.month, now.day).subtract(Duration(days: mondayOffset));
        endTime = startTime.add(const Duration(days: 7));
        isCurrentPeriod = true;
        break;
      case 'M1':
        final date = targetDate ?? now;
        startTime = DateTime.utc(date.year, date.month, 1);
        endTime = DateTime.utc(date.year, date.month + 1, 1);
        limit = endTime.difference(startTime).inDays;
        isCurrentPeriod = (date.year == now.year && date.month == now.month);
        break;
      case 'Y1':
        final date = targetDate ?? now;
        startTime = DateTime.utc(date.year, 1, 1);
        endTime = DateTime.utc(date.year + 1, 1, 1);
        limit = 12;
        isCurrentPeriod = (date.year == now.year);
        break;
      default:
        return null;
    }

    final startMs = startTime.millisecondsSinceEpoch;
    final endMs = endTime.millisecondsSinceEpoch;
    final quarterDuration = (endMs - startMs) / 4;

    List rawCandles = [];
    final afterTs = endMs.toString();
    
    // Hàm gọi API
    Future<void> fetchApi(String endpoint) async {
      try {
        final response = await dio.get(
          endpoint,
          queryParameters: {'instId': 'BTC-USDT', 'bar': barId, 'limit': limit, 'after': afterTs},
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
      QuarterData('${prefix}4')
    ];

    for (int i = 0; i < 4; i++) {
      quarters[i].startTime = DateTime.fromMillisecondsSinceEpoch(
        (startMs + i * quarterDuration).toInt(), 
        isUtc: true
      ).toLocal();
    }

    double currentPrice = double.parse(rawCandles.first[4]); 

    for (var c in rawCandles) {
      int ts = int.parse(c[0]);
      if (ts < startMs || ts >= endMs) continue; 

      int qIndex = ((ts - startMs) / quarterDuration).floor();
      if (qIndex < 0 || qIndex > 3) continue;

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
        if (quarters[i].high! > maxHigh) { maxHigh = quarters[i].high!; maxHighQ = i; }
        if (quarters[i].low! < minLow) { minLow = quarters[i].low!; minLowQ = i; }
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

        final dt = DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true).toLocal();
        String label = timeframe == 'M1' ? dt.day.toString() : dt.month.toString();
        
        subCandles.add(SubCandle(
          label,
          double.parse(c[1]),
          double.parse(c[2]),
          double.parse(c[3]),
          double.parse(c[4]),
        ));
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