import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/network/backend_data_client.dart';
import 'package:trading_balance_f/core/network/backend_data_session.dart';
import 'package:trading_balance_f/features/orders/data/trade_api_client.dart';
import 'package:trading_balance_f/features/portfolio/data/risk/risk_repository.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_models.dart';

void main() {
  test(
    'backend session changes invalidate account config cache by generation',
    () async {
      final session = BackendDataSession(initialSession: _session('token-a'));
      final adapter = _BackendAdapter();
      final client = _client(adapter);
      final repository = RiskRepository(
        client.dio,
        backendSession: session,
        environment: 'test',
      );

      final first = await repository.getAccountConfig();
      expect(first.uid, 'account-a');
      session.update(_session('token-b'));
      final second = await repository.getAccountConfig();

      expect(second.uid, 'account-b');
      expect(adapter.configRequests, 2);
      expect(
        adapter.requests.map((request) => request.uri.path),
        everyElement('/v1/data/account/config'),
      );
      expect(
        adapter.requests.map((request) => request.headers['Authorization']),
        <String?>['Bearer token-a', 'Bearer token-b'],
      );

      await repository.dispose();
      client.close(force: true);
      session.dispose();
    },
  );

  test(
    'expired session is checked before a cached private response is returned',
    () async {
      final expiresAt = DateTime.now().toUtc().add(
        const Duration(milliseconds: 300),
      );
      final session = BackendDataSession(
        initialSession: _session('expiring-token', expiresAt: expiresAt),
      );
      final adapter = _BackendAdapter();
      final client = _client(adapter);
      final repository = RiskRepository(
        client.dio,
        backendSession: session,
        environment: 'test',
      );
      await repository.getAccountConfig();
      final generation = session.generation;

      while (DateTime.now().toUtc().isBefore(
        expiresAt.add(const Duration(milliseconds: 1)),
      )) {
        // Keep the timer callback queued so this entrypoint exercises the
        // synchronous expiry check before consulting its warm cache.
      }
      expect(session.current, isNull);
      expect(session.generation, generation);

      await expectLater(
        repository.getAccountConfig(),
        throwsA(
          isA<RiskRepositoryException>()
              .having((error) => error.statusCode, 'statusCode', 401)
              .having(
                (error) => error.credentialFailure,
                'credentialFailure',
                true,
              ),
        ),
      );
      expect(session.generation, greaterThan(generation));
      expect(adapter.configRequests, 1);

      await repository.dispose();
      client.close(force: true);
      session.dispose();
    },
  );

  test(
    'private 401 remains invalid and expires only the current backend session',
    () async {
      final session = BackendDataSession(
        initialSession: _session('unauthorized-token'),
      );
      final adapter = _BackendAdapter(unauthorizedPositions: true);
      final client = _client(
        adapter,
        onUnauthorized: (current, generation, expected) {
          if (current.matches(generation, expected)) current.update(null);
        },
      );
      final repository = RiskRepository(
        client.dio,
        backendSession: session,
        environment: 'test',
      );

      final selection = await repository.loadPosition();

      expect(selection.status, RiskEligibility.invalid);
      expect(selection.status, isNot(RiskEligibility.empty));
      expect(selection.quality.status, RiskQualityStatus.error);
      expect(repository.lastSelectionFailure?.statusCode, 401);
      expect(repository.lastSelectionFailure?.credentialFailure, isTrue);
      expect(session.current, isNull);
      expect(adapter.positionRequests, 1);

      await repository.dispose();
      client.close(force: true);
      session.dispose();
    },
  );
}

BackendDataClient _client(
  _BackendAdapter adapter, {
  BackendDataUnauthorizedHandler? onUnauthorized,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://backend.test'))
    ..httpClientAdapter = adapter;
  return BackendDataClient(
    dio: dio,
    baseUrl: 'https://backend.test',
    onUnauthorized: onUnauthorized,
  );
}

TradeSession _session(String token, {DateTime? expiresAt}) => TradeSession(
  bearerToken: token,
  accountIdentifier: 'risk-test-account',
  expiresAt:
      expiresAt ?? DateTime.now().toUtc().add(const Duration(minutes: 10)),
);

class _BackendAdapter implements HttpClientAdapter {
  _BackendAdapter({this.unauthorizedPositions = false});

  final bool unauthorizedPositions;
  final List<RequestOptions> requests = <RequestOptions>[];
  int configRequests = 0;
  int positionRequests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.uri.path == '/v1/data/account/config') {
      configRequests++;
      final bearer = options.headers['Authorization']?.toString();
      final account = bearer == 'Bearer token-a' ? 'account-a' : 'account-b';
      return _body(<String, dynamic>{
        'code': '0',
        'data': <Map<String, dynamic>>[
          <String, dynamic>{'uid': account, 'mgnIsoMode': 'auto_transfers_ccy'},
        ],
      });
    }
    if (options.uri.path == '/v1/data/account/positions') {
      positionRequests++;
      if (unauthorizedPositions) {
        return _body(<String, dynamic>{
          'code': '401',
          'msg': 'unauthorized',
          'data': [],
        }, statusCode: 401);
      }
      return _body(<String, dynamic>{'code': '0', 'data': <dynamic>[]});
    }
    throw StateError('Unexpected backend route ${options.uri.path}');
  }

  ResponseBody _body(Object value, {int statusCode = 200}) =>
      ResponseBody.fromString(
        jsonEncode(value),
        statusCode,
        headers: <String, List<String>>{
          'content-type': <String>['application/json'],
        },
      );

  @override
  void close({bool force = false}) {}
}
