import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/strategy/data/strategy_api_client.dart';
import 'package:trading_balance_f/features/strategy/domain/strategy_models.dart';
import 'package:trading_balance_f/features/strategy/domain/strategy_settings.dart';

void main() {
  test('retry DTOs require bound previews and consistent eligibility', () {
    expect(
      StrategyRetryDraft.tryParse(_retryDraftResponse()),
      isNotNull,
      reason: 'ordinary strategy result fields accompany retry fields',
    );
    final missingRevision = _retryDraftResponse();
    (missingRevision['preview'] as Map<String, dynamic>).remove(
      'sourceRevision',
    );
    expect(StrategyRetryDraft.tryParse(missingRevision), isNull);

    final contradictoryCandidate = _retryCandidateResponse()
      ..['priorOutcome'] = 'other'
      ..['eligible'] = true;
    expect(StrategyRetryCandidate.tryParse(contradictoryCandidate), isNull);
  });

  test(
    'automatic drafts post the authenticated stable request payload',
    () async {
      final adapter = _TradeAdapter();
      final client = StrategyApiClient(
        baseUrl: 'https://trade.example.com',
        dio: Dio(BaseOptions())..httpClientAdapter = adapter,
      );

      await client.createAutomaticDrafts(
        'current-session-token',
        instrumentId: 'btc-usdt-swap',
        interval: '1Dutc',
        requestId: 'auto-request_123456',
      );

      expect(adapter.requests, hasLength(1));
      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.path, '/v1/strategies/automatic-drafts');
      expect(request.headers['Authorization'], 'Bearer current-session-token');
      expect(request.data, {
        'instrumentId': 'BTC-USDT-SWAP',
        'interval': '1Dutc',
        'requestId': 'auto-request_123456',
      });
    },
  );

  test('automatic draft requests reject unsupported intervals and IDs', () {
    final adapter = _TradeAdapter();
    final client = StrategyApiClient(
      baseUrl: 'https://trade.example.com',
      dio: Dio(BaseOptions())..httpClientAdapter = adapter,
    );

    expect(
      () => client.createAutomaticDrafts(
        'current-session-token',
        instrumentId: 'BTC-USDT-SWAP',
        interval: '12Hutc',
        requestId: 'automatic-request-123',
      ),
      throwsA(isA<StrategyApiException>()),
    );
    expect(
      () => client.createAutomaticDrafts(
        'current-session-token',
        instrumentId: 'BTC-USDT-SWAP',
        interval: '6Hutc',
        requestId: 'short',
      ),
      throwsA(isA<StrategyApiException>()),
    );
    expect(adapter.requests, isEmpty);
  });

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
      final retryCandidates = await client.getRetryCandidates(
        token,
        'source-123',
      );
      final retryPreview = await client.previewRetry(
        token,
        'source-123',
        sourceRevision: 'revision-1',
        sourceClientOrderIds: const ['source-order-1'],
      );
      final retryDraft = await client.createRetryDraft(
        token,
        'source-123',
        sourceRevision: 'revision-1',
        sourceClientOrderIds: const ['source-order-1'],
        previewHash: 'review-hash-1',
        retryRequestId: 'retry-request-1234567890',
      );
      final strategies = await client.listStrategies(token);
      final prepared = await client.prepareApply(token, 'draft-123');
      final executed = await client.executeApply(
        token,
        'draft-123',
        'confirm-once',
      );
      await client.getResult(token, 'draft-123');
      final quote = await client.getQuote(token, 'draft-123');
      final preference = await client.getLimitOrderSubmissionMode(token);
      final savedPreference = await client.saveLimitOrderSubmissionMode(
        token,
        'batch',
      );
      await client.deleteDraft(token, 'draft-123');

      expect(preview['previewHash'], 'hash');
      expect(saved['id'], 'draft-123');
      expect(retryCandidates.candidates.single.eligible, isTrue);
      expect(
        retryPreview.orders.single['sourceClientOrderId'],
        'source-order-1',
      );
      expect(retryDraft.id, 'retry-child-1');
      expect(retryDraft.preview.previewHash, 'review-hash-1');
      expect(strategies, isEmpty);
      expect(prepared['confirmationToken'], 'confirm-once');
      expect(executed['status'], 'UNKNOWN');
      expect(quote['lastPrice'], '65000.125');
      expect(preference, 'sequential');
      expect(savedPreference, 'batch');
      expect(adapter.requests.map((request) => request.uri.path), [
        '/v1/strategies/preview',
        '/v1/strategies',
        '/v1/strategies/source-123/retry-candidates',
        '/v1/strategies/source-123/retry-preview',
        '/v1/strategies/source-123/retry-drafts',
        '/v1/strategies',
        '/v1/strategies/draft-123/prepare-apply',
        '/v1/strategies/draft-123/execute-apply',
        '/v1/strategies/draft-123/result',
        '/v1/strategies/draft-123/quote',
        '/v1/strategies/settings',
        '/v1/strategies/settings',
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
      expect(adapter.requests[3].data, {
        'sourceRevision': 'revision-1',
        'sourceClientOrderIds': ['source-order-1'],
      });
      expect(adapter.requests[4].data, {
        'sourceRevision': 'revision-1',
        'sourceClientOrderIds': ['source-order-1'],
        'previewHash': 'review-hash-1',
        'retryRequestId': 'retry-request-1234567890',
      });
      expect(adapter.requests[5].method, 'GET');
      expect(adapter.requests[9].method, 'GET');
      expect(adapter.requests[10].method, 'GET');
      expect(adapter.requests[11].method, 'POST');
      expect(adapter.requests[11].data, {'limitOrderSubmissionMode': 'batch'});
      expect(adapter.requests[12].data, const {});
    },
  );

  test(
    'settings responses require a known mode and exact save acknowledgment',
    () async {
      final invalidGet = await _captureSettingsFailure(
        _TradeAdapter(getSettingsMode: 'parallel'),
        save: false,
      );
      final invalidAck = await _captureSettingsFailure(
        _TradeAdapter(postSettingsMode: 'sequential'),
        save: true,
      );

      expect(invalidGet.code, 'invalid_response');
      expect(invalidAck.code, 'invalid_response');
    },
  );

  test(
    'full strategy settings use and verify the typed complete payload',
    () async {
      final adapter = _TradeAdapter();
      final client = StrategyApiClient(
        baseUrl: 'https://trade.example.com',
        dio: Dio(BaseOptions())..httpClientAdapter = adapter,
      );
      const defaults = StrategySettings(
        limitOrderSubmissionMode: 'sequential',
        jevScreeningThresholds: StrategyJevScreeningThresholds.defaults,
      );
      expect(await client.getStrategySettings('session-token'), defaults);

      const custom = StrategySettings(
        limitOrderSubmissionMode: 'batch',
        jevScreeningThresholds: StrategyJevScreeningThresholds(
          minStructuralQuality: 3,
          minEntrySuitabilityProbability: 0.555,
          maxFailureRiskProbability: 0.45,
        ),
      );
      expect(
        await client.saveStrategySettings('session-token', custom),
        custom,
      );
      expect(adapter.requests[0].method, 'GET');
      expect(adapter.requests[1].method, 'POST');
      expect(adapter.requests[1].data, custom.toJson());
    },
  );

  test(
    'full settings reject incomplete GET data and mismatched save ACK',
    () async {
      final invalidGetClient = StrategyApiClient(
        baseUrl: 'https://trade.example.com',
        dio: Dio(BaseOptions())
          ..httpClientAdapter = _TradeAdapter(
            getSettingsThresholds: const {'minStructuralQuality': 4},
          ),
      );
      await expectLater(
        invalidGetClient.getStrategySettings('session-token'),
        throwsA(
          isA<StrategyApiException>().having(
            (error) => error.code,
            'code',
            'invalid_response',
          ),
        ),
      );

      const custom = StrategySettings(
        limitOrderSubmissionMode: 'batch',
        jevScreeningThresholds: StrategyJevScreeningThresholds(
          minStructuralQuality: 3,
          minEntrySuitabilityProbability: 0.555,
          maxFailureRiskProbability: 0.45,
        ),
      );
      final mismatchClient = StrategyApiClient(
        baseUrl: 'https://trade.example.com',
        dio: Dio(BaseOptions())
          ..httpClientAdapter = _TradeAdapter(
            postSettingsThresholds: const {
              'minStructuralQuality': 3,
              'minEntrySuitabilityProbability': 0.56,
              'maxFailureRiskProbability': 0.45,
            },
          ),
      );
      await expectLater(
        mismatchClient.saveStrategySettings('session-token', custom),
        throwsA(
          isA<StrategyApiException>().having(
            (error) => error.code,
            'code',
            'invalid_response',
          ),
        ),
      );
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

Future<StrategyApiException> _captureSettingsFailure(
  _TradeAdapter adapter, {
  required bool save,
}) async {
  final client = StrategyApiClient(
    baseUrl: 'https://trade.example.com',
    dio: Dio(BaseOptions())..httpClientAdapter = adapter,
  );
  try {
    if (save) {
      await client.saveLimitOrderSubmissionMode('session-token', 'batch');
    } else {
      await client.getLimitOrderSubmissionMode('session-token');
    }
  } on StrategyApiException catch (error) {
    return error;
  }
  fail('Expected strategy settings request to fail.');
}

Map<String, dynamic> _retryCandidatesResponse() => {
  'sourceStrategyId': 'source-123',
  'sourceRevision': 'revision-1',
  'candidates': [
    {
      'sourceClientOrderId': 'source-order-1',
      'side': 'long',
      'role': 'entry',
      'limitPrice': '100',
      'contracts': '2',
      'leverage': '5',
      'priorOutcome': 'not_submitted',
      'eligible': true,
      'reason': null,
    },
  ],
  'blockedReason': null,
  'linkedChildren': <Object>[],
};

Map<String, dynamic> _retryCandidateResponse() => {
  'sourceClientOrderId': 'source-order-1',
  'side': 'long',
  'role': 'entry',
  'limitPrice': '100',
  'contracts': '2',
  'leverage': '5',
  'priorOutcome': 'not_submitted',
  'eligible': true,
  'reason': null,
};

Map<String, dynamic> _retryOrder({bool includeChildId = false}) => {
  if (includeChildId) 'clientOrderId': 'child-order-1',
  'sourceClientOrderId': 'source-order-1',
  'side': 'long',
  'role': 'entry',
  'limitPrice': '100',
  'contracts': '2',
  'leverage': '5',
  'margin': '4',
  'allocatedMargin': '4',
  'notional': '20',
  'openingFeeEstimate': '0.02',
  'allocationWeight': '1',
  'cumulativeContracts': '2',
  'cumulativeAverageEntry': '100',
  'liquidationEstimate': {'price': '80', 'method': 'cross'},
};

Map<String, dynamic> _retryPreviewResponse({bool includeChildId = false}) => {
  'sourceStrategyId': 'source-123',
  'sourceRevision': 'revision-1',
  'selectedSourceClientOrderIds': ['source-order-1'],
  'previewHash': 'review-hash-1',
  'instrumentId': 'BTC-USDT-SWAP',
  'interval': '6Hutc',
  'allocation': 'fixed',
  'feesOutsideMargin': true,
  'currentPrice': '101',
  'quoteTimestamp': '2026-10-03T00:00:00Z',
  'sidePercent': {'long': '100', 'short': '0'},
  'sides': [
    {'side': 'long', 'contracts': '2'},
  ],
  'totalMargin': '4',
  'plannedMargin': '4',
  'unallocatedMargin': '0',
  'estimatedOpeningFees': '0.02',
  'requiredBalance': '4.02',
  'orders': [_retryOrder(includeChildId: includeChildId)],
};

Map<String, dynamic> _retryDraftResponse() => {
  'id': 'retry-child-1',
  'status': 'DRAFT',
  'instrumentId': 'BTC-USDT-SWAP',
  'interval': '6Hutc',
  'sides': [
    {'side': 'long', 'contracts': '2'},
  ],
  'totalMargin': '4',
  'plannedMargin': '4',
  'unallocatedMargin': '0',
  'estimatedOpeningFees': '0.02',
  'fees': '0.02',
  'sidePercent': {'long': '100', 'short': '0'},
  'failureReason': null,
  'leverageResults': [],
  'batchAttempted': false,
  'submissionMode': 'sequential',
  'orderPlacementAttempted': false,
  'queueStatus': null,
  'queueProgress': null,
  'applyOutcome': null,
  'canDelete': true,
  'replacementCleanupConflict': false,
  'createdAt': '2026-10-03T00:00:00Z',
  'updatedAt': '2026-10-03T00:00:00Z',
  'orders': [_retryOrder(includeChildId: true)],
  'resubmission': {
    'sourceStrategyId': 'source-123',
    'sourceClientOrderIds': ['source-order-1'],
  },
  'preview': _retryPreviewResponse(includeChildId: true),
};

const Map<String, dynamic> _defaultSettingsThresholds = {
  'minStructuralQuality': 4,
  'minEntrySuitabilityProbability': 0.6,
  'maxFailureRiskProbability': 0.4,
};

class _TradeAdapter implements HttpClientAdapter {
  _TradeAdapter({
    this.getSettingsMode = 'sequential',
    this.postSettingsMode,
    this.getSettingsThresholds,
    this.postSettingsThresholds,
  });

  final String getSettingsMode;
  final String? postSettingsMode;
  final Map<String, dynamic>? getSettingsThresholds;
  final Map<String, dynamic>? postSettingsThresholds;
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
      '/v1/strategies/source-123/retry-candidates' =>
        _retryCandidatesResponse(),
      '/v1/strategies/source-123/retry-preview' => _retryPreviewResponse(),
      '/v1/strategies/source-123/retry-drafts' => _retryDraftResponse(),
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
      '/v1/strategies/settings' when options.method == 'GET' => {
        'limitOrderSubmissionMode': getSettingsMode,
        'jevScreeningThresholds':
            getSettingsThresholds ?? _defaultSettingsThresholds,
      },
      '/v1/strategies/settings' => {
        'limitOrderSubmissionMode':
            postSettingsMode ??
            (options.data as Map)['limitOrderSubmissionMode'],
        'jevScreeningThresholds':
            postSettingsThresholds ??
            (options.data as Map)['jevScreeningThresholds'] ??
            _defaultSettingsThresholds,
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
