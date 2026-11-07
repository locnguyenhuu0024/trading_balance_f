import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/features/connections/binance_connection_form.dart';
import 'package:trading_balance_f/features/connections/connections_screen.dart';
import 'package:trading_balance_f/exchanges/binance/binance_adapter.dart';
import 'package:trading_balance_f/main.dart' show WebStorageHelper;

void main() {
  for (final proxy in [false, true]) {
    testWidgets('web product line follows proxy=$proxy', (tester) async {
      SharedPreferences.setMockInitialValues({
        'BINANCE_API_KEY': 'key',
        'BINANCE_API_SECRET': 'secret',
      });
      final storage = WebStorageHelper(await SharedPreferences.getInstance());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageProvider.overrideWithValue(storage),
            binanceIsWebProvider.overrideWithValue(true),
            binanceProxyBaseUrlProvider.overrideWithValue(
              proxy ? 'https://proxy.example' : '',
            ),
          ],
          child: const MaterialApp(home: ConnectionsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          proxy ? 'USDⓈ-M · Spot · Margin\nĐã kết nối' : 'USDⓈ-M\nĐã kết nối',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      storage.dispose();
    });
  }
  testWidgets('lists configured connections and catalog opens existing form', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'BINANCE_API_KEY': 'key',
      'BINANCE_API_SECRET': 'secret',
    });
    final storage = WebStorageHelper(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [secureStorageProvider.overrideWithValue(storage)],
        child: const MaterialApp(home: ConnectionsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Binance / Chính'), findsOneWidget);
    expect(find.text('OKX / Chính'), findsNothing);
    await tester.tap(find.text('+ Thêm kết nối'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Sàn khác'))
          .enabled,
      isFalse,
    );
    await tester.tap(find.text('Binance'));
    await tester.pumpAndSettle();
    expect(find.byType(BinanceConnectionForm), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    storage.dispose();
  });
}
