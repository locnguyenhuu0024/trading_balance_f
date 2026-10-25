import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/exchange/binance_exchange_reader.dart';
import 'package:trading_balance_f/core/exchange/binance_history_scan.dart';
import 'package:trading_balance_f/core/exchange/binance_read_routes.dart';
import 'package:trading_balance_f/core/exchange/exchange_models.dart';
import 'package:trading_balance_f/core/exchange/exchange_readers.dart';
import 'package:trading_balance_f/core/network/binance_data_client.dart';
import 'package:trading_balance_f/core/network/binance_request_coordinator.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';

void main() {
  group('RED-117', () {
    test(
      'failed symbols are not complete and resume retries only unfinished pages',
      () async {
        final attempts = <String, int>{};
        final fixture = _newFixture((call, coordinator) async {
          if (call.path == '/api/v3/exchangeInfo') {
            return _spotExchangeInfo(<Map<String, Object?>>[
              _spotRow('BNBUSDT', 'BNB', 'USDT'),
              _spotRow('BTCUSDT', 'BTC', 'USDT'),
              _spotRow('ETHBTC', 'ETH', 'BTC'),
            ]);
          }
          if (call.path == '/api/v3/allOrders') {
            final symbol = call.query['symbol']! as String;
            attempts[symbol] = (attempts[symbol] ?? 0) + 1;
            if (symbol == 'BNBUSDT' && attempts[symbol] == 1) {
              return const BinanceDataException(
                code: 'binance_http_error',
                message: 'Binance order history read failed.',
              );
            }
            return <Object?>[_spotOrder(symbol, symbol, attempts[symbol]!)];
          }
          throw StateError('Unexpected endpoint: ' + call.path);
        });
        addTearDown(fixture.dispose);
        final session = fixture.service.startSpotScan();

        final first = await session.run();

        expect(first.state, BinanceHistoryScanState.failed);
        expect(first.totalSymbols, 3);
        expect(first.completedSymbols, 2);
        expect(first.failedSymbols, 1);
        expect(first.pendingSymbols, 0);
        expect(first.hasPartialCoverage, isTrue);
        expect(first.hasAuthoritativeEmptyHistory, isFalse);
        expect(first.rows, hasLength(2));

        final resumed = await session.resume();

        expect(resumed.state, BinanceHistoryScanState.complete);
        expect(resumed.completedSymbols, 3);
        expect(resumed.failedSymbols, 0);
        expect(resumed.pendingSymbols, 0);
        expect(resumed.rows, hasLength(3));
        expect(attempts['BNBUSDT'], 2);
        expect(attempts['BTCUSDT'], 1);
        expect(attempts['ETHBTC'], 1);
      },
    );

    test(
      'credential denial pauses before another captured symbol sends a private read',
      () async {
        final fixture = _newFixture((call, coordinator) async {
          if (call.path == '/api/v3/exchangeInfo') {
            return _spotExchangeInfo(<Map<String, Object?>>[
              _spotRow('BNBUSDT', 'BNB', 'USDT'),
              _spotRow('BTCUSDT', 'BTC', 'USDT'),
              _spotRow('ETHBTC', 'ETH', 'BTC'),
            ]);
          }
          if (call.path == '/api/v3/allOrders') {
            return const BinanceDataException(
              code: 'binance_authentication_failed',
              message: 'Binance rejected the API credentials.',
              statusCode: 401,
            );
          }
          throw StateError('Unexpected endpoint: ' + call.path);
        });
        addTearDown(fixture.dispose);

        final result = await fixture.service.startSpotScan().run();

        expect(result.state, BinanceHistoryScanState.paused);
        expect(result.totalSymbols, 3);
        expect(result.completedSymbols, 0);
        expect(result.failedSymbols, 0);
        expect(result.pendingSymbols, 3);
        expect(result.hasPartialCoverage, isTrue);
        expect(result.hasAuthoritativeEmptyHistory, isFalse);
        expect(
          fixture.client.calls.where(
            (call) => call.path == '/api/v3/allOrders',
          ),
          hasLength(1),
        );
      },
    );

    test(
      'unknown Futures settlement metadata remains a coverage issue without a guessed read',
      () async {
        final fixture = _newFixture((call, coordinator) async {
          if (call.path == '/fapi/v1/exchangeInfo') {
            return _futuresExchangeInfo(const <Map<String, Object?>>[]);
          }
          throw StateError('Unexpected endpoint: ' + call.path);
        });
        addTearDown(fixture.dispose);

        final result = await fixture.service
            .startFuturesScan(knownSymbols: const <String>['ODDUSDT'])
            .run();

        expect(result.state, BinanceHistoryScanState.complete);
        expect(result.totalSymbols, 0);
        expect(result.completedSymbols, 0);
        expect(result.hasPartialCoverage, isTrue);
        expect(result.allCapturedSymbolsComplete, isFalse);
        expect(result.hasAuthoritativeEmptyHistory, isFalse);
        expect(
          result.catalogIssues.any(
            (issue) =>
                issue.code ==
                    'binance_futures_known_symbol_metadata_unavailable' &&
                issue.instrument == 'ODDUSDT',
          ),
          isTrue,
        );
        expect(
          fixture.client.calls.where(
            (call) =>
                call.path == '/fapi/v1/allOrders' ||
                call.path == '/fapi/v1/allAlgoOrders',
          ),
          isEmpty,
        );
      },
    );

    test(
      'credential rotation clears already-published rows and prevents resume',
      () async {
        final secondPageStarted = Completer<void>();
        final secondPageResult = Completer<Object?>();
        final fixture = _newFixture((call, coordinator) async {
          if (call.path == '/api/v3/exchangeInfo') {
            return _spotExchangeInfo(<Map<String, Object?>>[
              _spotRow('BTCUSDT', 'BTC', 'USDT'),
              _spotRow('ETHBTC', 'ETH', 'BTC'),
            ]);
          }
          if (call.path == '/api/v3/allOrders') {
            final symbol = call.query['symbol']! as String;
            if (symbol == 'ETHBTC') {
              if (!secondPageStarted.isCompleted) secondPageStarted.complete();
              return secondPageResult.future;
            }
            return <Object?>[_spotOrder(symbol, '1', 10)];
          }
          throw StateError('Unexpected endpoint: ' + call.path);
        });
        addTearDown(fixture.dispose);
        final session = fixture.service.startSpotScan();
        final running = session.run();
        await secondPageStarted.future;

        expect(session.current.rows, hasLength(1));
        fixture.credentialState.value = const BinanceCredentialSnapshot(
          generation: 2,
          rotating: false,
          privateReadsEnabled: true,
        );
        expect(session.current.state, BinanceHistoryScanState.cancelled);
        expect(session.current.rows, isEmpty);

        secondPageResult.complete(<Object?>[_spotOrder('ETHBTC', '2', 20)]);
        final result = await running;

        expect(result.state, BinanceHistoryScanState.cancelled);
        expect(result.rows, isEmpty);
        expect(result.completedSymbols, 0);
        expect((await session.resume()).rows, isEmpty);
        expect(
          fixture.client.calls.where(
            (call) => call.path == '/api/v3/allOrders',
          ),
          hasLength(2),
        );
      },
    );

    test(
      'budget metadata absence pauses before history and resume refreshes metadata',
      () async {
        var catalogReads = 0;
        final fixture = _newFixture((call, coordinator) async {
          if (call.path == '/api/v3/exchangeInfo') {
            catalogReads++;
            return _spotExchangeInfo(<Map<String, Object?>>[
              _spotRow('BTCUSDT', 'BTC', 'USDT'),
            ], validBudget: catalogReads > 1);
          }
          if (call.path == '/api/v3/allOrders') {
            if (!coordinator.stateFor(BinanceHost.spot).hasValidBudget) {
              return const BinanceDataException(
                code: 'binance_budget_metadata_unavailable',
                message: 'Binance rate-limit metadata is unavailable.',
              );
            }
            return <Object?>[_spotOrder('BTCUSDT', '1', 1)];
          }
          throw StateError('Unexpected endpoint: ' + call.path);
        });
        addTearDown(fixture.dispose);
        final session = fixture.service.startSpotScan();

        final paused = await session.run();

        expect(paused.state, BinanceHistoryScanState.paused);
        expect(paused.totalSymbols, 1);
        expect(paused.pendingSymbols, 1);
        expect(paused.completedSymbols, 0);
        expect(paused.failedSymbols, 0);
        expect(paused.retryAt, isNull);
        expect(
          fixture.client.calls.where(
            (call) => call.path == '/api/v3/allOrders',
          ),
          hasLength(1),
        );

        final resumed = await session.resume();

        expect(catalogReads, 2);
        expect(resumed.state, BinanceHistoryScanState.complete);
        expect(resumed.completedSymbols, 1);
        expect(resumed.rows, hasLength(1));
      },
    );

    test(
      '429 and 418 deadlines remain paused coverage rather than failed symbols',
      () async {
        for (final status in <int>[429, 418]) {
          final fixture = _newFixture((call, coordinator) async {
            if (call.path == '/api/v3/exchangeInfo') {
              return _spotExchangeInfo(<Map<String, Object?>>[
                _spotRow('BTCUSDT', 'BTC', 'USDT'),
              ]);
            }
            if (call.path == '/api/v3/allOrders') {
              coordinator.observeResponse(
                BinanceHost.spot,
                statusCode: status,
                headers: const <String, List<String>>{
                  'retry-after': <String>['60'],
                },
              );
              return BinanceDataException(
                code: status == 429
                    ? 'binance_rate_limited'
                    : 'binance_ip_banned',
                message: 'Binance host cooldown.',
              );
            }
            throw StateError('Unexpected endpoint: ' + call.path);
          });
          addTearDown(fixture.dispose);

          final result = await fixture.service.startSpotScan().run();

          expect(result.state, BinanceHistoryScanState.paused);
          expect(result.failedSymbols, 0);
          expect(result.pendingSymbols, 1);
          expect(result.retryAt, isNotNull);
          expect(result.rows, isEmpty);
        }
      },
    );

    test(
      'history budgets preserve interactive reserve across every advertised interval',
      () async {
        final coordinator = BinanceRequestCoordinator(
          minimumSpacing: Duration.zero,
          delay: (_) async {},
        );
        expect(
          coordinator
              .installLimits(BinanceHost.spot, const <BinanceRateLimitWindow>[
                BinanceRateLimitWindow(
                  rateLimitType: 'REQUEST_WEIGHT',
                  interval: 'MINUTE',
                  intervalNum: 1,
                  limit: 100,
                ),
                BinanceRateLimitWindow(
                  rateLimitType: 'RAW_REQUEST',
                  interval: 'SECOND',
                  intervalNum: 10,
                  limit: 10,
                ),
              ]),
          isTrue,
        );

        for (var index = 0; index < 6; index++) {
          await coordinator.run<void>(
            host: BinanceHost.spot,
            weight: 1,
            rawRequests: 1,
            priority: BinanceRequestPriority.history,
            request: () async {},
          );
        }
        await expectLater(
          coordinator.run<void>(
            host: BinanceHost.spot,
            weight: 1,
            rawRequests: 1,
            priority: BinanceRequestPriority.history,
            request: () async {},
          ),
          throwsA(isA<BinanceRequestPausedException>()),
        );
        await coordinator.run<void>(
          host: BinanceHost.spot,
          weight: 1,
          rawRequests: 1,
          priority: BinanceRequestPriority.interactive,
          request: () async {},
        );
      },
    );

    test(
      'queued interactive work runs ahead of a later history page',
      () async {
        final coordinator = BinanceRequestCoordinator(
          minimumSpacing: Duration.zero,
          delay: (_) async {},
        );
        coordinator
            .installLimits(BinanceHost.spot, const <BinanceRateLimitWindow>[
              BinanceRateLimitWindow(
                rateLimitType: 'REQUEST_WEIGHT',
                interval: 'MINUTE',
                intervalNum: 1,
                limit: 100,
              ),
            ]);
        final firstStarted = Completer<void>();
        final releaseFirst = Completer<void>();
        final order = <String>[];
        final first = coordinator.run<void>(
          host: BinanceHost.spot,
          weight: 1,
          priority: BinanceRequestPriority.history,
          request: () async {
            order.add('first-history');
            firstStarted.complete();
            await releaseFirst.future;
          },
        );
        await firstStarted.future;
        final second = coordinator.run<void>(
          host: BinanceHost.spot,
          weight: 1,
          priority: BinanceRequestPriority.history,
          request: () async {
            order.add('later-history');
          },
        );
        final interactive = coordinator.run<void>(
          host: BinanceHost.spot,
          weight: 1,
          priority: BinanceRequestPriority.interactive,
          request: () async {
            order.add('interactive');
          },
        );

        releaseFirst.complete();
        await Future.wait<void>(<Future<void>>[first, second, interactive]);

        expect(order, <String>[
          'first-history',
          'interactive',
          'later-history',
        ]);
      },
    );
  });

  group('GREEN-117', () {
    test(
      'scans every captured Spot pair sequentially with recent limit 500',
      () async {
        final fixture = _newFixture((call, coordinator) async {
          if (call.path == '/api/v3/exchangeInfo') {
            return _spotExchangeInfo(<Map<String, Object?>>[
              _spotRow('BTCUSDT', 'BTC', 'USDT'),
              _spotRow('ETHBTC', 'ETH', 'BTC'),
            ]);
          }
          if (call.path == '/api/v3/allOrders') {
            final symbol = call.query['symbol']! as String;
            final time = symbol == 'BTCUSDT' ? 10 : 20;
            return <Object?>[_spotOrder(symbol, symbol, time)];
          }
          throw StateError('Unexpected endpoint: ' + call.path);
        });
        addTearDown(fixture.dispose);
        final session = fixture.service.startSpotScan(
          knownSymbols: const <String>['OLDPAIRBTC'],
        );

        final result = await session.run();

        expect(result.totalSymbols, 3);
        expect(result.completedSymbols, 3);
        expect(result.failedSymbols, 0);
        expect(result.pendingSymbols, 0);
        expect(result.allCapturedSymbolsComplete, isTrue);
        expect(result.hasAuthoritativeEmptyHistory, isFalse);
        expect(result.rows.map((order) => order.symbol), <String>[
          'ETHBTC',
          'OLDPAIRBTC',
          'BTCUSDT',
        ]);
        expect(result.coverageNotice, contains('first pages'));
        expect(result.coverageNotice, contains('delisted'));

        final historyCalls = fixture.client.calls
            .where((call) => call.path == '/api/v3/allOrders')
            .toList();
        expect(historyCalls, hasLength(3));
        expect(fixture.client.maxConcurrentHistory, 1);
        expect(
          historyCalls.map((call) => call.priority).toSet(),
          <BinanceRequestPriority>{BinanceRequestPriority.history},
        );
        expect(
          historyCalls.map((call) => call.query['limit']).toSet(),
          <Object?>{500},
        );
        expect(
          historyCalls.every(
            (call) => call.query.keys.toSet().difference(<String>{
              'symbol',
              'limit',
            }).isEmpty,
          ),
          isTrue,
        );
        expect(historyCalls.map((call) => call.query['symbol']).toSet(), {
          'BTCUSDT',
          'ETHBTC',
          'OLDPAIRBTC',
        });
      },
    );

    test(
      'Futures recent ordinary and conditional pages link only actual executions',
      () async {
        final fixture = _newFixture((call, coordinator) async {
          if (call.path == '/fapi/v1/exchangeInfo') {
            return _futuresExchangeInfo(<Map<String, Object?>>[
              _futuresRow('BTCUSDT', 'PERPETUAL'),
              _futuresRow('ETHUSDT', 'CURRENT_QUARTER'),
              _futuresRow('BTCBUSD', 'PERPETUAL', marginAsset: 'BUSD'),
            ]);
          }
          if (call.path == '/fapi/v1/allOrders') {
            final symbol = call.query['symbol']! as String;
            return symbol == 'BTCUSDT'
                ? <Object?>[_futuresOrder('BTCUSDT', '21', 10)]
                : const <Object?>[];
          }
          if (call.path == '/fapi/v1/allAlgoOrders') {
            final symbol = call.query['symbol']! as String;
            return symbol == 'BTCUSDT'
                ? <Object?>[_algoOrder('BTCUSDT', '900', '21', 30)]
                : const <Object?>[];
          }
          throw StateError('Unexpected endpoint: ' + call.path);
        });
        addTearDown(fixture.dispose);

        final result = await fixture.service.startFuturesScan().run();

        expect(result.totalSymbols, 2);
        expect(result.completedSymbols, 2);
        expect(result.failedSymbols, 0);
        expect(result.rows, hasLength(1));
        final execution = result.rows.single;
        expect(execution.product, ExchangeProduct.swap);
        expect(execution.nativeId, '21');
        expect(execution.conditionalParent?.nativeId, '900');
        expect(execution.conditionalParent?.actualOrderId, '21');
        expect(execution.conditionalParent?.status, 'TRIGGERED');
        expect(execution.conditionalParent?.createdAtMilliseconds, 30);
        expect(
          (execution.conditionalParent?.nativeRecord as Map)['algoId'],
          '900',
        );
        final historyCalls = fixture.client.calls.where(
          (call) =>
              call.path == '/fapi/v1/allOrders' ||
              call.path == '/fapi/v1/allAlgoOrders',
        );
        expect(historyCalls, hasLength(4));
        expect(
          historyCalls.every((call) => call.query['limit'] == 500),
          isTrue,
        );
        expect(
          historyCalls.every(
            (call) =>
                call.priority == BinanceRequestPriority.history &&
                call.query.keys.toSet().difference(<String>{
                  'symbol',
                  'limit',
                }).isEmpty,
          ),
          isTrue,
        );
        expect(fixture.client.maxConcurrentHistory, 1);
        expect(result.coverageNotice, contains('recent seven days'));
        expect(result.coverageNotice, contains('older than 90 days'));
        expect(
          result.coverageNotice,
          contains('canceled or expired unfilled orders after three days'),
        );
      },
    );

    test('a refreshed scan supersedes an in-flight stale callback', () async {
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<Object?>();
      var historyReads = 0;
      final fixture = _newFixture((call, coordinator) async {
        if (call.path == '/api/v3/exchangeInfo') {
          return _spotExchangeInfo(<Map<String, Object?>>[
            _spotRow('BTCUSDT', 'BTC', 'USDT'),
          ]);
        }
        if (call.path == '/api/v3/allOrders') {
          historyReads++;
          if (historyReads == 1) {
            firstStarted.complete();
            return releaseFirst.future;
          }
          return <Object?>[_spotOrder('BTCUSDT', 'fresh', 2)];
        }
        throw StateError('Unexpected endpoint: ' + call.path);
      });
      addTearDown(fixture.dispose);
      final old = fixture.service.startSpotScan();
      final oldRun = old.run();
      await firstStarted.future;
      final fresh = fixture.service.startSpotScan();
      expect(old.current.state, BinanceHistoryScanState.cancelled);
      final freshRun = fresh.run();

      releaseFirst.complete(<Object?>[_spotOrder('BTCUSDT', 'stale', 1)]);
      final oldResult = await oldRun;
      final freshResult = await freshRun;

      expect(oldResult.rows, isEmpty);
      expect(freshResult.rows.single.nativeId, 'fresh');
      expect(freshResult.state, BinanceHistoryScanState.complete);
    });
  });
}

