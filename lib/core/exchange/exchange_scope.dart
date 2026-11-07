import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/foreground_read_gate.dart';
import '../network/okx_read_scope.dart';
import '../network/request_coordinator.dart';
import '../security/secure_storage_helper.dart';
import 'exchange_models.dart';
import 'exchange_registry.dart';

const defaultConnectionId = 'okx-default';
final selectedConnectionIdProvider = StateProvider<String>(
  (ref) => defaultConnectionId,
);
final switchEpochProvider = StateProvider<int>((ref) => 0);

/// A callback provider makes the same switch operation available to widgets
/// and provider consumers.
final selectConnectionProvider = Provider<void Function(String)>((ref) {
  var writes = Future<void>.value();
  return (id) {
    final registry = ref.read(exchangeRegistryProvider);
    final selected = registry.any((entry) => entry.profile.connectionId == id)
        ? id
        : defaultConnectionId;
    ref.read(selectedConnectionIdProvider.notifier).state = selected;
    ref.read(switchEpochProvider.notifier).state++;
    final storage = ref.read(secureStorageProvider);
    writes = writes
        .then((_) => storage.saveSelectedConnectionId(selected))
        .catchError((Object _) {});
    for (final entry in registry) {
      entry.adapter.invalidateAccount(ref.invalidate);
      entry.adapter.invalidatePositions(ref.invalidate);
      entry.adapter.invalidateOrders(ref.invalidate);
    }
  };
});

void selectConnection(WidgetRef ref, String id) =>
    ref.read(selectConnectionProvider)(id);

final exchangeScopeProvider = Provider<ExchangeScope>((ref) {
  final id = ref.watch(selectedConnectionIdProvider);
  final registry = ref.watch(exchangeRegistryProvider);
  final registration =
      registry.where((entry) => entry.profile.connectionId == id).firstOrNull ??
      registry.firstWhere(
        (entry) => entry.profile.connectionId == defaultConnectionId,
      );
  final generation = registration.profile.exchange == ExchangeId.okx
      ? ref.watch(okxCredentialSnapshotProvider).generation
      : 0;
  return ExchangeScope(
    connectionId: registration.profile.connectionId,
    exchange: registration.profile.exchange,
    credentialGeneration: generation,
    switchEpoch: ref.watch(switchEpochProvider),
  );
});

final exchangeRequestCoordinatorProvider =
    Provider.family<RequestCoordinator, ExchangeId>((ref, id) {
      if (id == ExchangeId.okx) return ref.watch(requestCoordinatorProvider);
      return RequestCoordinator();
    });
final exchangeReadGateProvider =
    Provider.family<ForegroundReadGate, ExchangeId>((ref, id) {
      if (id == ExchangeId.okx) return ref.watch(okxDirectReadGateProvider);
      final gate = ForegroundReadGate();
      ref.onDispose(gate.dispose);
      return gate;
    });
