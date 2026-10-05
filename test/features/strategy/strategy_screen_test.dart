import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/theme/app_theme.dart';
import 'package:trading_balance_f/core/theme/pnl_color.dart';
import 'package:trading_balance_f/features/orders/data/trade_api_client.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/trade_session_provider.dart';
import 'package:trading_balance_f/features/portfolio/data/risk/risk_request_coordinator.dart';
import 'package:trading_balance_f/features/strategy/data/strategy_api_client.dart';
import 'package:trading_balance_f/features/strategy/data/strategy_market_repository.dart';
import 'package:trading_balance_f/features/strategy/domain/strategy_models.dart';
import 'package:trading_balance_f/features/strategy/presentation/providers/strategy_dashboard_provider.dart';
import 'package:trading_balance_f/features/strategy/presentation/strategy_automatic_draft_dialog.dart';
import 'package:trading_balance_f/features/strategy/presentation/strategy_screen.dart';
import 'package:trading_balance_f/features/strategy/presentation/strategy_wizard_dialog.dart';

void main() {
  testWidgets('strategy action toolbar fits mobile with discoverable actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tradeSessionProvider.overrideWith(
            (ref) => _AuthenticatedSessionController(),
          ),
          strategyApiProvider.overrideWithValue(_FakeStrategyApi()),
          strategyMarketRepositoryProvider.overrideWithValue(
            _FakeMarketRepository(),
          ),
        ],
        child: const MaterialApp(home: StrategyScreen()),
      ),
    );
    await _pumpFrames(tester);

    expect(find.text('Chiến Thuật'), findsOneWidget);
    expect(find.text('Chiến thuật đã lưu'), findsNothing);
    expect(find.text('Dựng chiến thuật tự động'), findsNothing);

    final manualAction = find.byKey(const Key('strategy-create-button'));
    final automaticAction = find.byKey(
      const Key('strategy-automatic-create-button'),
    );
    expect(manualAction, findsOneWidget);
    expect(automaticAction, findsOneWidget);
    expect(find.byTooltip('Dựng chiến thuật tự động'), findsOneWidget);

    for (final action in [manualAction, automaticAction]) {
      final rect = tester.getRect(action);
      expect(rect.width, greaterThanOrEqualTo(48));
      expect(rect.height, greaterThanOrEqualTo(48));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(390));
    }

    await tester.tap(manualAction);
    await tester.pumpAndSettle();
    expect(find.byType(StrategyWizardDialog), findsOneWidget);
    await tester.tap(find.text('Hủy').last);
    await tester.pumpAndSettle();

    expect(automaticAction, findsOneWidget);
    await tester.tap(automaticAction);
    await tester.pumpAndSettle();
    expect(find.byType(StrategyAutomaticDraftDialog), findsOneWidget);
    await tester.tap(find.byKey(const Key('strategy-automatic-close')));
    await tester.pumpAndSettle();
  });

  testWidgets('candidate drafts offer review and cannot be applied directly', (
    tester,
  ) async {
    final api = _FakeStrategyApi();
    api.strategies[0]
      ..['draftStage'] = 'candidates'
      ..['canApply'] = false
      ..['canReview'] = true
      ..['aiGeneration'] = _candidateGenerationSnapshot();
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
    await _pumpFrames(tester);

    expect(find.byKey(const Key('strategy-review-draft-1')), findsOneWidget);
    expect(find.byKey(const Key('strategy-apply-draft-1')), findsNothing);
    expect(find.byKey(const Key('strategy-replace-draft-1')), findsNothing);
  });

  testWidgets(
    'automatic candidates are persisted, unselected, and reopen without regeneration',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _FakeStrategyApi()..automaticFailureCount = 1;
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
      await _pumpFrames(tester);

      await tester.tap(
        find.byKey(const Key('strategy-automatic-create-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('strategy-automatic-instrument-picker')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('strategy-automatic-instrument-BTC-USDT-SWAP')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('strategy-automatic-interval-select')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('1D').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('strategy-automatic-generate')));
      await tester.pumpAndSettle();

      expect(api.automaticRequests, hasLength(1));
      expect(
        find.text('Máy chủ tự động đang bận. Vui lòng thử lại.'),
        findsOneWidget,
      );
      final originalRequestId = api.automaticRequests.single['requestId'];
      await tester.tap(find.byKey(const Key('strategy-automatic-generate')));
      await tester.pumpAndSettle();

      expect(api.automaticRequests, hasLength(2));
      expect(api.automaticRequests.last['instrumentId'], 'BTC-USDT-SWAP');
      expect(api.automaticRequests.last['interval'], '1Dutc');
      expect(originalRequestId, matches(RegExp(r'^[A-Za-z0-9_-]{8,64}$')));
      expect(api.automaticRequests.last['requestId'], originalRequestId);
      expect(find.text('Hỗ trợ cho Long'), findsOneWidget);
      expect(find.text('Kháng cự cho Short'), findsOneWidget);
      expect(find.text('Jev: chưa bật'), findsOneWidget);
      expect(find.text('Jev: đánh giá không thành công'), findsOneWidget);
      expect(
        tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .every((checkbox) => checkbox.value == false),
        isTrue,
      );
      expect(market.loadLevelsCalls, 0);
      final requestCountAfterCreation = api.automaticRequests.length;

      await tester.tap(find.byTooltip('Đóng'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('strategy-review-auto-draft-1')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('strategy-review-auto-draft-1')));
      await tester.pumpAndSettle();

      expect(api.automaticRequests, hasLength(requestCountAfterCreation));
      expect(market.loadLevelsCalls, 0);
      expect(find.text('Jev: chưa bật'), findsOneWidget);
      expect(find.text('Mã đánh giá: timeout'), findsOneWidget);
      expect(
        tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .every((checkbox) => checkbox.value == false),
        isTrue,
      );
    },
  );

  testWidgets('late automatic response is discarded after a session change', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = _AuthenticatedSessionController();
    final api = _FakeStrategyApi()
      ..automaticDraftCompleter = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tradeSessionProvider.overrideWith((ref) => session),
          strategyApiProvider.overrideWithValue(api),
          strategyMarketRepositoryProvider.overrideWithValue(
            _FakeMarketRepository(),
          ),
        ],
        child: const MaterialApp(home: StrategyScreen()),
      ),
    );
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const Key('strategy-automatic-create-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('strategy-automatic-instrument-picker')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('strategy-automatic-instrument-BTC-USDT-SWAP')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('strategy-automatic-interval-select')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('6H').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('strategy-automatic-generate')));
    await tester.pump();
    expect(api.automaticRequests, hasLength(1));

    session.switchTo('session-b-token');
    await tester.pumpAndSettle();
    api.automaticDraftCompleter!.complete(
      _candidateDraftRecord(
        id: 'late-auto-draft',
        instrumentId: 'BTC-USDT-SWAP',
        interval: '6Hutc',
        requestId: api.automaticRequests.single['requestId'] as String,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(StrategyWizardDialog), findsNothing);
    expect(find.byKey(const Key('strategy-selection-count')), findsNothing);
    expect(
      find.byKey(const Key('strategy-automatic-create-button')),
      findsOneWidget,
    );
  });

  testWidgets('T72 compact strategy cards show current status and omit intro', (
    tester,
  ) async {
    final api = _FakeStrategyApi();
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
    await _pumpFrames(tester);

    expect(
      find.text(
        'Tạo kế hoạch lệnh từ các vùng hỗ trợ và kháng cự của hợp đồng USDT.',
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('strategy-summary-draft-1')),
        matching: find.text('Bản nháp'),
      ),
      findsOneWidget,
    );
    final draftCard = find
        .ancestor(
          of: find.byKey(const Key('strategy-summary-draft-1')),
          matching: find.byType(Card),
        )
        .first;
    expect(
      find.descendant(of: draftCard, matching: find.byTooltip('Tạo lại')),
      findsOneWidget,
    );
  });

  testWidgets('strategy details use the modal scroll body without a card', (
    tester,
  ) async {
    final api = _FakeStrategyApi();
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
    await _pumpFrames(tester);

    await _openStrategyDetails(tester, 'started-1');
    final dialog = find.byType(Dialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.byType(Card)),
      findsNothing,
    );
    final scrollView = tester.widget<SingleChildScrollView>(
      find.descendant(of: dialog, matching: find.byType(SingleChildScrollView)),
    );
    expect(scrollView.padding, const EdgeInsets.fromLTRB(20, 4, 20, 16));
  });

  testWidgets('T72 canDelete does not grant replacement eligibility', (
    tester,
  ) async {
    final api = _FakeStrategyApi();
    api.strategies[0]
      ..['status'] = 'PARTIAL'
      ..['batchAttempted'] = true
      ..['canDelete'] = true
      ..['canReplace'] = false;
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
    await _pumpFrames(tester);
    final summary = find.byKey(const Key('strategy-summary-draft-1'));
    await tester.ensureVisible(summary);
    await tester.pump();
    final card = find.ancestor(of: summary, matching: find.byType(Card)).first;

    expect(
      find.descendant(of: card, matching: find.byTooltip('Tạo lại')),
      findsNothing,
    );
    expect(
      find.descendant(of: card, matching: find.byTooltip('Xóa chiến thuật')),
      findsOneWidget,
    );
  });

  testWidgets('T72 summary follows live lifecycle and all-canceled orders', (
    tester,
  ) async {
    final api = _FakeStrategyApi();
    final session = _AuthenticatedSessionController();
    StrategyDashboardController? dashboard;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tradeSessionProvider.overrideWith((ref) => session),
          strategyApiProvider.overrideWithValue(api),
          strategyMarketRepositoryProvider.overrideWithValue(
            _FakeMarketRepository(),
          ),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, child) {
              dashboard = ref.watch(
                strategyDashboardProvider(session.state.session!.bearerToken),
              );
              return const StrategyScreen();
            },
          ),
        ),
      ),
    );
    await _pumpFrames(tester);

    final summary = find.byKey(const Key('strategy-summary-started-1'));
    await tester.ensureVisible(summary);
    await tester.pump();
    expect(
      find.descendant(of: summary, matching: find.text('Đã gửi')),
      findsOneWidget,
    );

    api.strategies[1]
      ..['orders'] = [
        {'status': 'canceled'},
        {'status': 'mmp_canceled'},
      ]
      ..['queueStatus'] = 'stopped'
      ..['queueProgress'] = {
        'totalCount': 2,
        'attemptedCount': 2,
        'acceptedCount': 2,
        'pendingCount': 0,
        'notSubmittedCount': 0,
      }
      ..['orderSyncState'] = 'fresh'
      ..['canDelete'] = true
      ..['canReplace'] = false
      ..['batchAttempted'] = false
      ..['orderPlacementAttempted'] = true;
    await dashboard!.load();
    await _pumpFrames(tester);

    expect(
      find.descendant(of: summary, matching: find.text('Đã hủy')),
      findsOneWidget,
    );
    await _openStrategyDetails(tester, 'started-1');
    expect(find.text('Đã gửi'), findsOneWidget);
    expect(find.text('Chưa gửi'), findsNothing);
    expect(
      find.textContaining('Không có lệnh nào được gửi lên OKX'),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byTooltip('Tạo lại'),
      ),
      findsNothing,
    );
    await tester.tap(find.byTooltip('Đóng chi tiết'));
    await tester.pumpAndSettle();

    api.strategies[1]
      ..['orders'] = [
        {'status': 'canceled'},
      ]
      ..['queueStatus'] = 'submitted'
      ..['queueProgress'] = {
        'totalCount': 2,
        'attemptedCount': 1,
        'acceptedCount': 1,
        'pendingCount': 1,
        'notSubmittedCount': 0,
      };
    await dashboard!.load();
    await _pumpFrames(tester);
    expect(
      find.descendant(of: summary, matching: find.text('Đã hủy')),
      findsNothing,
    );

    api.strategies[1]['queueStatus'] = 'sending';
    await dashboard!.load();
    await _pumpFrames(tester);
    expect(
      find.descendant(of: summary, matching: find.text('Đã hủy')),
      findsNothing,
    );
  });

  testWidgets(
    'RED-004 sequential canceled summary requires complete queue evidence',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _FakeStrategyApi();
      final session = _AuthenticatedSessionController();
      StrategyDashboardController? dashboard;
      api.strategies[1]
        ..['status'] = 'PARTIAL'
        ..['orders'] = [
          {'status': 'canceled'},
          {'status': 'mmp_canceled'},
        ]
        ..['submissionMode'] = 'sequential'
        ..['queueStatus'] = 'stopped'
        ..['queueProgress'] = null
        ..['orderSyncState'] = 'fresh';
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tradeSessionProvider.overrideWith((ref) => session),
            strategyApiProvider.overrideWithValue(api),
            strategyMarketRepositoryProvider.overrideWithValue(
              _FakeMarketRepository(),
            ),
          ],
          child: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 800),
              textScaler: TextScaler.linear(1.5),
            ),
            child: MaterialApp(
              home: Consumer(
                builder: (context, ref, child) {
                  dashboard = ref.watch(
                    strategyDashboardProvider(
                      session.state.session!.bearerToken,
                    ),
                  );
                  return const StrategyScreen();
                },
              ),
            ),
          ),
        ),
      );
      await _pumpFrames(tester);
      final summary = find.byKey(const Key('strategy-summary-started-1'));
      await tester.ensureVisible(summary);
      await tester.pump();

      expect(
        find.descendant(of: summary, matching: find.text('Đã hủy')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: summary,
          matching: find.text('Một phần / cần kiểm tra'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      api.strategies[1]
        ..remove('queueStatus')
        ..remove('queueProgress');
      await dashboard!.load();
      await _pumpFrames(tester);
      expect(
        find.descendant(of: summary, matching: find.text('Đã hủy')),
        findsNothing,
      );

      api.strategies[1]['queueProgress'] = {'totalCount': 2};
      await dashboard!.load();
      await _pumpFrames(tester);
      expect(
        find.descendant(of: summary, matching: find.text('Đã hủy')),
        findsNothing,
      );

      api.strategies[1]
        ..['submissionMode'] = 'batch'
        ..remove('queueStatus')
        ..remove('queueProgress');
      await dashboard!.load();
      await _pumpFrames(tester);
      expect(
        find.descendant(of: summary, matching: find.text('Đã hủy')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('T72 strategy detail PnL amount and percent have sign colors', (
    tester,
  ) async {
    final api = _FakeStrategyApi();
    api.strategies[1]
      ..['totalMargin'] = '1234.56789'
      ..['unrealizedPnl'] = '1.23456789'
      ..['pnlPercent'] = '-0.006';
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
    await _pumpFrames(tester);
    await _openStrategyDetails(tester, 'started-1');

    expect(find.text('Vốn: 1,234.57 USDT'), findsOneWidget);
    final pnlMetric = find.ancestor(
      of: find.text('PnL chưa thực hiện'),
      matching: find.byWidgetPredicate(
        (widget) => widget is SizedBox && widget.width == 175,
      ),
    );
    final pnlText = find.descendant(
      of: pnlMetric,
      matching: find.text('1.2346'),
    );
    expect(tester.widget<Text>(pnlText).style?.color, PnlColors.lightPositive);

    final percentMetric = find.ancestor(
      of: find.text('% trên vốn đã khớp'),
      matching: find.byWidgetPredicate(
        (widget) => widget is SizedBox && widget.width == 175,
      ),
    );
    final percentText = find.descendant(
      of: percentMetric,
      matching: find.text('-0.01'),
    );
    expect(
      tester.widget<Text>(percentText).style?.color,
      PnlColors.lightNegative,
    );
  });

  testWidgets('RED-00 strategy action long press only reveals its tooltip', (
    tester,
  ) async {
    final api = _FakeStrategyApi();
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
    await _pumpFrames(tester);

    await tester.longPress(find.byKey(const Key('strategy-apply-draft-1')));
    await tester.pumpAndSettle();

    expect(find.text('Áp dụng bản nháp'), findsOneWidget);
    expect(api.prepareCalls, 0);
    expect(api.executeCalls, 0);
  });

  testWidgets('GREEN-001 summary icon action preserves frozen confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _FakeStrategyApi()
      ..prepared = {
        'confirmationToken': 'one-use-token',
        'submissionMode': 'batch',
        'estimatedOpeningFees': '0.03',
        'orders': [
          {
            'side': 'long',
            'role': 'entry',
            'limitPrice': '65000',
            'contracts': '1',
            'margin': '13',
            'leverage': 5,
            'openingFeeEstimate': '0.03',
          },
        ],
      };

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
    await _pumpFrames(tester);
    await tester.tap(find.byTooltip('Áp dụng bản nháp'));
    await _pumpFrames(tester);

    expect(find.text('Cơ chế gửi đã cố định: Gửi theo lô'), findsOneWidget);
    expect(
      find.textContaining('gửi cùng nhau theo cơ chế gửi theo lô'),
      findsOneWidget,
    );
    expect(api.executeCalls, 0);
    await tester.tap(find.byKey(const Key('strategy-confirm-apply')));
    await _pumpFrames(tester);

    expect(api.executeCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'RED-002 disables an oversized unstarted draft and shows recreate guidance',
    (tester) async {
      final api = _FakeStrategyApi();
      api.strategies.first['selectedLevels'] = List.generate(
        11,
        (index) => {
          'side': 'long',
          'price': '${99 - index}',
          'levelId': 'long_$index',
        },
      );
      api.strategies.add({
        'id': 'prepared-old',
        'instrumentId': 'ETH-USDT-SWAP',
        'interval': '6Hutc',
        'status': 'PREPARED',
        'batchAttempted': false,
        'canDelete': true,
        'orders': List.generate(
          11,
          (index) => {
            'side': 'long',
            'role': 'entry',
            'limitPrice': '${99 - index}',
          },
        ),
      });

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
      await _pumpFrames(tester);

      final applyButton = find.byKey(const Key('strategy-apply-draft-1'));
      expect(tester.widget<IconButton>(applyButton).onPressed, isNull);
      await _openStrategyDetails(tester, 'draft-1');
      expect(
        find.textContaining('Bản nháp cũ vượt quá giới hạn 10 lệnh'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Đóng chi tiết'));
      await tester.pumpAndSettle();
      await _openStrategyDetails(tester, 'prepared-old');
      final preparedDetails = _strategyDetailBody();
      expect(
        find.textContaining('Bản nháp đã chuẩn bị vượt quá giới hạn 10 lệnh'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: preparedDetails,
          matching: find.byTooltip('Cập nhật trạng thái'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: preparedDetails,
          matching: find.byTooltip('Tạo lại'),
        ),
        findsOneWidget,
      );
      expect(api.prepareCalls, 0);
      expect(api.executeCalls, 0);
    },
  );

  testWidgets(
    'RED-001 account session change hides captured strategy details and actions',
    (tester) async {
      final api = _FakeStrategyApi();
      final session = _AuthenticatedSessionController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tradeSessionProvider.overrideWith((ref) => session),
            strategyApiProvider.overrideWithValue(api),
            strategyMarketRepositoryProvider.overrideWithValue(
              _FakeMarketRepository(),
            ),
          ],
          child: const MaterialApp(home: StrategyScreen()),
        ),
      );
      await _pumpFrames(tester);
      await _openStrategyDetails(tester, 'started-1');

      expect(find.text('BTC-USDT-SWAP'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byTooltip('Gửi lại lệnh limit'),
        ),
        findsOneWidget,
      );

      session.state = const TradeSessionState();
      await _pumpFrames(tester);

      expect(find.text('BTC-USDT-SWAP'), findsNothing);
      expect(
        find.textContaining('Phiên giao dịch đã thay đổi'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byTooltip('Gửi lại lệnh limit'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('GREEN-002 preserves historical 20-order queue progress', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _FakeStrategyApi()..includeQueues = true;

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
    await _pumpFrames(tester);
    await _openStrategyDetails(tester, 'applying-queue-1');
    await tester.scrollUntilVisible(
      find.text('Chưa rõ kết quả gửi'),
      240,
      scrollable: find.byType(Scrollable).last,
    );

    expect(find.text('Đang gửi'), findsWidgets);
    expect(find.text('Đã được nhận'), findsWidgets);
    expect(find.text('Chưa rõ kết quả gửi'), findsOneWidget);
    expect(find.text('Chưa gửi'), findsWidgets);
    expect(
      find.textContaining('3 đã thử, 1 đã nhận, 1 đang chờ'),
      findsOneWidget,
    );
    expect(find.textContaining('16 chưa gửi / 20'), findsOneWidget);
    await tester.tap(find.byTooltip('Đóng chi tiết'));
    await tester.pumpAndSettle();
    await _openStrategyDetails(tester, 'stopped-queue-1');
    expect(find.text('Đã dừng'), findsOneWidget);
    await tester.tap(find.byTooltip('Đóng chi tiết'));
    await tester.pumpAndSettle();
    await _openStrategyDetails(tester, 'malformed-queue-1');
    expect(find.text('Tiến độ hàng đợi chưa khả dụng.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('GREEN-001 compact summary counts all rows and opens details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final market = _FakeMarketRepository();
    final api = _FakeStrategyApi();
    api.strategies[1]['totalMargin'] = '123.45';
    api.strategies[1]['filledMargin'] = '999';
    final startedOrders = List<Map<String, dynamic>>.from(
      api.strategies[1]['orders'] as List,
    );
    startedOrders.addAll([
      for (var index = 0; index < 8; index++)
        {
          'side': 'long',
          'role': 'entry',
          'limitPrice': '${58000 - index}',
          'contracts': '1',
          'status': const [
            'canceled',
            'queued',
            'not_submitted',
            'rejected',
          ][index % 4],
        },
    ]);
    api.strategies[1]['orders'] = startedOrders;

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
    expect(find.text('BTC'), findsNWidgets(2));
    expect(find.text('BTC-USDT-SWAP'), findsNothing);
    final summary = find.byKey(const Key('strategy-summary-started-1'));
    expect(
      find.descendant(of: summary, matching: find.text('Vốn: 123.45 USDT')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.text('Tổng lệnh: 12')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.text('Chưa khớp: 1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.text('Đã khớp: 1')),
      findsOneWidget,
    );
    final statusTooltip = find.descendant(
      of: summary,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip &&
            widget.message?.contains('Trạng thái lệnh đã cũ.') == true,
      ),
    );
    expect(statusTooltip, findsOneWidget);
    expect(
      tester.widget<Tooltip>(statusTooltip).message,
      contains('Hai nhóm có thể không bằng tổng'),
    );
    await _openStrategyDetails(tester, 'started-1');
    final draftSummary = find.byKey(const Key('strategy-summary-draft-1'));
    final startedDetails = _strategyDetailBody();
    expect(
      find.descendant(
        of: startedDetails,
        matching: find.textContaining('Giá SWAP 65,000.00'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: draftSummary,
        matching: find.textContaining('Giá SWAP 65000'),
      ),
      findsNothing,
    );
    expect(find.text('Khớp một phần'), findsOneWidget);
    expect(find.text('Đã khớp'), findsOneWidget);
    expect(find.text('Đã hủy'), findsNWidgets(3));
    expect(find.text('Chưa xác định'), findsOneWidget);
    expect(
      find.descendant(
        of: startedDetails,
        matching: find.textContaining('Khớp: 2.00 / 5.00 hợp đồng'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: startedDetails,
        matching: find.textContaining('Giá khớp TB: 58,990.00'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Lần quét lệnh đã cũ'), findsOneWidget);
  });

  testWidgets(
    'GREEN-001 open details track dashboard updates and action eligibility',
    (tester) async {
      final api = _FakeStrategyApi();
      final session = _AuthenticatedSessionController();
      StrategyDashboardController? dashboard;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tradeSessionProvider.overrideWith((ref) => session),
            strategyApiProvider.overrideWithValue(api),
            strategyMarketRepositoryProvider.overrideWithValue(
              _FakeMarketRepository(),
            ),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, child) {
                dashboard = ref.watch(
                  strategyDashboardProvider(session.state.session!.bearerToken),
                );
                return const StrategyScreen();
              },
            ),
          ),
        ),
      );
      await _pumpFrames(tester);
      await _openStrategyDetails(tester, 'started-1');

      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byTooltip('Gửi lại lệnh limit'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byTooltip('Áp dụng bản nháp'),
        ),
        findsNothing,
      );

      api.strategies[1]
        ..['status'] = 'DRAFT'
        ..['canDelete'] = true
        ..['orders'] = [
          {'status': 'live'},
          {'status': 'filled'},
        ];
      await dashboard!.load();
      await _pumpFrames(tester);

      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Bản nháp'),
        ),
        findsOneWidget,
      );
      final liveSummary = find.byKey(const Key('strategy-summary-started-1'));
      expect(
        find.descendant(of: liveSummary, matching: find.text('Tổng lệnh: 2')),
        findsOneWidget,
      );
      final details = find.byType(Dialog);
      expect(
        find.descendant(
          of: details,
          matching: find.byTooltip('Gửi lại lệnh limit'),
        ),
        findsNothing,
      );
      for (final label in ['Áp dụng bản nháp', 'Tạo lại', 'Xóa chiến thuật']) {
        expect(
          find.descendant(of: details, matching: find.byTooltip(label)),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(
          of: details,
          matching: find.byTooltip('Cập nhật trạng thái'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'GREEN-001 missing rows and invalid total capital stay unavailable',
    (tester) async {
      final api = _FakeStrategyApi();
      api.strategies.first['filledMargin'] = '88.50';
      api.strategies.addAll([
        {
          'id': 'empty-orders-1',
          'instrumentId': 'LTC-USDT-SWAP',
          'status': 'COMPLETED',
          'totalMargin': '-4',
          'orders': <Map<String, dynamic>>[],
        },
        {
          'id': 'malformed-margin-1',
          'instrumentId': 'DOGE-USDT-SWAP',
          'status': 'COMPLETED',
          'totalMargin': 'not-a-number',
          'orders': [
            {'status': 'live'},
          ],
        },
        {
          'id': 'nonfinite-margin-1',
          'instrumentId': 'XLM-USDT-SWAP',
          'status': 'COMPLETED',
          'totalMargin': '1e999',
          'orders': <Map<String, dynamic>>[],
        },
      ]);

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
      await _pumpFrames(tester);

      for (final id in [
        'draft-1',
        'empty-orders-1',
        'malformed-margin-1',
        'nonfinite-margin-1',
      ]) {
        final summary = find.byKey(Key('strategy-summary-$id'));
        await tester.ensureVisible(summary);
        await tester.pump();
        expect(
          find.descendant(of: summary, matching: find.text('Vốn: --')),
          findsOneWidget,
        );
        if (id == 'draft-1') {
          for (final label in [
            'Tổng lệnh: --',
            'Chưa khớp: --',
            'Đã khớp: --',
          ]) {
            expect(
              find.descendant(of: summary, matching: find.text(label)),
              findsOneWidget,
            );
          }
        }
        if (id == 'empty-orders-1') {
          for (final label in ['Tổng lệnh: 0', 'Chưa khớp: 0', 'Đã khớp: 0']) {
            expect(
              find.descendant(of: summary, matching: find.text(label)),
              findsOneWidget,
            );
          }
        }
        if (id == 'malformed-margin-1') {
          expect(
            find.descendant(of: summary, matching: find.text('Tổng lệnh: 1')),
            findsOneWidget,
          );
          expect(
            find.descendant(of: summary, matching: find.text('Chưa khớp: 1')),
            findsOneWidget,
          );
        }
      }
    },
  );

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
    await _openStrategyDetails(tester, 'completed-1');

    final detailStatus = find.descendant(
      of: find.byType(Dialog),
      matching: find.text('Hoàn tất'),
    );
    expect(detailStatus, findsOneWidget);
    final completedDetails = _strategyDetailBody();
    expect(
      find.descendant(of: completedDetails, matching: find.text('Đã khớp')),
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

    await _openStrategyDetails(tester, 'never-sent-1');
    final eligibleDetails = _strategyDetailBody();
    expect(
      find.descendant(of: eligibleDetails, matching: find.text('Chưa gửi')),
      findsNWidgets(2),
    );
    expect(
      find.descendant(
        of: eligibleDetails,
        matching: find.textContaining('Không có lệnh nào được gửi lên OKX'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: eligibleDetails,
        matching: find.textContaining('51008'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: eligibleDetails,
        matching: find.textContaining('Lần quét lệnh đã cũ'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: eligibleDetails, matching: find.byTooltip('Tạo lại')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: eligibleDetails,
        matching: find.byTooltip('Xóa chiến thuật'),
      ),
      findsOneWidget,
    );
    final summaryCard = find
        .ancestor(
          of: find.byKey(const Key('strategy-summary-never-sent-1')),
          matching: find.byType(Card),
        )
        .first;
    expect(
      find.descendant(of: summaryCard, matching: find.byTooltip('Tạo lại')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: summaryCard,
        matching: find.textContaining('Không có lệnh nào được gửi lên OKX'),
      ),
      findsNothing,
    );
    final replaceButton = find.descendant(
      of: eligibleDetails,
      matching: find.byKey(const Key('strategy-replace-never-sent-1')),
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
      of: eligibleDetails,
      matching: find.byKey(const Key('strategy-delete-never-sent-1')),
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
    expect(
      find.textContaining('không còn trong danh sách hiện tại'),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byTooltip('Xóa chiến thuật'),
      ),
      findsNothing,
    );
    await tester.tap(find.byTooltip('Đóng chi tiết'));
    await tester.pumpAndSettle();

    await _openStrategyDetails(tester, 'started-1');
    expect(
      find.textContaining('OKX đã chấp nhận đầy đủ lệnh thay thế'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Đóng chi tiết'));
    await tester.pumpAndSettle();

    await _openStrategyDetails(tester, 'never-sent-other-failure');
    final genericFailureDetails = _strategyDetailBody();
    expect(
      find.descendant(
        of: genericFailureDetails,
        matching: find.textContaining('Không có lệnh nào được gửi lên OKX'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: genericFailureDetails,
        matching: find.byTooltip('Tạo lại'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: genericFailureDetails,
        matching: find.textContaining('OKX từ chối thiết lập đòn bẩy'),
      ),
      findsNothing,
    );

    await tester.tap(find.byTooltip('Đóng chi tiết'));
    await tester.pumpAndSettle();
    for (final scenario in [
      (id: 'not-eligible-1', instrument: 'SOL-USDT-SWAP'),
      (id: 'attempted-1', instrument: 'XRP-USDT-SWAP'),
    ]) {
      await _openStrategyDetails(tester, scenario.id);
      final details = _strategyDetailBody();
      expect(
        find.descendant(of: details, matching: find.byTooltip('Tạo lại')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: details,
          matching: find.byTooltip('Xóa chiến thuật'),
        ),
        findsNothing,
      );
      await tester.tap(find.byTooltip('Đóng chi tiết'));
      await tester.pumpAndSettle();
    }
  });
}

Future<void> _pumpFrames(WidgetTester tester, [int count = 5]) async {
  for (var frame = 0; frame < count; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _openStrategyDetails(
  WidgetTester tester,
  String strategyId,
) async {
  final summary = find.byKey(Key('strategy-summary-$strategyId'));
  await tester.scrollUntilVisible(
    summary,
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
  await tester.tap(summary);
  await _pumpFrames(tester);
}

Finder _strategyDetailBody() => find.descendant(
  of: find.byType(Dialog),
  matching: find.byType(SingleChildScrollView),
);

Map<String, dynamic> _candidateGenerationSnapshot() => {
  'version': 'ai-generation-v1',
  'instrumentId': 'BTC-USDT-SWAP',
  'interval': '6Hutc',
  'tickSize': '0.01',
  'referencePrice': '100',
  'observedAt': '2030-01-01T00:00:00Z',
  'supports': [
    {
      'levelId': 'support-1',
      'side': 'long',
      'price': '90',
      'touchCount': 2,
      'firstTouchAt': '2029-12-31T00:00:00Z',
      'lastTouchAt': '2030-01-01T00:00:00Z',
      'generationOrder': 0,
      'rank': 1,
      'assessment': {
        'provider': 'typesafe',
        'status': 'disabled',
        'modelRequested': null,
        'modelUsed': null,
        'structuralQuality': null,
        'entrySuitabilityProbability': null,
        'failureRiskProbability': null,
        'errorCode': 'disabled',
      },
    },
  ],
  'resistances': [
    {
      'levelId': 'resistance-1',
      'side': 'short',
      'price': '110',
      'touchCount': 3,
      'firstTouchAt': '2029-12-31T00:00:00Z',
      'lastTouchAt': '2030-01-01T00:00:00Z',
      'generationOrder': 1,
      'rank': 1,
      'assessment': {
        'provider': 'typesafe',
        'status': 'failed',
        'modelRequested': 'test-model',
        'modelUsed': null,
        'structuralQuality': null,
        'entrySuitabilityProbability': null,
        'failureRiskProbability': null,
        'errorCode': 'timeout',
      },
    },
  ],
};

Map<String, dynamic> _candidateDraftRecord({
  required String id,
  required String instrumentId,
  required String interval,
  String? requestId,
}) => {
  'id': id,
  'instrumentId': instrumentId,
  'interval': interval,
  'status': 'DRAFT',
  'draftStage': 'candidates',
  'canApply': false,
  'canReview': true,
  'canDelete': true,
  'orders': <Object>[],
  'results': <Object>[],
  'aiGeneration': {
    ..._candidateGenerationSnapshot(),
    'instrumentId': instrumentId,
    'interval': interval,
    if (requestId != null) 'requestId': requestId,
  },
};

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

class _FakeStrategyApi implements StrategyApi, AutomaticStrategyApi {
  int quoteCalls = 0;
  int deleteCalls = 0;
  int prepareCalls = 0;
  int executeCalls = 0;
  final deletedIds = <String>{};
  bool includeCompleted = false;
  bool includeNeverSent = false;
  bool includeQueues = false;
  Map<String, dynamic> prepared = const {};
  final automaticRequests = <Map<String, dynamic>>[];
  int automaticFailureCount = 0;
  Completer<Map<String, dynamic>>? automaticDraftCompleter;

  @override
  Future<Map<String, dynamic>> createAutomaticDrafts(
    String token, {
    required String instrumentId,
    required String interval,
    required String requestId,
  }) async {
    final request = {
      'instrumentId': instrumentId,
      'interval': interval,
      'requestId': requestId,
    };
    automaticRequests.add(request);
    if (automaticFailureCount > 0) {
      automaticFailureCount--;
      throw const StrategyApiException(
        code: 'network_error',
        message: 'Máy chủ tự động đang bận. Vui lòng thử lại.',
      );
    }
    final response = automaticDraftCompleter == null
        ? _candidateDraftRecord(
            id: 'auto-draft-1',
            instrumentId: instrumentId,
            interval: interval,
            requestId: requestId,
          )
        : await automaticDraftCompleter!.future;
    if (automaticDraftCompleter == null) {
      strategies.removeWhere((item) => item['id'] == response['id']);
      strategies.insert(0, response);
    }
    return response;
  }

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
      'submissionMode': 'sequential',
      'queueStatus': 'submitted',
      'queueProgress': {
        'totalCount': 4,
        'attemptedCount': 4,
        'acceptedCount': 4,
        'pendingCount': 0,
        'notSubmittedCount': 0,
      },
      'orders': [
        {
          'side': 'long',
          'role': 'entry',
          'limitPrice': '59000',
          'contracts': '5',
          'status': 'partially_filled',
          'placementState': 'accepted',
          'filledContracts': '2',
          'averageFillPrice': '58990',
        },
        {
          'side': 'long',
          'role': 'dca',
          'limitPrice': '58000',
          'contracts': '5',
          'status': 'filled',
          'placementState': 'accepted',
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
    String token,
    Map<String, dynamic> body,
  ) async => {};

  @override
  Future<Map<String, dynamic>> saveDraft(
    String token,
    Map<String, dynamic> body,
  ) async => {'id': 'draft-1'};

  @override
  Future<Map<String, dynamic>> prepareApply(String token, String id) async {
    prepareCalls++;
    return prepared;
  }

  @override
  Future<Map<String, dynamic>> executeApply(
    String token,
    String id,
    String confirmationToken,
  ) async {
    executeCalls++;
    return {'status': 'APPLIED'};
  }

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
  Future<String> getLimitOrderSubmissionMode(String token) async =>
      'sequential';

  @override
  Future<String> saveLimitOrderSubmissionMode(
    String token,
    String mode,
  ) async => mode;

  @override
  Future<void> deleteDraft(String token, String id) async {
    deleteCalls++;
    deletedIds.add(id);
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
    if (includeQueues) {
      result.addAll([
        {
          'id': 'applying-queue-1',
          'instrumentId': 'SOL-USDT-SWAP',
          'status': 'APPLYING',
          'submissionMode': 'sequential',
          'queueStatus': 'sending',
          'queueProgress': {
            'totalCount': 20,
            'attemptedCount': 3,
            'acceptedCount': 1,
            'pendingCount': 1,
            'notSubmittedCount': 16,
          },
          'orders': [
            {
              'side': 'long',
              'role': 'entry',
              'limitPrice': '90',
              'contracts': '1',
              'status': 'live',
              'placementState': 'accepted',
              'filledContracts': '0',
            },
            {
              'side': 'long',
              'role': 'dca',
              'limitPrice': '89',
              'contracts': '1',
              'status': 'sending',
              'placementState': 'sending',
            },
            {
              'side': 'short',
              'role': 'entry',
              'limitPrice': '91',
              'contracts': '1',
              'status': 'unknown',
              'placementState': 'unknown',
            },
            {
              'side': 'short',
              'role': 'entry',
              'limitPrice': '91.5',
              'contracts': '1',
              'status': 'queued',
              'placementState': 'pending',
            },
            {
              'side': 'short',
              'role': 'dca',
              'limitPrice': '92',
              'contracts': '1',
              'status': 'not_submitted',
              'placementState': 'not_submitted',
            },
          ],
        },
        {
          'id': 'stopped-queue-1',
          'instrumentId': 'ETH-USDT-SWAP',
          'status': 'PARTIAL',
          'submissionMode': 'sequential',
          'queueStatus': 'stopped',
          'queueProgress': {
            'totalCount': 2,
            'attemptedCount': 1,
            'acceptedCount': 0,
            'pendingCount': 0,
            'notSubmittedCount': 1,
          },
          'orders': [
            {
              'side': 'long',
              'role': 'entry',
              'limitPrice': '3000',
              'contracts': '1',
              'status': 'rejected',
              'placementState': 'rejected',
            },
            {
              'side': 'long',
              'role': 'dca',
              'limitPrice': '2990',
              'contracts': '1',
              'status': 'not_submitted',
              'placementState': 'not_submitted',
            },
          ],
        },
        {
          'id': 'malformed-queue-1',
          'instrumentId': 'ADA-USDT-SWAP',
          'status': 'APPLYING',
          'submissionMode': 'sequential',
          'queueStatus': 'sending',
          'queueProgress': {
            'totalCount': 3,
            'attemptedCount': 1,
            'acceptedCount': 2,
            'pendingCount': 1,
            'notSubmittedCount': 1,
          },
        },
      ]);
    }
    return result
        .where((strategy) => !deletedIds.contains(strategy['id']))
        .toList(growable: false);
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
