import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/network/backend_data_client.dart';
import 'package:trading_balance_f/core/theme/app_theme.dart';
import 'package:trading_balance_f/features/orders/data/trade_api_client.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/trade_session_provider.dart';
import 'package:trading_balance_f/core/network/request_coordinator.dart';
import 'package:trading_balance_f/features/strategy/data/strategy_api_client.dart';
import 'package:trading_balance_f/features/strategy/data/strategy_market_repository.dart';
import 'package:trading_balance_f/features/strategy/domain/strategy_models.dart';
import 'package:trading_balance_f/features/strategy/presentation/providers/strategy_dashboard_provider.dart';
import 'package:trading_balance_f/features/strategy/presentation/strategy_wizard_dialog.dart';

const _strategyWizardPreviewKey = ValueKey('strategy-wizard-preview');

void main() {
  testWidgets('captures strategy budget at mobile and desktop scale', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.runAsync(_loadFormPreviewFonts);
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final viewport in [
        (
          name: 'mobile-360-scale-1.6',
          size: const Size(360, 900),
          textScale: 1.6,
        ),
        (name: 'desktop', size: const Size(1440, 1000), textScale: 1.0),
      ]) {
        final market = _FakeStrategyMarketRepository();
        final api = _FakeStrategyApi();
        final dashboard = _dashboard(api, market);
        await _pumpWizard(
          tester,
          market,
          api,
          dashboard,
          size: viewport.size,
          textScale: viewport.textScale,
          themeMode: mode,
        );

        final firstCandidate = find.byType(CheckboxListTile).first;
        await tester.ensureVisible(firstCandidate);
        await tester.tap(firstCandidate);
        await tester.pump();
        final nextButton = find.byKey(const Key('strategy-next-step-one'));
        await tester.ensureVisible(nextButton);
        await tester.tap(nextButton);
        await tester.pumpAndSettle();

        final allocation = find.byType(
          DropdownButtonFormField<StrategyAllocation>,
        );
        await tester.ensureVisible(allocation);
        await tester.tap(allocation);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Giảm dần từ điểm vào').last);
        await tester.pumpAndSettle();

        expect(find.text('Giảm dần từ điểm vào'), findsOneWidget);
        expect(
          tester.getSemantics(allocation).getSemanticsData().label,
          contains('Giảm dần từ điểm vào'),
        );
        expect(tester.takeException(), isNull);
        if (viewport.name == 'desktop') {
          final dialogSurface = find
              .descendant(
                of: find.byType(Dialog),
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is Material && widget.type == MaterialType.card,
                ),
              )
              .first;
          expect(tester.getRect(dialogSurface).height, lessThan(700));
        }
        await _writeStrategyWizardPreview(
          tester,
          'strategy-budget-${viewport.name}-${mode.name}.png',
        );
        dashboard.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
    semantics.dispose();
  });

  testWidgets('mobile scaled budget step expands its allocation choice', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final market = _FakeStrategyMarketRepository();
    final api = _FakeStrategyApi();
    final dashboard = _dashboard(api, market);
    addTearDown(dashboard.dispose);
    await _pumpWizard(
      tester,
      market,
      api,
      dashboard,
      size: const Size(360, 900),
      textScale: 1.6,
    );

    final firstCandidate = find.byType(CheckboxListTile).first;
    await tester.ensureVisible(firstCandidate);
    await tester.pumpAndSettle();
    await tester.tap(firstCandidate);
    await tester.pump();
    final nextButton = find.byKey(const Key('strategy-next-step-one'));
    await tester.ensureVisible(nextButton);
    await tester.tap(nextButton);
    await tester.pumpAndSettle();

    expect(find.text('Bước 2 / 3 · Ký quỹ và đòn bẩy'), findsOneWidget);
    final allocation = find.byType(DropdownButtonFormField<StrategyAllocation>);
    await tester.ensureVisible(allocation);
    await tester.pumpAndSettle();
    await tester.tap(allocation);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Giảm dần từ điểm vào').last);
    await tester.pumpAndSettle();
    expect(find.text('Giảm dần từ điểm vào'), findsOneWidget);
    expect(
      tester.getSemantics(allocation).getSemanticsData().label,
      contains('Giảm dần từ điểm vào'),
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('wizard instrument prompt stays below its label on mobile', (
    tester,
  ) async {
    final market = _FakeStrategyMarketRepository()..instruments = const [];
    final api = _FakeStrategyApi();
    final dashboard = _dashboard(api, market);
    addTearDown(dashboard.dispose);
    await _pumpWizard(
      tester,
      market,
      api,
      dashboard,
      size: const Size(360, 900),
      textScale: 1.6,
    );

    expect(find.text('Hợp đồng USDT SWAP'), findsOneWidget);
    expect(find.text('Chọn hợp đồng'), findsOneWidget);
    expect(
      tester.getRect(find.text('Hợp đồng USDT SWAP')).bottom,
      lessThan(tester.getRect(find.text('Chọn hợp đồng')).top),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'saved Jev recommendations preselect exact five-per-side IDs and nearest entries',
    (tester) async {
      final market = _FakeStrategyMarketRepository();
      final api = _FakeStrategyApi();
      final dashboard = _dashboard(api, market);
      addTearDown(dashboard.dispose);
      await _pumpWizard(
        tester,
        market,
        api,
        dashboard,
        initialCandidateDraft: _candidateDraftWithRecommendation(
          longIds: const ['long-1', 'long-2', 'long-3', 'long-4', 'long-5'],
          shortIds: const [
            'short-1',
            'short-2',
            'short-3',
            'short-4',
            'short-5',
          ],
        ),
      );

      expect(
        find.descendant(
          of: find.byKey(const Key('strategy-direction-select')),
          matching: find.text('Long&Short'),
        ),
        findsOneWidget,
      );
      expect(
        find.text('Đã chọn 10/10 lệnh · Long 5 · Short 5'),
        findsOneWidget,
      );
      for (var index = 1; index <= 6; index++) {
        final longCheckbox = tester.widget<CheckboxListTile>(
          find.descendant(
            of: find.byKey(Key('strategy-level-long-$index')),
            matching: find.byType(CheckboxListTile),
          ),
        );
        final shortCheckbox = tester.widget<CheckboxListTile>(
          find.descendant(
            of: find.byKey(Key('strategy-level-short-$index')),
            matching: find.byType(CheckboxListTile),
          ),
        );
        expect(longCheckbox.value, index <= 5);
        expect(shortCheckbox.value, index <= 5);
      }
      final entryIds = tester
          .widgetList<RadioListTile<String>>(find.byType(RadioListTile<String>))
          .map((radio) => radio.groupValue)
          .toSet();
      expect(entryIds, containsAll({'long-1', 'short-1'}));
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('strategy-next-step-one')),
            )
            .onPressed,
        isNotNull,
      );
      expect(market.loadCalls, isEmpty);
    },
  );

  testWidgets('wizard accepts saved IDs with valid custom thresholds', (
    tester,
  ) async {
    final market = _FakeStrategyMarketRepository();
    final api = _FakeStrategyApi();
    final dashboard = _dashboard(api, market);
    addTearDown(dashboard.dispose);
    final draft = _candidateDraftWithRecommendation(
      longIds: const ['long-5'],
      shortIds: const ['short-5'],
    );
    (draft['aiGeneration']['recommendation'] as Map<String, dynamic>)
      ..['minStructuralQuality'] = 3
      ..['minEntrySuitabilityProbability'] = 0.55
      ..['maxFailureRiskProbability'] = 0.45;

    await _pumpWizard(
      tester,
      market,
      api,
      dashboard,
      initialCandidateDraft: draft,
    );

    expect(find.text('Đã chọn 2/10 lệnh · Long 1 · Short 1'), findsOneWidget);
    final longFifth = tester.widget<CheckboxListTile>(
      find.descendant(
        of: find.byKey(const Key('strategy-level-long-5')),
        matching: find.byType(CheckboxListTile),
      ),
    );
    final shortFifth = tester.widget<CheckboxListTile>(
      find.descendant(
        of: find.byKey(const Key('strategy-level-short-5')),
        matching: find.byType(CheckboxListTile),
      ),
    );
    expect(longFifth.value, isTrue);
    expect(shortFifth.value, isTrue);
    expect(market.loadCalls, isEmpty);
  });

  testWidgets('one-sided recommendation derives Long and empty derives Both', (
    tester,
  ) async {
    final market = _FakeStrategyMarketRepository();
    final api = _FakeStrategyApi();
    final dashboard = _dashboard(api, market);
    addTearDown(dashboard.dispose);
    await _pumpWizard(
      tester,
      market,
      api,
      dashboard,
      initialCandidateDraft: _candidateDraftWithRecommendation(
        longIds: const ['long-1'],
        shortIds: const [],
      ),
    );

    expect(
      find.descendant(
        of: find.byKey(const Key('strategy-direction-select')),
        matching: find.text('Long'),
      ),
      findsOneWidget,
    );
    expect(find.text('Đã chọn 1/10 lệnh · Long 1 · Short 0'), findsOneWidget);
    expect(
      find.text('Không có mức nào đạt tiêu chí Jev; bạn có thể chọn thủ công.'),
      findsNothing,
    );

    final emptyMarket = _FakeStrategyMarketRepository();
    final emptyApi = _FakeStrategyApi();
    final emptyDashboard = _dashboard(emptyApi, emptyMarket);
    addTearDown(emptyDashboard.dispose);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpWizard(
      tester,
      emptyMarket,
      emptyApi,
      emptyDashboard,
      initialCandidateDraft: _candidateDraftWithRecommendation(
        longIds: const [],
        shortIds: const [],
      ),
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('strategy-direction-select')),
        matching: find.text('Long&Short'),
      ),
      findsOneWidget,
    );
    expect(find.text('Đã chọn 0/10 lệnh · Long 0 · Short 0'), findsOneWidget);
    expect(
      find.text('Không có mức nào đạt tiêu chí Jev; bạn có thể chọn thủ công.'),
      findsOneWidget,
    );
  });

  testWidgets('malformed recommendation clears both sides atomically', (
    tester,
  ) async {
    final market = _FakeStrategyMarketRepository();
    final api = _FakeStrategyApi();
    final dashboard = _dashboard(api, market);
    addTearDown(dashboard.dispose);
    await _pumpWizard(
      tester,
      market,
      api,
      dashboard,
      initialCandidateDraft: _candidateDraftWithRecommendation(
        longIds: const ['long-1'],
        shortIds: const ['missing-level'],
      ),
    );

    expect(
      tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .every((checkbox) => checkbox.value == false),
      isTrue,
    );
    expect(find.text('Đã chọn 0/10 lệnh · Long 0 · Short 0'), findsOneWidget);
    expect(
      find.text(
        'Đề xuất đã lưu không hợp lệ; mọi mức đã được bỏ chọn. Bạn có thể chọn thủ công.',
      ),
      findsOneWidget,
    );
    expect(market.loadCalls, isEmpty);
  });

  testWidgets(
    'empty saved candidate snapshots stay open without regenerating',
    (tester) async {
      final market = _FakeStrategyMarketRepository();
      final api = _FakeStrategyApi();
      final dashboard = _dashboard(api, market);
      addTearDown(dashboard.dispose);
      final draft = _savedCandidateDraft(includeSupport: false);
      await _pumpWizard(
        tester,
        market,
        api,
        dashboard,
        initialCandidateDraft: draft,
      );

      expect(
        find.text('Bản chụp đã lưu không có mức hỗ trợ hoặc kháng cự để chọn.'),
        findsOneWidget,
      );
      expect(market.loadCalls, isEmpty);
      expect(
        find.text('Không có đề xuất Jev đã lưu; mọi mức bắt đầu chưa chọn.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('strategy-next-step-one')),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('zero support is visible but disabled while valid rows remain', (
    tester,
  ) async {
    final market = _FakeStrategyMarketRepository();
    final api = _FakeStrategyApi();
    final dashboard = _dashboard(api, market);
    addTearDown(dashboard.dispose);
    await _pumpWizard(
      tester,
      market,
      api,
      dashboard,
      initialCandidateDraft: _savedCandidateDraft(supportPrice: '0'),
    );

    final zeroRow = find.byKey(const Key('strategy-level-support-1'));
    final validRow = find.byKey(const Key('strategy-level-support-malformed'));
    expect(zeroRow, findsOneWidget);
    expect(validRow, findsOneWidget);
    expect(
      find.text('Mức giá bằng 0 nên không thể chọn làm lệnh.'),
      findsOneWidget,
    );
    final checkboxes = tester.widgetList<CheckboxListTile>(
      find.byType(CheckboxListTile),
    );
    expect(checkboxes.first.onChanged, isNull);
    expect(checkboxes.last.onChanged, isNotNull);
    expect(find.text('Jev: đã đánh giá'), findsNWidgets(2));
    expect(find.text('Chất lượng: chưa có'), findsNWidgets(2));
    expect(find.text('Chất lượng: 3.5/5'), findsOneWidget);
    expect(find.text('Phù hợp điểm vào: 70.0%'), findsOneWidget);
    expect(find.text('Rủi ro thất bại: 20.0%'), findsOneWidget);
    expect(market.loadCalls, isEmpty);
  });

  testWidgets(
    'saved candidate review materializes through its original draft id',
    (tester) async {
      final market = _FakeStrategyMarketRepository();
      final api = _FakeStrategyApi()..saveDraftId = 'candidate-draft-1';
      final dashboard = _dashboard(api, market);
      addTearDown(dashboard.dispose);
      await _pumpWizard(
        tester,
        market,
        api,
        dashboard,
        initialCandidateDraft: _savedCandidateDraft(),
      );

      expect(market.loadCalls, isEmpty);
      expect(find.text('Jev: chưa bật'), findsOneWidget);
      expect(
        tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .every((checkbox) => checkbox.value == false),
        isTrue,
      );
      await tester.tap(find.byKey(const Key('strategy-direction-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Long').last);
      await tester.pumpAndSettle();
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
      await tester.tap(find.byKey(const Key('strategy-save-draft')));
      await tester.pumpAndSettle();

      expect(api.saveBodies, hasLength(1));
      expect(api.saveBodies.single['candidateDraftId'], 'candidate-draft-1');
      expect(api.saveDraftId, 'candidate-draft-1');
      expect(market.loadCalls, isEmpty);
    },
  );

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
      await tester.tap(find.text('Long&Short'));
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
    await tester.tap(find.text('Long&Short'));
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

  testWidgets('rounds preview numbers while preserving the request values', (
    tester,
  ) async {
    final market = _FakeStrategyMarketRepository();
    final api = _FakeStrategyApi()
      ..previewCurrentPrice = '12345.67891'
      ..previewTotalMargin = '1234.56789'
      ..previewUnallocatedMargin = '0.000000004'
      ..previewEstimatedOpeningFees = '0.000000003'
      ..previewOrderPrice = '12345.67891'
      ..previewOrderContracts = '0.000000004'
      ..previewOrderMargin = '1.23456789'
      ..previewOrderFee = '0.000000003';
    final dashboard = _dashboard(api, market);
    addTearDown(dashboard.dispose);
    await _pumpWizard(tester, market, api, dashboard);

    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    await tester.tap(find.byKey(const Key('strategy-next-step-one')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('strategy-margin-input')),
      '100.123456789',
    );
    await tester.tap(find.byKey(const Key('strategy-request-preview')));
    await tester.pumpAndSettle();

    expect(find.text('Giá thị trường lúc xem: 12,345.68'), findsOneWidget);
    expect(find.text('totalMargin: 1,234.57'), findsOneWidget);
    expect(find.text('unallocatedMargin: 4e-9'), findsOneWidget);
    expect(
      find.textContaining('Giá giới hạn 12,345.68 · Hợp đồng 4e-9'),
      findsOneWidget,
    );
    expect(find.text('Ký quỹ 1.2346 · Đòn bẩy 5x'), findsOneWidget);
    expect(api.previewBodies.single['totalMargin'], '100.123456789');
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
    await tester.tap(find.text('Long&Short'));
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
    await tester.tap(find.text('Long&Short'));
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

Map<String, dynamic> _savedCandidateDraft({
  String supportPrice = '90',
  bool includeSupport = true,
}) => {
  'id': 'candidate-draft-1',
  'instrumentId': 'BTC-USDT-SWAP',
  'interval': '6Hutc',
  'status': 'DRAFT',
  'draftStage': 'candidates',
  'canApply': false,
  'canReview': true,
  'aiGeneration': {
    'version': 'ai-generation-v1',
    'instrumentId': 'BTC-USDT-SWAP',
    'interval': '6Hutc',
    'tickSize': '0.01',
    'referencePrice': '100',
    'observedAt': '2030-01-01T00:00:00Z',
    'supports': !includeSupport
        ? <Object>[]
        : [
            {
              'levelId': 'support-1',
              'side': 'long',
              'price': supportPrice,
              'touchCount': 2,
              'firstTouchAt': '2029-12-31T00:00:00Z',
              'lastTouchAt': '2030-01-01T00:00:00Z',
              'generationOrder': 0,
              'rank': 1,
              'assessment': {'status': 'disabled', 'errorCode': 'disabled'},
            },
            {
              'levelId': 'support-assessed',
              'side': 'long',
              'price': '94',
              'touchCount': 1,
              'firstTouchAt': '2029-12-30T00:00:00Z',
              'lastTouchAt': '2029-12-31T00:00:00Z',
              'generationOrder': 1,
              'rank': 2,
              'assessment': {
                'status': 'success',
                'structuralQuality': 3.5,
                'entrySuitabilityProbability': 0.7,
                'failureRiskProbability': 0.2,
              },
            },
            {
              'levelId': 'support-malformed',
              'side': 'long',
              'price': '95',
              'touchCount': 1,
              'firstTouchAt': '2029-12-30T00:00:00Z',
              'lastTouchAt': '2029-12-31T00:00:00Z',
              'generationOrder': 2,
              'rank': 3,
              'assessment': {
                'status': 'success',
                'structuralQuality': 9,
                'entrySuitabilityProbability': 1.5,
                'failureRiskProbability': -0.1,
              },
            },
          ],
    'resistances': <Object>[],
  },
};

Map<String, dynamic> _candidateDraftWithRecommendation({
  required List<String> longIds,
  required List<String> shortIds,
}) {
  final draft = _savedCandidateDraft();
  final generation = draft['aiGeneration'] as Map<String, dynamic>;
  generation['supports'] = List.generate(6, (index) {
    final rank = index + 1;
    return _recommendedCandidate(
      id: 'long-$rank',
      side: 'long',
      price: (96 - (index * 2)).toString(),
      rank: rank,
    );
  });
  generation['resistances'] = List.generate(6, (index) {
    final rank = index + 1;
    return _recommendedCandidate(
      id: 'short-$rank',
      side: 'short',
      price: (104 + (index * 2)).toString(),
      rank: rank,
    );
  });
  generation['recommendation'] = {
    'version': 'ai-jev-selection-v1',
    'maxPerSide': 5,
    'minStructuralQuality': 4,
    'minEntrySuitabilityProbability': 0.6,
    'maxFailureRiskProbability': 0.4,
    'longLevelIds': longIds,
    'shortLevelIds': shortIds,
  };
  return draft;
}

Map<String, dynamic> _recommendedCandidate({
  required String id,
  required String side,
  required String price,
  required int rank,
}) => {
  'levelId': id,
  'side': side,
  'price': price,
  'touchCount': 1,
  'firstTouchAt': '2029-12-30T00:00:00Z',
  'lastTouchAt': '2029-12-31T00:00:00Z',
  'generationOrder': rank - 1,
  'rank': rank,
  'assessment': {
    'status': 'success',
    // The UI must use the saved IDs rather than re-screening model scores.
    'structuralQuality': rank == 5 ? 3.5 : 4,
    'entrySuitabilityProbability': rank == 5 ? 0.59 : 0.6,
    'failureRiskProbability': rank == 5 ? 0.41 : 0.4,
  },
};

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
  Map<String, dynamic>? initialCandidateDraft,
  _AuthenticatedSessionController? sessionController,
  Size size = const Size(1200, 1600),
  double textScale = 1,
  ThemeMode themeMode = ThemeMode.light,
}) async {
  tester.view.physicalSize = size;
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
      child: RepaintBoundary(
        key: _strategyWizardPreviewKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeMode,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child ?? const SizedBox.shrink(),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const Key('open-wizard'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => StrategyWizardDialog(
                    session: session,
                    dashboard: dashboard,
                    onSaved: () async {},
                    replacementSourceId: replacementSourceId,
                    initialCandidateDraft: initialCandidateDraft,
                  ),
                ),
                child: const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-wizard')));
  await tester.pumpAndSettle();
}

Future<void> _writeStrategyWizardPreview(
  WidgetTester tester,
  String filename,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_strategyWizardPreviewKey),
  );
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
  expect(image, isNotNull);
  final capturedImage = image!;
  final png = await tester.runAsync(
    () => capturedImage.toByteData(format: ui.ImageByteFormat.png),
  );
  capturedImage.dispose();
  expect(png, isNotNull);
  final bytes = png!.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
  await tester.runAsync(() async {
    final directory = Directory('build/forms-preview');
    await directory.create(recursive: true);
    await File('${directory.path}/$filename').writeAsBytes(bytes, flush: true);
  });
}

Future<Directory?> _findFormPreviewFontsDirectory() async {
  var directory = File(Platform.resolvedExecutable).absolute.parent;
  while (directory.path != directory.parent.path) {
    final candidate = Directory(
      '${directory.path}${Platform.pathSeparator}bin${Platform.pathSeparator}'
      'cache${Platform.pathSeparator}artifacts${Platform.pathSeparator}'
      'material_fonts',
    );
    if (await candidate.exists()) return candidate;
    directory = directory.parent;
  }
  return null;
}

Future<void> _loadFormPreviewFonts() async {
  final fontsDirectory = await _findFormPreviewFontsDirectory();
  if (fontsDirectory == null) return;

  for (final font in {
    'Roboto': 'roboto-regular.ttf',
    'MaterialIcons': 'materialicons-regular.otf',
  }.entries) {
    final fontFile = File(
      '${fontsDirectory.path}${Platform.pathSeparator}${font.value}',
    );
    if (!await fontFile.exists()) continue;
    final fontBytes = await fontFile.readAsBytes();
    final loader = FontLoader(font.key)
      ..addFont(Future.value(ByteData.sublistView(fontBytes)));
    await loader.load();
  }
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
  String? previewCurrentPrice;
  String? previewTotalMargin;
  String? previewUnallocatedMargin;
  String? previewEstimatedOpeningFees;
  String? previewOrderPrice;
  String? previewOrderContracts;
  String? previewOrderMargin;
  String? previewOrderFee;
  int previewOrderCount = 1;
  int preparedOrderCount = 1;
  int prepareCalls = 0;
  int executeCalls = 0;
  int deleteCalls = 0;
  bool reportCleanupConflict = false;
  String? saveDraftId;

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
      if (previewCurrentPrice != null) 'currentPrice': previewCurrentPrice,
      if (previewTotalMargin != null) 'totalMargin': previewTotalMargin,
      if (previewUnallocatedMargin != null)
        'unallocatedMargin': previewUnallocatedMargin,
      if (previewEstimatedOpeningFees != null)
        'estimatedOpeningFees': previewEstimatedOpeningFees,
      'orders': List.generate(
        previewOrderCount,
        (index) => {
          'side': 'long',
          'role': 'entry',
          'limitPrice': previewOrderPrice ?? (90 - index).toStringAsFixed(1),
          'contracts': previewOrderContracts ?? '1',
          'margin': previewOrderMargin ?? '100.0',
          'openingFeeEstimate': previewOrderFee ?? '0.03',
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
    return {'id': saveDraftId ?? 'draft-1'};
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
        BackendDataClient(dio: Dio(), baseUrl: 'https://data.example'),
        requestCoordinator: RequestCoordinator(
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
  List<StrategyInstrument> instruments = const [
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
