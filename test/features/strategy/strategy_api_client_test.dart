import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/strategy/data/strategy_api_client.dart';

void main() {
  test(
    'uses the T38 authenticated strategy routes and current session token',
    () async {
      final adapter = _TradeAdapter();
      final client = StrategyApiClient(
        baseUrl: 'https://trade.example.com',
        dio: Dio(BaseOptions())..httpClientAdapter = adapter,
      );
      const token = 'current-session-token';

      final preview = await client.preview(token, const {
        'instrumentId': 'BTC-USDT-SWAP',
      });
      final saved = await client.saveDraft(token, const {
        'previewHash': 'hash',
      });
      final strategies = await client.listStrategies(token);
      final prepared = await client.prepareApply(token, 'draft-123');
      final executed = await client.executeApply(
        token,
        'draft-123',
        'confirm-once',
      );
      await client.getResult(token, 'draft-123');
      await client.deleteDraft(token, 'draft-123');

      expect(preview['previewHash'], 'hash');
      expect(saved['id'], 'draft-123');
      expect(strategies, isEmpty);
      expect(prepared['confirmationToken'], 'confirm-once');
      expect(executed['status'], 'UNKNOWN');
      expect(adapter.requests.map((request) => request.uri.path), [
        '/v1/strategies/preview',
        '/v1/strategies',
        '/v1/strategies',
        '/v1/strategies/draft-123/prepare-apply',
        '/v1/strategies/draft-123/execute-apply',
        '/v1/strategies/draft-123/result',
        '/v1/strategies/draft-123/delete',
      ]);
      expect(
        adapter.requests.every(
          (request) =>
              request.headers['Authorization'] == 'Bearer $token' &&
              !request.followRedirects &&
              request.maxRedirects == 0,
        ),
        isTrue,
      );
      expect(adapter.requests[0].method, 'POST');
      expect(adapter.requests[1].data, {'previewHash': 'hash'});
      expect(adapter.requests[2].method, 'GET');
      expect(adapter.requests[6].data, const {});
    },
  );
}

class _TradeAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final path = options.uri.path;
    final payload = switch (path) {
      '/v1/strategies/preview' => {
        'previewHash': 'hash',
        'orders': [
          <String, Object>{'role': 'entry'},
        ],
      },
      '/v1/strategies' when options.method == 'POST' => {'id': 'draft-123'},
      '/v1/strategies' => {'strategies': <Object>[]},
      '/v1/strategies/draft-123/prepare-apply' => {
        'confirmationToken': 'confirm-once',
        'orders': [
          <String, Object>{'role': 'entry'},
        ],
      },
      '/v1/strategies/draft-123/execute-apply' => {'status': 'UNKNOWN'},
      '/v1/strategies/draft-123/result' => {'status': 'UNKNOWN'},
      _ => {'status': 'DELETED'},
    };
    return ResponseBody.fromString(
      jsonEncode(payload),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
