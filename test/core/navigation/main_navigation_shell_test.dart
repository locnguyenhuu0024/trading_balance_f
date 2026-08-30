import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/navigation/main_navigation_shell.dart';
import 'package:trading_balance_f/core/navigation/trading_navigation_bar.dart';
import 'package:trading_balance_f/core/network/okx_websocket_service.dart';
import 'package:trading_balance_f/features/fractal_tracker/data/fractal_model.dart';
import 'package:trading_balance_f/features/fractal_tracker/presentation/providers/fractal_provider.dart';
import 'package:trading_balance_f/features/market/presentation/providers/market_provider.dart';
import 'package:trading_balance_f/features/orders/data/okx_order_model.dart';
import 'package:trading_balance_f/features/orders/data/okx_position_model.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/order_provider.dart';
import 'package:trading_balance_f/features/portfolio/data/okx_balance_model.dart';
import 'package:trading_balance_f/features/portfolio/presentation/providers/portfolio_provider.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';

class _FakeOkxWebsocketService extends OkxWebsocketService {
  @override
  Stream<dynamic> get stream => const Stream.empty();

  @override
  void connect() {}

  @override
  void disconnect() {}

  @override
  void subscribeToTickers(List<String> coinSymbols) {}
}

void main() {
  testWidgets('shows all primary destinations and switches selected content', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          portfolioFutureProvider.overrideWith(
            (ref) async => const OkxAccountData(),
          ),
          livePriceProvider.overrideWith((ref) => LivePriceNotifier()),
          okxWebsocketProvider.overrideWithValue(_FakeOkxWebsocketService()),
          vndExchangeRateProvider.overrideWith((ref) async => 25400),
          fractalDataProvider.overrideWith((ref) async => <FractalData>[]),
          positionsFutureProvider.overrideWith((ref) async => <OkxPosition>[]),
          ordersFutureProvider.overrideWith((ref) async => <OkxOrder>[]),
          themeModeProvider.overrideWith((ref) => ThemeMode.light),
        ],
        child: const MaterialApp(home: MainNavigationShell()),
      ),
    );
    await tester.pump();

    expect(find.text('Trang chủ'), findsOneWidget);
    expect(find.text('BMAG'), findsNothing);
    expect(find.text('Lệnh'), findsNothing);
    expect(find.text('Thị trường'), findsNothing);
    expect(find.text('Cài đặt'), findsNothing);
    expect(TradingNavigationBar.items, hasLength(5));
    for (var index = 0; index < TradingNavigationBar.items.length; index++) {
      expect(find.byKey(Key('navigation-destination-$index')), findsOneWidget);
    }
    expect(find.text('Nhật ký'), findsNothing);
    expect(find.text('Ghi PnL'), findsNothing);
    expect(find.byTooltip('BMAG Matrix'), findsNothing);
    expect(find.byTooltip('Nhật ký PnL'), findsNothing);
    expect(find.byTooltip('Quản lý Lệnh'), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);

    await tester.tap(find.byKey(const Key('navigation-destination-1')));
    await tester.pump();
    expect(find.text('BMAG Tracker (BTC)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('navigation-destination-2')));
    await tester.pump();
    expect(find.text('Quản lý Giao dịch'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
