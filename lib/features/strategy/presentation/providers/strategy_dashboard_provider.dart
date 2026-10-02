import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../orders/presentation/providers/trade_session_provider.dart';
import '../../data/strategy_api_client.dart';
import '../../data/strategy_market_repository.dart';
import '../../domain/strategy_models.dart';

typedef StrategyConfirmation =
    Future<bool> Function(Map<String, dynamic> prepared);

enum StrategyApplyOutcomeKind {
  cancelled,
  applied,
  duplicate,
  unknown,
  rejected,
}

class StrategyApplyOutcome {
  const StrategyApplyOutcome(this.kind, {this.result, this.message});

  final StrategyApplyOutcomeKind kind;
  final Map<String, dynamic>? result;
  final String? message;
}

class StrategyDashboardController extends ChangeNotifier {
  static const _maximumStatusAge = Duration(seconds: 20);
  static const _quotePollingStatuses = {'APPLIED', 'PARTIAL', 'UNKNOWN'};

  StrategyDashboardController({
    required StrategyApi api,
    required StrategyMarketRepository marketRepository,
    required String bearerToken,
    StrategyMarketClock? clock,
    VoidCallback? onUnauthorized,
  }) : _api = api,
       _marketRepository = marketRepository,
       _bearerToken = bearerToken,
       _clock = clock ?? DateTime.now,
       _onUnauthorized = onUnauthorized;

  final StrategyApi _api;
  final StrategyMarketRepository _marketRepository;
  final String _bearerToken;
  final StrategyMarketClock _clock;
  final VoidCallback? _onUnauthorized;
  List<Map<String, dynamic>> _strategies = const [];
  final Map<String, StrategyTicker> _quotes = {};
  final Map<String, bool> _reportedQuoteFreshness = {};
  final Set<String> _quoteInFlight = {};
  final Map<String, DateTime> _quoteRetryAt = {};
  final Map<String, int> _quoteFailureCount = {};
  final Set<String> _actionInFlight = {};
  final Set<String> _deleteInFlight = {};
  Future<void>? _loadFuture;
  Timer? _quoteTimer;
  Timer? _statusTimer;
  bool _pageVisible = false;
  bool _appVisible = true;
  bool _isLoading = false;
  bool _disposed = false;
  bool _metricsAreStale = false;
  DateTime? _metricsStaleAt;
  DateTime? _lastSuccessfulStatusAt;
  String? _loadError;
  String? _actionError;
  String? _deleteError;

  List<Map<String, dynamic>> get strategies => _strategies;
  bool get isLoading => _isLoading;
  String? get loadError => _loadError;
  String? get actionError => _actionError;
  String? get deleteError => _deleteError;
  bool get metricsAreStale => _metricsAreStale;
  DateTime? get metricsStaleAt => _metricsStaleAt;
  Map<String, dynamic>? strategyById(String id) {
    for (final strategy in _strategies) {
      if (_text(strategy['id']) == id) return strategy;
    }
    return null;
  }

  StrategyTicker? quoteFor(String instrumentId) => _quotes[instrumentId];

  bool quoteIsFresh(String instrumentId) =>
      _quotes[instrumentId]?.isFreshAt(_clock().toUtc()) ?? false;

  Future<void> load() {
    if (_disposed) return Future<void>.value();
    final current = _loadFuture;
    if (current != null) return current;
    final future = _performLoad();
    _loadFuture = future;
    return future.whenComplete(() {
      if (identical(_loadFuture, future)) _loadFuture = null;
    });
  }

