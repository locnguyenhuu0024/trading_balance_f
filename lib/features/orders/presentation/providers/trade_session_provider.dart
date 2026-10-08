import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/backend_data_client.dart';
import '../../../../core/network/backend_data_session.dart';
import '../../../../core/network/foreground_read_gate.dart';
import '../../data/trade_api_client.dart';

final tradeApiProvider = Provider<TradeApi>((ref) => TradeApiClient());

final foregroundReadGateProvider = Provider<ForegroundReadGate>((ref) {
  final gate = ForegroundReadGate();
  ref.onDispose(gate.dispose);
  return gate;
});

final tradeSessionProvider =
    StateNotifierProvider<TradeSessionController, TradeSessionState>((ref) {
      final controller = TradeSessionController(ref.watch(tradeApiProvider));
      unawaited(controller.restore());
      return controller;
    });

/// Shared in-memory identity for foreground and later native data clients.
final backendDataSessionProvider = ChangeNotifierProvider<BackendDataSession>((
  ref,
) {
  final initialState = ref.read(tradeSessionProvider);
  final session = BackendDataSession(initialSession: initialState.session);
  ref.listen<TradeSessionState>(tradeSessionProvider, (previous, next) {
    session.update(next.session);
  });
  return session;
});

/// Production data client. A stale 401 cannot expire a newer foreground
/// session because both the shared generation and controller session are
/// checked before clearing it.
final backendDataClientProvider = Provider<BackendDataClient>((ref) {
  final client = BackendDataClient(
    onUnauthorized: (session, generation, expectedSession) {
      final sharedSession = ref.read(backendDataSessionProvider);
      if (!identical(sharedSession, session) ||
          !sharedSession.matches(generation, expectedSession)) {
        return;
      }
      final foregroundSession = ref.read(tradeSessionProvider).session;
      if (!_sameTradeSession(foregroundSession, expectedSession)) return;
      ref.read(tradeSessionProvider.notifier).expire();
    },
  );
  ref.onDispose(() => client.close(force: true));
  return client;
});

final tradePositionsProvider =
    FutureProvider.autoDispose<TradePositionsSnapshot>((ref) async {
      final isSessionLoading = ref.watch(
        tradeSessionProvider.select((state) => state.isLoading),
      );
      final sessionGeneration = ref.watch(
        backendDataSessionProvider.select((session) => session.generation),
      );
      final backendSession = ref.read(backendDataSessionProvider);
      final session = backendSession.current;
      if (isSessionLoading) {
        throw const TradeApiException(
          code: 'session_loading',
          message: 'Đang kiểm tra phiên giao dịch. Vui lòng đợi một chút.',
        );
      }
      if (session == null) {
        throw const TradeApiException(
          code: 'authentication_required',
          message: 'Vui lòng đăng nhập để xem vị thế giao dịch.',
        );
      }
      final generation = sessionGeneration;
      final api = ref.read(tradeApiProvider);
      final gate = ref.read(foregroundReadGateProvider);
      var callerActive = true;
      final lease = gate.acquire<TradePositionsSnapshot>(
        sessionIdentity: backendSession,
        generation: generation,
        requestKey: 'orders/positions/authenticated',
        canStart: () =>
            callerActive &&
            !ref.read(tradeSessionProvider).isLoading &&
            backendSession.matches(generation, session),
        load: (cancelToken) => api is CancellableTradePositionsApi
            ? (api as CancellableTradePositionsApi).getPositionsCancellable(
                session.bearerToken,
                cancelToken: cancelToken,
              )
            : api.getPositions(session.bearerToken),
        isTransientFailure: isTransientForegroundReadFailure,
        isCancellationFailure: isForegroundReadCancellation,
        retryAfter: foregroundReadRetryAfter,
      );
      ref.onDispose(() {
        callerActive = false;
        lease.release();
      });
      try {
        final snapshot = await lease.future;
        if (!backendSession.matches(generation, session)) {
          throw const BackendDataException(
            code: 'session_changed',
            message: 'Phiên giao dịch đã thay đổi. Hãy tải lại dữ liệu.',
            statusCode: 401,
          );
        }
        return snapshot;
      } on TradeApiException catch (error) {
        if (callerActive &&
            error.isUnauthorized &&
            backendSession.matches(generation, session) &&
            _sameTradeSession(
              ref.read(tradeSessionProvider).session,
              session,
            )) {
          ref.read(tradeSessionProvider.notifier).expire();
        }
        rethrow;
      }
    });

bool isTransientForegroundReadFailure(Object error) {
  final statusCode = switch (error) {
    BackendDataException(:final statusCode) => statusCode,
    TradeApiException(:final statusCode) => statusCode,
    _ => null,
  };
  if (statusCode == 429 || statusCode == 408 || statusCode == 425) return true;
  if (statusCode != null) return statusCode >= 500;
  return switch (error) {
    BackendDataException(code: 'network_error') => true,
    TradeApiException(code: 'network_error') => true,
    _ => false,
  };
}

bool isForegroundReadCancellation(Object error) => switch (error) {
  BackendDataException(code: 'request_cancelled') => true,
  TradeApiException(code: 'request_cancelled') => true,
  _ => false,
};

bool isTerminalForegroundReadFailure(Object? error) {
  if (error == null) return false;
  final statusCode = switch (error) {
    BackendDataException(:final statusCode) => statusCode,
    TradeApiException(:final statusCode) => statusCode,
    _ => null,
  };
  if (statusCode == 401 || statusCode == 403) return true;
  final code = switch (error) {
    BackendDataException(:final code) => code,
    TradeApiException(:final code) => code,
    _ => null,
  };
  return const {
    'api_not_configured',
    'authentication_required',
    'session_loading',
    'session_changed',
    'session_expired',
    'route_not_registered',
    'destination_forbidden',
    'exchange_credentials_forbidden',
  }.contains(code);
}

Duration? foregroundReadRetryAfter(Object error, DateTime now) {
  return switch (error) {
    BackendDataException(statusCode: 429, :final retryAfter) =>
      ForegroundReadGate.parseRetryAfter(retryAfter, now),
    TradeApiException(statusCode: 429, :final retryAfter) =>
      ForegroundReadGate.parseRetryAfter(retryAfter, now),
    _ => null,
  };
}

bool _sameTradeSession(TradeSession? left, TradeSession right) =>
    left != null &&
    left.bearerToken == right.bearerToken &&
    left.accountIdentifier == right.accountIdentifier &&
    left.expiresAt == right.expiresAt;

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