typedef _Handler =
    Future<Object?> Function(_Call call, BinanceRequestCoordinator coordinator);

class _Call {
  const _Call({
    required this.path,
    required this.query,
    required this.priority,
    required this.cancelToken,
  });

  final String path;
  final Map<String, dynamic> query;
  final BinanceRequestPriority priority;
  final CancelToken? cancelToken;
}

class _FakeBinanceDataClient extends BinanceDataClient {
  _FakeBinanceDataClient(this.handler, this.coordinator) : super();

  final _Handler handler;
  final BinanceRequestCoordinator coordinator;
  final List<_Call> calls = <_Call>[];
  int activeHistory = 0;
  int maxConcurrentHistory = 0;

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    BinanceRequestPriority priority = BinanceRequestPriority.interactive,
  }) async {
    final call = _Call(
      path: path,
      query: Map<String, dynamic>.of(
        queryParameters ?? const <String, dynamic>{},
      ),
      priority: priority,
      cancelToken: cancelToken,
    );
    calls.add(call);
    final isHistory = priority == BinanceRequestPriority.history;
    if (isHistory) {
      activeHistory++;
      if (activeHistory > maxConcurrentHistory) {
        maxConcurrentHistory = activeHistory;
      }
    }
    try {
      final data = await handler(call, coordinator);
      if (data is BinanceDataException) throw data;
      if (path.endsWith('/exchangeInfo')) {
        final host = path.startsWith('/fapi/')
            ? BinanceHost.futures
            : BinanceHost.spot;
        coordinator.updateFromExchangeInfo(host, data);
      }
      return Response<dynamic>(
        requestOptions: RequestOptions(path: path),
        data: data,
        statusCode: 200,
      );
    } finally {
      if (isHistory) activeHistory--;
    }
  }
}

