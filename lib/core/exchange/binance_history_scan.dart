import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/binance_request_coordinator.dart';
import '../security/secure_storage_helper.dart';
import 'binance_exchange_reader.dart';
import 'binance_read_routes.dart';
import 'exchange_models.dart';
import 'exchange_readers.dart';

final binanceHistoryScanProvider = Provider<BinanceHistoryScanService>((ref) {
  final service = BinanceHistoryScanService(
    reader: ref.watch(binanceExchangeReaderProvider),
    requestCoordinator: ref.watch(binanceRequestCoordinatorProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

enum BinanceHistoryScanState {
  idle,
  running,
  paused,
  complete,
  failed,
  cancelled,
}

class BinanceHistoryScanProgress {
  BinanceHistoryScanProgress({
    required this.product,
    required this.state,
    required this.initialized,
    required this.totalSymbols,
    required this.completedSymbols,
    required this.failedSymbols,
    required this.pendingSymbols,
    required Iterable<ExchangeOrder> rows,
    required Map<String, ExchangeReadException> failures,
    required Iterable<ExchangeReadIssue> catalogIssues,
    required this.retryAt,
    required this.message,
    required this.coverageNotice,
  }) : rows = List<ExchangeOrder>.unmodifiable(rows),
       failures = Map<String, ExchangeReadException>.unmodifiable(failures),
       catalogIssues = List<ExchangeReadIssue>.unmodifiable(catalogIssues);

  final ExchangeProduct product;
  final BinanceHistoryScanState state;
  final bool initialized;
  final int totalSymbols;
  final int completedSymbols;
  final int failedSymbols;
  final int pendingSymbols;
  final List<ExchangeOrder> rows;
  final Map<String, ExchangeReadException> failures;
  final List<ExchangeReadIssue> catalogIssues;
  final DateTime? retryAt;
  final String? message;
  final String coverageNotice;

  bool get allCapturedSymbolsComplete =>
      initialized &&
      completedSymbols == totalSymbols &&
      failedSymbols == 0 &&
      pendingSymbols == 0 &&
      catalogIssues.isEmpty;

  bool get hasAuthoritativeEmptyHistory =>
      allCapturedSymbolsComplete && rows.isEmpty;

  bool get hasPartialCoverage =>
      failedSymbols > 0 || pendingSymbols > 0 || catalogIssues.isNotEmpty;
}

class BinanceHistoryScanService {
  BinanceHistoryScanService({
    required BinanceExchangeReader reader,
    required BinanceRequestCoordinator requestCoordinator,
  }) : _reader = reader,
       _requestCoordinator = requestCoordinator;

  final BinanceExchangeReader _reader;
  final BinanceRequestCoordinator _requestCoordinator;
  final _BinanceHistoryRequestGate _requestGate = _BinanceHistoryRequestGate();
  final Map<String, BinanceHistoryScanSession> _active =
      <String, BinanceHistoryScanSession>{};
  bool _disposed = false;

  BinanceHistoryScanSession startSpotScan({
    Iterable<String> knownSymbols = const <String>[],
  }) => _start(product: ExchangeProduct.spot, knownSymbols: knownSymbols);

  BinanceHistoryScanSession startFuturesScan({
    Iterable<String> knownSymbols = const <String>[],
  }) => _start(product: ExchangeProduct.swap, knownSymbols: knownSymbols);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final session in _active.values.toList()) {
      session._supersede();
    }
    _active.clear();
  }

  BinanceHistoryScanSession _start({
    required ExchangeProduct product,
    required Iterable<String> knownSymbols,
  }) {
    if (_disposed) {
      throw const ExchangeReadException(
        code: 'binance_history_service_disposed',
        message: 'Binance history scanning is no longer active.',
      );
    }
    final key = product == ExchangeProduct.spot ? 'spot' : 'futures';
    _active.remove(key)?._supersede();
    final snapshot = _reader.credentialState.value;
    if (!snapshot.canUsePrivateReads) {
      throw const ExchangeReadException(
        code: 'binance_credentials_unavailable',
        message: 'Binance history requires usable local credentials.',
      );
    }
    late final BinanceHistoryScanSession session;
    session = BinanceHistoryScanSession._(
      product: product,
      reader: _reader,
      requestCoordinator: _requestCoordinator,
      requestGate: _requestGate,
      snapshot: snapshot,
      knownSymbols: knownSymbols,
      isCurrentSession: () => identical(_active[key], session),
    );
    _active[key] = session;
    return session;
  }
}

class BinanceHistoryScanSession {
  BinanceHistoryScanSession._({
    required this.product,
    required BinanceExchangeReader reader,
    required BinanceRequestCoordinator requestCoordinator,
    required _BinanceHistoryRequestGate requestGate,
    required BinanceCredentialSnapshot snapshot,
    required Iterable<String> knownSymbols,
    required bool Function() isCurrentSession,
  }) : _reader = reader,
       _requestCoordinator = requestCoordinator,
       _requestGate = requestGate,
       _snapshot = snapshot,
       _knownSymbols = Set<String>.of(knownSymbols),
       _isCurrentSession = isCurrentSession {
    _credentialListener = _onCredentialChanged;
    reader.credentialState.addListener(_credentialListener);
    _publish();
  }

  final ExchangeProduct product;
  final BinanceExchangeReader _reader;
  final BinanceRequestCoordinator _requestCoordinator;
  final _BinanceHistoryRequestGate _requestGate;
  final BinanceCredentialSnapshot _snapshot;
  final Set<String> _knownSymbols;
  final bool Function() _isCurrentSession;
  late final VoidCallback _credentialListener;
  final StreamController<BinanceHistoryScanProgress> _controller =
      StreamController<BinanceHistoryScanProgress>.broadcast();
  final Map<String, ExchangeInstrument> _instruments =
      <String, ExchangeInstrument>{};
  final Set<String> _pending = <String>{};
  final Set<String> _completed = <String>{};
  final Map<String, ExchangeReadException> _failures =
      <String, ExchangeReadException>{};
  final Set<String> _successfulPages = <String>{};
  final Map<String, ExchangeOrder> _rowsByIdentity = <String, ExchangeOrder>{};
  final List<ExchangeReadIssue> _catalogIssues = <ExchangeReadIssue>[];
  CancelToken _cancelToken = CancelToken();
  BinanceHistoryScanProgress? _current;
  Future<BinanceHistoryScanProgress>? _running;
  BinanceHistoryScanState _state = BinanceHistoryScanState.idle;
  String? _message;
  String? _pauseCode;
  DateTime? _retryAt;
  bool _initialized = false;
  bool _manualCancellation = false;
  bool _generationChanged = false;
  bool _superseded = false;
  bool _disposed = false;

  Stream<BinanceHistoryScanProgress> get progress => _controller.stream;

  BinanceHistoryScanProgress get current => _current ?? _buildProgress();

  Future<BinanceHistoryScanProgress> run() => _run(retryFailed: false);

  Future<BinanceHistoryScanProgress> resume({bool retryFailed = true}) =>
      _run(retryFailed: retryFailed);

  void cancel() {
    if (_disposed || _superseded || _generationChanged) return;
    _manualCancellation = true;
    _cancelToken.cancel('History scan cancelled by owner.');
    _state = BinanceHistoryScanState.cancelled;
    _message = 'History scan cancelled. Unfinished symbols can be resumed.';
    _publish();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelToken.cancel('History scan disposed.');
    _reader.credentialState.removeListener(_credentialListener);
    unawaited(_controller.close());
  }

  void _supersede() {
    if (_disposed || _superseded) return;
    _superseded = true;
    _cancelToken.cancel('A newer history scan replaced this session.');
    _state = BinanceHistoryScanState.cancelled;
    _message = 'A newer refresh replaced this scan.';
    _publish();
    _reader.credentialState.removeListener(_credentialListener);
  }

  void _onCredentialChanged() {
    if (_reader.credentialState.value == _snapshot) return;
    _generationChanged = true;
    _cancelToken.cancel('Binance credential generation changed.');
    _clearPrivateState();
    _state = BinanceHistoryScanState.cancelled;
    _message = 'Credentials changed; this scan cannot be resumed.';
    _publish();
  }

  Future<BinanceHistoryScanProgress> _run({required bool retryFailed}) {
    final running = _running;
    if (running != null) return running;
    if (_disposed || _superseded || !_isCurrentSession()) {
      return Future<BinanceHistoryScanProgress>.value(current);
    }
    if (_generationChanged || _reader.credentialState.value != _snapshot) {
      _generationChanged = true;
      _clearPrivateState();
      _state = BinanceHistoryScanState.cancelled;
      _message = 'Credentials changed; this scan cannot be resumed.';
      _publish();
      return Future<BinanceHistoryScanProgress>.value(current);
    }
    if (_state == BinanceHistoryScanState.complete) {
      return Future<BinanceHistoryScanProgress>.value(current);
    }
    if (_manualCancellation) {
      _manualCancellation = false;
      _cancelToken = CancelToken();
    }
    if (retryFailed && _failures.isNotEmpty) {
      _pending.addAll(_failures.keys);
      _failures.clear();
    }
    final future = _runLoop();
    _running = future;
    return future.whenComplete(() => _running = null);
  }

  Future<BinanceHistoryScanProgress> _runLoop() async {
    _state = BinanceHistoryScanState.running;
    _message = null;
    _retryAt = null;
    _publish();
    try {
      if (!_initialized) {
        final catalog = product == ExchangeProduct.spot
            ? await _reader.getSpotCatalog(
                cancelToken: _cancelToken,
                expectedGeneration: _snapshot,
                knownSymbols: _knownSymbols,
              )
            : await _reader.getFuturesCatalog(
                cancelToken: _cancelToken,
                expectedGeneration: _snapshot,
                knownSymbols: _knownSymbols,
              );
        _assertCurrent();
        for (final instrument in catalog.instruments) {
          _instruments[instrument.symbol] = instrument;
          _pending.add(instrument.symbol);
        }
        _catalogIssues
          ..clear()
          ..addAll(catalog.issues);
        _initialized = true;
        _publish();
      }

      if (_pauseCode == 'binance_budget_metadata_unavailable') {
        final known = _instruments.keys.toList(growable: false);
        if (product == ExchangeProduct.spot) {
          await _reader.getSpotCatalog(
            cancelToken: _cancelToken,
            expectedGeneration: _snapshot,
            knownSymbols: known,
          );
        } else {
          await _reader.getFuturesCatalog(
            cancelToken: _cancelToken,
            expectedGeneration: _snapshot,
            knownSymbols: known,
          );
        }
        _assertCurrent();
        final host = product == ExchangeProduct.spot
            ? BinanceHost.spot
            : BinanceHost.futures;
        if (!_requestCoordinator.stateFor(host).hasValidBudget) {
          _pause(
            const ExchangeReadException(
              code: 'binance_budget_metadata_unavailable',
              message:
                  'History is paused until valid Binance rate-limit metadata is available.',
            ),
          );
          return current;
        }
        _pauseCode = null;
      }

      while (_pending.isNotEmpty) {
        _assertCurrent();
        final symbol = (_pending.toList()..sort()).first;
        final instrument = _instruments[symbol];
        if (instrument == null) {
          _failures[symbol] = const ExchangeReadException(
            code: 'binance_history_instrument_missing',
            message: 'The captured history instrument is unavailable.',
          );
          _pending.remove(symbol);
          _publish();
          continue;
        }
        final failure = product == ExchangeProduct.spot
            ? await _scanSpotSymbol(instrument)
            : await _scanFuturesSymbol(instrument);
        if (_generationChanged || _reader.credentialState.value != _snapshot) {
          _generationChanged = true;
          _clearPrivateState();
          _state = BinanceHistoryScanState.cancelled;
          _message = 'Credentials changed; this scan cannot be resumed.';
          _publish();
          return current;
        }
        if (_cancelToken.isCancelled) {
          _state = BinanceHistoryScanState.cancelled;
          _message ??= 'History scan cancelled.';
          _publish();
          return current;
        }
        if (failure case final error?) {
          if (_isPause(error)) {
            _pause(error);
            return current;
          }
          _failures[symbol] = error;
          _pending.remove(symbol);
          _completed.remove(symbol);
          _publish();
          continue;
        }
        _failures.remove(symbol);
        _pending.remove(symbol);
        _completed.add(symbol);
        _publish();
      }
      _state = _failures.isEmpty
          ? BinanceHistoryScanState.complete
          : BinanceHistoryScanState.failed;
      _message = _failures.isEmpty
          ? 'All captured recent-history pages were read.'
          : 'Some captured symbols failed and remain visible in coverage.';
      _publish();
      return current;
    } on ExchangeReadException catch (error) {
      if (_isPause(error)) {
        _pause(error);
      } else if (_isGenerationFailure(error)) {
        _generationChanged = true;
        _clearPrivateState();
        _state = BinanceHistoryScanState.cancelled;
        _message = 'Credentials changed; this scan cannot be resumed.';
        _publish();
      } else if (_cancelToken.isCancelled || _superseded || _disposed) {
        _state = BinanceHistoryScanState.cancelled;
        _message ??= 'History scan cancelled.';
        _publish();
      } else {
        _state = BinanceHistoryScanState.failed;
        _message = error.message;
        _retryAt = error.retryAt;
        _publish();
      }
      return current;
    } catch (_) {
      if (_cancelToken.isCancelled || _superseded || _disposed) {
        _state = BinanceHistoryScanState.cancelled;
        _message ??= 'History scan cancelled.';
      } else {
        _state = BinanceHistoryScanState.failed;
        _message = 'Binance history scan failed.';
      }
      _publish();
      return current;
    }
  }

  Future<ExchangeReadException?> _scanSpotSymbol(
    ExchangeInstrument instrument,
  ) async {
    final pageKey = _pageKey(instrument.symbol, ExchangeOrderKind.ordinary);
    if (_successfulPages.contains(pageKey)) return null;
    try {
      final orders = await _requestGate.run(() async {
        _assertCurrent();
        return _reader.readSpotHistoryPage(
          instrument,
          expectedGeneration: _snapshot,
          cancelToken: _cancelToken,
        );
      });
      _assertCurrent();
      _successfulPages.add(pageKey);
      _retainRows(orders);
      return null;
    } on ExchangeReadException catch (error) {
      return error;
    } on DioException {
      if (_cancelToken.isCancelled) return _cancelledError();
      return ExchangeReadException(
        code: 'binance_history_request_failed',
        message: 'Recent Spot history could not be read.',
        instrument: instrument.symbol,
      );
    }
  }

  Future<ExchangeReadException?> _scanFuturesSymbol(
    ExchangeInstrument instrument,
  ) async {
    for (final kind in const <ExchangeOrderKind>[
      ExchangeOrderKind.ordinary,
      ExchangeOrderKind.conditional,
    ]) {
      final pageKey = _pageKey(instrument.symbol, kind);
      if (_successfulPages.contains(pageKey)) continue;
      try {
        final orders = await _requestGate.run(() async {
          _assertCurrent();
          return _reader.readFuturesHistoryPage(
            instrument,
            kind: kind,
            expectedGeneration: _snapshot,
            cancelToken: _cancelToken,
          );
        });
        _assertCurrent();
        _successfulPages.add(pageKey);
        _retainRows(orders);
        _publish();
      } on ExchangeReadException catch (error) {
        return error;
      } on DioException {
        if (_cancelToken.isCancelled) return _cancelledError();
        return ExchangeReadException(
          code: 'binance_history_request_failed',
          message: 'Recent Futures history could not be read.',
          instrument: instrument.symbol,
        );
      }
    }
    return null;
  }

  void _retainRows(Iterable<ExchangeOrder> orders) {
    final combined = <ExchangeOrder>[..._rowsByIdentity.values, ...orders];
    _rowsByIdentity
      ..clear()
      ..addEntries(
        linkConditionalExecutions(
          combined,
        ).map((order) => MapEntry(order.identityKey, order)),
      );
  }

  void _pause(ExchangeReadException error) {
    final host = product == ExchangeProduct.spot
        ? BinanceHost.spot
        : BinanceHost.futures;
    _state = BinanceHistoryScanState.paused;
    _pauseCode = error.code;
    _message = error.message;
    _retryAt = error.retryAt ?? _requestCoordinator.stateFor(host).retryAt;
    _publish();
  }

  bool _isPause(ExchangeReadException error) =>
      error.code == 'binance_budget_metadata_unavailable' ||
      error.code == 'binance_host_paused' ||
      error.code == 'binance_rate_limited' ||
      error.code == 'binance_ip_banned' ||
      error.code == 'binance_authentication_failed' ||
      error.code == 'binance_credentials_required' ||
      error.code == 'binance_credentials_unavailable' ||
      (error.code == 'binance_http_error' &&
          (error.statusCode == 401 || error.statusCode == 403));

  bool _isGenerationFailure(ExchangeReadException error) =>
      error.code == 'binance_credential_generation_changed';

  ExchangeReadException _cancelledError() => const ExchangeReadException(
    code: 'binance_request_cancelled',
    message: 'The history request was cancelled.',
  );

  String _pageKey(String symbol, ExchangeOrderKind kind) =>
      product.name + '|' + symbol + '|' + kind.name;

  void _assertCurrent() {
    if (_disposed || _superseded || !_isCurrentSession()) {
      throw const ExchangeReadException(
        code: 'binance_history_session_obsolete',
        message: 'A newer history refresh replaced this scan.',
      );
    }
    if (_generationChanged || _reader.credentialState.value != _snapshot) {
      _generationChanged = true;
      _clearPrivateState();
      throw const ExchangeReadException(
        code: 'binance_credential_generation_changed',
        message: 'The Binance credential generation changed.',
      );
    }
    if (_cancelToken.isCancelled) {
      throw const ExchangeReadException(
        code: 'binance_request_cancelled',
        message: 'The history request was cancelled.',
      );
    }
  }

  void _clearPrivateState() {
    _rowsByIdentity.clear();
    _instruments.clear();
    _pending.clear();
    _completed.clear();
    _failures.clear();
    _successfulPages.clear();
    _catalogIssues.clear();
    _knownSymbols.clear();
    _initialized = false;
    _retryAt = null;
  }

  BinanceHistoryScanProgress _buildProgress() {
    final orderedRows = _rowsByIdentity.values.toList()..sort(_compareOrders);
    return BinanceHistoryScanProgress(
      product: product,
      state: _state,
      initialized: _initialized,
      totalSymbols: _initialized ? _instruments.length : 0,
      completedSymbols: _completed.length,
      failedSymbols: _failures.length,
      pendingSymbols: _pending.length,
      rows: orderedRows,
      failures: _failures,
      catalogIssues: _catalogIssues,
      retryAt: _retryAt,
      message: _message,
      coverageNotice: product == ExchangeProduct.spot
          ? 'Recent first pages only: up to 500 orders per captured Spot pair. '
                'A current catalog plus symbols already known in this credential generation is used; '
                'delisted symbols no longer present in memory may be absent.'
          : 'Recent first pages only: up to 500 orders per captured USDT-settled contract. '
                'The native default covers recent seven days; retention excludes orders older '
                'than 90 days and canceled or expired unfilled orders after three days.',
    );
  }

  void _publish() {
    if (_disposed) return;
    final progress = _buildProgress();
    _current = progress;
    if (!_controller.isClosed) _controller.add(progress);
  }

  static int _compareOrders(ExchangeOrder left, ExchangeOrder right) {
    final leftTime = left.createdAtMilliseconds;
    final rightTime = right.createdAtMilliseconds;
    if (leftTime == null && rightTime != null) return 1;
    if (leftTime != null && rightTime == null) return -1;
    final byTime = (rightTime ?? 0).compareTo(leftTime ?? 0);
    if (byTime != 0) return byTime;
    final bySource = left.source.name.compareTo(right.source.name);
    if (bySource != 0) return bySource;
    final byProduct = (left.product?.name ?? 'unknown').compareTo(
      right.product?.name ?? 'unknown',
    );
    if (byProduct != 0) return byProduct;
    final byKind = left.kind.name.compareTo(right.kind.name);
    if (byKind != 0) return byKind;
    final bySymbol = left.symbol.compareTo(right.symbol);
    return bySymbol != 0 ? bySymbol : left.nativeId.compareTo(right.nativeId);
  }
}

class _BinanceHistoryRequestGate {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() request) async {
    final previous = _tail;
    final released = Completer<void>();
    _tail = released.future;
    await previous;
    try {
      return await request();
    } finally {
      released.complete();
    }
  }
}
