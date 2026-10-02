import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/strategy/data/strategy_api_client.dart';

void main() {
  final unstructuredHttpFailures = [
    (status: 404, marker: 'HTTP 404', guidance: 'không tìm thấy'),
    (status: 429, marker: 'HTTP 429', guidance: 'quá thường xuyên'),
    (status: 503, marker: 'HTTP 503', guidance: 'thử lại sau'),
    (status: 401, marker: 'HTTP 401', guidance: 'đăng nhập lại'),
  ];

  for (final failure in unstructuredHttpFailures) {
    test(
      'unstructured ${failure.marker} has safe actionable guidance',
      () async {
        const privateBody = '<html>PRIVATE-RESPONSE-BODY</html>';
        final error = await _capturePreviewFailure(
          _FailureAdapter(
            (_) async => ResponseBody.fromString(
              privateBody,
              failure.status,
              headers: {
                Headers.contentTypeHeader: ['text/html'],
              },
            ),
          ),
        );

        expect(error.message, contains(failure.marker));
        expect(error.message.toLowerCase(), contains(failure.guidance));
        expect(error.message, isNot(contains('PRIVATE-RESPONSE-BODY')));
        expect(error.statusCode, failure.status);
        expect(error.details, isEmpty);
        if (failure.status == 401) expect(error.isUnauthorized, isTrue);
      },
    );
  }

  test('timeout and connection failures have distinct safe markers', () async {
    const privateReason = 'PRIVATE-EXCEPTION-DETAIL';
    final timeout = await _capturePreviewFailure(
      _FailureAdapter(
        (request) async => throw DioException(
          requestOptions: request,
          type: DioExceptionType.receiveTimeout,
          message: privateReason,
        ),
      ),
    );
    final connection = await _capturePreviewFailure(
      _FailureAdapter(
        (request) async => throw DioException.connectionError(
          requestOptions: request,
          reason: privateReason,
        ),
      ),
    );

    expect(timeout.message, contains('TIMEOUT'));
    expect(connection.message, contains('CONNECTION'));
    expect(timeout.message, isNot(contains(privateReason)));
    expect(connection.message, isNot(contains(privateReason)));
    expect(timeout.message, isNot(contains('session-token')));
    expect(connection.message, isNot(contains('session-token')));
    expect(timeout.statusCode, isNull);
    expect(connection.statusCode, isNull);
  });

  test('unknown transport and cancellation failures remain safe', () async {
    const privateReason = 'PRIVATE-EXCEPTION-DETAIL';
    final unknown = await _capturePreviewFailure(
      _FailureAdapter(
        (request) async => throw DioException(
          requestOptions: request,
          type: DioExceptionType.unknown,
          message: privateReason,
        ),
      ),
    );
    final cancelled = await _capturePreviewFailure(
      _FailureAdapter(
        (request) async => throw DioException(
          requestOptions: request,
          type: DioExceptionType.cancel,
          message: privateReason,
        ),
      ),
    );

    expect(unknown.message, contains('CONNECTION'));
    expect(cancelled.message, contains('CANCELLED'));
    expect(unknown.message, isNot(contains(privateReason)));
    expect(cancelled.message, isNot(contains(privateReason)));
  });

  test('preserves structured 422 message, code, status, and details', () async {
    final error = await _capturePreviewFailure(
      _FailureAdapter(
        (_) async => ResponseBody.fromString(
          jsonEncode({
            'error': 'invalid_strategy',
            'message': 'SOL levels are invalid.',
            'details': {'field': 'selectedLevels'},
          }),
          422,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      ),
    );

    expect(error.message, 'SOL levels are invalid.');
    expect(error.code, 'invalid_strategy');
    expect(error.statusCode, 422);
    expect(error.details, {
      'error': 'invalid_strategy',
      'message': 'SOL levels are invalid.',
      'details': {'field': 'selectedLevels'},
    });
  });

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
        'replacementSourceId': 'never-sent-1',
      });
      final strategies = await client.listStrategies(token);
      final prepared = await client.prepareApply(token, 'draft-123');
      final executed = await client.executeApply(
        token,
        'draft-123',
        'confirm-once',
      );
      await client.getResult(token, 'draft-123');
      final quote = await client.getQuote(token, 'draft-123');
      await client.deleteDraft(token, 'draft-123');

      expect(preview['previewHash'], 'hash');
      expect(saved['id'], 'draft-123');
      expect(strategies, isEmpty);
      expect(prepared['confirmationToken'], 'confirm-once');
      expect(executed['status'], 'UNKNOWN');
      expect(quote['lastPrice'], '65000.125');
      expect(adapter.requests.map((request) => request.uri.path), [
        '/v1/strategies/preview',
        '/v1/strategies',
        '/v1/strategies',
        '/v1/strategies/draft-123/prepare-apply',
        '/v1/strategies/draft-123/execute-apply',
        '/v1/strategies/draft-123/result',
        '/v1/strategies/draft-123/quote',
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
      expect(adapter.requests[1].data, {
        'previewHash': 'hash',
        'replacementSourceId': 'never-sent-1',
      });
      expect(adapter.requests[2].method, 'GET');
      expect(adapter.requests[6].method, 'GET');
      expect(adapter.requests[7].data, const {});
    },
  );
}

Future<StrategyApiException> _capturePreviewFailure(
  HttpClientAdapter adapter,
) async {
  final client = StrategyApiClient(
    baseUrl: 'https://trade.example.com',
    dio: Dio(BaseOptions())..httpClientAdapter = adapter,
  );
  try {
    await client.preview('session-token', const {
      'instrumentId': 'SOL-USDT-SWAP',
    });
  } on StrategyApiException catch (error) {
    return error;
  }
  fail('Expected strategy preview to fail.');
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
      '/v1/strategies/draft-123/quote' => {
        'instrumentId': 'BTC-USDT-SWAP',
        'lastPrice': '65000.125',
        'observedAt': '2026-10-02T00:00:00.000Z',
      },
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

class _FailureAdapter implements HttpClientAdapter {
  _FailureAdapter(this._respond);

  final Future<ResponseBody> Function(RequestOptions request) _respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => _respond(options);

  @override
  void close({bool force = false}) {}
}
