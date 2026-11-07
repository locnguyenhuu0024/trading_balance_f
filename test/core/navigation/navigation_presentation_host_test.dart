import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/navigation/main_navigation_shell.dart';
import 'package:trading_balance_f/core/navigation/navigation_destination_data.dart';
import 'package:trading_balance_f/core/navigation/navigation_presentation_host.dart';
import 'package:trading_balance_f/core/navigation/trading_navigation_bar.dart';

class _TapDestination extends StatelessWidget {
  const _TapDestination({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: const ColoredBox(color: Colors.amber, child: SizedBox.expand()),
  );
}

void main() {
  testWidgets('presentation host always uses the fixed navigation bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NavigationPresentationHost(
          destinations: navigationItems,
          selectedIndex: 0,
          isDark: false,
          onDestinationSelected: (_) {},
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TradingNavigationBar), findsOneWidget);
    expect(find.byKey(const Key('floating-navigation-group')), findsNothing);
  });

  testWidgets('raised button hits do not fall through to page content', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);

    var pageTapCount = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: MainNavigationShell(
            destinationBuilder: (context, index) =>
                _TapDestination(onTap: () => pageTapCount++),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final selectedButton = tester.getRect(
      find.byKey(const Key('navigation-destination-0')),
    );
    final surface = tester.getRect(
      find.byKey(const Key('navigation-bar-surface')),
    );

    await tester.tapAt(selectedButton.center);
    await tester.pump();
    expect(pageTapCount, 0);

    await tester.tapAt(Offset(surface.left + 82, surface.top - 8));
    await tester.pump();
    expect(pageTapCount, 1);
  });
}
