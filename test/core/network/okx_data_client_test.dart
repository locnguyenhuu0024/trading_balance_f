import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:trading_balance_f/core/network/okx_data_client.dart';
import 'package:trading_balance_f/core/network/request_coordinator.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';

void main() {
  group('RED-114', () {
    test(
      'close during a signed interceptor keeps the final guard installed',
      () async {
        final adapter = _RecordingAdapter((_) => _WireResponse(200, _success));
        final interceptorReached = Completer<void>();
        final releaseInterceptor = Completer<void>();
        final dio = Dio()..httpClientAdapter = adapter;
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              interceptorReached.complete();
              await releaseInterceptor.future;
              options.path = 'https://attacker.example/api/v5/account/balance';
              options.method = 'POST';
              options.headers['Authorization'] = 'Bearer backend-token';
              handler.next(options);
            },
          ),
        );
        final storage = _FixtureStorage.withCredentials();
        final client = OkxDataClient(dio: dio, secureStorage: storage);

        final request = client.get('/api/v5/account/balance');
        await interceptorReached.future;
        client.dispose();
        releaseInterceptor.complete();

        await expectLater(
          request,
          throwsA(
            isA<OkxDataException>()
                .having((error) => error.code, 'code', 'request_cancelled')
                .having(
                  (error) => error.message,
                  'message',
                  'The OKX read client was closed.',
                ),
          ),
        );
        expect(adapter.requests, isEmpty);
        storage.dispose();
      },
    );

    test('close during credential loading prevents a later send', () async {
      final adapter = _RecordingAdapter((_) => _WireResponse(200, _success));
      final storage = _DelayedFixtureStorage();
      final client = _client(adapter, storage: storage);

      final request = client.get('/api/v5/account/balance');
      await storage.allReadsStarted.future;
      client.dispose();
      storage.releaseReads.complete();

      await expectLater(
        request,
        throwsA(
          isA<OkxDataException>()
              .having((error) => error.code, 'code', 'request_cancelled')
              .having(
                (error) => error.message,
                'message',
                'The OKX read client was closed.',
              ),
        ),
      );
      expect(adapter.requests, isEmpty);
      storage.dispose();
    });

    test(
      'close fences private work waiting in the coordinator queue',
      () async {
        final adapter = _FirstPendingThenRecordingAdapter();
        final storage = _FixtureStorage.withCredentials();
        final delayStarted = Completer<void>();
        final releaseDelay = Completer<void>();
        final coordinator = RequestCoordinator(
          minimumSpacing: const Duration(seconds: 1),
          delay: (_) {
            if (!delayStarted.isCompleted) delayStarted.complete();
            return releaseDelay.future;
          },
        );
        final client = OkxDataClient(
          dio: Dio()..httpClientAdapter = adapter,
          secureStorage: storage,
          requestCoordinator: coordinator,
        );

        final first = client.get('/api/v5/account/balance');
        await adapter.firstStarted.future;
        adapter.replyFirst(_WireResponse(200, _success));
        expect((await first).statusCode, 200);

        final queued = client.get('/api/v5/account/positions');
        await delayStarted.future;
        final queuedResult = expectLater(
          queued,
          throwsA(
            isA<OkxDataException>().having(
              (error) => error.code,
              'code',
              'request_cancelled',
            ),
          ),
        );

        client.dispose();
        releaseDelay.complete();
        await queuedResult;

        expect(adapter.requests, hasLength(1));
        storage.dispose();
      },
    );

    test('close rejects a late result from an already-sent request', () async {
      final adapter = _PendingAdapter();
      final storage = _FixtureStorage.withCredentials();
      final client = OkxDataClient(
        dio: Dio()..httpClientAdapter = adapter,
        secureStorage: storage,
      );

      final request = client.get('/api/v5/account/balance');
      await adapter.requestStarted.future;
      client.dispose();
      adapter.reply(_WireResponse(200, _success));

      await expectLater(
        request,
        throwsA(
          isA<OkxDataException>()
              .having((error) => error.code, 'code', 'request_cancelled')
              .having(
                (error) => error.message,
                'message',
                'The OKX read client was closed.',
              ),
        ),
      );
      expect(adapter.requestCount, 1);
      storage.dispose();
    });
  });

  group('GREEN-114', () {
    test(
      'normal public and current-generation private reads still succeed',
      () async {
        final adapter = _RecordingAdapter((_) => _WireResponse(200, _success));
        final storage = _FixtureStorage.withCredentials();
        final client = OkxDataClient(
          dio: Dio()..httpClientAdapter = adapter,
          secureStorage: storage,
          requestCoordinator: RequestCoordinator(
            minimumSpacing: Duration.zero,
            delay: (_) async {},
          ),
        );

        final publicResponse = await client.get('/api/v5/market/ticker');
        final privateResponse = await client.get('/api/v5/account/balance');

        expect(publicResponse.statusCode, 200);
        expect(privateResponse.statusCode, 200);
        expect(adapter.requests, hasLength(2));
        expect(_okxCredentialHeaderCount(adapter.requests.first.headers), 0);
        expect(_okxCredentialHeaderCount(adapter.requests.last.headers), 4);
        client.dispose();
        storage.dispose();
      },
    );

    test(
      'injected Dio restores after drain and remains usable without leaked credentials',
      () async {
        final adapter = _FirstPendingThenRecordingAdapter();
        final otherInterceptorCalls = <Map<String, dynamic>>[];
        final otherInterceptor = InterceptorsWrapper(
          onRequest: (options, handler) {
            otherInterceptorCalls.add(options.headers);
            handler.next(options);
          },
        );
        final dio = Dio()..httpClientAdapter = adapter;
        dio.interceptors.add(otherInterceptor);
        final originalInterceptors = List<Interceptor>.of(dio.interceptors);
        final storage = _FixtureStorage.withCredentials();
        final client = OkxDataClient(dio: dio, secureStorage: storage);

        final managed = client.get('/api/v5/account/balance');
        await adapter.firstStarted.future;
        expect(_okxCredentialHeaderCount(adapter.requests.single.headers), 4);

        client.dispose();
        adapter.replyFirst(_WireResponse(200, _success));
        await expectLater(
          managed,
          throwsA(
            isA<OkxDataException>()
                .having((error) => error.code, 'code', 'request_cancelled')
                .having(
                  (error) => error.message,
                  'message',
                  'The OKX read client was closed.',
                ),
          ),
        );

        expect(identical(dio.httpClientAdapter, adapter), isTrue);
        expect(dio.interceptors, hasLength(originalInterceptors.length));
        for (final interceptor in originalInterceptors) {
          expect(dio.interceptors, contains(same(interceptor)));
        }
        expect(dio.interceptors, contains(same(otherInterceptor)));
        final rawResponse = await dio.fetch<dynamic>(
          RequestOptions(
            path: 'https://www.okx.com/api/v5/account/balance',
            method: 'GET',
            followRedirects: false,
            maxRedirects: 0,
            extra: const {'withCredentials': false},
          ),
        );

        expect(rawResponse.statusCode, 200);
        expect(adapter.requests, hasLength(2));
        expect(_okxCredentialHeaderCount(adapter.requests.last.headers), 0);
        expect(otherInterceptorCalls, hasLength(2));
        expect(storage.readCount, 3);
        storage.dispose();
      },
    );
  });

  group('RED-116', () {
    test(
      'rejects Binance API-key headers before an OKX adapter send',
      () async {
        final configuredAdapter = _RecordingAdapter(
          (_) => _WireResponse(200, _success),
        );
        final configuredDio = Dio()
          ..options.headers['x-mbx-apikey'] = 'fixture-binance-key'
          ..httpClientAdapter = configuredAdapter;
        final configuredClient = OkxDataClient(dio: configuredDio);

        await expectLater(
          configuredClient.get('/api/v5/market/ticker'),
          throwsA(
            isA<OkxDataException>().having(
              (error) => error.code,
              'code',
              'okx_request_forbidden',
            ),
          ),
        );
        expect(configuredAdapter.requests, isEmpty);
        configuredClient.dispose();

        final lateAdapter = _RecordingAdapter(
          (_) => _WireResponse(200, _success),
        );
        final lateDio = Dio()..httpClientAdapter = lateAdapter;
        lateDio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              options.headers['X-MBX-APIKEY'] = 'fixture-late-binance-key';
              handler.next(options);
            },
          ),
        );
        final lateClient = OkxDataClient(dio: lateDio);

        await expectLater(
          lateClient.get('/api/v5/market/ticker'),
          throwsA(isA<OkxDataException>()),
        );
        expect(lateAdapter.requests, isEmpty);
        lateClient.dispose();
      },
    );
  });

  group('GREEN-116', () {
    test(
      'public OKX reads remain independent of Binance headers and storage',
      () async {
        final adapter = _RecordingAdapter((_) => _WireResponse(200, _success));
        final storage = _FixtureStorage.withCredentials();
        final client = _client(adapter, storage: storage);

        final response = await client.get('/api/v5/market/ticker');

        expect(response.statusCode, 200);
        expect(adapter.requests, hasLength(1));
        expect(adapter.requests.single.headers['X-MBX-APIKEY'], isNull);
        expect(storage.readCount, 0);
        client.dispose();
        storage.dispose();
      },
    );
  });

  group('RED-001', () {
    test('rejects missing private credentials before sending', () async {
      final adapter = _RecordingAdapter((_) => _WireResponse(200, _success));
      final storage = _FixtureStorage();
      final client = _client(adapter, storage: storage);

      await expectLater(
        client.get('/api/v5/account/balance'),
        throwsA(
          isA<OkxDataException>()
              .having((error) => error.code, 'code', 'okx_credentials_required')
              .having((error) => error.statusCode, 'statusCode', 401),
        ),
      );

      expect(adapter.requests, isEmpty);
      client.dispose();
      storage.dispose();
    });

    test('rejects unregistered routes and caller bearer headers', () async {
      final unregisteredAdapter = _RecordingAdapter(
        (_) => _WireResponse(200, _success),
      );
      final unregisteredClient = _client(unregisteredAdapter);
      await expectLater(
        unregisteredClient.get('/api/v5/market/quotes'),
        throwsA(
          isA<OkxDataException>().having(
            (error) => error.code,
            'code',
            'okx_route_not_allowed',
          ),
        ),
      );
      expect(unregisteredAdapter.requests, isEmpty);
      unregisteredClient.dispose();

      final headerAdapter = _RecordingAdapter(
        (_) => _WireResponse(200, _success),
      );
      final dio = Dio()
        ..options.headers['Authorization'] = 'Bearer backend-token';
      dio.httpClientAdapter = headerAdapter;
      final headerClient = OkxDataClient(dio: dio);
      await expectLater(
        headerClient.get('/api/v5/market/ticker'),
        throwsA(
          isA<OkxDataException>().having(
            (error) => error.code,
            'code',
            'okx_request_forbidden',
          ),
        ),
      );
      expect(headerAdapter.requests, isEmpty);
      headerClient.dispose();
    });

    test(
      'blocks later destination, method, and query mutation at the adapter',
      () async {
        final mutations = <void Function(RequestOptions)>[
          (options) =>
              options.path = 'https://attacker.example/api/v5/account/balance',
          (options) => options.method = 'POST',
          (options) => options.path = '${options.path}&instId=ETH-USDT',
          (options) =>
              options.headers['Authorization'] = 'Bearer backend-token',
        ];

        for (final mutate in mutations) {
          final adapter = _RecordingAdapter(
            (_) => _WireResponse(200, _success),
          );
          final dio = Dio()..httpClientAdapter = adapter;
          dio.interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                mutate(options);
                handler.next(options);
              },
            ),
          );
          final storage = _FixtureStorage.withCredentials();
          final client = OkxDataClient(dio: dio, secureStorage: storage);

          await expectLater(
            client.get(
              '/api/v5/account/balance',
              queryParameters: const {'ccy': 'USDT'},
            ),
            throwsA(isA<OkxDataException>()),
          );
          expect(adapter.requests, isEmpty);
          client.dispose();
          storage.dispose();
        }
      },
    );

    test(
      'rejects direct Dio.fetch without a client authorization record',
      () async {
        final adapter = _RecordingAdapter((_) => _WireResponse(200, _success));
        final dio = Dio()..httpClientAdapter = adapter;
        final client = OkxDataClient(dio: dio);

        await expectLater(
          dio.fetch<dynamic>(
            RequestOptions(
              path: 'https://www.okx.com/api/v5/public/instruments',
              method: 'GET',
              followRedirects: false,
              maxRedirects: 0,
              extra: const {'withCredentials': false},
            ),
          ),
          throwsA(isA<DioException>()),
        );

        expect(adapter.requests, isEmpty);
        client.dispose();
      },
    );

    test('rotation rejects a stale in-flight private success', () async {
      final adapter = _PendingAdapter();
      final storage = _FixtureStorage.withCredentials();
      final client = OkxDataClient(
        dio: Dio()..httpClientAdapter = adapter,
        secureStorage: storage,
      );

      final inFlight = client.get('/api/v5/account/balance');
      await adapter.requestStarted.future;
      await storage.rotate();
      adapter.reply(_WireResponse(200, _success));

      await expectLater(
        inFlight,
        throwsA(
          isA<OkxDataException>().having(
            (error) => error.code,
            'code',
            'credentials_changed',
          ),
        ),
      );
      client.dispose();
      storage.dispose();
    });

    test(
      'rotation fences private work already waiting in the shared queue',
      () async {
        final adapter = _PendingAdapter();
        final storage = _FixtureStorage.withCredentials();
        final delayStarted = Completer<void>();
        final releaseDelay = Completer<void>();
        final coordinator = RequestCoordinator(
          minimumSpacing: const Duration(seconds: 1),
          delay: (_) {
            if (!delayStarted.isCompleted) delayStarted.complete();
            return releaseDelay.future;
          },
        );
        final client = OkxDataClient(
          dio: Dio()..httpClientAdapter = adapter,
          secureStorage: storage,
          requestCoordinator: coordinator,
        );

        final inFlight = client.get('/api/v5/account/balance');
        await adapter.requestStarted.future;
        final queued = client.get('/api/v5/account/positions');
        adapter.reply(_WireResponse(200, _success));
        await inFlight;
        await delayStarted.future;
        await storage.rotate();
        releaseDelay.complete();

        await expectLater(
          queued,
          throwsA(
            isA<OkxDataException>().having(
              (error) => error.code,
              'code',
              'credentials_changed',
            ),
          ),
        );
        expect(adapter.requestCount, 1);
        client.dispose();
        storage.dispose();
      },
    );

    test('rotation replaces a late private transport error', () async {
      final adapter = _PendingAdapter();
      final storage = _FixtureStorage.withCredentials();
      final client = OkxDataClient(
        dio: Dio()..httpClientAdapter = adapter,
        secureStorage: storage,
      );

      final request = client.get('/api/v5/account/balance');
      final options = await adapter.requestStarted.future;
      await storage.rotate();
      adapter.fail(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
          message: 'fixture transport detail',
        ),
      );

      await expectLater(
        request,
        throwsA(
          isA<OkxDataException>().having(
            (error) => error.code,
            'code',
            'credentials_changed',
          ),
        ),
      );
      client.dispose();
      storage.dispose();
    });

    test('one cancel owner cannot cancel another private caller', () async {
      final adapter = _MultiPendingAdapter();
      final storage = _FixtureStorage.withCredentials();
      final coordinator = RequestCoordinator(
        minimumSpacing: Duration.zero,
        delay: (_) async {},
      );
      final client = OkxDataClient(
        dio: Dio()..httpClientAdapter = adapter,
        secureStorage: storage,
        requestCoordinator: coordinator,
      );
      final firstToken = CancelToken();
      final secondToken = CancelToken();

      final first = client.get(
        '/api/v5/account/balance',
        cancelToken: firstToken,
      );
      await adapter.firstStarted.future;
      final second = client.get(
        '/api/v5/account/balance',
        cancelToken: secondToken,
      );
      firstToken.cancel('first owner released');

      await expectLater(
        first,
        throwsA(
          isA<OkxDataException>().having(
            (error) => error.code,
            'code',
            'request_cancelled',
          ),
        ),
      );
      await adapter.secondStarted.future;
      adapter.reply(1, _WireResponse(200, _success));

      expect((await second).statusCode, 200);
      expect(adapter.requests, hasLength(2));
      client.dispose();
      storage.dispose();
    });

    test(
      'maps OKX code 50011 into authenticated coordinator backoff',
      () async {
        final adapter = _RecordingAdapter(
          (_) => _WireResponse(200, const {
            'code': '50011',
            'msg': 'private detail',
          }),
        );
        final storage = _FixtureStorage.withCredentials();
        final coordinator = RequestCoordinator(
          minimumSpacing: Duration.zero,
          delay: (_) async {},
        );
        final client = OkxDataClient(
          dio: Dio()..httpClientAdapter = adapter,
          secureStorage: storage,
          requestCoordinator: coordinator,
        );

        await expectLater(
          client.get('/api/v5/account/balance'),
          throwsA(
            isA<RequestRateLimitException>().having(
              (error) => error.statusCode,
              'statusCode',
              429,
            ),
          ),
        );
        expect(
          coordinator.stateFor(RequestLane.authenticated).isBackingOff,
          isTrue,
        );
        await expectLater(
          client.get('/api/v5/account/balance'),
          throwsA(isA<RequestBackoffException>()),
        );
        expect(adapter.requests, hasLength(1));
        client.dispose();
        storage.dispose();
      },
    );

    test(
      'sanitizes credential and timestamp envelopes as terminal auth errors',
      () async {
        for (final fixture in <(String, String)>[
          ('50113', 'private-key-detail'),
          ('50102', 'server-time-detail'),
        ]) {
          final adapter = _RecordingAdapter(
            (_) => _WireResponse(200, <String, String>{
              'code': fixture.$1,
              'msg': fixture.$2,
            }),
          );
          final storage = _FixtureStorage.withCredentials();
          final client = _client(adapter, storage: storage);
          final expectedCode = fixture.$1 == '50102'
              ? 'okx_timestamp_invalid'
              : 'okx_authentication_failed';

          await expectLater(
            client.get('/api/v5/account/balance'),
            throwsA(
              isA<OkxDataException>()
                  .having((error) => error.code, 'code', expectedCode)
                  .having((error) => error.statusCode, 'statusCode', 401)
                  .having(
                    (error) => error.message,
                    'message',
                    isNot(contains(fixture.$2)),
                  ),
            ),
          );
          client.dispose();
          storage.dispose();
        }
      },
    );
  });

  group('GREEN-001', () {
    test(
      'public GET uses fixed HTTPS origin without storage or backend session',
      () async {
        final adapter = _RecordingAdapter((_) => _WireResponse(200, _success));
        final storage = _FixtureStorage.withCredentials();
        final client = OkxDataClient(
          dio: Dio()..httpClientAdapter = adapter,
          secureStorage: storage,
        );

        final response = await client.get('/api/v5/market/ticker');

        expect(response.statusCode, 200);
        expect(
          adapter.requests.single.uri.toString(),
          'https://www.okx.com/api/v5/market/ticker',
        );
        expect(storage.readCount, 0);
        expect(_okxCredentialHeaderCount(adapter.requests.single.headers), 0);
        expect(adapter.requests.single.headers['Authorization'], isNull);
        client.dispose();
        storage.dispose();
      },
    );

    test(
      'public GET succeeds when no credential storage is provided',
      () async {
        final adapter = _RecordingAdapter((_) => _WireResponse(200, _success));
        final client = _client(adapter);

        final response = await client.get('/api/v5/public/instruments');

        expect(response.statusCode, 200);
        expect(
          adapter.requests.single.uri.toString(),
          'https://www.okx.com/api/v5/public/instruments',
        );
        client.dispose();
      },
    );

    test(
      'private GET signs the exact encoded query for the current generation',
      () async {
        final adapter = _RecordingAdapter((_) => _WireResponse(200, _success));
        final storage = _FixtureStorage.withCredentials();
        final coordinator = RequestCoordinator(
          minimumSpacing: Duration.zero,
          delay: (_) async {},
        );
        final client = OkxDataClient(
          dio: Dio()..httpClientAdapter = adapter,
          secureStorage: storage,
          requestCoordinator: coordinator,
        );

        final response = await client.get(
          '/api/v5/account/balance',
          queryParameters: const {'instId': 'BTC-USDT', 'detail': 'a b'},
        );

        final request = adapter.requests.single;
        final target = '/api/v5/account/balance?detail=a+b&instId=BTC-USDT';
        final timestamp = request.headers['OK-ACCESS-TIMESTAMP'] as String;
        final expectedSignature = base64Encode(
          Hmac(
            sha256,
            utf8.encode('fixture-secret'),
          ).convert(utf8.encode('${timestamp}GET$target')).bytes,
        );
        expect(response.statusCode, 200);
        expect(request.uri.toString(), 'https://www.okx.com$target');
        expect(request.method, 'GET');
        expect(request.data, isNull);
        expect(request.followRedirects, isFalse);
        expect(request.maxRedirects, 0);
        expect(request.headers['OK-ACCESS-KEY'], 'fixture-api-key');
        expect(request.headers['OK-ACCESS-SIGN'], expectedSignature);
        expect(request.headers['OK-ACCESS-PASSPHRASE'], 'fixture-passphrase');
        expect(request.headers['Authorization'], isNull);
        expect(request.extra['withCredentials'], isFalse);
        expect(storage.okxCredentialState.value.rotating, isFalse);
        client.dispose();
        storage.dispose();
      },
    );
  });
}

