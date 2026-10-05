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

enum StrategyRetryOutcomeKind {
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

class StrategyRetryOutcome {
  const StrategyRetryOutcome(
    this.kind, {
    this.childId,
    this.result,
    this.message,
  });

  final StrategyRetryOutcomeKind kind;
  final String? childId;
  final Map<String, dynamic>? result;
  final String? message;
}

typedef StrategyRetryInteraction =
    Future<StrategyRetryOutcome?> Function(StrategyRetryFlow flow);

class StrategyRetryFlowException implements Exception {
  const StrategyRetryFlowException(this.message);

  final String message;

  @override
  String toString() => message;
}

class StrategyRetryFlow {
  StrategyRetryFlow._({
    required StrategyDashboardController controller,
    required this.sourceStrategyId,
    required this.retryRequestId,
  }) : _controller = controller;

  final StrategyDashboardController _controller;
  final String sourceStrategyId;
  final String retryRequestId;
  StrategyRetryCandidates? _candidates;
  StrategyRetryPreview? _preview;
  StrategyRetryDraft? _draft;
  Map<String, dynamic>? _prepared;
  bool _createAttempted = false;
  bool _prepareAttempted = false;
  bool _executeAttempted = false;
  bool _writeMayBeUncertain = false;
  bool _closed = false;
  int _pendingOperations = 0;
  Completer<void>? _pendingOperationsDrained;
  String? _lockedChildId;

  StrategyRetryCandidates? get candidates => _candidates;
  StrategyRetryPreview? get preview => _preview;
  StrategyRetryDraft? get draft => _draft;
  Map<String, dynamic>? get prepared => _prepared;
  bool get writeMayBeUncertain => _writeMayBeUncertain;
  bool get createAttempted => _createAttempted;
  bool get prepareAttempted => _prepareAttempted;
  bool get executeAttempted => _executeAttempted;

  void cancel() => _closed = true;

  Future<void> waitForPendingOperations() async {
    final pending = _pendingOperationsDrained?.future;
    if (pending != null) await pending;
  }

  Future<T> _track<T>(Future<T> Function() operation) async {
    if (_pendingOperations++ == 0) {
      _pendingOperationsDrained = Completer<void>();
    }
    try {
      return await operation();
    } finally {
      _pendingOperations--;
      if (_pendingOperations == 0) {
        _pendingOperationsDrained?.complete();
        _pendingOperationsDrained = null;
      }
    }
  }

  void _ensureActive() {
    if (!_controller.ownsSession) throw const _StrategyRetrySessionChanged();
    if (_closed) {
      throw const StrategyRetryFlowException(
        'Đã đóng bước xem lại. Hãy mở lại chiến thuật để bắt đầu một phiên mới.',
      );
    }
  }

  Future<StrategyRetryCandidates> loadCandidates() => _track(_loadCandidates);

  Future<StrategyRetryCandidates> _loadCandidates() async {
    _ensureActive();
    if (!_controller.ownsSession) throw const _StrategyRetrySessionChanged();
    if (_candidates != null) return _candidates!;
    final response = await _controller._api.getRetryCandidates(
      _controller._bearerToken,
      sourceStrategyId,
    );
    _ensureActive();
    if (response.sourceStrategyId != sourceStrategyId) {
      throw const StrategyRetryFlowException(
        'Máy chủ trả về chiến thuật nguồn khác. Hãy làm mới rồi xem lại.',
      );
    }
    _candidates = response;
    return response;
  }

  Future<StrategyRetryPreview> previewSelection(
    Iterable<String> selectedSourceClientOrderIds,
  ) => _track(() => _previewSelection(selectedSourceClientOrderIds));

