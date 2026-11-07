import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/fractal_tracker/presentation/fractal_screen.dart';
import '../../features/market/presentation/market_screen.dart';
import '../../features/orders/presentation/orders_screen.dart';
import '../../features/portfolio/presentation/portfolio_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/support_resistance/presentation/support_resistance_screen.dart';
import '../../features/strategy/presentation/strategy_screen.dart';
import '../../features/tools/tools_screen.dart';
import '../backend_features.dart';
import '../theme/app_theme.dart';
import '../widgets/app_page_transition.dart';
import 'navigation_destination_data.dart';
import 'navigation_presentation_host.dart';

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

  Widget _buildSelectedScreen(
    BuildContext context,
    int selectedIndex,
    int selectedVisibleIndex,
  ) {
    final destinationBuilder = widget.destinationBuilder;
    if (destinationBuilder != null) {
      return destinationBuilder(context, selectedVisibleIndex);
    }

    return switch (selectedIndex) {
      1 => const FractalScreen(),
      2 => const OrdersScreen(),
      3 => const MarketScreen(),
      4 => const SettingsScreen(),
      6 => const SupportResistanceScreen(),
      7 => const StrategyScreen(),
      8 => const ToolsScreen(),
      _ => const PortfolioScreen(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final backendFeaturesEnabled = ref.watch(backendFeaturesEnabledProvider);
    final destinations = navigationItemsForBackendFeatures(
      backendFeaturesEnabled,
    );
    final isDark = ref.watch(isDarkModeProvider);
    final selectedDestinationIndex = destinations.indexWhere(
      (destination) => destination.screenIndex == _selectedIndex,
    );
    final selectedScreenIndex = selectedDestinationIndex < 0
        ? destinations.first.screenIndex
        : _selectedIndex;
    final selectedVisibleIndex = destinations.indexWhere(
      (destination) => destination.screenIndex == selectedScreenIndex,
    );

    return Material(
      color: AppPalette.forBrightness(isDark).background,
      child: NavigationPresentationHost(
        destinations: destinations,
        selectedIndex: selectedVisibleIndex,
        isDark: isDark,
        onDestinationSelected: (index) {
          if (index >= 0 && index < destinations.length) {
            final screenIndex = destinations[index].screenIndex;
            if (screenIndex != _selectedIndex) {
              setState(() => _selectedIndex = screenIndex);
            }
          }
        },
        child: AppDestinationTransition(
          destinationId: selectedScreenIndex,
          child: KeyedSubtree(
            key: ValueKey<int>(selectedScreenIndex),
            child: _buildSelectedScreen(
              context,
              selectedScreenIndex,
              selectedVisibleIndex,
            ),
          ),
        ),
      ),
    );
  }
}
