import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/exchange/exchange_scope.dart';
import '../../core/exchange/scoped_read.dart';
import '../../core/network/okx_read_scope.dart';
import '../../core/widgets/scope_bar.dart';

class ScopeSwitchGate extends ConsumerWidget {
  const ScopeSwitchGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(exchangeScopeProvider);
    final configured = ref.watch(configuredConnectionsProvider);
    final entries = configured.valueOrNull;
    final rotating =
        ref.watch(okxCredentialSnapshotProvider).rotating ||
        ref.watch(binanceCredentialReadScopeProvider).state.value.rotating;
    if (!rotating &&
        entries != null &&
        !entries.any(
          (entry) => entry.profile.connectionId == scope.connectionId,
        )) {
      final fallback = entries.isEmpty
          ? defaultConnectionId
          : entries.first.profile.connectionId;
      if (fallback != scope.connectionId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted &&
              ref.read(exchangeScopeProvider).connectionId ==
                  scope.connectionId) {
            ref.read(selectConnectionProvider)(fallback);
          }
        });
      }
    }
    if (scope.switchEpoch == 0) return child;
    final account = ref.watch(scopedAccountProvider(scope));
    if (!account.isLoading || account.hasValue) return child;
    final name = scope.exchange.name == 'okx' ? 'OKX' : 'Binance';
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return SafeArea(
      child: Column(
        children: [
          const Padding(padding: EdgeInsets.all(16), child: ScopeBar()),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text('Đang tải $name / Chính'),
                  ),
                  const SizedBox(height: 16),
                  if (reducedMotion)
                    const Icon(Icons.hourglass_empty)
                  else
                    const CircularProgressIndicator(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
