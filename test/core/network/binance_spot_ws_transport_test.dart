import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/network/binance_spot_ws_transport.dart';

void main() {
  group('BinanceSpotWebSocketTransport', () {
    test('parses success, error, and rate limit fields', () async {
      final harness = _Harness.create();
      addTearDown(harness.transport.dispose);

      final successFuture = harness.transport.send(
        method: 'account.status',
        params: const {'recvWindow': 5000},
      );
      final connection = await harness.connector.connectionAt(0);
      final successRequest = await connection.requestAt(0);
      expect(successRequest['method'], 'account.status');
      expect(successRequest['params'], {'recvWindow': 5000});
      expect(connection.requests, hasLength(1));
      connection.reply({
        'id': successRequest['id'],
        'status': 200,
        'result': {'accountType': 'SPOT'},
        'rateLimits': [
          {'rateLimitType': 'REQUEST_WEIGHT', 'count': 1},
        ],
      });

      final success = await successFuture;
      expect(success.status, 200);
      expect(success.result, {'accountType': 'SPOT'});
      expect(success.errorCode, isNull);
      expect(success.errorMessage, isNull);
      expect(success.rateLimits, [
        {'rateLimitType': 'REQUEST_WEIGHT', 'count': 1},
      ]);

      final errorFuture = harness.transport.send(
        method: 'account.status',
        params: const {},
      );
      final errorRequest = await connection.requestAt(1);
      connection.reply({
        'id': errorRequest['id'],
        'status': 400,
        'error': {'code': -1102, 'msg': 'Mandatory parameter missing'},
        'rateLimits': [
          {'rateLimitType': 'ORDERS', 'count': 2},
        ],
      });

      final error = await errorFuture;
      expect(error.status, 400);
      expect(error.errorCode, -1102);
      expect(error.errorMessage, 'Mandatory parameter missing');
      expect(error.rateLimits.single['count'], 2);
    });

    test('returns retryAfter for 429 and 418 replies', () async {
      final harness = _Harness.create();
      addTearDown(harness.transport.dispose);
      _FakeConnection? connection;

      for (final status in [429, 418]) {
        final replyFuture = harness.transport.send(
          method: 'account.status',
          params: const {},
        );
        final activeConnection = connection ??= await harness.connector
            .connectionAt(0);
        final request = await activeConnection.requestAt(status == 429 ? 0 : 1);
        activeConnection.reply({
          'id': request['id'],
          'status': status,
          'error': {'code': status, 'msg': 'Rate limited'},
          'retryAfter': '2026-10-29T12:00:00Z',
        });

        final reply = await replyFuture;
        expect(reply.status, status);
        expect(reply.retryAfter, '2026-10-29T12:00:00Z');
      }
    });

    test(
      'matches concurrent replies by id when they arrive out of order',
      () async {
        final harness = _Harness.create();
        addTearDown(harness.transport.dispose);

        final firstFuture = harness.transport.send(
          method: 'first',
          params: const {},
        );
        final secondFuture = harness.transport.send(
          method: 'second',
          params: const {},
        );
        final connection = await harness.connector.connectionAt(0);
        await connection
            .waitForRequestCount(2)
            .timeout(const Duration(seconds: 1));
        final firstRequest = await connection.requestAt(0);
        final secondRequest = await connection.requestAt(1);

        connection.reply({
          'id': secondRequest['id'],
          'status': 200,
          'result': 2,
        });
        connection.reply({
          'id': firstRequest['id'],
          'status': 200,
          'result': 1,
        });

        expect(
          (await firstFuture.timeout(const Duration(seconds: 1))).result,
          1,
        );
        expect(
          (await secondFuture.timeout(const Duration(seconds: 1))).result,
          2,
        );
      },
    );

    test('fails a request after its timeout', () async {
      final harness = _Harness.create(
        requestTimeout: const Duration(milliseconds: 25),
      );
      addTearDown(harness.transport.dispose);

      final future = harness.transport.send(method: 'slow', params: const {});
      final connection = await harness.connector.connectionAt(0);
      await connection.requestAt(0);

      await expectLater(
        future,
        throwsA(
          isA<BinanceSpotTransportException>().having(
            (error) => error.kind,
            'failure',
            BinanceSpotTransportFailure.timeout,
          ),
        ),
      );
    });

    test('closes idle connections and reconnects on the next send', () async {
      final harness = _Harness.create(
        idleTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(harness.transport.dispose);

      final firstFuture = harness.transport.send(
        method: 'first',
        params: const {},
      );
      final firstConnection = await harness.connector.connectionAt(0);
      final firstRequest = await firstConnection.requestAt(0);
      firstConnection.reply({'id': firstRequest['id'], 'status': 200});
      await firstFuture;

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(firstConnection.closed, isTrue);

      final secondFuture = harness.transport.send(
        method: 'second',
        params: const {},
      );
      final secondConnection = await harness.connector.connectionAt(1);
      final secondRequest = await secondConnection.requestAt(0);
      secondConnection.reply({'id': secondRequest['id'], 'status': 200});
      expect((await secondFuture).status, 200);
    });

    test(
      'serverShutdown fails in-flight requests as network failures',
      () async {
        final harness = _Harness.create();
        addTearDown(harness.transport.dispose);

        final pending = harness.transport.send(
          method: 'account.status',
          params: const {},
        );
        final connection = await harness.connector.connectionAt(0);
        await connection.requestAt(0);
        connection.reply({'method': 'serverShutdown', 'params': const {}});

        await expectLater(
          pending,
          throwsA(
            isA<BinanceSpotTransportException>().having(
              (error) => error.kind,
              'failure',
              BinanceSpotTransportFailure.network,
            ),
          ),
        );
      },
    );

    test(
      'a peer-closed connection fails pending requests and reconnects',
      () async {
        final harness = _Harness.create();
        addTearDown(harness.transport.dispose);

        final pending = harness.transport.send(
          method: 'pending',
          params: const {},
        );
        final firstConnection = await harness.connector.connectionAt(0);
        await firstConnection.requestAt(0);
        final networkExpectation = expectLater(
          pending,
          throwsA(
            isA<BinanceSpotTransportException>().having(
              (error) => error.kind,
              'failure',
              BinanceSpotTransportFailure.network,
            ),
          ),
        );
        await firstConnection.peerClose();
        await networkExpectation;

        final retry = harness.transport.send(
          method: 'after.peer.close',
          params: const {},
        );
        final secondConnection = await harness.connector.connectionAt(1);
        final request = await secondConnection.requestAt(0);
        secondConnection.reply({'id': request['id'], 'status': 200});
        expect((await retry).status, 200);
      },
    );

    test('close fails in-flight requests and allows later reuse', () async {
      final harness = _Harness.create();
      addTearDown(harness.transport.dispose);

      final pending = harness.transport.send(
        method: 'pending',
        params: const {},
      );
      final firstConnection = await harness.connector.connectionAt(0);
      await firstConnection.requestAt(0);
      final closedExpectation = expectLater(
        pending,
        throwsA(
          isA<BinanceSpotTransportException>().having(
            (error) => error.kind,
            'failure',
            BinanceSpotTransportFailure.closed,
          ),
        ),
      );
      harness.transport.close();
      await closedExpectation;

      final next = harness.transport.send(method: 'reused', params: const {});
      final secondConnection = await harness.connector.connectionAt(1);
      final request = await secondConnection.requestAt(0);
      secondConnection.reply({'id': request['id'], 'status': 200});
      expect((await next).status, 200);
    });

    test(
      'sanitizes connection failures and retries on a new connection',
      () async {
        const sentinel = 'KEY_SENTINEL_SIGNATURE_SENTINEL_BODY_SENTINEL';
        final harness = _Harness.create();
        addTearDown(harness.transport.dispose);
        harness.connector.failNext = StateError('private frame $sentinel');

        final failed = harness.transport.send(
          method: 'order.place',
          params: const {
            'key': 'KEY_SENTINEL',
            'signature': 'SIGNATURE_SENTINEL',
            'body': 'BODY_SENTINEL',
          },
        );
        await expectLater(
          failed,
          throwsA(
            isA<BinanceSpotTransportException>()
                .having(
                  (error) => error.kind,
                  'failure',
                  BinanceSpotTransportFailure.network,
                )
                .having(
                  (error) => error.toString(),
                  'text',
                  isNot(contains(sentinel)),
                )
                .having(
                  (error) => error.toString(),
                  'text',
                  isNot(contains('KEY_SENTINEL')),
                )
                .having(
                  (error) => error.toString(),
                  'text',
                  isNot(contains('SIGNATURE_SENTINEL')),
                )
                .having(
                  (error) => error.toString(),
                  'text',
                  isNot(contains('BODY_SENTINEL')),
                ),
          ),
        );

        final retry = harness.transport.send(
          method: 'account.status',
          params: const {},
        );
        final connection = await harness.connector.connectionAt(0);
        final request = await connection.requestAt(0);
        connection.reply({'id': request['id'], 'status': 200, 'result': 'ok'});
        final reply = await retry;
        expect(reply.result, 'ok');
        expect(reply.toString(), isNot(contains('KEY_SENTINEL')));
        expect(reply.toString(), isNot(contains('SIGNATURE_SENTINEL')));
        expect(reply.toString(), isNot(contains('BODY_SENTINEL')));
      },
    );

    test(
      'cancellation ignores late replies and cancellation after reply',
      () async {
        final harness = _Harness.create();
        addTearDown(harness.transport.dispose);
        final token = CancelToken();

        final cancelled = harness.transport.send(
          method: 'cancelled',
          params: const {},
          cancelToken: token,
        );
        final connection = await harness.connector.connectionAt(0);
        final cancelledRequest = await connection.requestAt(0);
        token.cancel('cancel sentinel');
        await expectLater(
          cancelled,
          throwsA(
            isA<BinanceSpotTransportException>().having(
              (error) => error.kind,
              'failure',
              BinanceSpotTransportFailure.cancelled,
            ),
          ),
        );
        connection.reply({
          'id': cancelledRequest['id'],
          'status': 200,
          'result': 'late',
        });

        final afterReplyToken = CancelToken();
        final completed = harness.transport.send(
          method: 'completed',
          params: const {},
          cancelToken: afterReplyToken,
        );
        final completedRequest = await connection.requestAt(1);
        connection.reply({
          'id': completedRequest['id'],
          'status': 200,
          'result': 'done',
        });
        expect((await completed).result, 'done');
        afterReplyToken.cancel('late cancellation');
      },
    );

    test('dispose fails in-flight requests and rejects future sends', () async {
      final harness = _Harness.create();

      final pending = harness.transport.send(
        method: 'pending',
        params: const {},
      );
      final connection = await harness.connector.connectionAt(0);
      await connection.requestAt(0);
      final disposedExpectation = expectLater(
        pending,
        throwsA(
          isA<BinanceSpotTransportException>().having(
            (error) => error.kind,
            'failure',
            BinanceSpotTransportFailure.closed,
          ),
        ),
      );
      harness.transport.dispose();
      await disposedExpectation;
      await expectLater(
        harness.transport.send(method: 'after.dispose', params: const {}),
        throwsA(isA<BinanceSpotTransportException>()),
      );
      expect(harness.connector.connections, hasLength(1));
    });

    test('ignores malformed frames and unknown request ids', () async {
      final harness = _Harness.create();
      addTearDown(harness.transport.dispose);

      final future = harness.transport.send(method: 'valid', params: const {});
      final connection = await harness.connector.connectionAt(0);
      final request = await connection.requestAt(0);
      connection.text('not json');
      connection.reply({'id': 'unknown-id', 'status': 200, 'result': 'wrong'});
      await Future<void>.delayed(const Duration(milliseconds: 10));

      connection.reply({'id': request['id'], 'status': 200, 'result': 'right'});
      expect((await future).result, 'right');
    });

    test('maps a pre-cancelled token to a cancellation failure', () async {
      final harness = _Harness.create();
      addTearDown(harness.transport.dispose);
      final token = CancelToken()..cancel('already cancelled');

      await expectLater(
        harness.transport.send(
          method: 'never.sent',
          params: const {},
          cancelToken: token,
        ),
        throwsA(
          isA<BinanceSpotTransportException>().having(
            (error) => error.kind,
            'failure',
            BinanceSpotTransportFailure.cancelled,
          ),
        ),
      );
      expect(harness.connector.connections, isEmpty);
    });
  });
}

class _Harness {
  _Harness(this.connector, this.transport);

  final _FakeConnector connector;
  final BinanceSpotWebSocketTransport transport;

  factory _Harness.create({
    Duration requestTimeout = const Duration(seconds: 1),
    Duration idleTimeout = const Duration(seconds: 5),
  }) {
    final connector = _FakeConnector();
    return _Harness(
      connector,
      BinanceSpotWebSocketTransport(
        connector: connector.connect,
        requestTimeout: requestTimeout,
        idleTimeout: idleTimeout,
      ),
    );
  }
}

class _FakeConnector {
  final List<_FakeConnection> connections = [];
  Object? failNext;

  Future<BinanceSpotWebSocketConnection> connect(Uri uri) async {
    expect(uri, Uri.parse('wss://ws-api.binance.com:443/ws-api/v3'));
    final failure = failNext;
    failNext = null;
    if (failure != null) throw failure;
    final connection = _FakeConnection();
    connections.add(connection);
    return connection;
  }

  Future<_FakeConnection> connectionAt(int index) async {
    final deadline = DateTime.now().add(const Duration(seconds: 1));
    while (connections.length <= index) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('Fake connection $index was not created.');
      }
      await Future<void>.delayed(Duration.zero);
    }
    return connections[index];
  }
}

