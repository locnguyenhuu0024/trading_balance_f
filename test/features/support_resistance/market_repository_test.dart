import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/network/backend_data_client.dart';
import 'package:trading_balance_f/core/network/request_coordinator.dart';
import 'package:trading_balance_f/features/support_resistance/data/market_repository.dart';
import 'package:trading_balance_f/features/support_resistance/domain/models.dart';

void main() {
  final now = DateTime.utc(2026, 9, 29, 12);

  test(
    'RED-28 drops the open spike, ignores tied highs, and uses crossed support',
    () async {
      final closed = _levelCandles(
        count: 300,
        timeframe: SupportResistanceTimeframe.h1,
        now: now,
        highAt: const <int, double>{5: 103, 40: 110, 41: 110},
      );
      final openTime = now;
      final adapter = _RecordingAdapter((request) {
        if (request.uri.path ==
            _backendPath(SupportResistanceRepository.tickerEndpoint)) {
          return const _WireResponse(<String, Object?>{
            'code': '0',
            'data': <Object?>[
              <String, Object?>{'instId': 'ETH-USDT', 'last': '104'},
            ],
          });
        }
        if (request.uri.path ==
            _backendPath(SupportResistanceRepository.candlesEndpoint)) {
          if (request.queryParameters['after'] == null) {
            return _ok(<Object?>[
              _row(openTime, 100, 1000, 99, 100, '0'),
              ...closed.skip(1).toList().reversed.map(_rowFor),
            ]);
          }
          return _ok(<Object?>[_rowFor(closed.first)]);
        }
        throw StateError('Unexpected endpoint ${request.uri.path}');
      });
      final repository = _repository(adapter, now);

      final result = await repository.loadLevels(
        marketMode: SupportResistanceMarketMode.spot,
        instrumentId: 'ETH-USDT',
        timeframe: SupportResistanceTimeframe.h1,
      );

      expect(result.candles, hasLength(300));
      expect(result.candles.every((candle) => candle.confirmed), isTrue);
      expect(result.analysis.supports.map((level) => level.price), <double>[
        103,
      ]);
      expect(result.analysis.resistances, isEmpty);
      final candleRequests = adapter.requests
          .where(
            (request) =>
                request.uri.path ==
                _backendPath(SupportResistanceRepository.candlesEndpoint),
          )
          .toList();
      expect(candleRequests, hasLength(2));
      expect(candleRequests.first.queryParameters['instId'], 'ETH-USDT');
      expect(candleRequests.first.queryParameters['bar'], '1H');
      expect(candleRequests.first.queryParameters['limit'], 300);
      expect(candleRequests.last.queryParameters['after'], isNotNull);
    },
  );

  test(
    'GREEN-28 computes 300-candle spot and perpetual results with exact keys',
    () async {
      final candles = _levelCandles(
        count: 300,
        timeframe: SupportResistanceTimeframe.h6,
        now: now,
        highAt: const <int, double>{
          10: 103,
          30: 103.2,
          50: 105,
          70: 102,
          90: 110,
          110: 106,
          130: 108,
        },
        lowAt: const <int, double>{
          20: 95,
          40: 95.4,
          60: 97,
          80: 92,
          100: 98,
          120: 96,
          140: 94,
        },
      );
      final adapter = _RecordingAdapter((request) {
        if (request.uri.path ==
            _backendPath(SupportResistanceRepository.tickerEndpoint)) {
          final instrument = request.queryParameters['instId'];
          return _ok(<Object?>[
            <String, Object?>{'instId': instrument, 'last': '100.3'},
          ]);
        }
        if (request.uri.path ==
            _backendPath(SupportResistanceRepository.candlesEndpoint)) {
          return _ok(candles.reversed.map(_rowFor).toList());
        }
        throw StateError('Unexpected endpoint ${request.uri.path}');
      });
      final repository = _repository(adapter, now);

      final spot = await repository.loadLevels(
        marketMode: SupportResistanceMarketMode.spot,
        instrumentId: 'ETH-USDT',
        timeframe: SupportResistanceTimeframe.h6,
      );
      final perpetual = await repository.loadLevels(
        marketMode: SupportResistanceMarketMode.perpetual,
        instrumentId: 'ETH-USDT-SWAP',
        timeframe: SupportResistanceTimeframe.h6,
      );

      for (final result in <SupportResistanceMarketSnapshot>[spot, perpetual]) {
        expect(result.candles, hasLength(300));
        expect(result.analysis.supports.map((level) => level.price), <double>[
          98,
          97,
          96,
          95.2,
          94,
        ]);
        expect(
          result.analysis.resistances.map((level) => level.price),
          <double>[102, 103.1, 105, 106, 108],
        );
      }
      final tickerKeys = adapter.requests
          .where(
            (request) =>
                request.uri.path ==
                _backendPath(SupportResistanceRepository.tickerEndpoint),
          )
          .map((request) => request.queryParameters['instId'])
          .toList();
      final candleKeys = adapter.requests
          .where(
            (request) =>
                request.uri.path ==
                _backendPath(SupportResistanceRepository.candlesEndpoint),
          )
          .map((request) => request.queryParameters)
          .toList();
      expect(tickerKeys, <String>['ETH-USDT', 'ETH-USDT-SWAP']);
      expect(candleKeys.map((query) => query['instId']), <String>[
        'ETH-USDT',
        'ETH-USDT-SWAP',
      ]);
      expect(candleKeys.map((query) => query['bar']), <String>[
        '6Hutc',
        '6Hutc',
      ]);
    },
  );

  test(
    'GREEN-28 discovers only active USDT instruments in the selected mode',
    () async {
      final adapter = _RecordingAdapter((request) {
        if (request.uri.path ==
            _backendPath(SupportResistanceRepository.instrumentsEndpoint)) {
          if (request.queryParameters['instType'] == 'SPOT') {
            return _ok(<Object?>[
              _instrument('ETH-USDT', 'SPOT', 'ETH', quote: 'USDT'),
              _instrument('ETH-USDC', 'SPOT', 'ETH', quote: 'USDC'),
              _instrument(
                'BTC-USDT',
                'SPOT',
                'BTC',
                quote: 'USDT',
                state: 'suspend',
              ),
            ]);
          }
          return _ok(<Object?>[
            _instrument('ETH-USDT-SWAP', 'SWAP', 'ETH', settle: 'USDT'),
            _instrument('ETH-USD-SWAP', 'SWAP', 'ETH', settle: 'USD'),
          ]);
        }
        throw StateError('Unexpected endpoint ${request.uri.path}');
      });
      final repository = _repository(adapter, now);

      final spot = await repository.getInstruments(
        marketMode: SupportResistanceMarketMode.spot,
      );
      final perpetual = await repository.getInstruments(
        marketMode: SupportResistanceMarketMode.perpetual,
      );

      expect(spot.map((item) => item.instrumentId), <String>['ETH-USDT']);
      expect(perpetual.map((item) => item.instrumentId), <String>[
        'ETH-USDT-SWAP',
      ]);
      expect(adapter.requests[0].queryParameters['instType'], 'SPOT');
      expect(adapter.requests[1].queryParameters['instType'], 'SWAP');
    },
  );

  test(
    'GREEN-28 AUD-28-01 derives a blank-base SWAP key and skips irrelevant rows',
    () async {
      final adapter = _RecordingAdapter((request) {
        if (request.uri.path ==
            _backendPath(SupportResistanceRepository.instrumentsEndpoint)) {
          return _ok(<Object?>[
            _instrument('ETH-USDT-SWAP', 'SWAP', '', settle: 'USDT'),
            _instrument('ETH-USD-SWAP', 'SWAP', '', settle: 'USD'),
          ]);
        }
        throw StateError('Unexpected endpoint ${request.uri.path}');
      });
      final repository = _repository(adapter, now);

      final perpetual = await repository.getInstruments(
        marketMode: SupportResistanceMarketMode.perpetual,
      );

      expect(perpetual, hasLength(1));
      expect(perpetual.single.instrumentId, 'ETH-USDT-SWAP');
      expect(perpetual.single.baseCurrency, 'ETH');
    },
  );

  test(
    'GREEN-28 maps each selection to the UTC exchange bar identifier',
    () async {
      final adapter = _RecordingAdapter((request) {
        if (request.uri.path ==
            _backendPath(SupportResistanceRepository.candlesEndpoint)) {
          return _ok(const <Object?>[]);
        }
        throw StateError('Unexpected endpoint ${request.uri.path}');
      });
      final repository = _repository(adapter, now);

      for (final timeframe in SupportResistanceTimeframe.values) {
        await repository.getCandles(
          marketMode: SupportResistanceMarketMode.spot,
          instrumentId: 'ETH-USDT',
          timeframe: timeframe,
        );
      }

      expect(
        adapter.requests.map((request) => request.queryParameters['bar']),
        <String>['1H', '4H', '6Hutc', '1Dutc', '1Wutc'],
      );
    },
  );

  test(
    'invalid ticker and candle keys return typed response failures',
    () async {
      final adapter = _RecordingAdapter((request) {
        if (request.uri.path ==
            _backendPath(SupportResistanceRepository.tickerEndpoint)) {
          return _ok(<Object?>[
            <String, Object?>{'instId': 'ETH-USDT-SWAP', 'last': '100'},
          ]);
        }
        if (request.uri.path ==
            _backendPath(SupportResistanceRepository.candlesEndpoint)) {
          final timestamp = now.subtract(const Duration(hours: 1));
          return _ok(<Object?>[
            <String, Object?>{
              'instId': 'ETH-USDT-SWAP',
              'ts': timestamp.millisecondsSinceEpoch.toString(),
              'o': '100',
              'h': '101',
              'l': '99',
              'c': '100',
              'confirm': '1',
            },
          ]);
        }
        throw StateError('Unexpected endpoint ${request.uri.path}');
      });
      final repository = _repository(adapter, now);

      await expectLater(
        repository.getTicker(
          marketMode: SupportResistanceMarketMode.spot,
          instrumentId: 'ETH-USDT',
        ),
        throwsA(
          isA<SupportResistanceRepositoryException>().having(
            (error) => error.failure,
            'failure',
            SupportResistanceRepositoryFailure.unavailableTicker,
          ),
        ),
      );
      await expectLater(
        repository.getCandles(
          marketMode: SupportResistanceMarketMode.spot,
          instrumentId: 'ETH-USDT',
          timeframe: SupportResistanceTimeframe.h1,
        ),
        throwsA(
          isA<SupportResistanceRepositoryException>().having(
            (error) => error.failure,
            'failure',
            SupportResistanceRepositoryFailure.invalidResponse,
          ),
        ),
      );
    },
  );

  test(
    '429 closes the injected public request lane with a typed retry state',
    () async {
      final adapter = _RecordingAdapter((_) {
        return const _WireResponse(
          <String, Object?>{'code': '50011', 'data': <Object?>[]},
          statusCode: 429,
          headers: <String, List<String>>{
            'retry-after': <String>['45'],
          },
        );
      });
      final repository = _repository(adapter, now);

      Future<void> request() => repository
          .getTicker(
            marketMode: SupportResistanceMarketMode.spot,
            instrumentId: 'ETH-USDT',
          )
          .then<void>((_) {});

      await expectLater(
        request(),
        throwsA(
          isA<SupportResistanceRepositoryException>()
              .having(
                (error) => error.failure,
                'failure',
                SupportResistanceRepositoryFailure.rateLimited,
              )
              .having((error) => error.statusCode, 'statusCode', 429)
              .having(
                (error) => error.retryAfter,
                'retryAfter',
                const Duration(seconds: 45),
              ),
        ),
      );
      await expectLater(
        request(),
        throwsA(
          isA<SupportResistanceRepositoryException>().having(
            (error) => error.failure,
            'failure',
            SupportResistanceRepositoryFailure.rateLimited,
          ),
        ),
      );
      expect(adapter.requests, hasLength(1));
    },
  );
}

