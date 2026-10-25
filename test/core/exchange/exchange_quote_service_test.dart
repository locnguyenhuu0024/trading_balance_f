import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/exchange/exchange_models.dart';
import 'package:trading_balance_f/core/exchange/exchange_quote_service.dart';
import 'package:trading_balance_f/core/exchange/binance_read_routes.dart';
import 'package:trading_balance_f/core/network/binance_data_client.dart';
import 'package:trading_balance_f/core/network/binance_request_coordinator.dart';
import 'package:trading_balance_f/core/network/okx_data_client.dart';

void main() {
  group('RED-117', () {
    test('new quote owner does not join a cancelled in-flight batch', () async {
      final adapter = _ControlledAdapter(heldIndexes: <int>{0, 1});
      final fixture = _fixture(adapter);
      final firstOwner = fixture.service.createOwner();
      final instrument = _instrument('BTC-USDT');
      final firstLoad = fixture.service.loadQuotes(
        owner: firstOwner,
        instruments: <ExchangeInstrument>[instrument],
      );
      await _waitUntil(() => adapter.requests.length == 1);

      firstOwner.dispose();
      final firstLoadCancelled = expectLater(
        firstLoad,
        throwsA(isA<ExchangeQuoteCancelledException>()),
      );
      final secondOwner = fixture.service.createOwner();
      final secondLoad = fixture.service.loadQuotes(
        owner: secondOwner,
        instruments: <ExchangeInstrument>[instrument],
      );
      await _waitUntil(() => adapter.requests.length == 2);

      adapter.reply(1, _rows('BTC-USDT', '12'));
      final secondSnapshot = await secondLoad;
      expect(_price(secondSnapshot, instrument), '12');
      adapter.reply(0, _rows('BTC-USDT', '11'));
      await firstLoadCancelled;

      secondOwner.dispose();
      fixture.dispose();
    });

    test(
      'revalidates a fresh cached quote after another quote finishes slowly',
      () async {
        final adapter = _ControlledAdapter(heldIndexes: <int>{1});
        final fixture = _fixture(adapter);
        final owner = fixture.service.createOwner();
        final bitcoin = _instrument('BTC-USDT');
        final ethereum = _instrument('ETH-USDT');

        final initial = await fixture.service.loadQuotes(
          owner: owner,
          instruments: <ExchangeInstrument>[bitcoin],
        );
        expect(_price(initial, bitcoin), '10');

        fixture.clock.now = fixture.clock.now.add(const Duration(seconds: 14));
        final slowLoad = fixture.service.loadQuotes(
          owner: owner,
          instruments: <ExchangeInstrument>[bitcoin, ethereum],
        );
        await _waitUntil(() => adapter.requests.length == 2);
        fixture.clock.now = fixture.clock.now.add(const Duration(seconds: 2));
        adapter.reply(1, _rows('ETH-USDT', '20'));

        final snapshot = await slowLoad;
        expect(adapter.requests, hasLength(3));
        expect(_price(snapshot, bitcoin), '11');
        expect(_price(snapshot, ethereum), '20');
        expect(
          snapshot.values.values.every(
            (value) =>
                value.value == null ||
                fixture.clock.now.difference(value.value!.observedAt) <
                    const Duration(seconds: 15),
          ),
          isTrue,
        );

        owner.dispose();
        fixture.dispose();
      },
    );
  });

  group('GREEN-117', () {
    test(
      'quote cache expires at 15 seconds and includes product in its key',
      () async {
        final adapter = _ControlledAdapter(heldIndexes: const <int>{});
        final fixture = _fixture(adapter);
        final owner = fixture.service.createOwner();
        final spot = _instrument('BTC-USDT');

        final first = await fixture.service.loadQuotes(
          owner: owner,
          instruments: <ExchangeInstrument>[spot],
        );
        fixture.clock.now = fixture.clock.now.add(const Duration(seconds: 14));
        final cached = await fixture.service.loadQuotes(
          owner: owner,
          instruments: <ExchangeInstrument>[spot],
        );
        expect(_price(first, spot), '10');
        expect(_price(cached, spot), '10');
        expect(adapter.requests, hasLength(1));

        fixture.clock.now = fixture.clock.now.add(const Duration(seconds: 1));
        final refreshed = await fixture.service.loadQuotes(
          owner: owner,
          instruments: <ExchangeInstrument>[spot],
        );
        expect(_price(refreshed, spot), '12');
        expect(adapter.requests, hasLength(2));

        final swap = _instrument('BTC-USDT', product: ExchangeProduct.swap);
        final distinctProduct = await fixture.service.loadQuotes(
          owner: owner,
          instruments: <ExchangeInstrument>[swap],
        );
        expect(_price(distinctProduct, swap), '11');
        expect(adapter.requests, hasLength(3));

        owner.dispose();
        fixture.dispose();
      },
    );

    test('Binance Spot quote batches contain at most twenty symbols', () async {
      final adapter = _BinanceQuoteAdapter();
      final fixture = _networkFixture(
        binanceAdapter: adapter,
        okxAdapter: _OkxQuoteAdapter(const <Map<String, Object>>[]),
      );
      final owner = fixture.service.createOwner();
      final instruments = List<ExchangeInstrument>.generate(
        21,
        (index) => _binanceInstrument(
          'PAIR' + index.toString().padLeft(2, '0') + 'USDT',
        ),
      );

      final snapshot = await fixture.service.loadQuotes(
        owner: owner,
        instruments: instruments,
      );

      expect(snapshot.values, hasLength(21));
      final batchSizes = adapter.requests.map((request) {
        final encoded = request.uri.queryParameters['symbols']!;
        return (jsonDecode(encoded) as List).length;
      }).toList();
      expect(batchSizes, <int>[20, 1]);
      expect(
        adapter.requests.every(
          (request) =>
              request.uri.path == '/api/v3/ticker/24hr' &&
              request.uri.queryParameters.keys.toSet().contains('symbols'),
        ),
        isTrue,
      );

      final hundredInstruments = List<ExchangeInstrument>.generate(
        100,
        (index) => _binanceInstrument(
          'BATCH' + index.toString().padLeft(3, '0') + 'USDT',
        ),
      );
      final hundredSnapshot = await fixture.service.loadQuotes(
        owner: owner,
        instruments: hundredInstruments,
      );
      expect(hundredSnapshot.values, hasLength(100));
      expect(adapter.requests, hasLength(7));
      final hundredBatchSizes = adapter.requests.skip(2).map((request) {
        final encoded = request.uri.queryParameters['symbols']!;
        return (jsonDecode(encoded) as List).length;
      }).toList();
      expect(hundredBatchSizes, <int>[20, 20, 20, 20, 20]);
      expect(
        adapter.requests.every(
          (request) =>
              ((jsonDecode(request.uri.queryParameters['symbols']!) as List)
                  .length) <=
              20,
        ),
        isTrue,
      );

      owner.dispose();
      fixture.dispose();
    });

    test(
      'source-specific quotes never cross-fallback and reject invalid prices',
      () async {
        final oversized = List<String>.filled(400, '9').join();
        final binanceAdapter = _BinanceQuoteAdapter(
          spotPrices: <String, String>{
            'BTCUSDT': '10',
            'ETHUSDT': '30',
            'ADAUSDT': '0',
            'BNBUSDT': 'NaN',
            'XRPUSDT': oversized,
          },
        );
        final okxAdapter = _OkxQuoteAdapter(<Map<String, Object>>[
          <String, Object>{'instId': 'BTCUSDT', 'last': '20'},
          <String, Object>{'instId': 'ADAUSDT', 'last': '1e309'},
          <String, Object>{'instId': 'BNBUSDT', 'last': '0'},
        ]);
        final fixture = _networkFixture(
          binanceAdapter: binanceAdapter,
          okxAdapter: okxAdapter,
        );
        final owner = fixture.service.createOwner();
        final binanceBtc = _binanceInstrument('BTCUSDT');
        final okxBtc = _instrument('BTCUSDT');
        final binanceEth = _binanceInstrument('ETHUSDT');
        final okxEth = _instrument('ETHUSDT');
        final invalidBinance = <ExchangeInstrument>[
          _binanceInstrument('ADAUSDT'),
          _binanceInstrument('BNBUSDT'),
          _binanceInstrument('XRPUSDT'),
        ];
        final invalidOkx = <ExchangeInstrument>[
          _instrument('ADAUSDT'),
          _instrument('BNBUSDT'),
        ];

        final snapshot = await fixture.service.loadQuotes(
          owner: owner,
          instruments: <ExchangeInstrument>[
            binanceBtc,
            okxBtc,
            binanceEth,
            okxEth,
            ...invalidBinance,
            ...invalidOkx,
          ],
        );

        expect(_price(snapshot, binanceBtc), '10');
        expect(_price(snapshot, okxBtc), '20');
        expect(_price(snapshot, binanceEth), '30');
        expect(_price(snapshot, okxEth), isNull);
        for (final instrument in <ExchangeInstrument>[
          ...invalidBinance,
          ...invalidOkx,
        ]) {
          expect(_price(snapshot, instrument), isNull);
        }

        owner.dispose();
        fixture.dispose();
      },
    );

    test('Futures products share one all-symbol ticker snapshot', () async {
      final adapter = _BinanceQuoteAdapter(
        futuresRows: <Map<String, Object>>[
          <String, Object>{'symbol': 'BTCUSDT', 'lastPrice': '100'},
          <String, Object>{'symbol': 'ETHUSDT', 'lastPrice': '50'},
        ],
      );
      final fixture = _networkFixture(
        binanceAdapter: adapter,
        okxAdapter: _OkxQuoteAdapter(const <Map<String, Object>>[]),
      );
      final owner = fixture.service.createOwner();
      final bitcoin = _binanceFuturesInstrument(
        'BTCUSDT',
        ExchangeProduct.swap,
      );
      final ethereum = _binanceFuturesInstrument(
        'ETHUSDT',
        ExchangeProduct.futures,
      );

      final snapshot = await fixture.service.loadQuotes(
        owner: owner,
        instruments: <ExchangeInstrument>[bitcoin, ethereum],
      );

      expect(_price(snapshot, bitcoin), '100');
      expect(_price(snapshot, ethereum), '50');
      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.uri.path, '/fapi/v1/ticker/24hr');
      expect(adapter.requests.single.uri.queryParameters, isEmpty);

      owner.dispose();
      fixture.dispose();
    });

    test(
      'expired cached quote is unavailable when bounded refresh is invalid',
      () async {
        final adapter = _ControlledAdapter(
          heldIndexes: const <int>{1},
          responses: <int, Object>{2: _rows('BTC-USDT', '0')},
        );
        final fixture = _fixture(adapter);
        final owner = fixture.service.createOwner();
        final bitcoin = _instrument('BTC-USDT');
        final ethereum = _instrument('ETH-USDT');
        await fixture.service.loadQuotes(
          owner: owner,
          instruments: <ExchangeInstrument>[bitcoin],
        );

        fixture.clock.now = fixture.clock.now.add(const Duration(seconds: 14));
        final pending = fixture.service.loadQuotes(
          owner: owner,
          instruments: <ExchangeInstrument>[bitcoin, ethereum],
        );
        await _waitUntil(() => adapter.requests.length == 2);
        fixture.clock.now = fixture.clock.now.add(const Duration(seconds: 2));
        adapter.reply(1, _rows('ETH-USDT', '20'));

        final snapshot = await pending;

        expect(snapshot.values.values, hasLength(2));
        expect(_price(snapshot, bitcoin), isNull);
        expect(_price(snapshot, ethereum), '20');
        expect(adapter.requests, hasLength(3));

        owner.dispose();
        fixture.dispose();
      },
    );
  });
}

