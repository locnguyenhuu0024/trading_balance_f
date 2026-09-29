import 'package:dio/dio.dart';

import '../../portfolio/data/risk/risk_request_coordinator.dart';
import '../domain/level_calculator.dart';
import '../domain/models.dart';

typedef SupportResistanceRepositoryClock = DateTime Function();

/// Public, read-only OKX adapter for the support and resistance feature.
///
/// The request coordinator is required so application wiring can share the
/// foreground public lane's single-flight, spacing, and rate-limit state.
class SupportResistanceRepository {
  SupportResistanceRepository(
    this._dio, {
    required this.requestCoordinator,
    SupportResistanceRepositoryClock? clock,
    this.calculator = const SupportResistanceCalculator(),
  }) : clock = clock ?? DateTime.now;

  static const String instrumentsEndpoint = '/api/v5/public/instruments';
  static const String tickerEndpoint = '/api/v5/market/ticker';
  static const String candlesEndpoint = '/api/v5/market/candles';
  static const int maximumCandleCount = 300;

  final Dio _dio;
  final RiskRequestCoordinator requestCoordinator;
  final SupportResistanceRepositoryClock clock;
  final SupportResistanceCalculator calculator;

  Future<List<SupportResistanceInstrument>> getInstruments({
    required SupportResistanceMarketMode marketMode,
  }) async {
    final response = await _get(
      instrumentsEndpoint,
      queryParameters: <String, dynamic>{'instType': marketMode.instrumentType},
    );
    final rows = _mapRows(response, instrumentsEndpoint);
    final instruments = <SupportResistanceInstrument>[];
    final seen = <String>{};
    for (final row in rows) {
      final instrumentType = _text(row['instType'])?.toUpperCase();
      if (instrumentType != marketMode.instrumentType) continue;
      if (_text(row['state'])?.toLowerCase() != 'live') continue;

      final isUsdtMarket = switch (marketMode) {
        SupportResistanceMarketMode.spot =>
          _text(row['quoteCcy'])?.toUpperCase() == 'USDT',
        SupportResistanceMarketMode.perpetual =>
          _text(row['settleCcy'])?.toUpperCase() == 'USDT' &&
              (_text(row['ctType']) == null ||
                  _text(row['ctType'])!.toLowerCase() == 'linear'),
      };
      if (!isUsdtMarket) continue;

      final instrumentId = _text(row['instId'])?.toUpperCase();
      if (instrumentId == null) {
        throw _invalidResponse(
          instrumentsEndpoint,
          'A live USDT instrument was missing its identity',
        );
      }
      final idPattern = marketMode == SupportResistanceMarketMode.spot
          ? RegExp(r'^([A-Z0-9]+)-USDT$')
          : RegExp(r'^([A-Z0-9]+)-USDT-SWAP$');
      final idBase = idPattern.firstMatch(instrumentId)?.group(1);
      if (idBase == null) {
        throw _invalidResponse(
          instrumentsEndpoint,
          'A live USDT instrument key did not match its market mode',
        );
      }
      final metadataBase = _text(row['baseCcy'])?.toUpperCase();
      final base = metadataBase == null || metadataBase.isEmpty
          ? idBase
          : metadataBase;
      if (base != idBase || instrumentId != marketMode.instrumentIdFor(base)) {
        throw _invalidResponse(
          instrumentsEndpoint,
          'A live USDT instrument key did not match its base currency',
        );
      }
      if (!seen.add(instrumentId)) {
        throw _invalidResponse(
          instrumentsEndpoint,
          'The active instrument response contained a duplicate key',
        );
      }
      instruments.add(
        SupportResistanceInstrument(
          marketMode: marketMode,
          instrumentId: instrumentId,
          baseCurrency: base,
        ),
      );
    }
    instruments.sort(
      (left, right) => left.instrumentId.compareTo(right.instrumentId),
    );
    return List<SupportResistanceInstrument>.unmodifiable(instruments);
  }

