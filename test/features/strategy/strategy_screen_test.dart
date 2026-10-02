import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/orders/data/trade_api_client.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/trade_session_provider.dart';
import 'package:trading_balance_f/features/portfolio/data/risk/risk_request_coordinator.dart';
import 'package:trading_balance_f/features/strategy/data/strategy_api_client.dart';
import 'package:trading_balance_f/features/strategy/data/strategy_market_repository.dart';
import 'package:trading_balance_f/features/strategy/domain/strategy_models.dart';
import 'package:trading_balance_f/features/strategy/presentation/strategy_screen.dart';
import 'package:trading_balance_f/features/strategy/presentation/strategy_wizard_dialog.dart';

void main() {
  testWidgets('started cards use backend quotes and show order freshness', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final market = _FakeMarketRepository();
    final api = _FakeStrategyApi();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tradeSessionProvider.overrideWith(
            (ref) => _AuthenticatedSessionController(),
          ),
          strategyApiProvider.overrideWithValue(api),
          strategyMarketRepositoryProvider.overrideWithValue(market),
        ],
        child: const MaterialApp(home: StrategyScreen()),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(api.quoteCalls, 1);
    expect(market.tickerCalls, 0);
    expect(find.text('BTC-USDT-SWAP'), findsNWidgets(2));
    final draftCard = find.ancestor(
      of: find.text('Bản nháp'),
      matching: find.byType(Card),
    );
    final startedCard = find.ancestor(
      of: find.text('Đã gửi'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(
        of: startedCard.first,
        matching: find.textContaining('Giá SWAP 65000'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: draftCard.first,
        matching: find.textContaining('Giá SWAP 65000'),
      ),
      findsNothing,
    );
    expect(find.text('Khớp một phần'), findsOneWidget);
    expect(find.text('Đã khớp'), findsOneWidget);
    expect(find.text('Đã hủy'), findsOneWidget);
    expect(find.text('Chưa xác định'), findsOneWidget);
    expect(
      find.descendant(
        of: startedCard.first,
        matching: find.textContaining('Khớp: 2 / 5 hợp đồng'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: startedCard.first,
        matching: find.textContaining('Giá khớp TB: 58990'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Lần quét lệnh đã cũ'), findsOneWidget);
  });

  testWidgets('completed strategy status is distinct', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _FakeStrategyApi()..includeCompleted = true;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tradeSessionProvider.overrideWith(
            (ref) => _AuthenticatedSessionController(),
          ),
          strategyApiProvider.overrideWithValue(api),
          strategyMarketRepositoryProvider.overrideWithValue(
            _FakeMarketRepository(),
          ),
        ],
        child: const MaterialApp(home: StrategyScreen()),
      ),
    );
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(find.text('Hoàn tất'), findsOneWidget);
    final completedCard = find.ancestor(
      of: find.text('Hoàn tất'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(of: completedCard, matching: find.text('Đã khớp')),
      findsOneWidget,
    );
  });

  testWidgets('never-sent diagnosis and actions require server eligibility', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _FakeStrategyApi()..includeNeverSent = true;
    final market = _FakeMarketRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tradeSessionProvider.overrideWith(
            (ref) => _AuthenticatedSessionController(),
          ),
          strategyApiProvider.overrideWithValue(api),
          strategyMarketRepositoryProvider.overrideWithValue(market),
        ],
        child: const MaterialApp(home: StrategyScreen()),
      ),
    );
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    final eligibleCard = find
        .ancestor(of: find.text('ETH-USDT-SWAP'), matching: find.byType(Card))
        .first;
    expect(
      find.descendant(of: eligibleCard, matching: find.text('Chưa gửi')),
      findsNWidgets(2),
    );
    expect(
      find.descendant(
        of: eligibleCard,
        matching: find.textContaining('Không có lệnh nào được gửi lên OKX'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: eligibleCard, matching: find.textContaining('51008')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: eligibleCard,
        matching: find.textContaining('Lần quét lệnh đã cũ'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: eligibleCard, matching: find.text('Tạo lại')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: eligibleCard, matching: find.text('Xóa chiến thuật')),
      findsOneWidget,
    );
    expect(
      find.textContaining('OKX đã chấp nhận đầy đủ lệnh thay thế'),
      findsOneWidget,
    );
    final draftCard = find
        .ancestor(of: find.text('Bản nháp'), matching: find.byType(Card))
        .first;
    expect(
      find.descendant(of: draftCard, matching: find.text('Tạo lại')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: draftCard,
        matching: find.textContaining('Không có lệnh nào được gửi lên OKX'),
      ),
      findsNothing,
    );
    expect(find.text('Tạo lại'), findsNWidgets(2));
    expect(
      find.textContaining('Không có lệnh nào được gửi lên OKX'),
      findsOneWidget,
    );
    final replaceButton = find.descendant(
      of: eligibleCard,
      matching: find.text('Tạo lại'),
    );
    await tester.scrollUntilVisible(
      replaceButton,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(replaceButton);
    await tester.pumpAndSettle();
    final replacementWizard = tester.widget<StrategyWizardDialog>(
      find.byType(StrategyWizardDialog),
    );
    expect(replacementWizard.replacementSourceId, 'never-sent-1');
    expect(market.loadLevelsCalls, 1);
    expect(
      tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .every((checkbox) => checkbox.value == false),
      isTrue,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Hủy'));
    await tester.pumpAndSettle();

    final deleteButton = find.descendant(
      of: eligibleCard,
      matching: find.text('Xóa chiến thuật'),
    );
    await tester.scrollUntilVisible(
      deleteButton,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Chỉ xóa bản ghi chiến thuật trong ứng dụng'),
      findsOneWidget,
    );
    expect(api.deleteCalls, 0);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Xóa chiến thuật'),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.deleteCalls, 1);
    await tester.scrollUntilVisible(
      find.text('ADA-USDT-SWAP'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final genericFailureCard = find
        .ancestor(of: find.text('ADA-USDT-SWAP'), matching: find.byType(Card))
        .first;
    expect(
      find.descendant(
        of: genericFailureCard,
        matching: find.textContaining('Không có lệnh nào được gửi lên OKX'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: genericFailureCard, matching: find.text('Tạo lại')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: genericFailureCard,
        matching: find.textContaining('OKX từ chối thiết lập đòn bẩy'),
      ),
      findsNothing,
    );

    for (final instrument in ['SOL-USDT-SWAP', 'XRP-USDT-SWAP']) {
      await tester.scrollUntilVisible(
        find.text(instrument),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      final card = find
          .ancestor(of: find.text(instrument), matching: find.byType(Card))
          .first;
      expect(
        find.descendant(of: card, matching: find.text('Tạo lại')),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.text('Xóa chiến thuật')),
        findsNothing,
      );
    }
  });
}

class _AuthenticatedSessionController extends TradeSessionController {
  _AuthenticatedSessionController()
    : super(TradeApiClient(baseUrl: 'https://trade.example')) {
    state = TradeSessionState(
      session: TradeSession(
        bearerToken: 'test-token',
        accountIdentifier: 'test-account',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
  }
}

class _FakeStrategyApi implements StrategyApi {
  int quoteCalls = 0;
  int deleteCalls = 0;
  bool includeCompleted = false;
  bool includeNeverSent = false;

  final strategies = <Map<String, dynamic>>[
    {
      'id': 'draft-1',
      'instrumentId': 'BTC-USDT-SWAP',
      'interval': '6Hutc',
      'status': 'DRAFT',
      'batchAttempted': false,
      'canDelete': true,
    },
    {
      'id': 'started-1',
      'instrumentId': 'BTC-USDT-SWAP',
      'interval': '6Hutc',
      'status': 'APPLIED',
      'orders': [
        {
          'side': 'long',
          'role': 'entry',
          'limitPrice': '59000',
          'contracts': '5',
          'status': 'partially_filled',
          'filledContracts': '2',
          'averageFillPrice': '58990',
        },
        {
          'side': 'long',
          'role': 'dca',
          'limitPrice': '58000',
          'contracts': '5',
          'status': 'filled',
          'filledContracts': '5',
          'averageFillPrice': '58010',
        },
        {
          'side': 'short',
          'role': 'entry',
          'limitPrice': '61000',
          'contracts': '5',
          'status': 'canceled',
          'filledContracts': '0',
        },
        {
          'side': 'short',
          'role': 'dca',
          'limitPrice': '62000',
          'contracts': '5',
          'status': 'unknown',
          'filledContracts': null,
        },
      ],
      'lastOrderScanAt': '2026-10-02T00:00:00Z',
      'orderSyncState': 'stale',
    },
  ];

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
  Future<Map<String, dynamic>> prepareApply(String token, String id) async =>
      {};

  @override
  Future<Map<String, dynamic>> executeApply(
    String token,
    String id,
    String confirmationToken,
  ) async => {};

  @override
  Future<Map<String, dynamic>> getResult(String token, String id) async => {};

  @override
  Future<Map<String, dynamic>> getQuote(String token, String id) async {
    quoteCalls++;
    return {
      'instrumentId': 'BTC-USDT-SWAP',
      'lastPrice': '65000',
      'observedAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  @override
  Future<void> deleteDraft(String token, String id) async {
    deleteCalls++;
  }

  List<Map<String, dynamic>> get strategiesForTest {
    final result = [...strategies];
    if (includeCompleted) {
      result.add({
        'id': 'completed-1',
        'instrumentId': 'ETH-USDT-SWAP',
        'interval': '6Hutc',
        'status': 'COMPLETED',
        'orders': [
          {
            'side': 'long',
            'role': 'entry',
            'limitPrice': '3000',
            'contracts': '1',
            'status': 'filled',
            'filledContracts': '1',
            'averageFillPrice': '3000',
          },
        ],
        'lastOrderScanAt': '2026-10-02T00:00:00Z',
        'orderSyncState': 'fresh',
      });
    }
    if (includeNeverSent) {
      final startedIndex = result.indexWhere(
        (strategy) => strategy['id'] == 'started-1',
      );
      if (startedIndex >= 0) {
        result[startedIndex] = {
          ...result[startedIndex],
          'replacementCleanupConflict': true,
        };
      }
      result.addAll([
        {
          'id': 'never-sent-1',
          'instrumentId': 'ETH-USDT-SWAP',
          'interval': '6Hutc',
          'status': 'PARTIAL',
          'batchAttempted': false,
          'canDelete': true,
          'failureReason': 'leverage_rejected',
          'leverageResults': [
            {'errorCode': '51008'},
          ],
          'orders': [
            {
              'side': 'long',
              'role': 'entry',
              'limitPrice': '3000',
              'contracts': '1',
              'status': 'not_submitted',
              'filledContracts': '0',
            },
          ],
          'lastOrderScanAt': '2026-10-02T00:00:00Z',
          'orderSyncState': 'stale',
        },
        {
          'id': 'not-eligible-1',
          'instrumentId': 'SOL-USDT-SWAP',
          'interval': '6Hutc',
          'status': 'PARTIAL',
          'batchAttempted': false,
          'canDelete': false,
          'failureReason': 'never_sent',
        },
        {
          'id': 'attempted-1',
          'instrumentId': 'XRP-USDT-SWAP',
          'interval': '6Hutc',
          'status': 'PARTIAL',
          'batchAttempted': true,
          'canDelete': false,
          'failureReason': 'unknown',
        },
        {
          'id': 'never-sent-other-failure',
          'instrumentId': 'ADA-USDT-SWAP',
          'interval': '6Hutc',
          'status': 'UNKNOWN',
          'batchAttempted': false,
          'canDelete': true,
          'failureReason': 'interrupted_before_batch',
          'orders': [
            {
              'side': 'long',
              'role': 'entry',
              'limitPrice': '3000',
              'contracts': '1',
              'status': 'not_submitted',
              'filledContracts': '0',
            },
          ],
        },
      ]);
    }
    return result;
  }

  @override
  Future<List<Map<String, dynamic>>> listStrategies(String token) async =>
      strategiesForTest;
}

class _FakeMarketRepository extends StrategyMarketRepository {
  _FakeMarketRepository()
    : super(
        Dio(BaseOptions(baseUrl: 'https://www.okx.com')),
        requestCoordinator: RiskRequestCoordinator(
          minimumSpacing: Duration.zero,
          delay: (_) async {},
        ),
      );

  int tickerCalls = 0;
  int loadLevelsCalls = 0;

  @override
  Future<List<StrategyInstrument>> getInstruments() async => const [
    StrategyInstrument(
      instrumentId: 'BTC-USDT-SWAP',
      base: 'BTC',
      tickSizeText: '0.01',
    ),
  ];

  @override
  Future<StrategyMarketSnapshot> loadLevels({
    required String instrumentId,
    required StrategyInterval interval,
    required String tickSizeText,
  }) async {
    loadLevelsCalls++;
    final candles = List.generate(5, (index) {
      final swing = index == 2;
      return StrategyCandle(
        timestamp: DateTime.utc(
          2030,
          1,
          1,
        ).add(Duration(microseconds: interval.duration.inMicroseconds * index)),
        open: 65000,
        high: swing ? 66000 : 65500,
        low: swing ? 64000 : 64500,
        close: 65000,
        interval: interval,
      );
    });
    final ticker = await getTicker(instrumentId: instrumentId);
    final calculated = calculator.calculate(
      candles: candles,
      referencePrice: ticker.lastPrice,
      tickSizeText: tickSizeText,
    );
    return StrategyMarketSnapshot(
      instrumentId: instrumentId,
      interval: interval,
      ticker: ticker,
      candles: candles,
      analysis: StrategyAnalysis(
        referencePrice: ticker.lastPrice,
        supports: calculated.supports,
        resistances: calculated.resistances,
      ),
    );
  }

  @override
  Future<StrategyTicker> getTicker({required String instrumentId}) async {
    tickerCalls++;
    return StrategyTicker(
      instrumentId: instrumentId,
      lastPrice: 65000,
      observedAt: DateTime.now().toUtc(),
    );
  }
}