SupportResistanceRepository _repository(
  _RecordingAdapter adapter,
  DateTime now,
) {
  return SupportResistanceRepository(
    BackendDataClient(
      dio: Dio()..httpClientAdapter = adapter,
      baseUrl: 'https://data.example',
    ),
    requestCoordinator: RequestCoordinator(
      clock: () => now,
      minimumSpacing: Duration.zero,
    ),
    clock: () => now,
  );
}

String _backendPath(String legacyPath) =>
    legacyPath.replaceFirst('/api/v5/', '/v1/data/');

List<SupportResistanceCandle> _levelCandles({
  required int count,
  required SupportResistanceTimeframe timeframe,
  required DateTime now,
  Map<int, double> highAt = const <int, double>{},
  Map<int, double> lowAt = const <int, double>{},
}) {
  final start = now.subtract(timeframe.duration * count);
  return List<SupportResistanceCandle>.generate(count, (index) {
    return SupportResistanceCandle(
      timestamp: start.add(timeframe.duration * index),
      open: 100,
      high: highAt[index] ?? 101,
      low: lowAt[index] ?? 99,
      close: 100,
      timeframe: timeframe,
      confirmed: true,
    );
  }, growable: false);
}

Object _rowFor(SupportResistanceCandle candle) => _row(
  candle.timestamp,
  candle.open,
  candle.high,
  candle.low,
  candle.close,
  candle.confirmed ? '1' : '0',
);

