import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/navigation/main_navigation_shell.dart';
import 'package:trading_balance_f/core/navigation/trading_navigation_bar.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/order_provider.dart';
import 'package:trading_balance_f/features/orders/presentation/widgets/order_filter_controls.dart';
import 'package:trading_balance_f/features/orders/presentation/widgets/responsive_order_grid.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';

void main() {
  Widget shellApp({ThemeMode themeMode = ThemeMode.light}) {
    return ProviderScope(
      key: ValueKey(themeMode),
      overrides: [themeModeProvider.overrideWith((ref) => themeMode)],
      child: MaterialApp(
        home: MainNavigationShell(
          destinationBuilder: (context, index) => Center(
            child: Text('Màn hình $index', key: Key('destination-body-$index')),
          ),
        ),
      ),
    );
  }

  testWidgets('root navigation exposes five destinations and selected label', (
    tester,
  ) async {
    await tester.pumpWidget(shellApp());

    expect(TradingNavigationBar.items, hasLength(5));
    expect(find.byKey(const Key('destination-body-0')), findsOneWidget);
    expect(find.text('Trang chủ'), findsOneWidget);
    expect(find.text('Thị trường'), findsNothing);

    await tester.tap(find.byKey(const Key('navigation-destination-3')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('destination-body-3')), findsOneWidget);
    expect(find.text('Trang chủ'), findsNothing);
    expect(find.text('Thị trường'), findsOneWidget);
    expect(find.byKey(const Key('navigation-destination-4')), findsOneWidget);
  });

  testWidgets('navigation bar keeps a contrasting continuous surface', (
    tester,
  ) async {
    await tester.pumpWidget(shellApp());

    final lightSurface = tester.widget<Container>(
      find.byKey(const Key('navigation-bar-surface')),
    );
    final lightIndicator = tester.widget<AnimatedContainer>(
      find.byKey(const Key('navigation-indicator-0')),
    );

    expect(lightSurface.color, Colors.black);
    expect((lightIndicator.decoration! as BoxDecoration).color, Colors.white);

    await tester.pumpWidget(shellApp(themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();

    final darkSurface = tester.widget<Container>(
      find.byKey(const Key('navigation-bar-surface')),
    );
    final darkIndicator = tester.widget<AnimatedContainer>(
      find.byKey(const Key('navigation-indicator-0')),
    );

    expect(darkSurface.color, Colors.white);
    expect((darkIndicator.decoration! as BoxDecoration).color, Colors.black);
  });

  testWidgets('order select controls update their selected values', (
    tester,
  ) async {
    var tab = OrderTab.positions;
    var filter = 'MARGIN';

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: OrderFilterControls(
                currentTab: tab,
                currentFilter: filter,
                isDark: false,
                onTabChanged: (value) => setState(() => tab = value),
                onFilterChanged: (value) => setState(() => filter = value),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(SegmentedButton<OrderTab>), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);

    await tester.tap(find.byKey(const Key('order-tab-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lịch sử').last);
    await tester.pumpAndSettle();
    expect(tab, OrderTab.history);

    await tester.tap(find.byKey(const Key('order-type-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SWAP').last);
    await tester.pumpAndSettle();
    expect(filter, 'SWAP');
  });

  testWidgets('order grid changes column count at responsive breakpoints', (
    tester,
  ) async {
    const cases = <(double, int)>[
      (390, 1),
      (600, 2),
      (900, 3),
      (1200, 3),
      (1600, 4),
    ];

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final testCase in cases) {
      tester.view.physicalSize = Size(testCase.$1, 800);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResponsiveOrderGrid(
              cardExtent: 180,
              children: List.generate(
                5,
                (index) => Card(child: Center(child: Text('Card $index'))),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      if (testCase.$2 == 1) {
        expect(find.byType(ListView), findsOneWidget);
      } else {
        final grid = tester.widget<GridView>(find.byType(GridView));
        final delegate =
            grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
        expect(delegate.crossAxisCount, testCase.$2);
      }
    }
  });
}