const _success = {'code': '0', 'data': <Object>[]};

OkxDataClient _client(
  HttpClientAdapter adapter, {
  SecureStorageHelper? storage,
}) => OkxDataClient(
  dio: Dio()..httpClientAdapter = adapter,
  secureStorage: storage,
);

int _okxCredentialHeaderCount(Map<String, dynamic> headers) => headers.keys
    .where((name) => name.toLowerCase().startsWith('ok-access-'))
    .length;

class _FixtureStorage extends SecureStorageHelper {
  _FixtureStorage({String? apiKey, String? secretKey, String? passphrase})
    : _apiKey = apiKey,
      _secretKey = secretKey,
      _passphrase = passphrase,
      super(const FlutterSecureStorage());

  String? _apiKey;
  String? _secretKey;
  String? _passphrase;
  int readCount = 0;

  factory _FixtureStorage.withCredentials() => _FixtureStorage(
    apiKey: 'fixture-api-key',
    secretKey: 'fixture-secret',
    passphrase: 'fixture-passphrase',
  );

  @override
  Future<String?> getOkxApiKey() async {
    readCount++;
    return _apiKey;
  }

  @override
  Future<String?> getOkxSecretKey() async {
    readCount++;
    return _secretKey;
  }

  @override
  Future<String?> getOkxPassphrase() async {
    readCount++;
    return _passphrase;
  }

