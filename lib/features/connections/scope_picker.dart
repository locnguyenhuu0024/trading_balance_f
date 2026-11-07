import '../../exchanges/binance/binance_adapter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/exchange/exchange_scope.dart';
import '../../core/widgets/scope_bar.dart';
import '../../core/theme/app_theme.dart';
import 'connections_screen.dart';

class ScopePicker extends ConsumerWidget {
  const ScopePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configured = ref.watch(configuredConnectionsProvider);
    final selected = ref.watch(exchangeScopeProvider).connectionId;
    final palette = AppPalette.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Chọn sàn & tài khoản',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Chỉ hiển thị một tài khoản mỗi lần.',
                style: TextStyle(color: palette.muted),
              ),
              const SizedBox(height: 24),
              ...configured.valueOrNull?.map((entry) {
                    final active = entry.profile.connectionId == selected;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: active ? palette.ink : palette.border,
                        ),
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: palette.ink,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            entry.profile.label.substring(0, 1),
                            style: TextStyle(
                              color: palette.onStrong,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          '${entry.profile.label} / Chính',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              scopeProductLine(
                                entry.profile.exchange,
                                ref.watch(binanceSpotMarginAvailableProvider),
                              ),
                            ),
                            Text(
                              active ? 'Đang xem' : 'Chuyển sang tài khoản này',
                            ),
                          ],
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          if (!active)
                            ref.read(selectConnectionProvider)(
                              entry.profile.connectionId,
                            );
                        },
                      ),
                    );
                  }) ??
                  [],
              OutlinedButton(
                child: const Text('Quản lý kết nối'),
                onPressed: () {
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  navigator.push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ConnectionsScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
