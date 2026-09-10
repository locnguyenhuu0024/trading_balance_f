import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/orders/data/okx_position_model.dart';
import 'package:trading_balance_f/features/orders/presentation/orders_screen.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/order_provider.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';

void main() {
  testWidgets('keeps adaptive entry, mark and liquidation prices in Orders', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderFilterProvider.overrideWith((ref) => 'SWAP'),
          orderTabProvider.overrideWith((ref) => OrderTab.positions),
          positionsFutureProvider.overrideWith(
            (ref) async => const [
              OkxPosition(
                instId: 'BTC-USDT-SWAP',
                posSide: 'long',
                lever: '5',
                avgPx: '0.09117',
                markPx: '0.00001234',
                liqPx: '1234567.89',
                upl: '0',
                uplRatio: '0',
              ),
            ],
          ),
          themeModeProvider.overrideWith((ref) => ThemeMode.light),
          vndExchangeRateProvider.overrideWith((ref) async => 25400),
        ],
        child: const MaterialApp(home: OrdersScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Giá vào'), findsOneWidget);
    expect(find.text('0.09117'), findsOneWidget);
    expect(find.text('Giá mark'), findsOneWidget);
    expect(find.text('0.00001234'), findsOneWidget);
    expect(find.text('Thanh lý'), findsOneWidget);
    expect(find.text('1,234,567.89'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