  Future<void> rotate() => trackOkxCredentialMutation(() async {
    _apiKey = 'new-fixture-api-key';
    _secretKey = 'new-fixture-secret';
    _passphrase = 'new-fixture-passphrase';
  });
}

class _DelayedFixtureStorage extends _FixtureStorage {
  _DelayedFixtureStorage()
    : super(
        apiKey: 'fixture-api-key',
        secretKey: 'fixture-secret',
        passphrase: 'fixture-passphrase',
      );

  final Completer<void> allReadsStarted = Completer<void>();
  final Completer<void> releaseReads = Completer<void>();
  int _readCount = 0;

  Future<String?> _read(String value) async {
    _readCount++;
    if (_readCount == 3) allReadsStarted.complete();
    await releaseReads.future;
    return value;
  }

  @override
  Future<String?> getOkxApiKey() => _read('fixture-api-key');

  @override
  Future<String?> getOkxSecretKey() => _read('fixture-secret');

  @override
  Future<String?> getOkxPassphrase() => _read('fixture-passphrase');
}

class _WireResponse {
  const _WireResponse(this.statusCode, this.body, {this.headers = const {}});

  final int statusCode;
  final Object body;
  final Map<String, List<String>> headers;
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.handler);

  final _WireResponse Function(RequestOptions options) handler;
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
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        ...response.headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _PendingAdapter implements HttpClientAdapter {
  final Completer<RequestOptions> requestStarted = Completer<RequestOptions>();
  final Completer<ResponseBody> _pending = Completer<ResponseBody>();
  int requestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requestCount++;
    if (!requestStarted.isCompleted) requestStarted.complete(options);
    return _pending.future;
  }

  void reply(_WireResponse response) {
    _pending.complete(
      ResponseBody.fromString(
        jsonEncode(response.body),
        response.statusCode,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
          ...response.headers,
        },
      ),
    );
  }

  void fail(Object error) => _pending.completeError(error);

  @override
  void close({bool force = false}) {}
}