String? _price(ExchangeQuoteSnapshot snapshot, ExchangeInstrument instrument) =>
    snapshot
        .values[ExchangeQuoteKey(
          source: instrument.source,
          product: instrument.product,
          instrument: instrument.symbol,
        )]
        ?.value
        ?.price
        .text;

ExchangeInstrument _instrument(
  String symbol, {
  ExchangeProduct product = ExchangeProduct.spot,
}) => ExchangeInstrument(
  source: ExchangeSource.okx,
  product: product,
  symbol: symbol,
  baseAsset: const ExchangeValue.available('BTC'),
  quoteAsset: const ExchangeValue.available('USDT'),
  settlementAsset: const ExchangeValue.available('USDT'),
);

ExchangeInstrument _binanceInstrument(String symbol) => ExchangeInstrument(
  source: ExchangeSource.binance,
  product: ExchangeProduct.spot,
  symbol: symbol,
  baseAsset: const ExchangeValue.available('PAIR'),
  quoteAsset: const ExchangeValue.available('USDT'),
  settlementAsset: const ExchangeValue.available('USDT'),
);

ExchangeInstrument _binanceFuturesInstrument(
  String symbol,
  ExchangeProduct product,
) => ExchangeInstrument(
  source: ExchangeSource.binance,
  product: product,
  symbol: symbol,
  baseAsset: const ExchangeValue.available('BTC'),
  quoteAsset: const ExchangeValue.available('USDT'),
  settlementAsset: const ExchangeValue.available('USDT'),
);

