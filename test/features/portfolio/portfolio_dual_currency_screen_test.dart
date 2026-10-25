import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/currency/currency_display_mode.dart';
import 'package:trading_balance_f/core/exchange/exchange_account_providers.dart';
import 'package:trading_balance_f/core/exchange/exchange_models.dart';
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

ExchangePortfolioSourceData _okxSource({
  String asset = 'BTC',
  String balanceAmount = '1',
  String valuationAmount = '100',
  String pnlAmount = '10',
  bool accountPnlAvailable = true,
}) {
  final amount = ExchangeAmount.tryParse(balanceAmount)!;
  final valuation = ExchangeMoney.tryParse(valuationAmount, 'USDT')!;
  final pnl = ExchangeMoney.tryParse(pnlAmount, 'USDT')!;
  final balance = ExchangeBalance(
    source: ExchangeSource.okx,
    product: null,
    wallet: 'unified',
    asset: asset,
    free: ExchangeValue<ExchangeAmount>.available(amount),
    locked: ExchangeValue<ExchangeAmount>.available(
      ExchangeAmount.tryParse('0')!,
    ),
    reportedTotal: ExchangeValue<ExchangeAmount>.available(amount),
    reportedUsdValue: ExchangeValue<ExchangeMoney>.available(valuation),
    nativeRecord: OkxCoinDetail(
      ccy: asset,
      eq: balanceAmount,
      eqUsd: valuationAmount,
      upl:
          (double.parse(pnlAmount) *
                  double.parse(balanceAmount) /
                  double.parse(valuationAmount))
              .toString(),
    ),
  );
  final account = ExchangeAccountSnapshot(
    source: ExchangeSource.okx,
    product: null,
    generation: 0,
    balances: <ExchangeBalance>[balance],
    reportedEquity: ExchangeValue<ExchangeMoney>.available(valuation),
    unrealizedPnl: accountPnlAvailable
        ? ExchangeValue<ExchangeMoney>.available(pnl)
        : const ExchangeValue<ExchangeMoney>.unavailable(
            'Use native OKX balance-detail UPL in this fixture.',
          ),
    equityIncludesUnrealizedPnl: true,
  );
  final result = ExchangeAccountResult(
    source: ExchangeSource.okx,
    product: null,
    account: account,
  );
  return ExchangePortfolioSourceData(
    source: ExchangeSource.okx,
    product: null,
    result: result,
    rows: <PortfolioBalanceRow>[
      PortfolioBalanceRow(
        balance: balance,
        totalAmount: ExchangeValue<ExchangeAmount>.available(amount),
        valuation: ExchangeValue<ExchangeMoney>.available(valuation),
      ),
    ],
    credentialGeneration: 0,
    equityContribution: ExchangeValue<ExchangeAmount>.available(
      ExchangeAmount.tryParse(valuationAmount)!,
    ),
    valuationComplete: true,
  );
}

ExchangePortfolioSourceData _unavailableBinanceSource(ExchangeProduct product) {
  final result = ExchangeAccountResult(
    source: ExchangeSource.binance,
    product: product,
    account: null,
    error: 'Binance credentials are not configured in this fixture.',
    isTerminalFailure: true,
  );
  return ExchangePortfolioSourceData(
    source: ExchangeSource.binance,
    product: product,
    result: result,
    equityContribution: const ExchangeValue<ExchangeAmount>.unavailable(
      'Binance source is not configured in this fixture.',
    ),
    valuationComplete: false,
    warnings: <String>[result.error!],
  );
}

List<Override> _combinedPortfolioOverrides({
  required Future<ExchangePortfolioSourceData> Function() loadOkx,
}) => <Override>[
  okxPortfolioSourceProvider.overrideWith((ref) => loadOkx()),
  okxPortfolioValuationProvider.overrideWith(
    (ref) => ref.watch(okxPortfolioSourceProvider.future),
  ),
  binanceSpotPortfolioSourceProvider.overrideWith(
    (ref) async => _unavailableBinanceSource(ExchangeProduct.spot),
  ),
  binanceSpotPortfolioValuationProvider.overrideWith(
    (ref) => ref.watch(binanceSpotPortfolioSourceProvider.future),
  ),
  binanceFuturesPortfolioSourceProvider.overrideWith(
    (ref) async => _unavailableBinanceSource(ExchangeProduct.swap),
  ),
  binanceFuturesPortfolioValuationProvider.overrideWith(
    (ref) => ref.watch(binanceFuturesPortfolioSourceProvider.future),
  ),
];

