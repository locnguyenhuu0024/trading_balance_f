import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../portfolio/data/risk/risk_request_coordinator.dart';
import '../domain/strategy_calculator.dart';
import '../domain/strategy_models.dart';

typedef StrategyMarketClock = DateTime Function();

class StrategyMarketRepository {
  StrategyMarketRepository(
    this._dio, {
    required this.requestCoordinator,
    StrategyMarketClock? clock,
    this.calculator = const StrategyLevelCalculator(),
  }) : clock = clock ?? DateTime.now;

  static const instrumentsEndpoint = '/api/v5/public/instruments';
  static const tickerEndpoint = '/api/v5/market/ticker';
  static const candlesEndpoint = '/api/v5/market/candles';
  static const maximumCandleCount = 500;
  static const candlePageSize = 300;

  final Dio _dio;
  final RiskRequestCoordinator requestCoordinator;
  final StrategyMarketClock clock;
  final StrategyLevelCalculator calculator;
  final Map<String, DateTime> _lastTickerTimestamps = {};

  Future<List<StrategyInstrument>> getInstruments() async {
    final response = await _get(
      instrumentsEndpoint,
      query: const {'instType': 'SWAP'},
    );
    final instruments = <StrategyInstrument>[];
    final seen = <String>{};
    for (final raw in _rows(response, instrumentsEndpoint)) {
      if (_text(raw['instType'])?.toUpperCase() != 'SWAP' ||
          _text(raw['state'])?.toLowerCase() != 'live' ||
          _text(raw['settleCcy'])?.toUpperCase() != 'USDT' ||
          _text(raw['ctType'])?.toLowerCase() != 'linear') {
        continue;
      }
      final instrumentId = _text(raw['instId'])?.toUpperCase();
      final base = _text(raw['baseCcy'])?.toUpperCase();
      if (instrumentId == null || base == null) continue;
      if (!RegExp(r'^[A-Z0-9]+-USDT-SWAP$').hasMatch(instrumentId) ||
          instrumentId != '$base-USDT-SWAP' ||
          !seen.add(instrumentId)) {
        continue;
      }
      instruments.add(
        StrategyInstrument(instrumentId: instrumentId, base: base),
      );
    }
    instruments.sort(
      (left, right) => left.instrumentId.compareTo(right.instrumentId),
    );
    return List.unmodifiable(instruments);
  }

  Future<StrategyTicker> getTicker({required String instrumentId}) async {
    final normalized = _validateInstrument(instrumentId);
    final response = await _get(tickerEndpoint, query: {'instId': normalized});
    final rows = _rows(response, tickerEndpoint);
    if (rows.length != 1 ||
        _text(rows.single['instId'])?.toUpperCase() != normalized) {
      throw const StrategyMarketException(
        'No ticker for the selected USDT swap is available.',
      );
    }
    final price = _number(rows.single['last']);
    final timestamp = _epoch(rows.single['ts']);
    final now = clock().toUtc();
    if (price == null || price <= 0 || timestamp == null) {
      throw const StrategyMarketException(
        'The selected swap ticker is invalid.',
      );
    }
    final age = now.difference(timestamp);
    if (age.isNegative || age > const Duration(seconds: 4)) {
      throw const StrategyMarketException('The selected swap ticker is stale.');
    }
    final previousTimestamp = _lastTickerTimestamps[normalized];
    if (previousTimestamp != null && timestamp.isBefore(previousTimestamp)) {
      throw const StrategyMarketException(
        'An out-of-order swap ticker was rejected.',
      );
    }
    _lastTickerTimestamps[normalized] = timestamp;
    return StrategyTicker(
      instrumentId: normalized,
      lastPrice: price,
      observedAt: timestamp,
    );
  }

  Future<List<StrategyCandle>> getCandles({
    required String instrumentId,
    required StrategyInterval interval,
  }) async {
    final normalized = _validateInstrument(instrumentId);
    final candles = <StrategyCandle>[];
    final seenTimestamps = <int>{};
    var cursor = '';
    DateTime? priorPageOldest;

    for (
      var page = 0;
      page < 10 && candles.length < maximumCandleCount;
      page++
    ) {
      final query = <String, Object>{
        'instId': normalized,
        'bar': interval.bar,
        'limit': candlePageSize,
        if (cursor.isNotEmpty) 'after': cursor,
      };
      final response = await _get(candlesEndpoint, query: query);
      final data = _data(response, candlesEndpoint);
      if (data.isEmpty) break;
      if (data.length > candlePageSize) {
        throw const StrategyMarketException(
          'The swap returned an oversized candle page.',
        );
      }

      DateTime? pageOldest;
      for (final raw in data) {
        final row = _candleRow(raw);
        if (row == null) continue;
        final rowInstrument = _text(row['instId']);
        if (rowInstrument != null &&
            rowInstrument.toUpperCase() != normalized) {
          continue;
        }
        final timestamp = _epoch(row['ts']);
        if (timestamp == null || !interval.isUtcAligned(timestamp)) continue;
        if (pageOldest == null || timestamp.isBefore(pageOldest)) {
          pageOldest = timestamp;
        }
        if (_text(row['confirm']) != '1' ||
            timestamp.add(interval.duration).isAfter(clock().toUtc())) {
          continue;
        }
        final key = timestamp.millisecondsSinceEpoch;
        if (!seenTimestamps.add(key)) continue;
        final open = _number(row['o']);
        final high = _number(row['h']);
        final low = _number(row['l']);
        final close = _number(row['c']);
        if (open == null || high == null || low == null || close == null)
          continue;
        final candle = StrategyCandle(
          timestamp: timestamp,
          open: open,
          high: high,
          low: low,
          close: close,
          interval: interval,
        );
        if (!candle.hasValidPrices) continue;
        candles.add(candle);
      }

      if (pageOldest == null) break;
      if (priorPageOldest != null && !pageOldest.isBefore(priorPageOldest)) {
        throw const StrategyMarketException(
          'Candle pagination did not move to older data.',
        );
      }
      priorPageOldest = pageOldest;
      if (data.length < candlePageSize) break;
      cursor = pageOldest.millisecondsSinceEpoch.toString();
    }

    candles.sort((left, right) => right.timestamp.compareTo(left.timestamp));
    final newest = candles.length <= maximumCandleCount
        ? candles
        : candles.sublist(0, maximumCandleCount);
    newest.sort((left, right) => left.timestamp.compareTo(right.timestamp));
    return List.unmodifiable(newest);
  }