class _Fixture {
  _Fixture({
    required this.client,
    required this.reader,
    required this.service,
    required this.coordinator,
    required this.credentialState,
  });

  final _FakeBinanceDataClient client;
  final BinanceExchangeReader reader;
  final BinanceHistoryScanService service;
  final BinanceRequestCoordinator coordinator;
  final ValueNotifier<BinanceCredentialSnapshot> credentialState;

  void dispose() {
    service.dispose();
    reader.dispose();
    client.dispose();
    credentialState.dispose();
  }
}

_Fixture _newFixture(_Handler handler) {
  final coordinator = BinanceRequestCoordinator(
    minimumSpacing: Duration.zero,
    delay: (_) async {},
  );
  final client = _FakeBinanceDataClient(handler, coordinator);
  final credentialState = ValueNotifier(
    const BinanceCredentialSnapshot(
      generation: 1,
      rotating: false,
      privateReadsEnabled: true,
    ),
  );
  final reader = BinanceExchangeReader(
    client: client,
    credentialState: credentialState,
    requestCoordinator: coordinator,
  );
  final service = BinanceHistoryScanService(
    reader: reader,
    requestCoordinator: coordinator,
  );
  return _Fixture(
    client: client,
    reader: reader,
    service: service,
    coordinator: coordinator,
    credentialState: credentialState,
  );
}