Object _rows(String symbol, String price) => <String, Object>{
  'code': '0',
  'data': <Object>[
    <String, Object>{'instId': symbol, 'last': price},
  ],
};

_QuoteFixture _fixture(_ControlledAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  final okx = OkxDataClient(dio: dio);
  final binance = BinanceDataClient();
  final clock = _MutableClock(DateTime.utc(2026, 10, 25, 8));
  final service = ExchangeQuoteService(
    binanceClient: binance,
    okxClient: okx,
    clock: () => clock.now,
  );
  return _QuoteFixture(service, binance, okx, clock);
}

_QuoteFixture _networkFixture({
  required HttpClientAdapter binanceAdapter,
  required HttpClientAdapter okxAdapter,
}) {
  final coordinator = _testCoordinator();
  final binance = BinanceDataClient(
    requestCoordinator: coordinator,
    dio: Dio()..httpClientAdapter = binanceAdapter,
  );
  final okx = OkxDataClient(dio: Dio()..httpClientAdapter = okxAdapter);
  final clock = _MutableClock(DateTime.utc(2026, 10, 25, 8));
  final service = ExchangeQuoteService(
    binanceClient: binance,
    okxClient: okx,
    clock: () => clock.now,
  );
  return _QuoteFixture(service, binance, okx, clock);
}

