import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../security/secure_storage_helper.dart';
import 'backend_data_client.dart';
import 'foreground_read_gate.dart';
import 'okx_data_client.dart';
import 'request_coordinator.dart';

/// Exposes only the secret-free OKX credential generation to Riverpod.
class OkxCredentialReadScope extends ChangeNotifier {
  OkxCredentialReadScope(this._state) {
    _state.addListener(_notifyChanged);
  }

  final ValueListenable<OkxCredentialSnapshot> _state;

  OkxCredentialSnapshot get snapshot => _state.value;

  void _notifyChanged() => notifyListeners();

  @override
  void dispose() {
    _state.removeListener(_notifyChanged);
    super.dispose();
  }
}

final okxCredentialReadScopeProvider =
    ChangeNotifierProvider<OkxCredentialReadScope>((ref) {
      final storage = ref.watch(secureStorageProvider);
      return OkxCredentialReadScope(storage.okxCredentialState);
    });

final okxCredentialSnapshotProvider = Provider<OkxCredentialSnapshot>((ref) {
  return ref.watch(
    okxCredentialReadScopeProvider.select((scope) => scope.snapshot),
  );
});

/// Separate scope from backend-session reads; it shares neither gate identity
/// nor generation with TradeAccountControls or backend action preflights.
final okxDirectReadGateProvider = Provider<ForegroundReadGate>((ref) {
  final gate = ForegroundReadGate();
  ref.onDispose(gate.dispose);
  return gate;
});

/// Acquires a direct private-read lease fenced by the current local OKX
/// credential generation. OkxDataClient owns authenticated-lane scheduling.
Future<T> runOkxPrivateRead<T>({
  required Ref ref,
  required String requestKey,
  required Future<T> Function(CancelToken cancelToken) load,
}) async {
  final snapshot = ref.watch(okxCredentialSnapshotProvider);
  final storage = ref.read(secureStorageProvider);
  if (snapshot.rotating) {
    throw const OkxDataException(
      code: 'okx_credentials_rotating',
      message: 'OKX credentials are being updated. Try again shortly.',
    );
  }

  final gate = ref.read(okxDirectReadGateProvider);
  var callerActive = true;
  final lease = gate.acquire<T>(
    sessionIdentity: storage,
    generation: snapshot.generation,
    requestKey: requestKey,
    canStart: () =>
        callerActive &&
        !snapshot.rotating &&
        storage.okxCredentialState.value == snapshot,
    load: load,
    isTransientFailure: isTransientOkxReadFailure,
    isCancellationFailure: isOkxReadCancellation,
    retryAfter: okxReadRetryAfter,
  );
  ref.onDispose(() {
    callerActive = false;
    lease.release();
  });
  return await lease.future;
}

bool isTransientOkxReadFailure(Object error) {
  if (error is RequestBackoffException) return true;
  if (error is BackendDataException) {
    final status = error.statusCode;
    if (status == 429 || status == 408 || status == 425) return true;
    if (status != null) return status >= 500;
    return error.code == 'okx_network_error' || error.code == 'network_error';
  }
  if (error is DioException) {
    if (error.type == DioExceptionType.cancel) return false;
    final status = error.response?.statusCode;
    if (status == 429 || status == 408 || status == 425) return true;
    if (status != null) return status >= 500;
    return const {
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.connectionError,
    }.contains(error.type);
  }
  return false;
}

bool isOkxReadCancellation(Object error) => switch (error) {
  ForegroundReadCancelled() => true,
  BackendDataException(code: 'request_cancelled') => true,
  DioException(type: DioExceptionType.cancel) => true,
  _ => false,
};

Duration? okxReadRetryAfter(Object error, DateTime now) {
  if (error is RequestBackoffException) {
    final retryAfter = error.retryAfter;
    if (retryAfter != null) {
      return retryAfter.isNegative ? Duration.zero : retryAfter;
    }
    final remaining = error.retryAt.difference(now.toUtc());
    return remaining.isNegative ? Duration.zero : remaining;
  }
  if (error is BackendDataException) {
    return ForegroundReadGate.parseRetryAfter(error.retryAfter, now);
  }
  if (error is DioException) {
    return ForegroundReadGate.parseRetryAfter(
      error.response?.headers.value('retry-after'),
      now,
    );
  }
  return null;
}

bool isTerminalOkxReadFailure(Object? error) {
  if (error == null) return false;
  if (error is BackendDataException &&
      (error.statusCode == 401 || error.statusCode == 403)) {
    return true;
  }
  return error is BackendDataException &&
      const {
        'okx_credentials_rotating',
        'credentials_changed',
        'okx_credentials_required',
        'okx_authentication_failed',
        'okx_timestamp_invalid',
      }.contains(error.code);
}
