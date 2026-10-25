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
import 'package:trading_balance_f/core/currency/currency_display_mode.dart';
import 'package:trading_balance_f/core/exchange/binance_exchange_reader.dart';
import 'package:trading_balance_f/core/exchange/exchange_account_providers.dart';
import 'package:trading_balance_f/core/exchange/exchange_models.dart';
import 'package:trading_balance_f/core/exchange/exchange_quote_service.dart';
import 'package:trading_balance_f/core/exchange/exchange_readers.dart';
import 'package:trading_balance_f/core/exchange/okx_exchange_reader.dart';
import 'package:trading_balance_f/core/network/binance_data_client.dart';
import 'package:trading_balance_f/core/network/binance_request_coordinator.dart';
import 'package:trading_balance_f/core/network/okx_data_client.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/features/orders/data/order_repository.dart';
import 'package:trading_balance_f/features/orders/data/trade_api_client.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/trade_session_provider.dart';
import 'package:trading_balance_f/features/portfolio/data/portfolio_repository.dart';
import 'package:trading_balance_f/features/portfolio/presentation/portfolio_screen.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';

class _Storage extends SecureStorageHelper {
  _Storage() : super(const FlutterSecureStorage());

  String? binanceBundle;

  @override
  Future<String?> getOkxApiKey() async => 'fixture-okx-key';

  @override
  Future<String?> getOkxSecretKey() async => 'fixture-okx-secret';

  @override
  Future<String?> getOkxPassphrase() async => 'fixture-okx-passphrase';

  @override
  Future<String?> getBinanceCredentialBundle() async => binanceBundle;
}

class _OkxReader extends OkxExchangeReader {
  _OkxReader({
    required this.account,
    this.positions = const <ExchangePosition>[],
    this.pendingOrders = const <ExchangeOrder>[],
    this.historyOrders = const <ExchangeOrder>[],
    this.accountGate,
    this.positionsGate,
    this.ordersGate,
  }) : super(
         portfolioRepository: PortfolioRepository(OkxDataClient()),
         orderRepository: OrderRepository(OkxDataClient()),
       );

  final ExchangeAccountSnapshot account;
  final List<ExchangePosition> positions;
  final List<ExchangeOrder> pendingOrders;
  final List<ExchangeOrder> historyOrders;
  Completer<void>? accountGate;
  int accountCalls = 0;
  final Completer<void>? positionsGate;
  final Completer<void>? ordersGate;

  @override
  Future<ExchangeAccountSnapshot> getAccountBalance({
    CancelToken? cancelToken,
  }) async {
    accountCalls++;
    await accountGate?.future;
    return account;
  }

  @override
  Future<List<ExchangePosition>> getOpenPositions({
    String instType = 'ALL',
    CancelToken? cancelToken,
  }) async {
    await positionsGate?.future;
    return positions;
  }

  @override
  Future<List<ExchangeOrder>> getPendingOrders({
    String instType = 'ALL',
    CancelToken? cancelToken,
  }) async {
    await ordersGate?.future;
    return pendingOrders;
  }

  @override
  Future<List<ExchangeOrder>> getOrdersHistory({
    String instType = 'ALL',
    CancelToken? cancelToken,
  }) async {
    await ordersGate?.future;
    return historyOrders;
  }
}

class _BinanceReader extends BinanceExchangeReader {
  _BinanceReader({
    required ValueListenable<BinanceCredentialSnapshot> credentialState,
    required this.spot,
    required this.futures,
    this.positions = const <ExchangePosition>[],
    this.spotOrders = const <ExchangeOrder>[],
    this.futuresOrders = const <ExchangeOrder>[],
    this.positionIssues = const <ExchangeReadIssue>[],
    this.spotCatalogInstruments = const <ExchangeInstrument>[],
    this.spotFailure,
    this.spotGate,
    this.futuresGate,
    this.positionGate,
    this.pendingSpotGate,
    this.pendingFuturesGate,
  }) : super(
         client: BinanceDataClient(dio: Dio()),
         credentialState: credentialState,
         requestCoordinator: BinanceRequestCoordinator(
           minimumSpacing: Duration.zero,
           delay: (_) async {},
         ),
       );

