import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/okx_order_model.dart';
import '../../data/trade_api_client.dart';
import '../widgets/trade_action_confirmation_dialog.dart';
import 'order_provider.dart';
import 'position_action_flow_provider.dart';
import 'trade_session_provider.dart';

final orderCancellationFlowProvider =
    StateNotifierProvider<
      OrderCancellationFlowsController,
      Map<String, OrderCancellationFlowState>
    >((ref) {
      return OrderCancellationFlowsController(
        readApi: () => ref.read(tradeApiProvider),
        readSession: () => ref.read(tradeSessionProvider),
        readSessionController: () => ref.read(tradeSessionProvider.notifier),
        readAccountActions: () =>
            ref.read(positionActionFlowsProvider.notifier),
        invalidateOrders: () => ref.invalidate(ordersFutureProvider),
      );
    });

class OrderCancellationFlowState {
  const OrderCancellationFlowState({
    required this.runId,
    required this.sessionOwner,
    this.isBusy = false,
    this.statusMessage,
    this.accountIdentifier,
  });

  final int runId;
  final TradeSession? sessionOwner;
  final bool isBusy;
  final String? statusMessage;
  final String? accountIdentifier;
}

bool isActiveLimitOrder(OkxOrder order) =>
    order.ordType.toLowerCase() == 'limit' &&
    const {'live', 'partially_filled'}.contains(order.state.toLowerCase());

Map<String, dynamic> orderCancellationTargetIdentity(OkxOrder order) => {
  'instType': order.instType,
  'instId': order.instId,
  'ordId': order.ordId,
  'ordType': order.ordType,
  'side': order.side,
  'px': order.px,
  'sz': order.sz,
};

bool hasCompleteOrderCancellationIdentity(OkxOrder order) {
  if (!isActiveLimitOrder(order)) return false;
  final identity = orderCancellationTargetIdentity(order);
  if (identity.values.any((value) => !_boundedIdentityText(value.toString()))) {
    return false;
  }
  if (!const {
    'SPOT',
    'MARGIN',
    'SWAP',
    'FUTURES',
  }.contains(order.instType.toUpperCase())) {
    return false;
  }
  if (!const {'buy', 'sell'}.contains(order.side.toLowerCase())) return false;
  return _positiveDecimal(order.px) && _positiveDecimal(order.sz);
}

String orderCancellationFlowKey(
  Map<String, dynamic> identity,
  String? accountIdentifier,
) => jsonEncode([accountIdentifier ?? '', identity]);

