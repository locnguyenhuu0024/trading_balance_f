import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/exchange/exchange_models.dart';
import 'package:trading_balance_f/core/network/request_coordinator.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/exchanges/binance/binance_private_client.dart';

class Fixture implements HttpClientAdapter {
  Fixture(this.respond);
  final Future<ResponseBody> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody body(
  Object data, [
  int status = 200,
  Map<String, List<String>>? extra,
]) => ResponseBody.fromString(
  jsonEncode(data),
  status,
  headers: {
    'content-type': ['application/json'],
    ...?extra,
  },
);

void main() {
  late ValueNotifier<OkxCredentialSnapshot> state;
  late RequestCoordinator coordinator;
  setUp(() {
    state = ValueNotifier(
      const OkxCredentialSnapshot(generation: 0, rotating: false),
    );
    coordinator = RequestCoordinator(minimumSpacing: Duration.zero);
  });
  tearDown(() => state.dispose());
  BinancePrivateClient client(Fixture fixture, {bool web = false}) =>
      BinancePrivateClient(
        keys: BinanceKeyBundle(apiKey: 'fake-key', apiSecret: 'fake-secret'),
        credentialState: state,
        coordinator: coordinator,
        isWeb: web,
        dio: Dio()..httpClientAdapter = fixture,
        clock: () => DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
      );
  bool failure(Object? e, ExchangeFailureKind kind) =>
      e is BinancePrivateException && e.failure.kind == kind;

  test('HMAC SHA256 signs the exact query', () {
    expect(
      BinancePrivateClient.signature(
        'key',
        'The quick brown fox jumps over the lazy dog',
      ),
      'f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8',
    );
  });
  test('-2015 is terminal without retry and errors hide secrets', () async {
    final fixture = Fixture(
      (r) async => r.path.endsWith('/time')
          ? body({'serverTime': 1000})
          : body({'code': -2015, 'msg': 'fake-secret'}, 400),
    );
    try {
      await client(fixture).get('/fapi/v3/account');
      fail('expected failure');
    } catch (e) {
      expect(failure(e, ExchangeFailureKind.credential), isTrue);
      expect('$e', isNot(contains('fake-secret')));
    }
    expect(fixture.requests.length, 2);
  });
  test('-1021 resyncs and retries once even if it fails twice', () async {
    final fixture = Fixture(
      (r) async => r.path.endsWith('/time')
          ? body({'serverTime': 1000})
          : body({'code': -1021}, 400),
    );
    await expectLater(
      client(fixture).get('/fapi/v3/account'),
      throwsA(isA<BinancePrivateException>()),
    );
    expect(fixture.requests.where((r) => r.path.endsWith('/time')).length, 2);
    expect(
      fixture.requests.where((r) => r.path.endsWith('/account')).length,
      2,
    );
  });
  test('429 closes lane using Retry-After', () async {
    final fixture = Fixture(
      (r) async => r.path.endsWith('/time')
          ? body({'serverTime': 1000})
          : body(
              {'code': -1003},
              429,
              {
                'retry-after': ['60'],
              },
            ),
    );
    await expectLater(
      client(fixture).get('/fapi/v3/account'),
      throwsA(predicate((e) => failure(e, ExchangeFailureKind.transient))),
    );
    expect(
      coordinator.stateFor(RequestLane.authenticated).retryAfter!.inSeconds,
      greaterThanOrEqualTo(59),
    );
  });
  test('rotation mid-read drops the result', () async {
    final pending = Completer<ResponseBody>();
    final started = Completer<void>();
    final fixture = Fixture((r) {
      if (r.path.endsWith('/time'))
        return Future.value(body({'serverTime': 1000}));
      started.complete();
      return pending.future;
    });
    final read = client(fixture).get('/fapi/v3/account');
    await started.future;
    state.value = const OkxCredentialSnapshot(generation: 1, rotating: true);
    pending.complete(body({}));
    await expectLater(
      read,
      throwsA(predicate((e) => failure(e, ExchangeFailureKind.cancellation))),
    );
  });
  test(
    'rejects non-allowlisted routes and web Spot and Margin without network',
    () async {
      final fixture = Fixture((_) async => body({}));
      final c = client(fixture, web: true);
      await expectLater(c.get('/api/v3/order'), throwsArgumentError);
      for (final path in ['/api/v3/account', '/sapi/v1/margin/account']) {
        await expectLater(
          c.get(path),
          throwsA(
            predicate(
              (e) => failure(e, ExchangeFailureKind.unavailableOnPlatform),
            ),
          ),
        );
      }
      expect(fixture.requests, isEmpty);
    },
  );
  test('signs exact sent query with key header and server offset', () async {
    final fixture = Fixture(
      (r) async =>
          r.path.endsWith('/time') ? body({'serverTime': 5000}) : body({}),
    );
    await client(
      fixture,
    ).get('/fapi/v3/account', queryParameters: {'symbol': 'BTC USDT'});
    final request = fixture.requests.last;
    final query = request.uri.query;
    final split = query.lastIndexOf('&signature=');
    expect(
      query.substring(split + 11),
      BinancePrivateClient.signature('fake-secret', query.substring(0, split)),
    );
    expect(query, contains('timestamp=5000'));
    expect(request.headers['X-MBX-APIKEY'], 'fake-key');
  });
}