class _FirstPendingThenRecordingAdapter implements HttpClientAdapter {
  final Completer<void> firstStarted = Completer<void>();
  final Completer<ResponseBody> _firstResponse = Completer<ResponseBody>();
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    if (requests.length == 1) {
      firstStarted.complete();
      return _firstResponse.future;
    }
    return Future<ResponseBody>.value(
      ResponseBody.fromString(
        jsonEncode(_success),
        200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        },
      ),
    );
  }

  void replyFirst(_WireResponse response) {
    _firstResponse.complete(
      ResponseBody.fromString(
        jsonEncode(response.body),
        response.statusCode,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
          ...response.headers,
        },
      ),
    );
  }

  @override
  void close({bool force = false}) {}
}

class _MultiPendingAdapter implements HttpClientAdapter {
  final Completer<void> firstStarted = Completer<void>();
  final Completer<void> secondStarted = Completer<void>();
  final List<RequestOptions> requests = <RequestOptions>[];
  final List<Completer<ResponseBody>> _pending = <Completer<ResponseBody>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    final requestIndex = requests.length - 1;
    if (requestIndex == 0) firstStarted.complete();
    if (requestIndex == 1) secondStarted.complete();
    final response = Completer<ResponseBody>();
    _pending.add(response);
    cancelFuture?.then((_) {
      if (!response.isCompleted) {
        response.completeError(
          DioException(requestOptions: options, type: DioExceptionType.cancel),
        );
      }
    });
    return response.future;
  }

  void reply(int requestIndex, _WireResponse response) {
    _pending[requestIndex].complete(
      ResponseBody.fromString(
        jsonEncode(response.body),
        response.statusCode,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
          ...response.headers,
        },
      ),
    );
  }

  @override
  void close({bool force = false}) {}
}
