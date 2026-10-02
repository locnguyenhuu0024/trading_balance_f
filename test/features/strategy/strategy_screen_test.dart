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
  testWidgets('only started cards display a shared live quote', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final market = _FakeMarketRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tradeSessionProvider.overrideWith(
            (ref) => _AuthenticatedSessionController(),
          ),
          strategyApiProvider.overrideWithValue(_FakeStrategyApi()),
          strategyMarketRepositoryProvider.overrideWithValue(market),
        ],
        child: const MaterialApp(home: StrategyScreen()),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(market.tickerCalls, 1);
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
  Future<List<Map<String, dynamic>>> listStrategies(String token) async =>
      strategies;

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
  Future<void> deleteDraft(String token, String id) async {}
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
