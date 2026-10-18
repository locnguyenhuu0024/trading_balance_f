import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/currency/currency_display_mode.dart';
import 'package:trading_balance_f/core/network/foreground_read_gate.dart';
import 'package:trading_balance_f/core/network/okx_data_client.dart';
import 'package:trading_balance_f/core/network/okx_read_scope.dart';
import 'package:trading_balance_f/core/network/okx_websocket_service.dart';
import 'package:trading_balance_f/core/network/request_coordinator.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/features/market/presentation/providers/market_provider.dart';
import 'package:trading_balance_f/features/orders/data/trade_api_client.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/trade_session_provider.dart';
import 'package:trading_balance_f/features/portfolio/data/okx_balance_model.dart';
import 'package:trading_balance_f/features/portfolio/presentation/portfolio_screen.dart';
import 'package:trading_balance_f/features/portfolio/presentation/providers/portfolio_provider.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';

void main() {
  testWidgets(
    'signed-out direct balance loads and manual refresh works during restoration',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = TradeApiClient(baseUrl: 'https://trade.example');
      final session = _PortfolioSessionController(api, loading: true);
      final adapter = _PendingPortfolioAdapter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._directClientOverrides(adapter, tester.binding.clock.now),
            tradeApiProvider.overrideWithValue(api),
            tradeSessionProvider.overrideWith((ref) => session),
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
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PortfolioScreen)),
      );

      await _pumpPortfolioUntil(tester, () => adapter.responses.length == 1);
      expect(session.state.isLoading, isTrue);
      expect(adapter.requests.single.uri.path, '/api/v5/account/balance');
      adapter.reply(0, 200, _balancePayload('100'));
      await _pumpPortfolioUntil(
        tester,
        () => find
            .byKey(const Key('portfolio-asset-summary'))
            .evaluate()
            .isNotEmpty,
      );
      expect(find.byKey(const Key('portfolio-asset-summary')), findsOneWidget);
      expect(session.state.session, isNull);

      await tester.tap(find.byKey(const Key('portfolio-manual-refresh')));
      await _pumpPortfolioUntil(tester, () => adapter.responses.length == 2);
      expect(adapter.requests, hasLength(2));
      adapter.reply(1, 200, _balancePayload('200'));
      await _pumpPortfolioUntil(
        tester,
        () => container.read(portfolioFutureProvider).value?.totalEq == '200',
      );
      expect(container.read(portfolioFutureProvider).value?.totalEq, '200');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('credential generation fences a late balance response', (
    tester,
  ) async {
    final adapter = _PendingPortfolioAdapter();
    final container = ProviderContainer(
      overrides: _directClientOverrides(adapter, tester.binding.clock.now),
    );
    final storage =
        container.read(secureStorageProvider) as _PortfolioCredentialStorage;
    final subscription = container.listen(portfolioFutureProvider, (_, _) {});
    addTearDown(() {
      subscription.close();
      container.dispose();
    });

    await _waitFor(tester, () => adapter.responses.length == 1);
    await storage.rotate();
    await _waitFor(tester, () => adapter.responses.length == 2);

    adapter.reply(0, 200, _balancePayload('100'));
    await tester.pump();
    expect(container.read(portfolioFutureProvider).hasValue, isFalse);

    adapter.reply(1, 200, _balancePayload('200'));
    await _waitPortfolioProvider(container, tester);
    expect(container.read(portfolioFutureProvider).value?.totalEq, '200');
  });

  testWidgets('rate-limit cooldown survives portfolio screen re-entry', (
    tester,
  ) async {
    final api = TradeApiClient(baseUrl: 'https://trade.example');
    final adapter = _ImmediatePortfolioAdapter(
      429,
      {'code': '50011', 'msg': 'limited', 'data': []},
      headers: {
        'retry-after': ['120'],
      },
    );
    final container = _portfolioContainer(
      _PortfolioSessionController(api),
      adapter,
      now: tester.binding.clock.now,
    );
    final first = container.listen(portfolioFutureProvider, (_, _) {});

    await _flushPortfolio(tester);
    expect(adapter.requests, 1);
    expect(container.read(portfolioFutureProvider).hasError, isTrue);
    first.close();
    await _flushPortfolio(tester);
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
    await _flushPortfolio(tester);
    container.dispose();
  });

  testWidgets('backend session changes do not restart a direct balance read', (
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

    await _flushPortfolio(tester);
    expect(adapter.responses, hasLength(1));
    controller.replace(_activeSession(accountIdentifier: 'account-b'));
    await _flushPortfolio(tester);
    expect(adapter.responses, hasLength(1));

    adapter.reply(0, 200, _balancePayload('100'));
    await _waitPortfolioProvider(container, tester);
    expect(container.read(portfolioFutureProvider).value?.totalEq, '100');

    subscription.close();
    await _flushPortfolio(tester);
    container.dispose();
  });

  testWidgets('operation-only backend state does not restart a direct read', (
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

    await _flushPortfolio(tester);
    expect(adapter.responses, hasLength(1));
    controller.rememberOperation(
      const PendingTradeOperation(
        operationId: 'portfolio-operation',
        action: 'close_position',
        targetLabel: 'BTC-USDT-SWAP',
        status: 'IN_PROGRESS',
      ),
    );
    await _flushPortfolio(tester);
    expect(adapter.responses, hasLength(1));

    adapter.reply(0, 200, _balancePayload('100'));
    await _waitPortfolioProvider(container, tester);
    expect(container.read(portfolioFutureProvider).value?.totalEq, '100');

    subscription.close();
    await _flushPortfolio(tester);
    container.dispose();
  });

  testWidgets('terminal local credential errors stop automatic polling', (
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
            throw const OkxDataException(
              code: 'okx_credentials_required',
              message: 'Add OKX API credentials.',
              statusCode: 401,
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

  testWidgets('completed error stays visible until a pending retry begins', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = TradeApiClient(baseUrl: 'https://trade.example');
    final retry = Completer<OkxAccountData>();
    var loadCalls = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tradeApiProvider.overrideWithValue(api),
          tradeSessionProvider.overrideWith(
            (ref) => _PortfolioSessionController(api),
          ),
          portfolioFutureProvider.overrideWith((ref) {
            loadCalls++;
            if (loadCalls == 1) {
              return Future.error(Exception('balance failed'));
            }
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

List<Override> _directClientOverrides(
  HttpClientAdapter adapter,
  DateTime Function() now,
) => [
  secureStorageProvider.overrideWith((ref) {
    final storage = _PortfolioCredentialStorage();
    ref.onDispose(storage.dispose);
    return storage;
  }),
  okxDirectReadGateProvider.overrideWith((ref) {
    final gate = ForegroundReadGate(now: now);
    ref.onDispose(gate.dispose);
    return gate;
  }),
  okxDataClientProvider.overrideWith((ref) {
    final storage = ref.watch(secureStorageProvider);
    final client = OkxDataClient(
      dio: Dio()..httpClientAdapter = adapter,
      secureStorage: storage,
      requestCoordinator: RequestCoordinator(
        clock: now,
        minimumSpacing: Duration.zero,
        delay: (_) async {},
      ),
    );
    ref.onDispose(client.dispose);
    return client;
  }),
];

ProviderContainer _portfolioContainer(
  _PortfolioSessionController controller,
  HttpClientAdapter adapter, {
  required DateTime Function() now,
}) => ProviderContainer(
  overrides: [
    ..._directClientOverrides(adapter, now),
    tradeSessionProvider.overrideWith((ref) => controller),
  ],
);

class _PortfolioCredentialStorage extends SecureStorageHelper {
  _PortfolioCredentialStorage() : super(const FlutterSecureStorage());

  Future<void> rotate() => trackOkxCredentialMutation(() async {});

  @override
  Future<String?> getOkxApiKey() async => 'fixture-key';

  @override
  Future<String?> getOkxSecretKey() async => 'fixture-secret';

  @override
  Future<String?> getOkxPassphrase() async => 'fixture-passphrase';
}

Future<void> _flushPortfolio(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 1));
}

Future<void> _pumpPortfolioUntil(
  WidgetTester tester,
  bool Function() isReady,
) async {
  for (var attempt = 0; attempt < 40 && !isReady(); attempt++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Future<void> _waitFor(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(condition(), isTrue, reason: 'Timed out waiting for condition.');
}

Future<void> _waitPortfolioProvider(
  ProviderContainer container,
  WidgetTester tester,
) async {
  for (
    var attempt = 0;
    attempt < 40 && !container.read(portfolioFutureProvider).hasValue;
    attempt++
  ) {
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
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
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