  Future<void> _performLoad() async {
    _isLoading = true;
    _loadError = null;
    _notify();
    try {
      _strategies = await _api.listStrategies(_bearerToken);
      _loadError = null;
      _metricsAreStale = false;
      _metricsStaleAt = null;
      _lastSuccessfulStatusAt = _clock().toUtc();
      _startPolling();
      if (_pollingActive) unawaited(_pollQuotes());
    } on StrategyApiException catch (error) {
      if (error.isUnauthorized) _onUnauthorized?.call();
      _loadError = error.message;
      _markMetricsStale();
    } on Object {
      _loadError = 'Không thể tải danh sách chiến thuật. Hãy thử làm mới.';
      _markMetricsStale();
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  Future<void> refresh() => load();

  Future<StrategyApplyOutcome> applyDraft(
    String id, {
    required StrategyConfirmation confirm,
  }) async {
    if (_disposed || !_actionInFlight.add(id)) {
      return const StrategyApplyOutcome(StrategyApplyOutcomeKind.duplicate);
    }
    final existing = strategyById(id);
    if (existing != null &&
        _text(existing['status']).toUpperCase() != 'DRAFT') {
      _actionInFlight.remove(id);
      return const StrategyApplyOutcome(
        StrategyApplyOutcomeKind.rejected,
        message: 'Chỉ có thể áp dụng chiến thuật ở trạng thái bản nháp.',
      );
    }
    _actionError = null;
    _notify();
    try {
      final prepared = await _api.prepareApply(_bearerToken, id);
      final confirmationToken = _text(prepared['confirmationToken']);
      if (confirmationToken.isEmpty ||
          validatedStrategyOrders(prepared) == null) {
        const message =
            'Máy chủ không trả về danh sách lệnh hợp lệ để xác nhận.';
        _actionError = message;
        return const StrategyApplyOutcome(
          StrategyApplyOutcomeKind.rejected,
          message: message,
        );
      }
      if (!await confirm(prepared)) {
        return const StrategyApplyOutcome(StrategyApplyOutcomeKind.cancelled);
      }
      // This is the only execute call in this flow. An uncertain response is
      // surfaced as unknown and is never retried automatically.
      final result = await _api.executeApply(
        _bearerToken,
        id,
        confirmationToken,
      );
      await load();
      final resultStatus = _text(result['status']).toUpperCase();
      if (const {'PARTIAL', 'UNKNOWN', 'APPLYING'}.contains(resultStatus)) {
        return StrategyApplyOutcome(
          StrategyApplyOutcomeKind.unknown,
          result: result,
          message:
              'Máy chủ báo trạng thái $resultStatus. Không gửi lại; làm mới để xem kết quả.',
        );
      }
      return StrategyApplyOutcome(
        StrategyApplyOutcomeKind.applied,
        result: result,
      );
    } on StrategyApiException catch (error) {
      if (error.isUnauthorized) _onUnauthorized?.call();
      _actionError = error.message;
      if (error.statusCode == null || error.statusCode! >= 500) {
        // A status refresh is read-only; never repeat the execute write.
        await load();
        return StrategyApplyOutcome(
          StrategyApplyOutcomeKind.unknown,
          message:
              'Kết quả gửi lệnh chưa rõ. Không tự gửi lại; hãy làm mới trạng thái.',
        );
      }
      return StrategyApplyOutcome(
        StrategyApplyOutcomeKind.rejected,
        message: error.message,
      );
    } on Object {
      const message =
          'Kết quả gửi lệnh chưa rõ. Không tự gửi lại; hãy làm mới trạng thái.';
      _actionError = message;
      await load();
      return const StrategyApplyOutcome(
        StrategyApplyOutcomeKind.unknown,
        message: message,
      );
    } finally {
      _actionInFlight.remove(id);
      _notify();
    }
  }

  Future<bool> deleteDraft(String id) async {
    if (_disposed || !_deleteInFlight.add(id)) return false;
    final existing = strategyById(id);
    if (existing == null ||
        _text(existing['status']).toUpperCase() != 'DRAFT') {
      _deleteInFlight.remove(id);
      return false;
    }
    _deleteError = null;
    _notify();
    try {
      await _api.deleteDraft(_bearerToken, id);
      await load();
      return true;
    } on StrategyApiException catch (error) {
      if (error.isUnauthorized) _onUnauthorized?.call();
      _deleteError = error.message;
      return false;
    } on Object {
      _deleteError = 'Không thể xóa bản nháp.';
      return false;
    } finally {
      _deleteInFlight.remove(id);
      _notify();
    }
  }

  Future<Map<String, dynamic>?> refreshResult(String id) async {
    if (_disposed || !_actionInFlight.add('result:$id')) return null;
    try {
      final result = await _api.getResult(_bearerToken, id);
      await load();
      return result;
    } on Object catch (error) {
      if (error is StrategyApiException && error.isUnauthorized) {
        _onUnauthorized?.call();
      }
      _actionError = error is StrategyApiException
          ? error.message
          : 'Không thể cập nhật trạng thái chiến thuật.';
      _markMetricsStale();
      _notify();
      return null;
    } finally {
      _actionInFlight.remove('result:$id');
    }
  }

  bool isActionInFlight(String id) => _actionInFlight.contains(id);

  void setVisibility({required bool pageVisible, required bool appVisible}) {
    if (_disposed ||
        (_pageVisible == pageVisible && _appVisible == appVisible)) {
      return;
    }
    final wasActive = _pollingActive;
    _pageVisible = pageVisible;
    _appVisible = appVisible;
    if (_pollingActive) {
      if (!wasActive) _refreshStatusIfStale();
      _startPolling();
      if (!wasActive) unawaited(_pollQuotes());
    } else {
      _stopPolling();
    }
    _notifyQuoteFreshnessIfChanged();
  }

  bool get _pollingActive => _pageVisible && _appVisible && !_disposed;

  void _refreshStatusIfStale() {
    final lastSuccessfulAt = _lastSuccessfulStatusAt;
    if (lastSuccessfulAt == null) {
      unawaited(load());
      return;
    }
    final age = _clock().toUtc().difference(lastSuccessfulAt);
    if (!age.isNegative && age <= _maximumStatusAge) return;
    _markMetricsStale();
    _notify();
    unawaited(load());
  }

  void _startPolling() {
    if (!_pollingActive) return;
    _quoteTimer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_pollQuotes()),
    );
    _statusTimer ??= Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(load()),
    );
  }

  Future<void> _pollQuotes() async {
    if (!_pollingActive) return;
    _notifyQuoteFreshnessIfChanged();
    final instruments =
        _strategies
            .where(
              (item) => _quotePollingStatuses.contains(
                _text(item['status']).toUpperCase(),
              ),
            )
            .map((item) => _text(item['instrumentId']).toUpperCase())
            .where((id) => RegExp(r'^[A-Z0-9]+-USDT-SWAP$').hasMatch(id))
            .toSet()
            .toList()
          ..sort();
    for (final id in instruments) {
      if (!_pollingActive || _quoteInFlight.contains(id)) continue;
      final retryAt = _quoteRetryAt[id];
      if (retryAt != null && _clock().toUtc().isBefore(retryAt)) continue;
      if (!_quoteInFlight.add(id)) continue;
      try {
        final quote = await _marketRepository.getTicker(instrumentId: id);
        final previous = _quotes[id];
        if (_pollingActive &&
            instruments.contains(id) &&
            quote.instrumentId == id &&
            (previous == null ||
                !quote.observedAt.isBefore(previous.observedAt))) {
          _quotes[id] = quote;
          _quoteRetryAt.remove(id);
          _quoteFailureCount.remove(id);
          _notify();
          _notifyQuoteFreshnessIfChanged();
        } else if (_pollingActive) {
          _scheduleQuoteRetry(id);
        }
      } on Object {
        // Retain the last quote with its original timestamp. The UI marks it
        // stale after four seconds instead of presenting it as current.
        _scheduleQuoteRetry(id);
        _notifyQuoteFreshnessIfChanged();
      } finally {
        _quoteInFlight.remove(id);
      }
    }
  }

  void _scheduleQuoteRetry(String instrumentId) {
    final failures = (_quoteFailureCount[instrumentId] ?? 0) + 1;
    _quoteFailureCount[instrumentId] = failures;
    final seconds = 1 << failures.clamp(1, 5).toInt();
    _quoteRetryAt[instrumentId] = _clock().toUtc().add(
      Duration(seconds: seconds > 30 ? 30 : seconds),
    );
  }

  void _notifyQuoteFreshnessIfChanged() {
    var changed = false;
    final now = _clock().toUtc();
    for (final entry in _quotes.entries) {
      final fresh = entry.value.isFreshAt(now);
      if (_reportedQuoteFreshness[entry.key] != fresh) {
        _reportedQuoteFreshness[entry.key] = fresh;
        changed = true;
      }
    }
    if (changed) _notify();
  }

  void _markMetricsStale() {
    _metricsAreStale = true;
    _metricsStaleAt = _clock().toUtc();
  }

  void _stopPolling() {
    _quoteTimer?.cancel();
    _statusTimer?.cancel();
    _quoteTimer = null;
    _statusTimer = null;
  }

  String _text(Object? value) => value == null ? '' : value.toString();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopPolling();
    _quoteInFlight.clear();
    _actionInFlight.clear();
    _deleteInFlight.clear();
    _quoteRetryAt.clear();
    _quoteFailureCount.clear();
    super.dispose();
  }
}

final strategyDashboardProvider = ChangeNotifierProvider.autoDispose
    .family<StrategyDashboardController, String>((ref, bearerToken) {
      final controller = StrategyDashboardController(
        api: ref.watch(strategyApiProvider),
        marketRepository: ref.watch(strategyMarketRepositoryProvider),
        bearerToken: bearerToken,
        onUnauthorized: () => ref.read(tradeSessionProvider.notifier).expire(),
      );
      unawaited(controller.load());
      return controller;
    });
