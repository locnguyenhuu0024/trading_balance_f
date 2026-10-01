import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/orders/data/trade_api_client.dart';

void main() {
  group('TradeApiClient base URL validation', () {
    test(
      'rejects a public HTTP URL before sending login credentials',
      () async {
        final adapter = _RecordingAdapter();
        final client = TradeApiClient(
          baseUrl: 'http://trade.example.com',
          dio: _dio(adapter),
        );

        expect(client.isConfigured, isFalse);
        await expectLater(
          client.login(password: 'not-a-real-password', totp: '000000'),
          throwsA(isA<TradeApiException>()),
        );
        expect(adapter.requestCount, 0);
      },
    );

    test('rejects malformed and hostless URLs before any request', () async {
      for (final baseUrl in ['', 'not a URL', 'https:///missing-host']) {
        final adapter = _RecordingAdapter();
        final client = TradeApiClient(baseUrl: baseUrl, dio: _dio(adapter));

        expect(client.isConfigured, isFalse, reason: baseUrl);
        await expectLater(
          client.login(password: 'password', totp: '000000'),
          throwsA(isA<TradeApiException>()),
          reason: baseUrl,
        );
        expect(adapter.requestCount, 0, reason: baseUrl);
      }
    });

    test('accepts HTTPS with a host and can send a request', () async {
      final adapter = _RecordingAdapter();
      final client = TradeApiClient(
        baseUrl: 'https://trade.example.com',
        dio: _dio(adapter),
      );

      expect(client.isConfigured, isTrue);
      final session = await client.login(password: 'password', totp: '000000');

      expect(session.bearerToken, 'test-token');
      expect(adapter.requestCount, 1);
      expect(adapter.lastUri?.scheme, 'https');
    });

    test(
      'does not follow an HTTP redirect from a private HTTPS request',
      () async {
        final adapter = _RecordingAdapter(
          statusCode: 302,
          responseHeaders: {
            'location': ['http://attacker.example/collect'],
          },
        );
        final client = TradeApiClient(
          baseUrl: 'https://trade.example.com',
          dio: _dio(adapter),
        );

        await expectLater(
          client.login(password: 'private-password', totp: '123456'),
          throwsA(isA<TradeApiException>()),
        );

        expect(adapter.requests, hasLength(1));
        expect(adapter.requests.single.uri.scheme, 'https');
        expect(adapter.requests.single.uri.host, 'trade.example.com');
        expect(adapter.requests.single.followRedirects, isFalse);
        expect(adapter.requests.single.maxRedirects, 0);
        expect(adapter.requestedUris, [
          Uri.parse('https://trade.example.com/v1/login'),
        ]);
        expect(adapter.requests.single.data, {
          'password': 'private-password',
          'totp': '123456',
        });
      },
    );
  });
}

Dio _dio(_RecordingAdapter adapter) =>
    Dio(BaseOptions())..httpClientAdapter = adapter;

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({this.statusCode = 200, this.responseHeaders = const {}});

  final int statusCode;
  final Map<String, List<String>> responseHeaders;
  final List<RequestOptions> requests = [];
  final List<Uri> requestedUris = [];

  int requestCount = 0;
  Uri? lastUri;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    lastUri = options.uri;
    requests.add(options);
    requestedUris.add(options.uri);
    // Model the adapter following a redirect if the request permits it. This
    // makes the test fail if TradeApiClient restores Dio's default behavior.
    if (statusCode == 302 && options.followRedirects) {
      final location = responseHeaders['location']?.first;
      if (location != null) requestedUris.add(Uri.parse(location));
    }
    return ResponseBody.fromString(
      jsonEncode(
        statusCode == 200
            ? {
                'token': 'test-token',
                'expiresAt': DateTime.utc(2030).toIso8601String(),
                'accountIdentifier': 'test-account',
              }
            : {'error': 'redirect'},
      ),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        ...responseHeaders,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
