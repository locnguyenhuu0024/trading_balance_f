import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/okx_position_model.dart';
import '../../data/trade_api_client.dart';
import 'trade_session_provider.dart';

typedef PositionActionInputCollector = Future<String?> Function();
typedef PositionActionConfirmer =
    Future<bool> Function(PreparedTradeAction prepared);
typedef PositionActionResultPresenter =
    Future<void> Function(TradeOperationResult result, {String? lookupError});

final positionActionFlowsProvider =
    StateNotifierProvider<
      PositionActionFlowsController,
      Map<String, PositionActionFlowState>
    >((ref) {
      return PositionActionFlowsController(
        readApi: () => ref.read(tradeApiProvider),
        readSession: () => ref.read(tradeSessionProvider),
        readSessionController: () => ref.read(tradeSessionProvider.notifier),
        invalidatePositions: () => ref.invalidate(tradePositionsProvider),
      );
    });

class PositionActionFlowState {
  const PositionActionFlowState({
    required this.runId,
    this.isBusy = false,
    this.statusMessage,
    this.accountIdentifier,
  });

  final int runId;
  final bool isBusy;
  final String? statusMessage;
  final String? accountIdentifier;
}

/// Produces a deterministic key for the complete identity returned by the
/// private API. Sorting nested maps makes the key stable across JSON decoding.
String positionActionIdentityKey(Map<String, dynamic> identity) {
  return jsonEncode(_canonicalJsonValue(identity));
}

String positionActionFlowKey(
  Map<String, dynamic> identity,
  String? accountIdentifier,
) {
  return jsonEncode([accountIdentifier ?? '', _canonicalJsonValue(identity)]);
}

bool positionActionHasCompleteIdentity(OkxPosition position) {
  final identity = position.identity;
  final type = (identity['instrumentType'] ?? '').toString().toUpperCase();
  final instrument = (identity['instrumentId'] ?? '').toString();
  final side = (identity['positionSide'] ?? '').toString().toLowerCase();
  final marginMode = (identity['marginMode'] ?? '').toString().toLowerCase();
  final direction = position.direction.toLowerCase();
  final size = double.tryParse(position.size);
  if (!const {'MARGIN', 'SWAP', 'FUTURES'}.contains(type) ||
      instrument.isEmpty ||
      !const {'net', 'long', 'short'}.contains(side) ||
      !const {'cross', 'isolated'}.contains(marginMode) ||
      !const {'long', 'short'}.contains(direction) ||
      size == null ||
      !size.isFinite ||
      size <= 0) {
    return false;
  }
  if (type == 'MARGIN') {
    return (identity['marginCurrency'] ?? '').toString().isNotEmpty &&
        (identity['positionSide'] ?? '').toString().toLowerCase() == 'net';
  }
  return true;
}

