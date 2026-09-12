import 'package:dio/dio.dart';

import '../../domain/risk/market_risk_engine.dart';
import '../../domain/risk/risk_models.dart';
import 'okx_risk_dto.dart';

typedef RiskMarketRepositoryClock = DateTime Function();

/// Public market data errors remain typed so callers can expose an unavailable
/// source without treating a failed request as neutral market evidence.
class RiskMarketRepositoryException implements Exception {
  const RiskMarketRepositoryException(
    this.message, {
    this.statusCode,
    this.endpoint,
    this.cause,
    this.payloadError = false,
  });

  final String message;
  final int? statusCode;
  final String? endpoint;
  final Object? cause;
  final bool payloadError;

  @override
  String toString() {
    final suffix = statusCode == null ? '' : ' (HTTP $statusCode)';
    return 'RiskMarketRepositoryException$suffix: $message';
  }
}

/// Read-only public OKX market adapter. It never reuses the authenticated
/// account repository and never exposes a trading or borrowing operation.
class RiskMarketRepository {
  RiskMarketRepository(
    this._dio, {
    RiskMarketRepositoryClock? clock,
    this.venue = 'OKX',
    this.candleLimit = 120,
  }) : clock = clock ?? DateTime.now;

  final Dio _dio;
  final RiskMarketRepositoryClock clock;
  final String venue;
  final int candleLimit;

  static const String candlesEndpoint = '/api/v5/market/candles';
  static const String fundingEndpoint = '/api/v5/public/funding-rate';
  static const String openInterestEndpoint = '/api/v5/public/open-interest';

  /// Fetches confirmed spot candles for the requested 1H or 4H interval.
  /// Invalid intervals are rejected before any request is made.
  Future<MarketCandleSeries> getCandles({
    required String instId,
    required String interval,
    int? limit,
  }) async {
    final instrument = instId.trim().toUpperCase();
    final normalizedInterval = interval.trim().toUpperCase();
    _requireInterval(normalizedInterval);
    if (instrument.isEmpty) {
      throw ArgumentError.value('', 'instId', 'must not be empty');
    }
    final observedAt = clock().toUtc();
    final response = await _get(
      candlesEndpoint,
      queryParameters: <String, dynamic>{
        'instId': instrument,
        'bar': normalizedInterval,
        'limit': _safeLimit(limit ?? candleLimit, maximum: 300),
      },
    );
    final rows = _dataItems(response, candlesEndpoint);
    final parsed = <MarketCandle>[];
    var discarded = false;
    for (final row in rows) {
      final candle = _parseCandle(row, interval: normalizedInterval);
      if (candle == null) {
        discarded = true;
      } else {
        parsed.add(candle);
      }
    }
    parsed.sort((left, right) => left.timestamp.compareTo(right.timestamp));
    final unique = <MarketCandle>[];
    var duplicate = false;
    for (final candle in parsed) {
      if (unique.isNotEmpty && unique.last.timestamp == candle.timestamp) {
        duplicate = true;
        continue;
      }
      unique.add(candle);
    }
    final gap = _hasGap(unique, normalizedInterval);
    final complete = unique.isNotEmpty && !duplicate && !gap;
    final reason = complete
        ? null
        : duplicate
        ? 'Market $normalizedInterval candles contain duplicate timestamps'
        : gap
        ? 'Market $normalizedInterval candles contain a timestamp gap'
        : discarded
        ? 'No valid confirmed $normalizedInterval candles were returned'
        : 'No confirmed $normalizedInterval candles were returned';
    final sourceAt = unique.isEmpty ? null : unique.last.timestamp;
    return MarketCandleSeries(
      instrument: instrument,
      interval: normalizedInterval,
      candles: List.unmodifiable(unique),
      source: MarketSourceInfo(
        venue: venue,
        instrument: instrument,
        endpoint: candlesEndpoint,
        observedAt: observedAt,
        sourceAt: sourceAt,
        windowStart: unique.isEmpty ? null : unique.first.timestamp,
        windowEnd: sourceAt,
        quality: complete
            ? RiskQuality.complete(
                source: '$venue $candlesEndpoint',
                observedAt: observedAt,
                sourceAt: sourceAt,
              )
            : RiskQuality.partial(
                source: '$venue $candlesEndpoint',
                reason: reason,
                observedAt: observedAt,
                sourceAt: sourceAt,
              ),
      ),
      complete: complete,
      missingReason: reason,
    );
  }

