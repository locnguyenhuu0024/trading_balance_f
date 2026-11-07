import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/exchange/exchange_models.dart';
import '../../core/exchange/exchange_scope.dart';
import '../../core/widgets/scope_bar.dart';
import '../settings/presentation/settings_trade_access_page.dart';
import 'binance_connection_form.dart';
import 'connection_catalog_screen.dart';

Widget connectionForm(ExchangeId exchange) => exchange == ExchangeId.okx
    ? const SettingsTradeAccessPage()
    : const BinanceConnectionForm();

class ConnectionsScreen extends ConsumerWidget {
  const ConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connections = ref.watch(configuredConnectionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Sàn & tài khoản')),
      body: connections.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Không thể tải kết nối')),
        data: (entries) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final entry in entries)
              Card(
                child: ListTile(
                  title: Text('${entry.profile.label} / Chính'),
                  subtitle: Text(
                    '${scopeProductLine(entry.profile.exchange)}\nĐã kết nối',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => connectionForm(entry.profile.exchange),
                    ),
                  ),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ConnectionCatalogScreen(),
                ),
              ),
              child: const Text('+ Thêm kết nối'),
            ),
          ],
        ),
      ),
    );
  }
}
