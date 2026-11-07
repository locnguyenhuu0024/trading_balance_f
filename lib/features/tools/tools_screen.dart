import '../../core/widgets/scope_bar.dart';
import 'package:flutter/material.dart';

import '../../core/navigation/navigation_content_frame.dart';
import '../fractal_tracker/presentation/fractal_screen.dart';
import '../settings/presentation/settings_screen.dart';
import '../connections/connections_screen.dart';
import '../support_resistance/presentation/support_resistance_screen.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Công cụ')),
      body: NavigationContentFrame(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const ScopeBar(),
            const SizedBox(height: 12),
            _ToolCard(
              icon: Icons.donut_small_outlined,
              title: 'BMAG',
              destination: (_) => const FractalScreen(),
            ),
            _ToolCard(
              icon: Icons.stacked_line_chart_outlined,
              title: 'Hỗ trợ / kháng cự',
              destination: (_) => const SupportResistanceScreen(),
            ),
            _ToolCard(
              icon: Icons.key_outlined,
              title: 'Sàn & tài khoản',
              destination: (_) => const ConnectionsScreen(),
            ),
            _ToolCard(
              icon: Icons.settings_outlined,
              title: 'Cài đặt',
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
    required this.destination,
  });

  final IconData icon;
  final String title;
  final WidgetBuilder destination;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
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
