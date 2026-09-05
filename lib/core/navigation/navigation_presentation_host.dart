import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'floating_navigation_buttons.dart';
import 'navigation_content_frame.dart';
import 'navigation_preferences.dart';
import 'trading_navigation_bar.dart';

/// Hosts a stable destination subtree and places navigation above it.
///
/// Keeping [child] in one slot avoids remounting Settings (and its form fields)
/// when a user changes only the navigation presentation or floating edge.
class NavigationPresentationHost extends StatelessWidget {
  const NavigationPresentationHost({
    super.key,
    required this.child,
    required this.preferences,
    required this.selectedIndex,
    required this.isDark,
    required this.onDestinationSelected,
  });

  final Widget child;
  final NavigationPreferences preferences;
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
          if (preferences.displayMode == NavigationDisplayMode.bar)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: TradingNavigationBar(
                selectedIndex: selectedIndex,
                isDark: isDark,
                bottomInset: bottomInset,
                onDestinationSelected: onDestinationSelected,
              ),
            )
          else
            FloatingNavigationButtons(
              edge: preferences.floatingEdge,
              selectedIndex: selectedIndex,
              isDark: isDark,
              onDestinationSelected: onDestinationSelected,
            ),
        ],
      ),
    );
  }
}