  Future<SupportResistanceTicker> getTicker({
    required SupportResistanceMarketMode marketMode,
    required String instrumentId,
  }) async {
    final normalized = _validateInstrumentId(marketMode, instrumentId);
    final response = await _get(
      tickerEndpoint,
      queryParameters: <String, dynamic>{'instId': normalized},
    );
    final rows = _mapRows(response, tickerEndpoint);
    if (rows.length != 1 ||
        _text(rows.single['instId'])?.toUpperCase() != normalized) {
      throw SupportResistanceRepositoryException(
        failure: SupportResistanceRepositoryFailure.unavailableTicker,
        message: 'No exact-market ticker was returned',
        endpoint: tickerEndpoint,
      );
    }
    final lastPrice = _number(rows.single['last']);
    if (lastPrice == null || !lastPrice.isFinite || lastPrice <= 0) {
      throw SupportResistanceRepositoryException(
        failure: SupportResistanceRepositoryFailure.unavailableTicker,
        message: 'The exact-market ticker price was invalid',
        endpoint: tickerEndpoint,
      );
    }
    return SupportResistanceTicker(
      instrumentId: normalized,
      lastPrice: lastPrice,
      observedAt: clock().toUtc(),
    );
  }

  Future<List<SupportResistanceCandle>> getCandles({
    required SupportResistanceMarketMode marketMode,
    required String instrumentId,
    required SupportResistanceTimeframe timeframe,
  }) async {
    final normalized = _validateInstrumentId(marketMode, instrumentId);
    final candlesNewestFirst = <SupportResistanceCandle>[];
    final seenTimestamps = <int>{};
    var cursor = '';
    DateTime? previousPageOldest;
    final observedAt = clock().toUtc();

    // OKX caps a candle page at 300 rows. A current unconfirmed row can occupy
    // one slot, so request an older page only when fewer than 300 closed rows
    // were recovered from the newest page.
    for (var pageNumber = 0; pageNumber < 10; pageNumber++) {
      final query = <String, dynamic>{
        'instId': normalized,
        'bar': timeframe.bar,
        'limit': maximumCandleCount,
        if (cursor.isNotEmpty) 'after': cursor,
      };
      final response = await _get(candlesEndpoint, queryParameters: query);
      final rows = _dataItems(response, candlesEndpoint);
      if (rows.isEmpty) break;
      if (rows.length > maximumCandleCount) {
        throw _invalidResponse(
          candlesEndpoint,
          'The candle response exceeded its requested page size',
        );
      }

      DateTime? previousTimestamp;
      final pageCandles = <SupportResistanceCandle>[];
      for (final raw in rows) {
        final row = _candleRow(raw);
        final rowInstrument = _text(row['instId']);
        if (rowInstrument != null &&
            rowInstrument.toUpperCase() != normalized) {
          throw _invalidResponse(
            candlesEndpoint,
            'A candle response contained a different instrument key',
          );
        }
        final timestamp = _epoch(row['ts']);
        if (timestamp == null || !timeframe.isUtcAligned(timestamp)) {
          throw _invalidResponse(
            candlesEndpoint,
            'A candle timestamp was invalid or not UTC-aligned',
          );
        }
        if (previousTimestamp != null &&
            !timestamp.isBefore(previousTimestamp)) {
          throw _invalidResponse(
            candlesEndpoint,
            'Candle timestamps were duplicated or out of order',
          );
        }
        previousTimestamp = timestamp;
        if (!seenTimestamps.add(timestamp.millisecondsSinceEpoch)) {
          throw _invalidResponse(
            candlesEndpoint,
            'Candle pages contained a duplicate timestamp',
          );
        }

        final confirmation = _text(row['confirm']);
        if (confirmation == '0') continue;
        if (confirmation != '1') {
          throw _invalidResponse(
            candlesEndpoint,
            'A candle confirmation flag was missing or invalid',
          );
        }
        if (timestamp.add(timeframe.duration).isAfter(observedAt)) {
          throw _invalidResponse(
            candlesEndpoint,
            'A confirmed candle had not reached its UTC close time',
          );
        }
        final open = _number(row['o']);
        final high = _number(row['h']);
        final low = _number(row['l']);
        final close = _number(row['c']);
        if (open == null || high == null || low == null || close == null) {
          throw _invalidResponse(
            candlesEndpoint,
            'A confirmed candle had malformed OHLC values',
          );
        }
        final candle = SupportResistanceCandle(
          timestamp: timestamp,
          open: open,
          high: high,
          low: low,
          close: close,
          timeframe: timeframe,
          confirmed: true,
        );
        if (!candle.hasValidPrices) {
          throw _invalidResponse(
            candlesEndpoint,
            'A confirmed candle had invalid OHLC ranges',
          );
        }
        pageCandles.add(candle);
      }

      final pageOldest = previousTimestamp!;
      if (previousPageOldest != null &&
          !pageOldest.isBefore(previousPageOldest)) {
        throw _invalidResponse(
          candlesEndpoint,
          'Candle pagination did not move to older data',
        );
      }
      previousPageOldest = pageOldest;
      candlesNewestFirst.addAll(pageCandles);
      if (candlesNewestFirst.length >= maximumCandleCount ||
          rows.length < maximumCandleCount) {
        break;
      }
      cursor = pageOldest.millisecondsSinceEpoch.toString();
    }

    candlesNewestFirst.sort(
      (left, right) => right.timestamp.compareTo(left.timestamp),
    );
    final selected = candlesNewestFirst.length <= maximumCandleCount
        ? candlesNewestFirst
        : candlesNewestFirst.sublist(0, maximumCandleCount);
    selected.sort((left, right) => left.timestamp.compareTo(right.timestamp));
    return List<SupportResistanceCandle>.unmodifiable(selected);
  }