List<Object?> _row(
  DateTime timestamp,
  Object open,
  Object high,
  Object low,
  Object close,
  String confirm,
) => <Object?>[
  timestamp.millisecondsSinceEpoch.toString(),
  open.toString(),
  high.toString(),
  low.toString(),
  close.toString(),
  '1',
  '1',
  '1',
  confirm,
];

Object _instrument(
  String instrumentId,
  String type,
  String base, {
  String? quote,
  String? settle,
  String state = 'live',
}) => <String, Object?>{
  'instId': instrumentId,
  'instType': type,
  'baseCcy': base,
  'quoteCcy': quote,
  'settleCcy': settle,
  'state': state,
};

_WireResponse _ok(List<Object?> rows) =>
    _WireResponse(<String, Object?>{'code': '0', 'data': rows});

class _WireResponse {
  const _WireResponse(
    this.body, {
    this.statusCode = 200,
    this.headers = const <String, List<String>>{},
  });

  final Object? body;
  final int statusCode;
  final Map<String, List<String>> headers;
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.handler);

  final _WireResponse Function(RequestOptions request) handler;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final response = handler(options);
    return ResponseBody.fromString(
      jsonEncode(response.body),
      response.statusCode,
      headers: <String, List<String>>{
        'content-type': <String>['application/json'],
        ...response.headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
