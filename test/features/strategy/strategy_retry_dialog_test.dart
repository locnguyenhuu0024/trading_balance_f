import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/network/backend_data_client.dart';
import 'package:trading_balance_f/features/orders/data/trade_api_client.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/trade_session_provider.dart';
import 'package:trading_balance_f/features/portfolio/data/risk/risk_request_coordinator.dart';
import 'package:trading_balance_f/features/strategy/data/strategy_api_client.dart';
import 'package:trading_balance_f/features/strategy/data/strategy_market_repository.dart';
import 'package:trading_balance_f/features/strategy/domain/strategy_models.dart';
import 'package:trading_balance_f/features/strategy/presentation/providers/strategy_dashboard_provider.dart';
import 'package:trading_balance_f/features/strategy/presentation/strategy_screen.dart';

void main() {
  testWidgets(
    'T65 narrow dialog follows fixed preview, linked draft, prepare, one execute',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final api = _RetryDialogApi()
        ..executeCompleter = Completer<Map<String, dynamic>>();
      await tester.pumpWidget(_app(api));
      await _pumpFrames(tester);
      await _openRetryDialog(tester);

      expect(
        find.textContaining('Chọn 1–10 lệnh theo mã lệnh nguồn.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('strategy-retry-candidate-source-order-10')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Không đủ bằng chứng an toàn để gửi lại'),
        findsOneWidget,
      );

      await _tapCandidate(tester, 'source-order-1');
      await tester.pump();
      expect(find.text('Đã chọn: 1 / 10'), findsOneWidget);
      await tester.tap(find.byKey(const Key('strategy-retry-preview')));
      await _pumpFrames(tester);
      expect(api.previewCalls, 1);
      expect(find.text('Bản xem trước cố định'), findsOneWidget);
      expect(
        find.text('Giá tham chiếu hiện tại 65,000.12 · 2026-10-03T00:00:00Z'),
        findsOneWidget,
      );
      expect(find.text('Ký quỹ: 1,234.57'), findsOneWidget);
      expect(find.text('Phí mở ước tính: 3e-9'), findsOneWidget);
      expect(find.text('Chưa phân bổ: 0.00'), findsOneWidget);
      expect(
        find.textContaining('1.00 hợp đồng · 5x · Ký quỹ 1,234.57 · Phí 3e-9'),
        findsOneWidget,
      );
      expect(api.lastPreview!.raw['totalMargin'], '1234.56789');
      expect(api.lastPreview!.orders.single['limitPrice'], '65000.123456');
      expect(api.previewCalls, 1);
      expect(api.previewSourceRevision, 'source-revision-1');
      expect(api.previewSourceOrderIds, ['source-order-1']);

      await tester.tap(find.byKey(const Key('strategy-retry-create')));
      await _pumpFrames(tester);
      expect(api.createCalls, 1);
      expect(api.createSourceStrategyId, 'source-1');
      expect(api.createSourceRevision, 'source-revision-1');
      expect(api.createSourceOrderIds, ['source-order-1']);
      expect(api.createPreviewHash, 'retry-hash-1');
      expect(api.retryRequestId, matches(RegExp(r'^[A-Za-z0-9_-]{32}$')));
      expect(
        find.textContaining('Đã tạo bản gửi lại retry-child-1'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('strategy-retry-prepare')));
      await _pumpFrames(tester);
      expect(api.prepareCalls, 1);
      expect(api.preparedId, 'retry-child-1');
      expect(find.text('Cơ chế gửi đã cố định: Gửi theo lô'), findsOneWidget);
      expect(find.textContaining('retry-child-order-1'), findsWidgets);

      final executeButton = find.byKey(
        const Key('strategy-retry-execute-once'),
      );
      await tester.tap(executeButton);
      await tester.pump();
      expect(api.executeCalls, 1);
      expect(api.executedId, 'retry-child-1');
      expect(tester.widget<FilledButton>(executeButton).onPressed, isNull);
      await tester.tap(executeButton, warnIfMissed: false);
      expect(api.executeCalls, 1);

      api.executeCompleter!.complete(api.executionResult);
      await _pumpFrames(tester);
      expect(
        find.textContaining('Đã gửi bản liên kết retry-child-1'),
        findsOneWidget,
      );
      expect(api.createCalls, 1);
      expect(api.prepareCalls, 1);
      expect(api.executeCalls, 1);
      await _openStrategyDetails(tester, 'retry-child-1');
      expect(
        find.textContaining(
          'Bản gửi lại retry-child-1 liên kết với nguồn source-1 · source-order-1',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('T65 cancel during pending create cannot repeat or advance', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _RetryDialogApi()
      ..createCompleter = Completer<StrategyRetryDraft>();
    await tester.pumpWidget(_app(api));
    await _pumpFrames(tester);
    await _openRetryDialog(tester);
    await _tapCandidate(tester, 'source-order-1');
    await tester.pump();
    await tester.tap(find.byKey(const Key('strategy-retry-preview')));
    await _pumpFrames(tester);

    final createButton = find.byKey(const Key('strategy-retry-create'));
    await tester.tap(createButton);
    await tester.pump();
    expect(api.createCalls, 1);
    expect(tester.widget<FilledButton>(createButton).onPressed, isNull);
    await tester.tap(find.byKey(const Key('strategy-retry-cancel-flow')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('strategy-retry-create')), findsNothing);
    expect(api.prepareCalls, 0);
    expect(api.executeCalls, 0);

    api.linkedChildListed = true;
    api.createCompleter!.complete(_retryDraft());
    await _pumpFrames(tester, 10);
    await _openStrategyDetails(tester, 'retry-child-1');
    expect(api.createCalls, 1);
    expect(api.prepareCalls, 0);
    expect(api.executeCalls, 0);
    expect(
      find.textContaining(
        'Bản gửi lại retry-child-1 liên kết với nguồn source-1 · source-order-1',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'T65 desktop keeps all candidates and enforces the ten selection cap',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final api = _RetryDialogApi();
      await tester.pumpWidget(_app(api));
      await _pumpFrames(tester);
      await _openRetryDialog(tester);

      expect(
        find.byKey(const Key('strategy-retry-candidate-source-order-10')),
        findsOneWidget,
      );
      final excluded = tester.widget<CheckboxListTile>(
        find.byKey(const Key('strategy-retry-candidate-source-order-excluded')),
      );
      expect(excluded.onChanged, isNull);
      expect(
        find.textContaining('Không đủ bằng chứng an toàn để gửi lại'),
        findsOneWidget,
      );

      for (var index = 0; index < 10; index++) {
        await _tapCandidate(tester, 'source-order-$index');
        await tester.pump();
      }
      expect(find.text('Đã chọn: 10 / 10'), findsOneWidget);
      await _tapCandidate(tester, 'source-order-10');
      await tester.pump();
      expect(find.text('Đã chọn: 10 / 10'), findsOneWidget);
      expect(
        find.text('Chỉ có thể chọn tối đa 10 lệnh cho một lần gửi.'),
        findsOneWidget,
      );
      expect(api.previewCalls, 0);
      expect(api.createCalls, 0);
      expect(api.prepareCalls, 0);
      expect(api.executeCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('T65 cancel after PREPARED leaves linked child visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _RetryDialogApi();
    await tester.pumpWidget(_app(api));
    await _pumpFrames(tester);
    await _openRetryDialog(tester);
    await _tapCandidate(tester, 'source-order-1');
    await tester.pump();
    await tester.tap(find.byKey(const Key('strategy-retry-preview')));
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const Key('strategy-retry-create')));
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const Key('strategy-retry-prepare')));
    await _pumpFrames(tester);

    expect(api.prepareCalls, 1);
    expect(api.preparedId, 'retry-child-1');
    expect(
      find.textContaining('bản PREPARED vẫn còn trong lịch sử'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('strategy-retry-cancel-flow')));
    await tester.pumpAndSettle();

    expect(api.executeCalls, 0);
    await _openStrategyDetails(tester, 'retry-child-1');
    expect(
      find.textContaining(
        'Bản gửi lại retry-child-1 liên kết với nguồn source-1 · source-order-1',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Widget _app(_RetryDialogApi api) => ProviderScope(
  overrides: [
    tradeSessionProvider.overrideWith(
      (ref) => _AuthenticatedSessionController(),
    ),
    strategyApiProvider.overrideWithValue(api),
    strategyMarketRepositoryProvider.overrideWithValue(_FakeMarketRepository()),
  ],
  child: const MaterialApp(home: StrategyScreen()),
);

Future<void> _openRetryDialog(WidgetTester tester) async {
  final retry = find.byKey(const Key('strategy-retry-source-1'));
  await tester.scrollUntilVisible(
    retry,
    220,
    scrollable: find.byType(Scrollable).first,
  );
  expect(retry, findsOneWidget);
  await tester.ensureVisible(retry);
  await _pumpFrames(tester);
  await tester.tap(retry);
  await _pumpFrames(tester);
}

Future<void> _openStrategyDetails(
  WidgetTester tester,
  String strategyId,
) async {
  final summary = find.byKey(Key('strategy-summary-$strategyId'));
  await tester.ensureVisible(summary);
  await tester.pump();
  await tester.tap(summary);
  await _pumpFrames(tester);
}

Future<void> _tapCandidate(WidgetTester tester, String sourceOrderId) async {
  final candidate = find.byKey(Key('strategy-retry-candidate-$sourceOrderId'));
  await tester.ensureVisible(candidate);
  await tester.pump();
  await tester.tap(candidate);
}

Future<void> _pumpFrames(WidgetTester tester, [int count = 6]) async {
  for (var frame = 0; frame < count; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

class _AuthenticatedSessionController extends TradeSessionController {
  _AuthenticatedSessionController()
    : super(TradeApiClient(baseUrl: 'https://trade.example')) {
    state = TradeSessionState(
      session: TradeSession(
        bearerToken: 'retry-test-token',
        accountIdentifier: 'retry-test-account',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
  }
}

class _RetryDialogApi implements StrategyApi {
  int candidateCalls = 0;
  int previewCalls = 0;
  int createCalls = 0;
  int prepareCalls = 0;
  int executeCalls = 0;
  String? previewSourceRevision;
  List<String> previewSourceOrderIds = const [];
  String? createSourceStrategyId;
  String? createSourceRevision;
  List<String> createSourceOrderIds = const [];
  String? createPreviewHash;
  String? retryRequestId;
  String? preparedId;
  String? executedId;
  StrategyRetryPreview? lastPreview;
  bool linkedChildListed = false;
  Completer<StrategyRetryDraft>? createCompleter;
  Completer<Map<String, dynamic>>? executeCompleter;

  final executionResult = {
    'id': 'retry-child-1',
    'status': 'APPLIED',
    'resubmission': {
      'sourceStrategyId': 'source-1',
      'sourceClientOrderIds': ['source-order-1'],
    },
  };

  List<Map<String, dynamic>> get _strategies => [
    {
      'id': 'source-1',
      'instrumentId': 'BTC-USDT-SWAP',
      'interval': '6Hutc',
      'status': 'APPLIED',
      'submissionMode': 'batch',
      'canDelete': false,
      'orders': [
        {
          'side': 'long',
          'role': 'entry',
          'limitPrice': '65000',
          'contracts': '1',
          'status': 'not_submitted',
        },
      ],
    },
    if (linkedChildListed)
      {
        'id': 'retry-child-1',
        'instrumentId': 'BTC-USDT-SWAP',
        'interval': '6Hutc',
        'status': 'DRAFT',
        'resubmission': {
          'sourceStrategyId': 'source-1',
          'sourceClientOrderIds': ['source-order-1'],
        },
        'orders': [_retryOrder(clientOrderId: 'retry-child-order-1')],
      },
  ];

  @override
  Future<StrategyRetryCandidates> getRetryCandidates(
    String token,
    String sourceStrategyId,
  ) async {
    candidateCalls++;
    return StrategyRetryCandidates(
      sourceStrategyId: sourceStrategyId,
      sourceRevision: 'source-revision-1',
      candidates:
          [
            for (var index = 0; index < 11; index++)
              StrategyRetryCandidate(
                sourceClientOrderId: 'source-order-$index',
                side: 'long',
                role: 'entry',
                limitPrice: '65000.123456',
                contracts: '1',
                leverage: '5',
                priorOutcome: 'not_submitted',
                eligible: true,
                reason: null,
                levelId: null,
              ),
          ]..add(
            StrategyRetryCandidate(
              sourceClientOrderId: 'source-order-excluded',
              side: 'short',
              role: 'entry',
              limitPrice: '64000',
              contracts: '1',
              leverage: '5',
              priorOutcome: 'other',
              eligible: false,
              reason: 'missing_evidence',
              levelId: null,
            ),
          ),
      blockedReason: null,
      linkedChildren: const [],
    );
  }

  @override
  Future<StrategyRetryPreview> previewRetry(
    String token,
    String sourceStrategyId, {
    required String sourceRevision,
    required List<String> sourceClientOrderIds,
  }) async {
    previewCalls++;
    previewSourceRevision = sourceRevision;
    previewSourceOrderIds = List.unmodifiable(sourceClientOrderIds);
    lastPreview = _retryPreview(sourceStrategyId, sourceClientOrderIds);
    return lastPreview!;
  }

  @override
  Future<StrategyRetryDraft> createRetryDraft(
    String token,
    String sourceStrategyId, {
    required String sourceRevision,
    required List<String> sourceClientOrderIds,
    required String previewHash,
    required String retryRequestId,
  }) async {
    createCalls++;
    createSourceStrategyId = sourceStrategyId;
    createSourceRevision = sourceRevision;
    createSourceOrderIds = List.unmodifiable(sourceClientOrderIds);
    createPreviewHash = previewHash;
    this.retryRequestId = retryRequestId;
    if (createCompleter != null) return createCompleter!.future;
    linkedChildListed = true;
    return _retryDraft();
  }

  @override
  Future<Map<String, dynamic>> preview(
    String token,
    Map<String, dynamic> body,
  ) async => {};

  @override
  Future<Map<String, dynamic>> saveDraft(
    String token,
    Map<String, dynamic> body,
  ) async => {'id': 'draft-1'};

  @override
  Future<List<Map<String, dynamic>>> listStrategies(String token) async =>
      _strategies;

  @override
  Future<Map<String, dynamic>> prepareApply(String token, String id) async {
    prepareCalls++;
    preparedId = id;
    return _retryPrepared();
  }

  @override
  Future<Map<String, dynamic>> executeApply(
    String token,
    String id,
    String confirmationToken,
  ) async {
    executeCalls++;
    executedId = id;
    if (executeCompleter != null) return executeCompleter!.future;
    return executionResult;
  }

  @override
  Future<Map<String, dynamic>> getResult(String token, String id) async => {
    'id': id,
    'status': 'APPLIED',
  };

  @override
  Future<Map<String, dynamic>> getQuote(String token, String id) async => {
    'instrumentId': 'BTC-USDT-SWAP',
    'lastPrice': '65000',
    'observedAt': DateTime.now().toUtc().toIso8601String(),
  };

  @override
  Future<String> getLimitOrderSubmissionMode(String token) async => 'batch';

  @override
  Future<String> saveLimitOrderSubmissionMode(
    String token,
    String mode,
  ) async => mode;

  @override
  Future<void> deleteDraft(String token, String id) async {}
}

StrategyRetryPreview _retryPreview(
  String sourceId,
  List<String> sourceOrderIds,
) {
  final order = _retryOrder(sourceClientOrderId: sourceOrderIds.single);
  final raw = <String, dynamic>{
    'sourceStrategyId': sourceId,
    'sourceRevision': 'source-revision-1',
    'selectedSourceClientOrderIds': sourceOrderIds,
    'previewHash': 'retry-hash-1',
    'instrumentId': 'BTC-USDT-SWAP',
    'interval': '6Hutc',
    'allocation': 'fixed',
    'feesOutsideMargin': true,
    'currentPrice': '65000.123456',
    'quoteTimestamp': '2026-10-03T00:00:00Z',
    'sidePercent': {'long': '100', 'short': '0'},
    'sides': [
      {'side': 'long', 'contracts': '1'},
    ],
    'totalMargin': '1234.56789',
    'plannedMargin': '1234.56789',
    'unallocatedMargin': '0',
    'estimatedOpeningFees': '0.000000003',
    'requiredBalance': '1234.567890003',
    'orders': [order],
  };
  return StrategyRetryPreview(
    sourceStrategyId: sourceId,
    sourceRevision: 'source-revision-1',
    selectedSourceClientOrderIds: List.unmodifiable(sourceOrderIds),
    previewHash: 'retry-hash-1',
    orders: [order],
    totalMargin: '1234.56789',
    plannedMargin: '1234.56789',
    unallocatedMargin: '0',
    estimatedOpeningFees: '0.000000003',
    requiredBalance: '1234.567890003',
    raw: raw,
  );
}

StrategyRetryDraft _retryDraft() {
  final preview = _retryPreview('source-1', ['source-order-1']);
  final order = _retryOrder(
    sourceClientOrderId: 'source-order-1',
    clientOrderId: 'retry-child-order-1',
  );
  final nestedPreview = StrategyRetryPreview(
    sourceStrategyId: preview.sourceStrategyId,
    sourceRevision: preview.sourceRevision,
    selectedSourceClientOrderIds: preview.selectedSourceClientOrderIds,
    previewHash: preview.previewHash,
    orders: [order],
    totalMargin: preview.totalMargin,
    plannedMargin: preview.plannedMargin,
    unallocatedMargin: preview.unallocatedMargin,
    estimatedOpeningFees: preview.estimatedOpeningFees,
    requiredBalance: preview.requiredBalance,
    raw: {
      ...preview.raw,
      'orders': [order],
    },
  );
  return StrategyRetryDraft(
    id: 'retry-child-1',
    status: 'DRAFT',
    orders: [order],
    resubmission: {
      'sourceStrategyId': 'source-1',
      'sourceClientOrderIds': ['source-order-1'],
    },
    preview: nestedPreview,
    raw: {
      'id': 'retry-child-1',
      'status': 'DRAFT',
      'orders': [order],
      'resubmission': {
        'sourceStrategyId': 'source-1',
        'sourceClientOrderIds': ['source-order-1'],
      },
      'preview': nestedPreview.raw,
    },
  );
}

Map<String, dynamic> _retryPrepared() => {
  'id': 'retry-child-1',
  'status': 'PREPARED',
  'confirmationToken': 'one-use-retry-token',
  'expiresAt': '2026-10-03T00:01:00Z',
  'plannedMargin': '1234.56789',
  'unallocatedMargin': '0',
  'estimatedOpeningFees': '0.000000003',
  'quoteTimestamp': '2026-10-03T00:00:00Z',
  'submissionMode': 'batch',
  'resubmission': {
    'sourceStrategyId': 'source-1',
    'sourceClientOrderIds': ['source-order-1'],
  },
  'orders': [
    _retryOrder(
      sourceClientOrderId: 'source-order-1',
      clientOrderId: 'retry-child-order-1',
    ),
  ],
};

Map<String, dynamic> _retryOrder({
  String sourceClientOrderId = 'source-order-1',
  String? clientOrderId,
}) => {
  'sourceClientOrderId': sourceClientOrderId,
  if (clientOrderId != null) 'clientOrderId': clientOrderId,
  'side': 'long',
  'role': 'entry',
  'limitPrice': '65000.123456',
  'contracts': '1',
  'leverage': '5',
  'margin': '1234.56789',
  'allocatedMargin': '1234.56789',
  'notional': '65000',
  'openingFeeEstimate': '0.000000003',
  'allocationWeight': '1',
  'cumulativeContracts': '1',
  'cumulativeAverageEntry': '65000.123456',
  'liquidationEstimate': {'price': '64000.123456', 'method': 'cross'},
};

class _FakeMarketRepository extends StrategyMarketRepository {
  _FakeMarketRepository()
    : super(
        BackendDataClient(dio: Dio(), baseUrl: 'https://data.example'),
        requestCoordinator: RiskRequestCoordinator(
          minimumSpacing: Duration.zero,
          delay: (_) async {},
        ),
      );

  @override
  Future<List<StrategyInstrument>> getInstruments() async => const [];

  @override
  Future<StrategyMarketSnapshot> loadLevels({
    required String instrumentId,
    required StrategyInterval interval,
    required String tickSizeText,
  }) async => throw UnimplementedError();

  @override
  Future<StrategyTicker> getTicker({required String instrumentId}) async =>
      throw UnimplementedError();
}