class OrderCancellationFlowsController
    extends StateNotifier<Map<String, OrderCancellationFlowState>> {
  OrderCancellationFlowsController({
    required TradeApi Function() readApi,
    required TradeSessionState Function() readSession,
    required TradeSessionController Function() readSessionController,
    required PositionActionFlowsController Function() readAccountActions,
    required void Function() invalidateOrders,
  }) : _readApi = readApi,
       _readSession = readSession,
       _readSessionController = readSessionController,
       _readAccountActions = readAccountActions,
       _invalidateOrders = invalidateOrders,
       super(const {});

  final TradeApi Function() _readApi;
  final TradeSessionState Function() _readSession;
  final TradeSessionController Function() _readSessionController;
  final PositionActionFlowsController Function() _readAccountActions;
  final void Function() _invalidateOrders;
  int _nextRunId = 0;
  final Map<String, TradeSession> _operationSessions = {};

  bool operationBelongsToSession(
    PendingTradeOperation operation,
    TradeSession? session,
  ) {
    if (operation.action != 'cancel_order') return true;
    final owner = _operationSessions[operation.operationId];
    return owner != null && identical(owner, session);
  }

  void associateOperationWithSession(String operationId, TradeSession session) {
    _operationSessions[operationId] = session;
  }

  Future<void> cancelOrder({
    required OkxOrder order,
    required NavigatorState navigator,
    required Route<dynamic>? ownerRoute,
  }) async {
    final identity = Map<String, dynamic>.unmodifiable(
      orderCancellationTargetIdentity(order),
    );
    final initialState = _readSession();
    final initialSession = initialState.session;
    final flowKey = orderCancellationFlowKey(
      identity,
      initialSession?.accountIdentifier ??
          initialState.operationAccountIdentifier,
    );
    final previousFlow = state[flowKey];
    if (previousFlow?.isBusy == true &&
        identical(previousFlow?.sessionOwner, initialSession)) {
      return;
    }

    final runId = ++_nextRunId;
    if (!_readApi().isConfigured) {
      _publish(
        flowKey,
        OrderCancellationFlowState(
          runId: runId,
          sessionOwner: initialSession,
          statusMessage: 'TRADE_API_BASE_URL chưa được cấu hình.',
        ),
      );
      return;
    }
    if (!hasCompleteOrderCancellationIdentity(order)) {
      _publish(
        flowKey,
        OrderCancellationFlowState(
          runId: runId,
          sessionOwner: initialSession,
          statusMessage: 'Thiếu định danh lệnh hợp lệ; không gửi yêu cầu.',
        ),
      );
      return;
    }
    if (initialSession == null ||
        !initialState.isAuthenticated ||
        !initialSession.isActive) {
      if (initialSession != null) _readSessionController().expire();
      _publish(
        flowKey,
        OrderCancellationFlowState(
          runId: runId,
          sessionOwner: initialSession,
          statusMessage: 'Phiên giao dịch không hoạt động. Hãy đăng nhập lại.',
        ),
      );
      return;
    }
    if (initialState.pendingOperations.isNotEmpty) {
      _publish(
        flowKey,
        OrderCancellationFlowState(
          runId: runId,
          sessionOwner: initialSession,
          statusMessage:
              'Có thao tác chưa rõ kết quả. Tra cứu trạng thái trước khi gửi thao tác mới.',
        ),
      );
      return;
    }

    final accountActions = _readAccountActions();
    if (!accountActions.tryAcquireAccountAction(
      initialSession.accountIdentifier,
    )) {
      _publish(
        flowKey,
        OrderCancellationFlowState(
          runId: runId,
          sessionOwner: initialSession,
          statusMessage: 'Đang có thao tác khác trên tài khoản này.',
        ),
      );
      return;
    }

    _publish(
      flowKey,
      OrderCancellationFlowState(
        runId: runId,
        sessionOwner: initialSession,
        isBusy: true,
        accountIdentifier: initialSession.accountIdentifier,
      ),
    );
    var shouldRefreshOrders = false;
    var ordersRefreshed = false;
    void refreshOrdersOnce() {
      if (ordersRefreshed) return;
      ordersRefreshed = true;
      _invalidateOrders();
    }

    var writeStarted = false;
    try {
      if (!_canContinue(
        flowKey,
        runId,
        initialSession,
        navigator,
        ownerRoute,
      )) {
        return;
      }

      final api = _readApi();
      late final PreparedTradeAction prepared;
      try {
        shouldRefreshOrders = true;
        prepared = await api.prepare(
          initialSession.bearerToken,
          action: 'cancel_order',
          targetIdentity: identity,
        );
      } on TradeApiException catch (error) {
        if (error.isUnauthorized && _sessionMatches(initialSession!)) {
          _readSessionController().expire();
        }
        _setStatus(flowKey, runId, error.message);
        return;
      }

      if (!_canContinue(
        flowKey,
        runId,
        initialSession,
        navigator,
        ownerRoute,
      )) {
        return;
      }
      if (!_preparedCancellationMatches(prepared, identity)) {
        _setStatus(
          flowKey,
          runId,
          'Máy chủ trả về mục tiêu hủy khác hoặc thiếu thông tin. Không có lệnh nào được gửi.',
        );
        return;
      }

      final target = prepared.targets.single;
      final remainingSize = _summaryValue(target, 'remainingSize');
      final confirmed = await showTradeActionConfirmation(
        navigator.context,
        prepared: prepared,
        title: 'Xác nhận hủy lệnh limit',
        confirmLabel: 'Hủy phần còn lại $remainingSize',
        destructive: true,
        sessionOwner: initialSession,
      );
      if (!confirmed ||
          !_canContinue(
            flowKey,
            runId,
            initialSession,
            navigator,
            ownerRoute,
          )) {
        return;
      }

      final beforeExecute = _readSession();
      if (beforeExecute.pendingOperations.isNotEmpty) {
        _setStatus(
          flowKey,
          runId,
          'Có thao tác chưa rõ kết quả. Tra cứu trạng thái trước khi gửi thao tác mới.',
        );
        return;
      }
      if (!_sessionMatches(initialSession) ||
          !_dialogOwnerIsActive(navigator, ownerRoute)) {
        _setStatus(
          flowKey,
          runId,
          'Phiên giao dịch hoặc màn hình đã thay đổi. Không gửi lệnh hủy.',
        );
        return;
      }

      final operationId = prepared.operationId;
      final sessionController = _readSessionController();
      _operationSessions[operationId] = initialSession;
      sessionController.rememberOperation(
        PendingTradeOperation(
          operationId: operationId,
          action: 'cancel_order',
          targetLabel: _orderTargetLabel(order),
          status: 'IN_PROGRESS',
        ),
      );

      // Remember the operation before the write, then recheck ownership at the
      // last point where execute can still be prevented.
      final justBeforeExecute = _readSession();
      if (!_sessionMatches(initialSession) ||
          !_dialogOwnerIsActive(navigator, ownerRoute) ||
          justBeforeExecute.pendingOperations.any(
            (operation) => operation.operationId != operationId,
          )) {
        sessionController.resolveOperation(operationId);
        _operationSessions.remove(operationId);
        _setStatus(
          flowKey,
          runId,
          'Phiên giao dịch hoặc màn hình đã thay đổi. Không gửi lệnh hủy.',
        );
        return;
      }

      shouldRefreshOrders = true;
      writeStarted = true;
      await _executeCancellation(
        api: api,
        order: order,
        prepared: prepared,
        initialSession: initialSession,
        navigator: navigator,
        ownerRoute: ownerRoute,
        flowKey: flowKey,
        runId: runId,
        refreshOrders: refreshOrdersOnce,
      );
    } on TradeApiException catch (error) {
      if (error.isUnauthorized && _sessionMatches(initialSession!)) {
        _readSessionController().expire();
      }
      _setStatus(flowKey, runId, error.message);
    } catch (_) {
      _setStatus(
        flowKey,
        runId,
        writeStarted
            ? 'Chưa xác nhận được kết quả hủy. Thao tác vẫn được lưu để tra cứu.'
            : 'Chưa thể chuẩn bị xác nhận hủy. Không gửi lệnh hủy.',
      );
    } finally {
      if (shouldRefreshOrders) refreshOrdersOnce();
      accountActions.releaseAccountAction(initialSession.accountIdentifier);
      final currentFlow = state[flowKey];
      if (currentFlow?.runId == runId) {
        _publish(
          flowKey,
          OrderCancellationFlowState(
            runId: runId,
            sessionOwner: currentFlow?.sessionOwner,
            statusMessage: currentFlow?.statusMessage,
            accountIdentifier: currentFlow?.accountIdentifier,
          ),
        );
      }
    }
  }

  Future<void> _executeCancellation({
    required TradeApi api,
    required OkxOrder order,
    required PreparedTradeAction prepared,
    required TradeSession initialSession,
    required NavigatorState navigator,
    required Route<dynamic>? ownerRoute,
    required String flowKey,
    required int runId,
    required void Function() refreshOrders,
  }) async {
    final operationId = prepared.operationId;
    final sessionController = _readSessionController();
    TradeOperationResult? result;
    String? lookupError;
    var lookupAttempted = false;

    try {
      result = await api.execute(
        initialSession.bearerToken,
        operationId: operationId,
        confirmationToken: prepared.confirmationToken,
      );
    } on TradeApiException catch (error) {
      if (error.isUnauthorized ||
          (error.statusCode != null && error.statusCode! < 500)) {
        if (_sessionMatches(initialSession)) {
          if (error.isUnauthorized) sessionController.expire();
          sessionController.resolveOperation(operationId);
          _operationSessions.remove(operationId);
        }
        refreshOrders();
        _setStatus(flowKey, runId, error.message);
        return;
      }
      lookupAttempted = true;
      final lookup = await _lookupOnce(api, initialSession, operationId);
      if (!_sessionMatches(initialSession)) return;
      result = lookup.result;
      lookupError = lookup.error;
    } catch (_) {
      lookupAttempted = true;
      final lookup = await _lookupOnce(api, initialSession, operationId);
      if (!_sessionMatches(initialSession)) return;
      result = lookup.result;
      lookupError = lookup.error;
    }

    refreshOrders();
    if (!_sessionMatches(initialSession)) return;
    if (result == null || !_resultMatches(result, operationId)) {
      if (!lookupAttempted) {
        lookupAttempted = true;
        final lookup = await _lookupOnce(api, initialSession, operationId);
        if (!_sessionMatches(initialSession)) return;
        result = lookup.result;
        lookupError = lookup.error;
      }
    }

    final initialResult = result;
    if (initialResult == null || !_resultMatches(initialResult, operationId)) {
      _setStatus(
        flowKey,
        runId,
        'Chưa xác nhận được kết quả hủy. Thao tác vẫn được lưu để tra cứu.',
      );
      return;
    }
    var currentResult = initialResult;

    if (!lookupAttempted && tradeOperationNeedsStatusLookup(currentResult)) {
      lookupAttempted = true;
      final lookup = await _lookupOnce(api, initialSession, operationId);
      if (!_sessionMatches(initialSession)) return;
      if (lookup.result != null &&
          _resultMatches(lookup.result!, operationId)) {
        currentResult = lookup.result!;
      }
      lookupError ??= lookup.error;
    }

    if (!_sessionMatches(initialSession)) return;
    if (!_resultMatches(currentResult, operationId)) {
      _setStatus(
        flowKey,
        runId,
        'Kết quả không khớp thao tác hủy. Thao tác vẫn được lưu để tra cứu.',
      );
      return;
    }

    if (tradeOperationNeedsStatusLookup(currentResult)) {
      sessionController.updateOperation(
        PendingTradeOperation(
          operationId: operationId,
          action: 'cancel_order',
          targetLabel: _orderTargetLabel(order),
          status: currentResult.status,
        ),
      );
    } else {
      sessionController.resolveOperation(operationId);
      _operationSessions.remove(operationId);
    }

    if (_dialogOwnerIsActive(navigator, ownerRoute)) {
      await _showResult(
        navigator,
        currentResult,
        sessionOwner: initialSession,
        lookupError: lookupError,
      );
    }
    _setStatus(
      flowKey,
      runId,
      _cancellationHeadline(currentResult.status, currentResult.operationId),
    );
  }

  bool _canContinue(
    String flowKey,
    int runId,
    TradeSession expectedSession,
    NavigatorState navigator,
    Route<dynamic>? ownerRoute,
  ) {
    if (!_dialogOwnerIsActive(navigator, ownerRoute)) return false;
    final current = _readSession();
    if (current.pendingOperations.isNotEmpty) {
      _setStatus(
        flowKey,
        runId,
        'Có thao tác chưa rõ kết quả. Tra cứu trạng thái trước khi gửi thao tác mới.',
      );
      return false;
    }
    if (!_sessionMatches(expectedSession)) {
      _setStatus(
        flowKey,
        runId,
        'Phiên giao dịch đã thay đổi hoặc hết hạn. Hãy đăng nhập lại.',
      );
      return false;
    }
    return true;
  }

  bool _sessionMatches(TradeSession expected) {
    final currentState = _readSession();
    final current = currentState.session;
    if (!currentState.isAuthenticated ||
        current == null ||
        !identical(current, expected) ||
        current.bearerToken != expected.bearerToken ||
        current.accountIdentifier != expected.accountIdentifier) {
      return false;
    }
    if (!current.isActive) {
      _readSessionController().expire();
      return false;
    }
    return true;
  }

  bool _dialogOwnerIsActive(
    NavigatorState navigator,
    Route<dynamic>? ownerRoute,
  ) => navigator.mounted && (ownerRoute == null || ownerRoute.isActive);

  bool _preparedCancellationMatches(
    PreparedTradeAction prepared,
    Map<String, dynamic> selectedIdentity,
  ) {
    if (prepared.operationId.isEmpty ||
        prepared.confirmationToken.isEmpty ||
        prepared.action != 'cancel_order' ||
        prepared.summary['targetCount'] != 1 ||
        prepared.targets.length != 1) {
      return false;
    }
    final target = prepared.targets.single;
    final preparedIdentity = tradeJsonMap(target['identity']);
    if (!_sameOrderCancellationIdentity(preparedIdentity, selectedIdentity)) {
      return false;
    }
    final price = _summaryValue(target, 'price');
    final originalSize = _summaryValue(target, 'originalSize');
    final filledSize = _summaryValue(target, 'filledSize');
    final remainingSize = _summaryValue(target, 'remainingSize');
    if (!_positiveDecimal(price) ||
        !_positiveDecimal(originalSize) ||
        !_nonNegativeDecimal(filledSize) ||
        !_positiveDecimal(remainingSize) ||
        !_sameDecimal(price, selectedIdentity['px'].toString()) ||
        !_sameDecimal(originalSize, selectedIdentity['sz'].toString())) {
      return false;
    }
    return _decimalLessThanOrEqual(filledSize, originalSize) &&
        _decimalLessThanOrEqual(remainingSize, originalSize) &&
        _decimalSumEquals(filledSize, remainingSize, originalSize);
  }

  bool _sameOrderCancellationIdentity(
    Map<String, dynamic> actual,
    Map<String, dynamic> selected,
  ) {
    const exactFields = ['instType', 'instId', 'ordId', 'ordType', 'side'];
    for (final field in exactFields) {
      if (actual[field]?.toString() != selected[field]?.toString())
        return false;
    }
    return _sameDecimal(actual['px']?.toString(), selected['px']?.toString()) &&
        _sameDecimal(actual['sz']?.toString(), selected['sz']?.toString());
  }

  bool _resultMatches(TradeOperationResult result, String operationId) =>
      result.operationId == operationId && result.action == 'cancel_order';

  Future<_LookupResult> _lookupOnce(
    TradeApi api,
    TradeSession session,
    String operationId,
  ) async {
    try {
      return _LookupResult(
        result: await api.getResult(session.bearerToken, operationId),
      );
    } on TradeApiException catch (error) {
      if (error.isUnauthorized && _sessionMatches(session)) {
        _readSessionController().expire();
      }
      return _LookupResult(error: error.message);
    } catch (_) {
      return const _LookupResult(
        error: 'Không thể tra cứu trạng thái thao tác.',
      );
    }
  }

  Future<void> _showResult(
    NavigatorState navigator,
    TradeOperationResult result, {
    required TradeSession sessionOwner,
    String? lookupError,
  }) async {
    if (!navigator.mounted) return;
    await showDialog<void>(
      context: navigator.context,
      builder: (context) => _OrderCancellationResultDialog(
        result: result,
        lookupError: lookupError,
        sessionOwner: sessionOwner,
        targetOutcome: _targetOutcome,
        headline: _cancellationHeadline,
      ),
    );
  }

  Widget _targetOutcome(Map<String, dynamic> target) {
    final identity = tradeJsonMap(target['identity']);
    final outcome = tradeJsonMap(target['outcome']);
    final status = target['status']?.toString().toUpperCase() ?? 'UNKNOWN';
    final instrument = identity['instId']?.toString() ?? 'Lệnh';
    final orderId = identity['ordId']?.toString() ?? '--';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$instrument · $status'),
          Text('Mã lệnh: $orderId'),
          Text(
            'Giá: ${_summaryValue(target, 'price', fallback: identity['px'])} · '
            'Tổng khối lượng: ${_summaryValue(target, 'originalSize', fallback: identity['sz'])}',
          ),
          Text(
            'Đã khớp: ${_summaryValue(target, 'filledSize', fallback: outcome['filledSize'])} · '
            'Còn lại: ${_summaryValue(target, 'remainingSize', fallback: outcome['remainingSize'])}',
          ),
          if (outcome['reason'] != null)
            Text('Lý do: ${outcome['reason'].toString().replaceAll('_', ' ')}'),
        ],
      ),
    );
  }

  String _cancellationHeadline(String status, String operationId) =>
      switch (status) {
        'SUCCEEDED' => 'Đã hủy lệnh limit',
        'PARTIAL' => 'Lệnh đã khớp một phần trước khi hủy',
        'UNKNOWN' => 'Chưa rõ kết quả hủy lệnh',
        'CONFLICT' => 'Lệnh đã thay đổi trước khi hủy',
        'FAILED' => 'Hủy lệnh limit thất bại',
        'EXPIRED' => 'Xác nhận hủy lệnh đã hết hạn',
        _ => 'Trạng thái hủy $status · $operationId',
      };

  void _setStatus(String key, int runId, String message) {
    final current = state[key];
    if (current == null || current.runId != runId) return;
    _publish(
      key,
      OrderCancellationFlowState(
        runId: runId,
        sessionOwner: current.sessionOwner,
        isBusy: current.isBusy,
        statusMessage: message,
        accountIdentifier: current.accountIdentifier,
      ),
    );
  }

  void _publish(String key, OrderCancellationFlowState value) {
    state = {...state, key: value};
  }
}

