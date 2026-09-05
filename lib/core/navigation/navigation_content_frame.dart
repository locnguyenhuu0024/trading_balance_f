import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'navigation_preferences.dart';
import 'navigation_preferences_provider.dart';

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

/// Reserves the content space needed by the fixed navigation bar.
///
/// Floating navigation is a true overlay, so it never changes the destination
/// body's constraints or adds a layout lane around its edge.
class NavigationContentFrame extends ConsumerWidget {
  const NavigationContentFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!NavigationPresentationScope.isActive(context)) return child;

    final preferences = ref.watch(
      navigationPreferencesProvider.select((state) => state.preferences),
    );
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = math.max(
      mediaQuery.viewPadding.bottom,
      mediaQuery.viewInsets.bottom,
    );

    if (preferences.displayMode == NavigationDisplayMode.floating) {
      return child;
    }

    return Padding(
      key: const Key('navigation-content-frame'),
      padding: EdgeInsets.only(bottom: 60 + bottomInset),
      child: child,
    );
  }
}
