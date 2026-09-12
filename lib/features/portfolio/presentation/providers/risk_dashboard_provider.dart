import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/risk_monitor_bridge.dart';

/// The presentation layer depends on the typed monitor protocol.  Production
/// wiring can override this provider with the foreground owner (and the later
/// Android owner); the in-memory owner keeps previews and widget tests
/// deterministic without starting a platform service.
final riskMonitorOwnerProvider = Provider<RiskMonitorOwner>((ref) {
  final owner = InMemoryRiskMonitorOwner();
  ref.onDispose(owner.dispose);
  return owner;
});

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
