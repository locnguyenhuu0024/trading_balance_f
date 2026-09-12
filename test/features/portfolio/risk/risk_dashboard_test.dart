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
import 'package:trading_balance_f/features/portfolio/presentation/portfolio_screen.dart';
import 'package:trading_balance_f/features/portfolio/presentation/providers/risk_dashboard_provider.dart';
import 'package:trading_balance_f/features/portfolio/presentation/widgets/risk/risk_history_view.dart';
import 'package:trading_balance_f/features/portfolio/presentation/widgets/risk/risk_market_card.dart';
import 'package:trading_balance_f/features/portfolio/presentation/widgets/risk/risk_recovery_view.dart';
import 'package:trading_balance_f/features/portfolio/presentation/widgets/risk/risk_stress_view.dart';
import 'package:trading_balance_f/features/portfolio/presentation/widgets/risk/risk_overview.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';

import 'fixtures/risk_test_fixtures.dart';

Future<void> main() async {
  final screenshotFontFamily = await _loadScreenshotFont();
  testWidgets(
    'RED-004 empty, stale and partial states never claim safety or stable data',
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
      expect(find.text('No isolated position selected'), findsOneWidget);
      expect(find.text('NORMAL'), findsNothing);
      expect(find.text('Stable'), findsNothing);
      expect(find.textContaining('PnL'), findsNothing);

      owner.publish(
        RiskMonitorViewState(
          quality: const RiskQuality.partial(reason: 'Mark price is stale'),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Partial risk assessment'), findsOneWidget);
      expect(find.text('NORMAL'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'RED-004 at 320px and 200 percent text remains scroll accessible',
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
      await tester.ensureVisible(find.text('Create rule'));
      await tester.ensureVisible(find.text('Create zone'));
      expect(find.text('Your plan'), findsOneWidget);
      expect(find.text('Create rule'), findsOneWidget);
      expect(find.text('Create zone'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'RED-004 cached complete evaluation never overrides stale, error or partial state quality',
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
        const RiskQuality.stale(reason: 'Snapshot is stale'): 'Stale data',
        const RiskQuality.error(reason: 'Offline storage read failed'):
            'Connection error',
        const RiskQuality.partial(reason: 'Funding source is incomplete'):
            'Partial assessment',
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
        expect(find.textContaining('NORMAL'), findsWidgets);
        expect(find.textContaining('At least NORMAL'), findsWidgets);
        expect(find.text('Fresh'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'RED-004 partial and stale states preserve cached CRITICAL as last known',
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
        expect(find.text('CRITICAL'), findsWidgets);
        expect(find.textContaining('Last known CRITICAL'), findsWidgets);
        expect(find.text(riskQualityLabel(quality)), findsWidgets);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'RED-004 complete transport qualifies partial NORMAL component assessments',
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
        find.textContaining('At least NORMAL · Partial assessment'),
        findsWidgets,
      );
      final marketCard = find.byKey(const Key('risk-market-card'));
      expect(
        find.descendant(
          of: marketCard,
          matching: find.textContaining('At least NORMAL · Partial'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('NORMAL'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'GREEN-004 F1 Home exposes seven priority answers and engine scenario state',
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
        'Overall',
        'Trend',
        'Effective leverage',
        'Debt',
        'True Exit',
        '-10% scenario',
        'Plan status',
      ]) {
        expect(find.text(label), findsOneWidget, reason: 'Missing $label');
      }
      expect(find.text('Liquidation buffer'), findsOneWidget);
      expect(find.text('Position'), findsWidgets);
      expect(find.text('Market'), findsWidgets);
      expect(find.text('Recovery'), findsWidgets);
      final planStatus = tester.getRect(
        find.byKey(const ValueKey<String>('risk-answer-Plan status')),
      );
      expect(planStatus.bottom, lessThanOrEqualTo(1139));
      await tester.ensureVisible(find.text('-10% scenario'));
      final scenario = owner.currentState.evaluation!.stressScenarios
          .firstWhere(
            (item) =>
                item.percentageChange != null &&
                (item.percentageChange! + 0.10).abs() < 1e-9,
          );
      expect(find.text(scenario.overallState?.label ?? '-'), findsWidgets);
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
      final recoveryButton = find.text('Recovery & costs');
      await tester.ensureVisible(recoveryButton);
      await tester.pumpAndSettle();
      await tester.tap(recoveryButton);
      await tester.pumpAndSettle();
      expect(find.text('Recovery and costs'), findsWidgets);
      expect(find.textContaining('guaranteed exchange'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'GREEN-004 Home consumes typed persisted state and switches account data atomically',
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
      expect(find.text('No previous check'), findsNothing);
      expect(find.text('Previous check'), findsOneWidget);
      expect(find.text('Overall'), findsWidgets);
      expect(find.text('Buffer'), findsWidgets);
      expect(find.text('Leverage'), findsWidgets);
      expect(find.text('Debt'), findsWidgets);
      expect(find.text('True Exit'), findsWidgets);
      expect(find.text('Structure'), findsWidgets);
      expect(find.text('Funding'), findsWidgets);
      expect(find.text('OI'), findsWidgets);
      expect(find.textContaining('NORMAL → WATCH'), findsOneWidget);
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
    'GREEN-004 history renders daily and previous data then clear updates the open surface',
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
      await tester.ensureVisible(find.text('History'));
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      final history = find.byType(RiskHistoryView);
      expect(history, findsOneWidget);
      final previousOverall = find.descendant(
        of: history,
        matching: find.textContaining('NORMAL → WATCH'),
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
        find.descendant(of: history, matching: find.text('Trend and velocity')),
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
          matching: find.textContaining('Partial / unknown'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: history,
          matching: find.textContaining('Major change'),
        ),
        findsOneWidget,
      );
      await tester.drag(find.byType(ListView).last, const Offset(0, 1200));
      await tester.pump();
      await tester.tap(find.text('Clear history'));
      await tester.pump();
      await tester.pump();
      expect(
        find.descendant(
          of: history,
          matching: find.text('No daily summary captured yet.'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: history,
          matching: find.text('No risk events recorded.'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: history, matching: find.text('No previous check')),
        findsOneWidget,
      );
      expect(owner.currentState.samples, isEmpty);
      expect(owner.currentState.summaries, isEmpty);
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('No previous check'));
      expect(find.text('No previous check'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'GREEN-004 privacy redacts market, stress, history and semantics content',
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
    'GREEN-004 captures rendered light, dark, desktop and boundary screenshots',
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
    'GREEN-004 drill-down widgets render without financial fallback values',
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
      expect(find.text('Market risk'), findsOneWidget);
      expect(find.text('Stress scenarios'), findsOneWidget);
      expect(find.text('Recovery and costs'), findsOneWidget);
      expect(find.text('History and checks'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

ProviderScope _homeOwnerScope(
  InMemoryRiskMonitorOwner owner,
  Widget child, {
  ThemeMode themeMode = ThemeMode.light,
}) {
  return ProviderScope(
    key: ValueKey<String>('risk-home-$themeMode'),
    overrides: [
      riskMonitorOwnerProvider.overrideWithValue(owner),
      riskMonitorBridgeProvider.overrideWithValue(RiskMonitorBridge(owner)),
      themeModeProvider.overrideWith((ref) => themeMode),
    ],
    child: child,
  );
}

Widget _home(
  InMemoryRiskMonitorOwner owner, {
  ThemeMode themeMode = ThemeMode.light,
  String? fontFamily,
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
        child: PortfolioScreen(),
      ),
    ),
    themeMode: themeMode,
  );
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
