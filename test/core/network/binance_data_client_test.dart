import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/exchange/binance_read_routes.dart';
import 'package:trading_balance_f/core/network/binance_data_client.dart';
import 'package:trading_balance_f/core/network/binance_request_coordinator.dart';
import 'package:trading_balance_f/core/network/binance_spot_ws_transport.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/features/settings/domain/binance_credential_bundle.dart';

void main() {
  group('RED-116', () {
    test(
      'missing or malformed keys reject before any private adapter send',
      () async {
        for (final encoded in <String?>[
          null,
          '{"version":1,"apiKey":"fixture-key"}',
        ]) {
          final adapter = _RecordingAdapter(
            (_) => _WireResponse(200, <String, Object>{}),
          );
          final storage = _FixtureStorage(encodedBundle: encoded);
          final client = _client(adapter, storage: storage);

          await expectLater(
            client.get('/api/v3/account'),
            throwsA(isA<BinanceDataException>()),
          );

          expect(adapter.requests, isEmpty);
          expect(storage.readCount, 1);
          client.dispose();
          storage.dispose();
        }
      },
    );

    test(
      'rejects foreign routes, methods, and query fields before sending',
      () async {
        final adapter = _RecordingAdapter(
          (_) => _WireResponse(200, <String, Object>{}),
        );
        final storage = _FixtureStorage.withCredentials();
        final client = _client(adapter, storage: storage);

        await expectLater(
          client.get('/api/v3/order'),
          throwsA(
            isA<BinanceDataException>().having(
              (error) => error.code,
              'code',
              'binance_route_not_allowed',
            ),
          ),
        );
        await expectLater(
          client.get(
            '/api/v3/allOrders',
            queryParameters: const <String, Object>{
              'symbol': 'BTCUSDT',
              'startTime': 123,
            },
          ),
          throwsA(isA<BinanceDataException>()),
        );
        await expectLater(
          client.get(
            '/api/v3/ticker/24hr',
            queryParameters: <String, Object>{
              'symbols': List<String>.generate(21, (index) => 'PAIR$index'),
            },
          ),
          throwsA(isA<BinanceDataException>()),
        );

        expect(adapter.requests, isEmpty);
        client.dispose();
        storage.dispose();
      },
    );

    test(
      'rejects OKX and simulated-trading headers in defaults and late interceptors',
      () async {
        for (final header in <String>[
          'OK-ACCESS-KEY',
          'ok-access-sign',
          'X-SIMULATED-TRADING',
        ]) {
          for (final useDefaultHeader in <bool>[true, false]) {
            for (final publicRoute in <bool>[true, false]) {
              final clock = _MutableClock(DateTime.utc(2026, 10, 25, 8));
              final adapter = _RecordingAdapter((options) {
                if (options.uri.path.endsWith('/time')) {
                  return _WireResponse(200, <String, Object>{
                    'serverTime': clock.now.millisecondsSinceEpoch,
                  });
                }
                return _WireResponse(200, <String, Object>{});
              });
              final dio = Dio()..httpClientAdapter = adapter;
              if (useDefaultHeader) {
                dio.options.headers[header] = 'fixture-forbidden-header';
              } else {
                dio.interceptors.add(
                  InterceptorsWrapper(
                    onRequest: (options, handler) {
                      final targetPath = publicRoute
                          ? '/api/v3/ticker/24hr'
                          : '/api/v3/account';
                      if (options.uri.path == targetPath) {
                        options.headers[header] = 'fixture-forbidden-header';
                      }
                      handler.next(options);
                    },
                  ),
                );
              }
              final storage = _FixtureStorage.withCredentials();
              final client = BinanceDataClient(
                secureStorage: storage,
                requestCoordinator: _coordinator(clock),
                dio: dio,
                clock: () => clock.now,
              );
              final targetPath = publicRoute
                  ? '/api/v3/ticker/24hr'
                  : '/api/v3/account';

              await expectLater(
                client.get(
                  targetPath,
                  queryParameters: publicRoute
                      ? const <String, String>{'symbol': 'BTCUSDT'}
                      : null,
                ),
                throwsA(
                  isA<BinanceDataException>().having(
                    (error) => error.code,
                    'code',
                    'binance_request_forbidden',
                  ),
                ),
              );
              expect(
                adapter.requests.where(
                  (request) => request.uri.path == targetPath,
                ),
                isEmpty,
              );
              if (useDefaultHeader) expect(adapter.requests, isEmpty);
              client.dispose();
              storage.dispose();
            }
          }
        }
      },
    );

    test(
      'adapter rejects origin, method, query, and foreign API-key mutation',
      () async {
        final mutations = <void Function(RequestOptions)>[
          (options) => options.path = 'https://attacker.example/api/v3/account',
          (options) => options.method = 'POST',
          (options) => options.path = '${options.path}&newParameter=1',
          (options) =>
              options.headers['X-MBX-APIKEY'] = 'fixture-attacker-binance-key',
        ];

        for (final mutate in mutations) {
          final clock = _MutableClock(DateTime.utc(2026, 10, 25, 8));
          final coordinator = _coordinator(clock);
          final adapter = _RecordingAdapter((options) {
            if (options.uri.path == '/api/v3/time') {
              return _WireResponse(200, <String, Object>{
                'serverTime': clock.now.millisecondsSinceEpoch,
              });
            }
            return _WireResponse(200, <String, Object>{});
          });
          final dio = Dio()..httpClientAdapter = adapter;
          dio.interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                if (options.uri.path == '/api/v3/account') mutate(options);
                handler.next(options);
              },
            ),
          );
          final storage = _FixtureStorage.withCredentials();
          final client = BinanceDataClient(
            secureStorage: storage,
            requestCoordinator: coordinator,
            dio: dio,
            clock: () => clock.now,
          );

          await expectLater(
            client.get('/api/v3/account'),
            throwsA(isA<BinanceDataException>()),
          );
          expect(
            adapter.requests.where(
              (request) => request.uri.path == '/api/v3/account',
            ),
            isEmpty,
          );
          client.dispose();
          storage.dispose();
        }
      },
    );

    test(
      'rotating keys while queued prevents the stale private adapter send',
      () async {
        final clock = _MutableClock(DateTime.utc(2026, 10, 25, 8));
        final delayStarted = Completer<void>();
        final releaseDelay = Completer<void>();
        final coordinator = BinanceRequestCoordinator(
          clock: () => clock.now,
          minimumSpacing: const Duration(seconds: 1),
          delay: (_) {
            if (!delayStarted.isCompleted) delayStarted.complete();
            return releaseDelay.future;
          },
        );
        _installBudget(coordinator, BinanceHost.spot);
        final adapter = _RecordingAdapter((options) {
          if (options.uri.path == '/api/v3/time') {
            return _WireResponse(200, <String, Object>{
              'serverTime': clock.now.millisecondsSinceEpoch,
            });
          }
          return _WireResponse(200, <String, Object>{});
        });
        final storage = _FixtureStorage.withCredentials();
        final client = BinanceDataClient(
          secureStorage: storage,
          requestCoordinator: coordinator,
          dio: Dio()..httpClientAdapter = adapter,
          clock: () => clock.now,
        );

        final request = client.get('/api/v3/account');
        await delayStarted.future;
        await storage.rotate();
        releaseDelay.complete();

        await expectLater(
          request,
          throwsA(
            isA<BinanceDataException>().having(
              (error) => error.code,
              'code',
              'credentials_changed',
            ),
          ),
        );
        expect(
          adapter.requests.where(
            (value) => value.uri.path == '/api/v3/account',
          ),
          isEmpty,
        );
        client.dispose();
        storage.dispose();
      },
    );

    test(
      'rotation while storage load is pending prevents the private send',
      () async {
        final readStarted = Completer<void>();
        final releaseRead = Completer<void>();
        final storage = _FixtureStorage.withCredentials()
          ..readStarted = readStarted
          ..readGate = releaseRead.future;
        final adapter = _RecordingAdapter(
          (_) => _WireResponse(200, <String, Object>{}),
        );
        final client = _client(adapter, storage: storage);

        final request = client.get('/api/v3/account');
        await readStarted.future;
        await storage.rotate();
        releaseRead.complete();

        await expectLater(
          request,
          throwsA(
            isA<BinanceDataException>().having(
              (error) => error.code,
              'code',
              'credentials_changed',
            ),
          ),
        );
        expect(adapter.requests, isEmpty);
        client.dispose();
        storage.dispose();
      },
    );

    test('rotating keys during transport rejects the stale response', () async {
      final clock = _MutableClock(DateTime.utc(2026, 10, 25, 8));
      final accountStarted = Completer<void>();
      final releaseAccount = Completer<_WireResponse>();
      final adapter = _RecordingAdapter((options) async {
        if (options.uri.path == '/api/v3/time') {
          return _WireResponse(200, <String, Object>{
            'serverTime': clock.now.millisecondsSinceEpoch,
          });
        }
        accountStarted.complete();
        return releaseAccount.future;
      });
      final coordinator = _coordinator(clock);
      final storage = _FixtureStorage.withCredentials();
      final client = _client(
        adapter,
        storage: storage,
        coordinator: coordinator,
        clock: clock,
      );

      final request = client.get('/api/v3/account');
      await accountStarted.future;
      await storage.rotate();
      releaseAccount.complete(
        _WireResponse(200, <String, Object>{'balances': []}),
      );

      await expectLater(
        request,
        throwsA(
          isA<BinanceDataException>().having(
            (error) => error.code,
            'code',
            'credentials_changed',
          ),
        ),
      );
      client.dispose();
      storage.dispose();
    });

    test('timestamp rejection resynchronizes once and retries once', () async {
      final clock = _MutableClock(DateTime.utc(2026, 10, 25, 8));
      var timeReads = 0;
      var accountReads = 0;
      final adapter = _RecordingAdapter((options) {
        if (options.uri.path == '/api/v3/time') {
          timeReads++;
          return _WireResponse(200, <String, Object>{
            'serverTime': clock.now.millisecondsSinceEpoch + timeReads * 5000,
          });
        }
        accountReads++;
        if (accountReads == 1) {
          return _WireResponse(400, <String, Object>{'code': -1021});
        }
        return _WireResponse(200, <String, Object>{'balances': []});
      });
      final storage = _FixtureStorage.withCredentials();
      final client = _client(
        adapter,
        storage: storage,
        coordinator: _coordinator(clock),
        clock: clock,
      );

      final response = await client.get('/api/v3/account');

      expect(response.statusCode, 200);
      expect(timeReads, 2);
      expect(accountReads, 2);
      final timestamps = adapter.requests
          .where((request) => request.uri.path == '/api/v3/account')
          .map((request) => request.uri.queryParameters['timestamp'])
          .toList();
      expect(timestamps, hasLength(2));
      expect(timestamps.first, isNot(timestamps.last));
      client.dispose();
      storage.dispose();
    });

    test(
      'timestamp and retry signatures are created after each long queue delay',
      () async {
        final clock = _MutableClock(DateTime.utc(2026, 10, 25, 8));
        final timeDispatches = <int>[];
        final accountDispatches = <int>[];
        final delayDurations = <Duration>[];
        final coordinator = BinanceRequestCoordinator(
          clock: () => clock.now,
          minimumSpacing: const Duration(seconds: 6),
          delay: (duration) async {
            delayDurations.add(duration);
            clock.advance(duration);
          },
        );
        _installBudget(coordinator, BinanceHost.spot);
        var accountReads = 0;
        final adapter = _RecordingAdapter((options) {
          if (options.uri.path == '/api/v3/time') {
            timeDispatches.add(clock.now.millisecondsSinceEpoch);
            return _WireResponse(200, <String, Object>{
              'serverTime': clock.now.millisecondsSinceEpoch + 100,
            });
          }
          accountDispatches.add(clock.now.millisecondsSinceEpoch);
          accountReads++;
          if (accountReads == 1) {
            return _WireResponse(400, <String, Object>{'code': -1021});
          }
          return _WireResponse(200, <String, Object>{'balances': []});
        });
        final storage = _FixtureStorage.withCredentials();
        final client = _client(
          adapter,
          storage: storage,
          coordinator: coordinator,
          clock: clock,
        );

        final response = await client.get('/api/v3/account');

        final accountRequests = adapter.requests
            .where((request) => request.uri.path == '/api/v3/account')
            .toList(growable: false);
        expect(response.statusCode, 200);
        expect(accountRequests, hasLength(2));
        expect(timeDispatches, hasLength(2));
        expect(accountDispatches, hasLength(2));
        expect(
          accountDispatches[0] - timeDispatches[0],
          greaterThanOrEqualTo(6000),
        );
        expect(
          accountDispatches[1] - timeDispatches[1],
          greaterThanOrEqualTo(6000),
        );
        for (var index = 0; index < accountRequests.length; index++) {
          final request = accountRequests[index];
          final timestamp = request.uri.queryParameters['timestamp']!;
          expect(timestamp, '${accountDispatches[index] + 100}');
          final unsigned = Uri.https(
            'api.binance.com',
            '/api/v3/account',
            <String, String>{'recvWindow': '5000', 'timestamp': timestamp},
          );
          final signature = Hmac(
            sha256,
            utf8.encode('fixture-binance-secret'),
          ).convert(utf8.encode(unsigned.query)).toString();
          expect(request.uri.queryParameters['signature'], signature);
        }
        expect(delayDurations, everyElement(const Duration(seconds: 6)));
        client.dispose();
        storage.dispose();
      },
    );

    test(
      'repeated timestamp rejection gets exactly one private retry',
      () async {
        final clock = _MutableClock(DateTime.utc(2026, 10, 25, 8));
        var timeReads = 0;
        var accountReads = 0;
        final adapter = _RecordingAdapter((options) {
          if (options.uri.path == '/api/v3/time') {
            timeReads++;
            return _WireResponse(200, <String, Object>{
              'serverTime': clock.now.millisecondsSinceEpoch,
            });
          }
          accountReads++;
          return _WireResponse(400, <String, Object>{'code': -1021});
        });
        final storage = _FixtureStorage.withCredentials();
        final client = _client(
          adapter,
          storage: storage,
          coordinator: _coordinator(clock),
          clock: clock,
        );

        await expectLater(
          client.get('/api/v3/account'),
          throwsA(
            isA<BinanceDataException>().having(
              (error) => error.code,
              'code',
              'binance_timestamp_invalid',
            ),
          ),
        );

        expect(timeReads, 2);
        expect(accountReads, 2);
        client.dispose();
        storage.dispose();
      },
    );

    test('authentication failure is sanitized without a retry', () async {
      final clock = _MutableClock(DateTime.utc(2026, 10, 25, 8));
      var timeReads = 0;
      var accountReads = 0;
      final adapter = _RecordingAdapter((options) {
        if (options.uri.path == '/api/v3/time') {
          timeReads++;
          return _WireResponse(200, <String, Object>{
            'serverTime': clock.now.millisecondsSinceEpoch,
          });
        }
        accountReads++;
        return _WireResponse(401, <String, Object>{
          'code': -2015,
          'msg': 'fixture-api-key fixture-private-body',
        });
      });
      final storage = _FixtureStorage.withCredentials();
      final client = _client(
        adapter,
        storage: storage,
        coordinator: _coordinator(clock),
        clock: clock,
      );

      await expectLater(
        client.get('/api/v3/account'),
        throwsA(
          isA<BinanceDataException>()
              .having(
                (error) => error.code,
                'code',
                'binance_authentication_failed',
              )
              .having(
                (error) => error.toString(),
                'message',
                isNot(contains('fixture-api-key')),
              )
              .having(
                (error) => error.toString(),
                'message',
                isNot(contains('fixture-private-body')),
              ),
        ),
      );
      expect(timeReads, 1);
      expect(accountReads, 1);
      client.dispose();
      storage.dispose();
    });

    test('cancellation while queued stops before adapter dispatch', () async {
      final clock = _MutableClock(DateTime.utc(2026, 10, 25, 8));
      final timeStarted = Completer<void>();
      final releaseDelay = Completer<void>();
      var holdNextDelay = false;
      final coordinator = BinanceRequestCoordinator(
        clock: () => clock.now,
        minimumSpacing: const Duration(seconds: 6),
        delay: (duration) async {
          if (holdNextDelay) {
            holdNextDelay = false;
            timeStarted.complete();
            await releaseDelay.future;
          }
          clock.advance(duration);
        },
      );
      _installBudget(coordinator, BinanceHost.spot);
      final adapter = _RecordingAdapter(
        (options) => _WireResponse(200, <String, Object>{
          'serverTime': clock.now.millisecondsSinceEpoch,
        }),
      );
      final storage = _FixtureStorage.withCredentials();
      final client = _client(
        adapter,
        storage: storage,
        coordinator: coordinator,
        clock: clock,
      );
      await client.get('/api/v3/time');
      await coordinator.run<void>(
        host: BinanceHost.spot,
        weight: 1,
        priority: BinanceRequestPriority.interactive,
        request: () async {},
      );
      holdNextDelay = true;
      final cancelToken = CancelToken();
      final request = client.get('/api/v3/account', cancelToken: cancelToken);
      await timeStarted.future;
      cancelToken.cancel('fixture cancellation');
      releaseDelay.complete();

      await expectLater(
        request,
        throwsA(
          isA<BinanceDataException>().having(
            (error) => error.code,
            'code',
            'request_cancelled',
          ),
        ),
      );
      expect(
        adapter.requests.where(
          (request) => request.uri.path == '/api/v3/account',
        ),
        isEmpty,
      );
      client.dispose();
      storage.dispose();
    });

    test(
      'Dio transport failures are sanitized before coordinator completion',
      () async {
        final clock = _MutableClock(DateTime.utc(2026, 10, 25, 8));
        final coordinator = _CapturingCoordinator(
          clock: () => clock.now,
          minimumSpacing: Duration.zero,
          delay: (_) async {},
        );
        _installBudget(coordinator, BinanceHost.spot);
        final adapter = _RecordingAdapter((options) {
          if (options.uri.path == '/api/v3/time') {
            return _WireResponse(200, <String, Object>{
              'serverTime': clock.now.millisecondsSinceEpoch,
            });
          }
          throw DioException(
            requestOptions: options,
            message:
                'fixture-api-key fixture-private-header fixture-signed-url',
            response: Response<dynamic>(
              requestOptions: options,
              statusCode: 500,
              data: <String, Object>{'msg': 'fixture-private-body'},
              headers: Headers.fromMap(<String, List<String>>{
                'x-private-header': <String>['fixture-private-header'],
              }),
            ),
          );
        });
        final storage = _FixtureStorage.withCredentials();
        final client = _client(
          adapter,
          storage: storage,
          coordinator: coordinator,
          clock: clock,
        );

        await expectLater(
          client.get('/api/v3/account'),
          throwsA(isA<BinanceDataException>()),
        );
        expect(coordinator.completedErrors, hasLength(1));
        expect(coordinator.completedErrors.single, isA<BinanceDataException>());
        expect(coordinator.completedErrors.single, isNot(isA<DioException>()));
        final completionText = coordinator.completedErrors.single.toString();
        for (final secret in <String>[
          'fixture-api-key',
          'fixture-private-header',
          'fixture-signed-url',
          'signature=',
          'fixture-private-body',
        ]) {
          expect(completionText, isNot(contains(secret)));
        }
        client.dispose();
        storage.dispose();
      },
    );

    test(
      'caller supplied Dio errors cannot impersonate safe transport failures',
      () async {
        final clock = _MutableClock(DateTime.utc(2026, 10, 25, 8));
        final coordinator = _CapturingCoordinator(
          clock: () => clock.now,
          minimumSpacing: Duration.zero,
          delay: (_) async {},
        );
        _installBudget(coordinator, BinanceHost.spot);
        final adapter = _RecordingAdapter((options) {
          if (options.uri.path == '/api/v3/time') {
            return _WireResponse(200, <String, Object>{
              'serverTime': clock.now.millisecondsSinceEpoch,
            });
          }
          return _WireResponse(200, <String, Object>{});
        });
        final dio = Dio()..httpClientAdapter = adapter;
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              if (options.uri.path == '/api/v3/account') {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    message: 'fixture-api-key fixture-signed-url',
                    error: const BinanceDataException(
                      code: 'binance_request_forbidden',
                      message: 'fixture-private-body fixture-private-header',
                      statusCode: 418,
                      retryAfter: 'fixture-secret',
                    ),
                  ),
                );
                return;
              }
              handler.next(options);
            },
          ),
        );
        final storage = _FixtureStorage.withCredentials();
        final client = BinanceDataClient(
          secureStorage: storage,
          requestCoordinator: coordinator,
          dio: dio,
          clock: () => clock.now,
        );

        await expectLater(
          client.get('/api/v3/account'),
          throwsA(
            isA<BinanceDataException>().having(
              (error) => error.code,
              'code',
              'binance_network_error',
            ),
          ),
        );
        expect(coordinator.completedErrors, hasLength(1));
        expect(coordinator.completedErrors.single, isA<BinanceDataException>());
        expect(coordinator.completedErrors.single, isNot(isA<DioException>()));
        final completionText = coordinator.completedErrors.single.toString();
        for (final secret in <String>[
          'fixture-api-key',
          'fixture-signed-url',
          'signature=',
          'fixture-private-body',
          'fixture-private-header',
          'fixture-secret',
        ]) {
          expect(completionText, isNot(contains(secret)));
        }
        expect(
          adapter.requests.where(
            (request) => request.uri.path == '/api/v3/account',
          ),
          isEmpty,
        );
        client.dispose();
        storage.dispose();
      },
    );

    test(
      '429 and 418 pause all requests for the affected host until deadline',
      () async {
        for (final statusCode in <int>[429, 418]) {
          final clock = _MutableClock(DateTime.utc(2026, 10, 25, 8));
          var tickerReads = 0;
          final adapter = _RecordingAdapter((options) {
            if (options.uri.path == '/api/v3/time') {
              return _WireResponse(200, <String, Object>{
                'serverTime': clock.now.millisecondsSinceEpoch,
              });
            }
            tickerReads++;
            if (tickerReads == 1) {
              return _WireResponse(
                statusCode,
                <String, Object>{},
                headers: const <String, List<String>>{
                  'retry-after': <String>['5'],
                },
              );
            }
            return _WireResponse(200, <String, Object>{'symbol': 'BTCUSDT'});
          });
          final coordinator = _coordinator(clock);
          final client = _client(
            adapter,
            coordinator: coordinator,
            clock: clock,
          );

          await expectLater(
            client.get(
              '/api/v3/ticker/24hr',
              queryParameters: const {'symbol': 'BTCUSDT'},
            ),
            throwsA(isA<BinanceDataException>()),
          );
          expect(coordinator.stateFor(BinanceHost.spot).isPaused, isTrue);
          expect(coordinator.stateFor(BinanceHost.futures).isPaused, isFalse);
          final sendsBeforePause = adapter.requests.length;
          await expectLater(
            client.get('/api/v3/time'),
            throwsA(
              isA<BinanceDataException>().having(
                (error) => error.code,
                'code',
                'binance_host_paused',
              ),
            ),
          );
          expect(adapter.requests, hasLength(sendsBeforePause));

          clock.advance(const Duration(seconds: 6));
          final resumed = await client.get(
            '/api/v3/ticker/24hr',
            queryParameters: const {'symbol': 'BTCUSDT'},
          );
          expect(resumed.statusCode, 200);
          expect(tickerReads, 2);
          client.dispose();
        }
      },
    );

    test('history pauses when rate-limit metadata is missing', () async {
      final clock = _MutableClock(DateTime.utc(2026, 10, 25, 8));
      final adapter = _RecordingAdapter((options) {
        if (options.uri.path == '/api/v3/time') {
          return _WireResponse(200, <String, Object>{
            'serverTime': clock.now.millisecondsSinceEpoch,
          });
        }
        return _WireResponse(200, <String, Object>{'orders': []});
      });
      final storage = _FixtureStorage.withCredentials();
      final coordinator = BinanceRequestCoordinator(
        clock: () => clock.now,
        minimumSpacing: Duration.zero,
        delay: (_) async {},
      );
      final client = _client(
        adapter,
        storage: storage,
        coordinator: coordinator,
        clock: clock,
      );

      await expectLater(
        client.get(
          '/api/v3/allOrders',
          queryParameters: const {'symbol': 'BTCUSDT', 'limit': 500},
          priority: BinanceRequestPriority.history,
        ),
        throwsA(
          isA<BinanceDataException>().having(
            (error) => error.code,
            'code',
            'binance_budget_metadata_unavailable',
          ),
        ),
      );
      expect(
        adapter.requests.where(
          (request) => request.uri.path == '/api/v3/allOrders',
        ),
        isEmpty,
      );
      client.dispose();
      storage.dispose();
    });

    test(
      'history stays under the 60 percent budget and all owned work under 80 percent',
      () async {
        final clock = _MutableClock(DateTime.utc(2026, 10, 25, 8));
        final coordinator = BinanceRequestCoordinator(
          clock: () => clock.now,
          minimumSpacing: Duration.zero,
          delay: (_) async {},
        );
        coordinator.installLimits(BinanceHost.spot, const [
          BinanceRateLimitWindow(
            rateLimitType: 'REQUEST_WEIGHT',
            interval: 'MINUTE',
            intervalNum: 1,
            limit: 100,
          ),
        ]);
        for (var index = 0; index < 60; index++) {
          await coordinator.run<void>(
            host: BinanceHost.spot,
            weight: 1,
            priority: BinanceRequestPriority.history,
            request: () async {},
          );
        }
        await expectLater(
          coordinator.run<void>(
            host: BinanceHost.spot,
            weight: 1,
            priority: BinanceRequestPriority.history,
            request: () async {},
          ),
          throwsA(isA<BinanceRequestPausedException>()),
        );
        for (var index = 0; index < 20; index++) {
          await coordinator.run<void>(
            host: BinanceHost.spot,
            weight: 1,
            priority: BinanceRequestPriority.interactive,
            request: () async {},
          );
        }
        await expectLater(
          coordinator.run<void>(
            host: BinanceHost.spot,
            weight: 1,
            priority: BinanceRequestPriority.interactive,
            request: () async {},
          ),
          throwsA(isA<BinanceRequestPausedException>()),
        );
      },
    );

    test('raw request costs enforce the owner and history ceilings', () async {
      final clock = _MutableClock(DateTime.utc(2026, 10, 25, 8));
      final coordinator = BinanceRequestCoordinator(
        clock: () => clock.now,
        minimumSpacing: Duration.zero,
        delay: (_) async {},
      );
      coordinator.installLimits(BinanceHost.spot, const [
        BinanceRateLimitWindow(
          rateLimitType: 'REQUEST_WEIGHT',
          interval: 'MINUTE',
          intervalNum: 1,
          limit: 1000,
        ),
        BinanceRateLimitWindow(
          rateLimitType: 'RAW_REQUEST',
          interval: 'MINUTE',
          intervalNum: 1,
          limit: 100,
        ),
      ]);
      var requests = 0;

      await expectLater(
        coordinator.run<void>(
          host: BinanceHost.spot,
          weight: 1,
          rawRequests: 61,
          priority: BinanceRequestPriority.history,
          request: () async => requests++,
        ),
        throwsA(isA<BinanceRequestPausedException>()),
      );
      expect(requests, 0);

      await coordinator.run<void>(
        host: BinanceHost.spot,
        weight: 1,
        rawRequests: 60,
        priority: BinanceRequestPriority.history,
        request: () async => requests++,
      );
      await expectLater(
        coordinator.run<void>(
          host: BinanceHost.spot,
          weight: 1,
          rawRequests: 1,
          priority: BinanceRequestPriority.history,
          request: () async => requests++,
        ),
        throwsA(isA<BinanceRequestPausedException>()),
      );
      await coordinator.run<void>(
        host: BinanceHost.spot,
        weight: 1,
        rawRequests: 20,
        priority: BinanceRequestPriority.interactive,
        request: () async => requests++,
      );
      await expectLater(
        coordinator.run<void>(
          host: BinanceHost.spot,
          weight: 1,
          rawRequests: 1,
          priority: BinanceRequestPriority.interactive,
          request: () async => requests++,
        ),
        throwsA(isA<BinanceRequestPausedException>()),
      );
      expect(requests, 2);
    });

    test(
      'used-weight headers and exchangeInfo windows update the host budget',
      () async {
        final clock = _MutableClock(DateTime.utc(2026, 10, 25, 8));
        final coordinator = BinanceRequestCoordinator(
          clock: () => clock.now,
          minimumSpacing: Duration.zero,
          delay: (_) async {},
        );
        expect(
          coordinator.updateFromExchangeInfo(BinanceHost.spot, <String, Object>{
            'rateLimits': <Object>[
              <String, Object>{
                'rateLimitType': 'REQUEST_WEIGHT',
                'interval': 'MINUTE',
                'intervalNum': 1,
                'limit': 100,
              },
              <String, Object>{
                'rateLimitType': 'RAW_REQUEST',
                'interval': 'SECOND',
                'intervalNum': 10,
                'limit': 50,
              },
            ],
          }),
          isTrue,
        );
        coordinator.observeResponse(
          BinanceHost.spot,
          statusCode: 200,
          headers: const <String, List<String>>{
            'X-MBX-USED-WEIGHT-1m': <String>['79'],
          },
        );
        await coordinator.run<void>(
          host: BinanceHost.spot,
          weight: 1,
          priority: BinanceRequestPriority.interactive,
          request: () async {},
        );
        await expectLater(
          coordinator.run<void>(
            host: BinanceHost.spot,
            weight: 1,
            priority: BinanceRequestPriority.interactive,
            request: () async {},
          ),
          throwsA(isA<BinanceRequestPausedException>()),
        );
        expect(
          coordinator.updateFromExchangeInfo(
            BinanceHost.futures,
            <String, Object>{
              'rateLimits': <Object>[
                <String, Object>{
                  'rateLimitType': 'RAW_REQUEST',
                  'interval': 'SECOND',
                  'intervalNum': 10,
                  'limit': 50,
                },
              ],
            },
          ),
          isFalse,
        );
        expect(
          coordinator.stateFor(BinanceHost.futures).hasValidBudget,
          isFalse,
        );
      },
    );

    test(
      'credential and transport failures never expose stored values',
      () async {
        final clock = _MutableClock(DateTime.utc(2026, 10, 25, 8));
        final adapter = _RecordingAdapter((options) {
          if (options.uri.path == '/api/v3/time') {
            return _WireResponse(200, <String, Object>{
              'serverTime': clock.now.millisecondsSinceEpoch,
            });
          }
          throw DioException(
            requestOptions: options,
            message: 'fixture-api-key fixture-secret',
          );
        });
        final storage = _FixtureStorage.withCredentials();
        final client = _client(
          adapter,
          storage: storage,
          coordinator: _coordinator(clock),
          clock: clock,
        );

        await expectLater(
          client.get('/api/v3/account'),
          throwsA(
            isA<BinanceDataException>()
                .having((error) => error.code, 'code', 'binance_network_error')
                .having(
                  (error) => error.toString(),
                  'message',
                  isNot(contains('fixture-api-key')),
                )
                .having(
                  (error) => error.toString(),
                  'message',
                  isNot(contains('fixture-secret')),
                ),
          ),
        );
        client.dispose();
        storage.dispose();
      },
    );
  });

  group('GREEN-116', () {
    test('classifies Dio timeouts on public and signed routes safely', () async {
      for (final type in <DioExceptionType>[
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        for (final signed in <bool>[false, true]) {
          final clock = _MutableClock(DateTime.utc(2026, 10, 25, 8));
          final adapter = _RecordingAdapter((options) {
            if (options.uri.path == '/api/v3/time') {
              return _WireResponse(200, <String, Object>{
                'serverTime': clock.now.millisecondsSinceEpoch,
              });
            }
            throw DioException(
              requestOptions: options,
              type: type,
              message:
                  'fixture-api-key fixture-signature ${options.uri.toString()}',
            );
          });
          final storage = signed ? _FixtureStorage.withCredentials() : null;
          final client = _client(
            adapter,
            storage: storage,
            coordinator: _coordinator(clock),
            clock: clock,
          );
          final route = signed ? '/api/v3/account' : '/api/v3/ticker/24hr';

          await expectLater(
            client.get(
              route,
              queryParameters: signed ? null : const {'symbol': 'BTCUSDT'},
            ),
            throwsA(
              isA<BinanceDataException>()
                  .having((error) => error.code, 'code', 'binance_timeout')
                  .having(
                    (error) => error.message,
                    'safe message',
                    allOf(
                      isNot(contains('fixture-binance-api-key')),
                      isNot(contains('fixture-signature')),
                      isNot(contains('symbol=BTCUSDT')),
                      isNot(contains('https://')),
                    ),
                  )
                  .having(
                    (error) => error.toString(),
                    'safe string',
                    allOf(
                      isNot(contains('fixture-binance-api-key')),
                      isNot(contains('fixture-signature')),
                      isNot(contains('symbol=BTCUSDT')),
                      isNot(contains('https://')),
                    ),
                  ),
            ),
          );
          client.dispose();
          storage?.dispose();
        }
      }
    });

    test('response-less connection errors remain network errors', () async {
      final adapter = _RecordingAdapter((options) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      });
      final client = _client(adapter);

      await expectLater(
        client.get(
          '/api/v3/ticker/24hr',
          queryParameters: const {'symbol': 'BTCUSDT'},
        ),
        throwsA(
          isA<BinanceDataException>().having(
            (error) => error.code,
            'code',
            'binance_network_error',
          ),
        ),
      );
      client.dispose();
    });

    test(
      'exchangeInfo installs budgets and charges serialized bootstrap calls',
      () async {
        final clock = _MutableClock(DateTime.utc(2026, 10, 25, 8));
        final coordinator = BinanceRequestCoordinator(
          clock: () => clock.now,
          minimumSpacing: Duration.zero,
          delay: (_) async {},
        );
        final adapter = _RecordingAdapter((options) {
          if (options.uri.path == '/api/v3/time') {
            return _WireResponse(200, <String, Object>{
              'serverTime': clock.now.millisecondsSinceEpoch,
            });
          }
          if (options.uri.path == '/api/v3/exchangeInfo') {
            return _WireResponse(200, <String, Object>{
              'rateLimits': <Object>[
                <String, Object>{
                  'rateLimitType': 'REQUEST_WEIGHT',
                  'interval': 'MINUTE',
                  'intervalNum': 1,
                  'limit': 25,
                },
              ],
            });
          }
          return _WireResponse(200, <String, Object>{'symbol': 'BTCUSDT'});
        });
        final client = _client(adapter, coordinator: coordinator, clock: clock);

        await client.get('/api/v3/time');
        await client.get('/api/v3/exchangeInfo');
        expect(coordinator.stateFor(BinanceHost.spot).hasValidBudget, isTrue);
        await expectLater(
          client.get(
            '/api/v3/ticker/24hr',
            queryParameters: const {'symbol': 'BTCUSDT'},
          ),
          throwsA(isA<BinanceDataException>()),
        );
        expect(adapter.requests, hasLength(2));
        client.dispose();
      },
    );

    test(
      'route registry pins the approved endpoints, weights, and query limits',
      () {
        expect(
          BinanceReadRoutes.all.map((route) => route.path).toSet(),
          <String>{
            '/api/v3/time',
            '/api/v3/exchangeInfo',
            '/api/v3/ticker/24hr',
            '/api/v3/account',
            '/api/v3/openOrders',
            '/api/v3/allOrders',
            '/fapi/v1/time',
            '/fapi/v1/exchangeInfo',
            '/fapi/v1/ticker/24hr',
            '/fapi/v3/account',
            '/fapi/v3/positionRisk',
            '/fapi/v1/symbolConfig',
            '/fapi/v1/multiAssetsMargin',
            '/fapi/v1/openOrders',
            '/fapi/v1/openAlgoOrders',
            '/fapi/v1/allOrders',
            '/fapi/v1/allAlgoOrders',
          },
        );
        final spotTicker = BinanceReadRoutes.forPath('/api/v3/ticker/24hr')!;
        final futuresTicker = BinanceReadRoutes.forPath(
          '/fapi/v1/ticker/24hr',
        )!;
        final spotOpen = BinanceReadRoutes.forPath('/api/v3/openOrders')!;
        final futuresOpen = BinanceReadRoutes.forPath('/fapi/v1/openOrders')!;
        final spotHistory = BinanceReadRoutes.forPath('/api/v3/allOrders')!;

        expect(BinanceReadRoutes.forPath('/api/v3/time')!.weight, 1);
        expect(BinanceReadRoutes.forPath('/api/v3/exchangeInfo')!.weight, 20);
        expect(
          spotTicker.weightFor(const {
            'symbols': ['A', 'B'],
          }),
          2,
        );
        expect(futuresTicker.weightFor(const {'symbol': 'BTCUSDT'}), 1);
        expect(futuresTicker.weightFor(const {}), 40);
        expect(spotOpen.weightFor(const {'symbol': 'BTCUSDT'}), 6);
        expect(spotOpen.weightFor(const {}), 80);
        expect(futuresOpen.weightFor(const {'symbol': 'BTCUSDT'}), 1);
        expect(futuresOpen.weightFor(const {}), 40);
        expect(
          spotHistory.acceptsQuery(const {'symbol': 'BTCUSDT', 'limit': 500}),
          isTrue,
        );
        expect(spotHistory.acceptsQuery(const {'symbol': 'BTCUSDT'}), isFalse);
        expect(
          spotTicker.acceptsQuery(<String, Object>{
            'symbols': List<String>.generate(21, (index) => 'PAIR$index'),
          }),
          isFalse,
        );
      },
    );

    test(
      'private GET signs the exact encoded query at the fixed origin',
      () async {
        final clock = _MutableClock(DateTime.utc(2026, 10, 25, 8));
        final adapter = _RecordingAdapter((options) {
          if (options.uri.path == '/api/v3/time') {
            return _WireResponse(200, <String, Object>{
              'serverTime': clock.now.millisecondsSinceEpoch + 1200,
            });
          }
          return _WireResponse(200, <String, Object>{'orders': []});
        });
        final storage = _FixtureStorage.withCredentials();
        final client = _client(
          adapter,
          storage: storage,
          coordinator: _coordinator(clock),
          clock: clock,
        );

        final response = await client.get(
          '/api/v3/allOrders',
          queryParameters: const {'symbol': 'BTC USDT', 'limit': 500},
        );

        final request = adapter.requests.singleWhere(
          (value) => value.uri.path == '/api/v3/allOrders',
        );
        final timestamp = clock.now.millisecondsSinceEpoch + 1200;
        final expectedUnsigned =
            Uri.https('api.binance.com', '/api/v3/allOrders', <String, String>{
              'limit': '500',
              'recvWindow': '5000',
              'symbol': 'BTC USDT',
              'timestamp': '$timestamp',
            });
        final expectedSignature = Hmac(
          sha256,
          utf8.encode('fixture-binance-secret'),
        ).convert(utf8.encode(expectedUnsigned.query)).toString();

        expect(response.statusCode, 200);
        expect(response.requestOptions.path, '/<redacted>');
        expect(response.requestOptions.headers, isEmpty);
        expect(
          request.uri.toString(),
          'https://api.binance.com${expectedUnsigned.path}?'
          '${expectedUnsigned.query}&signature=$expectedSignature',
        );
        expect(request.method, 'GET');
        expect(request.data, isNull);
        expect(request.followRedirects, isFalse);
        expect(request.maxRedirects, 0);
        expect(request.headers['X-MBX-APIKEY'], 'fixture-binance-api-key');
        expect(request.headers['Authorization'], isNull);
        expect(request.headers['Cookie'], isNull);
        expect(request.extra['withCredentials'], isFalse);
        expect(storage.readCount, 1);
        client.dispose();
        storage.dispose();
      },
    );

    test('public read uses no credential storage or API-key header', () async {
      final adapter = _RecordingAdapter(
        (_) => _WireResponse(200, <String, Object>{'symbol': 'BTCUSDT'}),
      );
      final storage = _FixtureStorage.withCredentials();
      final client = _client(adapter, storage: storage);

      final response = await client.get(
        '/api/v3/ticker/24hr',
        queryParameters: const {'symbol': 'BTCUSDT'},
      );

      expect(response.statusCode, 200);
      expect(
        adapter.requests.single.uri.toString(),
        'https://api.binance.com/api/v3/ticker/24hr?symbol=BTCUSDT',
      );
      expect(adapter.requests.single.headers['X-MBX-APIKEY'], isNull);
      expect(storage.readCount, 0);
      client.dispose();
      storage.dispose();
    });

    test('interactive request jumps ahead of a queued history step', () async {
      final clock = _MutableClock(DateTime.utc(2026, 10, 25, 8));
      final delayStarted = Completer<void>();
      final releaseDelay = Completer<void>();
      final coordinator = BinanceRequestCoordinator(
        clock: () => clock.now,
        minimumSpacing: const Duration(seconds: 1),
        delay: (_) {
          if (!delayStarted.isCompleted) delayStarted.complete();
          return releaseDelay.future;
        },
      );
      _installBudget(coordinator, BinanceHost.spot);
      final order = <String>[];
      final first = coordinator.run<void>(
        host: BinanceHost.spot,
        weight: 1,
        priority: BinanceRequestPriority.interactive,
        request: () async => order.add('first'),
      );
      await first;
      final history = coordinator.run<void>(
        host: BinanceHost.spot,
        weight: 1,
        priority: BinanceRequestPriority.history,
        request: () async => order.add('history'),
      );
      await delayStarted.future;
      final interactive = coordinator.run<void>(
        host: BinanceHost.spot,
        weight: 1,
        priority: BinanceRequestPriority.interactive,
        request: () async => order.add('interactive'),
      );
      releaseDelay.complete();
      await Future.wait<void>(<Future<void>>[history, interactive]);

      expect(order, <String>['first', 'interactive', 'history']);
    });

    test(
      'dispose keeps the injected adapter fence through the active request',
      () async {
        final clock = _MutableClock(DateTime.utc(2026, 10, 25, 8));
        final accountStarted = Completer<void>();
        final releaseAccount = Completer<_WireResponse>();
        final adapter = _RecordingAdapter((options) async {
          if (options.uri.path == '/api/v3/time') {
            return _WireResponse(200, <String, Object>{
              'serverTime': clock.now.millisecondsSinceEpoch,
            });
          }
          accountStarted.complete();
          return releaseAccount.future;
        });
        final dio = Dio()..httpClientAdapter = adapter;
        final storage = _FixtureStorage.withCredentials();
        final client = BinanceDataClient(
          secureStorage: storage,
          requestCoordinator: _coordinator(clock),
          dio: dio,
          clock: () => clock.now,
        );

        final request = client.get('/api/v3/account');
        await accountStarted.future;
        client.dispose();
        final sentBeforeProbe = adapter.requests.length;
        await expectLater(
          dio.fetch<dynamic>(
            RequestOptions(
              path: 'https://api.binance.com/api/v3/time',
              method: 'GET',
            ),
          ),
          throwsA(isA<DioException>()),
        );
        expect(adapter.requests, hasLength(sentBeforeProbe));

        releaseAccount.complete(
          _WireResponse(200, <String, Object>{'balances': []}),
        );
        await expectLater(
          request,
          throwsA(
            isA<BinanceDataException>().having(
              (error) => error.code,
              'code',
              'request_cancelled',
            ),
          ),
        );
        expect(identical(dio.httpClientAdapter, adapter), isTrue);
        storage.dispose();
      },
    );

    group('RED-125 Spot private WebSocket reads', () {
      test('routes the three signed Spot reads with exact signed params', () async {
        final clock = _MutableClock(DateTime.utc(2026, 10, 25, 8));
        final adapter = _RecordingAdapter(
          (_) => _WireResponse(200, <String, Object>{
            'serverTime': clock.now.millisecondsSinceEpoch,
          }),
        );
        final storage = _FixtureStorage.withCredentials();
        final transport = _RecordingSpotTransport(
          (method, _, _) => BinanceWsReply(
            status: 200,
            result: <String, Object>{'method': method},
          ),
        );
        final client = BinanceDataClient(
          secureStorage: storage,
          requestCoordinator: _coordinator(clock),
          dio: Dio()..httpClientAdapter = adapter,
          clock: () => clock.now,
          spotPrivateTransport: transport,
        );

        final account = await client.get('/api/v3/account');
        final openOrders = await client.get(
          '/api/v3/openOrders',
          queryParameters: const <String, Object>{'symbol': 'BTCUSDT'},
        );
        final allOrders = await client.get(
          '/api/v3/allOrders',
          queryParameters: const <String, Object>{
            'symbol': 'BTCUSDT',
            'limit': 500,
          },
        );

        expect(transport.calls.map((call) => call.method), <String>[
          'account.status',
          'openOrders.status',
          'allOrders',
        ]);
        expect(account.data, <String, Object>{'method': 'account.status'});
        expect(openOrders.data, <String, Object>{
          'method': 'openOrders.status',
        });
        expect(allOrders.data, <String, Object>{'method': 'allOrders'});
        expect(account.statusCode, 200);
        expect(adapter.requests.map((request) => request.uri.path), <String>[
          '/api/v3/time',
        ]);

        final expectedPayloads = <String>[
          'apiKey=fixture-binance-api-key&recvWindow=5000&timestamp=1792915200000',
          'apiKey=fixture-binance-api-key&recvWindow=5000&symbol=BTCUSDT&timestamp=1792915200000',
          'apiKey=fixture-binance-api-key&limit=500&recvWindow=5000&symbol=BTCUSDT&timestamp=1792915200000',
        ];
        final expectedUnsignedParams = <Map<String, Object>>[
          <String, Object>{
            'apiKey': 'fixture-binance-api-key',
            'recvWindow': '5000',
            'timestamp': '1792915200000',
          },
          <String, Object>{
            'apiKey': 'fixture-binance-api-key',
            'recvWindow': '5000',
            'symbol': 'BTCUSDT',
            'timestamp': '1792915200000',
          },
          <String, Object>{
            'apiKey': 'fixture-binance-api-key',
            'limit': '500',
            'recvWindow': '5000',
            'symbol': 'BTCUSDT',
            'timestamp': '1792915200000',
          },
        ];
        for (var index = 0; index < transport.calls.length; index++) {
          final params = transport.calls[index].params;
          final unsignedParams = Map<String, Object>.from(params)
            ..remove('signature');
          expect(unsignedParams, expectedUnsignedParams[index]);
          expect(params.keys, contains('signature'));
          final independentlyComputedSignature = Hmac(
            sha256,
            utf8.encode('fixture-binance-secret'),
          ).convert(utf8.encode(expectedPayloads[index])).toString();
          expect(params['signature'], independentlyComputedSignature);
          expect(params['signature'], matches(RegExp(r'^[0-9a-f]{64}$')));
        }
        client.dispose();
        storage.dispose();
      });

      test('public and Futures routes keep using Dio', () async {
        final clock = _MutableClock(DateTime.utc(2026, 10, 25, 8));
        final adapter = _RecordingAdapter((options) {
          if (options.uri.path.endsWith('/time')) {
            return _WireResponse(200, <String, Object>{
              'serverTime': clock.now.millisecondsSinceEpoch,
            });
          }
          return _WireResponse(200, <String, Object>{'ok': true});
        });
        final storage = _FixtureStorage.withCredentials();
        final transport = _RecordingSpotTransport(
          (_, __, ___) => const BinanceWsReply(
            status: 200,
            result: <String, Object>{'unexpected': true},
          ),
        );
        final client = BinanceDataClient(
          secureStorage: storage,
          requestCoordinator: _coordinator(clock),
          dio: Dio()..httpClientAdapter = adapter,
          clock: () => clock.now,
          spotPrivateTransport: transport,
        );

        await client.get(
          '/api/v3/ticker/24hr',
          queryParameters: const <String, Object>{'symbol': 'BTCUSDT'},
        );
        await client.get('/fapi/v3/account');

        expect(transport.calls, isEmpty);
        final publicRequest = adapter.requests.singleWhere(
          (request) => request.uri.path == '/api/v3/ticker/24hr',
        );
        final futuresRequest = adapter.requests.singleWhere(
          (request) => request.uri.path == '/fapi/v3/account',
        );
        expect(publicRequest.headers['X-MBX-APIKEY'], isNull);
        expect(
          futuresRequest.headers['X-MBX-APIKEY'],
          'fixture-binance-api-key',
        );
        client.dispose();
        storage.dispose();
      });

      test(
        'synthetic Spot weight header reaches the request coordinator',
        () async {
          final clock = _MutableClock(DateTime.utc(2026, 10, 25, 8));
          final coordinator = BinanceRequestCoordinator(
            clock: () => clock.now,
            minimumSpacing: Duration.zero,
            delay: (_) async {},
          );
          coordinator.installLimits(BinanceHost.spot, const [
            BinanceRateLimitWindow(
              rateLimitType: 'REQUEST_WEIGHT',
              interval: 'MINUTE',
              intervalNum: 1,
              limit: 60,
            ),
            BinanceRateLimitWindow(
              rateLimitType: 'RAW_REQUEST',
              interval: 'SECOND',
              intervalNum: 10,
              limit: 100,
            ),
          ]);
          final adapter = _RecordingAdapter(
            (_) => _WireResponse(200, <String, Object>{
              'serverTime': clock.now.millisecondsSinceEpoch,
            }),
          );
          final storage = _FixtureStorage.withCredentials();
          final transport = _RecordingSpotTransport(
            (_, __, ___) => const BinanceWsReply(
              status: 200,
              result: <String, Object>{'ok': true},
              rateLimits: <Map<String, Object?>>[
                <String, Object?>{
                  'rateLimitType': 'REQUEST_WEIGHT',
                  'interval': 'SECOND',
                  'intervalNum': 1,
                  'count': 1,
                },
                <String, Object?>{
                  'rateLimitType': 'REQUEST_WEIGHT',
                  'interval': 'MINUTE',
                  'intervalNum': 1,
                  'count': 50,
                },
              ],
            ),
          );
          final client = BinanceDataClient(
            secureStorage: storage,
            requestCoordinator: coordinator,
            dio: Dio()..httpClientAdapter = adapter,
            clock: () => clock.now,
            spotPrivateTransport: transport,
          );

          await client.get('/api/v3/account');
          await expectLater(
            client.get('/api/v3/account'),
            throwsA(
              isA<BinanceDataException>().having(
                (error) => error.code,
                'code',
                'binance_host_paused',
              ),
            ),
          );
          expect(transport.calls, hasLength(1));
          client.dispose();
          storage.dispose();
        },
      );

      test(
        '429 and 418 replies preserve status and retry-after mappings',
        () async {
          for (final (status, code) in <(int, String)>[
            (429, 'binance_rate_limited'),
            (418, 'binance_ip_banned'),
          ]) {
            final clock = _MutableClock(DateTime.utc(2026, 10, 25, 8));
            final adapter = _RecordingAdapter(
              (_) => _WireResponse(200, <String, Object>{
                'serverTime': clock.now.millisecondsSinceEpoch,
              }),
            );
            final storage = _FixtureStorage.withCredentials();
            final transport = _RecordingSpotTransport(
              (_, __, ___) => BinanceWsReply(
                status: status,
                errorCode: -1000,
                errorMessage: 'private transport error detail',
                retryAfter: '75',
              ),
            );
            final client = BinanceDataClient(
              secureStorage: storage,
              requestCoordinator: _coordinator(clock),
              dio: Dio()..httpClientAdapter = adapter,
              clock: () => clock.now,
              spotPrivateTransport: transport,
            );

            final error = await _captureBinanceError(
              () => client.get('/api/v3/account'),
            );
            expect(error.code, code);
            expect(error.statusCode, status);
            expect(error.retryAfter, '75');
            client.dispose();
            storage.dispose();
          }
        },
      );

      test(
        'timestamp errors resync and retry the transport exactly once',
        () async {
          final clock = _MutableClock(DateTime.utc(2026, 10, 25, 8));
          var timeReads = 0;
          final adapter = _RecordingAdapter((options) {
            if (options.uri.path == '/api/v3/time') {
              timeReads++;
              return _WireResponse(200, <String, Object>{
                'serverTime':
                    clock.now.millisecondsSinceEpoch + timeReads * 5000,
              });
            }
            return _WireResponse(200, <String, Object>{});
          });
          final storage = _FixtureStorage.withCredentials();
          var sends = 0;
          final transport = _RecordingSpotTransport((_, __, ___) {
            sends++;
            if (sends == 1) {
              return const BinanceWsReply(
                status: 400,
                errorCode: -1021,
                errorMessage: 'timestamp rejected',
              );
            }
            return const BinanceWsReply(
              status: 200,
              result: <String, Object>{'balances': []},
            );
          });
          final client = BinanceDataClient(
            secureStorage: storage,
            requestCoordinator: _coordinator(clock),
            dio: Dio()..httpClientAdapter = adapter,
            clock: () => clock.now,
            spotPrivateTransport: transport,
          );

          final response = await client.get('/api/v3/account');

          expect(response.statusCode, 200);
          expect(response.data, <String, Object>{'balances': []});
          expect(timeReads, 2);
          expect(transport.calls, hasLength(2));
          expect(
            transport.calls.map((call) => call.params['timestamp']).toSet(),
            hasLength(2),
          );
          client.dispose();
          storage.dispose();
        },
      );

      test('authentication errors are sanitized and do not retry', () async {
        const apiKey = 'sentinel-api-key-task-125';
        const secretKey = 'sentinel-secret-task-125';
        for (final errorCode in <int>[-2014, -2015]) {
          final clock = _MutableClock(DateTime.utc(2026, 10, 25, 8));
          var timeReads = 0;
          final adapter = _RecordingAdapter((options) {
            if (options.uri.path == '/api/v3/time') {
              timeReads++;
              return _WireResponse(200, <String, Object>{
                'serverTime': clock.now.millisecondsSinceEpoch,
              });
            }
            return _WireResponse(200, <String, Object>{});
          });
          final storage = _FixtureStorage.withCredentials(
            apiKey: apiKey,
            secretKey: secretKey,
          );
          final transport = _RecordingSpotTransport((_, params, _) {
            return BinanceWsReply(
              status: 400,
              errorCode: errorCode,
              errorMessage: '$apiKey $secretKey ${params['signature']}',
            );
          });
          final client = BinanceDataClient(
            secureStorage: storage,
            requestCoordinator: _coordinator(clock),
            dio: Dio()..httpClientAdapter = adapter,
            clock: () => clock.now,
            spotPrivateTransport: transport,
          );

          final error = await _captureBinanceError(
            () => client.get('/api/v3/account'),
          );
          expect(error.code, 'binance_authentication_failed');
          expect(error.toString(), isNot(contains(apiKey)));
          expect(error.toString(), isNot(contains(secretKey)));
          expect(
            error.toString(),
            isNot(contains(transport.calls.single.params['signature'])),
          );
          expect(timeReads, 1);
          expect(transport.calls, hasLength(1));
          client.dispose();
          storage.dispose();
        }
      });

      test(
        'maps each typed transport failure to the safe client code',
        () async {
          for (final (failure, code) in <(BinanceSpotTransportFailure, String)>[
            (BinanceSpotTransportFailure.timeout, 'binance_timeout'),
            (BinanceSpotTransportFailure.network, 'binance_network_error'),
            (BinanceSpotTransportFailure.cancelled, 'request_cancelled'),
            (BinanceSpotTransportFailure.closed, 'request_cancelled'),
          ]) {
            final clock = _MutableClock(DateTime.utc(2026, 10, 25, 8));
            final adapter = _RecordingAdapter(
              (_) => _WireResponse(200, <String, Object>{
                'serverTime': clock.now.millisecondsSinceEpoch,
              }),
            );
            final storage = _FixtureStorage.withCredentials();
            final transport = _RecordingSpotTransport(
              (_, __, ___) => throw BinanceSpotTransportException(failure),
            );
            final client = BinanceDataClient(
              secureStorage: storage,
              requestCoordinator: _coordinator(clock),
              dio: Dio()..httpClientAdapter = adapter,
              clock: () => clock.now,
              spotPrivateTransport: transport,
            );

            final error = await _captureBinanceError(
              () => client.get('/api/v3/account'),
            );
            expect(error.code, code);
            client.dispose();
            storage.dispose();
          }
        },
      );

      test(
        'credential changes fence requests and close the transport',
        () async {
          final readStarted = Completer<void>();
          final releaseRead = Completer<void>();
          final clock = _MutableClock(DateTime.utc(2026, 10, 25, 8));
          final adapter = _RecordingAdapter(
            (_) => _WireResponse(200, <String, Object>{
              'serverTime': clock.now.millisecondsSinceEpoch,
            }),
          );
          final storage = _FixtureStorage.withCredentials()
            ..readStarted = readStarted
            ..readGate = releaseRead.future;
          final transport = _RecordingSpotTransport(
            (_, __, ___) => const BinanceWsReply(
              status: 200,
              result: <String, Object>{'ok': true},
            ),
          );
          final client = BinanceDataClient(
            secureStorage: storage,
            requestCoordinator: _coordinator(clock),
            dio: Dio()..httpClientAdapter = adapter,
            clock: () => clock.now,
            spotPrivateTransport: transport,
          );

          final request = client.get('/api/v3/account');
          await readStarted.future;
          await storage.rotate();
          expect(transport.closeCount, greaterThan(0));
          releaseRead.complete();

          final error = await _captureBinanceError(() => request);
          expect(error.code, 'credentials_changed');
          expect(transport.calls, isEmpty);
          client.dispose();
          expect(transport.disposeCount, 1);
          storage.dispose();
        },
      );

      test(
        'rotation during transport rejects the stale result and dispose closes it',
        () async {
          final clock = _MutableClock(DateTime.utc(2026, 10, 25, 8));
          final transportStarted = Completer<void>();
          final releaseTransport = Completer<BinanceWsReply>();
          final adapter = _RecordingAdapter(
            (_) => _WireResponse(200, <String, Object>{
              'serverTime': clock.now.millisecondsSinceEpoch,
            }),
          );
          final storage = _FixtureStorage.withCredentials();
          final transport = _RecordingSpotTransport((_, __, ___) {
            transportStarted.complete();
            return releaseTransport.future;
          });
          final client = BinanceDataClient(
            secureStorage: storage,
            requestCoordinator: _coordinator(clock),
            dio: Dio()..httpClientAdapter = adapter,
            clock: () => clock.now,
            spotPrivateTransport: transport,
          );

          final request = client.get('/api/v3/account');
          await transportStarted.future;
          await storage.rotate();
          expect(transport.closeCount, greaterThan(0));
          releaseTransport.complete(
            const BinanceWsReply(
              status: 200,
              result: <String, Object>{'ok': true},
            ),
          );

          final error = await _captureBinanceError(() => request);
          expect(error.code, 'credentials_changed');
          client.dispose();
          expect(transport.disposeCount, 1);
          storage.dispose();
        },
      );
    });
  });
}

