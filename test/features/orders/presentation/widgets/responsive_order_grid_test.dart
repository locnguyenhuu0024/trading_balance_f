import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/orders/presentation/widgets/responsive_order_grid.dart';

Widget _grid({required List<double> heights, double? cardExtent}) {
  return MaterialApp(
    home: Scaffold(
      body: ResponsiveOrderGrid(
        cardExtent: cardExtent,
        children: [
          for (var index = 0; index < heights.length; index++)
            SizedBox(
              key: ValueKey('grid-child-$index'),
              height: heights[index],
              child: const ColoredBox(color: Colors.blue),
            ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('uses natural rows at every responsive breakpoint', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    const cases = <(double, int)>[(390, 1), (600, 2), (900, 3), (1600, 4)];

    for (final (width, columnCount) in cases) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpWidget(
        _grid(heights: List<double>.filled(columnCount + 1, 40)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ListView), findsOneWidget);
      expect(find.byType(GridView), findsNothing);
      expect(find.byKey(const ValueKey('grid-child-0')), findsOneWidget);
      expect(find.byKey(ValueKey('grid-child-$columnCount')), findsOneWidget);

      final firstChildRect = tester.getRect(
        find.byKey(const ValueKey('grid-child-0')),
      );
      final firstNextRowRect = tester.getRect(
        find.byKey(ValueKey('grid-child-$columnCount')),
      );
      final expectedWidth =
          (width - 24 - ((columnCount - 1) * 12)) / columnCount;
      expect(firstChildRect.width, closeTo(expectedWidth, 0.01));
      expect(firstChildRect.top, closeTo(12, 0.01));
      expect(
        firstNextRowRect.top,
        closeTo(firstChildRect.bottom + (columnCount == 1 ? 8 : 12), 0.01),
      );
    }
  });

  testWidgets('top-aligns cards and advances by the tallest row child', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 500);

    await tester.pumpWidget(_grid(heights: [100, 40, 30, 20, 50]));
    await tester.pumpAndSettle();

    final firstRect = tester.getRect(
      find.byKey(const ValueKey('grid-child-0')),
    );
    final secondRect = tester.getRect(
      find.byKey(const ValueKey('grid-child-1')),
    );
    final thirdRect = tester.getRect(
      find.byKey(const ValueKey('grid-child-2')),
    );
    final fourthRect = tester.getRect(
      find.byKey(const ValueKey('grid-child-3')),
    );
    final fifthRect = tester.getRect(
      find.byKey(const ValueKey('grid-child-4')),
    );

    expect(secondRect.top, firstRect.top);
    expect(thirdRect.top, closeTo(firstRect.bottom + 12, 0.01));
    expect(fourthRect.top, thirdRect.top);
    expect(fifthRect.top, closeTo(thirdRect.bottom + 12, 0.01));
    expect(firstRect.width, closeTo(secondRect.width, 0.01));
    expect(thirdRect.width, closeTo(fourthRect.width, 0.01));
  });

  testWidgets('reserves the incomplete final row slot and remains scrollable', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 180);

    await tester.pumpWidget(_grid(heights: List<double>.filled(7, 48)));
    await tester.pumpAndSettle();

    final firstRect = tester.getRect(
      find.byKey(const ValueKey('grid-child-0')),
    );
    final fifthRect = tester.getRect(
      find.byKey(const ValueKey('grid-child-4')),
    );
    expect(firstRect.width, closeTo(282, 0.01));
    expect(fifthRect.width, closeTo(firstRect.width, 0.01));
    expect(fifthRect.left, firstRect.left);
    expect(find.byKey(const ValueKey('grid-child-6')), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('grid-child-6')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retains fixed-extent grid behavior when extent is supplied', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 500);

    await tester.pumpWidget(
      _grid(heights: List<double>.filled(5, 40), cardExtent: 180),
    );
    await tester.pumpAndSettle();

    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 3);
    expect(delegate.mainAxisExtent, 180);
    expect(find.byType(ListView), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