class _LookupResult {
  const _LookupResult({this.result, this.error});

  final TradeOperationResult? result;
  final String? error;
}

String _orderTargetLabel(OkxOrder order) =>
    '${order.instId} · ${order.side.toUpperCase()} · #${order.ordId}';

String _summaryValue(
  Map<String, dynamic> target,
  String key, {
  Object? fallback,
}) => (target[key] ?? fallback)?.toString() ?? '--';

bool _boundedIdentityText(String value) =>
    value.trim().isNotEmpty && value.length <= 256 && value == value.trim();

bool _positiveDecimal(String value) {
  final parsed = _scaledDecimal(value, _fractionDigits(value));
  return parsed != null && parsed > BigInt.zero;
}

bool _nonNegativeDecimal(String value) {
  final parsed = _scaledDecimal(value, _fractionDigits(value));
  return parsed != null && parsed >= BigInt.zero;
}

bool _sameDecimal(String? left, String? right) {
  if (left == null || right == null) return false;
  final leftParts = _decimalParts(left);
  final rightParts = _decimalParts(right);
  return leftParts != null && rightParts != null && leftParts == rightParts;
}

String? _decimalParts(String value) {
  final match = _decimalPattern.firstMatch(value);
  if (match == null) return null;
  final whole = match.group(1)!.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  final fraction = (match.group(2) ?? '').replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty ? whole : '$whole.$fraction';
}