BinanceDataClient _client(
  HttpClientAdapter adapter, {
  SecureStorageHelper? storage,
  BinanceRequestCoordinator? coordinator,
  _MutableClock? clock,
}) {
  final dio = Dio()..httpClientAdapter = adapter;
  final effectiveClock = clock ?? _MutableClock(DateTime.utc(2026, 10, 25, 8));
  return BinanceDataClient(
    secureStorage: storage,
    requestCoordinator: coordinator ?? _coordinator(effectiveClock),
    dio: dio,
    clock: () => effectiveClock.now,
  );
}

BinanceRequestCoordinator _coordinator(_MutableClock clock) {
  final coordinator = BinanceRequestCoordinator(
    clock: () => clock.now,
    minimumSpacing: Duration.zero,
    delay: (_) async {},
  );
  _installBudget(coordinator, BinanceHost.spot);
  _installBudget(coordinator, BinanceHost.futures);
  return coordinator;
}

void _installBudget(BinanceRequestCoordinator coordinator, BinanceHost host) {
  coordinator.installLimits(host, const <BinanceRateLimitWindow>[
    BinanceRateLimitWindow(
      rateLimitType: 'REQUEST_WEIGHT',
      interval: 'MINUTE',
      intervalNum: 1,
      limit: 1200,
    ),
    BinanceRateLimitWindow(
      rateLimitType: 'RAW_REQUEST',
      interval: 'SECOND',
      intervalNum: 10,
      limit: 100,
    ),
  ]);
}