void main() {
  testWidgets('manual Portfolio refresh waits for the current read', (
    tester,
  ) async {
    final api = TradeApiClient(baseUrl: 'https://trade.example');
    var loadCalls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._combinedPortfolioOverrides(
            loadOkx: () async {
              loadCalls++;
              return _okxSource(pnlAmount: '0');
            },
          ),
          tradeApiProvider.overrideWithValue(api),
          tradeSessionProvider.overrideWith(
            (ref) => _PortfolioAuthenticatedSessionController(api),
          ),
          livePriceProvider.overrideWith((ref) => LivePriceNotifier()),
          okxWebsocketProvider.overrideWithValue(_FakeOkxWebsocketService()),
          currencyProvider.overrideWith((ref) => CurrencyDisplayMode.usd),
          vndExchangeRateProvider.overrideWith((ref) async => 25400),
          themeModeProvider.overrideWith((ref) => ThemeMode.light),
          hideBalanceProvider.overrideWith((ref) => false),
        ],
        child: const MaterialApp(home: PortfolioScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(loadCalls, 1);
    expect(find.byTooltip('Làm mới dữ liệu'), findsOneWidget);

    await tester.tap(find.byKey(const Key('portfolio-manual-refresh')));
    await tester.pumpAndSettle();
    expect(loadCalls, 2);
    expect(find.byKey(const Key('portfolio-asset-summary')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Portfolio toolbar and pull refresh share one pending read', (
    tester,
  ) async {
    final api = TradeApiClient(baseUrl: 'https://trade.example');
    final pendingRate = Completer<double>();
    var rateLoads = 0;
    var portfolioLoads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._combinedPortfolioOverrides(
            loadOkx: () async {
              portfolioLoads++;
              return _okxSource(pnlAmount: '0');
            },
          ),
          tradeApiProvider.overrideWithValue(api),
          tradeSessionProvider.overrideWith(
            (ref) => _PortfolioAuthenticatedSessionController(api),
          ),
          livePriceProvider.overrideWith((ref) => LivePriceNotifier()),
          okxWebsocketProvider.overrideWithValue(_FakeOkxWebsocketService()),
          currencyProvider.overrideWith((ref) => CurrencyDisplayMode.usd),
          vndExchangeRateProvider.overrideWith((ref) {
            rateLoads++;
            return rateLoads == 1
                ? Future<double>.value(25400)
                : pendingRate.future;
          }),
          themeModeProvider.overrideWith((ref) => ThemeMode.light),
          hideBalanceProvider.overrideWith((ref) => false),
        ],
        child: const MaterialApp(home: PortfolioScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(rateLoads, 1);
    expect(portfolioLoads, 1);

    await tester.tap(find.byKey(const Key('portfolio-manual-refresh')));
    await tester.pump();
    expect(rateLoads, 2);
    expect(portfolioLoads, 2);
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    expect(rateLoads, 2);
    expect(portfolioLoads, 2);

    pendingRate.complete(25500);
    await tester.pumpAndSettle();
    expect(portfolioLoads, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Portfolio disposal during rate refresh starts no balance read', (
    tester,
  ) async {
    final api = TradeApiClient(baseUrl: 'https://trade.example');
    final pendingRate = Completer<double>();
    var rateLoads = 0;
    var portfolioLoads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._combinedPortfolioOverrides(
            loadOkx: () async {
              portfolioLoads++;
              return _okxSource(pnlAmount: '0');
            },
          ),
          tradeApiProvider.overrideWithValue(api),
          tradeSessionProvider.overrideWith(
            (ref) => _PortfolioAuthenticatedSessionController(api),
          ),
          livePriceProvider.overrideWith((ref) => LivePriceNotifier()),
          okxWebsocketProvider.overrideWithValue(_FakeOkxWebsocketService()),
          currencyProvider.overrideWith((ref) => CurrencyDisplayMode.usd),
          vndExchangeRateProvider.overrideWith((ref) {
            rateLoads++;
            return rateLoads == 1
                ? Future<double>.value(25400)
                : pendingRate.future;
          }),
          themeModeProvider.overrideWith((ref) => ThemeMode.light),
          hideBalanceProvider.overrideWith((ref) => false),
        ],
        child: const MaterialApp(home: PortfolioScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('portfolio-manual-refresh')));
    await tester.pump();
    expect(rateLoads, 2);
    expect(portfolioLoads, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    pendingRate.complete(25500);
    await tester.pump();
    await tester.pump();

    expect(portfolioLoads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Portfolio refresh waits for its loading request to finish', (
    tester,
  ) async {
    final pending = <Completer<ExchangePortfolioSourceData>>[];
    final api = TradeApiClient(baseUrl: 'https://trade.example');
    var loadCalls = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._combinedPortfolioOverrides(
            loadOkx: () {
              loadCalls++;
              final request = Completer<ExchangePortfolioSourceData>();
              pending.add(request);
              return request.future;
            },
          ),
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
    expect(find.byTooltip('Làm mới dữ liệu'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    expect(loadCalls, 1);

    pending.first.complete(_okxSource(pnlAmount: '0'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(loadCalls, 2);
    expect(find.byKey(const Key('portfolio-asset-summary')), findsOneWidget);

    pending.last.complete(_okxSource(pnlAmount: '0'));
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._combinedPortfolioOverrides(
            loadOkx: () async => _okxSource(pnlAmount: '10'),
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
    await tester.pump();

    expect(find.text('Tổng tài sản (USDT + VND)'), findsOneWidget);
    expect(find.text('100.00 USDT'), findsNWidgets(2));
    expect(find.text('≈ 2.540.000 đ'), findsNWidgets(2));
    expect(find.text('Vốn gốc'), findsOneWidget);
    expect(find.text('Lãi / lỗ chưa thực hiện'), findsOneWidget);
    expect(find.text('90.00 USDT'), findsOneWidget);
    expect(find.text('≈ 2.286.000 đ'), findsOneWidget);
    expect(find.text('+10.00 USDT'), findsOneWidget);
    expect(find.text('(+11.11%)'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('+10.00 USDT')).style?.color,
      PnlColors.lightPositive,
    );
    expect(
      tester.widget<Text>(find.text('(+11.11%)')).style?.color,
      PnlColors.lightPositive,
    );
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
    expect(find.text('******'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('main Portfolio keeps near-zero OKX PnL and ratio muted', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._combinedPortfolioOverrides(
            loadOkx: () async => _okxSource(pnlAmount: '0.001'),
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

  testWidgets(
    'main Portfolio uses native OKX detail PnL when account UPL is unavailable',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._combinedPortfolioOverrides(
              loadOkx: () async => _okxSource(accountPnlAvailable: false),
            ),
            livePriceProvider.overrideWith((ref) => LivePriceNotifier()),
            okxWebsocketProvider.overrideWithValue(_FakeOkxWebsocketService()),
            currencyProvider.overrideWith((ref) => CurrencyDisplayMode.usd),
            vndExchangeRateProvider.overrideWith((ref) async => 25400),
            themeModeProvider.overrideWith((ref) => ThemeMode.light),
            hideBalanceProvider.overrideWith((ref) => false),
          ],
          child: const MaterialApp(home: PortfolioScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text(r'$100.00'), findsNWidgets(2));
      expect(find.text(r'$90.00'), findsOneWidget);
      expect(find.text(r'+$10.00'), findsOneWidget);
      expect(find.text('(+11.11%)'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('T72 portfolio details uses dedicated PnL sign colors', (
    tester,
  ) async {
    final api = TradeApiClient(baseUrl: 'https://trade.example');
    var loadCalls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._combinedPortfolioOverrides(
            loadOkx: () async {
              loadCalls++;
              return _okxSource(pnlAmount: '10');
            },
          ),
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
        child: const MaterialApp(home: PortfolioDetailsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('portfolio-details-reveal-pnl')));
    await tester.pump();

    expect(find.text('+10.00 USDT'), findsOneWidget);
    expect(find.byTooltip('Làm mới dữ liệu'), findsOneWidget);
    await tester.tap(find.byTooltip('Làm mới dữ liệu'));
    await tester.pumpAndSettle();
    expect(loadCalls, 2);
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
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._combinedPortfolioOverrides(
            loadOkx: () async => _okxSource(pnlAmount: '0.001'),
          ),
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
    await tester.tap(find.byKey(const Key('portfolio-details-reveal-pnl')));
    await tester.pump();

    expect(
      tester.widget<Text>(find.text('+0.00 USDT')).style?.color,
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._combinedPortfolioOverrides(
            loadOkx: () async => _okxSource(pnlAmount: '0'),
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
