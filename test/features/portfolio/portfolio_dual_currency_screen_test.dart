import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/currency/currency_display_mode.dart';
import 'package:trading_balance_f/core/network/okx_websocket_service.dart';
import 'package:trading_balance_f/features/market/presentation/providers/market_provider.dart';
import 'package:trading_balance_f/features/portfolio/data/okx_balance_model.dart';
import 'package:trading_balance_f/features/portfolio/presentation/portfolio_screen.dart';
import 'package:trading_balance_f/features/portfolio/presentation/providers/portfolio_provider.dart';
import 'package:trading_balance_f/features/portfolio/presentation/widgets/portfolio_currency_amount.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';

class _FakeOkxWebsocketService extends OkxWebsocketService {
  @override
  Stream<dynamic> get stream => const Stream.empty();

  @override
  void connect() {}

  @override
  void subscribeToTickers(List<String> coinSymbols) {}

  @override
  void disconnect() {}
}

void main() {
  testWidgets(
    'shows dual amounts across Portfolio and hides both currency lines',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const account = OkxAccountData(
        details: [OkxCoinDetail(ccy: 'BTC', eq: '1', eqUsd: '100', upl: '0.1')],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            portfolioFutureProvider.overrideWith((ref) async => account),
            livePriceProvider.overrideWith((ref) => LivePriceNotifier()),
            okxWebsocketProvider.overrideWithValue(_FakeOkxWebsocketService()),
            currencyProvider.overrideWith((ref) => CurrencyDisplayMode.usdtVnd),
            vndExchangeRateProvider.overrideWith((ref) async => 25400),
            themeModeProvider.overrideWith((ref) => ThemeMode.light),
            hideBalanceProvider.overrideWith((ref) => false),
          ],
          child: const MaterialApp(home: PortfolioScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Tổng tài sản (USDT + VND)'), findsOneWidget);
      expect(find.text('100.00 USDT'), findsNWidgets(2));
      expect(find.text('≈ 2.540.000 đ'), findsNWidgets(2));
      expect(find.text('Vốn gốc: 90.00 USDT'), findsOneWidget);
      expect(find.text('≈ 2.286.000 đ'), findsOneWidget);
      expect(find.text('+10.00 USDT'), findsOneWidget);
      expect(find.text('≈ +254.000 đ'), findsOneWidget);
      expect(find.byType(PortfolioCurrencyAmount), findsNWidgets(4));

      await tester.tap(find.byIcon(Icons.visibility));
      await tester.pump();

      final amountWidgets = tester.widgetList<PortfolioCurrencyAmount>(
        find.byType(PortfolioCurrencyAmount),
      );
      expect(amountWidgets, hasLength(4));
      expect(amountWidgets.every((widget) => widget.hidden), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