class _FixtureStorage extends SecureStorageHelper {
  _FixtureStorage({String? encodedBundle})
    : _encodedBundle = encodedBundle,
      super(const FlutterSecureStorage());

  String? _encodedBundle;
  int readCount = 0;
  Completer<void>? readStarted;
  Future<void>? readGate;

  factory _FixtureStorage.withCredentials({
    String apiKey = 'fixture-binance-api-key',
    String secretKey = 'fixture-binance-secret',
  }) {
    final bundle = BinanceCredentialBundle.tryCreate(
      apiKey: apiKey,
      secretKey: secretKey,
    )!;
    return _FixtureStorage(encodedBundle: bundle.encode());
  }

  @override
  Future<String?> readBinanceCredentialBundle() async {
    readCount++;
    final encoded = _encodedBundle;
    readStarted?.complete();
    if (readGate != null) await readGate;
    return encoded;
  }

  Future<void> rotate() => trackBinanceCredentialMutation(() async {
    final bundle = BinanceCredentialBundle.tryCreate(
      apiKey: 'fixture-new-binance-api-key',
      secretKey: 'fixture-new-binance-secret',
    )!;
    _encodedBundle = bundle.encode();
  });
}

Future<BinanceDataException> _captureBinanceError(
  Future<Object?> Function() action,
) async {
  try {
    await action();
  } on BinanceDataException catch (error) {
    return error;
  }
  throw StateError('Expected a BinanceDataException.');
}