  Future<StrategyMarketSnapshot> loadLevels({
    required String instrumentId,
    required StrategyInterval interval,
  }) async {
    final normalized = _validateInstrument(instrumentId);
    final tickerFuture = getTicker(instrumentId: normalized);
    final candlesFuture = getCandles(
      instrumentId: normalized,
      interval: interval,
    );
    final ticker = await tickerFuture;
    final candles = await candlesFuture;
    return StrategyMarketSnapshot(
      instrumentId: normalized,
      interval: interval,
      ticker: ticker,
      candles: candles,
      analysis: calculator.calculate(
        candles: candles,
        referencePrice: ticker.lastPrice,
      ),
    );
  }

  Future<Response<dynamic>> _get(
    String endpoint, {
    required Map<String, Object> query,
  }) async {
    final keyEntries = query.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final key =
        '$endpoint?${keyEntries.map((e) => '${e.key}=${e.value}').join('&')}';
    try {
      return await requestCoordinator.run<Response<dynamic>>(
        lane: RiskRequestLane.public,
        key: key,
        request: () => _dio.get<dynamic>(
          endpoint,
          queryParameters: query,
          options: Options(extra: const {'requiresAuth': false}),
        ),
      );
    } on RiskRequestBackoffException {
      throw const StrategyMarketException(
        'Public market requests are backing off.',
      );
    } on DioException catch (error) {
      throw StrategyMarketException(
        error.response?.statusCode == 429
            ? 'Public market requests are rate-limited.'
            : 'Could not load public swap market data.',
      );
    } on StrategyMarketException {
      rethrow;
    } on Object {
      throw const StrategyMarketException(
        'Could not load public swap market data.',
      );
    }
  }

  List<Map<String, dynamic>> _rows(
    Response<dynamic> response,
    String endpoint,
  ) => _data(
    response,
    endpoint,
  ).whereType<Map>().map(_keyed).toList(growable: false);

  List<Object?> _data(Response<dynamic> response, String endpoint) {
    final body = response.data;
    if (body is! Map || _text(body['code']) != '0' || body['data'] is! List) {
      throw StrategyMarketException(
        'The exchange returned an invalid response from $endpoint.',
      );
    }
    return List<Object?>.from(body['data'] as List);
  }

  Map<String, dynamic>? _candleRow(Object? raw) {
    if (raw is Map) return _keyed(raw);
    if (raw is! List || raw.length < 9) return null;
    return {
      'ts': raw[0],
      'o': raw[1],
      'h': raw[2],
      'l': raw[3],
      'c': raw[4],
      'confirm': raw[8],
    };
  }

  Map<String, dynamic> _keyed(Map raw) =>
      raw.map<String, dynamic>((key, value) => MapEntry(key.toString(), value));

  String _validateInstrument(String instrumentId) {
    final normalized = instrumentId.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]+-USDT-SWAP$').hasMatch(normalized)) {
      throw const StrategyMarketException(
        'Choose a USDT linear swap instrument.',
      );
    }
    return normalized;
  }

  String? _text(Object? value) =>
      value is String || value is num ? value.toString().trim() : null;

  double? _number(Object? value) {
    final parsed = switch (value) {
      num number => number.toDouble(),
      String text => double.tryParse(text.trim()),
      _ => null,
    };
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  DateTime? _epoch(Object? value) {
    final millis = switch (value) {
      int number => number,
      num number when number.isFinite && number == number.roundToDouble() =>
        number.toInt(),
      String text => int.tryParse(text.trim()),
      _ => null,
    };
    if (millis == null || millis <= 0) return null;
    try {
      return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    } on RangeError {
      return null;
    }
  }
}

final strategyMarketRepositoryProvider = Provider<StrategyMarketRepository>((
  ref,
) {
  final dio = Dio(
    BaseOptions(
      baseUrl: kIsWeb ? '' : 'https://www.okx.com',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: const {'Content-Type': 'application/json'},
    ),
  );
  ref.onDispose(() => dio.close(force: true));
  return StrategyMarketRepository(
    dio,
    requestCoordinator: ref.watch(riskRequestCoordinatorProvider),
  );
});