  Future<StrategyRetryPreview> _previewSelection(
    Iterable<String> selectedSourceClientOrderIds,
  ) async {
    _ensureActive();
    _preview = null;
    final candidates = _candidates;
    if (candidates == null) {
      throw const StrategyRetryFlowException('Hãy tải danh sách lệnh trước.');
    }
    if (candidates.blockedReason != null) {
      throw StrategyRetryFlowException(
        _retryBlockMessage(candidates.blockedReason!),
      );
    }
    final selectedSet = selectedSourceClientOrderIds.toSet();
    if (selectedSet.isEmpty ||
        selectedSet.length > strategyNewSubmissionOrderLimit ||
        selectedSet.length != selectedSourceClientOrderIds.length) {
      throw const StrategyRetryFlowException(
        'Chọn từ 1 đến 10 lệnh khác nhau để xem lại.',
      );
    }
    final eligibleIds = candidates.candidates
        .where((candidate) => candidate.eligible)
        .map((candidate) => candidate.sourceClientOrderId)
        .toSet();
    if (!selectedSet.every(eligibleIds.contains)) {
      throw const StrategyRetryFlowException(
        'Danh sách có lệnh không đủ điều kiện. Hãy chọn lại từ các lệnh được đánh dấu.',
      );
    }
    final ids = candidates.candidates
        .where(
          (candidate) => selectedSet.contains(candidate.sourceClientOrderId),
        )
        .map((candidate) => candidate.sourceClientOrderId)
        .toList(growable: false);
    if (candidates.linkedChildren.any(
      (child) => child.sourceClientOrderIds.any(selectedSet.contains),
    )) {
      throw const StrategyRetryFlowException(
        'Các lệnh đã có bản gửi lại liên kết. Mở lịch sử để xem trạng thái bản đó.',
      );
    }
    final result = await _controller._api.previewRetry(
      _controller._bearerToken,
      sourceStrategyId,
      sourceRevision: candidates.sourceRevision,
      sourceClientOrderIds: ids,
    );
    _ensureActive();
    _validatePreview(result, candidates, ids);
    _preview = result;
    _draft = null;
    _prepared = null;
    return result;
  }

  Future<StrategyRetryDraft> createLinkedDraft() => _track(_createLinkedDraft);

  Future<StrategyRetryDraft> _createLinkedDraft() async {
    _ensureActive();
    final candidates = _candidates;
    final preview = _preview;
    if (candidates == null || preview == null) {
      throw const StrategyRetryFlowException(
        'Xem lại chính xác các lệnh trước khi tạo bản gửi lại.',
      );
    }
    if (_createAttempted) {
      throw const StrategyRetryFlowException(
        'Yêu cầu tạo bản gửi lại đã được gửi. Hãy làm mới trạng thái thay vì gửi lại.',
      );
    }
    _createAttempted = true;
    StrategyRetryDraft response;
    try {
      response = await _controller._api.createRetryDraft(
        _controller._bearerToken,
        sourceStrategyId,
        sourceRevision: candidates.sourceRevision,
        sourceClientOrderIds: preview.selectedSourceClientOrderIds,
        previewHash: preview.previewHash,
        retryRequestId: retryRequestId,
      );
    } on Object catch (error) {
      if (_isUncertainWrite(error)) {
        _writeMayBeUncertain = true;
        await _refreshAfterUncertain();
      }
      rethrow;
    }
    if (_closed) {
      _writeMayBeUncertain = true;
      await _refreshAfterUncertain();
      _ensureActive();
    }
    _ensureActive();
    try {
      _validateDraft(response, preview);
    } on Object {
      _writeMayBeUncertain = true;
      await _refreshAfterUncertain();
      rethrow;
    }
    if (!_controller._actionInFlight.add(response.id)) {
      _writeMayBeUncertain = true;
      await _refreshAfterUncertain();
      throw const StrategyRetryFlowException(
        'Bản gửi lại đã được tạo nhưng đang được xử lý ở một thao tác khác. Hãy làm mới trạng thái.',
      );
    }
    _lockedChildId = response.id;
    _controller._notify();
    _draft = response;
    await _controller.load();
    if (!_controller.ownsSession) throw const _StrategyRetrySessionChanged();
    return response;
  }

  Future<Map<String, dynamic>> prepareChild() => _track(_prepareChild);

  Future<Map<String, dynamic>> _prepareChild() async {
    _ensureActive();
    final draft = _draft;
    final preview = _preview;
    if (draft == null || preview == null) {
      throw const StrategyRetryFlowException(
        'Tạo bản gửi lại liên kết trước khi chuẩn bị xác nhận.',
      );
    }
    if (_prepareAttempted) {
      throw const StrategyRetryFlowException(
        'Bản gửi lại đã được chuẩn bị. Làm mới để xem trạng thái hiện tại.',
      );
    }
    _prepareAttempted = true;
    Map<String, dynamic> prepared;
    try {
      _ensureActive();
      prepared = await _controller._api.prepareApply(
        _controller._bearerToken,
        draft.id,
      );
    } on Object catch (error) {
      if (_isUncertainWrite(error)) {
        _writeMayBeUncertain = true;
        await _refreshAfterUncertain();
      }
      rethrow;
    }
    if (_closed) {
      _writeMayBeUncertain = true;
      await _refreshAfterUncertain();
      _ensureActive();
    }
    _ensureActive();
    try {
      _validatePrepared(prepared, draft, preview);
    } on Object {
      _writeMayBeUncertain = true;
      await _refreshAfterUncertain();
      rethrow;
    }
    _prepared = Map.unmodifiable(prepared);
    return _prepared!;
  }