final RegExp _decimalPattern = RegExp(r'^(\d+)(?:\.(\d+))?$');

int? _fractionDigits(String value) {
  if (value.length > 128) return null;
  final match = _decimalPattern.firstMatch(value);
  if (match == null) return null;
  final digits = match.group(2)?.length ?? 0;
  return digits <= 64 ? digits : null;
}

BigInt? _scaledDecimal(String value, int? scale) {
  if (scale == null || value.length > 128) return null;
  final match = _decimalPattern.firstMatch(value);
  if (match == null) return null;
  final whole = BigInt.tryParse(match.group(1)!);
  if (whole == null) return null;
  final fraction = match.group(2) ?? '';
  if (fraction.length > scale) return null;
  final unit = BigInt.from(10).pow(scale);
  final fractionalUnits = fraction.isEmpty
      ? BigInt.zero
      : BigInt.parse(fraction.padRight(scale, '0'));
  return whole * unit + fractionalUnits;
}

bool _decimalLessThanOrEqual(String left, String right) {
  final leftScale = _fractionDigits(left);
  final rightScale = _fractionDigits(right);
  if (leftScale == null || rightScale == null) return false;
  final scale = leftScale > rightScale ? leftScale : rightScale;
  final leftValue = _scaledDecimal(left, scale);
  final rightValue = _scaledDecimal(right, scale);
  return leftValue != null && rightValue != null && leftValue <= rightValue;
}