  Future<SupportResistanceMarketSnapshot> loadLevels({
    required SupportResistanceMarketMode marketMode,
    required String instrumentId,
    required SupportResistanceTimeframe timeframe,
  }) async {
    final normalized = _validateInstrumentId(marketMode, instrumentId);
    final tickerFuture = getTicker(
      marketMode: marketMode,
      instrumentId: normalized,
    );
    final candlesFuture = getCandles(
      marketMode: marketMode,
      instrumentId: normalized,
      timeframe: timeframe,
    );
    final ticker = await tickerFuture;
    final candles = await candlesFuture;
    final analysis = calculator.calculate(
      candles: candles,
      referencePrice: ticker.lastPrice,
    );
    return SupportResistanceMarketSnapshot(
      marketMode: marketMode,
      instrumentId: normalized,
      timeframe: timeframe,
      referencePrice: ticker.lastPrice,
      fetchedAt: clock().toUtc(),
      candles: candles,
      analysis: analysis,
    );
  }

  Future<Response<dynamic>> _get(
    String endpoint, {
    required Map<String, dynamic> queryParameters,
  }) async {
    try {
      return await requestCoordinator.run<Response<dynamic>>(
        lane: RiskRequestLane.public,
        key: _requestKey(endpoint, queryParameters),
        request: () => _dio.get<dynamic>(
          endpoint,
          queryParameters: queryParameters,
          options: Options(extra: <String, dynamic>{'requiresAuth': false}),
        ),
      );
    } on RiskRequestBackoffException catch (error) {
      throw SupportResistanceRepositoryException(
        failure: SupportResistanceRepositoryFailure.rateLimited,
        message: 'Public market request is backing off',
        endpoint: endpoint,
        statusCode: error.statusCode,
        retryAfter: error.retryAfter,
        retryAt: error.retryAt,
        cause: error,
      );
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      throw SupportResistanceRepositoryException(
        failure: status == 429
            ? SupportResistanceRepositoryFailure.rateLimited
            : SupportResistanceRepositoryFailure.transport,
        message: status == 429
            ? 'Public market request is rate-limited'
            : 'Public market request failed',
        endpoint: endpoint,
        statusCode: status,
        retryAfter: _retryAfter(error.response),
        cause: error,
      );
    } on Object catch (error) {
      throw SupportResistanceRepositoryException(
        failure: SupportResistanceRepositoryFailure.transport,
        message: 'Public market request failed',
        endpoint: endpoint,
        cause: error,
      );
    }
  }

