import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/network/backend_data_client.dart';
import 'package:trading_balance_f/core/network/backend_data_session.dart';
import 'package:trading_balance_f/features/orders/data/trade_api_client.dart';

void main() {
  TradeSession activeSession(String token) => TradeSession(
    bearerToken: token,
    accountIdentifier: 'account',
    expiresAt: DateTime.now().add(const Duration(minutes: 5)),
  );

  test('public reads need no login and preserve a backend base path', () async {
    final adapter = _RecordingAdapter((_) => _jsonResponse({'code': '0'}));
    final client = _client(adapter);

    await client.get(
      '/api/v5/market/ticker',
      queryParameters: {'instId': 'BTC-USDT'},
    );

    expect(adapter.requests, hasLength(1));
    expect(
      adapter.requests.single.uri.toString(),
      'https://data.example/gateway/v1/data/market/ticker?instId=BTC-USDT',
    );
    expect(adapter.requests.single.headers['Authorization'], isNull);
    expect(adapter.requests.single.followRedirects, isFalse);
  });

  test('private route without an active session sends zero requests', () async {
    final adapter = _RecordingAdapter((_) => _jsonResponse({'code': '0'}));
    final client = _client(adapter);
    final session = BackendDataSession();

    await expectLater(
      client.get('/api/v5/account/balance', session: session),
      throwsA(isA<BackendDataException>()),
    );

    expect(adapter.requests, isEmpty);
    session.dispose();
  });

  test('private route uses only the shared backend bearer header', () async {
    final adapter = _RecordingAdapter((_) => _jsonResponse({'code': '0'}));
    final client = _client(adapter);
    final session = BackendDataSession(
      initialSession: activeSession('test-token'),
    );

    await client.get('/api/v5/account/balance', session: session);

    expect(adapter.requests, hasLength(1));
    expect(
      adapter.requests.single.uri.path,
      '/gateway/v1/data/account/balance',
    );
    expect(
      adapter.requests.single.headers['Authorization'],
      'Bearer test-token',
    );
    expect(
      adapter.requests.single.headers.keys.where(
        (name) => name.toLowerCase().startsWith('ok-access-'),
      ),
      isEmpty,
    );
    session.dispose();
  });

  test(
    'private HTTP errors preserve status and Retry-After metadata',
    () async {
      final adapter = _RecordingAdapter(
        (_) => const _WireResponse(
          429,
          {'message': 'limited'},
          headers: {
            'retry-after': ['120'],
          },
        ),
      );
      final client = _client(adapter);
      final session = BackendDataSession(
        initialSession: activeSession('test-token'),
      );

      await expectLater(
        client.get('/api/v5/account/balance', session: session),
        throwsA(
          isA<BackendDataException>()
              .having((error) => error.statusCode, 'statusCode', 429)
              .having((error) => error.retryAfter, 'retryAfter', '120'),
        ),
      );

      expect(adapter.requests, hasLength(1));
      session.dispose();
    },
  );

  test(
    'unconfigured, insecure, absolute and unknown routes fail closed',
    () async {
      final adapter = _RecordingAdapter((_) => _jsonResponse({'code': '0'}));
      final insecure = BackendDataClient(
        dio: _dio(adapter),
        baseUrl: 'http://data.example',
      );
      final unconfigured = BackendDataClient(dio: _dio(adapter), baseUrl: ' ');

      expect(insecure.isConfigured, isFalse);
      expect(unconfigured.isConfigured, isFalse);
      await expectLater(
        insecure.get('/api/v5/market/ticker'),
        throwsA(isA<BackendDataException>()),
      );
      await expectLater(
        unconfigured.get('/api/v5/market/ticker'),
        throwsA(isA<BackendDataException>()),
      );

      final client = _client(adapter);
      await expectLater(
        client.get('https://evil.example/data'),
        throwsA(isA<BackendDataException>()),
      );
      await expectLater(
        client.get('/api/v5/account/config'),
        throwsA(isA<BackendDataException>()),
      );
      expect(adapter.requests, isEmpty);
    },
  );

  test(
    'exchange-auth headers are rejected before reaching the adapter',
    () async {
      final adapter = _RecordingAdapter((_) => _jsonResponse({'code': '0'}));
      final client = _client(adapter);

      await expectLater(
        client.dio.get<dynamic>(
          '/api/v5/market/ticker',
          options: Options(headers: {'OK-ACCESS-KEY': 'not-forwarded'}),
        ),
        throwsA(isA<DioException>()),
      );

      expect(adapter.requests, isEmpty);
    },
  );

  test(
    'a later interceptor cannot change the final backend destination',
    () async {
      final adapter = _RecordingAdapter((_) => _jsonResponse({'code': '0'}));
      final client = _client(adapter);
      final session = BackendDataSession(
        initialSession: activeSession('test-token'),
      );
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            options.baseUrl = 'https://foreign.example';
            handler.next(options);
          },
        ),
      );

      await expectLater(
        client.get('/api/v5/account/balance', session: session),
        throwsA(isA<BackendDataException>()),
      );

      expect(adapter.requests, isEmpty);
      session.dispose();
    },
  );

  test('a later interceptor cannot add exchange credential headers', () async {
    final adapter = _RecordingAdapter((_) => _jsonResponse({'code': '0'}));
    final client = _client(adapter);
    final session = BackendDataSession(
      initialSession: activeSession('test-token'),
    );
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.headers['ok-access-key'] = 'blocked';
          handler.next(options);
        },
      ),
    );

    await expectLater(
      client.get('/api/v5/account/balance', session: session),
      throwsA(isA<BackendDataException>()),
    );

    expect(adapter.requests, isEmpty);
    session.dispose();
  });

  test(
    'a later interceptor cannot replace the recorded backend bearer',
    () async {
      final adapter = _RecordingAdapter((_) => _jsonResponse({'code': '0'}));
      final client = _client(adapter);
      final session = BackendDataSession(
        initialSession: activeSession('test-token'),
      );
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            options.headers['Authorization'] = 'Bearer changed-token';
            handler.next(options);
          },
        ),
      );

      await expectLater(
        client.get('/api/v5/account/balance', session: session),
        throwsA(isA<BackendDataException>()),
      );

      expect(adapter.requests, isEmpty);
      session.dispose();
    },
  );

  test(
    'raw Dio fetch with a valid session cannot use a foreign destination',
    () async {
      final adapter = _RecordingAdapter((_) => _jsonResponse({'code': '0'}));
      final client = _client(adapter);
      final session = BackendDataSession(
        initialSession: activeSession('test-token'),
      );

      await expectLater(
        client.dio.fetch<dynamic>(
          RequestOptions(
            path: '/api/v5/account/balance',
            baseUrl: 'https://foreign.example',
            method: 'GET',
            extra: {BackendDataClient.sessionExtraKey: session},
          ),
        ),
        throwsA(isA<DioException>()),
      );

      expect(adapter.requests, isEmpty);
      session.dispose();
    },
  );

  test(
    'logout during a delayed later interceptor stops the final send',
    () async {
      final adapter = _RecordingAdapter((_) => _jsonResponse({'code': '0'}));
      final client = _client(adapter);
      final session = BackendDataSession(
        initialSession: activeSession('test-token'),
      );
      final laterInterceptorEntered = Completer<void>();
      final releaseInterceptor = Completer<void>();
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            laterInterceptorEntered.complete();
            await releaseInterceptor.future;
            handler.next(options);
          },
        ),
      );

      final result = client.get('/api/v5/account/balance', session: session);
      await laterInterceptorEntered.future;
      session.update(null);
      releaseInterceptor.complete();

      await expectLater(result, throwsA(isA<BackendDataException>()));
      expect(adapter.requests, isEmpty);
      session.dispose();
    },
  );

  test(
    'clearing mutable request extras cannot bypass response session fencing',
    () async {
      final adapter = _PendingAdapter();
      final client = _client(adapter);
      final session = BackendDataSession(
        initialSession: activeSession('test-token'),
      );
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            options.extra.clear();
            handler.next(options);
          },
        ),
      );

      final result = client.get('/api/v5/account/balance', session: session);
      final request = await adapter.requestStarted.future;
      session.update(null);
      adapter.reply(request, 200, {'code': '0', 'data': []});

      await expectLater(result, throwsA(isA<BackendDataException>()));
      expect(session.current, isNull);
      session.dispose();
    },
  );

  test('logout during an in-flight success rejects the response', () async {
    final adapter = _PendingAdapter();
    final client = _client(adapter);
    final session = BackendDataSession(
      initialSession: activeSession('old-token'),
    );
    final result = client.get('/api/v5/account/balance', session: session);
    final request = await adapter.requestStarted.future;
    session.update(null);
    adapter.reply(request, 200, {'code': '0', 'data': []});

    await expectLater(result, throwsA(isA<BackendDataException>()));
    expect(session.current, isNull);
    session.dispose();
  });

  test(
    'disposing the owner during an in-flight success rejects the response',
    () async {
      final adapter = _PendingAdapter();
      final client = _client(adapter);
      final session = BackendDataSession(
        initialSession: activeSession('old-token'),
      );
      final result = client.get('/api/v5/account/balance', session: session);
      final request = await adapter.requestStarted.future;
      session.dispose();
      adapter.reply(request, 200, {'code': '0', 'data': []});

      await expectLater(result, throwsA(isA<BackendDataException>()));
      expect(session.current, isNull);
    },
  );

  test(
    'a late 401 from an old generation cannot expire the new session',
    () async {
      final adapter = _PendingAdapter();
      var unauthorizedCalls = 0;
      final client = BackendDataClient(
        dio: _dio(adapter),
        baseUrl: 'https://data.example/gateway',
        onUnauthorized: (_, _, _) => unauthorizedCalls++,
      );
      final session = BackendDataSession(
        initialSession: activeSession('old-token'),
      );
      final result = client.get('/api/v5/account/balance', session: session);
      final request = await adapter.requestStarted.future;
      session.update(activeSession('new-token'));
      adapter.reply(request, 401, {'error': 'expired'});

      await expectLater(result, throwsA(isA<BackendDataException>()));
      expect(session.current?.bearerToken, 'new-token');
      expect(unauthorizedCalls, 0);
      session.dispose();
    },
  );
}

BackendDataClient _client(HttpClientAdapter adapter) => BackendDataClient(
  dio: _dio(adapter),
  baseUrl: 'https://data.example/gateway',
);

Dio _dio(HttpClientAdapter adapter) => Dio()..httpClientAdapter = adapter;

_WireResponse _jsonResponse(Object body) => _WireResponse(200, body);

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
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        ...response.headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _PendingAdapter implements HttpClientAdapter {
  final Completer<RequestOptions> requestStarted = Completer<RequestOptions>();
  final Map<RequestOptions, Completer<ResponseBody>> _pending = {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requestStarted.complete(options);
    final response = Completer<ResponseBody>();
    _pending[options] = response;
    return response.future;
  }

  void reply(RequestOptions options, int statusCode, Object body) {
    _pending
        .remove(options)!
        .complete(
          ResponseBody.fromString(
            jsonEncode(body),
            statusCode,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          ),
        );
  }

  @override
  void close({bool force = false}) {}
}