  Future<Map<String, dynamic>> executeOnce() => _track(_executeOnce);

  Future<Map<String, dynamic>> _executeOnce() async {
    _ensureActive();
    final draft = _draft;
    final preview = _preview;
    final prepared = _prepared;
    if (draft == null || preview == null || prepared == null) {
      throw const StrategyRetryFlowException(
        'Chưa có bản gửi lại được chuẩn bị để xác nhận.',
      );
    }
    if (_executeAttempted) {
      throw const StrategyRetryFlowException(
        'Lệnh gửi đã được xác nhận một lần. Không gửi lại.',
      );
    }
    _executeAttempted = true;
    final token = _retryText(prepared['confirmationToken']);
    _ensureActive();
    Map<String, dynamic> result;
    try {
      result = await _controller._api.executeApply(
        _controller._bearerToken,
        draft.id,
        token,
      );
    } on Object catch (error) {
      _writeMayBeUncertain = true;
      await _refreshAfterUncertain();
      rethrow;
    }
    if (!_controller.ownsSession) throw const _StrategyRetrySessionChanged();
    await _refreshAfterUncertain();
    _ensureActive();
    final resultSource = _retryMap(result['resubmission']);
    final knownStatus = _retryText(result['status']).toUpperCase();
    final validAcknowledgement =
        _retryText(result['id']) == draft.id &&
        _retryText(resultSource?['sourceStrategyId']) == sourceStrategyId &&
        _sameStrings(
          _retryStrings(resultSource?['sourceClientOrderIds']),
          preview.selectedSourceClientOrderIds,
        ) &&
        const {
          'APPLIED',
          'COMPLETED',
          'PARTIAL',
          'UNKNOWN',
          'APPLYING',
          'FAILED',
          'REJECTED',
        }.contains(knownStatus);
    if (!validAcknowledgement) {
      _writeMayBeUncertain = true;
      return {
        'id': draft.id,
        'status': 'UNKNOWN',
        'resubmission': {
          'sourceStrategyId': sourceStrategyId,
          'sourceClientOrderIds': preview.selectedSourceClientOrderIds,
        },
        'acknowledgementInvalid': true,
      };
    }
    if (!const {'APPLIED', 'COMPLETED'}.contains(knownStatus)) {
      _writeMayBeUncertain = true;
    }
    return result;
  }

  Future<void> refreshReadOnly() => _track(_refreshAfterUncertain);

  Future<void> _refreshAfterUncertain() async {
    if (!_controller.ownsSession) return;
    try {
      final candidates = await _controller._api.getRetryCandidates(
        _controller._bearerToken,
        sourceStrategyId,
      );
      if (!_controller.ownsSession) return;
      if (candidates.sourceStrategyId == sourceStrategyId) {
        _candidates = candidates;
      }
    } on Object {
      if (!_controller.ownsSession) return;
    }
    await _controller.load();
    if (!_controller.ownsSession) return;
  }

  void _validatePreview(
    StrategyRetryPreview response,
    StrategyRetryCandidates candidates,
    List<String> ids,
  ) {
    final source = _controller.strategyById(sourceStrategyId);
    if (response.sourceStrategyId != sourceStrategyId ||
        response.sourceRevision != candidates.sourceRevision ||
        (source != null &&
            (_retryText(source['instrumentId']) !=
                    _retryText(response.raw['instrumentId']) ||
                _retryText(source['interval']) !=
                    _retryText(response.raw['interval']))) ||
        !_sameStrings(response.selectedSourceClientOrderIds, ids) ||
        response.orders.length != ids.length) {
      throw const StrategyRetryFlowException(
        'Máy chủ trả về bản xem trước khác với các lệnh đã chọn. Không thể tiếp tục.',
      );
    }
    for (var index = 0; index < ids.length; index++) {
      final candidate = candidates.candidates.firstWhere(
        (item) => item.sourceClientOrderId == ids[index],
      );
      final order = response.orders[index];
      if (order['sourceClientOrderId'] != candidate.sourceClientOrderId ||
          order['side'] != candidate.side ||
          order['role'] != candidate.role ||
          !_sameDecimal(order['limitPrice'], candidate.limitPrice) ||
          !_sameDecimal(order['contracts'], candidate.contracts) ||
          !_sameDecimal(order['leverage'], candidate.leverage) ||
          (candidate.levelId != null &&
              order['levelId'] != candidate.levelId)) {
        throw const StrategyRetryFlowException(
          'Giá, số hợp đồng hoặc đòn bẩy của lệnh xem trước khác nguồn. Không thể tiếp tục.',
        );
      }
    }
  }

