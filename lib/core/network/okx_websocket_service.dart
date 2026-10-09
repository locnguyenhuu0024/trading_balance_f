import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/orders/presentation/providers/trade_session_provider.dart';
import '../../features/portfolio/data/risk/risk_request_coordinator.dart';
import 'backend_data_client.dart';

/// A cancellable owner of a set of public ticker subscriptions.
class TickerPollingSubscription {
  TickerPollingSubscription._(this._cancel);

  final Future<void> Function() _cancel;
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  Future<void> cancel() async {
    if (_isCancelled) return;
    _isCancelled = true;
    await _cancel();
  }
}

/// Polls the backend market quote route for the union of active consumers.
/// The historical class name remains for compatibility; this service opens no
/// exchange socket and sends no exchange credentials.
class OkxWebsocketService {
  OkxWebsocketService({
    BackendDataClient? client,
    RiskRequestCoordinator? requestCoordinator,
    Duration pollInterval = const Duration(seconds: 1),
    Duration maximumQuoteAge = OkxWebsocketService.maximumQuoteAge,
    DateTime Function()? clock,
  }) : _client = client,
       _requestCoordinator = requestCoordinator ?? RiskRequestCoordinator(),
       _pollInterval = pollInterval,
       _maximumQuoteAge = maximumQuoteAge,
       _clock = clock ?? DateTime.now {
    if (pollInterval <= Duration.zero) {
      throw ArgumentError.value(
        pollInterval,
        'pollInterval',
        'must be positive',
      );
    }
    if (maximumQuoteAge <= Duration.zero ||
        maximumQuoteAge > OkxWebsocketService.maximumQuoteAge) {
      throw ArgumentError.value(
        maximumQuoteAge,
        'maximumQuoteAge',
        'must be positive and no greater than 15 seconds',
      );
    }
  }

  static const Duration maximumQuoteAge = Duration(seconds: 15);

  final BackendDataClient? _client;
  final RiskRequestCoordinator _requestCoordinator;
  final Duration _pollInterval;
  final Duration _maximumQuoteAge;
  final DateTime Function() _clock;
  final StreamController<dynamic> _stream = StreamController<dynamic>.broadcast(
    sync: true,
  );
  final LinkedHashMap<int, LinkedHashSet<String>> _subscriptions =
      LinkedHashMap<int, LinkedHashSet<String>>();
  final Map<String, String> _latestPrices = <String, String>{};
  final Map<String, DateTime> _quoteTimestamps = <String, DateTime>{};

  Timer? _timer;
  Timer? _expiryTimer;
  CancelToken? _activeCancelToken;
  int _nextSubscriptionId = 0;
  int _generation = 0;
  int _backoffAttempt = 0;
  bool _pollInFlight = false;
  bool _disposed = false;
  DateTime? _retryAt;

  Stream<dynamic> get stream => _stream.stream;

  /// Retained as a harmless compatibility method. Polling starts only when a
  /// consumer calls [subscribe].
  void connect() {}

  /// Subscribe to canonical SPOT `*-USDT` tickers. Identical IDs are
  /// de-duplicated within each owner while preserving the input order.
  TickerPollingSubscription subscribe(List<String> coinSymbols) {
    if (_disposed) {
      throw StateError('Ticker polling service has been disposed.');
    }
    final id = ++_nextSubscriptionId;
    final previousIds = _activeInstrumentIds;
    _subscriptions[id] = LinkedHashSet<String>.of(
      coinSymbols.map(_canonicalInstrumentId).whereType<String>(),
    );
    if (!_sameIds(previousIds, _activeInstrumentIds)) _refreshSchedule();
    return TickerPollingSubscription._(() async {
      final previousIds = _activeInstrumentIds;
      _subscriptions.remove(id);
      if (!_sameIds(previousIds, _activeInstrumentIds)) _refreshSchedule();
    });
  }

  /// Legacy entry point; new consumers should retain the handle from
  /// [subscribe] so they can stop their own polling interest.
  void subscribeToTickers(List<String> coinSymbols) {
    clearLegacySubscription();
    _legacySubscription = subscribe(coinSymbols);
  }

  TickerPollingSubscription? _legacySubscription;

  void clearLegacySubscription() {
    final subscription = _legacySubscription;
    _legacySubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
  }

  void _refreshSchedule() {
    final ids = _activeInstrumentIds;
    _generation++;
    _timer?.cancel();
    _timer = null;
    _activeCancelToken?.cancel('Ticker subscription changed');
    _activeCancelToken = null;
    _retryAt = null;
    _backoffAttempt = 0;
    final active = ids.toSet();
    _latestPrices.removeWhere(
      (instrumentId, _) => !active.contains(instrumentId),
    );
    _quoteTimestamps.removeWhere(
      (instrumentId, _) => !active.contains(instrumentId),
    );
    _scheduleExpiry();
    _emitSnapshot();
    if (ids.isEmpty || _disposed) return;

    final generation = _generation;
    Timer.run(() => unawaited(_poll(generation)));
    _timer = Timer.periodic(_pollInterval, (_) {
      unawaited(_poll(generation));
    });
  }

  List<String> get _activeInstrumentIds {
    final ids = LinkedHashSet<String>();
    for (final ownerIds in _subscriptions.values) {
      ids.addAll(ownerIds);
    }
    return ids.toList(growable: false);
  }

