import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/network/backend_data_client.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/trade_session_provider.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';

void main() {
  test(
    'loads the public USDT-VND rate without login or auth headers',
    () async {
      final adapter = _CurrencyAdapter({
        'code': '0',
        'data': [
          {'instId': 'USDT-VND', 'rate': '25431.25', 'source': 'CoinGecko'},
        ],
      });
      final container = ProviderContainer(
        overrides: [
          backendDataClientProvider.overrideWithValue(_client(adapter)),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(vndExchangeRateProvider.future), 25431.25);
      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.uri.path, '/v1/data/currency/usdt-vnd');
      expect(adapter.requests.single.headers['Authorization'], isNull);
    },
  );

  test('malformed or non-positive rate keeps the local fallback', () async {
    for (final rawRate in ['NaN', '0', '-1', 12345]) {
      final adapter = _CurrencyAdapter({
        'code': '0',
        'data': [
          {'instId': 'USDT-VND', 'rate': rawRate, 'source': 'CoinGecko'},
        ],
      });
      final container = ProviderContainer(
        overrides: [
          backendDataClientProvider.overrideWithValue(_client(adapter)),
        ],
      );

      expect(await container.read(vndExchangeRateProvider.future), 25400.0);
      container.dispose();
    }
  });
}

BackendDataClient _client(HttpClientAdapter adapter) => BackendDataClient(
  dio: Dio()..httpClientAdapter = adapter,
  baseUrl: 'https://data.example',
);

class _CurrencyAdapter implements HttpClientAdapter {
  _CurrencyAdapter(this.body);
  final Object body;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