  void _validateDraft(
    StrategyRetryDraft response,
    StrategyRetryPreview preview,
  ) {
    if (response.id == sourceStrategyId ||
        _retryText(response.resubmission['sourceStrategyId']) !=
            sourceStrategyId ||
        !_sameStrings(
          _retryStrings(response.resubmission['sourceClientOrderIds']),
          preview.selectedSourceClientOrderIds,
        ) ||
        response.orders.length != preview.orders.length ||
        response.orders.any(
          (order) => preview.selectedSourceClientOrderIds.contains(
            _retryText(order['clientOrderId']),
          ),
        ) ||
        !_sameRetryOrders(
          preview.orders,
          response.orders,
          requireChildIds: true,
        )) {
      throw const StrategyRetryFlowException(
        'Bản nháp trả về không khớp với chiến thuật nguồn và danh sách đã duyệt. Không thể chuẩn bị.',
      );
    }
    final nestedPreview = response.preview;
    if (nestedPreview.sourceStrategyId != preview.sourceStrategyId ||
        nestedPreview.sourceRevision != preview.sourceRevision ||
        nestedPreview.previewHash != preview.previewHash ||
        !_sameStrings(
          nestedPreview.selectedSourceClientOrderIds,
          preview.selectedSourceClientOrderIds,
        ) ||
        !_sameRetryOrders(
          preview.orders,
          nestedPreview.orders,
          requireChildIds: true,
        ) ||
        !_sameRetryCosts(preview, nestedPreview)) {
      throw const StrategyRetryFlowException(
        'Bản xem trước gắn trong bản nháp đã thay đổi. Không thể chuẩn bị.',
      );
    }
  }

  void _validatePrepared(
    Map<String, dynamic> prepared,
    StrategyRetryDraft draft,
    StrategyRetryPreview preview,
  ) {
    final mode = StrategyLimitOrderSubmissionMode.parse(
      prepared['submissionMode'],
    );
    final preparedOrders = validatedNewStrategyOrders(prepared);
    final responseIds = _retryStrings(
      _retryMap(prepared['resubmission'])?['sourceClientOrderIds'],
    );
    final preparedSource = _retryText(
      _retryMap(prepared['resubmission'])?['sourceStrategyId'],
    );
    final plannedMargin = _retryDecimal(prepared['plannedMargin']);
    final unallocatedMargin = _retryDecimal(prepared['unallocatedMargin']);
    final estimatedFees = _retryDecimal(prepared['estimatedOpeningFees']);
    if (_retryText(prepared['id']) != draft.id ||
        _retryText(prepared['status']).toUpperCase() != 'PREPARED' ||
        _retryText(prepared['confirmationToken']).isEmpty ||
        _retryText(prepared['confirmationToken']).length > 4096 ||
        mode == null ||
        preparedOrders == null ||
        preparedOrders.length != draft.orders.length ||
        preparedSource != sourceStrategyId ||
        !_sameStrings(responseIds, preview.selectedSourceClientOrderIds) ||
        !_sameRetryOrders(
          draft.orders,
          preparedOrders,
          requireChildIds: true,
        ) ||
        plannedMargin == null ||
        !_sameDecimal(plannedMargin, preview.plannedMargin) ||
        unallocatedMargin == null ||
        !_sameDecimal(unallocatedMargin, preview.unallocatedMargin) ||
        estimatedFees == null ||
        !_sameDecimal(estimatedFees, preview.estimatedOpeningFees)) {
      throw const StrategyRetryFlowException(
        'Máy chủ trả về danh sách, chi phí, nguồn liên kết hoặc cơ chế gửi khác với bản đã duyệt. Không thể xác nhận.',
      );
    }
  }
}

class _StrategyRetrySessionChanged implements Exception {
  const _StrategyRetrySessionChanged();
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
  final Set<String> _actionInFlight = {};
  final Set<String> _deleteInFlight = {};
  Future<void>? _loadFuture;
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
      await _refreshQuoteSnapshot();
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

