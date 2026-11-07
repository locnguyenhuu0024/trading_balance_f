import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/exchange/exchange_models.dart';
import 'package:trading_balance_f/core/network/request_coordinator.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/exchanges/binance/binance_private_client.dart';
import 'package:trading_balance_f/exchanges/binance/binance_client.dart';
import 'package:trading_balance_f/exchanges/binance/binance_market.dart';
import 'package:trading_balance_f/exchanges/binance/binance_reader.dart';

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
  BinancePrivateClient client(
    Fixture fixture, {
    bool web = false,
    String proxy = '',
  }) => BinancePrivateClient(
    keys: BinanceKeyBundle(apiKey: 'fake-key', apiSecret: 'fake-secret'),
    credentialState: state,
    coordinator: coordinator,
    isWeb: web,
    proxyBaseUrl: proxy,
    dio: Dio()..httpClientAdapter = fixture,
    clock: () => DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
  );
  bool failure(Object? e, ExchangeFailureKind kind) =>
      e is BinancePrivateException && e.failure.kind == kind;

  test('HMAC SHA256 signs the exact query', () {
    expect(
      BinancePrivateClient.signature(
        'NhqPtmdSJYdKjVHjA7PZj4Mge3R5YNiP1e3UZjInClVN65XAbvqqM6A7H5fATj0j',
        'symbol=LTCBTC&side=BUY&type=LIMIT&timeInForce=GTC&quantity=1&price=0.1&recvWindow=5000&timestamp=1499827319559',
      ),
      'c8db56825ae71d6d79447849e617115f4a920fa2acdcab2b053c4b2838bd6b71',
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
      fixture.requests.where((r) => r.uri.path.endsWith('/account')).length,
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
  test(
    'web proxy signs Spot and Margin while futures and time stay direct',
    () async {
      final fixture = Fixture(
        (r) async => r.uri.path.endsWith('/time')
            ? body({'serverTime': 1000})
            : body({}),
      );
      final c = client(
        fixture,
        web: true,
        proxy: 'https://proxy.example/base/',
      );
      for (final path in [
        '/api/v3/account',
        '/sapi/v1/margin/account',
        '/fapi/v3/account',
        '/api/v3/time',
      ]) {
        await c.get(path);
      }
      for (final request in fixture.requests) {
        final path = request.uri.path;
        if (path.startsWith('/base/')) {
          expect(request.uri.host, 'proxy.example');
          expect(
            path,
            anyOf('/base/api/v3/account', '/base/sapi/v1/margin/account'),
          );
          final query = request.uri.query;
          final split = query.lastIndexOf('&signature=');
          expect(split, greaterThan(0));
          expect(
            query.substring(split + 11),
            BinancePrivateClient.signature(
              'fake-secret',
              query.substring(0, split),
            ),
          );
          expect(request.headers['X-MBX-APIKEY'], 'fake-key');
          expect(request.uri.toString(), isNot(contains('fake-secret')));
          expect(request.headers.toString(), isNot(contains('fake-secret')));
        } else {
          expect(
            request.uri.host,
            path.startsWith('/fapi/') ? 'fapi.binance.com' : 'api.binance.com',
          );
        }
      }
      expect(
        fixture.requests.where((r) => r.uri.host == 'proxy.example').length,
        2,
      );
    },
  );
  test('trade routes use the proxy and are unavailable without it', () async {
    final fixture = Fixture(
      (r) async =>
          r.uri.path.endsWith('/time') ? body({'serverTime': 1000}) : body([]),
    );
    final unavailable = client(fixture, web: true);
    for (final path in ['/api/v3/myTrades', '/sapi/v1/margin/myTrades']) {
      await expectLater(
        unavailable.get(path),
        throwsA(
          predicate(
            (e) => failure(e, ExchangeFailureKind.unavailableOnPlatform),
          ),
        ),
      );
    }
    expect(fixture.requests, isEmpty);
    final proxied = client(fixture, web: true, proxy: 'https://proxy.example');
    for (final path in ['/api/v3/myTrades', '/sapi/v1/margin/myTrades']) {
      await proxied.get(path, queryParameters: {'symbol': 'BTCUSDT'});
    }
    expect(
      fixture.requests
          .where((r) => r.uri.path.endsWith('/myTrades'))
          .every((r) => r.uri.host == 'proxy.example'),
      isTrue,
    );
  });
  test('account reads never request trade history', () async {
    final fixture = Fixture((r) async {
      if (r.uri.path.endsWith('/time')) return body({'serverTime': 1000});
      if (r.uri.path == '/fapi/v3/account') return body({'assets': []});
      if (r.uri.path == '/api/v3/account') return body({'balances': []});
      if (r.uri.path == '/sapi/v1/margin/account')
        return body({'userAssets': []});
      if (r.uri.path == '/sapi/v1/margin/isolated/account')
        return body({'assets': []});
      return body({});
    });
    final reader = BinanceReader(
      client(fixture),
      BinanceMarket(BinanceClient(coordinator: coordinator)),
    );
    await reader.readAccount();
    expect(
      fixture.requests.any((request) => request.uri.path.endsWith('/myTrades')),
      isFalse,
    );
  });
  test('invalid proxy values disable web private routes', () async {
    for (final proxy in [
      'http://proxy.example',
      'https://proxy.example?x=1',
      'https://proxy.example#x',
      'not a url',
    ]) {
      final fixture = Fixture((_) async => body({}));
      final c = client(fixture, web: true, proxy: proxy);
      expect(c.spotMarginAvailable, isFalse);
      await expectLater(
        c.get('/api/v3/account'),
        throwsA(
          predicate(
            (e) => failure(e, ExchangeFailureKind.unavailableOnPlatform),
          ),
        ),
      );
      expect(fixture.requests, isEmpty);
    }
  });
  test('native ignores configured proxy', () async {
    final fixture = Fixture(
      (r) async =>
          r.uri.path.endsWith('/time') ? body({'serverTime': 1000}) : body({}),
    );
    await client(
      fixture,
      proxy: 'https://proxy.example',
    ).get('/sapi/v1/margin/account');
    expect(
      fixture.requests.every((r) => r.uri.host == 'api.binance.com'),
      isTrue,
    );
  });
  test('403 and 451 remain other even with credential error codes', () async {
    for (final status in [403, 451]) {
      final fixture = Fixture(
        (r) async => r.uri.path.endsWith('/time')
            ? body({'serverTime': 1000})
            : body({'code': -2015}, status),
      );
      await expectLater(
        client(
          fixture,
          web: true,
          proxy: 'https://proxy.example',
        ).get('/api/v3/account'),
        throwsA(predicate((e) => failure(e, ExchangeFailureKind.other))),
      );
    }
  });
}