class PositionActionFlowsController
    extends StateNotifier<Map<String, PositionActionFlowState>> {
  PositionActionFlowsController({
    required TradeApi Function() readApi,
    required TradeSessionState Function() readSession,
    required TradeSessionController Function() readSessionController,
    required void Function() invalidatePositions,
  }) : _readApi = readApi,
       _readSession = readSession,
       _readSessionController = readSessionController,
       _invalidatePositions = invalidatePositions,
       super(const {});

  final TradeApi Function() _readApi;
  final TradeSessionState Function() _readSession;
  final TradeSessionController Function() _readSessionController;
  final void Function() _invalidatePositions;
  final Set<String> _activeAccounts = {};
  int _nextRunId = 0;

  bool isAccountActionActive(String accountIdentifier) {
    return _activeAccounts.contains(accountIdentifier);
  }

  bool tryAcquireAccountAction(String accountIdentifier) {
    return _activeAccounts.add(accountIdentifier);
  }

  void releaseAccountAction(String accountIdentifier) {
    _activeAccounts.remove(accountIdentifier);
  }

  Future<void> runAction({
    required OkxPosition position,
    required String action,
    required String? inputKind,
    required NavigatorState navigator,
    required Route<dynamic>? ownerRoute,
    required PositionActionConfirmer confirm,
    required PositionActionResultPresenter showResult,
    PositionActionInputCollector? collectInput,
  }) async {
    final identity = Map<String, dynamic>.unmodifiable(
      Map<String, dynamic>.from(position.identity),
    );
    final initialSessionState = _readSession();
    final initialSession = initialSessionState.session;
    final flowKey = positionActionFlowKey(
      identity,
      initialSession?.accountIdentifier ??
          initialSessionState.operationAccountIdentifier,
    );

    if (state[flowKey]?.isBusy == true) return;
    final runId = ++_nextRunId;
    if (!_readApi().isConfigured) {
      _publish(
        flowKey,
        PositionActionFlowState(
          runId: runId,
          statusMessage: 'TRADE_API_BASE_URL chưa được cấu hình.',
        ),
      );
      return;
    }
    if (!positionActionHasCompleteIdentity(position)) {
      _publish(
        flowKey,
        PositionActionFlowState(
          runId: runId,
          statusMessage:
              'Thiếu định danh hoặc hướng vị thế; không gửi yêu cầu.',
        ),
      );
      return;
    }
    if (initialSession == null || !initialSession.isActive) {
      if (initialSession != null) _readSessionController().expire();
      _publish(
        flowKey,
        PositionActionFlowState(
          runId: runId,
          statusMessage: 'Phiên giao dịch không hoạt động. Hãy đăng nhập lại.',
        ),
      );
      return;
    }
    if (initialSessionState.pendingOperations.isNotEmpty) {
      _publish(
        flowKey,
        PositionActionFlowState(
          runId: runId,
          statusMessage:
              'Có thao tác chưa rõ kết quả. Tra cứu trạng thái trước khi gửi thao tác mới.',
        ),
      );
      return;
    }
    if (!tryAcquireAccountAction(initialSession.accountIdentifier)) {
      _publish(
        flowKey,
        PositionActionFlowState(
          runId: runId,
          statusMessage: 'Đang có thao tác khác trên tài khoản này.',
        ),
      );
      return;
    }

    _publish(
      flowKey,
      PositionActionFlowState(
        runId: runId,
        isBusy: true,
        accountIdentifier: initialSession.accountIdentifier,
      ),
    );
    try {
      String? input;
      if (inputKind != null) {
        if (collectInput == null ||
            !_dialogOwnerIsActive(navigator, ownerRoute)) {
          return;
        }
        input = await collectInput();
        if (input == null) return;
        if (!_canContinue(
          flowKey,
          runId,
          initialSession,
          navigator,
          ownerRoute,
        )) {
          return;
        }
        if (!_validInput(inputKind, input)) {
          _setStatus(
            flowKey,
            runId,
            inputKind == 'percentage'
                ? 'Tỷ lệ đóng phải lớn hơn 0 và nhỏ hơn 100.'
                : 'Nhập một giá trị dương hợp lệ.',
          );
          return;
        }
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
      final api = _readApi();
      final prepared = await api.prepare(
        initialSession.bearerToken,
        action: action,
        targetIdentity: identity,
        amount: inputKind == 'amount' ? input : null,
        size: inputKind == 'size' ? input : null,
        percentage: inputKind == 'percentage' ? input : null,
      );
      if (!_canContinue(
        flowKey,
        runId,
        initialSession,
        navigator,
        ownerRoute,
      )) {
        _invalidatePositions();
        return;
      }
      if (!_preparedTargetMatches(prepared, identity)) {
        _invalidatePositions();
        _setStatus(
          flowKey,
          runId,
          'Máy chủ trả về mục tiêu khác hoặc nhiều mục tiêu. Hãy kiểm tra lại vị thế.',
        );
        return;
      }

      final confirmed = await confirm(prepared);
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

      // The unresolved-operation guard is repeated immediately before the
      // write. Another action may have changed session state while this dialog
      // was open.
      final beforeExecute = _readSession();
      if (beforeExecute.pendingOperations.isNotEmpty) {
        _setStatus(
          flowKey,
          runId,
          'Có thao tác chưa rõ kết quả. Tra cứu trạng thái trước khi gửi thao tác mới.',
        );
        return;
      }
      if (!_sessionMatches(initialSession)) {
        _setStatus(
          flowKey,
          runId,
          'Phiên giao dịch đã thay đổi hoặc hết hạn. Hãy đăng nhập lại.',
        );
        return;
      }

      final sessionController = _readSessionController();
      sessionController.rememberOperation(
        PendingTradeOperation(
          operationId: prepared.operationId,
          action: action,
          targetLabel: identity['instrumentId']?.toString() ?? 'Vị thế',
          status: 'IN_PROGRESS',
        ),
      );
      var finalResult = TradeOperationResult(
        operationId: prepared.operationId,
        action: action,
        status: 'UNKNOWN',
        targets: const [],
        updatedAt: '',
      );
      String? lookupError;
      var lookupAttempted = false;
      try {
        finalResult = await api.execute(
          initialSession.bearerToken,
          operationId: prepared.operationId,
          confirmationToken: prepared.confirmationToken,
        );
      } on TradeApiException catch (error) {
        if (error.isUnauthorized ||
            (error.statusCode != null && error.statusCode! < 500)) {
          sessionController.resolveOperation(prepared.operationId);
          rethrow;
        }
        // The server may have accepted the write before a network failure.
        // Reconcile by operation ID and never resend execute.
        lookupAttempted = true;
        try {
          finalResult = await api.getResult(
            initialSession.bearerToken,
            prepared.operationId,
          );
        } on TradeApiException catch (lookupFailure) {
          lookupError = lookupFailure.message;
          if (lookupFailure.isUnauthorized) sessionController.expire();
        }
      }
      if (!lookupAttempted && tradeOperationNeedsStatusLookup(finalResult)) {
        lookupAttempted = true;
        try {
          finalResult = await api.getResult(
            initialSession.bearerToken,
            finalResult.operationId,
          );
        } on TradeApiException catch (error) {
          lookupError ??= error.message;
          if (error.isUnauthorized) sessionController.expire();
        }
      }
      if (tradeOperationNeedsStatusLookup(finalResult)) {
        sessionController.updateOperation(
          PendingTradeOperation(
            operationId: finalResult.operationId,
            action: action,
            targetLabel: identity['instrumentId']?.toString() ?? 'Vị thế',
            status: finalResult.status,
          ),
        );
      } else {
        sessionController.resolveOperation(prepared.operationId);
      }
      _invalidatePositions();
      _setStatus(
        flowKey,
        runId,
        _resultHeadline(finalResult.status, finalResult.operationId),
      );
      if (_dialogOwnerIsActive(navigator, ownerRoute)) {
        await showResult(finalResult, lookupError: lookupError);
      }
    } on TradeApiException catch (error) {
      if (error.isUnauthorized) _readSessionController().expire();
      if (error.isStale || error.statusCode == 409) _invalidatePositions();
      _setStatus(flowKey, runId, error.message);
    } catch (_) {
      _setStatus(
        flowKey,
        runId,
        'Thao tác chưa xác nhận được. Kiểm tra trạng thái trước khi thử lại.',
      );
    } finally {
      releaseAccountAction(initialSession.accountIdentifier);
      final currentFlow = state[flowKey];
      if (currentFlow?.runId == runId) {
        _publish(
          flowKey,
          PositionActionFlowState(
            runId: runId,
            statusMessage: currentFlow?.statusMessage,
            accountIdentifier: currentFlow?.accountIdentifier,
          ),
        );
      }
    }
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

  bool _sessionMatches(TradeSession expectedSession) {
    final current = _readSession().session;
    if (current == null ||
        current.bearerToken != expectedSession.bearerToken ||
        current.accountIdentifier != expectedSession.accountIdentifier) {
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
  ) {
    return navigator.mounted && (ownerRoute == null || ownerRoute.isActive);
  }

  bool _validInput(String kind, String value) {
    final parsed = double.tryParse(value);
    if (parsed == null || !parsed.isFinite || parsed <= 0) return false;
    if (kind == 'percentage' && parsed >= 100) return false;
    return true;
  }

  bool _preparedTargetMatches(
    PreparedTradeAction prepared,
    Map<String, dynamic> selectedIdentity,
  ) {
    if (prepared.targets.length != 1 || prepared.summary['targetCount'] != 1) {
      return false;
    }
    final preparedIdentity = tradeJsonMap(prepared.targets.single['identity']);
    for (final entry in selectedIdentity.entries) {
      if (preparedIdentity[entry.key]?.toString() != entry.value?.toString()) {
        return false;
      }
    }
    return selectedIdentity.isNotEmpty;
  }

  String _resultHeadline(String status, String operationId) {
    return switch (status) {
      'SUCCEEDED' => 'Đã hoàn tất thao tác',
      'PARTIAL' => 'Thao tác chỉ hoàn tất một phần',
      'UNKNOWN' => 'Chưa rõ kết quả thao tác',
      'CONFLICT' => 'Vị thế đã thay đổi trước khi xác nhận',
      'FAILED' => 'Thao tác thất bại',
      'EXPIRED' => 'Xác nhận đã hết hạn',
      _ => 'Trạng thái $status · $operationId',
    };
  }

  void _setStatus(String key, int runId, String message) {
    final current = state[key];
    if (current?.runId != runId) return;
    _publish(
      key,
      PositionActionFlowState(
        runId: runId,
        isBusy: current!.isBusy,
        statusMessage: message,
        accountIdentifier: current.accountIdentifier,
      ),
    );
  }

  void _publish(String key, PositionActionFlowState value) {
    state = {...state, key: value};
  }
}

Object? _canonicalJsonValue(Object? value) {
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort(
        (left, right) => left.key.toString().compareTo(right.key.toString()),
      );
    return {
      for (final entry in entries)
        entry.key.toString(): _canonicalJsonValue(entry.value),
    };
  }
  if (value is List) {
    return value.map(_canonicalJsonValue).toList(growable: false);
  }
  return value;
}
