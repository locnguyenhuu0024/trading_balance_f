import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/exchange/binance_exchange_reader.dart';
import 'package:trading_balance_f/core/exchange/binance_history_scan.dart';
import 'package:trading_balance_f/core/exchange/exchange_account_providers.dart';
import 'package:trading_balance_f/core/exchange/exchange_models.dart';
import 'package:trading_balance_f/core/exchange/exchange_readers.dart';
import 'package:trading_balance_f/core/exchange/okx_exchange_reader.dart';
import 'package:trading_balance_f/core/network/binance_data_client.dart';
import 'package:trading_balance_f/core/network/binance_request_coordinator.dart';
import 'package:trading_balance_f/core/network/okx_data_client.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/core/timezone/app_time_zone.dart';
import 'package:trading_balance_f/features/orders/data/okx_order_model.dart';
import 'package:trading_balance_f/features/orders/data/okx_position_model.dart';
import 'package:trading_balance_f/features/orders/data/order_repository.dart';
import 'package:trading_balance_f/features/orders/data/trade_api_client.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/order_cancellation_flow_provider.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/position_action_flow_provider.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/trade_session_provider.dart';
import 'package:trading_balance_f/features/orders/presentation/widgets/order_notional.dart';
import 'package:trading_balance_f/features/orders/presentation/orders_screen.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/order_provider.dart';
import 'package:trading_balance_f/features/portfolio/data/portfolio_repository.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';

class _Storage extends SecureStorageHelper {
  _Storage() : super(const FlutterSecureStorage());

  @override
  Future<String?> getOkxApiKey() async => 'fixture';

  @override
  Future<String?> getOkxSecretKey() async => 'fixture';

  @override
  Future<String?> getOkxPassphrase() async => 'fixture';

  @override
  Future<String?> getBinanceCredentialBundle() async => null;
}

class _OkxReader extends OkxExchangeReader {
  _OkxReader({
    this.pending = const <ExchangeOrder>[],
    this.history = const <ExchangeOrder>[],
    this.positions = const <ExchangePosition>[],
    this.pendingGate,
    this.historyGate,
    this.positionsGate,
  }) : super(
         portfolioRepository: PortfolioRepository(OkxDataClient()),
         orderRepository: OrderRepository(OkxDataClient()),
       );

  final List<ExchangeOrder> pending;
  final List<ExchangeOrder> history;
  final List<ExchangePosition> positions;
  final Completer<void>? pendingGate;
  final Completer<void>? historyGate;
  final Completer<void>? positionsGate;
  int positionCalls = 0;
  int pendingCalls = 0;

  @override
  Future<List<ExchangeOrder>> getPendingOrders({
    String instType = 'ALL',
    CancelToken? cancelToken,
  }) async {
    pendingCalls++;
    await pendingGate?.future;
    return pending;
  }

  @override
  Future<List<ExchangeOrder>> getOrdersHistory({
    String instType = 'ALL',
    CancelToken? cancelToken,
  }) async {
    await historyGate?.future;
    return history;
  }

  @override
  Future<List<ExchangePosition>> getOpenPositions({
    String instType = 'ALL',
    CancelToken? cancelToken,
  }) async {
    positionCalls++;
    await positionsGate?.future;
    return positions;
  }
}

class _BinanceReader extends BinanceExchangeReader {
  _BinanceReader({
    required ValueListenable<BinanceCredentialSnapshot> credentialState,
    this.denyPrivateReads = false,
    this.pendingSpot = const <ExchangeOrder>[],
    this.pendingFutures = const <ExchangeOrder>[],
    this.positions = const <ExchangePosition>[],
    this.positionIssues = const <ExchangeReadIssue>[],
    this.pendingSpotGate,
    this.pendingFuturesGate,
    this.positionsGate,
  }) : super(
         client: BinanceDataClient(dio: Dio()),
         credentialState: credentialState,
         requestCoordinator: BinanceRequestCoordinator(
           minimumSpacing: Duration.zero,
           delay: (_) async {},
         ),
       );

