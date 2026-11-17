import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
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

class BinanceCredentialReadScope extends ChangeNotifier {
  BinanceCredentialReadScope(this.state) {
    state.addListener(_changed);
  }
  final ValueListenable<OkxCredentialSnapshot> state;
  void _changed() => notifyListeners();
  @override
  void dispose() {
    state.removeListener(_changed);
    super.dispose();
  }
}

final binanceCredentialReadScopeProvider =
    ChangeNotifierProvider<BinanceCredentialReadScope>(
      (ref) => BinanceCredentialReadScope(
        ref.watch(secureStorageProvider).binanceCredentialState,
      ),
    );

/// Connections with complete credentials, in registry order.
final configuredConnectionsProvider =
    FutureProvider<List<ExchangeRegistration>>((ref) async {
      ref.watch(okxCredentialSnapshotProvider);
      ref.watch(binanceCredentialReadScopeProvider).state.value;
      final storage = ref.watch(secureStorageProvider);
      final registry = ref.watch(exchangeRegistryProvider);
      final okx = await Future.wait([
        storage.getOkxApiKey(),
        storage.getOkxSecretKey(),
        storage.getOkxPassphrase(),
      ]);
      final binance = await Future.wait([
        storage.getBinanceApiKey(),
        storage.getBinanceApiSecret(),
      ]);
      bool complete(List<String?> keys) =>
          keys.every((key) => key != null && key.trim().isNotEmpty);
      return registry
          .where(
            (entry) => entry.profile.exchange == ExchangeId.okx
                ? complete(okx)
                : complete(binance),
          )
          .toList();
    });

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
      : ref.watch(binanceCredentialReadScopeProvider).state.value.generation;
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
