import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/navigation/floating_navigation_buttons.dart';
import 'package:trading_balance_f/core/navigation/navigation_preferences.dart';

void main() {
  Widget appFor({
    required NavigationEdge edge,
    required ValueChanged<int> onDestinationSelected,
    bool disableAnimations = false,
    EdgeInsets viewInsets = EdgeInsets.zero,
    TextScaler? textScaler,
  }) {
    return MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: disableAnimations,
          viewInsets: viewInsets,
          textScaler: textScaler,
        ),
        child: child!,
      ),
      home: Material(
        child: SizedBox.expand(
          key: const Key('floating-test-viewport'),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.amber),
              FloatingNavigationButtons(
                edge: edge,
                selectedIndex: 0,
                isDark: false,
                onDestinationSelected: onDestinationSelected,
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('anchors and orders horizontal floating buttons', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);

    await tester.pumpWidget(
      appFor(edge: NavigationEdge.top, onDestinationSelected: (_) {}),
    );
    await tester.pumpAndSettle();

    final group = tester.getRect(
      find.byKey(const Key('floating-navigation-group')),
    );
    final first = tester.getRect(
      find.byKey(const Key('floating-navigation-destination-0')),
    );
    final last = tester.getRect(
      find.byKey(const Key('floating-navigation-destination-4')),
    );

    expect(group.top, greaterThan(0));
    expect(first.center.dx, lessThan(last.center.dx));
    expect(find.text('Trang chủ'), findsOneWidget);
    expect(find.byKey(const Key('navigation-bar-surface')), findsNothing);
  });

  testWidgets('uses a vertical top-to-bottom order on both side edges', (
    tester,
  ) async {
    for (final edge in [NavigationEdge.left, NavigationEdge.right]) {
      await tester.pumpWidget(
        appFor(edge: edge, onDestinationSelected: (_) {}),
      );
      await tester.pumpAndSettle();

      final first = tester.getRect(
        find.byKey(const Key('floating-navigation-destination-0')),
      );
      final last = tester.getRect(
        find.byKey(const Key('floating-navigation-destination-4')),
      );

      expect(first.center.dy, lessThan(last.center.dy));
      if (edge == NavigationEdge.left) {
        expect(first.left, lessThan(100));
      } else {
        final viewport = tester.getRect(
          find.byKey(const Key('floating-test-viewport')),
        );
        expect(first.right, greaterThan(viewport.right - 100));
      }
    }
  });

  testWidgets('sends a destination callback from its real button target', (
    tester,
  ) async {
    var selected = -1;
    await tester.pumpWidget(
      appFor(
        edge: NavigationEdge.bottom,
        onDestinationSelected: (index) => selected = index,
      ),
    );

    await tester.tap(
      find.byKey(const Key('floating-navigation-destination-3')),
    );
    await tester.pump();

    expect(selected, 3);
  });

  testWidgets('falls back to bounded scrolling in a constrained viewport', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(240, 320);

    await tester.pumpWidget(
      appFor(edge: NavigationEdge.top, onDestinationSelected: (_) {}),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('floating-navigation-horizontal-scroll')),
      findsOneWidget,
    );

    await tester.pumpWidget(
      appFor(edge: NavigationEdge.left, onDestinationSelected: (_) {}),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('floating-navigation-vertical-scroll')),
      findsOneWidget,
    );
  });

  testWidgets('honors reduced-motion settings for floating controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      appFor(
        edge: NavigationEdge.bottom,
        disableAnimations: true,
        onDestinationSelected: (_) {},
      ),
    );

    final indicator = tester.widget<AnimatedContainer>(
      find.byKey(const Key('floating-navigation-indicator-0')),
    );
    expect(indicator.duration, Duration.zero);
  });

  testWidgets('keeps a bottom group above the keyboard inset', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);

    await tester.pumpWidget(
      appFor(
        edge: NavigationEdge.bottom,
        viewInsets: const EdgeInsets.only(bottom: 200),
        onDestinationSelected: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    final viewport = tester.getRect(
      find.byKey(const Key('floating-test-viewport')),
    );
    final group = tester.getRect(
      find.byKey(const Key('floating-navigation-group')),
    );
    expect(group.bottom, lessThanOrEqualTo(viewport.bottom - 212));
  });

  testWidgets('keeps every destination available at enlarged text scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      appFor(
        edge: NavigationEdge.top,
        textScaler: const TextScaler.linear(2),
        onDestinationSelected: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    for (var index = 0; index < 5; index++) {
      expect(
        find.byKey(Key('floating-navigation-destination-$index')),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('exposes selected destinations as semantic buttons', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();

    await tester.pumpWidget(
      appFor(edge: NavigationEdge.left, onDestinationSelected: (_) {}),
    );

    expect(find.bySemanticsLabel('Trang chủ'), findsWidgets);
    semanticsHandle.dispose();
  });
}