BinanceRequestCoordinator _testCoordinator() {
  final coordinator = BinanceRequestCoordinator(
    minimumSpacing: Duration.zero,
    delay: (_) async {},
  );
  final limits = <BinanceRateLimitWindow>[
    const BinanceRateLimitWindow(
      rateLimitType: 'REQUEST_WEIGHT',
      interval: 'MINUTE',
      intervalNum: 1,
      limit: 6000,
    ),
    const BinanceRateLimitWindow(
      rateLimitType: 'RAW_REQUEST',
      interval: 'MINUTE',
      intervalNum: 1,
      limit: 1200,
    ),
  ];
  coordinator.installLimits(BinanceHost.spot, limits);
  coordinator.installLimits(BinanceHost.futures, limits);
  return coordinator;
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for the expected quote request.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _QuoteFixture {
  const _QuoteFixture(this.service, this.binance, this.okx, this.clock);

  final ExchangeQuoteService service;
  final BinanceDataClient binance;
  final OkxDataClient okx;
  final _MutableClock clock;

  void dispose() {
    service.dispose();
    binance.dispose();
    okx.dispose();
  }
}

class _MutableClock {
  _MutableClock(this.now);

  DateTime now;
}

class _ControlledAdapter implements HttpClientAdapter {
  _ControlledAdapter({
    required this.heldIndexes,
    this.responses = const <int, Object>{},
  });

  final Set<int> heldIndexes;
  final Map<int, Object> responses;
  final List<RequestOptions> requests = <RequestOptions>[];
  final Map<int, Completer<ResponseBody>> _held =
      <int, Completer<ResponseBody>>{};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final index = requests.length;
    requests.add(options);
    if (heldIndexes.contains(index)) {
      final completer = Completer<ResponseBody>();
      _held[index] = completer;
      return completer.future;
    }
    final custom = responses[index];
    if (custom != null) {
      return Future<ResponseBody>.value(_response(custom));
    }
    if (index == 0)
      return Future<ResponseBody>.value(_response(_rows('BTC-USDT', '10')));
    if (index == 2)
      return Future<ResponseBody>.value(_response(_rows('BTC-USDT', '11')));
    return Future<ResponseBody>.value(_response(_rows('BTC-USDT', '12')));
  }

  void reply(int index, Object body) {
    final completer = _held[index];
    if (completer == null || completer.isCompleted) return;
    completer.complete(_response(body));
  }

  @override
  void close({bool force = false}) {}
}

class _BinanceQuoteAdapter implements HttpClientAdapter {
  _BinanceQuoteAdapter({
    this.spotPrices = const <String, String>{},
    this.futuresRows = const <Map<String, Object>>[],
  });

  final Map<String, String> spotPrices;
  final List<Map<String, Object>> futuresRows;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.uri.path == '/fapi/v1/ticker/24hr') {
      return _response(futuresRows);
    }
    final symbols =
        jsonDecode(options.uri.queryParameters['symbols']!) as List<dynamic>;
    final rows = symbols
        .map(
          (symbol) => <String, Object>{
            'symbol': symbol.toString(),
            'lastPrice': spotPrices[symbol.toString()] ?? '2',
          },
        )
        .toList(growable: false);
    return _response(rows);
  }

  @override
  void close({bool force = false}) {}
}

class _OkxQuoteAdapter implements HttpClientAdapter {
  _OkxQuoteAdapter(this.rows);

  final List<Map<String, Object>> rows;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return _response(<String, Object>{'code': '0', 'data': rows});
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _response(Object body) => ResponseBody.fromString(
  jsonEncode(body),
  200,
  headers: <String, List<String>>{
    Headers.contentTypeHeader: <String>[Headers.jsonContentType],
  },
);
