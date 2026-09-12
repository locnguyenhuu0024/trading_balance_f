import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/portfolio/data/risk/risk_market_repository.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_models.dart';

void main() {
  final now = DateTime.utc(2026, 9, 10, 12);

  test(
    'RED-002 filters unconfirmed/gapped candles and validates intervals',
    () async {
      final adapter = _RecordingAdapter((options) {
        if (options.uri.path == RiskMarketRepository.candlesEndpoint) {
          return _ok(<List<String>>[
            <String>[
              _epoch(now.subtract(const Duration(hours: 2))),
              '100',
              '101',
              '99',
              '100',
              '10',
              '10',
              '1000',
              '1',
            ],
            <String>[
              _epoch(now.subtract(const Duration(hours: 1))),
              '100',
              '101',
              '99',
              '100',
              '10',
              '10',
              '1000',
              '0',
            ],
            <String>[
              _epoch(now),
              '100',
              '101',
              '99',
              '100.5',
              '10',
              '10',
              '1000',
              '1',
            ],
          ]);
        }
        if (options.uri.path == RiskMarketRepository.openInterestEndpoint) {
          return _ok(<Map<String, String>>[
            <String, String>{
              'instId': 'SUI-USDT-SWAP',
              'oi': '100',
              'ts': _epoch(now),
            },
          ]);
        }
        throw StateError('Unexpected endpoint ${options.uri.path}');
      });
      final repository = RiskMarketRepository(
        _publicDio(adapter),
        clock: () => now,
      );
      final series = await repository.getCandles(
        instId: 'sui-usdt',
        interval: '1h',
        limit: 10,
      );
      expect(series.candles, hasLength(2));
      expect(series.candles.every((candle) => candle.confirmed), isTrue);
      expect(
        series.candles.first.timestamp,
        now.subtract(const Duration(hours: 2)),
      );
      expect(series.candles.last.timestamp, now);
      expect(series.complete, isFalse);
      expect(series.missingReason, contains('gap'));
      expect(adapter.requests.single.method, 'GET');
      expect(adapter.requests.single.queryParameters, <String, dynamic>{
        'instId': 'SUI-USDT',
        'bar': '1H',
        'limit': 10,
      });
      expect(adapter.requests.single.queryParameters['instId'], 'SUI-USDT');
      expect(adapter.requests.single.queryParameters['bar'], '1H');
      expect(
        adapter.requests.single.queryParameters.containsKey('confirm'),
        isFalse,
      );
      expect(adapter.requests.single.extra['requiresAuth'], isFalse);
      expect(
        adapter.requests.single.headers.keys.where(
          (key) => key.toUpperCase().startsWith('OK-ACCESS-'),
        ),
        isEmpty,
      );

      final oiOnly = await repository.getOpenInterestResult(
        instId: 'SUI-USDT-SWAP',
      );
      expect(oiOnly.value, isNull);
      expect(oiOnly.quality.status, RiskQualityStatus.partial);
      expect(oiOnly.quality.reason, contains('oiCcy'));

      await expectLater(
        repository.getCandles(instId: 'SUI-USDT', interval: '1D'),
        throwsArgumentError,
      );
      expect(adapter.requests, hasLength(2));
    },
  );

  test(
    'GREEN-002 maps public spot, BTC and perpetual sources with metadata',
    () async {
      final adapter = _RecordingAdapter((options) {
        if (options.uri.path == RiskMarketRepository.candlesEndpoint) {
          final instrument = options.queryParameters['instId'] as String;
          final close = instrument == 'BTC-USDT' ? '30000' : '100';
          return _ok(<List<String>>[
            <String>[
              _epoch(now),
              close,
              close,
              close,
              close,
              '10',
              '10',
              '1000',
              '1',
            ],
          ]);
        }
        if (options.uri.path == RiskMarketRepository.fundingEndpoint) {
          expect(options.queryParameters, <String, dynamic>{
            'instId': 'SUI-USDT-SWAP',
          });
          return _ok(<Map<String, String>>[
            <String, String>{
              'instId': 'SUI-USDT-SWAP',
              'fundingRate': '0.0004',
              'fundingTime': _epoch(now.subtract(const Duration(hours: 4))),
              'nextFundingTime': _epoch(now),
            },
          ]);
        }
        if (options.uri.path == RiskMarketRepository.openInterestEndpoint) {
          expect(options.queryParameters, <String, dynamic>{
            'instId': 'SUI-USDT-SWAP',
            'instType': 'SWAP',
          });
          return _ok(<Map<String, String>>[
            <String, String>{
              'instId': 'SUI-USDT-SWAP',
              'oiCcy': '103',
              'ts': _epoch(now),
            },
          ]);
        }
        throw StateError('Unexpected endpoint ${options.uri.path}');
      });
      final repository = RiskMarketRepository(
        _publicDio(adapter),
        clock: () => now,
      );
      final snapshot = await repository.load(asset: 'SUI', now: now);

      expect(snapshot.assetInstrument, 'SUI-USDT');
      expect(snapshot.btcInstrument, 'BTC-USDT');
      expect(snapshot.derivativeInstrument, 'SUI-USDT-SWAP');
      expect(snapshot.assetOneHour.candles.single.close, 100);
      expect(snapshot.assetOneHour.candles.single.confirmed, isTrue);
      expect(snapshot.assetOneHour.source.venue, 'OKX');
      expect(snapshot.assetOneHour.source.instrument, 'SUI-USDT');
      expect(snapshot.assetOneHour.source.sourceAt, now);
      expect(snapshot.funding?.instrument, 'SUI-USDT-SWAP');
      expect(snapshot.funding?.normalized8h, closeTo(0.0008, 1e-12));
      expect(snapshot.fundingQuality?.status, RiskQualityStatus.complete);
      expect(snapshot.openInterest, hasLength(1));
      expect(snapshot.openInterestQuality?.status, RiskQualityStatus.complete);
      expect(
        snapshot.openInterest.every(
          (sample) => sample.instrument == 'SUI-USDT-SWAP',
        ),
        isTrue,
      );
      expect(snapshot.openInterest.last.oiCcy, 103);

      final candleQueries = adapter.requests
          .where(
            (request) =>
                request.uri.path == RiskMarketRepository.candlesEndpoint,
          )
          .map(
            (request) => <String, dynamic>{
              'instId': request.queryParameters['instId'],
              'bar': request.queryParameters['bar'],
              'hasConfirm': request.queryParameters.containsKey('confirm'),
            },
          )
          .toList();
      expect(
        candleQueries,
        containsAll(<Map<String, dynamic>>[
          <String, dynamic>{
            'instId': 'SUI-USDT',
            'bar': '1H',
            'hasConfirm': false,
          },
          <String, dynamic>{
            'instId': 'SUI-USDT',
            'bar': '4H',
            'hasConfirm': false,
          },
          <String, dynamic>{
            'instId': 'BTC-USDT',
            'bar': '1H',
            'hasConfirm': false,
          },
          <String, dynamic>{
            'instId': 'BTC-USDT',
            'bar': '4H',
            'hasConfirm': false,
          },
        ]),
      );
      expect(
        adapter.requests
            .where(
              (request) =>
                  request.uri.path == RiskMarketRepository.candlesEndpoint,
            )
            .every(
              (request) =>
                  request.queryParameters.keys.length == 3 &&
                  request.queryParameters.keys.toSet().containsAll(<String>{
                    'instId',
                    'bar',
                    'limit',
                  }),
            ),
        isTrue,
      );
      expect(
        adapter.requests.every((request) => request.method == 'GET'),
        isTrue,
      );
      expect(
        adapter.requests.every(
          (request) => request.extra['requiresAuth'] == false,
        ),
        isTrue,
      );
      expect(
        adapter.requests.every(
          (request) => request.headers.keys.every(
            (key) => !key.toUpperCase().startsWith('OK-ACCESS-'),
          ),
        ),
        isTrue,
      );
      expect(
        adapter.requests.where(
          (request) => request.uri.path.contains('/account/'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'RED-002 rejects duplicate or out-of-order current OI observations',
    () async {
      final adapter = _RecordingAdapter((options) {
        expect(options.queryParameters, <String, dynamic>{
          'instId': 'SUI-USDT-SWAP',
          'instType': 'SWAP',
        });
        return _ok(<Map<String, String>>[
          <String, String>{
            'instId': 'SUI-USDT-SWAP',
            'oiCcy': '103',
            'ts': _epoch(now),
          },
          <String, String>{
            'instId': 'SUI-USDT-SWAP',
            'oiCcy': '100',
            'ts': _epoch(now.subtract(const Duration(minutes: 1))),
          },
        ]);
      });
      final result = await RiskMarketRepository(
        _publicDio(adapter),
        clock: () => now,
      ).getOpenInterestResult(instId: 'SUI-USDT-SWAP');

      expect(result.value, isNull);
      expect(result.quality.status, RiskQualityStatus.partial);
      expect(result.quality.reason, contains('duplicate or out-of-order'));
    },
  );

  test(
    'RED-002 keeps funding and OI request, missing, and malformed quality distinct',
    () async {
      final requestFailure = _RecordingAdapter((options) {
        throw DioException(
          requestOptions: options,
          response: Response<dynamic>(requestOptions: options, statusCode: 429),
        );
      });
      final failedRepository = RiskMarketRepository(
        _publicDio(requestFailure),
        clock: () => now,
      );
      final failedFunding = await failedRepository.getFundingResult(
        instId: 'SUI-USDT-SWAP',
      );
      final failedOi = await failedRepository.getOpenInterestResult(
        instId: 'SUI-USDT-SWAP',
      );
      expect(failedFunding.quality.status, RiskQualityStatus.error);
      expect(failedFunding.quality.reason, contains('HTTP 429'));
      expect(failedFunding.quality.source, contains('funding-rate'));
      expect(failedOi.quality.status, RiskQualityStatus.error);
      expect(failedOi.quality.reason, contains('HTTP 429'));
      expect(failedOi.quality.source, contains('open-interest'));
      final failedSnapshot = await failedRepository.load(
        asset: 'SUI',
        now: now,
      );
      expect(failedSnapshot.fundingQuality?.status, RiskQualityStatus.error);
      expect(
        failedSnapshot.openInterestQuality?.status,
        RiskQualityStatus.error,
      );

      final missingAdapter = _RecordingAdapter((options) {
        if (options.uri.path == RiskMarketRepository.fundingEndpoint) {
          return _ok(<Map<String, String>>[
            <String, String>{
              'instId': 'BTC-USDT-SWAP',
              'fundingRate': '0.0001',
              'fundingTime': _epoch(now.subtract(const Duration(hours: 4))),
              'nextFundingTime': _epoch(now),
            },
          ]);
        }
        return _ok(<Map<String, String>>[
          <String, String>{
            'instId': 'BTC-USDT-SWAP',
            'oiCcy': '100',
            'ts': _epoch(now),
          },
        ]);
      });
      final missingRepository = RiskMarketRepository(
        _publicDio(missingAdapter),
        clock: () => now,
      );
      final missingFunding = await missingRepository.getFundingResult(
        instId: 'SUI-USDT-SWAP',
      );
      final missingOi = await missingRepository.getOpenInterestResult(
        instId: 'SUI-USDT-SWAP',
      );
      expect(missingFunding.quality.status, RiskQualityStatus.empty);
      expect(missingFunding.quality.reason, contains('No matching'));
      expect(missingOi.quality.status, RiskQualityStatus.empty);
      expect(missingOi.quality.reason, contains('No matching'));

      final malformedAdapter = _RecordingAdapter((options) {
        if (options.uri.path == RiskMarketRepository.fundingEndpoint) {
          return _ok(<Map<String, String>>[
            <String, String>{
              'instId': 'SUI-USDT-SWAP',
              'fundingRate': 'not-a-number',
              'fundingTime': _epoch(now.subtract(const Duration(hours: 4))),
              'nextFundingTime': _epoch(now),
            },
          ]);
        }
        return _ok(<Map<String, String>>[
          <String, String>{
            'instId': 'SUI-USDT-SWAP',
            'oiCcy': 'not-a-number',
            'ts': _epoch(now),
          },
        ]);
      });
      final malformedRepository = RiskMarketRepository(
        _publicDio(malformedAdapter),
        clock: () => now,
      );
      final malformedFunding = await malformedRepository.getFundingResult(
        instId: 'SUI-USDT-SWAP',
      );
      final malformedOi = await malformedRepository.getOpenInterestResult(
        instId: 'SUI-USDT-SWAP',
      );
      expect(malformedFunding.quality.status, RiskQualityStatus.partial);
      expect(malformedFunding.quality.reason, contains('incomplete'));
      expect(malformedOi.quality.status, RiskQualityStatus.partial);
      expect(malformedOi.quality.reason, contains('oiCcy'));
    },
  );
}

String _epoch(DateTime value) => value.millisecondsSinceEpoch.toString();

Dio _publicDio(_RecordingAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://unit.test'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.extra['requiresAuth'] == true) {
          options.headers['OK-ACCESS-KEY'] = 'synthetic';
        }
        handler.next(options);
      },
    ),
  );
  dio.httpClientAdapter = adapter;
  return dio;
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.handler);

  final Object Function(RequestOptions options) handler;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(handler(options)),
      200,
      headers: <String, List<String>>{
        'content-type': <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _ok(Object data) => <String, dynamic>{
  'code': '0',
  'msg': '',
  'data': data,
};
