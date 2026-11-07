import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/foreground_read_gate.dart';
import 'exchange_models.dart';
import 'exchange_registry.dart';

/// Acquires a lease whose owner releases it when the provider is disposed.
Future<T> runPrivateRead<T>({
  required Ref ref,
  required ForegroundReadGate gate,
  required Object sessionIdentity,
  required int generation,
  required String requestKey,
  required bool Function() canStart,
  required Future<T> Function(CancelToken) load,
  required ExchangeFailure Function(Object) classify,
  Duration? Function(Object, DateTime)? retryAfter,
}) async {
  var active = true;
  final lease = gate.acquire<T>(
    sessionIdentity: sessionIdentity,
    generation: generation,
    requestKey: requestKey,
    canStart: () => active && canStart(),
    load: load,
    isTransientFailure: (error) =>
        classify(error).kind == ExchangeFailureKind.transient,
    isCancellationFailure: (error) =>
        classify(error).kind == ExchangeFailureKind.cancellation,
    retryAfter: retryAfter ?? (error, now) => classify(error).retryAfter,
  );
  ref.onDispose(() {
    active = false;
    lease.release();
  });
  return lease.future;
}

ExchangeRegistration _registration(Ref ref, ExchangeScope scope) => ref
    .watch(exchangeRegistryProvider)
    .firstWhere(
      (entry) =>
          entry.profile.connectionId == scope.connectionId &&
          entry.profile.exchange == scope.exchange,
    );
final scopedAccountProvider = FutureProvider.autoDispose
    .family<AccountSnapshot, ExchangeScope>(
      (ref, scope) => _registration(ref, scope).adapter.readAccount(ref, scope),
    );
final scopedPositionsProvider = FutureProvider.autoDispose
    .family<List<ExchangePosition>, ExchangeScope>(
      (ref, scope) =>
          _registration(ref, scope).adapter.readPositions(ref, scope),
    );
final scopedOrdersProvider = FutureProvider.autoDispose
    .family<List<ExchangeOrder>, ExchangeScope>(
      (ref, scope) => _registration(ref, scope).adapter.readOrders(ref, scope),
    );
