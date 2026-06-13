// File Name: fractal_provider.dart
// File Path: lib/features/fractal_tracker/presentation/providers/fractal_provider.dart

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/fractal_model.dart';

final fractalDataProvider = FutureProvider.autoDispose<List<FractalData>>((ref) async {
  final dio = Dio(BaseOptions(baseUrl: 'https://www.okx.com'));

  final results = await Future.wait([
    _fetchAndProcess(dio, 'D1', '1H', 24),
    _fetchAndProcess(dio, 'W1', '4H', 42),
    _fetchAndProcess(dio, 'M1', '1D', 31),
    _fetchAndProcess(dio, 'Y1', '1W', 53),
  ]);

  return results.whereType<FractalData>().toList();
});

Future<FractalData?> _fetchAndProcess(Dio dio, String timeframe, String barId, int limit) async {
  try {
    final response = await dio.get(
      '/api/v5/market/candles',
      queryParameters: {'instId': 'BTC-USDT', 'bar': barId, 'limit': limit},
    );

    if (response.data['code'] != '0') return null;
    final List rawCandles = response.data['data'];
    if (rawCandles.isEmpty) return null;

    final now = DateTime.now().toUtc();
    DateTime startTime;
    DateTime endTime;

    switch (timeframe) {
      case 'D1':
        startTime = DateTime.utc(now.year, now.month, now.day);
        endTime = startTime.add(const Duration(days: 1));
        break;
      case 'W1':
        final mondayOffset = now.weekday - 1;
        startTime = DateTime.utc(now.year, now.month, now.day).subtract(Duration(days: mondayOffset));
        endTime = startTime.add(const Duration(days: 7));
        break;
      case 'M1':
        startTime = DateTime.utc(now.year, now.month, 1);
        endTime = DateTime.utc(now.year, now.month + 1, 1);
        break;
      case 'Y1':
        startTime = DateTime.utc(now.year, 1, 1);
        endTime = DateTime.utc(now.year + 1, 1, 1);
        break;
      default:
        return null;
    }

    final startMs = startTime.millisecondsSinceEpoch;
    final endMs = endTime.millisecondsSinceEpoch;
    final quarterDuration = (endMs - startMs) / 4;

    // THAY ĐỔI: Kiểm tra khung thời gian để quyết định có gắn chữ Q hay không
    final prefix = timeframe == 'Y1' ? 'Q' : '';
    List<QuarterData> quarters = [
      QuarterData('${prefix}1'),
      QuarterData('${prefix}2'),
      QuarterData('${prefix}3'),
      QuarterData('${prefix}4')
    ];

    // THÊM MỚI: Tính toán thời gian bắt đầu cho từng đốt (Chuyển sang giờ Local)
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

    for (var q in quarters) {
      // Xác định màu sắc (Xanh hay Đỏ)
      if (!q.isEmpty) {
        // q.isGreen là getter trong model dựa trên giá open/close
      }
    }

    return FractalData(timeframeLabel: timeframe, quarters: quarters, currentPrice: currentPrice);
  } catch (e) {
    return null;
  }
}