  Future<StrategyRetryOutcome> retryLimitOrders(
    String sourceStrategyId, {
    required String retryRequestId,
    required StrategyRetryInteraction interact,
  }) async {
    if (!_ownsSession ||
        sourceStrategyId.isEmpty ||
        !_actionInFlight.add(sourceStrategyId)) {
      return const StrategyRetryOutcome(StrategyRetryOutcomeKind.duplicate);
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{16,64}$').hasMatch(retryRequestId)) {
      _actionInFlight.remove(sourceStrategyId);
      return const StrategyRetryOutcome(
        StrategyRetryOutcomeKind.rejected,
        message: 'Không thể tạo mã yêu cầu gửi lại an toàn.',
      );
    }
    _actionError = null;
    _notify();
    final flow = StrategyRetryFlow._(
      controller: this,
      sourceStrategyId: sourceStrategyId,
      retryRequestId: retryRequestId,
    );
    try {
      final outcome = await interact(flow);
      if (!_ownsSession) return _staleRetrySessionOutcome();
      return outcome ??
          const StrategyRetryOutcome(StrategyRetryOutcomeKind.cancelled);
    } on StrategyApiException catch (error) {
      if (!_ownsSession) return _staleRetrySessionOutcome();
      if (error.isUnauthorized) _onUnauthorized?.call();
      _actionError = error.message;
      if (flow.writeMayBeUncertain) await flow.refreshReadOnly();
      if (!_ownsSession) return _staleRetrySessionOutcome();
      return StrategyRetryOutcome(
        StrategyRetryOutcomeKind.rejected,
        message: error.message,
      );
    } on StrategyRetryFlowException catch (error) {
      if (!_ownsSession) return _staleRetrySessionOutcome();
      _actionError = error.message;
      return StrategyRetryOutcome(
        StrategyRetryOutcomeKind.rejected,
        message: error.message,
      );
    } on Object {
      if (!_ownsSession) return _staleRetrySessionOutcome();
      const message =
          'Kết quả gửi lại chưa rõ. Không gửi lại; hãy làm mới danh sách và lịch sử.';
      _actionError = message;
      if (flow.writeMayBeUncertain) await flow.refreshReadOnly();
      if (!_ownsSession) return _staleRetrySessionOutcome();
      return const StrategyRetryOutcome(
        StrategyRetryOutcomeKind.unknown,
        message: message,
      );
    } finally {
      flow.cancel();
      await flow.waitForPendingOperations();
      _actionInFlight.remove(sourceStrategyId);
      final childId = flow._lockedChildId;
      if (childId != null) _actionInFlight.remove(childId);
      _notify();
    }
  }

