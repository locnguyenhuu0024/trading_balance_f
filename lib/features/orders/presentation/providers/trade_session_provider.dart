import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/trade_api_client.dart';

final tradeApiProvider = Provider<TradeApi>((ref) => TradeApiClient());

final tradeSessionProvider =
    StateNotifierProvider<TradeSessionController, TradeSessionState>((ref) {
      final controller = TradeSessionController(ref.watch(tradeApiProvider));
      unawaited(controller.restore());
      return controller;
    });

final tradePositionsProvider =
    FutureProvider.autoDispose<TradePositionsSnapshot>((ref) async {
      final session = ref.watch(tradeSessionProvider).session;
      if (session == null) {
        throw const TradeApiException(
          code: 'authentication_required',
          message: 'Sign in to load positions owned by the trade API.',
        );
      }
      if (!session.isActive) {
        ref.read(tradeSessionProvider.notifier).expire();
        throw const TradeApiException(
          code: 'authentication_required',
          message:
              'The trade API session expired. Sign in again to enable actions.',
        );
      }
      try {
        return await ref
            .read(tradeApiProvider)
            .getPositions(session.bearerToken);
      } on TradeApiException catch (error) {
        if (error.isUnauthorized) {
          ref.read(tradeSessionProvider.notifier).expire();
        }
        rethrow;
      }
    });

class TradeSessionState {
  const TradeSessionState({
    this.session,
    this.isLoading = false,
    this.errorMessage,
    this.pendingOperations = const [],
    this.operationAccountIdentifier,
  });

  final TradeSession? session;
  final bool isLoading;
  final String? errorMessage;
  final List<PendingTradeOperation> pendingOperations;
  final String? operationAccountIdentifier;

  bool get isAuthenticated => !isLoading && (session?.isActive ?? false);
}

class PendingTradeOperation {
  const PendingTradeOperation({
    required this.operationId,
    required this.action,
    required this.targetLabel,
    required this.status,
  });

  final String operationId;
  final String action;
  final String targetLabel;
  final String status;
}

bool tradeOperationNeedsStatusLookup(TradeOperationResult result) {
  if (const {
    'UNKNOWN',
    'IN_PROGRESS',
    'PENDING',
    'ATTEMPT_STARTED',
  }.contains(result.status)) {
    return true;
  }
  if (result.status != 'PARTIAL') return false;
  if (result.targets.isEmpty) return true;

  for (final target in result.targets) {
    final status = (target['status'] ?? '').toString().toUpperCase();
    if (const {'UNKNOWN', 'ATTEMPT_STARTED', 'PENDING'}.contains(status)) {
      return true;
    }
    if (status == 'PARTIAL') {
      final outcome = tradeJsonMap(target['outcome']);
      final orderState = (outcome['orderState'] ?? '').toString();
      if (!const {
            'canceled',
            'rejected',
            'mmp_canceled',
          }.contains(orderState) ||
          outcome['terminalPartialResolved'] != true ||
          outcome['positionVerified'] != true) {
        return true;
      }
    }
  }
  return false;
}

class TradeSessionController extends StateNotifier<TradeSessionState> {
  TradeSessionController(this._api) : super(const TradeSessionState());

  final TradeApi _api;
  int _sessionOperationGeneration = 0;
  int? _restoringGeneration;
  TradeSession? _logoutInFlightSession;

  Future<bool> restore() async {
    if (!_api.isConfigured ||
        !_api.supportsSessionRestoration ||
        _restoringGeneration != null) {
      return false;
    }

    final generation = ++_sessionOperationGeneration;
    _restoringGeneration = generation;
    final pendingOperations = state.pendingOperations;
    final operationAccountIdentifier = state.operationAccountIdentifier;
    state = TradeSessionState(
      isLoading: true,
      pendingOperations: pendingOperations,
      operationAccountIdentifier: operationAccountIdentifier,
    );
    try {
      final session = await _api.restoreSession();
      if (!mounted || generation != _sessionOperationGeneration) return false;
      if (!session.isActive) {
        state = TradeSessionState(
          errorMessage:
              'The trade API session expired. Sign in again to enable actions.',
          pendingOperations: pendingOperations,
          operationAccountIdentifier: operationAccountIdentifier,
        );
        return false;
      }
      final sameAccount =
          operationAccountIdentifier == null ||
          operationAccountIdentifier == session.accountIdentifier;
      state = TradeSessionState(
        session: session,
        pendingOperations: sameAccount ? pendingOperations : const [],
        operationAccountIdentifier: session.accountIdentifier,
      );
      return true;
    } on TradeApiException catch (error) {
      if (!mounted || generation != _sessionOperationGeneration) return false;
      state = TradeSessionState(
        errorMessage: error.isUnauthorized ? null : error.message,
        pendingOperations: pendingOperations,
        operationAccountIdentifier: operationAccountIdentifier,
      );
      return false;
    } catch (_) {
      if (!mounted || generation != _sessionOperationGeneration) return false;
      state = TradeSessionState(
        errorMessage: 'The trade API session could not be restored.',
        pendingOperations: pendingOperations,
        operationAccountIdentifier: operationAccountIdentifier,
      );
      return false;
    } finally {
      if (_restoringGeneration == generation) _restoringGeneration = null;
    }
  }