  Future<void> _poll(int generation) async {
    if (_disposed ||
        generation != _generation ||
        _pollInFlight ||
        _activeInstrumentIds.isEmpty) {
      return;
    }
    final retryAt = _retryAt;
    if (retryAt != null && _clock().isBefore(retryAt)) return;

    _pollInFlight = true;
    final instrumentIds = _activeInstrumentIds;
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;
    final nextPrices = Map<String, String>.of(_latestPrices)
      ..removeWhere((id, _) => instrumentIds.contains(id));
    final nextTimestamps = Map<String, DateTime>.of(_quoteTimestamps)
      ..removeWhere((id, _) => instrumentIds.contains(id));
    var hadFailure = false;
    try {
      final client = _client;
      if (client == null) {
        hadFailure = true;
      } else {
        for (var offset = 0; offset < instrumentIds.length; offset += 100) {
          if (generation != _generation ||
              _disposed ||
              _activeInstrumentIds.isEmpty) {
            return;
          }
          final batch = instrumentIds.skip(offset).take(100).toList();
          try {
            final response = await _requestCoordinator.run<Response<dynamic>>(
              lane: RiskRequestLane.public,
              key: '/v1/data/market/quotes?instIds=${batch.join(',')}',
              request: () => client.get(
                '/api/v5/market/quotes',
                queryParameters: {'instIds': batch.join(',')},
                cancelToken: cancelToken,
              ),
            );
            if (generation != _generation || _disposed) return;
            for (final row in _tickerRows(response.data)) {
              final instrumentId = _canonicalInstrumentId(row['instId']);
              if (instrumentId == null || !batch.contains(instrumentId)) {
                continue;
              }
              final quoteTimestamp = _validQuoteTimestamp(
                row['ts'],
                now: _clock().toUtc(),
                maxAge: _maximumQuoteAge,
              );
              final last = _positiveFiniteNumber(row['last']);
              if (quoteTimestamp != null && last != null) {
                nextPrices[instrumentId] = last;
                nextTimestamps[instrumentId] = quoteTimestamp;
              }
            }
          } on Object {
            if (generation != _generation || _disposed) return;
            hadFailure = true;
          }
        }
      }
      if (generation != _generation || _disposed) return;
      _latestPrices
        ..clear()
        ..addAll(nextPrices);
      _quoteTimestamps
        ..clear()
        ..addAll(nextTimestamps);
      _expireQuotes();
      _emitSnapshot();
      if (hadFailure) {
        _backoffAttempt++;
        final seconds = 1 << (_backoffAttempt - 1).clamp(0, 5).toInt();
        _retryAt = _clock().add(Duration(seconds: seconds));
      } else {
        _backoffAttempt = 0;
        _retryAt = null;
      }
    } finally {
      if (identical(_activeCancelToken, cancelToken)) _activeCancelToken = null;
      _pollInFlight = false;
    }
  }

  List<Map<String, dynamic>> _tickerRows(dynamic envelope) {
    if (envelope is! Map || envelope['code']?.toString() != '0') {
      throw const FormatException('Backend quote response was invalid.');
    }
    final data = envelope['data'];
    if (data is! List) {
      throw const FormatException('Backend quote rows were invalid.');
    }
    return data
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  void _emitSnapshot() {
    if (_disposed || _stream.isClosed) return;
    final snapshot = <String, String>{};
    for (final entry in _latestPrices.entries) {
      snapshot[entry.key.substring(0, entry.key.length - '-USDT'.length)] =
          entry.value;
    }
    _stream.add(Map<String, String>.unmodifiable(snapshot));
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    if (_disposed || _quoteTimestamps.isEmpty) return;
    final nextExpiry = _quoteTimestamps.values
        .map((timestamp) => timestamp.add(_maximumQuoteAge))
        .reduce((left, right) => left.isBefore(right) ? left : right);
    final delay = nextExpiry.difference(_clock().toUtc());
    _expiryTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      _expireQuotes,
    );
  }

  void _expireQuotes() {
    if (_disposed) return;
    final now = _clock().toUtc();
    final expired = _quoteTimestamps.entries
        .where((entry) => now.difference(entry.value) >= _maximumQuoteAge)
        .map((entry) => entry.key)
        .toList();
    for (final instrumentId in expired) {
      _quoteTimestamps.remove(instrumentId);
      _latestPrices.remove(instrumentId);
    }
    if (expired.isNotEmpty) _emitSnapshot();
    _scheduleExpiry();
  }

  bool _sameIds(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  static String? _canonicalInstrumentId(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim().toUpperCase();
    final instrumentId = normalized.contains('-')
        ? normalized
        : '$normalized-USDT';
    if (!RegExp(r'^[A-Z0-9]{1,20}-USDT$').hasMatch(instrumentId)) return null;
    return instrumentId;
  }

  static String? _positiveFiniteNumber(Object? value) {
    if (value is! String && value is! num) return null;
    final parsed = double.tryParse(value.toString());
    if (parsed == null || !parsed.isFinite || parsed <= 0) return null;
    return value.toString();
  }

  static DateTime? _validQuoteTimestamp(
    Object? raw, {
    required DateTime now,
    required Duration maxAge,
  }) {
    if (raw is! String && raw is! num) return null;
    final milliseconds = int.tryParse(raw.toString());
    if (milliseconds == null || milliseconds <= 0) return null;
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      milliseconds,
      isUtc: true,
    );
    final age = now.difference(timestamp);
    if (age.isNegative || age > maxAge) return null;
    return timestamp;
  }

  void disconnect() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _timer = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _activeCancelToken?.cancel('Ticker polling service disposed');
    _activeCancelToken = null;
    _subscriptions.clear();
    _legacySubscription = null;
    _latestPrices.clear();
    _quoteTimestamps.clear();
    _stream.close();
  }
}

final okxWebsocketProvider = Provider.autoDispose<OkxWebsocketService>((ref) {
  final service = OkxWebsocketService(
    client: ref.watch(backendDataClientProvider),
    requestCoordinator: ref.watch(riskRequestCoordinatorProvider),
  );
  ref.onDispose(service.disconnect);
  return service;
});
