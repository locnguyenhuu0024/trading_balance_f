import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/portfolio/application/risk_monitor_bridge.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/action_plan.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_events.dart';

import 'fixtures/risk_test_fixtures.dart';

void main() {
  test(
    'RED-003 rejects malformed rules, overlapping zones and unknown True Exit',
    () {
      final missingThreshold = riskRule(threshold: null);
      expect(missingThreshold.isValid, isFalse);
      expect(missingThreshold.validate().join(' '), contains('threshold'));

      final overlap = riskPlan(
        zones: <RiskZone>[
          riskZone(id: 'one', lower: 9, upper: 10),
          riskZone(id: 'two', lower: 10, upper: 11),
        ],
      );
      expect(overlap.isValid, isFalse);
      expect(overlap.validate().join(' '), contains('overlap'));

      final unknownTrueExit = const ActionPlanEvaluator().evaluate(<RiskRule>[
        RiskRule(
          id: 'true-exit',
          episodeKey: 'episode-a',
          metric: RiskPlanMetric.priceVsTrueExit,
          comparison: RiskPlanComparison.lessThan,
          title: 'Verified exit',
          createdAt: riskTestNow,
          updatedAt: riskTestNow,
        ),
      ], riskEvaluation(verifiedCosts: false));
      expect(unknownTrueExit.unknownCount, 1);
      expect(unknownTrueExit.inactiveCount, 0);
      expect(
        RiskRule(
          id: 'static-true-exit',
          episodeKey: 'episode-a',
          metric: RiskPlanMetric.priceVsTrueExit,
          comparison: RiskPlanComparison.lessThan,
          threshold: 11,
          title: 'Invalid static exit',
          createdAt: riskTestNow,
          updatedAt: riskTestNow,
        ).isValid,
        isFalse,
      );
      final dynamicRange = RiskRule(
        id: 'dynamic-range-true-exit',
        episodeKey: 'episode-a',
        metric: RiskPlanMetric.priceVsTrueExit,
        comparison: RiskPlanComparison.betweenInclusive,
        title: 'Invalid range exit',
        createdAt: riskTestNow,
        updatedAt: riskTestNow,
      );
      expect(
        dynamicRange.validate(),
        contains('priceVsTrueExit supports only above/below comparisons'),
      );

      for (final metric in <RiskPlanMetric>[
        RiskPlanMetric.totalDebt,
        RiskPlanMetric.dailyHoldingCost,
      ]) {
        RiskRule rule({
          required RiskPlanComparison comparison,
          double? threshold,
          double? upperThreshold,
        }) => RiskRule(
          id: '${metric.name}-${comparison.name}-${threshold ?? 'null'}',
          episodeKey: 'episode-a',
          metric: metric,
          comparison: comparison,
          threshold: threshold,
          upperThreshold: upperThreshold,
          title: 'Positive cost rule',
          createdAt: riskTestNow,
          updatedAt: riskTestNow,
        );

        final scalarZero = rule(
          comparison: RiskPlanComparison.lessThan,
          threshold: 0,
        );
        expect(scalarZero.isValid, isFalse);
        expect(
          scalarZero.validate(),
          contains('Rule thresholds must be finite and positive'),
        );

        final lowerZero = rule(
          comparison: RiskPlanComparison.betweenInclusive,
          threshold: 0,
          upperThreshold: 1,
        );
        expect(lowerZero.isValid, isFalse);
        expect(
          lowerZero.validate(),
          contains('Rule thresholds must be finite and positive'),
        );

        final upperZero = rule(
          comparison: RiskPlanComparison.betweenInclusive,
          threshold: 1,
          upperThreshold: 0,
        );
        expect(upperZero.isValid, isFalse);
        expect(
          upperZero.validate(),
          contains('Rule thresholds must be finite and positive'),
        );
      }
    },
  );

  test(
    'GREEN-003 evaluates, serializes and idempotently forwards a plan',
    () async {
      final evaluation = riskEvaluation();
      final plan = riskPlan(
        rules: <RiskRule>[
          riskRule(
            id: 'buffer-watch',
            comparison: RiskPlanComparison.lessThanOrEqual,
            threshold: 0.40,
          ),
          riskRule(
            id: 'exit',
            metric: RiskPlanMetric.priceVsTrueExit,
            comparison: RiskPlanComparison.lessThan,
            threshold: null,
            title: 'Verified True Exit',
          ),
        ],
        zones: <RiskZone>[riskZone()],
      );
      expect(plan.isValid, isTrue);
      final evaluated = const ActionPlanEvaluator().evaluatePlan(
        plan,
        evaluation,
      );
      expect(evaluated.activeCount, 2);
      expect(evaluated.unknownCount, 0);
      expect(evaluated.byId('exit')?.observedValue, evaluation.markPrice);
      expect(evaluated.byId('exit')?.referenceValue, evaluation.trueExitPrice);
      expect(evaluated.activeZoneCount, 1);

      final restored = RiskPlan.fromJson(plan.toJson());
      expect(restored.episodeKey, plan.episodeKey);
      expect(
        restored.rules.map((rule) => rule.id),
        containsAll(<String>['buffer-watch', 'exit']),
      );
      expect(restored.zones.single.lowerPrice, 9);

      const settings = RiskSettings(
        customStressChanges: <double>[-0.12],
        customStressPrices: <double>[8.75],
        timeZone: 'Asia/Ho_Chi_Minh',
        summaryHour: 8,
      );
      expect(
        RiskSettings.fromJson(settings.toJson()).customStressPrices,
        <double>[8.75],
      );

      final owner = InMemoryRiskMonitorOwner();
      final bridge = RiskMonitorBridge(owner);
      final start = await bridge.start(
        commandId: 'start-1',
        accountHash: 'account-a',
        episodeKey: 'episode-a',
      );
      final duplicate = await bridge.start(
        commandId: 'start-1',
        accountHash: 'account-a',
        episodeKey: 'episode-a',
      );
      expect(start.status, RiskMonitorCommandStatus.accepted);
      expect(duplicate.status, RiskMonitorCommandStatus.accepted);
      expect(duplicate.replayed, isTrue);

      final event = RiskEvent(
        id: 'event-1',
        episodeKey: 'episode-a',
        kind: RiskEventKind.stateChange,
        message: 'state changed',
        createdAt: riskTestNow,
        observedAt: riskTestNow,
      );
      final mutableEvents = <RiskEvent>[event];
      final frozenState = RiskMonitorViewState(events: mutableEvents);
      mutableEvents.clear();
      expect(frozenState.events, hasLength(1));
      expect(
        () => frozenState.events.add(event),
        throwsA(isA<UnsupportedError>()),
      );

      final invalidPlan = await bridge.send(
        RiskMonitorCommand.updatePlan(
          id: 'invalid-plan',
          plan: riskPlan(rules: <RiskRule>[riskRule(threshold: null)]),
        ),
      );
      final invalidReplay = await bridge.send(
        RiskMonitorCommand.updatePlan(id: 'invalid-plan', plan: plan),
      );
      expect(invalidPlan.status, RiskMonitorCommandStatus.rejected);
      expect(invalidReplay.status, RiskMonitorCommandStatus.rejected);
      expect(invalidReplay.replayed, isTrue);

      final update = await bridge.send(
        RiskMonitorCommand.updatePlan(id: 'plan-1', plan: plan),
      );
      final updateDuplicate = await bridge.send(
        RiskMonitorCommand.updatePlan(id: 'plan-1', plan: plan),
      );
      expect(update.accepted, isTrue);
      expect(updateDuplicate.duplicate, isTrue);
      expect(owner.plan?.episodeKey, 'episode-a');
      final settingsUpdate = await bridge.send(
        RiskMonitorCommand.updateSettings(id: 'settings-1', settings: settings),
      );
      final settingsDuplicate = await bridge.send(
        RiskMonitorCommand.updateSettings(id: 'settings-1', settings: settings),
      );
      expect(settingsUpdate.accepted, isTrue);
      expect(settingsDuplicate.duplicate, isTrue);
      expect(owner.settings?.timeZone, 'Asia/Ho_Chi_Minh');
      await owner.dispose();
    },
  );
}
