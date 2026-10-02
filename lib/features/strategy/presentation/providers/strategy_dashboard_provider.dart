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
  queued,
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
    // Preserve compatibility for existing callers during the API handoff.
    StrategyMarketRepository? marketRepository,
    required String bearerToken,
    DateTime Function()? clock,
    VoidCallback? onUnauthorized,
    bool Function()? sessionIsCurrent,
  }) : _api = api,
       _bearerToken = bearerToken,
       _clock = clock ?? DateTime.now,
       _onUnauthorized = onUnauthorized,
       _sessionIsCurrent = sessionIsCurrent;

  final StrategyApi _api;
  final String _bearerToken;
  final DateTime Function() _clock;
  final VoidCallback? _onUnauthorized;
  final bool Function()? _sessionIsCurrent;
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
  String? _limitOrderSubmissionMode;
  String? _settingsError;
  bool _settingsIsLoading = false;
  bool _settingsIsSaving = false;
  bool _settingsLoaded = false;
  Future<void>? _settingsLoadFuture;

  bool get ownsSession => _ownsSession;

  bool get _ownsSession => !_disposed && (_sessionIsCurrent?.call() ?? true);

  List<Map<String, dynamic>> get strategies => _strategies;
  bool get isLoading => _isLoading;
  String? get loadError => _loadError;
  String? get actionError => _actionError;
  String? get deleteError => _deleteError;
  String? get limitOrderSubmissionMode => _limitOrderSubmissionMode;
  String? get settingsError => _settingsError;
  bool get settingsIsLoading => _settingsIsLoading;
  bool get settingsIsSaving => _settingsIsSaving;
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
    if (!_ownsSession) return Future<void>.value();
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
      final strategies = await _api.listStrategies(_bearerToken);
      if (!_ownsSession) return;
      _strategies = strategies;
      _loadError = null;
      _metricsAreStale = false;
      _metricsStaleAt = null;
      _lastSuccessfulStatusAt = _clock().toUtc();
      _startPolling();
      if (_pollingActive) unawaited(_pollQuotes());
    } on StrategyApiException catch (error) {
      if (!_ownsSession) return;
      if (error.isUnauthorized) _onUnauthorized?.call();
      _loadError = error.message;
      _markMetricsStale();
    } on Object {
      if (!_ownsSession) return;
      _loadError = 'Không thể tải danh sách chiến thuật. Hãy thử làm mới.';
      _markMetricsStale();
    } finally {
      if (_ownsSession) {
        _isLoading = false;
        _notify();
      }
    }
  }

  Future<void> loadStrategySettings({bool force = false}) {
    if (!_ownsSession) return Future<void>.value();
    final current = _settingsLoadFuture;
    if (current != null) return current;
    if (_settingsLoaded && !force) return Future<void>.value();
    final future = _performSettingsLoad();
    _settingsLoadFuture = future;
    return future.whenComplete(() {
      if (identical(_settingsLoadFuture, future)) _settingsLoadFuture = null;
    });
  }

  Future<void> _performSettingsLoad() async {
    _settingsIsLoading = true;
    _settingsError = null;
    _notify();
    try {
      final mode = await _api.getLimitOrderSubmissionMode(_bearerToken);
      if (!_ownsSession) return;
      if (StrategyLimitOrderSubmissionMode.parse(mode) == null) {
        throw const StrategyApiException(
          code: 'invalid_response',
          message: 'Máy chủ trả về cơ chế gửi lệnh không hợp lệ.',
        );
      }
      _limitOrderSubmissionMode = mode;
      _settingsLoaded = true;
      _settingsError = null;
    } on StrategyApiException catch (error) {
      if (!_ownsSession) return;
      if (error.isUnauthorized) _onUnauthorized?.call();
      _settingsError = error.message;
    } on Object {
      if (!_ownsSession) return;
      _settingsError = 'Không thể tải cài đặt chiến thuật.';
    } finally {
      if (_ownsSession) {
        _settingsIsLoading = false;
        _notify();
      }
    }
  }

  Future<bool> saveLimitOrderSubmissionMode(String mode) async {
    if (!_ownsSession || _settingsIsSaving) return false;
    if (StrategyLimitOrderSubmissionMode.parse(mode) == null) {
      _settingsError = 'Cơ chế gửi lệnh không hợp lệ.';
      _notify();
      return false;
    }
    _settingsIsSaving = true;
    _settingsError = null;
    _notify();
    try {
      final acknowledged = await _api.saveLimitOrderSubmissionMode(
        _bearerToken,
        mode,
      );
      if (!_ownsSession) return false;
      if (acknowledged != mode ||
          StrategyLimitOrderSubmissionMode.parse(acknowledged) == null) {
        throw const StrategyApiException(
          code: 'invalid_response',
          message: 'Máy chủ chưa xác nhận lựa chọn đã lưu.',
        );
      }
      _limitOrderSubmissionMode = acknowledged;
      _settingsLoaded = true;
      _settingsError = null;
      return true;
    } on StrategyApiException catch (error) {
      if (!_ownsSession) return false;
      if (error.isUnauthorized) _onUnauthorized?.call();
      _settingsError = error.message;
      return false;
    } on Object {
      if (!_ownsSession) return false;
      _settingsError = 'Không thể lưu cài đặt chiến thuật.';
      return false;
    } finally {
      if (_ownsSession) {
        _settingsIsSaving = false;
        _notify();
      }
    }
  }

  Future<void> refresh() => load();

  Future<StrategyApplyOutcome> applyDraft(
    String id, {
    required StrategyConfirmation confirm,
  }) async {
    if (!_ownsSession || !_actionInFlight.add(id)) {
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
      if (!_ownsSession) return _staleSessionOutcome();
      final confirmationToken = _text(prepared['confirmationToken']);
      if (confirmationToken.isEmpty ||
          StrategyLimitOrderSubmissionMode.parse(prepared['submissionMode']) ==
              null ||
          validatedStrategyOrders(prepared) == null) {
        const message =
            'Máy chủ không trả về cơ chế gửi và danh sách lệnh hợp lệ để xác nhận.';
        _actionError = message;
        return const StrategyApplyOutcome(
          StrategyApplyOutcomeKind.rejected,
          message: message,
        );
      }
      final confirmed = await confirm(prepared);
      if (!_ownsSession) return _staleSessionOutcome();
      if (!confirmed) {
        return const StrategyApplyOutcome(StrategyApplyOutcomeKind.cancelled);
      }
      // This is the only execute call in this flow. An uncertain response is
      // surfaced as unknown and is never retried automatically.
      final result = await _api.executeApply(
        _bearerToken,
        id,
        confirmationToken,
      );
      if (!_ownsSession) return _staleSessionOutcome();
      await load();
      if (!_ownsSession) return _staleSessionOutcome();
      _rememberReplacementCleanupConflict(id, result);
      final resultStatus = _text(result['status']).toUpperCase();
      if (resultStatus == 'APPLYING' &&
          _isAcknowledgedSequentialQueue(result)) {
        return StrategyApplyOutcome(
          StrategyApplyOutcomeKind.queued,
          result: result,
          message: 'Các lệnh đã được đưa vào hàng đợi tuần tự.',
        );
      }
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
      if (!_ownsSession) return _staleSessionOutcome();
      if (error.isUnauthorized) _onUnauthorized?.call();
      _actionError = error.message;
      if (error.statusCode == null || error.statusCode! >= 500) {
        // A status refresh is read-only; never repeat the execute write.
        await load();
        if (!_ownsSession) return _staleSessionOutcome();
        return const StrategyApplyOutcome(
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
      if (!_ownsSession) return _staleSessionOutcome();
      const message =
          'Kết quả gửi lệnh chưa rõ. Không tự gửi lại; hãy làm mới trạng thái.';
      _actionError = message;
      await load();
      if (!_ownsSession) return _staleSessionOutcome();
      return const StrategyApplyOutcome(
        StrategyApplyOutcomeKind.unknown,
        message: message,
      );
    } finally {
      _actionInFlight.remove(id);
      _notify();
    }
  }

  StrategyApplyOutcome _staleSessionOutcome() => const StrategyApplyOutcome(
    StrategyApplyOutcomeKind.rejected,
    message: 'Phiên giao dịch đã thay đổi. Hãy mở lại chiến thuật.',
  );

  bool _isAcknowledgedSequentialQueue(Map<String, dynamic> result) {
    final mode = StrategyLimitOrderSubmissionMode.parse(
      result['submissionMode'],
    );
    return mode == StrategyLimitOrderSubmissionMode.sequential &&
        const {'pending', 'sending'}.contains(result['queueStatus']);
  }

  Future<bool> deleteDraft(String id) async {
    if (!_ownsSession || !_deleteInFlight.add(id)) return false;
    final existing = strategyById(id);
    if (existing == null || existing['canDelete'] != true) {
      _deleteInFlight.remove(id);
      return false;
    }
    _deleteError = null;
    _notify();
    try {
      await _api.deleteDraft(_bearerToken, id);
      if (!_ownsSession) return false;
      await load();
      return _ownsSession;
    } on StrategyApiException catch (error) {
      if (!_ownsSession) return false;
      if (error.isUnauthorized) _onUnauthorized?.call();
      _deleteError = error.message;
      return false;
    } on Object {
      if (!_ownsSession) return false;
      _deleteError = 'Không thể xóa chiến thuật.';
      return false;
    } finally {
      _deleteInFlight.remove(id);
      _notify();
    }
  }

  Future<Map<String, dynamic>?> refreshResult(String id) async {
    if (!_ownsSession || !_actionInFlight.add('result:$id')) return null;
    try {
      final result = await _api.getResult(_bearerToken, id);
      if (!_ownsSession) return null;
      await load();
      if (!_ownsSession) return null;
      _rememberReplacementCleanupConflict(id, result);
      return result;
    } on Object catch (error) {
      if (!_ownsSession) return null;
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

  bool isActionInFlight(String id) =>
      _actionInFlight.contains(id) || _deleteInFlight.contains(id);

  void _rememberReplacementCleanupConflict(
    String id,
    Map<String, dynamic> result,
  ) {
    if (result['replacementCleanupConflict'] != true) return;
    final index = _strategies.indexWhere(
      (strategy) => _text(strategy['id']) == id,
    );
    if (index < 0) return;
    final updated = List<Map<String, dynamic>>.of(_strategies);
    updated[index] = {...updated[index], 'replacementCleanupConflict': true};
    _strategies = updated;
    _notify();
  }

  void setVisibility({required bool pageVisible, required bool appVisible}) {
    if (!_ownsSession ||
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
    final strategyByInstrument = <String, String>{};
    for (final item in _strategies) {
      if (!_quotePollingStatuses.contains(
        _text(item['status']).toUpperCase(),
      )) {
        continue;
      }
      final instrumentId = _text(item['instrumentId']).toUpperCase();
      final strategyId = _text(item['id']);
      if (strategyId.isEmpty ||
          !RegExp(r'^[A-Z0-9]+-USDT-SWAP$').hasMatch(instrumentId)) {
        continue;
      }
      strategyByInstrument.putIfAbsent(instrumentId, () => strategyId);
    }
    final instruments = strategyByInstrument.keys.toList()..sort();
    for (final id in instruments) {
      if (!_pollingActive || _quoteInFlight.contains(id)) continue;
      final retryAt = _quoteRetryAt[id];
      if (retryAt != null && _clock().toUtc().isBefore(retryAt)) continue;
      if (!_quoteInFlight.add(id)) continue;
      try {
        final strategyId = strategyByInstrument[id]!;
        final response = await _api.getQuote(_bearerToken, strategyId);
        if (!_ownsSession) continue;
        final quote = _tickerFromResponse(id, response);
        final previous = _quotes[id];
        if (_pollingActive &&
            strategyByInstrument[id] == strategyId &&
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
      } on StrategyApiException catch (error) {
        if (!_ownsSession) continue;
        if (error.isUnauthorized) _onUnauthorized?.call();
        _scheduleQuoteRetry(id);
        _notifyQuoteFreshnessIfChanged();
      } on Object {
        if (!_ownsSession) continue;
        // Retain the last backend quote with its original timestamp.
        _scheduleQuoteRetry(id);
        _notifyQuoteFreshnessIfChanged();
      } finally {
        _quoteInFlight.remove(id);
      }
    }
  }

  StrategyTicker _tickerFromResponse(
    String expectedInstrumentId,
    Map<String, dynamic> response,
  ) {
    final instrumentId = _text(response['instrumentId']).toUpperCase();
    final exactPriceText = response['lastPrice'] is String
        ? response['lastPrice'] as String
        : '';
    final price = double.tryParse(exactPriceText);
    final observedAt = DateTime.tryParse(
      _text(response['observedAt']),
    )?.toUtc();
    final now = _clock().toUtc();
    if (instrumentId != expectedInstrumentId ||
        exactPriceText.isEmpty ||
        price == null ||
        !price.isFinite ||
        price <= 0 ||
        observedAt == null) {
      throw const FormatException('The strategy quote response is invalid.');
    }
    final age = now.difference(observedAt);
    if (age.isNegative || age > const Duration(seconds: 15)) {
      throw const FormatException('The strategy quote response is stale.');
    }
    return StrategyTicker(
      instrumentId: instrumentId,
      lastPrice: price,
      observedAt: observedAt,
      exactPriceText: exactPriceText,
    );
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
      bool sessionIsCurrent() {
        final state = ref.read(tradeSessionProvider);
        return state.isAuthenticated &&
            state.session?.bearerToken == bearerToken;
      }

      final controller = StrategyDashboardController(
        api: ref.watch(strategyApiProvider),
        bearerToken: bearerToken,
        sessionIsCurrent: sessionIsCurrent,
        onUnauthorized: () => ref.read(tradeSessionProvider.notifier).expire(),
      );
      unawaited(controller.load());
      return controller;
    });
