import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
    OrderTab? selectedTab;
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
              onTabChanged: (tab) => selectedTab = tab,
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
    final tabFace = tester.getRect(
      find.byKey(const Key('order-tab-select-face')),
    );
    final typeFace = tester.getRect(
      find.byKey(const Key('order-type-select-face')),
    );

    expect(tabSelector.top, typeSelector.top);
    expect(tabSelector.right, lessThanOrEqualTo(typeSelector.left));
    expect(tabSelector.width, lessThanOrEqualTo(140));
    expect(typeSelector.width, lessThanOrEqualTo(140));
    expect(tabSelector.height, 48);
    expect(typeSelector.height, 48);
    expect(tabFace.height, 40);
    expect(typeFace.height, 40);
    expect(find.byTooltip('Trạng thái'), findsOneWidget);
    expect(find.byTooltip('Loại giao dịch'), findsOneWidget);
    expect(typeSelector.right, lessThanOrEqualTo(390));

    await tester.tap(find.byKey(const Key('order-tab-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đang chờ').last);
    await tester.pumpAndSettle();
    expect(selectedTab, OrderTab.pending);

    await tester.tap(find.byKey(const Key('order-type-select')));
    await tester.pumpAndSettle();
    final futuresOption = find.text('FUTURES');
    expect(futuresOption, findsOneWidget);
    await tester.tap(futuresOption);
    await tester.pumpAndSettle();

    expect(selectedFilter, 'FUTURES');
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps full selected value accessible when the face ellipsizes', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 800);
    final semanticsHandle = tester.ensureSemantics();

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 118,
                  child: OrderFilterControls(
                    currentTab: OrderTab.pending,
                    currentFilter: 'FUTURES',
                    isDark: false,
                    onTabChanged: (_) {},
                    onFilterChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final selectedValueParagraph = find.descendant(
        of: find.text('FUTURES'),
        matching: find.byType(RichText),
      );
      expect(
        tester
            .renderObject<RenderParagraph>(selectedValueParagraph)
            .didExceedMaxLines,
        isTrue,
      );
      final selectedSemantics = tester
          .getSemantics(find.text('FUTURES'))
          .getSemanticsData();
      expect(selectedSemantics.label, contains('Loại giao dịch'));
      expect(selectedSemantics.label, contains('FUTURES'));
      final statusSemantics = tester
          .getSemantics(find.byKey(const Key('order-tab-select')))
          .getSemanticsData();
      expect(statusSemantics.label, contains('Trạng thái'));
      expect(statusSemantics.label, contains('Đang chờ'));
      expect(tester.takeException(), isNull);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('keeps both selectors in one row at 360 px with enlarged text', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: OrderFilterControls(
                currentTab: OrderTab.positions,
                currentFilter: 'MARGIN',
                isDark: false,
                onTabChanged: (_) {},
                onFilterChanged: (_) {},
              ),
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
    expect(typeSelector.top, tabSelector.top);
    expect(tabSelector.width, lessThanOrEqualTo(140));
    expect(typeSelector.width, lessThanOrEqualTo(140));
    expect(tabSelector.height, 48);
    expect(typeSelector.height, 48);
    expect(typeSelector.right, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
  });
}
