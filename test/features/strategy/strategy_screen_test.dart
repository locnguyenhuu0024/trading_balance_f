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

void main() {
  testWidgets('started cards use backend quotes and show order freshness', (tester) async {
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
      find.descendant(
        of: completedCard,
        matching: find.text('Đã khớp'),
      ),
      findsOneWidget,
    );
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
  bool includeCompleted = false;

  final strategies = <Map<String, dynamic>>[
    {
      'id': 'draft-1',
      'instrumentId': 'BTC-USDT-SWAP',
      'interval': '6Hutc',
      'status': 'DRAFT',
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
  Future<void> deleteDraft(String token, String id) async {}

  List<Map<String, dynamic>> get strategiesForTest {
    if (!includeCompleted) return strategies;
    return [
      ...strategies,
      {
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
      },
    ];
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