  /// Fetches funding for exactly one USDT perpetual instrument.
  Future<MarketFundingObservation?> getFunding({required String instId}) async {
    return (await getFundingResult(instId: instId)).value;
  }

  Future<MarketSourceResult<MarketFundingObservation>> getFundingResult({
    required String instId,
  }) async {
    final instrument = instId.trim().toUpperCase();
    if (instrument.isEmpty) {
      throw ArgumentError.value('', 'instId', 'must not be empty');
    }
    final observedAt = clock().toUtc();
    final List<Map<String, dynamic>> rows;
    try {
      final response = await _get(
        fundingEndpoint,
        queryParameters: <String, dynamic>{'instId': instrument},
      );
      rows = _dataList(response, fundingEndpoint);
    } on RiskMarketRepositoryException catch (error) {
      return MarketSourceResult<MarketFundingObservation>(
        quality: _exceptionQuality(error, instrument, observedAt),
      );
    }
    var malformedRow = false;
    for (final row in rows) {
      final rowInstrument = parseRiskText(row['instId'])?.toUpperCase();
      if (rowInstrument == null) {
        malformedRow = true;
        continue;
      }
      if (rowInstrument != instrument) continue;
      final rate = parseRiskNumber(row['fundingRate']);
      final fundingTime = parseRiskEpoch(row['fundingTime']);
      final nextFundingTime = parseRiskEpoch(row['nextFundingTime']);
      final sourceAt = fundingTime ?? nextFundingTime;
      final complete =
          rate != null &&
          fundingTime != null &&
          nextFundingTime != null &&
          nextFundingTime.isAfter(fundingTime);
      final reason = complete
          ? null
          : 'Funding rate and actual settlement interval are incomplete';
      final quality = complete
          ? RiskQuality.complete(
              source: '$venue $fundingEndpoint',
              observedAt: observedAt,
              sourceAt: sourceAt,
            )
          : RiskQuality.partial(
              source: '$venue $fundingEndpoint',
              reason: reason,
              observedAt: observedAt,
              sourceAt: sourceAt,
            );
      return MarketSourceResult<MarketFundingObservation>(
        value: MarketFundingObservation(
          instrument: instrument,
          rate: rate,
          fundingTime: fundingTime,
          nextFundingTime: nextFundingTime,
          source: MarketSourceInfo(
            venue: venue,
            instrument: instrument,
            endpoint: fundingEndpoint,
            observedAt: observedAt,
            sourceAt: sourceAt,
            quality: quality,
          ),
        ),
        quality: quality,
      );
    }
    return MarketSourceResult<MarketFundingObservation>(
      quality: RiskQuality(
        status: malformedRow
            ? RiskQualityStatus.partial
            : RiskQualityStatus.empty,
        source: '$venue $fundingEndpoint',
        reason: malformedRow
            ? 'Funding payload contains a row without a valid instId'
            : 'No matching $instrument funding observation',
        observedAt: observedAt,
      ),
    );
  }

  /// Fetches current currency-unit open-interest observations for exactly one
  /// USDT perpetual instrument. Historical samples are supplied separately by
  /// the caller; OI in USD and contract-count OI are deliberately ignored.
  Future<List<MarketOpenInterestSample>> getOpenInterest({
    required String instId,
  }) async =>
      (await getOpenInterestResult(instId: instId)).value ??
      const <MarketOpenInterestSample>[];

