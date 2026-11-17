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
  Widget shellApp({
    ThemeMode themeMode = ThemeMode.light,
    TextScaler? textScaler,
  }) {
    const destinationScreenIndices = [0, 2, 3, 8];
    return ProviderScope(
      key: ValueKey(themeMode),
      overrides: [themeModeProvider.overrideWith((ref) => themeMode)],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: MainNavigationShell(
          destinationBuilder: (context, index) {
            final screenIndex = destinationScreenIndices[index];
            return Center(
              child: Text(
                'Màn hình $screenIndex',
                key: Key('destination-body-$screenIndex'),
              ),
            );
          },
        ),
      ),
    );
  }

  testWidgets('root navigation exposes four fixed destinations', (
    tester,
  ) async {
    await tester.pumpWidget(shellApp());

    expect(TradingNavigationBar.items.map((item) => item.id), [
      'home',
      'orders',
      'market',
      'tools',
    ]);
    expect(find.byKey(const Key('destination-body-0')), findsOneWidget);
    expect(find.byTooltip('Tài sản'), findsOneWidget);
    expect(find.byTooltip('Lệnh'), findsOneWidget);
    expect(find.byTooltip('Thị trường'), findsOneWidget);
    expect(find.byTooltip('Thêm'), findsOneWidget);
    expect(find.text('Thị trường'), findsOneWidget);

    await tester.tap(find.byKey(const Key('navigation-destination-2')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('destination-body-3')), findsOneWidget);
    expect(find.text('Thị trường'), findsOneWidget);

    await tester.tap(find.byKey(const Key('navigation-destination-3')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('destination-body-8')), findsOneWidget);
    expect(find.text('Thêm'), findsOneWidget);
  });

  testWidgets('navigation bar uses a surface pill and accessible targets', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 900);
    await tester.pumpWidget(shellApp(textScaler: const TextScaler.linear(2)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (var index = 0; index < TradingNavigationBar.items.length; index++) {
      final target = tester.getSize(
        find.byKey(Key('navigation-destination-$index')),
      );
      expect(target.width, greaterThanOrEqualTo(48));
      expect(target.height, greaterThanOrEqualTo(48));
    }
    final indicator = tester.widget<Container>(
      find.byKey(const Key('navigation-indicator-0')),
    );
    expect(
      (indicator.decoration! as BoxDecoration).borderRadius,
      BorderRadius.circular(12),
    );
    await tester.tap(find.byKey(const Key('navigation-destination-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('destination-body-3')), findsOneWidget);
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
    expect(find.byType(ChoiceChip), findsWidgets);

    await tester.tap(find.text('Lịch sử'));
    await tester.pumpAndSettle();
    expect(tab, OrderTab.history);

    await tester.ensureVisible(find.text('Perpetual'));
    await tester.tap(find.text('Perpetual'));
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
