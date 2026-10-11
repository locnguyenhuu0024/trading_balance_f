import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/network/backend_data_client.dart';
import 'package:trading_balance_f/core/session/connection_scope.dart';
import 'package:trading_balance_f/core/session/user_session.dart';
import 'package:trading_balance_f/features/connections/data/multi_user_api_client.dart';
import 'package:trading_balance_f/features/connections/domain/connection_models.dart';
import 'package:trading_balance_f/features/strategy/data/strategy_api_client.dart';

void main() {
  test(
    'normalized readers walk every cursor in one consistent snapshot',
    () async {
      final adapter = _PagingAdapter();
      final session = _session();
      final sessions = UserSessionStore(initialSession: session);
      final scopes = ConnectionScopeStore();
      final scope = scopes.select(
        session: session,
        connectionId: 'conn_demo_001',
        exchange: 'OKX',
        environment: 'demo',
        region: 'global',
        product: 'SWAP',
        credentialVersion: 1,
        permissionVersion: 1,
      )!;
      final client = MultiUserApiClient(
        backend: BackendDataClient(
          dio: Dio()..httpClientAdapter = adapter,
          baseUrl: 'https://data.example/gateway',
          isWeb: false,
        ),
        sessions: sessions,
        scopes: scopes,
        isWeb: false,
      );

      final result = await client.allBalances(scope);

      expect(result.page.rows.map((row) => row.asset), ['BTC', 'ETH']);
      expect(result.page.nextCursor, isNull);
      expect(adapter.cursors, [null, 'next-1']);
      sessions.dispose();
      scopes.dispose();
    },
  );

  test('normalized DTOs retain native units and contract metadata', () async {
    final responseBody = {
      'data': [
        {
          'exchange': 'OKX',
          'product': 'SWAP',
          'environment': 'demo',
          'region': 'global',
          'instrument': 'BTC-USDT-SWAP',
          'nativeQuantity': '100',
          'quantityUnit': null,
          'nativeAsset': 'USDT',
          'contractValue': '0.01',
          'contractValueUnit': 'BTC',
          'contractType': 'linear',
          'settlementAsset': 'USDT',
          'metadataVersion': 'contract-v4',
          'side': 'long',
        },
      ],
      'page': {'nextCursor': null},
      'dataMeta': _validMeta(),
    };
    final session = _session();
    final sessions = UserSessionStore(initialSession: session);
    final scopes = ConnectionScopeStore();
    final scope = scopes.select(
      session: session,
      connectionId: 'conn_demo_001',
      exchange: 'OKX',
      environment: 'demo',
      region: 'global',
      product: 'SWAP',
      credentialVersion: 1,
      permissionVersion: 1,
    )!;
    final client = MultiUserApiClient(
      backend: BackendDataClient(
        dio: Dio()..httpClientAdapter = _JsonAdapter(responseBody),
        baseUrl: 'https://data.example/gateway',
        isWeb: false,
      ),
      sessions: sessions,
      scopes: scopes,
      isWeb: false,
    );

    final result = await client.positions(scope);
    final row = result.page.rows.single;
    expect(row.nativeQuantity, '100');
    expect(row.quantityUnit, isNull);
    expect(row.nativeAsset, 'USDT');
    expect(row.contractValue, '0.01');
    expect(row.contractValueUnit, 'BTC');
    expect(row.contractType, 'linear');
    expect(row.settlementAsset, 'USDT');
    expect(row.metadataVersion, 'contract-v4');
    sessions.dispose();
    scopes.dispose();
  });

  test('order wire DTO retains quote-budget and fill-unit semantics', () async {
    final session = _session();
    final sessions = UserSessionStore(initialSession: session);
    final scopes = ConnectionScopeStore();
    final scope = scopes.select(
      session: session,
      connectionId: 'conn_demo_001',
      exchange: 'OKX',
      environment: 'demo',
      region: 'global',
      product: 'SPOT',
      credentialVersion: 1,
      permissionVersion: 1,
    )!;
    final client = MultiUserApiClient(
      backend: BackendDataClient(
        dio: Dio()
          ..httpClientAdapter = _JsonAdapter({
            'data': [
              {
                'exchange': 'OKX',
                'product': 'SPOT',
                'environment': 'demo',
                'region': 'global',
                'orderId': 'order-quote-buy',
                'instrument': 'BTC-USDT',
                'side': 'buy',
                'orderType': 'market',
                'status': 'partially_filled',
                'nativeQuantity': '100',
                'quantityUnit': null,
                'nativeAsset': 'USDT',
                'filledQuantity': '0.001',
                'filledQuantityUnit': 'base',
                'clientOrderId': 'client-a-17',
                'metadataVersion': 'spot-v4',
              },
            ],
            'page': {'nextCursor': null},
            'dataMeta': _validMeta(),
          }),
        baseUrl: 'https://data.example/gateway',
        isWeb: false,
      ),
      sessions: sessions,
      scopes: scopes,
      isWeb: false,
    );

    final row = (await client.orders(scope)).page.rows.single;
    expect(row.nativeQuantity, '100');
    expect(row.quantityUnit, isNull);
    expect(row.nativeAsset, 'USDT');
    expect(row.filledQuantity, '0.001');
    expect(row.filledQuantityUnit, 'base');
    expect(row.clientOrderId, 'client-a-17');
    expect(row.metadataVersion, 'spot-v4');
    sessions.dispose();
    scopes.dispose();
  });

  test(
    'prepared action binds wire identity and server confirmation summary',
    () async {
      final identity = {
        'instrumentType': 'SWAP',
        'instrumentId': 'BTC-USDT-SWAP',
        'positionSide': 'long',
        'marginMode': 'cross',
      };
      final response = _preparedAction(identity: identity);
      final session = _session().withStepUp(
        DateTime.now().add(const Duration(minutes: 5)),
      );
      final sessions = UserSessionStore(initialSession: session);
      final scopes = ConnectionScopeStore();
      final scope = _scope(scopes, session);
      final adapter = _JsonAdapter({'operation': response});
      final client = _client(adapter, sessions, scopes);

      final operation = await client.prepareAction(
        scope,
        action: 'close_position',
        targetIdentity: identity,
      );

      expect(operation['operationId'], 'operation_0001');
      expect(connectionJsonMap(operation['summary'])['currentSize'], '2');
      sessions.dispose();
      scopes.dispose();
    },
  );

  test(
    'prepared action rejects foreign identity and incomplete confirmation',
    () async {
      final requested = {
        'instrumentType': 'SWAP',
        'instrumentId': 'BTC-USDT-SWAP',
        'positionSide': 'long',
        'marginMode': 'cross',
      };
      final fixtures = [
        _preparedAction(identity: requested, currentSize: null),
        {
          ..._preparedAction(identity: requested),
          'connectionId': 'conn_other_001',
        },
        {..._preparedAction(identity: requested), 'product': 'SPOT'},
        {..._preparedAction(identity: requested), 'action': 'cancel_order'},
        {..._preparedAction(identity: requested), 'operationId': 'bad'},
        {
          ..._preparedAction(identity: requested),
          'targets': [
            {'index': 1, 'status': 'PREPARED'},
          ],
        },
        {
          ..._preparedAction(identity: requested),
          'summary': {
            'action': 'close_position',
            'identity': {...requested, 'instrumentId': 'ETH-USDT-SWAP'},
            'direction': 'long',
            'currentSize': '2',
          },
        },
      ];
      for (final fixture in fixtures) {
        final session = _session().withStepUp(
          DateTime.now().add(const Duration(minutes: 5)),
        );
        final sessions = UserSessionStore(initialSession: session);
        final scopes = ConnectionScopeStore();
        final scope = _scope(scopes, session);
        final client = _client(
          _JsonAdapter({'operation': fixture}),
          sessions,
          scopes,
        );

        await expectLater(
          client.prepareAction(
            scope,
            action: 'close_position',
            targetIdentity: requested,
          ),
          throwsA(isA<BackendDataException>()),
        );
        sessions.dispose();
        scopes.dispose();
      }
    },
  );

  test(
    'operation result preserves target attempt proof and rejects foreign operation',
    () async {
      final session = _session();
      final sessions = UserSessionStore(initialSession: session);
      final scopes = ConnectionScopeStore();
      final scope = _scope(scopes, session);
      final response = {
        'operationId': 'operation_0001',
        'connectionId': 'conn_demo_001',
        'product': 'SWAP',
        'action': 'close_position',
        'status': 'SENDING',
        'targets': [
          {
            'index': 0,
            'status': 'ATTEMPT_STARTED',
            'result': {'positionVerified': false},
          },
        ],
        'result': null,
      };
      final valid = await _client(
        _JsonAdapter({'operation': response}),
        sessions,
        scopes,
      ).operationResult(scope, 'operation_0001', 'close_position');
      final target = connectionJsonMap((valid['targets'] as List).single);
      expect(target['status'], 'ATTEMPT_STARTED');
      expect(connectionJsonMap(target['result'])['positionVerified'], isFalse);

      for (final bad in [
        {...response, 'operationId': 'operation_foreign'},
        {...response, 'connectionId': 'conn_other_001'},
        {
          ...response,
          'targets': [
            {'index': 1, 'status': 'ATTEMPT_STARTED'},
          ],
        },
      ]) {
        await expectLater(
          _client(
            _JsonAdapter({'operation': bad}),
            sessions,
            scopes,
          ).operationResult(scope, 'operation_0001', 'close_position'),
          throwsA(isA<BackendDataException>()),
        );
      }
      sessions.dispose();
      scopes.dispose();
    },
  );

  test(
    'non-empty normalized pages preserve OKX and Binance row scope',
    () async {
      for (final exchange in ['OKX', 'BINANCE']) {
        final product = exchange == 'OKX' ? 'SWAP' : 'SPOT';
        final responseBody = {
          'data': [
            {
              'exchange': exchange,
              'product': product,
              'environment': 'demo',
              'region': 'global',
              'asset': 'USDT',
              'available': '1.2300',
              'locked': null,
              'total': '1.2300',
              'unit': 'USDT',
            },
          ],
          'page': {'nextCursor': null},
          'dataMeta': _validMeta(),
        };
        final adapter = _JsonAdapter(responseBody);
        final session = _session();
        final sessions = UserSessionStore(initialSession: session);
        final scopes = ConnectionScopeStore();
        final scope = scopes.select(
          session: session,
          connectionId: 'conn_demo_001',
          exchange: exchange,
          environment: 'demo',
          region: 'global',
          product: product,
          credentialVersion: 1,
          permissionVersion: 1,
        )!;
        final client = MultiUserApiClient(
          backend: BackendDataClient(
            dio: Dio()..httpClientAdapter = adapter,
            baseUrl: 'https://data.example/gateway',
            isWeb: false,
          ),
          sessions: sessions,
          scopes: scopes,
          isWeb: false,
        );

        final page = await client.balances(scope);
        expect(page.page.rows, hasLength(1));
        expect(page.page.rows.single.exchange, exchange);
        expect(page.page.rows.single.product, product);
        expect(page.page.rows.single.total, '1.2300');
        sessions.dispose();
        scopes.dispose();
      }
    },
  );

  test(
    'private pages reject missing, malformed, and unproven freshness',
    () async {
      final malformed = <Map<String, Object?>>[
        {'stale': false, 'complete': true},
        {
          'fetchedAt': 'not-a-date',
          'asOf': '2026-10-11T02:59:58Z',
          'snapshotExpiresAt': '2026-10-11T03:05:00Z',
          'stale': false,
          'complete': true,
        },
        {
          'fetchedAt': '2026-10-11T03:00:00Z',
          'asOf': '2026-10-11T02:59:58Z',
          'snapshotExpiresAt': '2026-10-11T03:05:00Z',
          'complete': true,
        },
        {
          'fetchedAt': '2026-10-11T03:00:00Z',
          'asOf': '2026-10-11T02:59:58Z',
          'snapshotExpiresAt': '2026-10-11T02:59:59Z',
          'stale': false,
          'complete': true,
        },
      ];

      for (final meta in malformed) {
        final session = _session();
        final sessions = UserSessionStore(initialSession: session);
        final scopes = ConnectionScopeStore();
        final scope = scopes.select(
          session: session,
          connectionId: 'conn_demo_001',
          exchange: 'OKX',
          environment: 'demo',
          region: 'global',
          product: 'SWAP',
          credentialVersion: 1,
          permissionVersion: 1,
        )!;
        final client = MultiUserApiClient(
          backend: BackendDataClient(
            dio: Dio()
              ..httpClientAdapter = _JsonAdapter({
                'data': [],
                'page': {'nextCursor': null},
                'dataMeta': meta,
              }),
            baseUrl: 'https://data.example/gateway',
            isWeb: false,
          ),
          sessions: sessions,
          scopes: scopes,
          isWeb: false,
        );

        await expectLater(
          client.balances(scope),
          throwsA(isA<BackendDataException>()),
        );
        sessions.dispose();
        scopes.dispose();
      }
    },
  );

  test('owned strategy list accepts a fresh complete snapshot', () async {
    final session = _session();
    final sessions = UserSessionStore(initialSession: session);
    final scopes = ConnectionScopeStore();
    final scope = _scope(scopes, session);
    final client = _client(
      _JsonAdapter({
        'strategies': [
          {'id': 'draft-known-1', 'status': 'DRAFT'},
        ],
        'page': {'nextCursor': null},
        'dataMeta': _validMeta(),
      }),
      sessions,
      scopes,
    );

    final strategies = await OwnedStrategyApi(
      client: client,
      scope: scope,
    ).listStrategies(session.sessionId);

    expect(strategies, hasLength(1));
    expect(strategies.single['id'], 'draft-known-1');
    expect(strategies.single['status'], 'DRAFT');
    sessions.dispose();
    scopes.dispose();
  });

  test(
    'owned strategy list rejects stale, incomplete and expired snapshots',
    () async {
      for (final meta in [
        {..._validMeta(), 'stale': true},
        {..._validMeta(), 'complete': false},
        {
          ..._validMeta(),
          'asOf': DateTime.now()
              .toUtc()
              .subtract(const Duration(minutes: 2))
              .toIso8601String(),
          'snapshotExpiresAt': DateTime.now()
              .toUtc()
              .subtract(const Duration(seconds: 1))
              .toIso8601String(),
        },
      ]) {
        final session = _session();
        final sessions = UserSessionStore(initialSession: session);
        final scopes = ConnectionScopeStore();
        final scope = _scope(scopes, session);
        final client = _client(
          _JsonAdapter({
            'strategies': <Object>[],
            'page': {'nextCursor': null},
            'dataMeta': meta,
          }),
          sessions,
          scopes,
        );

        await expectLater(
          OwnedStrategyApi(
            client: client,
            scope: scope,
          ).listStrategies(session.sessionId),
          throwsA(
            isA<StrategyApiException>().having(
              (error) => error.code,
              'code',
              'strategy_snapshot_unavailable',
            ),
          ),
        );
        sessions.dispose();
        scopes.dispose();
      }
    },
  );
}