  Future<MarketSourceResult<List<MarketOpenInterestSample>>>
  getOpenInterestResult({required String instId}) async {
    final instrument = instId.trim().toUpperCase();
    if (instrument.isEmpty) {
      throw ArgumentError.value('', 'instId', 'must not be empty');
    }
    final observedAt = clock().toUtc();
    final List<Map<String, dynamic>> rows;
    try {
      final response = await _get(
        openInterestEndpoint,
        queryParameters: <String, dynamic>{
          'instId': instrument,
          'instType': 'SWAP',
        },
      );
      rows = _dataList(response, openInterestEndpoint);
    } on RiskMarketRepositoryException catch (error) {
      return MarketSourceResult<List<MarketOpenInterestSample>>(
        quality: _exceptionQuality(error, instrument, observedAt),
      );
    }
    final parsed = <MarketOpenInterestSample>[];
    var matchingRows = 0;
    var malformedMatchingRow = false;
    var malformedUnscopedRow = false;
    for (final row in rows) {
      final rowInstrument = parseRiskText(row['instId'])?.toUpperCase();
      final timestamp = parseRiskEpoch(row['ts'] ?? row['timestamp']);
      if (rowInstrument != instrument) {
        if (rowInstrument == null) malformedUnscopedRow = true;
        continue;
      }
      matchingRows++;
      final oiCcy = parseRiskNumber(row['oiCcy']);
      if (timestamp == null || oiCcy == null || !oiCcy.isFinite || oiCcy <= 0) {
        malformedMatchingRow = true;
        continue;
      }
      parsed.add(
        MarketOpenInterestSample(
          instrument: instrument,
          timestamp: timestamp,
          oiCcy: oiCcy,
          source: MarketSourceInfo(
            venue: venue,
            instrument: instrument,
            endpoint: openInterestEndpoint,
            observedAt: observedAt,
            sourceAt: timestamp,
            quality: RiskQuality.complete(
              source: '$venue $openInterestEndpoint',
              observedAt: observedAt,
              sourceAt: timestamp,
            ),
          ),
        ),
      );
    }
    if (parsed.isNotEmpty && (malformedMatchingRow || malformedUnscopedRow)) {
      return MarketSourceResult<List<MarketOpenInterestSample>>(
        quality: RiskQuality.partial(
          source: '$venue $openInterestEndpoint',
          reason: malformedMatchingRow
              ? 'Matching $instrument open-interest payload contains a malformed row'
              : 'Open-interest payload contains a row without a valid instId',
          observedAt: observedAt,
          sourceAt: parsed.last.timestamp,
        ),
      );
    }
    for (var index = 1; index < parsed.length; index++) {
      if (!parsed[index].timestamp.isAfter(parsed[index - 1].timestamp)) {
        return MarketSourceResult<List<MarketOpenInterestSample>>(
          quality: RiskQuality.partial(
            source: '$venue $openInterestEndpoint',
            reason:
                'Matching $instrument open-interest samples contain duplicate or out-of-order timestamps',
            observedAt: observedAt,
            sourceAt: parsed.last.timestamp,
          ),
        );
      }
    }
    if (parsed.isEmpty) {
      final status = matchingRows == 0 && !malformedUnscopedRow
          ? RiskQualityStatus.empty
          : RiskQualityStatus.partial;
      final reason = matchingRows == 0 && !malformedUnscopedRow
          ? 'No matching $instrument current open-interest observation'
          : matchingRows > 0
          ? 'Matching $instrument open-interest payload has no valid oiCcy sample'
          : 'Open-interest payload contains a row without a valid instId';
      return MarketSourceResult<List<MarketOpenInterestSample>>(
        quality: RiskQuality(
          status: status,
          source: '$venue $openInterestEndpoint',
          reason: reason,
          observedAt: observedAt,
        ),
      );
    }
    final sourceQuality = parsed.first.source.quality;
    return MarketSourceResult<List<MarketOpenInterestSample>>(
      value: List.unmodifiable(parsed),
      quality: sourceQuality,
    );
  }

