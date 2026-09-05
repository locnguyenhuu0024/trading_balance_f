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

/// Reserves only the content space needed by the current navigation overlay.
/// It never paints a lane or intercepts gestures around the navigation itself.
class NavigationContentFrame extends ConsumerWidget {
  const NavigationContentFrame({super.key, required this.child});

  // The button group itself is 68 high/wide. Include its 12-pixel edge gap so
  // scroll content never settles beneath a label or a button shadow.
  static const _floatingHorizontalClearance = 80.0;
  static const _floatingSideClearance = 88.0;

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

    final padding = switch (preferences.displayMode) {
      NavigationDisplayMode.bar => EdgeInsets.only(bottom: 60 + bottomInset),
      NavigationDisplayMode.floating => _floatingPadding(
        preferences.floatingEdge,
        mediaQuery,
        bottomInset,
      ),
    };

    return Padding(
      key: const Key('navigation-content-frame'),
      padding: padding,
      child: child,
    );
  }

  EdgeInsets _floatingPadding(
    NavigationEdge edge,
    MediaQueryData mediaQuery,
    double bottomInset,
  ) {
    return switch (edge) {
      NavigationEdge.top => const EdgeInsets.only(
        top: _floatingHorizontalClearance,
      ),
      NavigationEdge.bottom => EdgeInsets.only(
        bottom: _floatingHorizontalClearance + bottomInset,
      ),
      NavigationEdge.left => EdgeInsets.only(
        left: _floatingSideClearance + mediaQuery.viewPadding.left,
      ),
      NavigationEdge.right => EdgeInsets.only(
        right: _floatingSideClearance + mediaQuery.viewPadding.right,
      ),
    };
  }
}
