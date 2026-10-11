import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/network/backend_data_client.dart';
import 'package:trading_balance_f/core/session/connection_scope.dart';
import 'package:trading_balance_f/core/session/user_session.dart';

void main() {
  const connectionA = 'conn_demo_001';
  const connectionB = 'conn_demo_002';

  UserSession session({
    String userId = 'user-a',
    String sessionId = 'session-a',
    String? token = 'opaque-a',
    String mode = 'ordinary',
    DateTime? stepUpUntil,
  }) => UserSession(
    userId: userId,
    username: userId,
    sessionId: sessionId,
    mode: mode,
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    stepUpUntil: stepUpUntil,
    bearerToken: token,
    csrfToken: 'csrf-a',
  );

  ConnectionScope select(
    ConnectionScopeStore store,
    UserSession owner,
    String id,
  ) => store.select(
    session: owner,
    connectionId: id,
    exchange: 'OKX',
    environment: 'demo',
    region: 'global',
    product: 'SWAP',
    credentialVersion: 1,
    permissionVersion: 2,
  )!;

  test(
    'native private v2 read carries opaque bearer and transport marker',
    () async {
      final adapter = _RecordingAdapter((_) => _success({'data': []}));
      final backend = _backend(adapter);
      final active = session(
        stepUpUntil: DateTime.now().add(const Duration(minutes: 5)),
      );
      final sessions = UserSessionStore(initialSession: active);
      final scopes = ConnectionScopeStore();
      final scope = select(scopes, active, connectionA);

      final response = await backend.requestV2(
        'GET',
        '/v2/connections/$connectionA/positions',
        queryParameters: const {'product': 'SWAP'},
        sessionStore: sessions,
        scopeStore: scopes,
        expectedScope: scope,
      );

      expect(response.data, {'data': []});
      expect(adapter.requests, hasLength(1));
      final request = adapter.requests.single;
      expect(
        request.uri.path,
        '/gateway/v2/connections/$connectionA/positions',
      );
      expect(request.headers['Authorization'], 'Bearer opaque-a');
      expect(request.headers['X-Session-Transport'], 'bearer');
      expect(request.headers['X-CSRF-Token'], isNull);
      sessions.dispose();
      scopes.dispose();
    },
  );

  test(
    'restricted sessions and mismatched product fail before transport',
    () async {
      final adapter = _RecordingAdapter((_) => _success({'data': []}));
      final backend = _backend(adapter);
      final restricted = session(mode: 'enrollment');
      final sessions = UserSessionStore(initialSession: restricted);
      final scopes = ConnectionScopeStore();

      await expectLater(
        backend.requestV2('GET', '/v2/connections', sessionStore: sessions),
        throwsA(
          isA<BackendDataException>().having(
            (error) => error.code,
            'code',
            'restricted_session',
          ),
        ),
      );
      sessions.update(session());
      final scope = select(scopes, sessions.current!, connectionA);
      await expectLater(
        backend.requestV2(
          'GET',
          '/v2/connections/$connectionA/positions',
          queryParameters: const {'product': 'MARGIN'},
          sessionStore: sessions,
          scopeStore: scopes,
          expectedScope: scope,
        ),
        throwsA(
          isA<BackendDataException>().having(
            (error) => error.code,
            'code',
            'scope_changed',
          ),
        ),
      );
      expect(adapter.requests, isEmpty);
      sessions.dispose();
      scopes.dispose();
    },
  );

  test('a switched account fence rejects an in-flight success', () async {
    final entered = Completer<void>();
    final finish = Completer<_WireResponse>();
    final adapter = _RecordingAdapter((_) {
      if (!entered.isCompleted) entered.complete();
      return finish.future;
    });
    final backend = _backend(adapter);
    final active = session();
    final sessions = UserSessionStore(initialSession: active);
    final scopes = ConnectionScopeStore();
    final oldScope = select(scopes, active, connectionA);
    final request = backend.requestV2(
      'GET',
      '/v2/connections/$connectionA/positions',
      queryParameters: const {'product': 'SWAP'},
      sessionStore: sessions,
      scopeStore: scopes,
      expectedScope: oldScope,
    );
    await entered.future;
    select(scopes, active, connectionB);
    finish.complete(
      _success({
        'data': [
          {'positionId': 'old'},
        ],
      }),
    );

    await expectLater(
      request,
      throwsA(
        isA<BackendDataException>().having(
          (error) => error.code,
          'code',
          'scope_changed',
        ),
      ),
    );
    sessions.dispose();
    scopes.dispose();
  });

  test(
    'late 401 from the old account cannot expire the current selection',
    () async {
      final entered = Completer<void>();
      final finish = Completer<_WireResponse>();
      var unauthorizedCalls = 0;
      final adapter = _RecordingAdapter((_) {
        if (!entered.isCompleted) entered.complete();
        return finish.future;
      });
      final backend = BackendDataClient(
        dio: Dio()..httpClientAdapter = adapter,
        baseUrl: 'https://data.example/gateway',
        isWeb: false,
        onV2Unauthorized: (_, _, _) => unauthorizedCalls++,
      );
      final active = session();
      final sessions = UserSessionStore(initialSession: active);
      final scopes = ConnectionScopeStore();
      final oldScope = select(scopes, active, connectionA);
      final request = backend.requestV2(
        'GET',
        '/v2/connections/$connectionA/positions',
        queryParameters: const {'product': 'SWAP'},
        sessionStore: sessions,
        scopeStore: scopes,
        expectedScope: oldScope,
      );
      await entered.future;
      select(scopes, active, connectionB);
      finish.complete(const _WireResponse(401, {'message': 'expired'}));

      await expectLater(
        request,
        throwsA(
          isA<BackendDataException>().having(
            (error) => error.code,
            'code',
            'scope_changed',
          ),
        ),
      );
      expect(unauthorizedCalls, 0);
      expect(sessions.current?.sessionId, 'session-a');
      sessions.dispose();
      scopes.dispose();
    },
  );

  test('detached scope is reserved for owned operation results', () async {
    final adapter = _RecordingAdapter((_) => _success({'status': 'UNKNOWN'}));
    final backend = _backend(adapter);
    final active = session();
    final sessions = UserSessionStore(initialSession: active);
    final scopes = ConnectionScopeStore();
    final scope = select(scopes, active, connectionA);

    await expectLater(
      backend.requestV2(
        'GET',
        '/v2/connections/$connectionA/positions',
        queryParameters: const {'product': 'SWAP'},
        sessionStore: sessions,
        scopeStore: scopes,
        expectedScope: scope,
        allowDetachedScope: true,
      ),
      throwsA(isA<BackendDataException>()),
    );
    expect(adapter.requests, isEmpty);

    await backend.requestV2(
      'GET',
      '/v2/connections/$connectionA/actions/op_demo_001',
      sessionStore: sessions,
      scopeStore: scopes,
      expectedScope: scope,
      allowDetachedScope: true,
    );
    expect(adapter.requests, hasLength(1));
    sessions.dispose();
    scopes.dispose();
  });

  test(
    'exchange-specific credential headers fail at the final guard',
    () async {
      final adapter = _RecordingAdapter((_) => _success({'data': []}));
      final backend = _backend(adapter);
      final active = session();
      final sessions = UserSessionStore(initialSession: active);
      final scopes = ConnectionScopeStore();
      final scope = select(scopes, active, connectionA);
      backend.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            options.headers['x-mbx-apikey'] = 'must-not-forward';
            handler.next(options);
          },
        ),
      );

      await expectLater(
        backend.requestV2(
          'GET',
          '/v2/connections/$connectionA/positions',
          queryParameters: const {'product': 'SWAP'},
          sessionStore: sessions,
          scopeStore: scopes,
          expectedScope: scope,
        ),
        throwsA(isA<BackendDataException>()),
      );
      expect(adapter.requests, isEmpty);
      sessions.dispose();
      scopes.dispose();
    },
  );

  test(
    'expired step-up during an interceptor blocks the final action send',
    () async {
      final entered = Completer<void>();
      final adapter = _RecordingAdapter((_) => _success({'operation': {}}));
      final backend = _backend(adapter);
      final active = session(
        stepUpUntil: DateTime.now().add(const Duration(milliseconds: 300)),
      );
      final sessions = UserSessionStore(initialSession: active);
      final scopes = ConnectionScopeStore();
      final scope = select(scopes, active, connectionA);
      backend.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            if (!entered.isCompleted) entered.complete();
            await Future<void>.delayed(const Duration(milliseconds: 450));
            handler.next(options);
          },
        ),
      );

      final request = backend.requestV2(
        'POST',
        '/v2/connections/$connectionA/actions/prepare',
        body: const {
          'action': 'close_position',
          'targetIdentity': {
            'instrumentType': 'SWAP',
            'instrumentId': 'BTC-USDT-SWAP',
            'positionSide': 'net',
            'marginMode': 'cross',
          },
        },
        sessionStore: sessions,
        scopeStore: scopes,
        expectedScope: scope,
      );
      await entered.future;
      await expectLater(
        request,
        throwsA(
          isA<BackendDataException>().having(
            (error) => error.code,
            'code',
            'step_up_required',
          ),
        ),
      );
      expect(adapter.requests, isEmpty);
      sessions.dispose();
      scopes.dispose();
    },
  );

  test('a later interceptor cannot append an unregistered URI query', () async {
    final adapter = _RecordingAdapter((_) => _success({'data': []}));
    final backend = _backend(adapter);
    final active = session();
    final sessions = UserSessionStore(initialSession: active);
    final scopes = ConnectionScopeStore();
    final scope = select(scopes, active, connectionA);
    backend.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.path = '${options.path}?unexpected=1';
          handler.next(options);
        },
      ),
    );

    await expectLater(
      backend.requestV2(
        'GET',
        '/v2/connections/$connectionA/positions',
        queryParameters: const {'product': 'SWAP'},
        sessionStore: sessions,
        scopeStore: scopes,
        expectedScope: scope,
      ),
      throwsA(isA<BackendDataException>()),
    );
    expect(adapter.requests, isEmpty);
    sessions.dispose();
    scopes.dispose();
  });

  test(
    'an earlier interceptor cannot redirect v2 to a foreign destination',
    () async {
      final adapter = _RecordingAdapter((_) => _success({'instruments': []}));
      final backend = _backend(adapter);
      backend.dio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (options, handler) {
            options.baseUrl = 'https://foreign.example';
            handler.next(options);
          },
        ),
      );

      await expectLater(
        backend.requestV2('GET', '/v2/session'),
        throwsA(
          isA<BackendDataException>().having(
            (error) => error.code,
            'code',
            'destination_forbidden',
          ),
        ),
      );
      expect(adapter.requests, isEmpty);
    },
  );

  test(
    'registered GET routes reject bodies before and after interceptors',
    () async {
      final adapter = _RecordingAdapter((_) => _success({'connections': []}));
      final backend = _backend(adapter);
      final active = session();
      final sessions = UserSessionStore(initialSession: active);
      final scopes = ConnectionScopeStore();
      final scope = select(scopes, active, connectionA);

      await expectLater(
        backend.requestV2(
          'GET',
          '/v2/connections/$connectionA/positions',
          body: const {'apiKey': 'never-send'},
          queryParameters: const {'product': 'SWAP'},
          sessionStore: sessions,
          scopeStore: scopes,
          expectedScope: scope,
        ),
        throwsA(isA<BackendDataException>()),
      );
      expect(adapter.requests, isEmpty);

      backend.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            options.data = const {'apiSecret': 'never-send'};
            handler.next(options);
          },
        ),
      );
      await expectLater(
        backend.requestV2(
          'GET',
          '/v2/connections/$connectionA/positions',
          queryParameters: const {'product': 'SWAP'},
          sessionStore: sessions,
          scopeStore: scopes,
          expectedScope: scope,
        ),
        throwsA(isA<BackendDataException>()),
      );
      expect(adapter.requests, isEmpty);
      sessions.dispose();
      scopes.dispose();
    },
  );

  test(
    'detached operation 401 cannot expire after switching selection',
    () async {
      final entered = Completer<void>();
      final finish = Completer<_WireResponse>();
      var unauthorizedCalls = 0;
      final adapter = _RecordingAdapter((_) {
        if (!entered.isCompleted) entered.complete();
        return finish.future;
      });
      final backend = BackendDataClient(
        dio: Dio()..httpClientAdapter = adapter,
        baseUrl: 'https://data.example/gateway',
        isWeb: false,
        onV2Unauthorized: (_, _, _) => unauthorizedCalls++,
      );
      final active = session();
      final sessions = UserSessionStore(initialSession: active);
      final scopes = ConnectionScopeStore();
      final scopeA = select(scopes, active, connectionA);
      final request = backend.requestV2(
        'GET',
        '/v2/connections/$connectionA/actions/op_demo_001',
        sessionStore: sessions,
        scopeStore: scopes,
        expectedScope: scopeA,
        allowDetachedScope: true,
      );
      await entered.future;
      select(scopes, active, connectionB);
      finish.complete(const _WireResponse(401, {'message': 'expired'}));

      await expectLater(request, throwsA(isA<BackendDataException>()));
      expect(unauthorizedCalls, 0);
      expect(sessions.current?.sessionId, 'session-a');
      sessions.dispose();
      scopes.dispose();
    },
  );

  test(
    'production request allowlist blocks old private v1 and unknown routes',
    () async {
      final adapter = _RecordingAdapter((_) => _success({}));
      final backend = _backend(adapter);

      await expectLater(
        backend.requestV2('GET', '/v1/account/balance'),
        throwsA(
          isA<BackendDataException>().having(
            (error) => error.code,
            'code',
            'route_not_registered',
          ),
        ),
      );
      await expectLater(
        backend.requestV2('DELETE', '/v2/connections/$connectionA'),
        throwsA(isA<BackendDataException>()),
      );
      expect(adapter.requests, isEmpty);
    },
  );

  test('strategy draft request uses an owned v2 connection route', () async {
    final adapter = _RecordingAdapter((_) => _success({'id': 'draft-1'}));
    final backend = _backend(adapter);
    final active = session();
    final sessions = UserSessionStore(initialSession: active);
    final scopes = ConnectionScopeStore();
    final scope = select(scopes, active, connectionA);

    await backend.requestV2(
      'POST',
      '/v2/connections/$connectionA/strategies/preview',
      body: const {
        'instrumentId': 'BTC-USDT-SWAP',
        'interval': '6Hutc',
        'direction': 'long',
      },
      sessionStore: sessions,
      scopeStore: scopes,
      expectedScope: scope,
    );

    expect(adapter.requests, hasLength(1));
    expect(
      adapter.requests.single.uri.path,
      '/gateway/v2/connections/$connectionA/strategies/preview',
    );
    expect(adapter.requests.single.headers['Authorization'], 'Bearer opaque-a');
    expect(adapter.requests.single.data, {
      'instrumentId': 'BTC-USDT-SWAP',
      'interval': '6Hutc',
      'direction': 'long',
    });
    sessions.dispose();
    scopes.dispose();
  });
}

BackendDataClient _backend(_RecordingAdapter adapter) => BackendDataClient(
  dio: Dio()..httpClientAdapter = adapter,
  baseUrl: 'https://data.example/gateway',
  isWeb: false,
);

_WireResponse _success(Object body) => _WireResponse(200, body);

class _WireResponse {
  const _WireResponse(this.statusCode, this.body);
  final int statusCode;
  final Object body;
}

class _RecordedRequest {
  const _RecordedRequest(this.uri, this.headers, this.data);
  final Uri uri;
  final Map<String, dynamic> headers;
  final Object? data;
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.handler);
  final FutureOr<_WireResponse> Function(RequestOptions) handler;
  final List<_RecordedRequest> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(
      _RecordedRequest(
        options.uri,
        Map<String, dynamic>.from(options.headers),
        options.data,
      ),
    );
    final response = await handler(options);
    return ResponseBody.fromString(
      jsonEncode(response.body),
      response.statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
