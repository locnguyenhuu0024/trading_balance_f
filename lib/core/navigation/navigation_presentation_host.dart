import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'navigation_content_frame.dart';
import 'navigation_destination_data.dart';
import 'trading_navigation_bar.dart';

class NavigationPresentationHost extends StatelessWidget {
  const NavigationPresentationHost({
    super.key,
    required this.child,
    required this.destinations,
    required this.selectedIndex,
    required this.isDark,
    required this.onDestinationSelected,
  });

  final Widget child;
  final List<NavigationItemData> destinations;
  final int selectedIndex;
  final bool isDark;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = math.max(
      mediaQuery.viewPadding.bottom,
      mediaQuery.viewInsets.bottom,
    );

    return NavigationPresentationScope(
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: child),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: TradingNavigationBar(
              destinations: destinations,
              selectedIndex: selectedIndex,
              isDark: isDark,
              bottomInset: bottomInset,
              onDestinationSelected: onDestinationSelected,
            ),
          ),
        ],
      ),
    );
  }
}
