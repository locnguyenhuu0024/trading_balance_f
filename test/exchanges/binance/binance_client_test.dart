import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/network/request_coordinator.dart';
import 'package:trading_balance_f/exchanges/binance/binance_client.dart';

class FixtureAdapter implements HttpClientAdapter {
  FixtureAdapter(this.status);
  final int status;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode([]),
      status,
      headers: {
        'content-type': ['application/json'],
        if (status == 429) 'retry-after': ['60'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('public requests omit API key and reject other endpoints', () async {
    final fixture = FixtureAdapter(200);
    final dio = Dio()..httpClientAdapter = fixture;
    dio.options.headers['X-MBX-APIKEY'] = 'not-a-key';
    final client = BinanceClient(
      coordinator: RequestCoordinator(minimumSpacing: Duration.zero),
      dio: dio,
    );
    await client.get('/api/v3/exchangeInfo');
    expect(fixture.requests.single.uri.host, 'api.binance.com');
    expect(
      fixture.requests.single.headers.keys.map((e) => e.toLowerCase()),
      isNot(contains('x-mbx-apikey')),
    );
    expect(() => client.get('/api/v3/order'), throwsArgumentError);
  });
  test(
    '429 backs off Binance public lane while OKX lane remains open',
    () async {
      final binance = RequestCoordinator(minimumSpacing: Duration.zero);
      final okx = RequestCoordinator(minimumSpacing: Duration.zero);
      final client = BinanceClient(
        coordinator: binance,
        dio: Dio()..httpClientAdapter = FixtureAdapter(429),
      );
      await expectLater(
        client.get('/fapi/v1/exchangeInfo'),
        throwsA(isA<RequestRateLimitException>()),
      );
      expect(
        binance.stateFor(RequestLane.public).retryAfter!.inSeconds,
        greaterThanOrEqualTo(59),
      );
      expect(okx.stateFor(RequestLane.public).isClosed, isFalse);
    },
  );
}