  Future<StrategyApplyOutcome> applyDraft(
    String id, {
    required StrategyConfirmation confirm,
  }) async {
    final existing = strategyById(id);
    final resubmission = _retryMap(existing?['resubmission']);
    final sourceId = _retryText(resubmission?['sourceStrategyId']);
    final actionIds = <String>{id, if (sourceId.isNotEmpty) sourceId};
    if (!_ownsSession || actionIds.any(_actionInFlight.contains)) {
      return const StrategyApplyOutcome(StrategyApplyOutcomeKind.duplicate);
    }
    _actionInFlight.addAll(actionIds);
    if (existing != null &&
        _text(existing['status']).toUpperCase() != 'DRAFT') {
      _actionInFlight.removeAll(actionIds);
      return const StrategyApplyOutcome(
        StrategyApplyOutcomeKind.rejected,
        message: 'Chỉ có thể áp dụng chiến thuật ở trạng thái bản nháp.',
      );
    }
    if (existing != null && existing['draftStage'] == 'candidates') {
      _actionInFlight.removeAll(actionIds);
      return const StrategyApplyOutcome(
        StrategyApplyOutcomeKind.rejected,
        message: 'Ứng viên cần được xem xét và lưu trước khi áp dụng.',
      );
    }
    if (existing != null && hasOversizedNewStrategyOrderPayload(existing)) {
      _actionInFlight.removeAll(actionIds);
      return const StrategyApplyOutcome(
        StrategyApplyOutcomeKind.rejected,
        message:
            'Bản nháp cũ vượt quá giới hạn 10 lệnh. Hãy tạo bản nháp mới với tối đa 10 lệnh.',
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
          validatedNewStrategyOrders(prepared) == null) {
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
      _actionInFlight.removeAll(actionIds);
      _notify();
    }
  }

  StrategyApplyOutcome _staleSessionOutcome() => const StrategyApplyOutcome(
    StrategyApplyOutcomeKind.rejected,
    message: 'Phiên giao dịch đã thay đổi. Hãy mở lại chiến thuật.',
  );

  StrategyRetryOutcome _staleRetrySessionOutcome() =>
      const StrategyRetryOutcome(
        StrategyRetryOutcomeKind.rejected,
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
    if (!_ownsSession ||
        _actionInFlight.contains(id) ||
        !_deleteInFlight.add(id) ||
        !_actionInFlight.add(id)) {
      _deleteInFlight.remove(id);
      return false;
    }
    final existing = strategyById(id);
    if (existing == null || existing['canDelete'] != true) {
      _deleteInFlight.remove(id);
      _actionInFlight.remove(id);
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
      _actionInFlight.remove(id);
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
    _pageVisible = pageVisible;
    _appVisible = appVisible;
    _markMetricsStaleIfExpired();
    _notifyQuoteFreshnessIfChanged();
  }

  void _markMetricsStaleIfExpired() {
    final lastSuccessfulAt = _lastSuccessfulStatusAt;
    if (lastSuccessfulAt == null || _metricsAreStale) return;
    final age = _clock().toUtc().difference(lastSuccessfulAt);
    if (!age.isNegative && age <= _maximumStatusAge) return;
    _markMetricsStale();
    _notify();
  }

  Future<void> _refreshQuoteSnapshot() async {
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
      if (!_ownsSession) return;
      try {
        final strategyId = strategyByInstrument[id]!;
        final response = await _api.getQuote(_bearerToken, strategyId);
        if (!_ownsSession) return;
        final quote = _tickerFromResponse(id, response);
        final previous = _quotes[id];
        if (strategyByInstrument[id] == strategyId &&
            quote.instrumentId == id &&
            (previous == null ||
                !quote.observedAt.isBefore(previous.observedAt))) {
          _quotes[id] = quote;
          _notify();
          _notifyQuoteFreshnessIfChanged();
        }
      } on StrategyApiException catch (error) {
        if (!_ownsSession) return;
        if (error.isUnauthorized) {
          _onUnauthorized?.call();
          return;
        }
        _notifyQuoteFreshnessIfChanged();
      } on Object {
        if (!_ownsSession) return;
        // Retain the last backend quote with its original timestamp.
        _notifyQuoteFreshnessIfChanged();
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

  String _text(Object? value) => value == null ? '' : value.toString();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _actionInFlight.clear();
    _deleteInFlight.clear();
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

String _retryText(Object? value) => value is String ? value : '';

StrategyDecimal? _retryDecimal(Object? value) =>
    StrategyDecimal.tryParse(strategyNumber(value));

Map<String, dynamic>? _retryMap(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) return null;
  return Map<String, dynamic>.from(value);
}

List<String>? _retryStrings(Object? value) {
  if (value is! List || value.any((item) => item is! String || item.isEmpty)) {
    return null;
  }
  return value.cast<String>();
}

bool _sameStrings(List<String>? actual, List<String> expected) =>
    actual != null &&
    actual.length == expected.length &&
    List<bool>.generate(
      actual.length,
      (index) => actual[index] == expected[index],
    ).every((match) => match);

bool _sameDecimal(Object? left, Object? right) {
  final leftDecimal = StrategyDecimal.tryParse(strategyNumber(left));
  final rightDecimal = StrategyDecimal.tryParse(strategyNumber(right));
  return leftDecimal != null &&
      rightDecimal != null &&
      leftDecimal.compareTo(rightDecimal) == 0;
}

bool _sameRetryCosts(StrategyRetryPreview left, StrategyRetryPreview right) =>
    _sameDecimal(left.totalMargin, right.totalMargin) &&
    _sameDecimal(left.plannedMargin, right.plannedMargin) &&
    _sameDecimal(left.unallocatedMargin, right.unallocatedMargin) &&
    _sameDecimal(left.estimatedOpeningFees, right.estimatedOpeningFees) &&
    _sameDecimal(left.requiredBalance, right.requiredBalance);

bool _sameRetryOrders(
  List<Map<String, dynamic>> expected,
  List<Map<String, dynamic>> actual, {
  required bool requireChildIds,
}) {
  if (expected.length != actual.length) return false;
  const fields = {
    'sourceClientOrderId',
    'side',
    'role',
    'limitPrice',
    'contracts',
    'leverage',
    'margin',
    'allocatedMargin',
    'notional',
    'openingFeeEstimate',
    'allocationWeight',
    'cumulativeContracts',
    'cumulativeAverageEntry',
    'liquidationEstimate',
    'levelId',
  };
  final actualClientIds = <String>{};
  for (var index = 0; index < expected.length; index++) {
    final left = expected[index];
    final right = actual[index];
    for (final field in fields) {
      if (left.containsKey(field) != right.containsKey(field)) return false;
      if (left.containsKey(field) &&
          !_sameRetryOrderField(field, left[field], right[field])) {
        return false;
      }
    }
    final expectedChildId = _retryText(left['clientOrderId']);
    final actualChildId = _retryText(right['clientOrderId']);
    if (expectedChildId.isNotEmpty && expectedChildId != actualChildId) {
      return false;
    }
    if (requireChildIds) {
      final sourceOrderId = _retryText(right['sourceClientOrderId']);
      if (actualChildId.isEmpty ||
          actualChildId == sourceOrderId ||
          !actualClientIds.add(actualChildId)) {
        return false;
      }
    }
  }
  return true;
}

bool _sameRetryOrderField(String field, Object? left, Object? right) {
  if (const {
    'sourceClientOrderId',
    'side',
    'role',
    'levelId',
  }.contains(field)) {
    return left == right;
  }
  if (field == 'liquidationEstimate') {
    return _sameRetryNestedValue(left, right);
  }
  return _sameDecimal(left, right);
}

bool _sameRetryNestedValue(Object? left, Object? right) {
  if (left == null || right == null) return left == right;
  if (left is Map && right is Map) {
    if (left.keys.any((key) => key is! String) ||
        right.keys.any((key) => key is! String) ||
        left.length != right.length ||
        left.keys.toSet().difference(right.keys.toSet()).isNotEmpty) {
      return false;
    }
    for (final key in left.keys) {
      if (!_sameRetryNestedValue(left[key], right[key])) return false;
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!_sameRetryNestedValue(left[index], right[index])) return false;
    }
    return true;
  }
  if (left is String && right is String) return left == right;
  if (left is num && right is num) {
    return _sameDecimal(left, right);
  }
  return left == right;
}

bool _isUncertainWrite(Object error) =>
    error is! StrategyApiException ||
    error.statusCode == null ||
    error.statusCode! >= 500 ||
    error.code == 'invalid_response';

String _retryBlockMessage(String code) => switch (code) {
  'retry_source_unavailable' =>
    'Chiến thuật nguồn không còn đủ điều kiện. Làm mới trạng thái vị thế và lệnh đang chờ, rồi xem lại.',
  'retry_source_stale' || 'retry_preview_stale' =>
    'Dữ liệu nguồn đã thay đổi. Làm mới danh sách và xem lại lệnh.',
  'retry_selection_in_use' =>
    'Một số lệnh đã thuộc bản gửi lại khác. Mở lịch sử liên kết để kiểm tra.',
  'position_exists' || 'positions_present' =>
    'Tài khoản đang có vị thế. Đóng hoặc kiểm tra vị thế rồi xem lại.',
  'pending_order' || 'pending_orders' =>
    'Tài khoản còn lệnh đang chờ. Cập nhật trạng thái trước khi xem lại.',
  'reservation_conflict' || 'reservation_exists' =>
    'Tài khoản đang có khoản vốn được giữ chỗ. Cập nhật trạng thái trước khi xem lại.',
  'lease_active' || 'strategy_busy' =>
    'Chiến thuật đang được xử lý. Làm mới trạng thái rồi thử xem lại sau.',
  _ => 'Máy chủ chưa cho phép gửi lại: $code. Cập nhật trạng thái rồi xem lại.',
};
