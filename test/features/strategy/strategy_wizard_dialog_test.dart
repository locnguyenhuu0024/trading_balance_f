import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/orders/data/trade_api_client.dart';
import 'package:trading_balance_f/features/portfolio/data/risk/risk_request_coordinator.dart';
import 'package:trading_balance_f/features/strategy/data/strategy_api_client.dart';
import 'package:trading_balance_f/features/strategy/data/strategy_market_repository.dart';
import 'package:trading_balance_f/features/strategy/domain/strategy_models.dart';
import 'package:trading_balance_f/features/strategy/presentation/providers/strategy_dashboard_provider.dart';
import 'package:trading_balance_f/features/strategy/presentation/strategy_wizard_dialog.dart';

void main() {
  testWidgets('shows why step one cannot continue without a selection', (
    tester,
  ) async {
    final market = _FakeStrategyMarketRepository();
    final api = _FakeStrategyApi();
    final dashboard = _dashboard(api, market);
    addTearDown(dashboard.dispose);
    await _pumpWizard(tester, market, api, dashboard);

    expect(
      find.text(
        'Chọn ít nhất một mức hợp lệ và điểm vào gần giá nhất cho mỗi phía.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('strategy-next-step-one')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('stale quote does not block navigation but blocks preview', (
    tester,
  ) async {
    final market = _FakeStrategyMarketRepository()
      ..tickerAge = const Duration(seconds: 16);
    final api = _FakeStrategyApi();
    final dashboard = _dashboard(api, market);
    addTearDown(dashboard.dispose);
    await _pumpWizard(tester, market, api, dashboard);

    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    expect(find.textContaining('đã cũ'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('strategy-next-step-one')))
          .onPressed,
      isNotNull,
    );
    expect(find.byTooltip('Làm mới báo giá'), findsOneWidget);
    await tester.tap(find.byKey(const Key('strategy-next-step-one')));
    await tester.pumpAndSettle();

    expect(find.text('Bước 2 / 3 · Ký quỹ và đòn bẩy'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('strategy-margin-input')),
      '100',
    );
    await tester.tap(find.byKey(const Key('strategy-request-preview')));
    await tester.pump();

    expect(api.previewBodies, isEmpty);
    expect(
      find.text(
        'Giá SWAP đã cũ. Quay lại bước chọn vùng và nhấn làm mới trước khi xem lại.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('preview failure can be retried without losing inputs', (
    tester,
  ) async {
    final market = _FakeStrategyMarketRepository();
    final api = _FakeStrategyApi()
      ..nextPreviewError = const StrategyApiException(
        code: 'network_error',
        statusCode: 503,
        message: 'Máy chủ xem trước đang gặp sự cố. (HTTP 503)',
      );
    final dashboard = _dashboard(api, market);
    addTearDown(dashboard.dispose);
    await _pumpWizard(tester, market, api, dashboard);

    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    await tester.tap(find.byKey(const Key('strategy-next-step-one')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('strategy-margin-input')),
      '100',
    );
    await tester.tap(find.byKey(const Key('strategy-request-preview')));
    await tester.pumpAndSettle();

    expect(find.text('Bước 2 / 3 · Ký quỹ và đòn bẩy'), findsOneWidget);
    expect(find.textContaining('HTTP 503'), findsOneWidget);
    expect(api.previewBodies, hasLength(1));
    expect(api.previewBodies.single['totalMargin'], '100');
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('strategy-request-preview')),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const Key('strategy-request-preview')));
    await tester.pumpAndSettle();

    expect(find.text('Bước 3 / 3 · Xem lại và xác nhận'), findsOneWidget);
    expect(api.previewBodies, hasLength(2));
    expect(api.previewBodies[1], api.previewBodies[0]);
  });

  testWidgets(
    'manual quote retry bypasses backoff without overlapping a request',
    (tester) async {
      final market = _FakeStrategyMarketRepository()
        ..tickerAge = const Duration(seconds: 16)
        ..pendingAutomaticRefresh = Completer<StrategyTicker>();
      final api = _FakeStrategyApi();
      final dashboard = _dashboard(api, market);
      addTearDown(dashboard.dispose);
      await _pumpWizard(tester, market, api, dashboard);

      expect(market.tickerRequests, 2);
      await tester.tap(find.byTooltip('Làm mới báo giá'));
      await tester.pump();
      expect(market.tickerRequests, 2);

      market.pendingAutomaticRefresh!.completeError(
        const StrategyMarketException('Temporary ticker failure.'),
      );
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('đã cũ'), findsOneWidget);

      await tester.tap(find.byTooltip('Làm mới báo giá'));
      await tester.pumpAndSettle();

      expect(market.tickerRequests, 3);
      expect(find.textContaining('đã cũ'), findsNothing);
    },
  );

  testWidgets('quote between five and fifteen seconds remains usable', (
    tester,
  ) async {
    final market = _FakeStrategyMarketRepository()
      ..tickerAge = const Duration(seconds: 10);
    final api = _FakeStrategyApi();
    final dashboard = _dashboard(api, market);
    addTearDown(dashboard.dispose);
    await _pumpWizard(tester, market, api, dashboard);

    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    expect(find.textContaining('đã cũ'), findsNothing);
    await tester.tap(find.byKey(const Key('strategy-next-step-one')));
    await tester.pumpAndSettle();
    expect(find.text('Bước 2 / 3 · Ký quỹ và đòn bẩy'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('strategy-margin-input')),
      '100',
    );
    await tester.tap(find.byKey(const Key('strategy-request-preview')));
    await tester.pumpAndSettle();
    expect(api.previewBodies, hasLength(1));
  });

  testWidgets('price crossing removes invalid choice and retains valid one', (
    tester,
  ) async {
    final market = _FakeStrategyMarketRepository();
    final api = _FakeStrategyApi();
    final dashboard = _dashboard(api, market);
    addTearDown(dashboard.dispose);
    await _pumpWizard(tester, market, api, dashboard);

    await tester.tap(find.byKey(const Key('strategy-direction-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Long và Short'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    await tester.tap(find.byType(CheckboxListTile).last);
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('strategy-next-step-one')))
          .onPressed,
      isNotNull,
    );

    market.tickerPrice = 120;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(
      find.text(
        'Giá đã di chuyển; mức không còn hợp lệ đã được bỏ chọn. Vui lòng kiểm tra lựa chọn.',
      ),
      findsOneWidget,
    );
    final checkboxes = tester
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .toList();
    expect(checkboxes.map((item) => item.value), [false, true]);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('strategy-next-step-one')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('search filters locally and only selection changes instrument', (
    tester,
  ) async {
    final market = _FakeStrategyMarketRepository();
    final api = _FakeStrategyApi();
    final dashboard = _dashboard(api, market);
    addTearDown(dashboard.dispose);
    await _pumpWizard(tester, market, api, dashboard);

    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    await tester.tap(find.byKey(const Key('strategy-instrument-picker')));
    await tester.pumpAndSettle();
    final search = find.byKey(const Key('strategy-instrument-search'));
    expect(
      find.byKey(const Key('strategy-instrument-option-BTC-USDT-SWAP')),
      findsOneWidget,
    );
    await tester.enterText(search, ' eth ');
    await tester.pump();
    expect(
      find.byKey(const Key('strategy-instrument-option-ETH-USDT-SWAP')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('strategy-instrument-option-BTC-USDT-SWAP')),
      findsNothing,
    );

    await tester.enterText(search, 'no-such-coin');
    await tester.pump();
    expect(find.text('Không tìm thấy hợp đồng phù hợp.'), findsOneWidget);

    await tester.enterText(search, 'eth-usdt-swap');
    await tester.pump();
    expect(
      find.byKey(const Key('strategy-instrument-option-ETH-USDT-SWAP')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('strategy-instrument-picker-close')));
    await tester.pumpAndSettle();
    expect(_selectedInstrument('BTC-USDT-SWAP'), findsOneWidget);
    expect(
      tester
          .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
          .value,
      isTrue,
    );
    expect(market.loadCalls, ['BTC-USDT-SWAP']);
    expect(market.instrumentCatalogCalls, 1);

    await tester.tap(find.byKey(const Key('strategy-instrument-picker')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('strategy-instrument-search')),
      'ETH-USDT-SWAP',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('strategy-instrument-option-ETH-USDT-SWAP')),
    );
    await tester.pumpAndSettle();

    expect(_selectedInstrument('ETH-USDT-SWAP'), findsOneWidget);
    expect(market.loadCalls, ['BTC-USDT-SWAP', 'ETH-USDT-SWAP']);
    expect(market.instrumentCatalogCalls, 1);
  });

  testWidgets('comma-decimal margin reaches preview as decimal strings', (
    tester,
  ) async {
    final market = _FakeStrategyMarketRepository();
    final api = _FakeStrategyApi();
    final dashboard = _dashboard(api, market);
    addTearDown(dashboard.dispose);
    await _pumpWizard(tester, market, api, dashboard);

    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    await tester.tap(find.byKey(const Key('strategy-next-step-one')));
    await tester.pump();
    const cases = {'100': '100', '100.0': '100.0', '100,0': '100.0'};
    var caseIndex = 0;
    for (final entry in cases.entries) {
      if (caseIndex > 0) {
        await tester.tap(find.text('Quay lại'));
        await tester.pumpAndSettle();
      }
      await tester.enterText(
        find.byKey(const Key('strategy-margin-input')),
        entry.key,
      );
      await tester.tap(find.byKey(const Key('strategy-request-preview')));
      await tester.pumpAndSettle();

      expect(api.previewBodies, hasLength(caseIndex + 1));
      final request = api.previewBodies.last;
      expect(request['totalMargin'], entry.value);
      expect(request['selectedLevels'], [
        {'side': 'long', 'price': '90.0'},
      ]);
      expect(request['entryBySide'], {'long': '90.0'});
      expect(find.text('Nhập ngân sách ký quỹ USDT lớn hơn 0.'), findsNothing);
      caseIndex++;
    }

    await tester.tap(find.byKey(const Key('strategy-save-draft')));
    await tester.pumpAndSettle();
    expect(api.saveBodies, hasLength(1));
    expect(api.saveBodies.single['totalMargin'], '100.0');
    expect(api.saveBodies.single['selectedLevels'], [
      {'side': 'long', 'price': '90.0'},
    ]);
    expect(api.saveBodies.single['entryBySide'], {'long': '90.0'});
  });

  testWidgets('normalizes Long percentage comma and rejects malformed margin', (
    tester,
  ) async {
    final market = _FakeStrategyMarketRepository();
    final api = _FakeStrategyApi();
    final dashboard = _dashboard(api, market);
    addTearDown(dashboard.dispose);
    await _pumpWizard(tester, market, api, dashboard);

    await tester.tap(find.byKey(const Key('strategy-direction-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Long và Short'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    await tester.tap(find.byType(CheckboxListTile).last);
    await tester.pump();
    await tester.tap(find.byKey(const Key('strategy-next-step-one')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('strategy-margin-input')),
      '100',
    );
    await tester.enterText(
      find.byKey(const Key('strategy-long-percent-input')),
      '50,5',
    );
    await tester.tap(find.byKey(const Key('strategy-request-preview')));
    await tester.pumpAndSettle();

    expect(api.previewBodies, hasLength(1));
    expect(api.previewBodies.single['sidePercent'], {
      'long': '50.5',
      'short': '49.5',
    });

    await tester.tap(find.text('Quay lại'));
    await tester.pumpAndSettle();
    for (final malformed in ['1,000', '100,0.0', '100 USDT', '0', '-100']) {
      await tester.enterText(
        find.byKey(const Key('strategy-margin-input')),
        malformed,
      );
      await tester.tap(find.byKey(const Key('strategy-request-preview')));
      await tester.pump();
      expect(api.previewBodies, hasLength(1));
      expect(
        find.text('Nhập ngân sách ký quỹ USDT lớn hơn 0.'),
        findsOneWidget,
      );
    }
  });
}

Finder _selectedInstrument(String instrumentId) => find.descendant(
  of: find.byKey(const Key('strategy-instrument-selected')),
  matching: find.text(instrumentId),
);

StrategyDashboardController _dashboard(
  StrategyApi api,
  StrategyMarketRepository market,
) => StrategyDashboardController(
  api: api,
  marketRepository: market,
  bearerToken: 'session-token',
);

Future<void> _pumpWizard(
  WidgetTester tester,
  StrategyMarketRepository market,
  StrategyApi api,
  StrategyDashboardController dashboard,
) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final session = TradeSession(
    bearerToken: 'session-token',
    accountIdentifier: 'test-account',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        strategyMarketRepositoryProvider.overrideWithValue(market),
        strategyApiProvider.overrideWithValue(api),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => StrategyWizardDialog(
                  session: session,
                  dashboard: dashboard,
                  onSaved: () async {},
                ),
              ),
              child: const Text('Open wizard'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open wizard'));
  await tester.pumpAndSettle();
}

class _FakeStrategyApi implements StrategyApi {
  final previewBodies = <Map<String, dynamic>>[];
  final saveBodies = <Map<String, dynamic>>[];
  StrategyApiException? nextPreviewError;

  @override
  Future<Map<String, dynamic>> preview(
    String bearerToken,
    Map<String, dynamic> body,
  ) async {
    previewBodies.add(body);
    final error = nextPreviewError;
    nextPreviewError = null;
    if (error != null) throw error;
    return {
      'previewHash': 'preview-hash',
      'orders': [
        {
          'side': 'long',
          'role': 'entry',
          'limitPrice': '90.0',
          'contracts': '1',
          'margin': '100.0',
          'leverage': '5',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> saveDraft(
    String bearerToken,
    Map<String, dynamic> body,
  ) async {
    saveBodies.add(body);
    return {'id': 'draft-1'};
  }

  @override
  Future<List<Map<String, dynamic>>> listStrategies(String bearerToken) async =>
      const [];

  @override
  Future<Map<String, dynamic>> prepareApply(
    String bearerToken,
    String id,
  ) async => const {};

  @override
  Future<Map<String, dynamic>> executeApply(
    String bearerToken,
    String id,
    String confirmationToken,
  ) async => const {};

  @override
  Future<Map<String, dynamic>> getResult(String bearerToken, String id) async =>
      const {};

  @override
  Future<void> deleteDraft(String bearerToken, String id) async {}
}

class _FakeStrategyMarketRepository extends StrategyMarketRepository {
  _FakeStrategyMarketRepository()
    : super(
        Dio(),
        requestCoordinator: RiskRequestCoordinator(
          minimumSpacing: Duration.zero,
          delay: (_) async {},
        ),
      );

  int instrumentCatalogCalls = 0;
  int tickerRequests = 0;
  double tickerPrice = 100;
  Duration tickerAge = Duration.zero;
  Completer<StrategyTicker>? pendingAutomaticRefresh;
  final loadCalls = <String>[];
  final instruments = const [
    StrategyInstrument(instrumentId: 'BTC-USDT-SWAP', base: 'BTC'),
    StrategyInstrument(instrumentId: 'ETH-USDT-SWAP', base: 'ETH'),
    StrategyInstrument(instrumentId: 'SOL-USDT-SWAP', base: 'SOL'),
  ];

  @override
  Future<List<StrategyInstrument>> getInstruments() async {
    instrumentCatalogCalls++;
    return instruments;
  }

  @override
  Future<StrategyMarketSnapshot> loadLevels({
    required String instrumentId,
    required StrategyInterval interval,
  }) async {
    loadCalls.add(instrumentId);
    final candles = List.generate(5, (index) {
      final swing = index == 2;
      return StrategyCandle(
        timestamp: DateTime.utc(
          2030,
          1,
          1,
        ).add(Duration(microseconds: interval.duration.inMicroseconds * index)),
        open: 100,
        high: swing ? 110 : 105,
        low: swing ? 90 : 95,
        close: 100,
        interval: interval,
      );
    });
    final ticker = await getTicker(instrumentId: instrumentId);
    return StrategyMarketSnapshot(
      instrumentId: instrumentId,
      interval: interval,
      ticker: ticker,
      candles: candles,
      analysis: calculator.calculate(candles: candles, referencePrice: 100),
    );
  }

  @override
  Future<StrategyTicker> getTicker({required String instrumentId}) async {
    tickerRequests++;
    if (tickerRequests == 2 && pendingAutomaticRefresh != null) {
      return pendingAutomaticRefresh!.future;
    }
    final age = pendingAutomaticRefresh != null && tickerRequests > 2
        ? Duration.zero
        : tickerAge;
    return StrategyTicker(
      instrumentId: instrumentId,
      lastPrice: tickerPrice,
      observedAt: DateTime.now().toUtc().subtract(age),
    );
  }
}