  /// Loads the exact spot and derivative proxy mapping required by P02.
  Future<MarketRiskSnapshot> load({
    required String asset,
    DateTime? now,
  }) async {
    final normalizedAsset = asset.trim().toUpperCase();
    if (normalizedAsset.isEmpty) {
      throw ArgumentError.value('', 'asset', 'must not be empty');
    }
    final assetInstrument = '$normalizedAsset-USDT';
    const btcInstrument = 'BTC-USDT';
    final derivativeInstrument = '$normalizedAsset-USDT-SWAP';
    final observedAt = (now ?? clock()).toUtc();

    final assetOneHourFuture = _safeCandles(assetInstrument, '1H', observedAt);
    final assetFourHourFuture = _safeCandles(assetInstrument, '4H', observedAt);
    final btcOneHourFuture = normalizedAsset == 'BTC'
        ? assetOneHourFuture
        : _safeCandles(btcInstrument, '1H', observedAt);
    final btcFourHourFuture = normalizedAsset == 'BTC'
        ? assetFourHourFuture
        : _safeCandles(btcInstrument, '4H', observedAt);
    final fundingFuture = _safeFunding(derivativeInstrument);
    final oiFuture = _safeOpenInterest(derivativeInstrument);
    final values = await Future.wait<dynamic>([
      assetOneHourFuture,
      assetFourHourFuture,
      btcOneHourFuture,
      btcFourHourFuture,
      fundingFuture,
      oiFuture,
    ]);
    return MarketRiskSnapshot(
      asset: normalizedAsset,
      assetOneHour: values[0] as MarketCandleSeries,
      assetFourHour: values[1] as MarketCandleSeries,
      btcOneHour: values[2] as MarketCandleSeries,
      btcFourHour: values[3] as MarketCandleSeries,
      funding:
          (values[4] as MarketSourceResult<MarketFundingObservation>).value,
      openInterest:
          (values[5] as MarketSourceResult<List<MarketOpenInterestSample>>)
              .value ??
          const <MarketOpenInterestSample>[],
      fundingQuality:
          (values[4] as MarketSourceResult<MarketFundingObservation>).quality,
      openInterestQuality:
          (values[5] as MarketSourceResult<List<MarketOpenInterestSample>>)
              .quality,
      observedAt: observedAt,
    );
  }

  Future<MarketRiskSnapshot> getMarketSnapshot({
    required String asset,
    DateTime? now,
  }) => load(asset: asset, now: now);

  Future<MarketRiskSnapshot> fetch({required String asset, DateTime? now}) =>
      load(asset: asset, now: now);

  Future<MarketCandleSeries> _safeCandles(
    String instrument,
    String interval,
    DateTime observedAt,
  ) async {
    try {
      return await getCandles(instId: instrument, interval: interval);
    } on Object {
      return MarketCandleSeries.unavailable(
        instrument: instrument,
        interval: interval,
        endpoint: candlesEndpoint,
        reason: 'Unable to load $instrument $interval candles',
        observedAt: observedAt,
      );
    }
  }

  Future<MarketSourceResult<MarketFundingObservation>> _safeFunding(
    String instrument,
  ) async {
    try {
      return await getFundingResult(instId: instrument);
    } on Object {
      return MarketSourceResult<MarketFundingObservation>(
        quality: RiskQuality.error(
          source: '$venue $fundingEndpoint',
          reason: 'Public funding request failed',
          observedAt: clock().toUtc(),
        ),
      );
    }
  }

  Future<MarketSourceResult<List<MarketOpenInterestSample>>> _safeOpenInterest(
    String instrument,
  ) async {
    try {
      return await getOpenInterestResult(instId: instrument);
    } on Object {
      return MarketSourceResult<List<MarketOpenInterestSample>>(
        quality: RiskQuality.error(
          source: '$venue $openInterestEndpoint',
          reason: 'Public open-interest request failed',
          observedAt: clock().toUtc(),
        ),
      );
    }
  }

  Future<Response<dynamic>> _get(
    String endpoint, {
    required Map<String, dynamic> queryParameters,
  }) async {
    try {
      return await _dio.get<dynamic>(
        endpoint,
        queryParameters: queryParameters,
        options: Options(extra: <String, dynamic>{'requiresAuth': false}),
      );
    } on DioException catch (error) {
      throw RiskMarketRepositoryException(
        'Public market request failed',
        statusCode: error.response?.statusCode,
        endpoint: endpoint,
        cause: error,
      );
    } on Object catch (error) {
      throw RiskMarketRepositoryException(
        'Public market request failed',
        endpoint: endpoint,
        cause: error,
      );
    }
  }