Map<String, Object?> _spotExchangeInfo(
  List<Map<String, Object?>> symbols, {
  bool validBudget = true,
}) => <String, Object?>{
  'symbols': symbols,
  'rateLimits': validBudget
      ? const <Object?>[
          <String, Object?>{
            'rateLimitType': 'REQUEST_WEIGHT',
            'interval': 'MINUTE',
            'intervalNum': 1,
            'limit': 1000,
          },
          <String, Object?>{
            'rateLimitType': 'RAW_REQUEST',
            'interval': 'SECOND',
            'intervalNum': 10,
            'limit': 1000,
          },
        ]
      : const <Object?>[],
};

Map<String, Object?> _futuresExchangeInfo(List<Map<String, Object?>> symbols) =>
    <String, Object?>{
      'symbols': symbols,
      'rateLimits': const <Object?>[
        <String, Object?>{
          'rateLimitType': 'REQUEST_WEIGHT',
          'interval': 'MINUTE',
          'intervalNum': 1,
          'limit': 1000,
        },
        <String, Object?>{
          'rateLimitType': 'RAW_REQUEST',
          'interval': 'SECOND',
          'intervalNum': 10,
          'limit': 1000,
        },
      ],
    };

Map<String, Object?> _spotRow(String symbol, String base, String quote) =>
    <String, Object?>{
      'symbol': symbol,
      'baseAsset': base,
      'quoteAsset': quote,
      'status': 'TRADING',
      'isSpotTradingAllowed': true,
    };

