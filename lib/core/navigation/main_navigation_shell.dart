import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/fractal_tracker/presentation/fractal_screen.dart';
import '../../features/market/presentation/market_screen.dart';
import '../../features/orders/presentation/orders_screen.dart';
import '../../features/portfolio/presentation/portfolio_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import 'trading_navigation_bar.dart';

typedef NavigationDestinationBodyBuilder =
    Widget Function(BuildContext context, int index);

class MainNavigationShell extends ConsumerStatefulWidget {
  const MainNavigationShell({super.key, this.destinationBuilder});

  final NavigationDestinationBodyBuilder? destinationBuilder;

  @override
  ConsumerState<MainNavigationShell> createState() =>
      _MainNavigationShellState();
}

class _MainNavigationShellState extends ConsumerState<MainNavigationShell> {
  int _selectedIndex = 0;

  Widget _buildSelectedScreen(BuildContext context) {
    final destinationBuilder = widget.destinationBuilder;
    if (destinationBuilder != null) {
      return destinationBuilder(context, _selectedIndex);
    }

    switch (_selectedIndex) {
      case 1:
        return const FractalScreen();
      case 2:
        return const OrdersScreen();
      case 3:
        return const MarketScreen();
      case 4:
        return const SettingsScreen();
      case 0:
      default:
        return const PortfolioScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(isDarkModeProvider);
    final backgroundColor = isDark ? const Color(0xFF121212) : Colors.white;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: _buildSelectedScreen(context),
      bottomNavigationBar: TradingNavigationBar(
        selectedIndex: _selectedIndex,
        isDark: isDark,
        onDestinationSelected: (index) {
          if (index != _selectedIndex) {
            setState(() => _selectedIndex = index);
          }
        },
      ),
    );
  }
}