  RiskQuality _exceptionQuality(
    RiskMarketRepositoryException error,
    String instrument,
    DateTime observedAt,
  ) {
    final endpoint = error.endpoint ?? 'public market endpoint';
    final status = error.payloadError
        ? RiskQualityStatus.partial
        : RiskQualityStatus.error;
    final statusSuffix = error.statusCode == null
        ? ''
        : ' (HTTP ${error.statusCode})';
    return RiskQuality(
      status: status,
      source: '$venue $endpoint [$instrument]',
      reason: '${error.message}$statusSuffix',
      observedAt: observedAt,
    );
  }

  List<Map<String, dynamic>> _dataList(
    Response<dynamic> response,
    String endpoint,
  ) {
    final items = _dataItems(response, endpoint);
    if (items.any((item) => item is! Map)) {
      throw RiskMarketRepositoryException(
        'OKX response data row was not an object',
        endpoint: endpoint,
        payloadError: true,
      );
    }
    return items
        .map((item) {
          final row = item as Map;
          return row.map<String, dynamic>(
            (key, value) => MapEntry(key.toString(), value),
          );
        })
        .toList(growable: false);
  }

  List<Object?> _dataItems(Response<dynamic> response, String endpoint) {
    final body = response.data;
    if (body is! Map) {
      throw RiskMarketRepositoryException(
        'OKX response body was not an object',
        endpoint: endpoint,
        payloadError: true,
      );
    }
    final code = parseRiskText(body['code']);
    if (code != null && code != '0') {
      throw RiskMarketRepositoryException(
        'OKX returned error code $code',
        endpoint: endpoint,
      );
    }
    final data = body['data'];
    if (data is! List) {
      throw RiskMarketRepositoryException(
        'OKX response data was not a list',
        endpoint: endpoint,
        payloadError: true,
      );
    }
    return List<Object?>.from(data);
  }

  MarketCandle? _parseCandle(Object? raw, {required String interval}) {
    final row = raw is List
        ? <String, dynamic>{
            'ts': raw.isNotEmpty ? raw[0] : null,
            'o': raw.length > 1 ? raw[1] : null,
            'h': raw.length > 2 ? raw[2] : null,
            'l': raw.length > 3 ? raw[3] : null,
            'c': raw.length > 4 ? raw[4] : null,
            'vol': raw.length > 5 ? raw[5] : null,
            'confirm': raw.length > 8 ? raw[8] : null,
          }
        : raw is Map
        ? raw.map<String, dynamic>(
            (key, value) => MapEntry(key.toString(), value),
          )
        : const <String, dynamic>{};
    final timestamp = parseRiskEpoch(row['ts'] ?? row['timestamp']);
    final open = parseRiskNumber(row['o'] ?? row['open']);
    final high = parseRiskNumber(row['h'] ?? row['high']);
    final low = parseRiskNumber(row['l'] ?? row['low']);
    final close = parseRiskNumber(row['c'] ?? row['close']);
    final volume = parseRiskNumber(row['vol'] ?? row['volume']);
    final confirmed = parseRiskText(row['confirm']) == '1';
    if (timestamp == null ||
        open == null ||
        high == null ||
        low == null ||
        close == null ||
        volume == null ||
        !confirmed) {
      return null;
    }
    final candle = MarketCandle(
      timestamp: timestamp,
      open: open,
      high: high,
      low: low,
      close: close,
      volume: volume,
      interval: interval,
      confirmed: true,
    );
    return candle.isValid ? candle : null;
  }

  void _requireInterval(String interval) {
    if (interval != '1H' && interval != '4H') {
      throw ArgumentError.value(interval, 'interval', 'must be 1H or 4H');
    }
  }

  bool _hasGap(List<MarketCandle> candles, String interval) {
    final duration = interval == '1H'
        ? const Duration(hours: 1)
        : const Duration(hours: 4);
    for (var index = 1; index < candles.length; index++) {
      if (candles[index].timestamp.difference(candles[index - 1].timestamp) !=
          duration) {
        return true;
      }
    }
    return false;
  }

  int _safeLimit(int value, {required int maximum}) {
    if (value < 1) return 1;
    if (value > maximum) return maximum;
    return value;
  }
}
