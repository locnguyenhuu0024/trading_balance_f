import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/exchange/exchange_scope.dart';
import '../../core/exchange/scoped_read.dart';
import '../../core/network/okx_read_scope.dart';
import '../../core/widgets/scope_bar.dart';
import '../../core/theme/app_theme.dart';

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
    final palette = AppPalette.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Đang đổi tài khoản',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const ScopeBar(),
            const SizedBox(height: 64),
            Center(
              child: reducedMotion
                  ? const Icon(Icons.hourglass_empty)
                  : const CircularProgressIndicator(),
            ),
            const SizedBox(height: 64),
            Semantics(
              liveRegion: true,
              child: Text(
                'Đang tải $name / Chính',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Ẩn dữ liệu tài khoản cũ trong khi tải.',
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.muted),
            ),
          ],
        ),
      ),
    );
  }
}
