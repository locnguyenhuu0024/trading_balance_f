import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trading_balance_f/core/navigation/main_navigation_shell.dart';
import 'package:trading_balance_f/core/navigation/navigation_destination_data.dart';
import 'package:trading_balance_f/core/navigation/trading_navigation_bar.dart';
import 'package:trading_balance_f/main.dart' as app;
import '../../support/backend_features_override.dart';

void main() {
  testWidgets(
    'stored floating preference still renders a fixed four-item bar',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'NAVIGATION_PREFERENCES': jsonEncode({
          'version': 1,
          'mode': 'floating',
          'edge': 'right',
          'enabledDestinationIds': [
            'home',
            'bmag',
            'orders',
            'market',
            'settings',
            'support',
            'strategy',
          ],
          'destinationOrderIds': [
            'home',
            'bmag',
            'orders',
            'market',
            'settings',
            'support',
            'strategy',
          ],
        }),
      });
      final startup = await app.initializeAppStartup(
        isWeb: true,
        loadWebPreferences: SharedPreferences.getInstance,
        initializeTimeZone: () {},
      );

      await tester.pumpWidget(
        app.buildInitializedApp(
          startup,
          home: MainNavigationShell(
            destinationBuilder: (context, index) => Text('Screen $index'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final bar = tester.widget<TradingNavigationBar>(
        find.byType(TradingNavigationBar),
      );
      expect(
        [
          find.byKey(const Key('floating-navigation-group')).evaluate().length,
          bar.destinations.map((item) => item.label).toList(),
        ],
        [
          0,
          ['Tài sản', 'Lệnh', 'Thị trường', 'Thêm'],
        ],
      );
    },
  );

  testWidgets('backend-enabled navigation inserts Strategy third', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [backendFeaturesEnabledTestOverride],
        child: MaterialApp(
          home: MainNavigationShell(
            destinationBuilder: (context, index) => Text('Screen $index'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bar = tester.widget<TradingNavigationBar>(
      find.byType(TradingNavigationBar),
    );
    expect(bar.destinations.map((item) => item.label).toList(), [
      'Tài sản',
      'Lệnh',
      'Chiến thuật',
      'Thị trường',
      'Thêm',
    ]);
    expect(navigationItems, hasLength(4));

    await tester.tap(find.byKey(const Key('navigation-destination-2')));
    await tester.pumpAndSettle();
    expect(find.text('Screen 2'), findsOneWidget);
  });

  testWidgets('fixed destinations switch to their matching screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: MainNavigationShell(
            destinationBuilder: (context, index) => Text('Screen $index'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('navigation-destination-1')));
    await tester.pumpAndSettle();
    expect(find.text('Screen 1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('navigation-destination-3')));
    await tester.pumpAndSettle();
    expect(find.text('Screen 3'), findsOneWidget);
  });
}
