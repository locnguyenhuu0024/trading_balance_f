import 'dart:ui' show SemanticsFlag;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/order_provider.dart';
import 'package:trading_balance_f/features/orders/presentation/widgets/order_filter_controls.dart';

void main() {
  testWidgets('tabs and OKX chips remain accessible at narrow width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    OrderTab? tab;
    String? filter;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: OrderFilterControls(
              currentTab: OrderTab.positions,
              currentFilter: 'MARGIN',
              isDark: false,
              onTabChanged: (value) => tab = value,
              onFilterChanged: (value) => filter = value,
            ),
          ),
        ),
      ),
    );
    final selected = tester
        .getSemantics(find.bySemanticsLabel('Vị thế'))
        .getSemanticsData();
    expect(selected.hasFlag(SemanticsFlag.isSelected), isTrue);
    expect(selected.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(
      tester.getSize(find.widgetWithText(TextButton, 'Vị thế')).height,
      greaterThanOrEqualTo(48),
    );
    await tester.tap(find.text('Chờ khớp'));
    expect(tab, OrderTab.pending);
    await tester.ensureVisible(find.text('Futures'));
    await tester.tap(find.text('Futures'));
    expect(filter, 'FUTURES');
    expect(
      tester.getSize(find.widgetWithText(ChoiceChip, 'Futures')).height,
      greaterThanOrEqualTo(48),
    );
    expect(tester.takeException(), isNull);
  });
}
