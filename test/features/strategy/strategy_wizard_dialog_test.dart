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
import 'package:trading_balance_f/features/strategy/presentation/providers/strategy_dashboard_provider.dart';
import 'package:trading_balance_f/features/strategy/presentation/strategy_wizard_dialog.dart';

void main() {
  testWidgets('account switch while wizard open disables old session preview', (
    tester,
  ) async {
    final market = _FakeStrategyMarketRepository();
    final api = _FakeStrategyApi();
    final dashboard = _dashboard(api, market);
    final sessionController = _AuthenticatedSessionController('session-token');
    addTearDown(dashboard.dispose);
    await _pumpWizard(
      tester,
      market,
      api,
      dashboard,
      sessionController: sessionController,
    );

    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    await tester.tap(find.byKey(const Key('strategy-next-step-one')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('strategy-margin-input')),
      '100',
    );
    sessionController.switchTo('session-b-token');
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('strategy-request-preview')),
          )
          .onPressed,
      isNull,
    );
    expect(api.previewBodies, isEmpty);
  });

  testWidgets(
    'replacement uses fresh levels and executes once after prepared confirmation',
    (tester) async {
      final market = _FakeStrategyMarketRepository();
      final api = _FakeStrategyApi()..reportCleanupConflict = true;
      final dashboard = _dashboard(api, market);
      addTearDown(dashboard.dispose);
      await _pumpWizard(
        tester,
        market,
        api,
        dashboard,
        replacementSourceId: 'never-sent-1',
      );

      expect(market.loadCalls, ['BTC-USDT-SWAP']);
      expect(
        tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .every((checkbox) => checkbox.value == false),
        isTrue,
      );

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
      await tester.tap(find.byKey(const Key('strategy-apply-now')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(api.saveBodies.single['replacementSourceId'], 'never-sent-1');
      expect(api.prepareCalls, 1);
      expect(find.text('Xác nhận danh sách lệnh'), findsOneWidget);
      expect(
        find.text('Cơ chế gửi đã cố định: Hàng đợi tuần tự'),
        findsOneWidget,
      );
      expect(
        find.textContaining('không có nghĩa là lệnh đã khớp'),
        findsOneWidget,
      );
      expect(find.textContaining('LONG · entry · 90.0'), findsOneWidget);
      expect(api.executeCalls, 0);

      await tester.tap(find.byKey(const Key('strategy-confirm-apply')));
      await tester.pumpAndSettle();

      expect(api.executeCalls, 1);
      expect(api.deleteCalls, 0);
      expect(
        find.textContaining('OKX đã chấp nhận đầy đủ lệnh thay thế'),
        findsOneWidget,
      );
    },
  );

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

  testWidgets(
    'RED-002 preserves 10 selected rows and the preview when an 11th is rejected',
    (tester) async {
      final market = _FakeStrategyMarketRepository()
        ..supportLevels = _levels(
          StrategySide.long,
          List.generate(11, (index) => 99 - index.toDouble()),
        );
      final api = _FakeStrategyApi()..previewOrderCount = 10;
      final dashboard = _dashboard(api, market);
      addTearDown(dashboard.dispose);
      await _pumpWizard(tester, market, api, dashboard);

      for (var index = 0; index < 10; index++) {
        final level = find.byKey(ValueKey('strategy-level-long_$index'));
        final checkbox = find.descendant(
          of: level,
          matching: find.byType(CheckboxListTile),
        );
        await tester.ensureVisible(checkbox);
        await tester.tap(checkbox);
        await tester.pump();
      }
      expect(
        find.text('Đã chọn 10/10 lệnh · Long 10 · Short 0'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('strategy-next-step-one')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('strategy-margin-input')),
        '100',
      );
      await tester.tap(find.byKey(const Key('strategy-request-preview')));
      await tester.pumpAndSettle();
      expect(api.previewBodies, hasLength(1));

      await tester.tap(find.text('Quay lại'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quay lại'));
      await tester.pumpAndSettle();
      final eleventh = find.descendant(
        of: find.byKey(const ValueKey('strategy-level-long_10')),
        matching: find.byType(CheckboxListTile),
      );
      await tester.ensureVisible(eleventh);
      await tester.tap(eleventh);
      await tester.pump();

      expect(
        find.text('Đã chọn 10/10 lệnh · Long 10 · Short 0'),
        findsOneWidget,
      );
      expect(
        tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .where((checkbox) => checkbox.value == true),
        hasLength(10),
      );
      final radios = tester.widgetList<RadioListTile<String>>(
        find.byType(RadioListTile<String>),
      );
      expect(
        radios.firstWhere((radio) => radio.value == 'long_0').groupValue,
        'long_0',
      );
      expect(api.previewBodies, hasLength(1));
      expect(api.saveBodies, isEmpty);
      expect(find.textContaining('tối đa 10 lệnh'), findsOneWidget);
    },
  );

  testWidgets('RED-002 rejects a forged 11-order preview before save', (
    tester,
  ) async {
    final market = _FakeStrategyMarketRepository();
    final api = _FakeStrategyApi()..previewOrderCount = 11;
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

    expect(find.byKey(const Key('strategy-save-draft')), findsNothing);
    expect(api.previewBodies, hasLength(1));
    expect(api.saveBodies, isEmpty);
    expect(api.prepareCalls, 0);
    expect(api.executeCalls, 0);
    expect(find.textContaining('giới hạn 10 lệnh'), findsOneWidget);
  });

  testWidgets(
    'RED-002 rejects an 11-order prepared response before confirmation',
    (tester) async {
      final market = _FakeStrategyMarketRepository();
      final api = _FakeStrategyApi()..preparedOrderCount = 11;
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
      await tester.tap(find.byKey(const Key('strategy-apply-now')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(api.prepareCalls, 1);
      expect(find.text('Xác nhận danh sách lệnh'), findsNothing);
      expect(api.executeCalls, 0);
    },
  );

  testWidgets(
    'GREEN-002 previews and executes a mixed 10-order selection once',
    (tester) async {
      final market = _FakeStrategyMarketRepository()
        ..supportLevels = _levels(
          StrategySide.long,
          List.generate(5, (index) => 99 - index.toDouble()),
        )
        ..resistanceLevels = _levels(
          StrategySide.short,
          List.generate(5, (index) => 101 + index.toDouble()),
        );
      final api = _FakeStrategyApi()
        ..previewOrderCount = 10
        ..preparedOrderCount = 10;
      final dashboard = _dashboard(api, market);
      addTearDown(dashboard.dispose);
      await _pumpWizard(tester, market, api, dashboard);

      await tester.tap(find.byKey(const Key('strategy-direction-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Long và Short'));
      await tester.pumpAndSettle();
      for (var index = 0; index < 10; index++) {
        final checkbox = find.byType(CheckboxListTile).at(index);
        await tester.ensureVisible(checkbox);
        await tester.tap(checkbox);
        await tester.pump();
      }
      expect(
        find.text('Đã chọn 10/10 lệnh · Long 5 · Short 5'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('strategy-next-step-one')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('strategy-margin-input')),
        '100',
      );
      await tester.tap(find.byKey(const Key('strategy-request-preview')));
      await tester.pumpAndSettle();
      expect(api.previewBodies.single['selectedLevels'], hasLength(10));

      await tester.tap(find.byKey(const Key('strategy-apply-now')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.saveBodies.single['selectedLevels'], hasLength(10));
      expect(api.prepareCalls, 1);
      await tester.tap(find.byKey(const Key('strategy-confirm-apply')));
      await tester.pumpAndSettle();

      expect(api.executeCalls, 1);
    },
  );

  testWidgets('Both cannot continue until each side has a selected entry', (
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

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('strategy-next-step-one')))
          .onPressed,
      isNull,
    );
    expect(
      find.text(
        'Chọn ít nhất một mức Long và một mức Short, cùng điểm vào gần nhất cho mỗi phía.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'initial quote is one-time reference and its age does not block preview or save',
    (tester) async {
      final market = _FakeStrategyMarketRepository()
        ..tickerAge = const Duration(seconds: 16);
      final api = _FakeStrategyApi();
      final dashboard = _dashboard(api, market);
      addTearDown(dashboard.dispose);
      await _pumpWizard(tester, market, api, dashboard);

      expect(market.tickerRequests, 1);
      expect(find.textContaining('Giá tham chiếu'), findsOneWidget);
      await tester.pump(const Duration(seconds: 20));
      expect(market.tickerRequests, 1);

      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('strategy-next-step-one')),
            )
            .onPressed,
        isNotNull,
      );
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
      expect(find.text('Bước 3 / 3 · Xem lại và xác nhận'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('strategy-save-draft')),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('strategy-apply-now')))
            .onPressed,
        isNotNull,
      );
    },
  );

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

  testWidgets('wizard reference does not poll when the market moves', (
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

    expect(market.tickerRequests, 1);
    expect(find.textContaining('Giá đã di chuyển'), findsNothing);
    final checkboxes = tester
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .toList();
    expect(checkboxes.map((item) => item.value), [true, true]);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('strategy-next-step-one')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('rounded equal-price rows stay selected by distinct IDs', (
    tester,
  ) async {
    final market = _FakeStrategyMarketRepository()
      ..supportLevels = [
        StrategyLevel(
          price: 90,
          exactPriceText: '90.00',
          levelId: 'low_source_one',
          firstTouchAt: DateTime.utc(2030, 1, 1),
          lastTouchAt: DateTime.utc(2030, 1, 1),
          touchCount: 1,
          side: StrategySide.long,
        ),
        StrategyLevel(
          price: 90,
          exactPriceText: '90.0',
          levelId: 'low_source_two',
          firstTouchAt: DateTime.utc(2030, 1, 2),
          lastTouchAt: DateTime.utc(2030, 1, 2),
          touchCount: 1,
          side: StrategySide.long,
        ),
      ];
    final api = _FakeStrategyApi();
    final dashboard = _dashboard(api, market);
    addTearDown(dashboard.dispose);
    await _pumpWizard(tester, market, api, dashboard);

    final checkboxes = find.byType(CheckboxListTile);
    await tester.tap(checkboxes.first);
    await tester.pump();
    await tester.tap(checkboxes.last);
    await tester.pump();
    await tester.tap(find.byKey(const Key('strategy-next-step-one')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('strategy-margin-input')),
      '100',
    );
    await tester.tap(find.byKey(const Key('strategy-request-preview')));
    await tester.pumpAndSettle();

    final requestLevels = api.previewBodies.single['selectedLevels'] as List;
    expect(requestLevels, [
      {'side': 'long', 'price': '90', 'levelId': 'low_source_one'},
      {'side': 'long', 'price': '90', 'levelId': 'low_source_two'},
    ]);
    expect(api.previewBodies.single['entryLevelIdBySide'], {
      'long': 'low_source_one',
    });
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
      final selectedLevels = request['selectedLevels'] as List;
      expect(selectedLevels, hasLength(1));
      final levelId = (selectedLevels.single as Map)['levelId'];
      expect(levelId, matches(RegExp(r'^[A-Za-z0-9_-]{1,128}$')));
      expect(request['direction'], 'long');
      expect(selectedLevels.single, {
        'side': 'long',
        'price': '90',
        'levelId': levelId,
      });
      expect(request['entryBySide'], {'long': '90'});
      expect(request['entryLevelIdBySide'], {'long': levelId});
      expect(find.text('Nhập ngân sách ký quỹ USDT lớn hơn 0.'), findsNothing);
      caseIndex++;
    }

    await tester.tap(find.byKey(const Key('strategy-save-draft')));
    await tester.pumpAndSettle();
    expect(api.saveBodies, hasLength(1));
    expect(api.saveBodies.single['totalMargin'], '100.0');
    final savedLevels = api.saveBodies.single['selectedLevels'] as List;
    final savedLevelId = (savedLevels.single as Map)['levelId'];
    expect(savedLevels.single, {
      'side': 'long',
      'price': '90',
      'levelId': savedLevelId,
    });
    expect(api.saveBodies.single['entryBySide'], {'long': '90'});
    expect(api.saveBodies.single['entryLevelIdBySide'], {'long': savedLevelId});
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
  StrategyDashboardController dashboard, {
  String? replacementSourceId,
  _AuthenticatedSessionController? sessionController,
}) async {
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
        tradeSessionProvider.overrideWith(
          (ref) =>
              sessionController ??
              _AuthenticatedSessionController(session.bearerToken),
        ),
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
                  replacementSourceId: replacementSourceId,
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

class _AuthenticatedSessionController extends TradeSessionController {
  _AuthenticatedSessionController(String bearerToken)
    : super(TradeApiClient(baseUrl: 'https://trade.example')) {
    state = TradeSessionState(
      session: TradeSession(
        bearerToken: bearerToken,
        accountIdentifier: 'test-account',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
  }

  void switchTo(String bearerToken) {
    state = TradeSessionState(
      session: TradeSession(
        bearerToken: bearerToken,
        accountIdentifier: 'other-account',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
  }
}

class _FakeStrategyApi implements StrategyApi {
  final previewBodies = <Map<String, dynamic>>[];
  final saveBodies = <Map<String, dynamic>>[];
  StrategyApiException? nextPreviewError;
  int previewOrderCount = 1;
  int preparedOrderCount = 1;
  int prepareCalls = 0;
  int executeCalls = 0;
  int deleteCalls = 0;
  bool reportCleanupConflict = false;

  @override
  Future<StrategyRetryCandidates> getRetryCandidates(
    String token,
    String sourceStrategyId,
  ) async => throw UnimplementedError();

  @override
  Future<StrategyRetryPreview> previewRetry(
    String token,
    String sourceStrategyId, {
    required String sourceRevision,
    required List<String> sourceClientOrderIds,
  }) async => throw UnimplementedError();

  @override
  Future<StrategyRetryDraft> createRetryDraft(
    String token,
    String sourceStrategyId, {
    required String sourceRevision,
    required List<String> sourceClientOrderIds,
    required String previewHash,
    required String retryRequestId,
  }) async => throw UnimplementedError();

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
      'orders': List.generate(
        previewOrderCount,
        (index) => {
          'side': 'long',
          'role': 'entry',
          'limitPrice': (90 - index).toStringAsFixed(1),
          'contracts': '1',
          'margin': '100.0',
          'leverage': '5',
        },
      ),
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
  ) async {
    prepareCalls++;
    return {
      'confirmationToken': 'one-use-token',
      'submissionMode': 'sequential',
      'estimatedOpeningFees': (0.03 * preparedOrderCount).toStringAsFixed(2),
      'orders': List.generate(
        preparedOrderCount,
        (index) => {
          'side': 'long',
          'role': 'entry',
          'limitPrice': (90 - index).toStringAsFixed(1),
          'contracts': '1',
          'margin': '100.0',
          'leverage': 5,
          'openingFeeEstimate': '0.03',
        },
      ),
    };
  }

  @override
  Future<Map<String, dynamic>> executeApply(
    String bearerToken,
    String id,
    String confirmationToken,
  ) async {
    executeCalls++;
    return {
      'status': 'APPLIED',
      'replacementCleanupConflict': reportCleanupConflict,
    };
  }

  @override
  Future<Map<String, dynamic>> getResult(String bearerToken, String id) async =>
      const {};

  @override
  Future<Map<String, dynamic>> getQuote(String bearerToken, String id) async =>
      const {};

  @override
  Future<String> getLimitOrderSubmissionMode(String bearerToken) async =>
      'sequential';

  @override
  Future<String> saveLimitOrderSubmissionMode(
    String bearerToken,
    String mode,
  ) async => mode;

  @override
  Future<void> deleteDraft(String bearerToken, String id) async {
    deleteCalls++;
  }
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
  final loadCalls = <String>[];
  List<StrategyLevel>? supportLevels;
  List<StrategyLevel>? resistanceLevels;
  final instruments = const [
    StrategyInstrument(
      instrumentId: 'BTC-USDT-SWAP',
      base: 'BTC',
      tickSizeText: '0.01',
    ),
    StrategyInstrument(
      instrumentId: 'ETH-USDT-SWAP',
      base: 'ETH',
      tickSizeText: '0.01',
    ),
    StrategyInstrument(
      instrumentId: 'SOL-USDT-SWAP',
      base: 'SOL',
      tickSizeText: '0.01',
    ),
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
    required String tickSizeText,
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
    final calculated = calculator.calculate(
      candles: candles,
      referencePrice: 100,
      tickSizeText: tickSizeText,
    );
    return StrategyMarketSnapshot(
      instrumentId: instrumentId,
      interval: interval,
      ticker: ticker,
      candles: candles,
      analysis: StrategyAnalysis(
        referencePrice: 100,
        supports: supportLevels ?? calculated.supports,
        resistances: resistanceLevels ?? calculated.resistances,
      ),
    );
  }

  @override
  Future<StrategyTicker> getTicker({required String instrumentId}) async {
    tickerRequests++;
    return StrategyTicker(
      instrumentId: instrumentId,
      lastPrice: tickerPrice,
      observedAt: DateTime.now().toUtc().subtract(tickerAge),
    );
  }
}

List<StrategyLevel> _levels(StrategySide side, List<double> prices) => [
  for (var index = 0; index < prices.length; index++)
    StrategyLevel(
      price: prices[index],
      exactPriceText: prices[index].toString(),
      firstTouchAt: DateTime.utc(2030, 1, 1).add(Duration(days: index)),
      lastTouchAt: DateTime.utc(2030, 1, 1).add(Duration(days: index)),
      touchCount: 2,
      side: side,
      levelId: '${side.wireValue}_$index',
    ),
];
