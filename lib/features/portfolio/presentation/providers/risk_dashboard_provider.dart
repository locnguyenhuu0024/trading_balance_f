import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/security/secure_storage_helper.dart';
import '../../application/risk_monitor_bridge.dart';
import '../../application/risk_monitor.dart';
import '../../application/risk_monitor_runtime.dart';
import '../../application/risk_notification_sink.dart';
import '../../data/risk/risk_local_store.dart';
import '../../data/risk/risk_market_repository.dart';
import '../../data/risk/risk_repository.dart';
import '../../data/risk/risk_request_coordinator.dart';

/// The presentation layer depends on the typed monitor protocol.  Production
/// wiring can override this provider with the foreground owner (and the later
/// Android owner); the in-memory owner keeps previews and widget tests
/// deterministic without starting a platform service.
final riskMonitorOwnerProvider = Provider<RiskMonitorOwner>((ref) {
  final repository = ref.watch(riskRepositoryProvider);
  final marketDio = Dio(
    BaseOptions(
      baseUrl: kIsWeb ? '' : 'https://www.okx.com',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: const <String, Object>{'Content-Type': 'application/json'},
    ),
  );
  final monitor = RiskMonitor.fromRepositories(
    repository: repository,
    marketRepository: RiskMarketRepository(
      marketDio,
      requestCoordinator: ref.watch(riskRequestCoordinatorProvider),
    ),
    store: RiskLocalStore(storage: DeferredSharedPreferencesRiskStorage()),
    notificationSink: kIsWeb
        ? const InAppRiskNotificationSink()
        : FlutterLocalRiskNotificationSink(),
  );
  final runtime = RiskMonitorRuntime(
    monitor: monitor,
    platform: kIsWeb
        ? const DefaultRiskRuntimePlatformAdapter()
        : FlutterBackgroundRiskRuntimeAdapter(),
    credentialChanges: CredentialMutationBus.changes,
  );
  ref.onDispose(runtime.dispose);
  return runtime;
});

/// Keeps the provider synchronous while using the already-approved
/// SharedPreferences storage asynchronously. It is safe for Web because it
/// never touches native plugins.
class DeferredSharedPreferencesRiskStorage implements RiskKeyValueStore {
  DeferredSharedPreferencesRiskStorage()
    : _preferences = SharedPreferences.getInstance();

  final Future<SharedPreferences> _preferences;

  @override
  Future<String?> getString(String key) async =>
      (await _preferences).getString(key);

  @override
  Future<bool> setString(String key, String value) async =>
      (await _preferences).setString(key, value);

  @override
  Future<bool> remove(String key) async => (await _preferences).remove(key);

  @override
  Future<Set<String>> getKeys() async => (await _preferences).getKeys();
}

final riskMonitorBridgeProvider = Provider<RiskMonitorBridge>((ref) {
  return RiskMonitorBridge(ref.watch(riskMonitorOwnerProvider));
});

/// Emits the current state immediately, then forwards every state published by
/// the owner.  This makes the first frame useful even before a monitor start
/// acknowledgement arrives.
final riskMonitorViewStateProvider =
    StreamProvider.autoDispose<RiskMonitorViewState>((ref) async* {
      final bridge = ref.watch(riskMonitorBridgeProvider);
      yield bridge.currentState;
      yield* bridge.states;
    });

/// Name used by presentation callers that think in terms of the dashboard.
final riskDashboardStateProvider = riskMonitorViewStateProvider;

String riskCommandId(String prefix) {
  final now = DateTime.now().toUtc().microsecondsSinceEpoch;
  return '$prefix-$now';
}