  final ExchangeAccountSnapshot spot;
  final ExchangeAccountSnapshot futures;
  final List<ExchangePosition> positions;
  final List<ExchangeOrder> spotOrders;
  final List<ExchangeOrder> futuresOrders;
  final List<ExchangeReadIssue> positionIssues;
  final List<ExchangeInstrument> spotCatalogInstruments;
  final ExchangeReadException? spotFailure;
  final Completer<void>? spotGate;
  final Completer<void>? futuresGate;
  final Completer<void>? positionGate;
  final Completer<void>? pendingSpotGate;
  final Completer<void>? pendingFuturesGate;

  bool _usable(BinanceCredentialSnapshot? expected) =>
      expected == null || expected.canUsePrivateReads;

  @override
  Future<ExchangeCatalog> getSpotCatalog({
    CancelToken? cancelToken,
    BinanceCredentialSnapshot? expectedGeneration,
    Iterable<String> knownSymbols = const <String>[],
  }) async {
    if (!_usable(expectedGeneration))
      throw const ExchangeReadException(
        code: 'binance_credentials_required',
        message: 'Binance credentials are required.',
      );
    return ExchangeCatalog(
      source: ExchangeSource.binance,
      product: ExchangeProduct.spot,
      generation: expectedGeneration?.generation ?? generation,
      instruments: spotCatalogInstruments,
    );
  }

  @override
  Future<ExchangeAccountSnapshot> getSpotAccount({
    CancelToken? cancelToken,
    BinanceCredentialSnapshot? expectedGeneration,
  }) async {
    if (!_usable(expectedGeneration))
      throw const ExchangeReadException(
        code: 'binance_credentials_required',
        message: 'Binance credentials are required.',
      );
    await spotGate?.future;
    final failure = spotFailure;
    if (failure != null) throw failure;
    return _withGeneration(spot, expectedGeneration?.generation ?? generation);
  }

  @override
  Future<ExchangeAccountSnapshot> getFuturesAccount({
    CancelToken? cancelToken,
    BinanceCredentialSnapshot? expectedGeneration,
  }) async {
    if (!_usable(expectedGeneration))
      throw const ExchangeReadException(
        code: 'binance_credentials_required',
        message: 'Binance credentials are required.',
      );
    await futuresGate?.future;
    return _withGeneration(
      futures,
      expectedGeneration?.generation ?? generation,
    );
  }

  ExchangeAccountSnapshot _withGeneration(
    ExchangeAccountSnapshot account,
    int generation,
  ) => ExchangeAccountSnapshot(
    source: account.source,
    product: account.product,
    generation: generation,
    accountMode: account.accountMode,
    balances: account.balances,
    reportedEquity: account.reportedEquity,
    unrealizedPnl: account.unrealizedPnl,
    equityIncludesUnrealizedPnl: account.equityIncludesUnrealizedPnl,
    positions: account.positions,
    issues: account.issues,
    nativeRecord: account.nativeRecord,
  );

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
    await positionGate?.future;
    issues?.addAll(positionIssues);
    return positions;
  }

  @override
  Future<List<ExchangeOrder>> getSpotOpenOrders({
    CancelToken? cancelToken,
    BinanceCredentialSnapshot? expectedGeneration,
  }) async {
    await pendingSpotGate?.future;
    return spotOrders;
  }

  @override
  Future<List<ExchangeOrder>> getFuturesOpenOrders({
    CancelToken? cancelToken,
    BinanceCredentialSnapshot? expectedGeneration,
  }) async {
    await pendingFuturesGate?.future;
    return futuresOrders;
  }
}

class _QuoteFixture extends ExchangeQuoteService {
  _QuoteFixture()
    : super(
        binanceClient: BinanceDataClient(dio: Dio()),
        okxClient: OkxDataClient(),
      );

  int calls = 0;
  bool returnExpiredOnNextRead = false;
  bool failNextRead = false;
  Completer<void>? nextReadGate;

  @override
  Future<ExchangeQuoteSnapshot> loadQuotes({
    required ExchangeQuoteOwner owner,
    required Iterable<ExchangeInstrument> instruments,
  }) async {
    calls++;
    final gate = nextReadGate;
    nextReadGate = null;
    await gate?.future;
    if (failNextRead) {
      failNextRead = false;
      throw StateError('fixture quote read failed');
    }
    final observedAt = DateTime.now().toUtc().subtract(
      returnExpiredOnNextRead ? const Duration(seconds: 16) : Duration.zero,
    );
    return ExchangeQuoteSnapshot(
      observedAt: observedAt,
      values: <ExchangeQuoteKey, ExchangeValue<ExchangeQuote>>{
        for (final instrument in instruments)
          ExchangeQuoteKey(
            source: instrument.source,
            product: instrument.product,
            instrument: instrument.symbol,
          ): ExchangeValue<ExchangeQuote>.available(
            ExchangeQuote(
              key: ExchangeQuoteKey(
                source: instrument.source,
                product: instrument.product,
                instrument: instrument.symbol,
              ),
              price: ExchangeAmount.tryParse('${calls * 100}')!,
              quoteCurrency: 'USDT',
              observedAt: observedAt,
            ),
          ),
      },
    );
  }
}

