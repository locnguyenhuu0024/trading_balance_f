import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/order_provider.dart';
import 'package:trading_balance_f/features/orders/presentation/widgets/order_filter_controls.dart';

void main() {
  testWidgets('shows usable status and type selectors in one row at 390 px', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    String? selectedFilter;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: OrderFilterControls(
              currentTab: OrderTab.positions,
              currentFilter: 'MARGIN',
              isDark: false,
              onTabChanged: (_) {},
              onFilterChanged: (filter) => selectedFilter = filter,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tabSelector = tester.getRect(
      find.byKey(const Key('order-tab-select')),
    );
    final typeSelector = tester.getRect(
      find.byKey(const Key('order-type-select')),
    );

    expect(tabSelector.top, typeSelector.top);
    expect(tabSelector.right, lessThanOrEqualTo(typeSelector.left));
    expect(typeSelector.right, lessThanOrEqualTo(390));

    await tester.tap(find.byKey(const Key('order-type-select')));
    await tester.pumpAndSettle();
    final allOption = find.text('ALL');
    expect(allOption, findsOneWidget);
    await tester.tap(allOption);
    await tester.pumpAndSettle();

    expect(selectedFilter, 'ALL');
    expect(tester.takeException(), isNull);
  });
}
