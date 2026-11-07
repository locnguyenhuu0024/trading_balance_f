import '../../core/widgets/scope_bar.dart';
import 'package:flutter/material.dart';

import '../../core/navigation/navigation_content_frame.dart';
import '../../core/theme/app_theme.dart';
import '../fractal_tracker/presentation/fractal_screen.dart';
import '../settings/presentation/settings_screen.dart';
import '../connections/connections_screen.dart';
import '../support_resistance/presentation/support_resistance_screen.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NavigationContentFrame(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Công cụ',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const ScopeBar(),
            const SizedBox(height: 12),
            _ToolCard(
              icon: Icons.donut_small_outlined,
              title: 'BMAG',
              subtitle: 'Fractal theo nguồn giá của sàn',
              destination: (_) => const FractalScreen(),
            ),
            _ToolCard(
              icon: Icons.stacked_line_chart_outlined,
              title: 'Hỗ trợ / kháng cự',
              subtitle: 'Coin theo dõi riêng theo sàn',
              destination: (_) => const SupportResistanceScreen(),
            ),
            _ToolCard(
              icon: Icons.key_outlined,
              title: 'Sàn & tài khoản',
              subtitle: 'Thêm, đổi hoặc quản lý kết nối',
              destination: (_) => const ConnectionsScreen(),
            ),
            _ToolCard(
              icon: Icons.settings_outlined,
              title: 'Cài đặt',
              subtitle: 'Hiển thị, tiền tệ, múi giờ',
              destination: (_) => const SettingsScreen(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.destination,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final WidgetBuilder destination;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.border),
      ),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: TextStyle(color: palette.muted)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () {
          Navigator.of(
            context,
          ).push<void>(MaterialPageRoute<void>(builder: destination));
        },
      ),
    );
  }
}