bool _decimalSumEquals(String left, String right, String expected) {
  final leftScale = _fractionDigits(left);
  final rightScale = _fractionDigits(right);
  final expectedScale = _fractionDigits(expected);
  if (leftScale == null || rightScale == null || expectedScale == null) {
    return false;
  }
  final scale = [
    leftScale,
    rightScale,
    expectedScale,
  ].reduce((a, b) => a > b ? a : b);
  final leftValue = _scaledDecimal(left, scale);
  final rightValue = _scaledDecimal(right, scale);
  final expectedValue = _scaledDecimal(expected, scale);
  return leftValue != null &&
      rightValue != null &&
      expectedValue != null &&
      leftValue + rightValue == expectedValue;
}

class _OrderCancellationResultDialog extends ConsumerWidget {
  const _OrderCancellationResultDialog({
    required this.result,
    required this.lookupError,
    required this.sessionOwner,
    required this.targetOutcome,
    required this.headline,
  });

  final TradeOperationResult result;
  final String? lookupError;
  final TradeSession sessionOwner;
  final Widget Function(Map<String, dynamic>) targetOutcome;
  final String Function(String, String) headline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSession = ref.watch(tradeSessionProvider).session;
    final ownsResult = identical(currentSession, sessionOwner);
    return AlertDialog(
      title: Text(
        ownsResult
            ? headline(result.status, result.operationId)
            : 'Phiên giao dịch đã thay đổi',
      ),
      content: SizedBox(
        width: 420,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: ownsResult
              ? ListView(
                  shrinkWrap: true,
                  children: [
                    Text('Mã thao tác: ${result.operationId}'),
                    for (final target in result.targets) targetOutcome(target),
                    if (lookupError != null)
                      Text('Lỗi tra cứu trạng thái: $lookupError'),
                  ],
                )
              : const Text('Nội dung thao tác đã được ẩn.'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Đóng'),
        ),
      ],
    );
  }
}