typedef _SpotTransportHandler =
    FutureOr<BinanceWsReply> Function(
      String method,
      Map<String, Object> params,
      CancelToken? cancelToken,
    );

class _RecordingSpotTransport implements BinanceSpotPrivateTransport {
  _RecordingSpotTransport(this.handler);

  final _SpotTransportHandler handler;
  final List<_SpotCall> calls = <_SpotCall>[];
  int closeCount = 0;
  int disposeCount = 0;

  @override
  Future<BinanceWsReply> send({
    required String method,
    required Map<String, Object> params,
    CancelToken? cancelToken,
  }) async {
    final safeParams = Map<String, Object>.unmodifiable(params);
    calls.add(_SpotCall(method, safeParams, cancelToken));
    return await handler(method, safeParams, cancelToken);
  }

  @override
  void close() => closeCount++;

  @override
  void dispose() => disposeCount++;
}

class _SpotCall {
  const _SpotCall(this.method, this.params, this.cancelToken);

  final String method;
  final Map<String, Object> params;
  final CancelToken? cancelToken;
}

class _CapturingCoordinator extends BinanceRequestCoordinator {
  _CapturingCoordinator({super.clock, super.delay, super.minimumSpacing});

  final List<Object> completedErrors = <Object>[];

  @override
  Future<T> run<T>({
    required BinanceHost host,
    required int weight,
    required BinanceRequestPriority priority,
    int rawRequests = 1,
    required Future<T> Function() request,
  }) {
    return super.run<T>(
      host: host,
      weight: weight,
      priority: priority,
      rawRequests: rawRequests,
      request: () async {
        try {
          return await request();
        } catch (error) {
          completedErrors.add(error);
          rethrow;
        }
      },
    );
  }
}

class _MutableClock {
  _MutableClock(this.now);

  DateTime now;

  void advance(Duration duration) {
    now = now.add(duration);
  }
}

typedef _ResponseHandler =
    FutureOr<_WireResponse> Function(RequestOptions options);

class _WireResponse {
  const _WireResponse(
    this.statusCode,
    this.body, {
    this.headers = const <String, List<String>>{},
  });

  final int statusCode;
  final Object body;
  final Map<String, List<String>> headers;
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.handler);

  final _ResponseHandler handler;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final response = await handler(options);
    return ResponseBody.fromString(
      jsonEncode(response.body),
      response.statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        ...response.headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
