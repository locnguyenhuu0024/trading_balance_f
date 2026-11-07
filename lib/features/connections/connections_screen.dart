import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/exchange/exchange_models.dart';
import '../../core/exchange/exchange_scope.dart';
import '../../core/widgets/scope_bar.dart';
import '../../core/theme/app_theme.dart';
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
      body: SafeArea(
        child: connections.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Center(child: Text('Không thể tải kết nối')),
          data: (entries) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  if (Navigator.of(context).canPop()) const BackButton(),
                  const Expanded(
                    child: Text(
                      'Sàn & tài khoản',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              for (final entry in entries)
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: AppPalette.forBrightness(
                        Theme.of(context).brightness == Brightness.dark,
                      ).border,
                    ),
                  ),
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
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: AppPalette.forBrightness(
                    Theme.of(context).brightness == Brightness.dark,
                  ).ink,
                  foregroundColor: AppPalette.forBrightness(
                    Theme.of(context).brightness == Brightness.dark,
                  ).onStrong,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
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
      ),
    );
  }
}