Map<String, Object?> _validMeta() {
  final now = DateTime.now().toUtc();
  return {
    'fetchedAt': now.toIso8601String(),
    'asOf': now.subtract(const Duration(seconds: 1)).toIso8601String(),
    'snapshotExpiresAt': now.add(const Duration(minutes: 5)).toIso8601String(),
    'stale': false,
    'complete': true,
  };
}

UserSession _session() => UserSession(
  userId: 'user-a',
  username: 'alice',
  sessionId: 'session-a',
  mode: 'ordinary',
  expiresAt: DateTime.now().add(const Duration(hours: 1)),
  bearerToken: 'opaque-a',
);

ConnectionScope _scope(ConnectionScopeStore scopes, UserSession session) =>
    scopes.select(
      session: session,
      connectionId: 'conn_demo_001',
      exchange: 'OKX',
      environment: 'demo',
      region: 'global',
      product: 'SWAP',
      credentialVersion: 1,
      permissionVersion: 1,
    )!;

MultiUserApiClient _client(
  HttpClientAdapter adapter,
  UserSessionStore sessions,
  ConnectionScopeStore scopes,
) => MultiUserApiClient(
  backend: BackendDataClient(
    dio: Dio()..httpClientAdapter = adapter,
    baseUrl: 'https://data.example/gateway',
    isWeb: false,
  ),
  sessions: sessions,
  scopes: scopes,
  isWeb: false,
);

