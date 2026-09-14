import 'dart:async';

import 'package:dio/dio.dart';

import '../../domain/risk/market_risk_engine.dart';
import '../../domain/risk/risk_models.dart';
import 'okx_risk_dto.dart';
import 'risk_request_coordinator.dart';

typedef RiskMarketRepositoryClock = DateTime Function();

/// Public market data errors remain typed so callers can expose an unavailable
/// source without treating a failed request as neutral market evidence.
class RiskMarketRepositoryException implements Exception {
  const RiskMarketRepositoryException(
    this.message, {
    this.statusCode,
    this.retryAfter,
    this.endpoint,
    this.cause,
    this.payloadError = false,
  });

  final String message;
  final int? statusCode;
  final Duration? retryAfter;
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
    RiskRequestCoordinator? requestCoordinator,
    this.venue = 'OKX',
    this.candleLimit = 120,
    this.marketCacheTtl = const Duration(minutes: 1),
  }) : clock = clock ?? DateTime.now,
       requestCoordinator =
           requestCoordinator ??
           RiskRequestCoordinator(clock: clock ?? DateTime.now);

  final Dio _dio;
  final RiskMarketRepositoryClock clock;
  final RiskRequestCoordinator requestCoordinator;
  final String venue;
  final int candleLimit;
  final Duration marketCacheTtl;

  final Map<String, _TimedMarketValue<MarketCandleSeries>> _candleCache =
      <String, _TimedMarketValue<MarketCandleSeries>>{};
  final Map<String, Future<MarketCandleSeries>> _candleRequests =
      <String, Future<MarketCandleSeries>>{};
  final Map<
    String,
    _TimedMarketValue<MarketSourceResult<MarketFundingObservation>>
  >
  _fundingCache =
      <
        String,
        _TimedMarketValue<MarketSourceResult<MarketFundingObservation>>
      >{};
  final Map<String, Future<MarketSourceResult<MarketFundingObservation>>>
  _fundingRequests =
      <String, Future<MarketSourceResult<MarketFundingObservation>>>{};
  final Map<
    String,
    _TimedMarketValue<MarketSourceResult<List<MarketOpenInterestSample>>>
  >
  _openInterestCache =
      <
        String,
        _TimedMarketValue<MarketSourceResult<List<MarketOpenInterestSample>>>
      >{};
  final Map<String, Future<MarketSourceResult<List<MarketOpenInterestSample>>>>
  _openInterestRequests =
      <String, Future<MarketSourceResult<List<MarketOpenInterestSample>>>>{};

  static const String candlesEndpoint = '/api/v5/market/candles';
  static const String fundingEndpoint = '/api/v5/public/funding-rate';
  static const String openInterestEndpoint = '/api/v5/public/open-interest';

  void clearCaches() {
    _candleCache.clear();
    _candleRequests.clear();
    _fundingCache.clear();
    _fundingRequests.clear();
    _openInterestCache.clear();
    _openInterestRequests.clear();
    requestCoordinator.clearLane(RiskRequestLane.public);
  }

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
    final safeLimit = _safeLimit(limit ?? candleLimit, maximum: 300);
    final key = _candleKey(instrument, normalizedInterval, safeLimit);
    final cached = _candleCache[key];
    if (cached != null && !_expired(cached.fetchedAt)) {
      return cached.value;
    }
    if (cached != null) {
      _startCandleRefresh(
        key,
        instrument: instrument,
        interval: normalizedInterval,
        limit: safeLimit,
      );
      return _staleCandle(cached.value);
    }
    final pending = _candleRequests[key];
    if (pending != null) return pending;
    final request = _fetchCandles(
      instrument: instrument,
      interval: normalizedInterval,
      limit: safeLimit,
    );
    _candleRequests[key] = request;
    _completeCandleRequest(key, request);
    return request;
  }

  Future<MarketCandleSeries> _fetchCandles({
    required String instrument,
    required String interval,
    required int limit,
  }) async {
    final observedAt = clock().toUtc();
    final response = await _get(
      candlesEndpoint,
      queryParameters: <String, dynamic>{
        'instId': instrument,
        'bar': interval,
        'limit': limit,
      },
    );
    final rows = _dataItems(response, candlesEndpoint);
    final parsed = <MarketCandle>[];
    var discarded = false;
    for (final row in rows) {
      final candle = _parseCandle(row, interval: interval);
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
    final gap = _hasGap(unique, interval);
    final complete = unique.isNotEmpty && !duplicate && !gap;
    final reason = complete
        ? null
        : duplicate
        ? 'Market $interval candles contain duplicate timestamps'
        : gap
        ? 'Market $interval candles contain a timestamp gap'
        : discarded
        ? 'No valid confirmed $interval candles were returned'
        : 'No confirmed $interval candles were returned';
    final sourceAt = unique.isEmpty ? null : unique.last.timestamp;
    return MarketCandleSeries(
      instrument: instrument,
      interval: interval,
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
    final cached = _fundingCache[instrument];
    if (cached != null && !_expired(cached.fetchedAt)) {
      return cached.value;
    }
    if (cached != null) {
      _startFundingRefresh(instrument);
      return _staleFunding(cached.value);
    }
    final pending = _fundingRequests[instrument];
    if (pending != null) return pending;
    final request = _fetchFundingResult(instrument);
    _fundingRequests[instrument] = request;
    _completeFundingRequest(instrument, request);
    return request;
  }

  Future<MarketSourceResult<MarketFundingObservation>> _fetchFundingResult(
    String instrument,
  ) async {
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
    final cached = _openInterestCache[instrument];
    if (cached != null && !_expired(cached.fetchedAt)) {
      return cached.value;
    }
    if (cached != null) {
      _startOpenInterestRefresh(instrument);
      return _staleOpenInterest(cached.value);
    }
    final pending = _openInterestRequests[instrument];
    if (pending != null) return pending;
    final request = _fetchOpenInterestResult(instrument);
    _openInterestRequests[instrument] = request;
    _completeOpenInterestRequest(instrument, request);
    return request;
  }

  Future<MarketSourceResult<List<MarketOpenInterestSample>>>
  _fetchOpenInterestResult(String instrument) async {
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

    // Invoke each source only after the previous source has completed. The
    // coordinator still coalesces concurrent callers, while this owner keeps
    // one asset capture from enqueueing a per-position burst of work.
    final assetOneHour = await _safeCandles(assetInstrument, '1H', observedAt);
    final assetFourHour = await _safeCandles(assetInstrument, '4H', observedAt);
    final btcOneHour = normalizedAsset == 'BTC'
        ? assetOneHour
        : await _safeCandles(btcInstrument, '1H', observedAt);
    final btcFourHour = normalizedAsset == 'BTC'
        ? assetFourHour
        : await _safeCandles(btcInstrument, '4H', observedAt);
    final funding = await _safeFunding(derivativeInstrument);
    final openInterest = await _safeOpenInterest(derivativeInstrument);
    return MarketRiskSnapshot(
      asset: normalizedAsset,
      assetOneHour: assetOneHour,
      assetFourHour: assetFourHour,
      btcOneHour: btcOneHour,
      btcFourHour: btcFourHour,
      funding: funding.value,
      openInterest: openInterest.value ?? const <MarketOpenInterestSample>[],
      fundingQuality: funding.quality,
      openInterestQuality: openInterest.quality,
      observedAt: observedAt,
    );
  }

  /// Load several assets through one public repository batch. BTC candle keys
  /// are shared by the cache, so a due batch issues one BTC request per
  /// timeframe regardless of the number of assets.
  Future<List<MarketRiskSnapshot>> loadBatch({
    required Iterable<String> assets,
    DateTime? now,
  }) async {
    final uniqueAssets = <String>[];
    final seen = <String>{};
    for (final asset in assets) {
      final normalized = asset.trim().toUpperCase();
      if (normalized.isEmpty || !seen.add(normalized)) continue;
      uniqueAssets.add(normalized);
    }
    final snapshots = <MarketRiskSnapshot>[];
    for (final asset in uniqueAssets) {
      snapshots.add(await load(asset: asset, now: now));
    }
    return List.unmodifiable(snapshots);
  }

  Future<List<MarketRiskSnapshot>> getMarketSnapshots({
    required Iterable<String> assets,
    DateTime? now,
  }) => loadBatch(assets: assets, now: now);

  String _candleKey(String instrument, String interval, int limit) =>
      '$instrument|$interval|$limit';

  bool _expired(DateTime fetchedAt) {
    final age = clock().difference(fetchedAt);
    return !age.isNegative && age >= marketCacheTtl;
  }

  void _completeCandleRequest(String key, Future<MarketCandleSeries> request) {
    request.then<void>(
      (value) {
        _candleCache[key] = _TimedMarketValue(value, clock());
        if (identical(_candleRequests[key], request)) {
          _candleRequests.remove(key);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_candleRequests[key], request)) {
          _candleRequests.remove(key);
        }
      },
    );
  }

  void _startCandleRefresh(
    String key, {
    required String instrument,
    required String interval,
    required int limit,
  }) {
    if (_candleRequests.containsKey(key)) return;
    final request = _fetchCandles(
      instrument: instrument,
      interval: interval,
      limit: limit,
    );
    _candleRequests[key] = request;
    _completeCandleRequest(key, request);
  }

  MarketCandleSeries _staleCandle(MarketCandleSeries value) {
    final quality = value.source.quality.withStatus(
      RiskQualityStatus.stale,
      nextReason: 'Cached market data is stale; refreshing',
    );
    return MarketCandleSeries(
      instrument: value.instrument,
      interval: value.interval,
      candles: value.candles,
      source: MarketSourceInfo(
        venue: value.source.venue,
        instrument: value.source.instrument,
        endpoint: value.source.endpoint,
        observedAt: value.source.observedAt,
        sourceAt: value.source.sourceAt,
        windowStart: value.source.windowStart,
        windowEnd: value.source.windowEnd,
        quality: quality,
      ),
      complete: value.complete,
      missingReason: value.missingReason ?? quality.reason,
    );
  }

  void _completeFundingRequest(
    String key,
    Future<MarketSourceResult<MarketFundingObservation>> request,
  ) {
    request.then<void>(
      (value) {
        _fundingCache[key] = _TimedMarketValue(value, clock());
        if (identical(_fundingRequests[key], request)) {
          _fundingRequests.remove(key);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_fundingRequests[key], request)) {
          _fundingRequests.remove(key);
        }
      },
    );
  }

  void _startFundingRefresh(String instrument) {
    if (_fundingRequests.containsKey(instrument)) return;
    final request = _fetchFundingResult(instrument);
    _fundingRequests[instrument] = request;
    _completeFundingRequest(instrument, request);
  }

  MarketSourceResult<MarketFundingObservation> _staleFunding(
    MarketSourceResult<MarketFundingObservation> value,
  ) {
    final quality = value.quality.withStatus(
      RiskQualityStatus.stale,
      nextReason: 'Cached funding data is stale; refreshing',
    );
    final observation = value.value;
    if (observation == null) {
      return MarketSourceResult<MarketFundingObservation>(quality: quality);
    }
    return MarketSourceResult<MarketFundingObservation>(
      value: MarketFundingObservation(
        instrument: observation.instrument,
        rate: observation.rate,
        fundingTime: observation.fundingTime,
        nextFundingTime: observation.nextFundingTime,
        source: MarketSourceInfo(
          venue: observation.source.venue,
          instrument: observation.source.instrument,
          endpoint: observation.source.endpoint,
          observedAt: observation.source.observedAt,
          sourceAt: observation.source.sourceAt,
          windowStart: observation.source.windowStart,
          windowEnd: observation.source.windowEnd,
          quality: quality,
        ),
      ),
      quality: quality,
    );
  }

  void _completeOpenInterestRequest(
    String key,
    Future<MarketSourceResult<List<MarketOpenInterestSample>>> request,
  ) {
    request.then<void>(
      (value) {
        _openInterestCache[key] = _TimedMarketValue(value, clock());
        if (identical(_openInterestRequests[key], request)) {
          _openInterestRequests.remove(key);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_openInterestRequests[key], request)) {
          _openInterestRequests.remove(key);
        }
      },
    );
  }

  void _startOpenInterestRefresh(String instrument) {
    if (_openInterestRequests.containsKey(instrument)) return;
    final request = _fetchOpenInterestResult(instrument);
    _openInterestRequests[instrument] = request;
    _completeOpenInterestRequest(instrument, request);
  }

  MarketSourceResult<List<MarketOpenInterestSample>> _staleOpenInterest(
    MarketSourceResult<List<MarketOpenInterestSample>> value,
  ) {
    final quality = value.quality.withStatus(
      RiskQualityStatus.stale,
      nextReason: 'Cached open-interest data is stale; refreshing',
    );
    final samples = value.value;
    if (samples == null) {
      return MarketSourceResult<List<MarketOpenInterestSample>>(
        quality: quality,
      );
    }
    return MarketSourceResult<List<MarketOpenInterestSample>>(
      value: samples
          .map(
            (sample) => MarketOpenInterestSample(
              instrument: sample.instrument,
              timestamp: sample.timestamp,
              oiCcy: sample.oiCcy,
              source: MarketSourceInfo(
                venue: sample.source.venue,
                instrument: sample.source.instrument,
                endpoint: sample.source.endpoint,
                observedAt: sample.source.observedAt,
                sourceAt: sample.source.sourceAt,
                windowStart: sample.source.windowStart,
                windowEnd: sample.source.windowEnd,
                quality: quality,
              ),
            ),
          )
          .toList(growable: false),
      quality: quality,
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
      throw RiskMarketRepositoryException(
        'Public market request failed',
        statusCode: error.statusCode,
        retryAfter: error.retryAfter,
        endpoint: endpoint,
        cause: error,
      );
    } on DioException catch (error) {
      throw RiskMarketRepositoryException(
        'Public market request failed',
        statusCode: error.response?.statusCode,
        retryAfter: _retryAfter(error.response),
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

  String _requestKey(String endpoint, Map<String, dynamic> queryParameters) {
    final query = queryParameters.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return '$endpoint?${query.map((entry) => '${entry.key}=${entry.value}').join('&')}';
  }

  Duration? _retryAfter(Response<dynamic>? response) {
    final raw = response?.headers.value('retry-after')?.trim();
    if (raw == null || raw.isEmpty) return null;
    final seconds = int.tryParse(raw);
    if (seconds != null && seconds >= 0) return Duration(seconds: seconds);
    return null;
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

class _TimedMarketValue<T> {
  const _TimedMarketValue(this.value, this.fetchedAt);

  final T value;
  final DateTime fetchedAt;
}
