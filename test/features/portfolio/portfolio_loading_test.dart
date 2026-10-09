import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/currency/currency_display_mode.dart';
import 'package:trading_balance_f/core/network/backend_data_client.dart';
import 'package:trading_balance_f/core/network/backend_data_session.dart';
import 'package:trading_balance_f/core/network/foreground_read_gate.dart';
import 'package:trading_balance_f/core/network/okx_websocket_service.dart';
import 'package:trading_balance_f/core/theme/app_theme.dart';
import 'package:trading_balance_f/features/market/presentation/providers/market_provider.dart';
import 'package:trading_balance_f/features/orders/data/trade_api_client.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/trade_session_provider.dart';
import 'package:trading_balance_f/features/portfolio/data/okx_balance_model.dart';
import 'package:trading_balance_f/features/portfolio/presentation/portfolio_screen.dart';
import 'package:trading_balance_f/features/portfolio/presentation/providers/portfolio_provider.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';

void main() {
  testWidgets('old portfolio data is hidden while replacement session loads', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = TradeApiClient(baseUrl: 'https://trade.example');
    final controller = _PortfolioSessionController(api);
    final adapter = _PendingPortfolioAdapter();
    final client = BackendDataClient(
      dio: Dio()..httpClientAdapter = adapter,
      baseUrl: 'https://data.example',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tradeApiProvider.overrideWithValue(api),
          tradeSessionProvider.overrideWith((ref) => controller),
          backendDataClientProvider.overrideWithValue(client),
          foregroundReadGateProvider.overrideWith((ref) {
            final gate = ForegroundReadGate(now: tester.binding.clock.now);
            ref.onDispose(gate.dispose);
            return gate;
          }),
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

    await tester.pump(const Duration(milliseconds: 1));
    expect(adapter.responses, hasLength(1));
    adapter.reply(0, 200, _balancePayload('100'));
    await _pumpPortfolioUntil(
      tester,
      () => find
          .byKey(const Key('portfolio-asset-summary'))
          .evaluate()
          .isNotEmpty,
    );
    expect(find.byKey(const Key('portfolio-asset-summary')), findsOneWidget);

    controller.replace(_activeSession(accountIdentifier: 'account-b'));
    await _pumpPortfolioUntil(tester, () => adapter.responses.length == 2);
    expect(adapter.responses, hasLength(2));
    expect(find.byKey(const Key('portfolio-asset-summary')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    adapter.reply(1, 200, _balancePayload('200'));
    await _pumpPortfolioUntil(
      tester,
      () => find
          .byKey(const Key('portfolio-asset-summary'))
          .evaluate()
          .isNotEmpty,
    );
    expect(find.byKey(const Key('portfolio-asset-summary')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('production portfolio provider skips reads during restoration', (
    tester,
  ) async {
    final api = TradeApiClient(baseUrl: 'https://trade.example');
    final controller = _PortfolioSessionController(api, loading: true);
    final adapter = _ImmediatePortfolioAdapter(200, _balancePayload('100'));
    final container = _portfolioContainer(
      controller,
      adapter,
      now: tester.binding.clock.now,
    );
    final subscription = container.listen(portfolioFutureProvider, (_, _) {});
    var sessionChanges = 0;
    final sessionSubscription = container.listen(
      tradeSessionProvider,
      (_, _) => sessionChanges++,
    );
    var generationChanges = 0;
    final generationSubscription = container.listen(
      backendDataSessionProvider.select((session) => session.generation),
      (_, _) => generationChanges++,
    );

    await tester.pump();
    expect(adapter.requests, 0);
    controller.replace(_activeSession());
    expect(container.read(tradeSessionProvider).isLoading, isFalse);
    expect(container.read(tradeSessionProvider).session, isNotNull);
    expect(sessionChanges, 1);
    expect(generationChanges, 1);
    await _flushPortfolio(tester, container);
    for (var attempts = 0; attempts < 5 && adapter.requests == 0; attempts++) {
      await tester.pump();
    }
    expect(adapter.requests, 1);
    expect(container.read(portfolioFutureProvider).hasValue, isTrue);

    subscription.close();
    sessionSubscription.close();
    generationSubscription.close();
    await _flushPortfolio(tester, container);
    container.dispose();
  });

  testWidgets('production portfolio cooldown survives screen re-entry', (
    tester,
  ) async {
    final api = TradeApiClient(baseUrl: 'https://trade.example');
    final controller = _PortfolioSessionController(api);
    final adapter = _ImmediatePortfolioAdapter(
      429,
      {'message': 'limited'},
      headers: {
        'retry-after': ['120'],
      },
    );
    final container = _portfolioContainer(
      controller,
      adapter,
      now: tester.binding.clock.now,
    );
    final first = container.listen(portfolioFutureProvider, (_, _) {});

    await _flushPortfolio(tester, container);
    expect(adapter.requests, 1);
    expect(container.read(portfolioFutureProvider).hasError, isTrue);
    first.close();
    await _flushPortfolio(tester, container);
    await tester.pump(const Duration(seconds: 30));

    final reentered = container.listen(portfolioFutureProvider, (_, _) {});
    await tester.pump();
    expect(adapter.requests, 1);
    await tester.pump(const Duration(seconds: 89));
    expect(adapter.requests, 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump();
    expect(adapter.requests, 2);

    reentered.close();
    await _flushPortfolio(tester, container);
    container.dispose();
  });

  testWidgets('operation-only changes do not restart production balance read', (
    tester,
  ) async {
    final api = TradeApiClient(baseUrl: 'https://trade.example');
    final controller = _PortfolioSessionController(api);
    final adapter = _PendingPortfolioAdapter();
    final container = _portfolioContainer(
      controller,
      adapter,
      now: tester.binding.clock.now,
    );
    final subscription = container.listen(portfolioFutureProvider, (_, _) {});

    await _flushPortfolio(tester, container);
    expect(adapter.responses, hasLength(1));
    controller.rememberOperation(
      const PendingTradeOperation(
        operationId: 'portfolio-operation',
        action: 'close_position',
        targetLabel: 'BTC-USDT-SWAP',
        status: 'IN_PROGRESS',
      ),
    );
    await _flushPortfolio(tester, container);
    expect(adapter.responses, hasLength(1));

    adapter.reply(0, 200, _balancePayload('100'));
    await _pumpPortfolioUntil(
      tester,
      () => container.read(portfolioFutureProvider).hasValue,
    );
    expect(container.read(portfolioFutureProvider).value?.totalEq, '100');

    subscription.close();
    await _flushPortfolio(tester, container);
    container.dispose();
  });

  testWidgets('production portfolio rejects a stale session response', (
    tester,
  ) async {
    final api = TradeApiClient(baseUrl: 'https://trade.example');
    final controller = _PortfolioSessionController(api);
    final adapter = _PendingPortfolioAdapter();
    final container = _portfolioContainer(
      controller,
      adapter,
      now: tester.binding.clock.now,
    );
    final subscription = container.listen(portfolioFutureProvider, (_, _) {});

    await _flushPortfolio(tester, container);
    expect(adapter.responses, hasLength(1));
    controller.replace(_activeSession(accountIdentifier: 'account-b'));
    await _pumpPortfolioUntil(tester, () => adapter.responses.length == 2);
    expect(adapter.responses, hasLength(2));

    adapter.reply(0, 200, _balancePayload('100'));
    await tester.pump(const Duration(milliseconds: 1));
    expect(container.read(portfolioFutureProvider).hasValue, isFalse);

    adapter.reply(1, 200, _balancePayload('200'));
    await _pumpPortfolioUntil(
      tester,
      () => container.read(portfolioFutureProvider).hasValue,
    );
    expect(container.read(portfolioFutureProvider).value?.totalEq, '200');

    subscription.close();
    await _flushPortfolio(tester, container);
    container.dispose();
  });

  testWidgets('Portfolio polling stops after terminal configuration error', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = TradeApiClient(baseUrl: 'https://trade.example');
    var loadCalls = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tradeApiProvider.overrideWithValue(api),
          tradeSessionProvider.overrideWith(
            (ref) => _PortfolioSessionController(api),
          ),
          portfolioFutureProvider.overrideWith((ref) async {
            loadCalls++;
            throw const BackendDataException(
              code: 'api_not_configured',
              message: 'Not configured.',
            );
          }),
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
    expect(loadCalls, 1);
    await tester.pump(const Duration(seconds: 30));
    expect(loadCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('session restoration and initial read stay in loading state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = TradeApiClient(baseUrl: 'https://trade.example');
    final sessionController = _PortfolioSessionController(api, loading: true);
    final initialRead = Completer<OkxAccountData>();
    var loadCalls = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tradeApiProvider.overrideWithValue(api),
          tradeSessionProvider.overrideWith((ref) => sessionController),
          portfolioFutureProvider.overrideWith((ref) {
            ref.watch(tradeSessionProvider.select((state) => state.isLoading));
            ref.watch(tradeSessionProvider.select((state) => state.session));
            if (ref.read(tradeSessionProvider).isLoading) {
              throw const BackendDataException(
                code: 'session_loading',
                message: 'Restoring session.',
              );
            }
            loadCalls++;
            return initialRead.future;
          }),
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
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('Lỗi kết nối'), findsNothing);
    expect(loadCalls, 0);

    sessionController.replace(_activeSession());
    await tester.pump();
    await tester.pump();
    expect(loadCalls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('Lỗi kết nối'), findsNothing);

    initialRead.complete(
      const OkxAccountData(
        details: [OkxCoinDetail(ccy: 'BTC', eq: '1', eqUsd: '100', upl: '0')],
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('portfolio-asset-summary')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('completed error stays visible until a pending retry begins', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = TradeApiClient(baseUrl: 'https://trade.example');
    final sessionController = _PortfolioSessionController(api);
    final retry = Completer<OkxAccountData>();
    var loadCalls = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tradeApiProvider.overrideWithValue(api),
          tradeSessionProvider.overrideWith((ref) => sessionController),
          portfolioFutureProvider.overrideWith((ref) {
            ref.watch(tradeSessionProvider.select((state) => state.isLoading));
            ref.watch(tradeSessionProvider.select((state) => state.session));
            loadCalls++;
            if (loadCalls == 1)
              return Future.error(Exception('balance failed'));
            return retry.future;
          }),
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
    expect(find.textContaining('balance failed'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(loadCalls, 2);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('balance failed'), findsNothing);

    retry.completeError(Exception('retry failed'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('retry failed'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

ProviderContainer _portfolioContainer(
  _PortfolioSessionController controller,
  HttpClientAdapter adapter, {
  required DateTime Function() now,
}) {
  final client = BackendDataClient(
    dio: Dio()..httpClientAdapter = adapter,
    baseUrl: 'https://data.example',
  );
  return ProviderContainer(
    overrides: [
      tradeSessionProvider.overrideWith((ref) => controller),
      backendDataClientProvider.overrideWithValue(client),
      foregroundReadGateProvider.overrideWith((ref) {
        final gate = ForegroundReadGate(now: now);
        ref.onDispose(gate.dispose);
        return gate;
      }),
    ],
  );
}

Future<void> _flushPortfolio(WidgetTester tester, ProviderContainer _) async {
  await tester.pump(const Duration(milliseconds: 1));
}

Future<void> _pumpPortfolioUntil(
  WidgetTester tester,
  bool Function() isReady,
) async {
  for (var attempt = 0; attempt < 20 && !isReady(); attempt++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Map<String, Object> _balancePayload(String totalEq) => {
  'code': '0',
  'data': [
    {'totalEq': totalEq, 'details': []},
  ],
};

ResponseBody _portfolioResponse(
  int statusCode,
  Object body, {
  Map<String, List<String>> headers = const {},
}) => ResponseBody.fromString(
  jsonEncode(body),
  statusCode,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
    ...headers,
  },
);

class _ImmediatePortfolioAdapter implements HttpClientAdapter {
  _ImmediatePortfolioAdapter(
    this.statusCode,
    this.body, {
    this.headers = const {},
  });

  final int statusCode;
  final Object body;
  final Map<String, List<String>> headers;
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    return _portfolioResponse(statusCode, body, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

class _PendingPortfolioAdapter implements HttpClientAdapter {
  final List<Completer<ResponseBody>> responses = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final response = Completer<ResponseBody>();
    responses.add(response);
    return response.future;
  }

  void reply(int index, int statusCode, Object body) {
    responses[index].complete(_portfolioResponse(statusCode, body));
  }

  @override
  void close({bool force = false}) {}
}

class _PortfolioSessionController extends TradeSessionController {
  _PortfolioSessionController(super.api, {bool loading = false}) {
    state = TradeSessionState(isLoading: loading);
    if (!loading) replace(_activeSession());
  }

  void replace(TradeSession session) {
    state = TradeSessionState(session: session);
  }
}

TradeSession _activeSession({String accountIdentifier = 'test-account'}) =>
    TradeSession(
      bearerToken: 'test-token-$accountIdentifier',
      accountIdentifier: accountIdentifier,
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );

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
