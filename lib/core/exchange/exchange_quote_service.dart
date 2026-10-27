import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/binance_data_client.dart';
import '../network/binance_request_coordinator.dart';
import '../network/okx_data_client.dart';
import 'exchange_models.dart';

final exchangeQuoteServiceProvider = Provider<ExchangeQuoteService>((ref) {
  final service = ExchangeQuoteService(
    binanceClient: ref.watch(binanceDataClientProvider),
    okxClient: ref.watch(okxDataClientProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

typedef ExchangeQuoteClock = DateTime Function();

class ExchangeQuoteService {
  ExchangeQuoteService({
    required BinanceDataClient binanceClient,
    required OkxDataClient okxClient,
    ExchangeQuoteClock? clock,
    this.freshness = const Duration(seconds: 15),
  }) : _binanceClient = binanceClient,
       _okxClient = okxClient,
       _clock = clock ?? DateTime.now {
    if (freshness <= Duration.zero) {
      throw ArgumentError.value(freshness, 'freshness', 'must be positive');
    }
  }

  static const int maxSpotSymbolsPerRequest = 20;

  final BinanceDataClient _binanceClient;
  final OkxDataClient _okxClient;
  final ExchangeQuoteClock _clock;
  final Duration freshness;
  final Map<ExchangeQuoteKey, ExchangeQuote> _cache =
      <ExchangeQuoteKey, ExchangeQuote>{};
  final Map<ExchangeQuoteKey, _PendingQuote> _inFlight =
      <ExchangeQuoteKey, _PendingQuote>{};
  final Set<_QuoteBatch> _batches = <_QuoteBatch>{};
  bool _disposed = false;

  ExchangeQuoteOwner createOwner() {
    _assertActive();
    return ExchangeQuoteOwner._(this);
  }

  Future<ExchangeQuoteSnapshot> loadQuotes({
    required ExchangeQuoteOwner owner,
    required Iterable<ExchangeInstrument> instruments,
  }) async {
    _assertActive();
    if (!owner.isActive || !identical(owner._service, this)) {
      throw const ExchangeQuoteCancelledException();
    }
    final requested = <ExchangeQuoteKey, ExchangeInstrument>{};
    for (final instrument in instruments) {
      final key = ExchangeQuoteKey(
        source: instrument.source,
        product: instrument.product,
        instrument: instrument.symbol,
      );
      requested.putIfAbsent(key, () => instrument);
    }
    final values = <ExchangeQuoteKey, ExchangeValue<ExchangeQuote>>{};
    final pending = <ExchangeQuoteKey, _PendingQuote>{};
    final needsFetch = <ExchangeInstrument>[];
    final now = _clock().toUtc();
    for (final entry in requested.entries) {
      if (entry.value.product == null) {
        values[entry.key] = const ExchangeValue<ExchangeQuote>.unavailable(
          'Instrument product metadata is unavailable.',
        );
        continue;
      }
      final cached = _cache[entry.key];
      if (cached != null && _isFresh(cached, now)) {
        values[entry.key] = ExchangeValue<ExchangeQuote>.available(cached);
        continue;
      }
      final existing = _inFlight[entry.key];
      if (existing != null) {
        _addOwner(existing, owner);
        pending[entry.key] = existing;
      } else {
        needsFetch.add(entry.value);
      }
    }
    for (final batch in _makeBatches(needsFetch)) {
      _startBatch(batch, owner);
      for (final instrument in batch) {
        final key = _key(instrument);
        final item = _inFlight[key];
        if (item != null) pending[key] = item;
      }
    }
    if (pending.isNotEmpty) {
      final entries = await Future.wait(
        pending.entries.map(
          (entry) async =>
              MapEntry(entry.key, await entry.value.completer.future),
        ),
      );
      if (!owner.isActive) throw const ExchangeQuoteCancelledException();
      values.addEntries(entries);
    }
    if (!owner.isActive) throw const ExchangeQuoteCancelledException();

    // A cache entry can be fresh when this call starts but expire while a
    // slower quote in the same valuation set is loading. Refresh those entries
    // once before publishing so the snapshot never contains an expired price.
    final refresh = <ExchangeQuoteKey, _PendingQuote>{};
    final refreshInstruments = <ExchangeInstrument>[];
    final refreshAt = _clock().toUtc();
    for (final entry in requested.entries) {
      final quote = values[entry.key]?.value;
      if (quote == null || _isFresh(quote, refreshAt)) continue;
      final existing = _inFlight[entry.key];
      if (existing != null) {
        _addOwner(existing, owner);
        refresh[entry.key] = existing;
      } else {
        refreshInstruments.add(entry.value);
      }
    }
    for (final batch in _makeBatches(refreshInstruments)) {
      _startBatch(batch, owner);
      for (final instrument in batch) {
        final key = _key(instrument);
        final item = _inFlight[key];
        if (item != null) refresh[key] = item;
      }
    }
    if (refresh.isNotEmpty) {
      final entries = await Future.wait(
        refresh.entries.map(
          (entry) async =>
              MapEntry(entry.key, await entry.value.completer.future),
        ),
      );
      if (!owner.isActive) throw const ExchangeQuoteCancelledException();
      values.addEntries(entries);
    }
    if (!owner.isActive) throw const ExchangeQuoteCancelledException();

    final publishedAt = _clock().toUtc();
    for (final entry in values.entries.toList()) {
      final quote = entry.value.value;
      if (quote != null && !_isFresh(quote, publishedAt)) {
        values[entry.key] = const ExchangeValue<ExchangeQuote>.unavailable(
          'The source quote expired before the valuation snapshot was ready.',
        );
      }
    }
    return ExchangeQuoteSnapshot(values: values, observedAt: publishedAt);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final batch in _batches.toList()) {
      batch.cancelToken.cancel('Quote service disposed.');
      _completeBatchUnavailable(batch, 'Quote service disposed.');
    }
    _cache.clear();
    _inFlight.clear();
    _batches.clear();
  }

  void _releaseOwner(ExchangeQuoteOwner owner) {
    if (!owner._active) return;
    owner._active = false;
    for (final pending in owner._pending.toList()) {
      pending.owners.remove(owner);
      if (pending.batch.hasActiveOwners) continue;
      pending.batch.cancelToken.cancel('Quote ownership became inactive.');
      _completeBatchUnavailable(
        pending.batch,
        'Quote ownership became inactive.',
      );
    }
    owner._pending.clear();
  }

  void _startBatch(
    List<ExchangeInstrument> instruments,
    ExchangeQuoteOwner owner,
  ) {
    final batch = _QuoteBatch(instruments);
    _batches.add(batch);
    for (final instrument in instruments) {
      final pending = _PendingQuote(batch);
      _inFlight[_key(instrument)] = pending;
      _addOwner(pending, owner);
    }
    unawaited(_fetchBatch(batch));
  }

  void _addOwner(_PendingQuote pending, ExchangeQuoteOwner owner) {
    pending.owners.add(owner);
    pending.batch.owners.add(owner);
    owner._pending.add(pending);
  }

  Future<void> _fetchBatch(_QuoteBatch batch) async {
    try {
      final rows = await _readBatch(batch);
      if (_disposed || batch.cancelToken.isCancelled) {
        _completeBatchUnavailable(batch, 'Quote request was cancelled.');
        return;
      }
      final bySymbol = <String, Map<String, dynamic>>{};
      for (final row in rows) {
        final symbol = _string(row['symbol'] ?? row['instId']);
        if (symbol != null) bySymbol[symbol] = row;
      }
      final observedAt = _clock().toUtc();
      for (final instrument in batch.instruments) {
        final key = _key(instrument);
        final pending = _inFlight[key];
        if (pending == null || !identical(pending.batch, batch)) continue;
        final row = bySymbol[instrument.symbol];
        final quote = row == null
            ? null
            : _toQuote(instrument, row, observedAt);
        if (quote == null) {
          _completePending(
            key,
            pending,
            const ExchangeValue.unavailable(
              'This exchange did not return a positive finite valuation quote.',
            ),
          );
        } else {
          _cache[key] = quote;
          _completePending(
            key,
            pending,
            ExchangeValue<ExchangeQuote>.available(quote),
          );
        }
      }
    } catch (_) {
      _completeBatchUnavailable(
        batch,
        batch.cancelToken.isCancelled
            ? 'Quote request was cancelled.'
            : 'A source-specific valuation quote is unavailable.',
      );
    } finally {
      _batches.remove(batch);
    }
  }

  Future<List<Map<String, dynamic>>> _readBatch(_QuoteBatch batch) async {
    final first = batch.instruments.first;
    final product = first.product;
    if (product == null) {
      throw StateError('Instrument product metadata is unavailable.');
    }
    if (first.source == ExchangeSource.binance) {
      if (product == ExchangeProduct.spot) {
        final response = await _binanceClient.get(
          '/api/v3/ticker/24hr',
          queryParameters: <String, dynamic>{
            'symbols': batch.instruments.map((item) => item.symbol).toList(),
          },
          cancelToken: batch.cancelToken,
          priority: BinanceRequestPriority.interactive,
        );
        return _maps(response.data);
      }
      if (product == ExchangeProduct.swap ||
          product == ExchangeProduct.futures) {
        final response = await _binanceClient.get(
          '/fapi/v1/ticker/24hr',
          cancelToken: batch.cancelToken,
          priority: BinanceRequestPriority.interactive,
        );
        return _maps(response.data);
      }
      return const <Map<String, dynamic>>[];
    }
    final instType = switch (product) {
      ExchangeProduct.spot || ExchangeProduct.margin => 'SPOT',
      ExchangeProduct.swap => 'SWAP',
      ExchangeProduct.futures => 'FUTURES',
    };
    final response = await _okxClient.get(
      '/api/v5/market/tickers',
      queryParameters: <String, dynamic>{'instType': instType},
      cancelToken: batch.cancelToken,
    );
    final body = _map(response.data);
    if (body?['code']?.toString() != '0') return const [];
    return _maps(body?['data']);
  }

  List<List<ExchangeInstrument>> _makeBatches(
    Iterable<ExchangeInstrument> instruments,
  ) {
    final groups = <String, List<ExchangeInstrument>>{};
    for (final instrument in instruments) {
      final isBinanceFutures =
          instrument.source == ExchangeSource.binance &&
          (instrument.product == ExchangeProduct.swap ||
              instrument.product == ExchangeProduct.futures);
      final groupKey = isBinanceFutures
          ? 'binance|futures'
          : instrument.source.name +
                '|' +
                (instrument.product?.name ?? 'unknown');
      groups
          .putIfAbsent(groupKey, () => <ExchangeInstrument>[])
          .add(instrument);
    }
    final batches = <List<ExchangeInstrument>>[];
    for (final group in groups.values) {
      group.sort((left, right) => left.symbol.compareTo(right.symbol));
      final isBinanceSpot =
          group.first.source == ExchangeSource.binance &&
          group.first.product == ExchangeProduct.spot;
      if (!isBinanceSpot) {
        batches.add(List<ExchangeInstrument>.unmodifiable(group));
        continue;
      }
      for (
        var start = 0;
        start < group.length;
        start += maxSpotSymbolsPerRequest
      ) {
        final next = start + maxSpotSymbolsPerRequest;
        final end = next < group.length ? next : group.length;
        batches.add(
          List<ExchangeInstrument>.unmodifiable(group.sublist(start, end)),
        );
      }
    }
    return batches;
  }

  ExchangeQuote? _toQuote(
    ExchangeInstrument instrument,
    Map<String, dynamic> row,
    DateTime observedAt,
  ) {
    final price = ExchangeAmount.tryParse(row['lastPrice'] ?? row['last']);
    final quoteCurrency =
        instrument.quoteAsset.value ?? instrument.settlementAsset.value;
    if (price == null ||
        !price.isPositive ||
        price.finiteDouble == null ||
        quoteCurrency == null) {
      return null;
    }
    final quote = ExchangeQuote(
      key: _key(instrument),
      price: price,
      quoteCurrency: quoteCurrency,
      observedAt: observedAt,
    );
    return quote.isPositiveFinite ? quote : null;
  }

  bool _isFresh(ExchangeQuote quote, DateTime now) {
    final age = now.difference(quote.observedAt);
    return !age.isNegative && age < freshness;
  }

  void _completeBatchUnavailable(_QuoteBatch batch, String reason) {
    for (final instrument in batch.instruments) {
      final key = _key(instrument);
      final pending = _inFlight[key];
      if (pending == null || !identical(pending.batch, batch)) continue;
      _completePending(
        key,
        pending,
        ExchangeValue<ExchangeQuote>.unavailable(reason),
      );
    }
  }

  void _completePending(
    ExchangeQuoteKey key,
    _PendingQuote pending,
    ExchangeValue<ExchangeQuote> value,
  ) {
    if (identical(_inFlight[key], pending)) _inFlight.remove(key);
    for (final owner in pending.owners) {
      owner._pending.remove(pending);
    }
    pending.owners.clear();
    if (!pending.completer.isCompleted) pending.completer.complete(value);
  }

  void _assertActive() {
    if (_disposed) throw const ExchangeQuoteCancelledException();
  }

  static ExchangeQuoteKey _key(ExchangeInstrument instrument) =>
      ExchangeQuoteKey(
        source: instrument.source,
        product: instrument.product,
        instrument: instrument.symbol,
      );

  static List<Map<String, dynamic>> _maps(Object? value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .map(_map)
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }

  static Map<String, dynamic>? _map(Object? value) {
    if (value is! Map) return null;
    return value.map<String, dynamic>(
      (key, item) => MapEntry(key.toString(), item),
    );
  }

  static String? _string(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
}

class ExchangeQuoteOwner {
  ExchangeQuoteOwner._(this._service);

  final ExchangeQuoteService _service;
  final Set<_PendingQuote> _pending = <_PendingQuote>{};
  bool _active = true;

  bool get isActive => _active;

  void dispose() => _service._releaseOwner(this);
}

class ExchangeQuoteCancelledException implements Exception {
  const ExchangeQuoteCancelledException();

  @override
  String toString() => 'Exchange quote ownership is inactive.';
}

class _QuoteBatch {
  _QuoteBatch(this.instruments);

  final List<ExchangeInstrument> instruments;
  final CancelToken cancelToken = CancelToken();
  final Set<ExchangeQuoteOwner> owners = <ExchangeQuoteOwner>{};

  bool get hasActiveOwners => owners.any((owner) => owner.isActive);
}

class _PendingQuote {
  _PendingQuote(this.batch);

  final _QuoteBatch batch;
  final Set<ExchangeQuoteOwner> owners = <ExchangeQuoteOwner>{};
  final Completer<ExchangeValue<ExchangeQuote>> completer =
      Completer<ExchangeValue<ExchangeQuote>>();
}