  final List<ExchangeOrder> pendingSpot;
  final List<ExchangeOrder> pendingFutures;
  final List<ExchangePosition> positions;
  final List<ExchangeReadIssue> positionIssues;
  final bool denyPrivateReads;
  final Completer<void>? pendingSpotGate;
  final Completer<void>? pendingFuturesGate;
  int pendingSpotCalls = 0;
  int pendingFuturesCalls = 0;
  int positionCalls = 0;
  final Completer<void>? positionsGate;

  bool _usable(BinanceCredentialSnapshot? expected) =>
      !denyPrivateReads && (expected == null || expected.canUsePrivateReads);

  @override
  Future<List<ExchangeOrder>> getSpotOpenOrders({
    CancelToken? cancelToken,
    BinanceCredentialSnapshot? expectedGeneration,
  }) async {
    pendingSpotCalls++;
    if (!_usable(expectedGeneration))
      throw const ExchangeReadException(
        code: 'binance_credentials_required',
        message: 'Binance credentials are required.',
      );
    await pendingSpotGate?.future;
    return pendingSpot;
  }

  @override
  Future<List<ExchangeOrder>> getFuturesOpenOrders({
    CancelToken? cancelToken,
    BinanceCredentialSnapshot? expectedGeneration,
  }) async {
    pendingFuturesCalls++;
    if (!_usable(expectedGeneration))
      throw const ExchangeReadException(
        code: 'binance_credentials_required',
        message: 'Binance credentials are required.',
      );
    await pendingFuturesGate?.future;
    return pendingFutures;
  }

  @override
  Future<List<ExchangePosition>> getFuturesPositions({
    CancelToken? cancelToken,
    BinanceCredentialSnapshot? expectedGeneration,
    List<ExchangeReadIssue>? issues,
  }) async {
    if (!_usable(expectedGeneration))
      throw const ExchangeReadException(
        code: 'binance_credentials_required',
        message: 'Binance credentials are required.',
      );
    positionCalls++;
    await positionsGate?.future;
    issues?.addAll(positionIssues);
    return positions;
  }
}

class _SpyTradeApi implements TradeApi {
  int prepareCalls = 0;
  int executeCalls = 0;
  bool allowActionCalls = false;
  Map<String, dynamic>? preparedIdentity;

  @override
  bool get isConfigured => true;
  @override
  bool get supportsSessionRestoration => false;

  @override
  Future<PreparedTradeAction> prepare(
    String bearerToken, {
    required String action,
    Map<String, dynamic>? targetIdentity,
    String? amount,
    String? size,
    String? percentage,
  }) async {
    prepareCalls++;
    if (!allowActionCalls) throw StateError('Unexpected action prepare call');
    preparedIdentity = targetIdentity;
    return PreparedTradeAction(
      operationId: 'operation-12345678',
      confirmationToken: 'single-use-token',
      action: action,
      expiresAt: '2099-01-01T00:00:00Z',
      summary: <String, dynamic>{
        'targetCount': 1,
        'targets': <Map<String, dynamic>>[
          <String, dynamic>{'identity': targetIdentity},
        ],
      },
    );
  }