Map<String, dynamic> _preparedAction({
  required Map<String, String> identity,
  String operationId = 'operation_0001',
  String? currentSize = '2',
}) => {
  'operationId': operationId,
  'connectionId': 'conn_demo_001',
  'product': 'SWAP',
  'action': 'close_position',
  'status': 'PREPARED',
  'confirmationToken': 'opaque-confirmation-token',
  'expiresAt': DateTime.now().add(const Duration(minutes: 2)).toIso8601String(),
  'targets': [
    {'index': 0, 'status': 'PREPARED', 'result': null},
  ],
  'summary': {
    'action': 'close_position',
    'identity': identity,
    'direction': 'long',
    if (currentSize != null) 'currentSize': currentSize,
  },
};

class _JsonAdapter implements HttpClientAdapter {
  _JsonAdapter(this.response);
  final Object response;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(response),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

class _PagingAdapter implements HttpClientAdapter {
  final cursors = <String?>[];
  final _asOf = DateTime.now().toUtc().subtract(const Duration(seconds: 1));
  final _expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 5));

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final cursor = options.queryParameters['cursor'] as String?;
    cursors.add(cursor);
    final now = DateTime.now().toUtc();
    final response = {
      'data': [
        {
          'exchange': 'OKX',
          'product': 'SWAP',
          'environment': 'demo',
          'region': 'global',
          'asset': cursor == null ? 'BTC' : 'ETH',
          'available': '1',
          'locked': '0',
          'total': '1',
          'unit': cursor == null ? 'BTC' : 'ETH',
        },
      ],
      'page': {'nextCursor': cursor == null ? 'next-1' : null},
      'dataMeta': {
        'fetchedAt': now.toIso8601String(),
        'asOf': _asOf.toIso8601String(),
        'snapshotExpiresAt': _expiresAt.toIso8601String(),
        'stale': false,
        'complete': true,
      },
    };
    return ResponseBody.fromString(
      jsonEncode(response),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
