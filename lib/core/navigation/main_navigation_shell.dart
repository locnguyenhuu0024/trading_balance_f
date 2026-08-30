import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/fractal_tracker/presentation/fractal_screen.dart';
import '../../features/orders/presentation/orders_screen.dart';
import '../../features/portfolio/presentation/portfolio_screen.dart';

class MainNavigationShell extends ConsumerStatefulWidget {
  const MainNavigationShell({super.key});

  @override
  ConsumerState<MainNavigationShell> createState() =>
      _MainNavigationShellState();
}

class _MainNavigationShellState extends ConsumerState<MainNavigationShell> {
  int _selectedIndex = 0;

  Widget _buildSelectedScreen() {
    switch (_selectedIndex) {
      case 1:
        return const FractalScreen();
      case 2:
        return const OrdersScreen();
      case 0:
      default:
        return const PortfolioScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(isDarkModeProvider);
    final backgroundColor = isDark ? const Color(0xFF121212) : Colors.white;
    final selectedColor = isDark ? Colors.black : Colors.white;
    final unselectedColor = isDark ? Colors.white70 : Colors.black54;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: _buildSelectedScreen(),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final isSelected = states.contains(WidgetState.selected);
            return TextStyle(
              color: isSelected ? selectedColor : unselectedColor,
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final isSelected = states.contains(WidgetState.selected);
            return IconThemeData(
              color: isSelected ? selectedColor : unselectedColor,
              size: 22,
            );
          }),
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            if (index != _selectedIndex) {
              setState(() => _selectedIndex = index);
            }
          },
          backgroundColor: backgroundColor,
          indicatorColor: isDark ? Colors.white : Colors.black,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Trang chủ',
            ),
            NavigationDestination(
              icon: Icon(Icons.donut_small_outlined),
              selectedIcon: Icon(Icons.donut_small),
              label: 'BMAG',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Lệnh',
            ),
          ],
        ),
      ),
    );
  }
}