  @override
  Future<TradeOperationResult> execute(
    String bearerToken, {
    required String operationId,
    required String confirmationToken,
  }) async {
    executeCalls++;
    if (!allowActionCalls) throw StateError('Unexpected action execute call');
    return TradeOperationResult(
      operationId: operationId,
      action: 'close_position',
      status: 'SUCCEEDED',
      targets: const <Map<String, dynamic>>[],
      updatedAt: '2099-01-01T00:00:00Z',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AuthenticatedTradeSessionController extends TradeSessionController {
  _AuthenticatedTradeSessionController(TradeApi api) : super(api) {
    state = TradeSessionState(
      session: TradeSession(
        bearerToken: 'in-memory-test-token',
        accountIdentifier: '••••-42',
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
      ),
    );
  }
}

class _InjectedHistoryController extends BinanceAccountHistoryController {
  _InjectedHistoryController({
    required BinanceExchangeReader reader,
    required BinanceHistoryScanService service,
    required BinanceAccountHistoryState initialState,
  }) : super(reader, service) {
    state = initialState;
  }

  int enterCalls = 0;
  int leaveCalls = 0;
  int refreshCalls = 0;
  int resumeCalls = 0;

  @override
  void enterHistory() => enterCalls++;

  @override
  void leaveHistory() => leaveCalls++;

  @override
  void refreshHistory() => refreshCalls++;

  @override
  void resumeHistory() => resumeCalls++;
}

ExchangeAmount _amount(String value) => ExchangeAmount.tryParse(value)!;

ExchangePosition _position({
  required ExchangeSource source,
  required String symbol,
  required String size,
  Object? nativeRecord,
}) => ExchangePosition(
  source: source,
  product: ExchangeProduct.swap,
  symbol: symbol,
  side: ExchangePositionSide.long,
  positionAmount: ExchangeValue<ExchangeAmount>.available(_amount(size)),
  entryPrice: ExchangeValue<ExchangeAmount>.available(_amount('10')),
  markPrice: ExchangeValue<ExchangeAmount>.available(_amount('11')),
  unrealizedPnl: ExchangeValue<ExchangeMoney>.available(
    ExchangeMoney.tryParse('1', 'USDT')!,
  ),
  marginMode: const ExchangeValue<String>.available('isolated'),
  leverage: ExchangeValue<ExchangeAmount>.available(_amount('3')),
  marginCurrency: const ExchangeValue<String>.available('USDT'),
  nativeId: 'position-$source',
  nativeRecord: nativeRecord,
);

OkxPosition _nativePosition() => OkxPosition(
  instId: 'BTC-USDT-SWAP',
  instType: 'SWAP',
  posSide: 'net',
  pos: '2',
  size: '2',
  signedSize: '2',
  direction: 'long',
  mgnMode: 'isolated',
  marginCurrency: 'USDT',
  identity: const <String, dynamic>{
    'instrumentType': 'SWAP',
    'instrumentId': 'BTC-USDT-SWAP',
    'positionId': 'position-1',
    'positionSide': 'net',
    'marginMode': 'isolated',
  },
);

ExchangeOrder _order({
  required ExchangeSource source,
  required String nativeId,
  Object? actionDto,
  String price = '10',
}) => ExchangeOrder(
  source: source,
  product: ExchangeProduct.swap,
  kind: ExchangeOrderKind.ordinary,
  symbol: 'BTC-USDT-SWAP',
  nativeId: nativeId,
  side: 'buy',
  status: 'live',
  quantity: ExchangeValue<ExchangeAmount>.available(_amount('2')),
  executedQuantity: ExchangeValue<ExchangeAmount>.available(_amount('0')),
  quoteAmount: const ExchangeValue<ExchangeMoney>.unavailable('not filled'),
  createdAtMilliseconds: 1,
  price: ExchangeValue<ExchangeMoney>.available(
    ExchangeMoney.tryParse(price, 'USDT')!,
  ),
  okxActionDto: actionDto,
  nativeRecord: actionDto,
);

ProviderContainer _container({
  required _Storage storage,
  required _OkxReader okx,
  required _BinanceReader binance,
}) => ProviderContainer(
  overrides: <Override>[
    secureStorageProvider.overrideWithValue(storage),
    okxExchangeReaderProvider.overrideWithValue(okx),
    binanceExchangeReaderProvider.overrideWithValue(binance),
  ],
);

Future<void> _drain() async {
  for (var index = 0; index < 12; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('GREEN-118 combined exchange orders', () {
    test(
      'pending orders publish OKX while Binance Spot remains pending and preserve colliding IDs',
      () async {
        final storage = _Storage();
        final gate = Completer<void>();
        final native = OkxOrder(
          instId: 'BTC-USDT-SWAP',
          instType: 'SWAP',
          ordId: 'order-99',
          ordType: 'limit',
          side: 'buy',
          px: '10',
          sz: '2',
          state: 'live',
        );
        final okxOrder = _order(
          source: ExchangeSource.okx,
          nativeId: 'order-99',
          actionDto: native,
        );
        final binanceOrder = _order(
          source: ExchangeSource.binance,
          nativeId: 'order-99',
        );
        final okx = _OkxReader(pending: <ExchangeOrder>[okxOrder]);
        final binance = _BinanceReader(
          credentialState: storage.binanceCredentialState,
          pendingSpot: <ExchangeOrder>[binanceOrder],
          pendingSpotGate: gate,
        );
        final container = _container(
          storage: storage,
          okx: okx,
          binance: binance,
        );
        addTearDown(() {
          container.dispose();
          storage.dispose();
          binance.dispose();
        });
        final request = const CombinedOrderReadRequest(
          type: CombinedOrderReadType.pending,
          filter: 'ALL',
        );
        final subscription = container.listen(
          combinedExchangeOrdersProvider(request),
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(subscription.close);
        await _drain();

        final result = container.read(combinedExchangeOrdersProvider(request));
        expect(result.rows, hasLength(1));
        expect(result.rows.single.source, ExchangeSource.okx);
        expect(result.isLoading, isTrue);
        gate.complete();
        await _drain();
        final settled = container.read(combinedExchangeOrdersProvider(request));
        expect(
          settled.rows.map((order) => order.source).toSet(),
          <ExchangeSource>{ExchangeSource.okx, ExchangeSource.binance},
        );
        expect(settled.rows.map((order) => order.nativeId), <String>[
          'order-99',
          'order-99',
        ]);
        expect(
          settled.rows.map((order) => order.identityKey).toSet(),
          hasLength(2),
        );
      },
    );

    test(
      'valid Binance positions remain visible with reader exclusions marked partial',
      () async {
        final storage = _Storage();
        final okxGate = Completer<void>();
        final okx = _OkxReader(positionsGate: okxGate);
        final valid = _position(
          source: ExchangeSource.binance,
          symbol: 'BTCUSDT',
          size: '2',
        );
        final binance = _BinanceReader(
          credentialState: storage.binanceCredentialState,
          positions: <ExchangePosition>[valid],
          positionIssues: const <ExchangeReadIssue>[
            ExchangeReadIssue(
              code: 'binance_invalid_position',
              message: 'A malformed position row was excluded.',
            ),
          ],
        );
        final container = _container(
          storage: storage,
          okx: okx,
          binance: binance,
        );
        addTearDown(() {
          container.dispose();
          storage.dispose();
          binance.dispose();
        });
        final subscription = container.listen(
          combinedExchangePositionsProvider('ALL'),
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(subscription.close);
        await _drain();
        final result = container.read(combinedExchangePositionsProvider('ALL'));
        expect(result.rows, hasLength(1));
        expect(result.rows.single.symbol, 'BTCUSDT');
        expect(result.isPartial, isTrue);
        expect(result.isLoading, isTrue);
        expect(
          result.sources
              .singleWhere((source) => source.source == ExchangeSource.binance)
              .error,
          contains('incomplete metadata'),
        );
        okxGate.complete();
      },
    );
  });

  group('RED-118 Binance order action boundary', () {
    testWidgets('Binance ID collision has no action backend entry call', (
      tester,
    ) async {
      final api = _SpyTradeApi();
      final sessionController = TradeSessionController(api);
      final accountActions = PositionActionFlowsController(
        readApi: () => api,
        readSession: () => const TradeSessionState(),
        readSessionController: () => sessionController,
        invalidatePositions: () {},
      );
      final controller = OrderCancellationFlowsController(
        readApi: () => api,
        readSession: () => const TradeSessionState(),
        readSessionController: () => sessionController,
        readAccountActions: () => accountActions,
        invalidateOrders: () {},
      );
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      final collidingBinanceRow = _order(
        source: ExchangeSource.binance,
        nativeId: 'order-99',
      );
      await controller.cancelExchangeOrder(
        exchangeOrder: collidingBinanceRow,
        navigator: navigator,
        ownerRoute: null,
      );
      expect(api.prepareCalls, 0);
      expect(api.executeCalls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      accountActions.dispose();
      sessionController.dispose();
    });
  });

  group('GREEN-118 OKX actions, refresh, history and rendering', () {
    test(
      'OKX derivatives keep native USD notional without contract-size price fallback',
      () {
        final native = OkxOrder(
          instId: 'BTC-USDT-SWAP',
          instType: 'SWAP',
          ordId: 'derivative-1',
          ordType: 'limit',
          side: 'buy',
          px: '100',
          sz: '2',
          notionalUsd: '20',
        );
        final withNativeNotional = _order(
          source: ExchangeSource.okx,
          nativeId: 'derivative-1',
          actionDto: native,
          price: '100',
        );
        expect(
          resolveExchangeOrderNotional(
            withNativeNotional,
            pending: true,
          )?.usdAmount,
          20,
        );

        final withoutNativeNotional = _order(
          source: ExchangeSource.okx,
          nativeId: 'derivative-2',
          actionDto: native.copyWith(ordId: 'derivative-2', notionalUsd: ''),
          price: '100',
        );
        expect(
          resolveExchangeOrderNotional(withoutNativeNotional, pending: true),
          isNull,
        );
      },
    );

    testWidgets(
      'successful OKX position action refreshes the combined display source',
      (tester) async {
        final api = _SpyTradeApi()..allowActionCalls = true;
        final sessionController = _AuthenticatedTradeSessionController(api);
        final native = _nativePosition();
        var displaySourceReads = 0;
        await tester.pumpWidget(
          ProviderScope(
            overrides: <Override>[
              okxExchangePositionsSourceProvider('ALL').overrideWith((
                ref,
              ) async {
                displaySourceReads++;
                return const ExchangeRowsResult<ExchangePosition>.success(
                  source: ExchangeSource.okx,
                  product: null,
                  rows: <ExchangePosition>[],
                );
              }),
              tradeApiProvider.overrideWithValue(api),
              tradeSessionProvider.overrideWith((ref) => sessionController),
              orderFilterProvider.overrideWith((ref) => 'ALL'),
            ],
            child: const MaterialApp(home: Scaffold(body: SizedBox())),
          ),
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(Scaffold)),
        );
        final subscription = container.listen(
          okxExchangePositionsSourceProvider('ALL'),
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(subscription.close);
        await tester.pump();
        await tester.pump();
        expect(displaySourceReads, 1);

        final controller = container.read(positionActionFlowsProvider.notifier);
        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        await controller.runAction(
          position: native,
          action: 'close_position',
          inputKind: null,
          navigator: navigator,
          ownerRoute: null,
          confirm: (_) async => true,
          showResult: (_, {lookupError}) async {},
        );
        await tester.pump();
        await tester.pump();

        expect(api.prepareCalls, 1);
        expect(api.executeCalls, 1);
        expect(displaySourceReads, 2);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'healthy pending source refreshes while terminal Binance is skipped and renders at mobile and desktop widths',
      (tester) async {
        final storage = _Storage();
        final api = _SpyTradeApi();
        final native = OkxOrder(
          instId: 'BTC-USDT-SWAP',
          instType: 'SWAP',
          ordId: 'order-healthy',
          ordType: 'limit',
          side: 'buy',
          px: '10',
          sz: '2',
          state: 'live',
        );
        final okxOrder = _order(
          source: ExchangeSource.okx,
          nativeId: 'order-healthy',
          actionDto: native,
        );
        final okx = _OkxReader(pending: <ExchangeOrder>[okxOrder]);
        final binance = _BinanceReader(
          credentialState: storage.binanceCredentialState,
          denyPrivateReads: true,
        );
        final captureKey = const Key('t118-orders-capture');
        addTearDown(() {
          storage.dispose();
          binance.dispose();
        });

        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          ProviderScope(
            overrides: <Override>[
              secureStorageProvider.overrideWithValue(storage),
              okxExchangeReaderProvider.overrideWithValue(okx),
              binanceExchangeReaderProvider.overrideWithValue(binance),
              orderTabProvider.overrideWith((ref) => OrderTab.pending),
              orderFilterProvider.overrideWith((ref) => 'ALL'),
              tradeApiProvider.overrideWithValue(api),
              tradeSessionProvider.overrideWith(
                (ref) => TradeSessionController(api),
              ),
              themeModeProvider.overrideWith((ref) => ThemeMode.light),
              currencyProvider.overrideWith((ref) => 'USD'),
              vndExchangeRateProvider.overrideWith((ref) async => 25400),
            ],
            child: MaterialApp(
              home: RepaintBoundary(
                key: captureKey,
                child: const OrdersScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(OrdersScreen)),
        );
        const request = CombinedOrderReadRequest(
          type: CombinedOrderReadType.pending,
          filter: 'ALL',
        );
        final combined = container.read(
          combinedExchangeOrdersProvider(request),
        );
        expect(
          combined.rows,
          hasLength(1),
          reason:
              'sources=${combined.sources.map((source) => '${source.source}:${source.error}:${source.isLoading}').join(', ')}; okxCalls=${okx.pendingCalls}',
        );
        expect(find.byTooltip('OKX Unified'), findsOneWidget);
        expect(okx.pendingCalls, 1);
        expect(binance.pendingSpotCalls, 1);
        expect(binance.pendingFuturesCalls, 1);
        expect(
          combined.sources
              .singleWhere((source) => source.product == ExchangeProduct.spot)
              .isTerminalFailure,
          isTrue,
          reason: combined.sources
              .map(
                (source) =>
                    '${source.source}/${source.product}:${source.error}:terminal=${source.isTerminalFailure}:loading=${source.isLoading}',
              )
              .join(' | '),
        );
        final spotDeniedCalls = binance.pendingSpotCalls;
        final futuresDeniedCalls = binance.pendingFuturesCalls;
        final mobileBoundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(captureKey),
        );
        final mobileImage = await mobileBoundary.toImage(pixelRatio: 1);
        final mobileBytes = await tester.runAsync(
          () => mobileImage.toByteData(format: ui.ImageByteFormat.png),
        );
        if (mobileBytes != null) {
          await tester.runAsync(
            () => File(
              '/private/tmp/t118_orders_mobile.png',
            ).writeAsBytes(mobileBytes.buffer.asUint8List()),
          );
        }
        mobileImage.dispose();

        await tester.pump(const Duration(seconds: 16));
        await tester.pumpAndSettle();
        expect(okx.pendingCalls, greaterThan(1));
        expect(binance.pendingSpotCalls, spotDeniedCalls);
        expect(binance.pendingFuturesCalls, futuresDeniedCalls);
        expect(find.byTooltip('OKX Unified'), findsOneWidget);

        tester.view.physicalSize = const Size(1440, 900);
        await tester.pump();
        final desktopBoundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(captureKey),
        );
        final desktopImage = await desktopBoundary.toImage(pixelRatio: 1);
        final desktopBytes = await tester.runAsync(
          () => desktopImage.toByteData(format: ui.ImageByteFormat.png),
        );
        if (desktopBytes != null) {
          await tester.runAsync(
            () => File(
              '/private/tmp/t118_orders_desktop.png',
            ).writeAsBytes(desktopBytes.buffer.asUint8List()),
          );
        }
        desktopImage.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'history shows 429 recovery counts and coverage, starts only on entry and refreshes manually',
      (tester) async {
        final storage = _Storage();
        final api = _SpyTradeApi();
        final okx = _OkxReader();
        final binance = _BinanceReader(
          credentialState: storage.binanceCredentialState,
        );
        final service = BinanceHistoryScanService(
          reader: binance,
          requestCoordinator: BinanceRequestCoordinator(
            minimumSpacing: Duration.zero,
            delay: (_) async {},
          ),
        );
        final retryAt = DateTime.now().toUtc().add(const Duration(hours: 1));
        const selectedTimeZone = 'Asia/Tokyo';
        final expectedRetryLabel = AppTimeZone.formatEpochMilliseconds(
          selectedTimeZone,
          retryAt.millisecondsSinceEpoch,
          pattern: 'HH:mm:ss',
        );
        final historyController = _InjectedHistoryController(
          reader: binance,
          service: service,
          initialState: BinanceAccountHistoryState(
            generation: 0,
            spot: BinanceHistoryScanProgress(
              product: ExchangeProduct.spot,
              state: BinanceHistoryScanState.paused,
              initialized: true,
              totalSymbols: 3,
              completedSymbols: 1,
              failedSymbols: 1,
              pendingSymbols: 1,
              rows: const <ExchangeOrder>[],
              failures: const <String, ExchangeReadException>{
                'ETHUSDT': ExchangeReadException(
                  code: 'binance_history_symbol_failed',
                  message: 'A previous symbol read failed.',
                ),
              },
              catalogIssues: const <ExchangeReadIssue>[],
              retryAt: retryAt,
              message: 'Binance host cooldown after HTTP 429.',
              coverageNotice:
                  'Recent first pages are captured up to 500 rows; delisted symbols may be unavailable.',
            ),
            futures: BinanceHistoryScanProgress(
              product: ExchangeProduct.swap,
              state: BinanceHistoryScanState.complete,
              initialized: true,
              totalSymbols: 1,
              completedSymbols: 1,
              failedSymbols: 0,
              pendingSymbols: 0,
              rows: const <ExchangeOrder>[],
              failures: const <String, ExchangeReadException>{},
              catalogIssues: const <ExchangeReadIssue>[],
              retryAt: null,
              message: 'All captured recent-history pages were read.',
              coverageNotice: 'Recent first pages are captured up to 500 rows.',
            ),
          ),
        );
        addTearDown(() {
          historyController.dispose();
          service.dispose();
          storage.dispose();
          binance.dispose();
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: <Override>[
              secureStorageProvider.overrideWithValue(storage),
              okxExchangeReaderProvider.overrideWithValue(okx),
              binanceExchangeReaderProvider.overrideWithValue(binance),
              binanceAccountHistoryProvider.overrideWith(
                (ref) => historyController,
              ),
              orderTabProvider.overrideWith((ref) => OrderTab.history),
              orderFilterProvider.overrideWith((ref) => 'ALL'),
              appTimeZoneProvider.overrideWith((ref) => selectedTimeZone),
              tradeApiProvider.overrideWithValue(api),
              tradeSessionProvider.overrideWith(
                (ref) => TradeSessionController(api),
              ),
              themeModeProvider.overrideWith((ref) => ThemeMode.light),
              currencyProvider.overrideWith((ref) => 'USD'),
              vndExchangeRateProvider.overrideWith((ref) async => 25400),
            ],
            child: const MaterialApp(home: OrdersScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(historyController.enterCalls, 1);
        expect(historyController.refreshCalls, 0);
        expect(find.textContaining('1/3 complete'), findsOneWidget);
        expect(find.textContaining('1 pending'), findsOneWidget);
        expect(find.textContaining('1 failed'), findsOneWidget);
        expect(
          find.textContaining('retry at $expectedRetryLabel'),
          findsOneWidget,
        );
        expect(find.textContaining('HTTP 429'), findsNWidgets(2));
        expect(find.textContaining('up to 500 rows'), findsNWidgets(2));
        expect(
          find.byKey(const Key('binance-history-scan-control')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('binance-history-scan-control')));
        await tester.pump();
        expect(historyController.resumeCalls, 1);
        expect(historyController.refreshCalls, 0);

        await tester.tap(find.byKey(const Key('orders-manual-refresh')));
        await tester.pumpAndSettle();
        expect(historyController.refreshCalls, 1);
        expect(historyController.enterCalls, 1);

        final container = ProviderScope.containerOf(
          tester.element(find.byType(OrdersScreen)),
        );
        container.read(orderTabProvider.notifier).state = OrderTab.pending;
        await tester.pumpAndSettle();
        expect(historyController.leaveCalls, 1);
        expect(historyController.enterCalls, 1);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'periodic refresh advances healthy OKX while Binance Spot stays held',
      (tester) async {
        final storage = _Storage();
        final api = _SpyTradeApi();
        final binanceGate = Completer<void>();
        final native = OkxOrder(
          instId: 'BTC-USDT-SWAP',
          instType: 'SWAP',
          ordId: 'held-refresh-order',
          ordType: 'limit',
          side: 'buy',
          px: '10',
          sz: '2',
          state: 'live',
        );
        final okx = _OkxReader(
          pending: <ExchangeOrder>[
            _order(
              source: ExchangeSource.okx,
              nativeId: 'held-refresh-order',
              actionDto: native,
            ),
          ],
        );
        final binance = _BinanceReader(
          credentialState: storage.binanceCredentialState,
          pendingSpotGate: binanceGate,
        );
        addTearDown(() {
          storage.dispose();
          binance.dispose();
        });

        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          ProviderScope(
            overrides: <Override>[
              secureStorageProvider.overrideWithValue(storage),
              okxExchangeReaderProvider.overrideWithValue(okx),
              binanceExchangeReaderProvider.overrideWithValue(binance),
              orderTabProvider.overrideWith((ref) => OrderTab.pending),
              orderFilterProvider.overrideWith((ref) => 'ALL'),
              tradeApiProvider.overrideWithValue(api),
              tradeSessionProvider.overrideWith(
                (ref) => TradeSessionController(api),
              ),
              themeModeProvider.overrideWith((ref) => ThemeMode.light),
              currencyProvider.overrideWith((ref) => 'USD'),
              vndExchangeRateProvider.overrideWith((ref) async => 25400),
            ],
            child: const MaterialApp(home: OrdersScreen()),
          ),
        );
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(OrdersScreen)),
        );
        const request = CombinedOrderReadRequest(
          type: CombinedOrderReadType.pending,
          filter: 'ALL',
        );
        var combined = container.read(combinedExchangeOrdersProvider(request));
        expect(okx.pendingCalls, 1);
        expect(binance.pendingSpotCalls, 1);
        expect(combined.rows, hasLength(1));
        expect(combined.isLoading, isTrue);

        await tester.pump(const Duration(seconds: 16));
        await tester.pumpAndSettle();

        combined = container.read(combinedExchangeOrdersProvider(request));
        final heldSpot = combined.sources.singleWhere(
          (source) =>
              source.source == ExchangeSource.binance &&
              source.product == ExchangeProduct.spot,
        );
        expect(okx.pendingCalls, greaterThan(1));
        expect(binance.pendingSpotCalls, 1);
        expect(heldSpot.isLoading, isTrue);
        expect(combined.rows, hasLength(1));
        expect(combined.isPartial, isTrue);
        expect(
          find.byKey(const Key('combined-orders-partial-warning')),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        binanceGate.complete();
      },
    );
  });
}
