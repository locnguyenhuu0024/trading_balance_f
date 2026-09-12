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
  testWidgets('reveals dual amounts only from explicit Portfolio details', (
    tester,
  ) async {
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

    expect(find.text('100.00 USDT'), findsNothing);
    expect(find.textContaining('Unrealized PnL'), findsNothing);
    await tester.tap(find.byKey(const Key('portfolio-details')));
    await tester.pumpAndSettle();

    expect(find.text('Total assets (USDT + VND)'), findsOneWidget);
    expect(find.text('100.00 USDT'), findsNWidgets(2));
    expect(find.text('≈ 2.540.000 đ'), findsNWidgets(2));
    expect(find.text('Principal / base capital'), findsOneWidget);
    expect(find.byKey(const Key('portfolio-reveal-pnl')), findsOneWidget);
    expect(find.textContaining('Unrealized PnL'), findsNothing);
    await tester.tap(find.byKey(const Key('portfolio-reveal-pnl')));
    await tester.pump();
    expect(find.text('Unrealized PnL'), findsOneWidget);
    expect(find.text('+10.00 USDT'), findsOneWidget);
    expect(find.text('≈ +254.000 đ'), findsOneWidget);
    expect(find.byType(PortfolioCurrencyAmount), findsNWidgets(4));

    await tester.tap(find.byIcon(Icons.visibility).first);
    await tester.pump();

    final amountWidgets = tester.widgetList<PortfolioCurrencyAmount>(
      find.byType(PortfolioCurrencyAmount),
    );
    expect(amountWidgets, hasLength(4));
    expect(amountWidgets.every((widget) => widget.hidden), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('keeps explicit details readable on compact widths', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const account = OkxAccountData(
      details: [OkxCoinDetail(ccy: 'BTC', eq: '1', eqUsd: '100', upl: '0')],
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

    await tester.tap(find.byKey(const Key('portfolio-details')));
    await tester.pumpAndSettle();
    final summary = find.byKey(const Key('portfolio-details-summary'));
    expect(summary, findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