  Future<bool> login({required String password, required String totp}) async {
    if (!_api.isConfigured) {
      state = const TradeSessionState(
        errorMessage: 'TRADE_API_BASE_URL is not configured.',
      );
      return false;
    }
    final generation = ++_sessionOperationGeneration;
    _restoringGeneration = null;
    final pendingOperations = state.pendingOperations;
    final operationAccountIdentifier = state.operationAccountIdentifier;
    state = TradeSessionState(
      isLoading: true,
      pendingOperations: pendingOperations,
      operationAccountIdentifier: operationAccountIdentifier,
    );
    try {
      final session = await _api.login(password: password, totp: totp);
      if (!mounted || generation != _sessionOperationGeneration) return false;
      final sameAccount =
          operationAccountIdentifier == null ||
          operationAccountIdentifier == session.accountIdentifier;
      state = TradeSessionState(
        session: session,
        pendingOperations: sameAccount ? pendingOperations : const [],
        operationAccountIdentifier: session.accountIdentifier,
      );
      return true;
    } on TradeApiException catch (error) {
      if (!mounted || generation != _sessionOperationGeneration) return false;
      state = TradeSessionState(
        errorMessage: error.message,
        pendingOperations: pendingOperations,
        operationAccountIdentifier: operationAccountIdentifier,
      );
      return false;
    } catch (_) {
      if (!mounted || generation != _sessionOperationGeneration) return false;
      state = TradeSessionState(
        errorMessage: 'The trade API login could not be completed.',
        pendingOperations: pendingOperations,
        operationAccountIdentifier: operationAccountIdentifier,
      );
      return false;
    }
  }

  Future<bool> logout() async {
    if (_logoutInFlightSession != null) return false;
    final generation = ++_sessionOperationGeneration;
    _restoringGeneration = null;
    final session = state.session;
    final pendingOperations = state.pendingOperations;
    final operationAccountIdentifier = state.operationAccountIdentifier;
    if (session == null) {
      state = TradeSessionState(
        pendingOperations: pendingOperations,
        operationAccountIdentifier: operationAccountIdentifier,
      );
      return true;
    }
    _logoutInFlightSession = session;
    state = TradeSessionState(
      isLoading: true,
      pendingOperations: pendingOperations,
      operationAccountIdentifier: operationAccountIdentifier,
    );
    try {
      await _api.logout(session.bearerToken);
      if (!mounted || generation != _sessionOperationGeneration) return false;
      state = TradeSessionState(
        pendingOperations: pendingOperations,
        operationAccountIdentifier: operationAccountIdentifier,
      );
      return true;
    } on TradeApiException catch (error) {
      if (!mounted || generation != _sessionOperationGeneration) return false;
      state = TradeSessionState(
        session: session,
        errorMessage: 'Could not end the trade session: ${error.message}',
        pendingOperations: pendingOperations,
        operationAccountIdentifier: operationAccountIdentifier,
      );
      return false;
    } catch (_) {
      if (!mounted || generation != _sessionOperationGeneration) return false;
      state = TradeSessionState(
        session: session,
        errorMessage:
            'Could not confirm logout. Check the connection and retry.',
        pendingOperations: pendingOperations,
        operationAccountIdentifier: operationAccountIdentifier,
      );
      return false;
    } finally {
      if (identical(_logoutInFlightSession, session)) {
        _logoutInFlightSession = null;
      }
    }
  }

  void expire() {
    _sessionOperationGeneration++;
    _restoringGeneration = null;
    state = TradeSessionState(
      errorMessage: 'Phiên giao dịch đã hết hạn. Hãy đăng nhập lại.',
      pendingOperations: state.pendingOperations,
      operationAccountIdentifier: state.operationAccountIdentifier,
    );
  }

  void rememberOperation(PendingTradeOperation operation) {
    final operations = [
      ...state.pendingOperations.where(
        (pending) => pending.operationId != operation.operationId,
      ),
      operation,
    ];
    state = TradeSessionState(
      session: state.session,
      isLoading: state.isLoading,
      errorMessage: state.errorMessage,
      pendingOperations: List.unmodifiable(operations),
      operationAccountIdentifier:
          state.operationAccountIdentifier ?? state.session?.accountIdentifier,
    );
  }

  void updateOperation(PendingTradeOperation operation) {
    if (!state.pendingOperations.any(
      (pending) => pending.operationId == operation.operationId,
    )) {
      return;
    }
    rememberOperation(operation);
  }

  void resolveOperation(String operationId) {
    if (!state.pendingOperations.any(
      (pending) => pending.operationId == operationId,
    )) {
      return;
    }
    state = TradeSessionState(
      session: state.session,
      isLoading: state.isLoading,
      errorMessage: state.errorMessage,
      pendingOperations: List.unmodifiable(
        state.pendingOperations.where(
          (pending) => pending.operationId != operationId,
        ),
      ),
      operationAccountIdentifier:
          state.operationAccountIdentifier ?? state.session?.accountIdentifier,
    );
  }

  void clearError() {
    if (state.errorMessage == null) return;
    state = TradeSessionState(
      session: state.session,
      isLoading: state.isLoading,
      pendingOperations: state.pendingOperations,
      operationAccountIdentifier: state.operationAccountIdentifier,
    );
  }
}