ExchangeValue<ExchangeAmount> _amount(String value) =>
    ExchangeValue<ExchangeAmount>.available(ExchangeAmount.tryParse(value)!);

ExchangeValue<ExchangeMoney> _money(String value, String currency) =>
    ExchangeValue<ExchangeMoney>.available(
      ExchangeMoney.tryParse(value, currency)!,
    );

ExchangeAccountSnapshot _account({
  required ExchangeSource source,
  required ExchangeProduct? product,
  required String asset,
  required String free,
  required String? locked,
  required String? reportedTotal,
  required String? equity,
  Iterable<ExchangeReadIssue> issues = const <ExchangeReadIssue>[],
}) => ExchangeAccountSnapshot(
  source: source,
  product: product,
  generation: 0,
  balances: <ExchangeBalance>[
    ExchangeBalance(
      source: source,
      product: product,
      wallet: product == null
          ? 'unified'
          : product == ExchangeProduct.futures
          ? 'futures'
          : 'spot',
      asset: asset,
      free: _amount(free),
      locked: locked == null
          ? const ExchangeValue<ExchangeAmount>.unavailable('not reported')
          : _amount(locked),
      reportedTotal: reportedTotal == null ? null : _amount(reportedTotal),
    ),
  ],
  reportedEquity: equity == null
      ? const ExchangeValue<ExchangeMoney>.unavailable('not reported')
      : _money(equity, 'USDT'),
  unrealizedPnl: const ExchangeValue<ExchangeMoney>.unavailable('not reported'),
  equityIncludesUnrealizedPnl: product == ExchangeProduct.futures,
  issues: issues,
);

_Storage _storage() {
  final storage = _Storage();
  storage.binanceBundle =
      '{"version":1,"apiKey":"fixture","secretKey":"fixture-secret"}';
  return storage;
}

List<Override> _accountOverrides({
  required _Storage storage,
  required _OkxReader okx,
  required _BinanceReader binance,
  required ExchangeQuoteService quotes,
}) => <Override>[
  secureStorageProvider.overrideWithValue(storage),
  okxExchangeReaderProvider.overrideWithValue(okx),
  binanceExchangeReaderProvider.overrideWithValue(binance),
  exchangeQuoteServiceProvider.overrideWithValue(quotes),
];

ProviderContainer _container({
  required _Storage storage,
  required _OkxReader okx,
  required _BinanceReader binance,
  required ExchangeQuoteService quotes,
}) => ProviderContainer(
  overrides: _accountOverrides(
    storage: storage,
    okx: okx,
    binance: binance,
    quotes: quotes,
  ),
);

