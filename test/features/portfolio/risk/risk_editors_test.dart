import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/portfolio/application/risk_monitor_bridge.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/action_plan.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_models.dart';
import 'package:trading_balance_f/features/portfolio/presentation/portfolio_screen.dart';
import 'package:trading_balance_f/features/portfolio/presentation/providers/risk_dashboard_provider.dart';
import 'package:trading_balance_f/features/portfolio/presentation/widgets/risk/risk_plan_editor.dart';
import 'package:trading_balance_f/features/portfolio/presentation/widgets/risk/risk_price_map.dart';
import 'package:trading_balance_f/features/portfolio/presentation/widgets/risk/risk_settings_sheet.dart';
import 'package:trading_balance_f/features/portfolio/presentation/widgets/risk/risk_stress_view.dart';

import 'fixtures/risk_test_fixtures.dart';

void main() {
  testWidgets('RED-004 invalid rule stays unevaluated and cannot save', (
    tester,
  ) async {
    final evaluation = riskEvaluation();
    final owner = InMemoryRiskMonitorOwner(
      initial: RiskMonitorViewState(
        isRunning: true,
        episodeKey: evaluation.position.episodeKey,
        evaluation: evaluation,
        quality: evaluation.quality,
      ),
    );
    addTearDown(owner.dispose);
    await tester.pumpWidget(_editorApp(owner, evaluation.position.episodeKey));

    await tester.tap(find.text('Create rule'));
    await tester.pumpAndSettle();
    expect(find.text('Create rule'), findsWidgets);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Bad buffer rule');
    await tester.enterText(fields.at(1), 'not-a-number');
    await tester.tap(find.text('Save rule'));
    await tester.pump();
    expect(find.textContaining('Rule threshold'), findsOneWidget);
    expect(owner.plan, isNull);
  });

  testWidgets('RED-004 overlapping and reversed zones are rejected', (
    tester,
  ) async {
    final evaluation = riskEvaluation();
    final now = DateTime.utc(2026, 9, 10);
    final invalidZone = RiskZone(
      id: 'zone-invalid',
      episodeKey: evaluation.position.episodeKey,
      title: 'Reversed',
      lowerPrice: 12,
      upperPrice: 10,
      createdAt: now,
      updatedAt: now,
    );
    expect(invalidZone.isValid, isFalse);
    final first = RiskZone(
      id: 'zone-one',
      episodeKey: evaluation.position.episodeKey,
      title: 'First',
      lowerPrice: 9,
      upperPrice: 10,
      createdAt: now,
      updatedAt: now,
    );
    final second = RiskZone(
      id: 'zone-two',
      episodeKey: evaluation.position.episodeKey,
      title: 'Overlapping',
      lowerPrice: 9.5,
      upperPrice: 11,
      createdAt: now,
      updatedAt: now,
    );
    final plan = RiskPlan(
      episodeKey: evaluation.position.episodeKey,
      zones: [first, second],
    );
    expect(plan.isValid, isFalse);
    expect(plan.validate().join(' '), contains('overlap'));
  });

  testWidgets(
    'GREEN-004 account switch from populated plan to null clears editor state',
    (tester) async {
      final evaluation = riskEvaluation();
      final oldPlan = riskPlan(
        episode: evaluation.position.episodeKey,
        rules: [riskRule(title: 'Account A only')],
      );
      final owner = InMemoryRiskMonitorOwner(
        initial: RiskMonitorViewState(
          isRunning: true,
          accountHash: 'account-a',
          episodeKey: evaluation.position.episodeKey,
          evaluation: evaluation,
          plan: oldPlan,
          quality: evaluation.quality,
        ),
      );
      addTearDown(owner.dispose);

      Widget editor({
        required String episodeKey,
        required String accountHash,
        RiskPlan? plan,
      }) {
        return MaterialApp(
          home: Scaffold(
            body: RiskPlanEditor(
              key: const Key('account-switch-plan-editor'),
              episodeKey: episodeKey,
              bridge: RiskMonitorBridge(owner),
              accountHash: accountHash,
              plan: plan,
              evaluation: evaluation,
            ),
          ),
        );
      }

      await tester.pumpWidget(
        editor(
          episodeKey: evaluation.position.episodeKey,
          accountHash: 'account-a',
          plan: oldPlan,
        ),
      );
      await tester.pump();
      expect(find.text('Account A only'), findsOneWidget);

      owner.publish(
        RiskMonitorViewState(
          isRunning: true,
          accountHash: 'account-b',
          episodeKey: evaluation.position.episodeKey,
          evaluation: evaluation,
          quality: evaluation.quality,
        ),
      );
      await tester.pumpWidget(
        editor(
          episodeKey: evaluation.position.episodeKey,
          accountHash: 'account-b',
        ),
      );
      await tester.pump();
      expect(find.text('Account A only'), findsNothing);
      expect(find.text('No plan defined'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'GREEN-004 rule editor persists through typed bridge and settings validates',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final evaluation = riskEvaluation();
      final owner = InMemoryRiskMonitorOwner(
        initial: RiskMonitorViewState(
          isRunning: true,
          episodeKey: evaluation.position.episodeKey,
          evaluation: evaluation,
          quality: evaluation.quality,
        ),
      );
      addTearDown(owner.dispose);
      await tester.pumpWidget(
        _editorApp(owner, evaluation.position.episodeKey),
      );

      await tester.tap(find.text('Create rule'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Buffer review');
      await tester.enterText(fields.at(1), '0.3');
      await tester.tap(find.text('Save rule'));
      await tester.pumpAndSettle();
      expect(owner.plan, isNotNull);
      expect(find.text('Buffer review'), findsOneWidget);

      await tester.tap(find.byTooltip('Edit rule'));
      await tester.pumpAndSettle();
      expect(find.text('Edit'), findsOneWidget);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Edit rule'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit rule'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(owner.plan!.rules, isEmpty);

      await tester.tap(find.text('Create zone'));
      await tester.pumpAndSettle();
      final zoneFields = find.byType(TextField);
      expect(zoneFields, findsNWidgets(4));
      await tester.tap(zoneFields.at(0));
      expect(FocusManager.instance.primaryFocus?.hasFocus, isTrue);
      await tester.enterText(zoneFields.at(0), 'Recovery zone');
      await tester.enterText(zoneFields.at(1), '9');
      await tester.enterText(zoneFields.at(2), '10');
      await tester.tap(find.text('Save zone'));
      await tester.pumpAndSettle();
      expect(owner.plan!.zones, hasLength(1));
      expect(find.text('Recovery zone'), findsOneWidget);
      await tester.tap(find.byTooltip('Edit zone'));
      await tester.pumpAndSettle();
      expect(find.text('Edit'), findsOneWidget);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Edit zone'), findsOneWidget);
      await tester.tap(find.text('Save zone'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit zone'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(owner.plan!.zones, isEmpty);

      final bridge = RiskMonitorBridge(owner);
      RiskSettingsSheet.show(
        tester.element(find.byType(RiskPlanEditor)),
        settings: const RiskSettings(),
        bridge: bridge,
      );
      // The sheet is modal; showing it is enough to prove it is connected to
      // the typed updateSettings command. Its save path is covered below.
      await tester.pumpAndSettle();
      expect(find.text('Risk settings'), findsOneWidget);
      for (final label in <String>[
        'Time zone label',
        'Daily summary hour',
        'Daily summary minute',
        'Sample retention days',
        'OI retention hours',
        'Event retention days',
        'Summary retention days',
        'Maximum history samples',
        'Maximum OI samples',
        'Maximum events',
        'Maximum episodes',
      ]) {
        await tester.scrollUntilVisible(
          find.text(label),
          220,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text(label), findsOneWidget, reason: 'Missing $label');
      }
      expect(const RiskSettings(summaryHour: 24).isValid, isFalse);
      expect(const RiskSettings(sampleRetentionDays: 0).isValid, isFalse);
      await tester.tap(find.text('Save risk settings'));
      await tester.pumpAndSettle();
      expect(owner.settings, isNotNull);
    },
  );

  testWidgets(
    'GREEN-004 scenario editor adds sequential custom prices from latest state and removes a custom row',
    (tester) async {
      final evaluation = riskEvaluation();
      final owner = InMemoryRiskMonitorOwner(
        initial: RiskMonitorViewState(
          isRunning: true,
          accountHash: 'scenario-account',
          episodeKey: evaluation.position.episodeKey,
          evaluation: evaluation,
          settings: const RiskSettings(),
          quality: completeQuality(),
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
      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'Scenarios'),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Scenarios'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Add custom price'),
        280,
        scrollable: find.byType(Scrollable).last,
      );
      final priceField = find.byType(TextField);
      await tester.enterText(priceField, '11');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Add custom price'),
        280,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.enterText(find.byType(TextField), '12');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(owner.currentState.settings!.customStressPrices, [11, 12]);
      final latestStress = tester.widget<RiskStressView>(
        find.byType(RiskStressView),
      );
      expect(
        latestStress.evaluation?.stressScenarios
            .where((scenario) => scenario.percentageChange == null)
            .map((scenario) => scenario.price),
        containsAll(<double>[11, 12]),
      );
      expect(latestStress.onRemoveCustomPrice, isNotNull);
      latestStress.onRemoveCustomPrice!(11);
      await tester.pumpAndSettle();
      expect(owner.currentState.settings!.customStressPrices, [12]);
      final reactiveStress = tester.widget<RiskStressView>(
        find.byType(RiskStressView),
      );
      expect(
        reactiveStress.evaluation?.stressScenarios
            .where((scenario) => scenario.label == 'Custom price')
            .map((scenario) => scenario.price),
        isNot(contains(11)),
      );
      expect(
        reactiveStress.evaluation?.stressScenarios
            .where((scenario) => scenario.label == 'Custom price')
            .map((scenario) => scenario.price),
        contains(12),
      );
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();

      final source = evaluation.stressScenarios.first;
      final custom = RiskStressScenario(
        label: 'Custom 11',
        price: 11,
        percentageChange: null,
        tradePnl: source.tradePnl,
        equity: source.equity,
        effectiveLeverage: source.effectiveLeverage,
        buffer: source.buffer,
        marginRatio: source.marginRatio,
        currentMarginRatio: source.currentMarginRatio,
        marketFrozen: source.marketFrozen,
        marketContextLabel: source.marketContextLabel,
        positionState: source.positionState,
        overallState: source.overallState,
        partial: source.partial,
        hypothetical: source.hypothetical,
        reasons: source.reasons,
      );
      final withCustom = RiskEvaluation(
        position: evaluation.position,
        metrics: evaluation.metrics,
        positionAssessment: evaluation.positionAssessment,
        marketAssessment: evaluation.marketAssessment,
        recoveryAssessment: evaluation.recoveryAssessment,
        overallState: evaluation.overallState,
        quality: evaluation.quality,
        reasons: evaluation.reasons,
        stressScenarios: [...evaluation.stressScenarios, custom],
        priceMap: evaluation.priceMap,
        evaluatedAt: evaluation.evaluatedAt,
        policyVersion: evaluation.policyVersion,
        missingReasons: evaluation.missingReasons,
        exchangePnlBasis: evaluation.exchangePnlBasis,
      );
      double? removed;
      await tester.pumpWidget(
        MaterialApp(
          home: RiskStressView(
            evaluation: withCustom,
            onRemoveCustomPrice: (price) => removed = price,
          ),
        ),
      );
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -1000));
      await tester.pump();
      final customCard = find.ancestor(
        of: find.textContaining('11.00 USDT'),
        matching: find.byType(Card),
      );
      expect(customCard, findsOneWidget);
      await tester.tap(
        find.descendant(
          of: customCard,
          matching: find.byIcon(Icons.delete_outline),
        ),
      );
      expect(removed, 11);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'GREEN-004 custom price map remains sorted and user text is inert',
    (tester) async {
      final evaluation = riskEvaluation();
      await tester.pumpWidget(
        MaterialApp(
          home: RiskPriceMap(
            currentPrice: evaluation.markPrice,
            levels: const [
              RiskPriceMapLevel(price: 12, labels: ['user zone']),
              RiskPriceMapLevel(price: 6, labels: ['liquidation']),
            ],
          ),
        ),
      );
      await tester.pump();
      final first = tester.getTopLeft(find.text('6.00 USDT')).dy;
      final second = tester.getTopLeft(find.text('12.00 USDT')).dy;
      expect(first, lessThan(second));
      expect(find.textContaining('executable'), findsOneWidget);
    },
  );
}

Widget _editorApp(InMemoryRiskMonitorOwner owner, String episodeKey) {
  return MaterialApp(
    home: Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          RiskPlanEditor(
            episodeKey: episodeKey,
            bridge: RiskMonitorBridge(owner),
            plan: RiskPlan(episodeKey: episodeKey),
            evaluation: owner.currentState.evaluation,
            planEvaluation: owner.currentState.planEvaluation,
          ),
        ],
      ),
    ),
  );
}

Widget _home(InMemoryRiskMonitorOwner owner) {
  return ProviderScope(
    overrides: [
      riskMonitorOwnerProvider.overrideWithValue(owner),
      riskMonitorBridgeProvider.overrideWithValue(RiskMonitorBridge(owner)),
    ],
    child: const MaterialApp(home: PortfolioScreen()),
  );
}
