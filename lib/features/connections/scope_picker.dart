import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/exchange/exchange_scope.dart';
import '../../core/widgets/scope_bar.dart';

class ScopePicker extends ConsumerWidget {
  const ScopePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configured = ref.watch(configuredConnectionsProvider);
    final selected = ref.watch(exchangeScopeProvider).connectionId;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Chọn sàn & tài khoản',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            ...configured.valueOrNull?.map((entry) {
                  final active = entry.profile.connectionId == selected;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: active
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).dividerColor,
                        width: active ? 2 : 1,
                      ),
                    ),
                    child: ListTile(
                      title: Text('${entry.profile.label} / Chính'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(scopeProductLine(entry.profile.exchange)),
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
            const ListTile(title: Text('Quản lý kết nối')),
          ],
        ),
      ),
    );
  }
}