class _FakeConnection implements BinanceSpotWebSocketConnection {
  final StreamController<dynamic> _incoming = StreamController<dynamic>(
    sync: true,
  );
  final StreamController<dynamic> _outgoing = StreamController<dynamic>(
    sync: true,
  );
  final List<String> requests = [];
  final Map<int, Completer<void>> _requestWaiters = {};
  late final StreamSubscription<dynamic> _outgoingSubscription;
  bool closed = false;

  _FakeConnection() {
    _outgoingSubscription = _outgoing.stream.listen((value) {
      if (value is String) requests.add(value);
      final readyCounts = _requestWaiters.keys
          .where((count) => requests.length >= count)
          .toList();
      for (final count in readyCounts) {
        _requestWaiters.remove(count)!.complete();
      }
    });
  }

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  StreamSink<dynamic> get sink => _outgoing.sink;

  Future<void> waitForRequestCount(int count) {
    if (requests.length >= count) return Future<void>.value();
    return (_requestWaiters[count] ??= Completer<void>()).future;
  }

  Future<Map<String, dynamic>> requestAt(int index) async {
    await waitForRequestCount(index + 1);
    return jsonDecode(requests[index]) as Map<String, dynamic>;
  }

  void reply(Object? frame) => _incoming.add(jsonEncode(frame));

  void text(String frame) => _incoming.add(frame);

  Future<void> peerClose() => _incoming.close();

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await _incoming.close();
    await _outgoing.close();
    await _outgoingSubscription.cancel();
  }
}
