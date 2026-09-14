import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/portfolio/application/risk_monitor_bridge.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/action_plan.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_engine.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_events.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_history.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_models.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_policy.dart';
import 'package:trading_balance_f/features/portfolio/presentation/risk_dashboard_screen.dart';
import 'package:trading_balance_f/features/portfolio/presentation/risk_vietnamese_formatter.dart';
import 'package:trading_balance_f/features/portfolio/presentation/providers/risk_dashboard_provider.dart';
import 'package:trading_balance_f/features/portfolio/presentation/portfolio_screen.dart';
import 'package:trading_balance_f/features/portfolio/presentation/widgets/risk/risk_history_view.dart';
import 'package:trading_balance_f/features/portfolio/presentation/widgets/risk/risk_market_card.dart';
import 'package:trading_balance_f/features/portfolio/presentation/widgets/risk/risk_recovery_view.dart';
import 'package:trading_balance_f/features/portfolio/presentation/widgets/risk/risk_stress_view.dart';
import 'package:trading_balance_f/features/portfolio/presentation/widgets/risk/risk_overview.dart';
import 'package:trading_balance_f/features/portfolio/presentation/widgets/risk/risk_plan_editor.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';

import 'fixtures/risk_test_fixtures.dart';

Future<void> main() async {
  final screenshotFontFamily = await _loadScreenshotFont();
  testWidgets('RED-003 collapsible all-position dashboard', (tester) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final owner = _countingOwner(_aggregateDashboardState());
    addTearDown(owner.dispose);
    await tester.pumpWidget(_home(owner));
    await tester.pump();

    for (final key in const <String>['btc', 'eth', 'sui', 'failed']) {
      expect(
        find.byKey(Key('risk-position-header-$key')),
        findsOneWidget,
        reason: 'Missing aggregate position $key',
      );
    }
    expect(
      find.textContaining(riskViSeverity(RiskSeverity.normal)),
      findsWidgets,
    );
    expect(
      find.textContaining(riskViSeverity(RiskSeverity.watch)),
      findsWidgets,
    );
    expect(
      find.textContaining(riskViSeverity(RiskSeverity.high)),
      findsWidgets,
    );
    expect(find.text(riskVi('failed')), findsOneWidget);
    expect(find.byKey(const Key('risk-overview')), findsNothing);
    expect(owner.dispatchCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('GREEN-003 collapsible all-position dashboard', (tester) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final owner = _countingOwner(_aggregateDashboardState());
    addTearDown(owner.dispose);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: _home(owner, hidden: true),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('risk-monitor-status')), findsOneWidget);
    expect(find.textContaining(riskVi('retryingSoon')), findsOneWidget);
    expect(find.text('10.00'), findsNothing);
    expect(find.text('******'), findsWidgets);
    expect(find.byKey(const Key('risk-position-header-btc')), findsOneWidget);
    expect(find.byKey(const Key('risk-position-header-eth')), findsOneWidget);
    expect(find.byKey(const Key('risk-position-header-sui')), findsOneWidget);
    expect(
      find.byKey(const Key('risk-position-header-failed')),
      findsOneWidget,
    );
    expect(find.text(riskVi('stressScenarios')), findsNothing);

    final semantics = tester.ensureSemantics();
    final headerSemantics = tester.getSemantics(
      find.byKey(const Key('risk-position-header-eth')),
    );
    final headerData = headerSemantics.getSemanticsData();
    expect(headerData.hasAction(SemanticsAction.tap), isTrue);
    expect(headerData.label, contains('Mở rộng'));
    expect(headerData.label, contains('LONG'));
    expect(headerData.label, contains('ISOLATED'));
    for (final literal in const <String>[
      '10.00',
      '2.00',
      '4.00',
      '0.40',
      '9/10',
      '14:09',
      '14:00',
      '21:00',
    ]) {
      expect(headerData.label, isNot(contains(literal)));
    }

    await tester.ensureVisible(
      find.byKey(const Key('risk-position-header-eth')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('risk-position-header-eth')));
    await tester.pump();
    final expandedHeaderData = tester
        .getSemantics(find.byKey(const Key('risk-position-header-eth')))
        .getSemanticsData();
    expect(expandedHeaderData.hasAction(SemanticsAction.tap), isTrue);
    expect(expandedHeaderData.label, contains('Thu gọn'));
    expect(expandedHeaderData.label, isNot(contains('Mở rộng')));
    expect(find.byKey(const Key('risk-overview')), findsOneWidget);
    expect(find.text('10.00'), findsNothing);
    expect(owner.dispatchCalls, 0);

    await Scrollable.ensureVisible(
      tester.element(find.byKey(const Key('risk-position-header-sui'))),
      duration: Duration.zero,
      alignment: 0.5,
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('risk-position-header-sui')));
    await tester.pump();
    expect(find.byKey(const Key('risk-overview')), findsNWidgets(2));
    expect(owner.dispatchCalls, 0);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'RED-003 selected aggregate episode stays isolated in reactive drill-downs',
    (tester) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final entries = _distinctAggregateEntries();
      final owner = _countingOwner(_distinctAggregateState(entries));
      addTearDown(owner.dispose);
      await tester.pumpWidget(_home(owner));
      await tester.pump();

      final eth = entries.firstWhere(
        (entry) => entry.position?.instrumentId == 'ETH-USDT',
      );
      await tester.tap(
        find.byKey(Key('risk-position-header-${eth.episodeKey}')),
      );
      await tester.pump();
      final ethOverview = find.byKey(const Key('risk-overview'));
      expect(
        find.descendant(of: ethOverview, matching: find.text('33.3%')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: ethOverview, matching: find.text('40.0%')),
        findsNothing,
      );
      await Scrollable.ensureVisible(
        tester.element(
          find.widgetWithText(OutlinedButton, riskVi('exposureSensitivity')),
        ),
        duration: Duration.zero,
        alignment: 0.5,
      );
      await tester.tap(
        find.widgetWithText(OutlinedButton, riskVi('exposureSensitivity')),
      );
      await tester.pumpAndSettle();
      final exposureSheet = find.byType(BottomSheet);
      expect(
        find.descendant(of: exposureSheet, matching: find.text('90.00 USDT')),
        findsNWidgets(2),
      );
      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.widgetWithText(OutlinedButton, riskVi('history'))),
        duration: Duration.zero,
        alignment: 0.5,
      );
      await tester.tap(find.widgetWithText(OutlinedButton, riskVi('history')));
      await tester.pumpAndSettle();

      expect(find.text('ETH-only event'), findsOneWidget);
      expect(find.text('BTC-only event'), findsNothing);

      // A bridge update can briefly omit the selected entry while the
      // aggregate snapshot is reconciled. The open sheet must retain the
      // last-known ETH episode rather than falling back to BTC/root data.
      owner.publish(
        _distinctAggregateState(
          entries
              .where((entry) => entry.episodeKey != eth.episodeKey)
              .toList(growable: false),
        ),
      );
      await tester.pump();
      expect(find.text('ETH-only event'), findsOneWidget);
      expect(find.text('BTC-only event'), findsNothing);

      // Restore the complete aggregate before closing the sheet so the
      // accordion remains present for the independent plan assertion.
      owner.publish(_distinctAggregateState(entries));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.widgetWithText(OutlinedButton, riskVi('plan'))),
        duration: Duration.zero,
        alignment: 0.5,
      );
      await tester.tap(find.widgetWithText(OutlinedButton, riskVi('plan')));
      await tester.pumpAndSettle();
      final editor = tester.widget<RiskPlanEditor>(
        find.byType(RiskPlanEditor).last,
      );
      expect(editor.episodeKey, eth.episodeKey);
      expect(find.text('ETH plan marker'), findsNWidgets(2));
      expect(find.text('BTC plan marker'), findsNothing);
      expect(owner.dispatchCalls, 0);
    },
  );

  testWidgets(
    'RED-003 aggregate header keeps input order eligibility freshness and reset',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final entries = _distinctAggregateEntries();
      final owner = _countingOwner(_distinctAggregateState(entries));
      addTearDown(owner.dispose);
      await tester.pumpWidget(_home(owner));
      await tester.pump();

      final eth = entries.firstWhere(
        (entry) => entry.position?.instrumentId == 'ETH-USDT',
      );
      final btc = entries.firstWhere(
        (entry) => entry.position?.instrumentId == 'BTC-USDT',
      );
      expect(
        tester.getTopLeft(find.text('ETH-USDT')).dy,
        lessThan(tester.getTopLeft(find.text('BTC-USDT')).dy),
      );
      expect(find.text('LONG'), findsWidgets);
      expect(find.text('ISOLATED'), findsWidgets);
      expect(find.text('MARGIN'), findsWidgets);
      expect(find.text(riskVi('freshness')), findsWidgets);

      await tester.tap(
        find.byKey(Key('risk-position-header-${eth.episodeKey}')),
      );
      await tester.pump();
      expect(find.byKey(const Key('risk-overview')), findsOneWidget);
      final freshVisitOwner = _countingOwner(_distinctAggregateState(entries));
      addTearDown(freshVisitOwner.dispose);
      await tester.pumpWidget(_home(freshVisitOwner, visitKey: 'fresh'));
      await tester.pump();
      expect(find.byKey(const Key('risk-overview')), findsNothing);
      expect(
        find.byKey(Key('risk-position-header-${btc.episodeKey}')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('RED-003 history mutation retains the selected episode key', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final entries = _distinctAggregateEntries();
    final owner = _countingOwner(_distinctAggregateState(entries));
    addTearDown(owner.dispose);
    await tester.pumpWidget(_home(owner));
    await tester.pump();

    final eth = entries.firstWhere(
      (entry) => entry.position?.instrumentId == 'ETH-USDT',
    );
    await tester.tap(find.byKey(Key('risk-position-header-${eth.episodeKey}')));
    await tester.pump();
    await tester.drag(
      find.byKey(const Key('risk-home-scroll')),
      const Offset(0, -900),
    );
    await tester.pump();
    final historyButton = find.widgetWithText(
      OutlinedButton,
      riskVi('history'),
    );
    await Scrollable.ensureVisible(
      tester.element(historyButton),
      duration: Duration.zero,
      alignment: 0.5,
    );
    await tester.tap(historyButton);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(riskVi('clearHistory')));
    await tester.tap(find.text(riskVi('clearHistory')));
    await tester.pumpAndSettle();

    final clear = owner.commands.singleWhere(
      (command) => command.type == RiskMonitorCommandType.clearHistory,
    );
    expect(clear.episodeKey, eth.episodeKey);
    expect(owner.dispatchCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'RED-003 selected sheet caches the latest verified entry and fails closed across accounts',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final entries = _distinctAggregateEntries();
      final owner = _countingOwner(_distinctAggregateState(entries));
      addTearDown(owner.dispose);
      await tester.pumpWidget(_home(owner));
      await tester.pump();

      final eth = entries.firstWhere(
        (entry) => entry.position?.instrumentId == 'ETH-USDT',
      );
      await tester.tap(
        find.byKey(Key('risk-position-header-${eth.episodeKey}')),
      );
      await tester.pump();
      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, riskVi('exposureSensitivity')),
      );
      await tester.tap(
        find.widgetWithText(OutlinedButton, riskVi('exposureSensitivity')),
      );
      await tester.pumpAndSettle();

      final exposureSheet = find.byType(BottomSheet);
      expect(
        find.descendant(of: exposureSheet, matching: find.text('90.00 USDT')),
        findsNWidgets(2),
      );

      final updatedEth = _distinctPositionEntry(
        riskEvaluation(),
        instrumentId: 'ETH-USDT',
        baseCurrency: 'ETH',
        positionId: 'eth-position',
        markPrice: 11,
        severity: RiskSeverity.watch,
        title: 'ETH V1 plan marker',
        eventMessage: 'ETH V1 event',
      );
      final v1Entries = <RiskPositionMonitorViewState>[
        updatedEth,
        ...entries.where((entry) => entry.episodeKey != eth.episodeKey),
      ];
      owner.publish(_distinctAggregateState(v1Entries));
      await tester.pump();
      await tester.pump();
      expect(
        find.descendant(of: exposureSheet, matching: find.text('110.00 USDT')),
        findsNWidgets(2),
      );

      final omissionEntries = v1Entries
          .where((entry) => entry.episodeKey != eth.episodeKey)
          .toList(growable: false);
      owner.publish(_distinctAggregateState(omissionEntries));
      await tester.pump();
      expect(
        find.descendant(of: exposureSheet, matching: find.text('110.00 USDT')),
        findsNWidgets(2),
      );
      expect(
        find.descendant(of: exposureSheet, matching: find.text('90.00 USDT')),
        findsNothing,
      );

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'RED-003 selected sheet fails closed for mismatched and missing accounts',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final entries = _distinctAggregateEntries();
      final owner = _countingOwner(_distinctAggregateState(entries));
      addTearDown(owner.dispose);
      await tester.pumpWidget(_home(owner));
      await tester.pump();

      final eth = entries.firstWhere(
        (entry) => entry.position?.instrumentId == 'ETH-USDT',
      );
      await tester.tap(
        find.byKey(Key('risk-position-header-${eth.episodeKey}')),
      );
      await tester.pump();
      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, riskVi('exposureSensitivity')),
      );
      await tester.tap(
        find.widgetWithText(OutlinedButton, riskVi('exposureSensitivity')),
      );
      await tester.pumpAndSettle();

      final crossAccountEth = _rekeyDistinctEntry(
        _distinctPositionEntry(
          riskEvaluation(),
          instrumentId: 'ETH-USDT',
          baseCurrency: 'ETH',
          positionId: 'other-account-eth',
          markPrice: 22,
          severity: RiskSeverity.watch,
          title: 'Other account plan marker',
          eventMessage: 'Other account event',
          accountNamespace: 'other-account',
        ),
        accountPositionId: 'other-account-eth',
        episodeKey: eth.episodeKey,
      );
      expect(crossAccountEth.episodeKey, eth.episodeKey);
      expect(crossAccountEth.position?.accountNamespace, 'other-account');
      expect(crossAccountEth.position?.markPrice, 22);
      final crossAccountEntries = <RiskPositionMonitorViewState>[
        crossAccountEth,
        ...entries.where((entry) => entry.episodeKey != eth.episodeKey),
      ];
      owner.publish(
        _distinctAggregateState(
          crossAccountEntries,
          accountHash: 'other-account',
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text(riskVi('exposureUnavailable')), findsOneWidget);
      expect(find.text('220.00 USDT'), findsNothing);

      owner.publish(
        _distinctAggregateState(crossAccountEntries, accountHash: null),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text(riskVi('exposureUnavailable')), findsOneWidget);
      expect(find.text('220.00 USDT'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'RED-003 net direction normalizes to long and freshness is distinct from quality',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final netEntry = _distinctPositionEntry(
        riskEvaluation(),
        instrumentId: 'NET-USDT',
        baseCurrency: 'NET',
        positionId: 'net-position',
        markPrice: 11,
        severity: RiskSeverity.normal,
        title: 'NET plan marker',
        eventMessage: 'NET-only event',
        positionSide: 'net',
      );
      final owner = _countingOwner(
        _distinctAggregateState([netEntry], accountHash: 'net-account'),
      );
      addTearDown(owner.dispose);
      await tester.pumpWidget(_home(owner));
      await tester.pump();

      expect(find.text('LONG'), findsWidgets);
      expect(find.text('NET'), findsNothing);
      expect(find.textContaining('${riskVi('observed')} 9/10'), findsWidgets);
      expect(find.text(riskQualityLabel(completeQuality())), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'RED-003 empty, stale and partial states never claim safety or stable data',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final owner = InMemoryRiskMonitorOwner(
        initial: RiskMonitorViewState(
          quality: const RiskQuality.empty(
            reason: 'No eligible isolated position',
          ),
        ),
      );
      addTearDown(owner.dispose);

      await tester.pumpWidget(_home(owner));
      await tester.pump();
      expect(find.text(riskVi('noIsolatedPosition')), findsOneWidget);
      expect(find.text(riskViSeverity(RiskSeverity.normal)), findsNothing);
      expect(find.text('Stable'), findsNothing);
      expect(find.textContaining('PnL'), findsNothing);

      owner.publish(
        RiskMonitorViewState(
          quality: const RiskQuality.partial(reason: 'Mark price is stale'),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text(riskVi('partialAssessment')), findsOneWidget);
      expect(find.text(riskViSeverity(RiskSeverity.normal)), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'RED-003 at 320px and 200 percent text remains scroll accessible',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final owner = _ownerWithEvaluation();
      addTearDown(owner.dispose);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: _home(owner),
        ),
      );
      await tester.pump();
      final scroll = find.byKey(const Key('risk-home-scroll'));
      expect(scroll, findsOneWidget);
      await tester.drag(scroll, const Offset(0, -2400));
      await tester.pump();
      await tester.ensureVisible(find.text(riskVi('createRule')));
      await tester.ensureVisible(find.text(riskVi('createZone')));
      expect(find.text('Kế hoạch của bạn'), findsOneWidget);
      expect(find.text(riskVi('createRule')), findsOneWidget);
      expect(find.text(riskVi('createZone')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'RED-003 cached complete evaluation never overrides stale, error or partial state quality',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final evaluation = riskEvaluation();
      final owner = InMemoryRiskMonitorOwner(
        initial: RiskMonitorViewState(
          isRunning: true,
          accountHash: 'cached-account',
          episodeKey: evaluation.position.episodeKey,
          evaluation: evaluation,
          quality: const RiskQuality.stale(
            source: 'cache',
            reason: 'Snapshot is outside the freshness window',
          ),
        ),
      );
      addTearDown(owner.dispose);
      await tester.pumpWidget(_home(owner));
      await tester.pump();

      for (final entry in <RiskQuality, String>{
        const RiskQuality.stale(reason: 'Snapshot is stale'): riskViQuality(
          const RiskQuality.stale(),
        ),
        const RiskQuality.error(reason: 'Offline storage read failed'):
            riskViQuality(const RiskQuality.error()),
        const RiskQuality.partial(reason: 'Funding source is incomplete'):
            riskViQuality(const RiskQuality.partial()),
      }.entries) {
        owner.publish(
          RiskMonitorViewState(
            isRunning: true,
            accountHash: 'cached-account',
            episodeKey: evaluation.position.episodeKey,
            evaluation: evaluation,
            quality: entry.key,
            lastError: entry.key.status == RiskQualityStatus.error
                ? 'Permission denied 401'
                : null,
          ),
        );
        await tester.pump();
        expect(find.text(entry.value), findsWidgets);
        expect(
          find.textContaining(riskViSeverity(RiskSeverity.normal)),
          findsWidgets,
        );
        expect(
          find.textContaining(
            '${riskVi('atLeast')} ${riskViSeverity(RiskSeverity.normal)}',
          ),
          findsWidgets,
        );
        expect(find.text('Fresh'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'RED-003 partial and stale states preserve cached CRITICAL as last known',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final evaluation = riskEvaluation(markPrice: 5);
      final owner = InMemoryRiskMonitorOwner(
        initial: RiskMonitorViewState(
          isRunning: true,
          accountHash: 'critical-cache',
          episodeKey: evaluation.position.episodeKey,
          evaluation: evaluation,
          quality: const RiskQuality.stale(
            source: 'cache',
            reason: 'Cached critical snapshot is outside the freshness window',
          ),
        ),
      );
      addTearDown(owner.dispose);
      await tester.pumpWidget(_home(owner));
      await tester.pump();

      for (final quality in const <RiskQuality>[
        RiskQuality.stale(reason: 'Critical snapshot is stale'),
        RiskQuality.partial(reason: 'Critical market evidence is incomplete'),
        RiskQuality.error(reason: 'Offline critical snapshot'),
      ]) {
        owner.publish(
          RiskMonitorViewState(
            isRunning: true,
            accountHash: 'critical-cache',
            episodeKey: evaluation.position.episodeKey,
            evaluation: evaluation,
            quality: quality,
          ),
        );
        await tester.pump();
        expect(find.text(riskViSeverity(RiskSeverity.critical)), findsWidgets);
        expect(
          find.textContaining(
            '${riskVi('lastKnown')} ${riskViSeverity(RiskSeverity.critical)}',
          ),
          findsWidgets,
        );
        expect(find.text(riskQualityLabel(quality)), findsWidgets);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'RED-003 complete transport qualifies partial NORMAL component assessments',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final base = riskEvaluation();
      final evaluation = RiskEngine(clock: () => riskTestNow).evaluate(
        base.position.copyWith(
          costAttribution: const RiskCostAttribution(
            coverage: RiskCostCoverage.unknown(),
          ),
        ),
        policy: const RiskPolicy(),
        market: const RiskMarketInput(
          state: RiskSeverity.normal,
          complete: false,
          missingReasons: <String>['Funding evidence unavailable'],
        ),
        now: riskTestNow,
      );
      final owner = InMemoryRiskMonitorOwner(
        initial: RiskMonitorViewState(
          isRunning: true,
          accountHash: 'component-quality',
          episodeKey: evaluation.position.episodeKey,
          evaluation: evaluation,
          quality: completeQuality(),
        ),
      );
      addTearDown(owner.dispose);

      await tester.pumpWidget(_home(owner));
      await tester.pump();

      expect(
        find.textContaining(
          '${riskVi('atLeast')} ${riskViSeverity(RiskSeverity.normal)} · ${riskViQuality(const RiskQuality.partial())}',
        ),
        findsWidgets,
      );
      final marketCard = find.byKey(const Key('risk-market-card'));
      expect(
        find.descendant(
          of: marketCard,
          matching: find.textContaining(
            '${riskVi('atLeast')} ${riskViSeverity(RiskSeverity.normal)} · ${riskViQuality(const RiskQuality.partial())}',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(riskViSeverity(RiskSeverity.normal)),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'GREEN-003 F1 Home exposes seven priority answers and engine scenario state',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final owner = _ownerWithEvaluation();
      addTearDown(owner.dispose);
      await tester.pumpWidget(_home(owner));
      await tester.pump();

      for (final label in <String>[
        riskVi('overall'),
        riskVi('trend'),
        riskVi('effectiveLeverage'),
        riskVi('debt'),
        riskVi('trueExit'),
        riskVi('scenarioTenPercent'),
        riskVi('planStatus'),
      ]) {
        final finder = label == riskVi('overall')
            ? find.text(label)
            : find.descendant(
                of: find.byKey(const Key('risk-answer-grid')),
                matching: find.text(label),
              );
        expect(finder, findsOneWidget, reason: 'Missing $label');
      }
      expect(find.text(riskVi('liquidationBuffer')), findsOneWidget);
      expect(find.text(riskVi('position')), findsWidgets);
      expect(find.text(riskVi('market')), findsWidgets);
      expect(find.text(riskVi('recovery')), findsWidgets);
      final planStatus = tester.getRect(
        find.byKey(const ValueKey<String>('risk-answer-Plan status')),
      );
      expect(planStatus.bottom, lessThanOrEqualTo(1230));
      await tester.ensureVisible(find.text(riskVi('scenarioTenPercent')));
      final scenario = owner.currentState.evaluation!.stressScenarios
          .firstWhere(
            (item) =>
                item.percentageChange != null &&
                (item.percentageChange! + 0.10).abs() < 1e-9,
          );
      expect(find.text(riskViSeverity(scenario.overallState)), findsWidgets);
      expect(find.textContaining('PnL'), findsNothing);

      final independent = RiskEngine(clock: () => riskTestNow).evaluate(
        owner.currentState.evaluation!.position.copyWith(
          markPrice: scenario.price,
        ),
        policy: const RiskPolicy(),
        market: const RiskMarketInput(
          state: RiskSeverity.normal,
          complete: true,
          dailyVolatility: 0.10,
        ),
        now: riskTestNow,
      );
      expect(scenario.positionState, independent.positionAssessment.state);
      expect(scenario.overallState, independent.overallState);

      await tester.drag(
        find.byKey(const Key('risk-home-scroll')),
        const Offset(0, -1100),
      );
      await tester.pumpAndSettle();
      final recoveryButton = find.text(riskVi('recoveryCosts'));
      await tester.ensureVisible(recoveryButton);
      await tester.pumpAndSettle();
      await tester.tap(recoveryButton);
      await tester.pumpAndSettle();
      expect(find.text(riskVi('recoveryCosts')), findsWidgets);
      expect(find.textContaining('được sàn bảo đảm'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'GREEN-003 Home consumes typed persisted state and switches account data atomically',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final evaluation = riskEvaluation();
      final episodeKey = evaluation.position.episodeKey;
      final firstPlan = riskPlan(
        episode: episodeKey,
        rules: [riskRule(episode: episodeKey, title: 'Account A rule')],
      );
      const firstSettings = RiskSettings(customStressPrices: [11]);
      final firstSample = riskSample(episode: episodeKey);
      final firstSummary = RiskDailySummary(
        episodeKey: episodeKey,
        dateKey: '2026-09-10',
        timeZone: 'UTC+7',
        capturedAt: riskTestNow,
        quality: completeQuality(),
        overallState: RiskSeverity.normal,
        positionState: RiskSeverity.normal,
        marketState: RiskSeverity.normal,
        recoveryState: RiskSeverity.watch,
        buffer: 0.4,
        effectiveLeverage: 2,
        actualInterestToday: 0.12,
        knownInterestToday: 0.1,
        actualInterestQuality: completeQuality(),
        interestCoverageComplete: true,
        majorChange: 'Debt changed by 5.00 USDT',
        activeRuleCount: 1,
        unknownRuleCount: 0,
      );
      final baseline = riskSample(
        episode: episodeKey,
        state: RiskSeverity.normal,
        buffer: 0.4,
        leverage: 2,
        debt: 100,
        trueExit: 10,
        structureLabel: 'Stable',
        fundingLabel: 'Neutral',
        openInterestChange: 0.02,
      );
      final current = riskSample(
        episode: episodeKey,
        state: RiskSeverity.watch,
        buffer: 0.3,
        leverage: 2.5,
        debt: 105,
        trueExit: 11,
        structureLabel: 'Breakdown',
        fundingLabel: 'Crowded',
        openInterestChange: 0.12,
      );
      final previousCheck = RiskSessionComparison(
        baseline: baseline,
        current: current,
        bufferDeltaPoints: -10,
        leverageDelta: 0.5,
        debtDelta: 5,
        trueExitChanged: true,
        overallChanged: true,
      );
      final owner = InMemoryRiskMonitorOwner(
        initial: RiskMonitorViewState(
          isRunning: true,
          accountHash: 'account-a',
          episodeKey: episodeKey,
          evaluation: evaluation,
          plan: firstPlan,
          settings: firstSettings,
          samples: [firstSample],
          summaries: [firstSummary],
          previousCheck: previousCheck,
          quality: evaluation.quality,
        ),
      );
      addTearDown(owner.dispose);
      expect(owner.currentState.samples, isA<List<RiskHistorySample>>());
      expect(
        () => owner.currentState.samples!.add(firstSample),
        throwsUnsupportedError,
      );
      await tester.pumpWidget(_home(owner));
      await tester.pump();
      expect(find.text(riskVi('noPreviousCheck')), findsNothing);
      expect(find.text(riskVi('previousCheck')), findsOneWidget);
      expect(find.text(riskVi('overall')), findsWidgets);
      expect(find.text(riskVi('buffer')), findsWidgets);
      expect(find.text(riskVi('leverage')), findsWidgets);
      expect(find.text(riskVi('debt')), findsWidgets);
      expect(find.text(riskVi('trueExit')), findsWidgets);
      expect(find.text(riskVi('structure')), findsWidgets);
      expect(find.text(riskVi('funding')), findsWidgets);
      expect(find.text('OI'), findsWidgets);
      expect(
        find.textContaining(
          '${riskViSeverity(RiskSeverity.normal)} → ${riskViSeverity(RiskSeverity.watch)}',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('40.0% → 30.0%'), findsOneWidget);
      expect(find.textContaining('10.00 USDT → 11.00 USDT'), findsOneWidget);

      await tester.drag(
        find.byKey(const Key('risk-home-scroll')),
        const Offset(0, -1800),
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Account A rule'));
      expect(find.text('Account A rule'), findsOneWidget);

      final nextEvaluation = riskEvaluation(markPrice: 9);
      final nextPlan = riskPlan(
        episode: episodeKey,
        rules: [
          riskRule(id: 'rule-b', episode: episodeKey, title: 'Account B rule'),
        ],
      );
      owner.publish(
        RiskMonitorViewState(
          isRunning: true,
          accountHash: 'account-b',
          episodeKey: episodeKey,
          evaluation: nextEvaluation,
          plan: nextPlan,
          settings: const RiskSettings(customStressPrices: [12]),
          samples: [riskSample(episode: episodeKey, markPrice: 9)],
          summaries: const <RiskDailySummary>[],
          quality: nextEvaluation.quality,
        ),
      );
      await tester.pump();
      expect(find.text('Account A rule'), findsNothing);
      expect(find.text('Account B rule'), findsOneWidget);
      expect(owner.currentState.settings!.customStressPrices, [12]);
      expect(owner.currentState.summaries, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'GREEN-003 history renders daily and previous data then clear updates the open surface',
    (tester) async {
      final evaluation = riskEvaluation();
      final episodeKey = evaluation.position.episodeKey;
      final event = RiskEvent(
        id: 'event-1',
        episodeKey: episodeKey,
        kind: RiskEventKind.factorEntry,
        message: 'Debt changed by 5.00 USDT',
        createdAt: riskTestNow,
        observedAt: riskTestNow,
        previousValue: 100,
        currentValue: 105,
        source: 'synthetic-1',
      );
      final summary = RiskDailySummary(
        episodeKey: episodeKey,
        dateKey: '2026-09-10',
        timeZone: 'UTC+7',
        capturedAt: riskTestNow,
        quality: completeQuality(),
        overallState: RiskSeverity.watch,
        positionState: RiskSeverity.normal,
        marketState: RiskSeverity.watch,
        recoveryState: RiskSeverity.high,
        buffer: 0.25,
        effectiveLeverage: 2.5,
        actualInterestToday: 0.12,
        knownInterestToday: 0.1,
        actualInterestQuality: completeQuality(),
        interestCoverageComplete: false,
        majorChange: 'Buffer changed by -10 pp',
        activeRuleCount: 2,
        unknownRuleCount: 1,
      );
      final previousCheck = RiskSessionComparison(
        baseline: riskSample(
          episode: episodeKey,
          state: RiskSeverity.normal,
          buffer: 0.4,
          leverage: 2,
          debt: 100,
          trueExit: 10,
          structureLabel: 'Stable',
          fundingLabel: 'Neutral',
          openInterestChange: 0.02,
        ),
        current: riskSample(
          episode: episodeKey,
          state: RiskSeverity.watch,
          buffer: 0.3,
          leverage: 2.5,
          debt: 105,
          trueExit: 11,
          structureLabel: 'Breakdown',
          fundingLabel: 'Crowded',
          openInterestChange: 0.12,
        ),
        bufferDeltaPoints: -10,
        leverageDelta: 0.5,
        debtDelta: 5,
        trueExitChanged: true,
        overallChanged: true,
      );
      final owner = InMemoryRiskMonitorOwner(
        initial: RiskMonitorViewState(
          isRunning: true,
          accountHash: 'history-account',
          episodeKey: episodeKey,
          evaluation: evaluation,
          samples: [riskSample(episode: episodeKey)],
          summaries: [summary],
          events: [event],
          previousCheck: previousCheck,
          quality: evaluation.quality,
        ),
      );
      addTearDown(owner.dispose);
      await tester.pumpWidget(_home(owner));
      await tester.pump();
      await tester.drag(
        find.byKey(const Key('risk-home-scroll')),
        const Offset(0, -1800),
      );
      await tester.pump();
      await tester.ensureVisible(find.text(riskVi('history')));
      await tester.tap(find.text(riskVi('history')));
      await tester.pumpAndSettle();
      final history = find.byType(RiskHistoryView);
      expect(history, findsOneWidget);
      final previousOverall = find.descendant(
        of: history,
        matching: find.textContaining(
          '${riskViSeverity(RiskSeverity.normal)} → ${riskViSeverity(RiskSeverity.watch)}',
        ),
      );
      await tester.drag(find.byType(ListView).last, const Offset(0, -120));
      await tester.pump();
      expect(previousOverall, findsOneWidget);
      expect(
        find.descendant(
          of: history,
          matching: find.textContaining('40.0% → 30.0%'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: history,
          matching: find.textContaining('10.00 USDT → 11.00 USDT'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: history,
          matching: find.text(riskVi('trendVelocity')),
        ),
        findsOneWidget,
      );
      final dailyDate = find.descendant(
        of: history,
        matching: find.text('2026-09-10'),
      );
      await tester.scrollUntilVisible(
        dailyDate,
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(dailyDate, findsOneWidget);
      expect(
        find.descendant(
          of: history,
          matching: find.textContaining('Một phần / chưa rõ'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: history,
          matching: find.textContaining('Thay đổi lớn'),
        ),
        findsOneWidget,
      );
      await tester.drag(find.byType(ListView).last, const Offset(0, 1200));
      await tester.pump();
      await tester.ensureVisible(find.text(riskVi('clearHistory')));
      await tester.tap(find.text(riskVi('clearHistory')));
      await tester.pump();
      await tester.pump();
      expect(
        find.descendant(
          of: history,
          matching: find.text(riskVi('noDailySummary')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: history,
          matching: find.text(riskVi('noRiskEvents')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: history,
          matching: find.text(riskVi('noPreviousCheck')),
        ),
        findsOneWidget,
      );
      expect(owner.currentState.samples, isEmpty);
      expect(owner.currentState.summaries, isEmpty);
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(riskVi('noPreviousCheck')));
      expect(find.text(riskVi('noPreviousCheck')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'GREEN-003 privacy redacts market, stress, history and semantics content',
    (tester) async {
      final evaluation = riskEvaluation();
      final market = RiskMarketInput(
        state: RiskSeverity.watch,
        complete: true,
        dailyVolatility: 0.1,
        source: 'market-123',
        observedAt: riskTestNow,
        sourceAt: riskTestNow,
        reasons: [
          RiskReason(
            factorId: 'funding-123',
            message: 'Observed mark price 123.45 exceeded 100.00',
            observedValue: 123.45,
            threshold: '100.00',
            unit: 'USDT',
            window: '4h',
            observedAt: riskTestNow,
            source: 'feed-1',
          ),
        ],
      );
      final event = RiskEvent(
        id: 'privacy-event',
        episodeKey: evaluation.position.episodeKey,
        kind: RiskEventKind.factorEntry,
        message: 'Observed 123.45 USDT at 14:00',
        createdAt: riskTestNow,
        observedAt: riskTestNow,
        previousValue: 100,
        currentValue: 123.45,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SingleChildScrollView(
            child: Column(
              children: [
                RiskMarketCard(
                  key: const Key('privacy-market'),
                  evaluation: evaluation,
                  market: market,
                  hideValues: true,
                ),
                SizedBox(
                  height: 700,
                  child: RiskStressView(
                    key: const Key('privacy-stress'),
                    evaluation: evaluation,
                    hideValues: true,
                  ),
                ),
                SizedBox(
                  height: 700,
                  child: RiskHistoryView(
                    key: const Key('privacy-history'),
                    events: [event],
                    samples: [
                      riskSample(episode: evaluation.position.episodeKey),
                    ],
                    hideValues: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('123.45'), findsNothing);
      expect(find.text('100.00'), findsNothing);
      expect(find.textContaining('-10%'), findsNothing);
      for (final key in const <Key>[
        Key('privacy-market'),
        Key('privacy-stress'),
        Key('privacy-history'),
      ]) {
        final semantics = tester.getSemantics(find.byKey(key)).toStringDeep();
        expect(semantics, isNot(contains('123.45')));
        expect(semantics, isNot(contains('100.00')));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'GREEN-003 captures rendered light, dark, desktop and boundary screenshots',
    (tester) async {
      final owner = _ownerWithEvaluation();
      addTearDown(owner.dispose);
      final sizes = <String, Size>{
        'light-390x844': const Size(390, 844),
        'dark-390x844': const Size(390, 844),
        'light-1280x900': const Size(1280, 900),
        'boundary-320x844-text-200': const Size(320, 844),
      };
      for (final entry in sizes.entries) {
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1;
        final dark = entry.key.startsWith('dark');
        final large = entry.key.startsWith('boundary');
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(large ? 2 : 1)),
            child: Theme(
              data: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light,
                fontFamily: screenshotFontFamily,
                useMaterial3: true,
              ),
              child: _home(
                owner,
                themeMode: dark ? ThemeMode.dark : ThemeMode.light,
                fontFamily: screenshotFontFamily,
              ),
            ),
          ),
        );
        await tester.pump();
        if (entry.key == 'light-390x844') {
          final trend = tester.getRect(
            find.byKey(const ValueKey<String>('risk-answer-Trend')),
          );
          final buffer = tester.getRect(
            find.byKey(const Key('risk-buffer-hero')),
          );
          expect(trend.width, lessThan(200));
          expect(buffer.width, greaterThan(300));
          expect(buffer.left, closeTo(trend.left, 1));
          expect(trend.top, greaterThan(buffer.bottom));
          final planStatus = tester.getRect(
            find.byKey(const ValueKey<String>('risk-answer-Plan status')),
          );
          expect(planStatus.bottom, lessThanOrEqualTo(1139));
        }
        if (entry.key == 'light-1280x900') {
          final overview = tester.getRect(
            find.byKey(const Key('risk-overview')),
          );
          final market = tester.getRect(
            find.byKey(const Key('risk-market-card')),
          );
          final plan = tester.getRect(
            find.byKey(const Key('risk-plan-editor')),
          );
          expect(overview.left, lessThan(market.left));
          expect(plan.left, greaterThan(overview.left));
        }
        await _captureRenderedScreenshot(
          tester,
          '${entry.key}.png',
          entry.value,
        );
        expect(tester.takeException(), isNull);
      }
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    },
  );

  testWidgets(
    'GREEN-003 drill-down widgets render without financial fallback values',
    (tester) async {
      final evaluation = riskEvaluation();
      await tester.pumpWidget(
        MaterialApp(
          home: SingleChildScrollView(
            child: Column(
              children: [
                RiskMarketCard(evaluation: evaluation),
                SizedBox(
                  height: 500,
                  child: RiskStressView(evaluation: evaluation),
                ),
                SizedBox(
                  height: 500,
                  child: RiskRecoveryView(evaluation: evaluation),
                ),
                const SizedBox(height: 500, child: RiskHistoryView()),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text(riskVi('marketRisk')), findsOneWidget);
      expect(find.text(riskVi('stressScenarios')), findsOneWidget);
      expect(find.text(riskVi('recoveryCosts')), findsOneWidget);
      expect(find.text(riskVi('historyAndChecks')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

ProviderScope _homeOwnerScope(
  InMemoryRiskMonitorOwner owner,
  Widget child, {
  ThemeMode themeMode = ThemeMode.light,
  bool hidden = false,
  String? visitKey,
}) {
  return ProviderScope(
    key: ValueKey<String>('risk-home-$themeMode-${visitKey ?? 'default'}'),
    overrides: [
      riskMonitorOwnerProvider.overrideWithValue(owner),
      riskMonitorBridgeProvider.overrideWithValue(RiskMonitorBridge(owner)),
      themeModeProvider.overrideWith((ref) => themeMode),
      hideBalanceProvider.overrideWith((ref) => hidden),
    ],
    child: child,
  );
}

Widget _home(
  InMemoryRiskMonitorOwner owner, {
  ThemeMode themeMode = ThemeMode.light,
  String? fontFamily,
  bool hidden = false,
  String? visitKey,
}) {
  return _homeOwnerScope(
    owner,
    MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        fontFamily: fontFamily,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: fontFamily,
      ),
      themeMode: themeMode,
      home: const RepaintBoundary(
        key: Key('risk-home-boundary'),
        child: RiskDashboardScreen(),
      ),
    ),
    themeMode: themeMode,
    hidden: hidden,
    visitKey: visitKey,
  );
}

RiskPositionMonitorViewState _positionEntry(
  RiskEvaluation base, {
  required String key,
  required RiskSeverity severity,
  RiskQuality? quality,
  String? lastError,
}) {
  final evaluation = RiskEvaluation(
    position: base.position,
    metrics: base.metrics,
    positionAssessment: base.positionAssessment,
    marketAssessment: base.marketAssessment,
    recoveryAssessment: base.recoveryAssessment,
    overallState: severity,
    quality: quality ?? base.quality,
    reasons: base.reasons,
    stressScenarios: base.stressScenarios,
    priceMap: base.priceMap,
    evaluatedAt: base.evaluatedAt,
    policyVersion: base.policyVersion,
    missingReasons: base.missingReasons,
    exchangePnlBasis: base.exchangePnlBasis,
  );
  return RiskPositionMonitorViewState(
    positionId: key,
    episodeKey: key,
    position: base.position,
    evaluation: evaluation,
    quality: quality ?? base.quality,
    lastError: lastError,
  );
}

RiskMonitorViewState _aggregateDashboardState() {
  final base = riskEvaluation();
  return RiskMonitorViewState(
    isRunning: true,
    backgroundAvailable: true,
    accountHash: 'aggregate-account',
    quality: completeQuality(),
    requestStatus: RiskMonitorRequestStatus.backingOff,
    retryAt: riskTestNow.add(const Duration(seconds: 30)),
    positions: <RiskPositionMonitorViewState>[
      _positionEntry(base, key: 'btc', severity: RiskSeverity.normal),
      _positionEntry(base, key: 'eth', severity: RiskSeverity.watch),
      _positionEntry(base, key: 'sui', severity: RiskSeverity.high),
      _positionEntry(
        base,
        key: 'failed',
        severity: RiskSeverity.normal,
        quality: const RiskQuality.error(reason: 'Synthetic position failure'),
        lastError: 'Position request failed',
      ),
    ],
  );
}

List<RiskPositionMonitorViewState> _distinctAggregateEntries() {
  final base = riskEvaluation();
  return <RiskPositionMonitorViewState>[
    _distinctPositionEntry(
      base,
      instrumentId: 'ETH-USDT',
      baseCurrency: 'ETH',
      positionId: 'eth-position',
      markPrice: 9,
      severity: RiskSeverity.watch,
      title: 'ETH plan marker',
      eventMessage: 'ETH-only event',
    ),
    _distinctPositionEntry(
      base,
      instrumentId: 'BTC-USDT',
      baseCurrency: 'BTC',
      positionId: 'btc-position',
      markPrice: 10,
      severity: RiskSeverity.normal,
      title: 'BTC plan marker',
      eventMessage: 'BTC-only event',
    ),
    _distinctPositionEntry(
      base,
      instrumentId: 'SUI-USDT',
      baseCurrency: 'SUI',
      positionId: 'sui-position',
      markPrice: 8,
      severity: RiskSeverity.high,
      title: 'SUI plan marker',
      eventMessage: 'SUI-only event',
    ),
  ];
}

RiskMonitorViewState _distinctAggregateState(
  List<RiskPositionMonitorViewState> entries, {
  String? accountHash = 'distinct-aggregate-account',
}) {
  final primary = entries.firstWhere(
    (entry) => entry.position?.instrumentId == 'BTC-USDT',
    orElse: () => entries.first,
  );
  return RiskMonitorViewState(
    isRunning: true,
    backgroundAvailable: true,
    accountHash: accountHash,
    episodeKey: primary.episodeKey,
    evaluation: primary.evaluation,
    plan: primary.plan,
    events: primary.events,
    samples: primary.samples,
    summaries: primary.summaries,
    quality: completeQuality(),
    requestStatus: RiskMonitorRequestStatus.ready,
    positions: entries,
  );
}

RiskPositionMonitorViewState _distinctPositionEntry(
  RiskEvaluation base, {
  required String instrumentId,
  required String baseCurrency,
  required String positionId,
  required double markPrice,
  required RiskSeverity severity,
  required String title,
  required String eventMessage,
  String? positionSide,
  String accountNamespace = 'distinct-account',
}) {
  final observedAt = riskTestNow.add(Duration(minutes: markPrice.toInt()));
  final position = RiskPosition(
    instrumentId: instrumentId,
    instrumentType: base.position.instrumentType,
    mode: base.position.mode,
    collateralCurrency: base.position.collateralCurrency,
    positionSide: positionSide ?? base.position.positionSide,
    accountNamespace: accountNamespace,
    positionId: positionId,
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: observedAt,
    observedAt: observedAt,
    baseCurrency: baseCurrency,
    quoteCurrency: base.position.quoteCurrency,
    positionCurrency: baseCurrency,
    accountCurrency: base.position.accountCurrency,
    liabilityCurrency: base.position.liabilityCurrency,
    rawQuantity: base.position.rawQuantity,
    quantity: base.position.quantity,
    margin: base.position.margin,
    markPrice: markPrice,
    entryPrice: base.position.entryPrice,
    liquidationPrice: base.position.liquidationPrice,
    unrealizedPnl: base.position.unrealizedPnl,
    reportedLeverage: base.position.reportedLeverage,
    marginRatio: base.position.marginRatio,
    maintenanceRequirement: base.position.maintenanceRequirement,
    reportedLiability: base.position.reportedLiability,
    reportedInterest: base.position.reportedInterest,
    baseBalance: base.position.baseBalance,
    quoteBalance: base.position.quoteBalance,
    baseBorrowed: base.position.baseBorrowed,
    quoteBorrowed: base.position.quoteBorrowed,
    baseInterest: base.position.baseInterest,
    quoteInterest: base.position.quoteInterest,
    hourlyBorrowRate: base.position.hourlyBorrowRate,
    entryFeeRate: base.position.entryFeeRate,
    exitFeeRate: base.position.exitFeeRate,
    costAttribution: base.position.costAttribution,
    quality: completeQuality(observedAt, 'distinct-position'),
    eligibility: base.position.eligibility,
    source: 'distinct-position',
  );
  final evaluated = RiskEngine(clock: () => observedAt).evaluate(
    position,
    policy: const RiskPolicy(),
    market: const RiskMarketInput(
      state: RiskSeverity.normal,
      complete: true,
      dailyVolatility: 0.1,
    ),
    now: observedAt,
  );
  final evaluation = RiskEvaluation(
    position: evaluated.position,
    metrics: evaluated.metrics,
    positionAssessment: evaluated.positionAssessment,
    marketAssessment: evaluated.marketAssessment,
    recoveryAssessment: evaluated.recoveryAssessment,
    overallState: severity,
    quality: evaluated.quality,
    reasons: evaluated.reasons,
    stressScenarios: evaluated.stressScenarios,
    priceMap: evaluated.priceMap,
    evaluatedAt: evaluated.evaluatedAt,
    policyVersion: evaluated.policyVersion,
    missingReasons: evaluated.missingReasons,
    exchangePnlBasis: evaluated.exchangePnlBasis,
  );
  final episodeKey = position.episodeKey;
  final at = observedAt;
  return RiskPositionMonitorViewState(
    positionId: positionId,
    episodeKey: episodeKey,
    position: position,
    evaluation: evaluation,
    plan: riskPlan(
      episode: episodeKey,
      rules: [riskRule(episode: episodeKey, title: title)],
    ),
    events: [
      RiskEvent(
        id: 'event-$positionId',
        episodeKey: episodeKey,
        kind: RiskEventKind.stateChange,
        message: eventMessage,
        createdAt: at,
        observedAt: at,
        severity: severity,
        source: 'distinct-fixture',
      ),
    ],
    samples: [
      riskSample(
        episode: episodeKey,
        at: at,
        markPrice: markPrice,
        state: severity,
      ),
    ],
    summaries: [
      RiskDailySummary(
        episodeKey: episodeKey,
        dateKey: '2026-09-${markPrice.toInt()}',
        timeZone: 'UTC',
        capturedAt: at,
        quality: completeQuality(at, 'distinct-summary'),
        overallState: severity,
        buffer: evaluation.buffer,
        effectiveLeverage: evaluation.effectiveLeverage,
        majorChange: eventMessage,
      ),
    ],
    quality: completeQuality(at, 'distinct-position'),
  );
}

RiskPositionMonitorViewState _rekeyDistinctEntry(
  RiskPositionMonitorViewState entry, {
  required String accountPositionId,
  required String episodeKey,
}) {
  return RiskPositionMonitorViewState(
    positionId: accountPositionId,
    episodeKey: episodeKey,
    positionSide: entry.positionSide,
    position: entry.position,
    evaluation: entry.evaluation,
    planEvaluation: entry.planEvaluation,
    plan: entry.plan,
    settings: entry.settings,
    market: entry.market,
    samples: entry.samples,
    summaries: entry.summaries,
    previousCheck: entry.previousCheck,
    trend: entry.trend,
    velocity: entry.velocity,
    events: entry.events,
    quality: entry.quality,
    unsaved: entry.unsaved,
    lastError: entry.lastError,
    freshnessAt: entry.freshnessAt,
  );
}

_CountingRiskMonitorOwner _countingOwner(RiskMonitorViewState state) =>
    _CountingRiskMonitorOwner(initial: state);

class _CountingRiskMonitorOwner extends InMemoryRiskMonitorOwner {
  _CountingRiskMonitorOwner({required super.initial});

  int dispatchCalls = 0;
  final List<RiskMonitorCommand> commands = <RiskMonitorCommand>[];

  @override
  Future<RiskMonitorCommandResult> dispatch(RiskMonitorCommand command) {
    dispatchCalls++;
    commands.add(command);
    return super.dispatch(command);
  }
}

Future<String> _loadScreenshotFont() async {
  const family = 'RiskScreenshotRoboto';
  final materialFonts = _findMaterialFontsDirectory();
  if (materialFonts == null) {
    fail(
      'Readable screenshot font unavailable: set FLUTTER_ROOT or expose its material_fonts cache in PATH.',
    );
  }
  final loader = FontLoader(family);
  for (final name in const <String>[
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]) {
    final file = File('$materialFonts/$name');
    if (!file.existsSync()) {
      fail('Readable screenshot font unavailable: missing ${file.path}.');
    }
    loader.addFont(
      file.readAsBytes().then((bytes) => bytes.buffer.asByteData()),
    );
  }
  await loader.load();
  final materialIcons = File('$materialFonts/MaterialIcons-Regular.otf');
  if (materialIcons.existsSync()) {
    final iconLoader = FontLoader('MaterialIcons');
    iconLoader.addFont(
      materialIcons.readAsBytes().then((bytes) => bytes.buffer.asByteData()),
    );
    await iconLoader.load();
  }
  return family;
}

String? _findMaterialFontsDirectory() {
  final roots = <String>{};
  final configuredRoot = Platform.environment['FLUTTER_ROOT'];
  if (configuredRoot != null && configuredRoot.trim().isNotEmpty) {
    roots.add(configuredRoot);
  }
  final path = Platform.environment['PATH'];
  if (path != null) {
    for (final entry in path.split(Platform.pathSeparator)) {
      if (entry.trim().isEmpty) continue;
      roots.add(Directory(entry).parent.path);
    }
  }
  for (final root in roots) {
    final directory = Directory('$root/bin/cache/artifacts/material_fonts');
    if (File('${directory.path}/Roboto-Regular.ttf').existsSync()) {
      return directory.path;
    }
  }
  return null;
}

InMemoryRiskMonitorOwner _ownerWithEvaluation() {
  final evaluation = riskEvaluation();
  final plan = riskPlan(rules: [riskRule()]);
  final planEvaluation = const ActionPlanEvaluator().evaluatePlan(
    plan,
    evaluation,
  );
  return InMemoryRiskMonitorOwner(
    initial: RiskMonitorViewState(
      isRunning: true,
      backgroundAvailable: false,
      accountHash: 'synthetic-account',
      episodeKey: evaluation.position.episodeKey,
      evaluation: evaluation,
      planEvaluation: planEvaluation,
      quality: completeQuality(),
    ),
  );
}

Future<void> _captureRenderedScreenshot(
  WidgetTester tester,
  String filename,
  Size expectedSize,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('risk-home-boundary')),
  );
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
  if (image == null) {
    fail('Rendered screenshot image was unavailable');
  }
  try {
    expect(image.width, expectedSize.width.toInt());
    expect(image.height, expectedSize.height.toInt());
    final raw = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    expect(raw, isNotNull);
    final bytes = raw!.buffer.asUint8List();
    final colors = <int>{};
    var visiblePixels = 0;
    for (var index = 0; index + 3 < bytes.length; index += 4) {
      final alpha = bytes[index + 3];
      if (alpha == 0) continue;
      visiblePixels++;
      if (colors.length < 64) {
        colors.add(
          (bytes[index] << 24) |
              (bytes[index + 1] << 16) |
              (bytes[index + 2] << 8) |
              alpha,
        );
      }
    }
    expect(visiblePixels, greaterThan(1000));
    expect(colors.length, greaterThan(8));

    final png = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    );
    expect(png, isNotNull);
    final directory = Directory('/tmp/risk-dashboard-review');
    directory.createSync(recursive: true);
    File(
      '${directory.path}/$filename',
    ).writeAsBytesSync(png!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}
