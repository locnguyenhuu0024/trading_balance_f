import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'trading_navigation_bar.dart';

/// Marks the subtree rendered by [NavigationPresentationHost].
///
/// Destination screens are also used directly in tests and previews. In those
/// cases [NavigationContentFrame] intentionally remains a no-op.
class NavigationPresentationScope extends InheritedWidget {
  const NavigationPresentationScope({super.key, required super.child});

  static bool isActive(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<
              NavigationPresentationScope
            >() !=
        null;
  }

  @override
  bool updateShouldNotify(NavigationPresentationScope oldWidget) => false;
}

/// Reserves the content space needed by the primary navigation bar.
class NavigationContentFrame extends StatelessWidget {
  const NavigationContentFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!NavigationPresentationScope.isActive(context)) return child;

    final mediaQuery = MediaQuery.of(context);
    final bottomInset = math.max(
      mediaQuery.viewPadding.bottom,
      mediaQuery.viewInsets.bottom,
    );

    return Padding(
      key: const Key('navigation-content-frame'),
      padding: EdgeInsets.only(
        bottom:
            TradingNavigationBar.crestHeight +
            TradingNavigationBar.barHeight +
            bottomInset,
      ),
      child: child,
    );
  }
}
