import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/currency/currency_display_mode.dart';
import 'package:trading_balance_f/core/network/okx_websocket_service.dart';
import 'package:trading_balance_f/core/theme/app_theme.dart';
import 'package:trading_balance_f/core/theme/pnl_color.dart';
import 'package:trading_balance_f/features/market/presentation/providers/market_provider.dart';
import 'package:trading_balance_f/features/portfolio/data/okx_balance_model.dart';
import 'package:trading_balance_f/features/portfolio/presentation/portfolio_screen.dart';
import 'package:trading_balance_f/features/portfolio/presentation/portfolio_details_screen.dart';
import 'package:trading_balance_f/features/portfolio/presentation/providers/portfolio_provider.dart';
import 'package:trading_balance_f/features/portfolio/presentation/widgets/portfolio_currency_amount.dart';
import 'package:trading_balance_f/features/orders/data/trade_api_client.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/trade_session_provider.dart';
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

class _TrackingOkxWebsocketService extends OkxWebsocketService {
  _TrackingOkxWebsocketService(this.controller);

  final StreamController<dynamic> controller;
  int connectCalls = 0;
  int disconnectCalls = 0;

  @override
  Stream<dynamic> get stream => controller.stream;

  @override
  void connect() {
    connectCalls++;
  }

  @override
  void subscribeToTickers(List<String> coinSymbols) {}

  @override
  void disconnect() {
    disconnectCalls++;
  }
}

void main() {
  testWidgets('Portfolio refresh waits for its loading request to finish', (
    tester,
  ) async {
    const account = OkxAccountData(
      details: [OkxCoinDetail(ccy: 'BTC', eq: '1', eqUsd: '100', upl: '0')],
    );
    final pending = <Completer<OkxAccountData>>[];
    final api = TradeApiClient(baseUrl: 'https://trade.example');
    var loadCalls = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          portfolioFutureProvider.overrideWith((ref) {
            loadCalls++;
            final request = Completer<OkxAccountData>();
            pending.add(request);
            return request.future;
          }),
          tradeApiProvider.overrideWithValue(api),
          tradeSessionProvider.overrideWith(
            (ref) => _PortfolioAuthenticatedSessionController(api),
          ),
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
    expect(loadCalls, 1);

    await tester.pump(const Duration(seconds: 5));
    expect(loadCalls, 1);

    pending.first.complete(account);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(loadCalls, 2);
    expect(find.byKey(const Key('portfolio-asset-summary')), findsOneWidget);

    pending.last.complete(account);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'live price disposal cancels its poll stream without starting polling',
    () async {
      final canceled = Completer<void>();
      final stream = StreamController<dynamic>.broadcast(
        onCancel: canceled.complete,
      );
      final service = _TrackingOkxWebsocketService(stream);
      final container = ProviderContainer(
        overrides: [
          okxWebsocketProvider.overrideWith((ref) {
            ref.onDispose(service.disconnect);
            return service;
          }),
        ],
      );
      final listener = container.listen(livePriceProvider, (_, _) {});

      expect(service.connectCalls, 0);
      listener.close();
      await container.pump();
      await canceled.future.timeout(const Duration(seconds: 1));

      expect(service.disconnectCalls, 1);
      container.dispose();
      await stream.close();
    },
  );

  testWidgets('renders direct Portfolio summary and dual currency amounts', (
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

    expect(find.text('Tổng tài sản (USDT + VND)'), findsOneWidget);
    expect(find.text('100.00 USDT'), findsNWidgets(2));
    expect(find.text('≈ 2.540.000 đ'), findsNWidgets(2));
    expect(find.text('Vốn gốc'), findsOneWidget);
    expect(find.text('Lãi / lỗ chưa thực hiện'), findsOneWidget);
    expect(find.text('+10.00 USDT'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('+10.00 USDT')).style?.color,
      PnlColors.lightPositive,
    );
    expect(find.text('≈ +254.000 đ'), findsOneWidget);
    expect(find.text('Tài sản chi tiết'), findsOneWidget);
    expect(find.text('BTC'), findsOneWidget);
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

  testWidgets('T72 portfolio details uses dedicated PnL sign colors', (
    tester,
  ) async {
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
        child: const MaterialApp(home: PortfolioDetailsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('portfolio-reveal-pnl')));
    await tester.pump();

    expect(find.text('+10.00 USDT'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('+10.00 USDT')).style?.color,
      PnlColors.lightPositive,
    );
    expect(
      tester.widget<Text>(find.text('(+11.11%)')).style?.color,
      PnlColors.lightPositive,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('T72 near-zero portfolio PnL amount and percent stay muted', (
    tester,
  ) async {
    const account = OkxAccountData(
      details: [
        OkxCoinDetail(ccy: 'BTC', eq: '1', eqUsd: '100', upl: '0.00001'),
      ],
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

    expect(
      tester.widget<Text>(find.text('+0.00 USDT')).style?.color,
      AppPalette.light.muted,
    );
    expect(
      tester.widget<Text>(find.text('(+0.00%)')).style?.color,
      AppPalette.light.muted,
    );
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

    final summary = find.byKey(const Key('portfolio-asset-summary'));
    expect(summary, findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _PortfolioAuthenticatedSessionController extends TradeSessionController {
  _PortfolioAuthenticatedSessionController(super.api) {
    state = TradeSessionState(
      session: TradeSession(
        bearerToken: 'test-token',
        accountIdentifier: 'test-account',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
  }
}