Future<void> _drainAsync() async {
  for (var index = 0; index < 10; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('GREEN-118 combined exchange portfolio', () {
    test(
      'keeps same-coin source rows separate and includes Futures margin equity once',
      () async {
        final storage = _storage();
        final quotes = _QuoteFixture();
        final okx = _OkxReader(
          account: _account(
            source: ExchangeSource.okx,
            product: null,
            asset: 'USDT',
            free: '100',
            locked: '0',
            reportedTotal: '100',
            equity: '100',
          ),
        );
        final binance = _BinanceReader(
          credentialState: storage.binanceCredentialState,
          spot: _account(
            source: ExchangeSource.binance,
            product: ExchangeProduct.spot,
            asset: 'USDT',
            free: '18',
            locked: '2',
            reportedTotal: '20',
            equity: null,
          ),
          futures: _account(
            source: ExchangeSource.binance,
            product: ExchangeProduct.futures,
            asset: 'USDT',
            free: '80',
            locked: null,
            reportedTotal: '95',
            equity: '75',
          ),
        );
        final container = _container(
          storage: storage,
          okx: okx,
          binance: binance,
          quotes: quotes,
        );
        addTearDown(() {
          container.dispose();
          storage.dispose();
          binance.dispose();
          quotes.dispose();
        });
        final subscription = container.listen(
          combinedExchangePortfolioProvider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(subscription.close);
        await _drainAsync();

        final portfolio = container.read(combinedExchangePortfolioProvider);
        final usdtRows = portfolio.rows
            .where((row) => row.balance.asset == 'USDT')
            .toList();
        final futures = usdtRows.singleWhere(
          (row) => row.balance.product == ExchangeProduct.futures,
        );
        expect(
          usdtRows.map((row) => row.balance.source).toSet(),
          containsAll(<ExchangeSource>{
            ExchangeSource.okx,
            ExchangeSource.binance,
          }),
        );
        expect(usdtRows, hasLength(3));
        expect(futures.totalAmount.value?.text, '95');
        expect(portfolio.totalEquity.value?.text, '195');
        expect(portfolio.isPartial, isFalse);
      },
    );

    testWidgets(
      'retains the last account snapshot with a stale warning while refresh is held',
      (tester) async {
        final storage = _storage();
        final quotes = _QuoteFixture();
        final okx = _OkxReader(
          account: _account(
            source: ExchangeSource.okx,
            product: null,
            asset: 'USDT',
            free: '42',
            locked: '0',
            reportedTotal: '42',
            equity: '42',
          ),
        );
        final binance = _BinanceReader(
          credentialState: storage.binanceCredentialState,
          spot: _account(
            source: ExchangeSource.binance,
            product: ExchangeProduct.spot,
            asset: 'USDT',
            free: '0',
            locked: '0',
            reportedTotal: '0',
            equity: null,
          ),
          futures: _account(
            source: ExchangeSource.binance,
            product: ExchangeProduct.futures,
            asset: 'USDT',
            free: '0',
            locked: null,
            reportedTotal: '0',
            equity: '0',
          ),
        );
        addTearDown(() {
          storage.dispose();
          binance.dispose();
          quotes.dispose();
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: <Override>[
              ..._accountOverrides(
                storage: storage,
                okx: okx,
                binance: binance,
                quotes: quotes,
              ),
              currencyProvider.overrideWith((ref) => CurrencyDisplayMode.usd),
              vndExchangeRateProvider.overrideWith((ref) async => 25400),
              themeModeProvider.overrideWith((ref) => ThemeMode.light),
            ],
            child: const MaterialApp(home: PortfolioScreen()),
          ),
        );
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(PortfolioScreen)),
        );
        final first = container.read(combinedExchangePortfolioProvider);
        expect(
          first.rows.any((row) => row.balance.source == ExchangeSource.okx),
          isTrue,
        );
        expect(first.totalEquity.value?.text, '42');
        expect(first.isPartial, isFalse);

        final refreshGate = Completer<void>();
        okx.accountGate = refreshGate;
        container.invalidate(okxPortfolioSourceProvider);
        for (var index = 0; index < 12; index++) {
          await tester.pump(const Duration(milliseconds: 20));
        }

        final refreshing = container.read(combinedExchangePortfolioProvider);
        expect(refreshing.isLoading, isTrue);
        expect(refreshing.isPartial, isTrue);
        expect(refreshing.totalEquity.value?.text, '42');
        expect(
          refreshing.rows.any(
            (row) =>
                row.balance.source == ExchangeSource.okx &&
                row.balance.asset == 'USDT',
          ),
          isTrue,
        );
        expect(
          refreshing.warnings.any(
            (warning) =>
                warning.contains('account is refreshing') &&
                warning.contains('may be stale'),
          ),
          isTrue,
        );
        expect(
          find.byKey(const Key('portfolio-partial-warning')),
          findsOneWidget,
        );
        expect(find.textContaining('account is refreshing'), findsOneWidget);
        expect(okx.accountCalls, 2);

        await tester.pumpWidget(const SizedBox.shrink());
        refreshGate.complete();
      },
    );
  });

  group('RED-118 Binance source read failure', () {
    test(
      'failed Binance Spot account read keeps other sources and marks the result partial',
      () async {
        final storage = _storage();
        final quotes = _QuoteFixture();
        final okx = _OkxReader(
          account: _account(
            source: ExchangeSource.okx,
            product: null,
            asset: 'USDT',
            free: '100',
            locked: '0',
            reportedTotal: '100',
            equity: '100',
          ),
        );
        final binance = _BinanceReader(
          credentialState: storage.binanceCredentialState,
          spot: _account(
            source: ExchangeSource.binance,
            product: ExchangeProduct.spot,
            asset: 'USDT',
            free: '20',
            locked: '0',
            reportedTotal: '20',
            equity: null,
          ),
          futures: _account(
            source: ExchangeSource.binance,
            product: ExchangeProduct.futures,
            asset: 'USDT',
            free: '75',
            locked: null,
            reportedTotal: '75',
            equity: '75',
          ),
          spotFailure: const ExchangeReadException(
            code: 'binance_read_failed',
            message: 'Binance Spot account read failed.',
          ),
        );
        final container = _container(
          storage: storage,
          okx: okx,
          binance: binance,
          quotes: quotes,
        );
        addTearDown(() {
          container.dispose();
          storage.dispose();
          binance.dispose();
          quotes.dispose();
        });
        final subscription = container.listen(
          combinedExchangePortfolioProvider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(subscription.close);
        await _drainAsync();

        final portfolio = container.read(combinedExchangePortfolioProvider);
        expect(portfolio.isPartial, isTrue);
        expect(
          portfolio.rows.map((row) => row.balance.source).toSet(),
          <ExchangeSource>{ExchangeSource.okx, ExchangeSource.binance},
        );
        expect(
          portfolio.rows.any(
            (row) => row.balance.product == ExchangeProduct.futures,
          ),
          isTrue,
        );
        expect(
          portfolio.sources
              .singleWhere((source) => source.product == ExchangeProduct.spot)
              .isTerminalFailure,
          isFalse,
        );
        expect(
          portfolio.sources
              .singleWhere((source) => source.product == ExchangeProduct.spot)
              .error,
          contains('Binance Spot account read failed'),
        );
        expect(
          portfolio.rows.any(
            (row) => row.balance.product == ExchangeProduct.spot,
          ),
          isFalse,
        );
      },
    );
  });

  group('GREEN-118 independent exchange loading and rotation', () {
    testWidgets('renders OKX while a Binance account read is held', (
      tester,
    ) async {
      final storage = _storage();
      final gate = Completer<void>();
      final quotes = _QuoteFixture();
      final okx = _OkxReader(
        account: _account(
          source: ExchangeSource.okx,
          product: null,
          asset: 'USDT',
          free: '42',
          locked: '0',
          reportedTotal: '42',
          equity: '42',
        ),
      );
      final binance = _BinanceReader(
        credentialState: storage.binanceCredentialState,
        spot: _account(
          source: ExchangeSource.binance,
          product: ExchangeProduct.spot,
          asset: 'USDT',
          free: '0',
          locked: '0',
          reportedTotal: '0',
          equity: null,
        ),
        futures: _account(
          source: ExchangeSource.binance,
          product: ExchangeProduct.futures,
          asset: 'USDT',
          free: '0',
          locked: null,
          reportedTotal: '0',
          equity: '0',
        ),
        futuresGate: gate,
      );
      final api = TradeApiClient(baseUrl: 'https://trade.example');
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            ..._accountOverrides(
              storage: storage,
              okx: okx,
              binance: binance,
              quotes: quotes,
            ),
            currencyProvider.overrideWith((ref) => CurrencyDisplayMode.usd),
            vndExchangeRateProvider.overrideWith((ref) async => 25400),
            themeModeProvider.overrideWith((ref) => ThemeMode.light),
            tradeApiProvider.overrideWithValue(api),
            tradeSessionProvider.overrideWith(
              (ref) => TradeSessionController(api),
            ),
          ],
          child: const MaterialApp(home: PortfolioScreen()),
        ),
      );
      for (var index = 0; index < 12; index++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.text('OKX · spot'), findsNothing);
      expect(find.text('OKX · unified'), findsOneWidget);
      expect(find.textContaining('42 USDT'), findsOneWidget);
      expect(
        find.byKey(const Key('portfolio-partial-warning')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      gate.complete();
      storage.dispose();
      binance.dispose();
      quotes.dispose();
    });

    test(
      'credential rotation clears only old Binance rows and preserves OKX',
      () async {
        final storage = _storage();
        final quotes = _QuoteFixture();
        final okx = _OkxReader(
          account: _account(
            source: ExchangeSource.okx,
            product: null,
            asset: 'USDT',
            free: '10',
            locked: '0',
            reportedTotal: '10',
            equity: '10',
          ),
        );
        final binance = _BinanceReader(
          credentialState: storage.binanceCredentialState,
          spot: _account(
            source: ExchangeSource.binance,
            product: ExchangeProduct.spot,
            asset: 'USDT',
            free: '5',
            locked: '0',
            reportedTotal: '5',
            equity: null,
          ),
          futures: _account(
            source: ExchangeSource.binance,
            product: ExchangeProduct.futures,
            asset: 'USDT',
            free: '0',
            locked: null,
            reportedTotal: '0',
            equity: '0',
          ),
        );
        final container = _container(
          storage: storage,
          okx: okx,
          binance: binance,
          quotes: quotes,
        );
        addTearDown(() {
          container.dispose();
          storage.dispose();
          binance.dispose();
          quotes.dispose();
        });
        final subscription = container.listen(
          combinedExchangePortfolioProvider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(subscription.close);
        await _drainAsync();
        expect(
          container
              .read(combinedExchangePortfolioProvider)
              .rows
              .any((row) => row.balance.source == ExchangeSource.binance),
          isTrue,
        );

        final release = Completer<void>();
        final mutation = storage.trackBinanceCredentialMutation(
          () => release.future,
        );
        await _drainAsync();
        final rotating = container.read(combinedExchangePortfolioProvider);
        expect(
          rotating.rows.every(
            (row) => row.balance.source == ExchangeSource.okx,
          ),
          isTrue,
        );
        expect(rotating.rows, isNotEmpty);
        release.complete();
        await mutation;
      },
    );
  });

  group('RED-118 missing and stale quote handling', () {
    test(
      'quote expiry and refresh proceed independently from cached account reads',
      () async {
        final storage = _storage();
        final quotes = _QuoteFixture();
        final okx = _OkxReader(
          account: _account(
            source: ExchangeSource.okx,
            product: null,
            asset: 'BTC',
            free: '1',
            locked: '0',
            reportedTotal: '1',
            equity: '100',
          ),
        );
        final binance = _BinanceReader(
          credentialState: storage.binanceCredentialState,
          spot: _account(
            source: ExchangeSource.binance,
            product: ExchangeProduct.spot,
            asset: 'USDT',
            free: '0',
            locked: '0',
            reportedTotal: '0',
            equity: null,
          ),
          futures: _account(
            source: ExchangeSource.binance,
            product: ExchangeProduct.futures,
            asset: 'USDT',
            free: '0',
            locked: null,
            reportedTotal: '0',
            equity: '0',
          ),
        );
        final container = _container(
          storage: storage,
          okx: okx,
          binance: binance,
          quotes: quotes,
        );
        addTearDown(() {
          container.dispose();
          storage.dispose();
          binance.dispose();
          quotes.dispose();
        });
        final subscription = container.listen(
          combinedExchangePortfolioProvider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(subscription.close);
        await _drainAsync();
        expect(quotes.calls, 1);
        final initialBtcRows = container
            .read(combinedExchangePortfolioProvider)
            .rows
            .where((row) => row.balance.source == ExchangeSource.okx)
            .toList();
        expect(initialBtcRows, hasLength(1));
        expect(initialBtcRows.single.valuation.value?.amount.text, '100');

        final accountGate = Completer<void>();
        okx.accountGate = accountGate;
        container.invalidate(okxPortfolioSourceProvider);
        quotes.returnExpiredOnNextRead = true;
        container.invalidate(okxPortfolioValuationProvider);
        await _drainAsync();
        final expired = container
            .read(combinedExchangePortfolioProvider)
            .rows
            .singleWhere((row) => row.balance.source == ExchangeSource.okx);
        expect(quotes.calls, 2);
        expect(expired.quote, isNull);
        expect(expired.valuation.value, isNull);
        expect(okx.accountCalls, 2);
        expect(accountGate.isCompleted, isFalse);
        expect(container.read(okxPortfolioSourceProvider).isLoading, isTrue);
        accountGate.complete();
      },
    );

    test(
      'missing same-exchange quote remains unavailable instead of becoming zero',
      () async {
        final storage = _storage();
        final quotes = _QuoteFixture()..failNextRead = true;
        final okx = _OkxReader(
          account: _account(
            source: ExchangeSource.okx,
            product: null,
            asset: 'USDT',
            free: '100',
            locked: '0',
            reportedTotal: '100',
            equity: '100',
          ),
        );
        final instrument = ExchangeInstrument(
          source: ExchangeSource.binance,
          product: ExchangeProduct.spot,
          symbol: 'BTCUSDT',
          baseAsset: const ExchangeValue<String>.available('BTC'),
          quoteAsset: const ExchangeValue<String>.available('USDT'),
          settlementAsset: const ExchangeValue<String>.unavailable(
            'Spot settlement is not applicable.',
          ),
        );
        final binance = _BinanceReader(
          credentialState: storage.binanceCredentialState,
          spot: _account(
            source: ExchangeSource.binance,
            product: ExchangeProduct.spot,
            asset: 'BTC',
            free: '1',
            locked: '0',
            reportedTotal: '1',
            equity: null,
          ),
          futures: _account(
            source: ExchangeSource.binance,
            product: ExchangeProduct.futures,
            asset: 'USDT',
            free: '0',
            locked: null,
            reportedTotal: '0',
            equity: '0',
          ),
          spotCatalogInstruments: <ExchangeInstrument>[instrument],
        );
        final container = _container(
          storage: storage,
          okx: okx,
          binance: binance,
          quotes: quotes,
        );
        addTearDown(() {
          container.dispose();
          storage.dispose();
          binance.dispose();
          quotes.dispose();
        });
        final subscription = container.listen(
          combinedExchangePortfolioProvider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(subscription.close);
        await _drainAsync();

        final portfolio = container.read(combinedExchangePortfolioProvider);
        final btc = portfolio.rows.singleWhere(
          (row) =>
              row.balance.source == ExchangeSource.binance &&
              row.balance.asset == 'BTC',
        );
        expect(portfolio.isPartial, isTrue);
        expect(btc.totalAmount.value?.text, '1');
        expect(btc.quote, isNull);
        expect(btc.valuation.value, isNull);
        expect(
          portfolio.warnings.join(' '),
          contains('Binance Spot equity is incomplete'),
        );
      },
    );
  });

  group('GREEN-118 responsive Portfolio rendering', () {
    testWidgets(
      'synthetic combined Portfolio capture at mobile and desktop widths',
      (tester) async {
        final storage = _storage();
        final quotes = _QuoteFixture();
        final okx = _OkxReader(
          account: _account(
            source: ExchangeSource.okx,
            product: null,
            asset: 'USDT',
            free: '12',
            locked: '0',
            reportedTotal: '12',
            equity: '12',
          ),
        );
        final binance = _BinanceReader(
          credentialState: storage.binanceCredentialState,
          spot: _account(
            source: ExchangeSource.binance,
            product: ExchangeProduct.spot,
            asset: 'USDT',
            free: '8',
            locked: '0',
            reportedTotal: '8',
            equity: null,
          ),
          futures: _account(
            source: ExchangeSource.binance,
            product: ExchangeProduct.futures,
            asset: 'USDT',
            free: '0',
            locked: null,
            reportedTotal: '0',
            equity: '0',
          ),
        );
        addTearDown(() {
          storage.dispose();
          binance.dispose();
          quotes.dispose();
        });
        for (final (name, width, height) in <(String, double, double)>[
          ('mobile', 390, 844),
          ('desktop', 1440, 900),
        ]) {
          tester.view.physicalSize = Size(width, height);
          tester.view.devicePixelRatio = 1;
          await tester.pumpWidget(
            ProviderScope(
              overrides: <Override>[
                ..._accountOverrides(
                  storage: storage,
                  okx: okx,
                  binance: binance,
                  quotes: quotes,
                ),
                currencyProvider.overrideWith((ref) => CurrencyDisplayMode.usd),
                vndExchangeRateProvider.overrideWith((ref) async => 25400),
                themeModeProvider.overrideWith((ref) => ThemeMode.light),
              ],
              child: RepaintBoundary(
                key: const Key('t118-portfolio-capture'),
                child: const MaterialApp(home: PortfolioScreen()),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pump(const Duration(milliseconds: 100));
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('t118-portfolio-capture')),
          );
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await tester.runAsync(
            () => image.toByteData(format: ui.ImageByteFormat.png),
          );
          if (bytes != null) {
            await tester.runAsync(
              () => File(
                '/private/tmp/t118_portfolio_$name.png',
              ).writeAsBytes(bytes.buffer.asUint8List()),
            );
          }
          image.dispose();
        }
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });
}