Map<String, Object?> _futuresRow(
  String symbol,
  String contractType, {
  String marginAsset = 'USDT',
}) => <String, Object?>{
  'symbol': symbol,
  'baseAsset': 'BTC',
  'quoteAsset': 'USDT',
  'marginAsset': marginAsset,
  'contractType': contractType,
  'status': 'TRADING',
};

Map<String, Object?> _spotOrder(String symbol, String id, int time) =>
    <String, Object?>{
      'symbol': symbol,
      'orderId': id,
      'side': 'BUY',
      'status': 'FILLED',
      'origQty': '1.000',
      'executedQty': '1.000',
      'cummulativeQuoteQty': '10.00',
      'price': '10.00',
      'time': time,
      'updateTime': time + 1,
    };

Map<String, Object?> _futuresOrder(String symbol, String id, int time) =>
    <String, Object?>{
      'symbol': symbol,
      'orderId': id,
      'side': 'BUY',
      'status': 'FILLED',
      'origQty': '1',
      'executedQty': '1',
      'cumQuote': '100',
      'avgPrice': '100',
      'time': time,
      'updateTime': time + 1,
    };

Map<String, Object?> _algoOrder(
  String symbol,
  String algoId,
  String actualOrderId,
  int createdAt,
) => <String, Object?>{
  'symbol': symbol,
  'algoId': algoId,
  'actualOrderId': actualOrderId,
  'side': 'BUY',
  'algoStatus': 'TRIGGERED',
  'quantity': '1',
  'createTime': createdAt,
  'updateTime': createdAt + 1,
  'price': '100',
};