  String _requestKey(String endpoint, Map<String, dynamic> queryParameters) {
    final entries = queryParameters.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return '$endpoint?${entries.map((entry) => '${entry.key}=${entry.value}').join('&')}';
  }

  String _validateInstrumentId(
    SupportResistanceMarketMode marketMode,
    String instrumentId,
  ) {
    final normalized = instrumentId.trim().toUpperCase();
    final pattern = marketMode == SupportResistanceMarketMode.spot
        ? RegExp(r'^[A-Z0-9]+-USDT$')
        : RegExp(r'^[A-Z0-9]+-USDT-SWAP$');
    if (!pattern.hasMatch(normalized)) {
      throw SupportResistanceRepositoryException(
        failure: SupportResistanceRepositoryFailure.invalidRequest,
        message: 'Instrument key does not match the selected market mode',
        endpoint: '',
      );
    }
    return normalized;
  }

  List<Map<String, dynamic>> _mapRows(
    Response<dynamic> response,
    String endpoint,
  ) {
    final values = _dataItems(response, endpoint);
    if (values.any((value) => value is! Map)) {
      throw _invalidResponse(endpoint, 'Response data row was not an object');
    }
    return values.map((value) => _stringKeyedMap(value as Map)).toList();
  }

  List<Object?> _dataItems(Response<dynamic> response, String endpoint) {
    final body = response.data;
    if (body is! Map) {
      throw _invalidResponse(endpoint, 'Response body was not an object');
    }
    final code = _text(body['code']);
    if (code != '0') {
      throw _invalidResponse(endpoint, 'Exchange returned an error code');
    }
    final data = body['data'];
    if (data is! List) {
      throw _invalidResponse(endpoint, 'Response data was not a list');
    }
    return List<Object?>.from(data);
  }

  Map<String, dynamic> _candleRow(Object? raw) {
    if (raw is Map) return _stringKeyedMap(raw);
    if (raw is! List || raw.length < 9) {
      throw _invalidResponse(candlesEndpoint, 'Candle row was malformed');
    }
    return <String, dynamic>{
      'ts': raw[0],
      'o': raw[1],
      'h': raw[2],
      'l': raw[3],
      'c': raw[4],
      'confirm': raw[8],
    };
  }

  Map<String, dynamic> _stringKeyedMap(Map raw) =>
      raw.map<String, dynamic>((key, value) => MapEntry(key.toString(), value));

  DateTime? _epoch(Object? value) {
    final millis = _integer(value);
    if (millis == null || millis <= 0) return null;
    try {
      return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    } on RangeError {
      return null;
    }
  }

  int? _integer(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  double? _number(Object? value) {
    final parsed = switch (value) {
      num number => number.toDouble(),
      String text => double.tryParse(text.trim()),
      _ => null,
    };
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  String? _text(Object? value) {
    if (value is String) return value.trim();
    if (value is num) return value.toString();
    return null;
  }

  Duration? _retryAfter(Response<dynamic>? response) {
    final raw = response?.headers.value('retry-after')?.trim();
    if (raw == null || raw.isEmpty) return null;
    final seconds = int.tryParse(raw);
    return seconds == null || seconds < 0 ? null : Duration(seconds: seconds);
  }

  SupportResistanceRepositoryException _invalidResponse(
    String endpoint,
    String message,
  ) => SupportResistanceRepositoryException(
    failure: SupportResistanceRepositoryFailure.invalidResponse,
    message: message,
    endpoint: endpoint,
  );
}
