import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/action_plan.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_events.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_models.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_policy.dart';

import 'fixtures/risk_test_fixtures.dart';

void main() {
  test(
    'RED-003 suppresses duplicate/restart/stale transitions and PnL-like noise',
    () {
      const policy = RiskPolicy();
      const reducer = RiskEventReducer();
      final start = riskTestNow;
      final initial = riskSample(at: start, buffer: 0.50);
      final seeded = reducer.reduce(
        null,
        initial,
        const RiskEventLatch(episodeKey: 'episode-a'),
        policy,
        now: start,
      );
      expect(seeded.events, isEmpty);

      final repeated = reducer.reduce(
        initial,
        initial,
        seeded.latches,
        policy,
        now: start,
      );
      expect(repeated.events, isEmpty);
      final stale = reducer.reduce(
        initial,
        riskSample(
          at: start.add(const Duration(minutes: 1)),
          quality: const RiskQuality.stale(reason: 'expired'),
        ),
        seeded.latches,
        policy,
        now: start.add(const Duration(minutes: 1)),
      );
      expect(stale.events, isEmpty);

      final unknownToKnown = reducer.reduce(
        riskSample(
          at: start.add(const Duration(minutes: 2)),
          state: RiskSeverity.normal,
        ),
        riskSample(
          at: start.add(const Duration(minutes: 3)),
          state: RiskSeverity.normal,
          buffer: 0.5,
          marginRatio: null,
        ),
        seeded.latches.copyWith(
          initialized: true,
          lastObservedAt: start.add(const Duration(minutes: 2)),
          lastSample: riskSample(at: start.add(const Duration(minutes: 2))),
        ),
        policy,
        now: start.add(const Duration(minutes: 3)),
      );
      expect(unknownToKnown.events, isEmpty);

      final partialImprovement = reducer.reduce(
        null,
        riskSample(at: start, state: RiskSeverity.high),
        const RiskEventLatch(episodeKey: 'episode-a'),
        policy,
        now: start,
      );
      final partialStep = reducer.reduce(
        partialImprovement.latches.lastSample,
        riskSample(
          at: start.add(const Duration(seconds: 1)),
          state: RiskSeverity.watch,
          quality: const RiskQuality.partial(reason: 'position incomplete'),
        ),
        partialImprovement.latches,
        policy,
        now: start.add(const Duration(seconds: 1)),
      );
      expect(partialStep.events, isEmpty);
      expect(partialStep.latches.pendingImprovements, isEmpty);
    },
  );

  test(
    'GREEN-003 latches threshold crossings, rearm and confirmed improvement',
    () {
      const policy = RiskPolicy();
      const reducer = RiskEventReducer();
      final start = riskTestNow;
      final seeded = reducer.reduce(
        null,
        riskSample(at: start, buffer: 0.50, marginRatio: 4),
        const RiskEventLatch(episodeKey: 'episode-a'),
        policy,
        now: start,
      );
      final entered = reducer.reduce(
        seeded.latches.lastSample,
        riskSample(
          at: start.add(const Duration(minutes: 1)),
          buffer: 0.44,
          marginRatio: 4,
        ),
        seeded.latches,
        policy,
        now: start.add(const Duration(minutes: 1)),
      );
      expect(entered.events.length, 1);
      expect(entered.events.single.kind, RiskEventKind.bufferBoundary);

      final watchBoundary = reducer.reduce(
        seeded.latches.lastSample,
        riskSample(
          at: start.add(const Duration(seconds: 30)),
          buffer: 0.45,
          marginRatio: 4,
        ),
        seeded.latches,
        policy,
        now: start.add(const Duration(seconds: 30)),
      );
      expect(watchBoundary.events.single.kind, RiskEventKind.bufferBoundary);

      final highSeed = reducer.reduce(
        null,
        riskSample(at: start, buffer: 0.40, marginRatio: 4),
        const RiskEventLatch(episodeKey: 'episode-a'),
        policy,
        now: start,
      );
      final highBoundary = reducer.reduce(
        highSeed.latches.lastSample,
        riskSample(
          at: start.add(const Duration(seconds: 31)),
          buffer: 0.30,
          marginRatio: 4,
        ),
        highSeed.latches,
        policy,
        now: start.add(const Duration(seconds: 31)),
      );
      expect(highBoundary.events, isEmpty);

      final safeFirst = reducer.reduce(
        entered.latches.lastSample,
        riskSample(
          at: start.add(const Duration(minutes: 2)),
          buffer: 0.46,
          marginRatio: 4,
        ),
        entered.latches,
        policy,
        now: start.add(const Duration(minutes: 2)),
      );
      expect(safeFirst.events, isEmpty);
      final safeSecond = reducer.reduce(
        safeFirst.latches.lastSample,
        riskSample(
          at: start.add(const Duration(minutes: 3)),
          buffer: 0.46,
          marginRatio: 4,
        ),
        safeFirst.latches,
        policy,
        now: start.add(const Duration(minutes: 3)),
      );
      expect(safeSecond.events, isEmpty);
      final reentered = reducer.reduce(
        safeSecond.latches.lastSample,
        riskSample(
          at: start.add(const Duration(minutes: 4)),
          buffer: 0.44,
          marginRatio: 4,
        ),
        safeSecond.latches,
        policy,
        now: start.add(const Duration(minutes: 4)),
      );
      expect(reentered.events.length, 1);

      final aggregated = reducer.reduce(
        seeded.latches.lastSample,
        riskSample(
          at: start.add(const Duration(minutes: 4, seconds: 30)),
          buffer: 0.44,
          marginRatio: 4,
          activeFactorIds: <String>['new-factor'],
        ),
        seeded.latches,
        policy,
        now: start.add(const Duration(minutes: 4, seconds: 30)),
      );
      expect(aggregated.events, hasLength(1));
      expect(aggregated.events.single.contributions, hasLength(2));

      final marginEntered = reducer.reduce(
        safeSecond.latches.lastSample,
        riskSample(
          at: start.add(const Duration(minutes: 5)),
          buffer: 0.50,
          marginRatio: 3,
        ),
        safeSecond.latches,
        policy,
        now: start.add(const Duration(minutes: 5)),
      );
      expect(
        marginEntered.events.any(
          (event) => event.kind == RiskEventKind.marginBoundary,
        ),
        isTrue,
      );

      final high = reducer.reduce(
        null,
        riskSample(
          at: start,
          state: RiskSeverity.high,
          buffer: 0.50,
          marginRatio: 4,
        ),
        const RiskEventLatch(episodeKey: 'episode-a'),
        policy,
        now: start,
      );
      final firstImprovement = reducer.reduce(
        high.latches.lastSample,
        riskSample(
          at: start.add(const Duration(seconds: 1)),
          state: RiskSeverity.watch,
          buffer: 0.50,
          marginRatio: 4,
        ),
        high.latches,
        policy,
        now: start.add(const Duration(seconds: 1)),
      );
      expect(firstImprovement.events, isEmpty);
      final confirmed = reducer.reduce(
        firstImprovement.latches.lastSample,
        riskSample(
          at: start.add(const Duration(seconds: 31)),
          state: RiskSeverity.watch,
          buffer: 0.50,
          marginRatio: 4,
        ),
        firstImprovement.latches,
        policy,
        now: start.add(const Duration(seconds: 31)),
      );
      expect(confirmed.events.single.kind, RiskEventKind.stateChange);
      expect(confirmed.events.single.message, contains('improvement'));
    },
  );

  test(
    'GREEN-003 applies zone hysteresis, verified-interest materiality and reconnect',
    () {
      const policy = RiskPolicy();
      const reducer = RiskEventReducer();
      final zone = riskZone();
      RiskPlanEvaluation zones(RiskRuleState state, double mark) =>
          RiskPlanEvaluation(
            rules: const <RiskRuleEvaluation>[],
            zones: <RiskZoneEvaluation>[
              RiskZoneEvaluation(zone: zone, state: state, markPrice: mark),
            ],
            evaluatedAt: riskTestNow,
          );
      final start = riskTestNow;
      final seeded = reducer.reduce(
        null,
        riskSample(at: start, markPrice: 9.5, buffer: 0.50),
        const RiskEventLatch(episodeKey: 'episode-a'),
        policy,
        currentPlan: zones(RiskRuleState.active, 9.5),
        now: start,
      );
      final nearExit = reducer.reduce(
        seeded.latches.lastSample,
        riskSample(
          at: start.add(const Duration(minutes: 1)),
          markPrice: 8.99,
          buffer: 0.50,
        ),
        seeded.latches,
        policy,
        previousPlan: zones(RiskRuleState.active, 9.5),
        currentPlan: zones(RiskRuleState.inactive, 8.99),
        now: start.add(const Duration(minutes: 1)),
      );
      final immediateReentry = reducer.reduce(
        nearExit.latches.lastSample,
        riskSample(
          at: start.add(const Duration(minutes: 2)),
          markPrice: 9.5,
          buffer: 0.50,
        ),
        nearExit.latches,
        policy,
        previousPlan: zones(RiskRuleState.inactive, 8.99),
        currentPlan: zones(RiskRuleState.active, 9.5),
        now: start.add(const Duration(minutes: 2)),
      );
      expect(immediateReentry.events, isEmpty);

      final exitFirst = reducer.reduce(
        immediateReentry.latches.lastSample,
        riskSample(
          at: start.add(const Duration(minutes: 3)),
          markPrice: 8.9,
          buffer: 0.50,
        ),
        immediateReentry.latches,
        policy,
        previousPlan: zones(RiskRuleState.active, 9.5),
        currentPlan: zones(RiskRuleState.inactive, 8.9),
        now: start.add(const Duration(minutes: 3)),
      );
      final exitSecond = reducer.reduce(
        exitFirst.latches.lastSample,
        riskSample(
          at: start.add(const Duration(minutes: 4)),
          markPrice: 8.9,
          buffer: 0.50,
        ),
        exitFirst.latches,
        policy,
        previousPlan: zones(RiskRuleState.inactive, 8.9),
        currentPlan: zones(RiskRuleState.inactive, 8.9),
        now: start.add(const Duration(minutes: 4)),
      );
      final zoneReentry = reducer.reduce(
        exitSecond.latches.lastSample,
        riskSample(
          at: start.add(const Duration(minutes: 5)),
          markPrice: 9.5,
          buffer: 0.50,
        ),
        exitSecond.latches,
        policy,
        previousPlan: zones(RiskRuleState.inactive, 8.9),
        currentPlan: zones(RiskRuleState.active, 9.5),
        now: start.add(const Duration(minutes: 5)),
      );
      expect(
        zoneReentry.events.any(
          (event) => event.kind == RiskEventKind.zoneEntry,
        ),
        isTrue,
      );

      final interestStart = reducer.reduce(
        null,
        riskSample(at: start, buffer: 0.50, trueExit: 10),
        const RiskEventLatch(episodeKey: 'episode-a'),
        policy,
        now: start,
      );
      final priceOnly = reducer.reduce(
        interestStart.latches.lastSample,
        riskSample(
          at: start.add(const Duration(hours: 1)),
          buffer: 0.50,
          trueExit: 10,
          markPrice: 11,
        ),
        interestStart.latches,
        policy,
        now: start.add(const Duration(hours: 1)),
      );
      expect(
        priceOnly.events.where(
          (event) => event.kind == RiskEventKind.interestChange,
        ),
        isEmpty,
      );
      final interest = reducer.reduce(
        priceOnly.latches.lastSample,
        riskSample(
          at: start.add(const Duration(hours: 24)),
          buffer: 0.50,
          trueExit: 10.03,
        ),
        priceOnly.latches,
        policy,
        now: start.add(const Duration(hours: 24)),
      );
      expect(
        interest.events
            .where((event) => event.kind == RiskEventKind.interestChange)
            .length,
        1,
      );

      final reconnect = reducer.reduce(
        interest.latches.lastSample,
        riskSample(
          at: start.add(const Duration(hours: 25)),
          state: RiskSeverity.watch,
          buffer: 0.44,
        ),
        interest.latches,
        policy,
        now: start.add(const Duration(hours: 25)),
      );
      expect(
        reconnect.events
            .where((event) => event.kind == RiskEventKind.reconnect)
            .length,
        1,
      );
    },
  );

  test('GREEN-003 applies exact threshold and user-rule rearm margins', () {
    const policy = RiskPolicy();
    const reducer = RiskEventReducer();
    final start = riskTestNow;
    RiskEventReduction thresholdSeed({
      required double buffer,
      required double leverage,
      required double marginRatio,
    }) => reducer.reduce(
      null,
      riskSample(
        at: start,
        buffer: buffer,
        leverage: leverage,
        marginRatio: marginRatio,
      ),
      const RiskEventLatch(episodeKey: 'episode-a'),
      policy,
      now: start,
    );

    final bufferSeed = thresholdSeed(buffer: 0.50, leverage: 2, marginRatio: 4);
    final bufferEntered = reducer.reduce(
      bufferSeed.latches.lastSample,
      riskSample(
        at: start.add(const Duration(seconds: 1)),
        buffer: 0.44,
        leverage: 2,
        marginRatio: 4,
      ),
      bufferSeed.latches,
      policy,
      now: start.add(const Duration(seconds: 1)),
    );
    expect(bufferEntered.events.single.kind, RiskEventKind.bufferBoundary);
    final bufferFirstSafe = reducer.reduce(
      bufferEntered.latches.lastSample,
      riskSample(
        at: start.add(const Duration(seconds: 2)),
        buffer: 0.46,
        leverage: 2,
        marginRatio: 4,
      ),
      bufferEntered.latches,
      policy,
      now: start.add(const Duration(seconds: 2)),
    );
    final bufferInsideMargin = reducer.reduce(
      bufferFirstSafe.latches.lastSample,
      riskSample(
        at: start.add(const Duration(seconds: 3)),
        buffer: 0.459,
        leverage: 2,
        marginRatio: 4,
      ),
      bufferFirstSafe.latches,
      policy,
      now: start.add(const Duration(seconds: 3)),
    );
    expect(bufferInsideMargin.latches.rearmSince, isEmpty);
    final bufferSafeAgain = reducer.reduce(
      bufferInsideMargin.latches.lastSample,
      riskSample(
        at: start.add(const Duration(seconds: 4)),
        buffer: 0.46,
        leverage: 2,
        marginRatio: 4,
      ),
      bufferInsideMargin.latches,
      policy,
      now: start.add(const Duration(seconds: 4)),
    );
    final bufferRearmed = reducer.reduce(
      bufferSafeAgain.latches.lastSample,
      riskSample(
        at: start.add(const Duration(seconds: 34)),
        buffer: 0.46,
        leverage: 2,
        marginRatio: 4,
      ),
      bufferSafeAgain.latches,
      policy,
      now: start.add(const Duration(seconds: 34)),
    );
    expect(bufferRearmed.latches.activeFactors, isNot(contains('buffer-0.45')));
    expect(
      reducer
          .reduce(
            bufferRearmed.latches.lastSample,
            riskSample(
              at: start.add(const Duration(seconds: 35)),
              buffer: 0.44,
              leverage: 2,
              marginRatio: 4,
            ),
            bufferRearmed.latches,
            policy,
            now: start.add(const Duration(seconds: 35)),
          )
          .events
          .single
          .kind,
      RiskEventKind.bufferBoundary,
    );

    final leverageSeed = thresholdSeed(
      buffer: 0.50,
      leverage: 2.5,
      marginRatio: 4,
    );
    final leverageEntered = reducer.reduce(
      leverageSeed.latches.lastSample,
      riskSample(
        at: start.add(const Duration(seconds: 1)),
        buffer: 0.50,
        leverage: 3,
        marginRatio: 4,
      ),
      leverageSeed.latches,
      policy,
      now: start.add(const Duration(seconds: 1)),
    );
    expect(leverageEntered.events.single.kind, RiskEventKind.leverageBoundary);
    final leverageInsideMargin = reducer.reduce(
      leverageEntered.latches.lastSample,
      riskSample(
        at: start.add(const Duration(seconds: 2)),
        buffer: 0.50,
        leverage: 2.81,
        marginRatio: 4,
      ),
      leverageEntered.latches,
      policy,
      now: start.add(const Duration(seconds: 2)),
    );
    expect(leverageInsideMargin.latches.rearmSince, isEmpty);
    final leverageFirstSafe = reducer.reduce(
      leverageInsideMargin.latches.lastSample,
      riskSample(
        at: start.add(const Duration(seconds: 3)),
        buffer: 0.50,
        leverage: 2.8,
        marginRatio: 4,
      ),
      leverageInsideMargin.latches,
      policy,
      now: start.add(const Duration(seconds: 3)),
    );
    final leverageRearmed = reducer.reduce(
      leverageFirstSafe.latches.lastSample,
      riskSample(
        at: start.add(const Duration(seconds: 33)),
        buffer: 0.50,
        leverage: 2.8,
        marginRatio: 4,
      ),
      leverageFirstSafe.latches,
      policy,
      now: start.add(const Duration(seconds: 33)),
    );
    expect(
      leverageRearmed.latches.activeFactors,
      isNot(contains('leverage-3.0')),
    );
    expect(
      reducer
          .reduce(
            leverageRearmed.latches.lastSample,
            riskSample(
              at: start.add(const Duration(seconds: 34)),
              buffer: 0.50,
              leverage: 3,
              marginRatio: 4,
            ),
            leverageRearmed.latches,
            policy,
            now: start.add(const Duration(seconds: 34)),
          )
          .events
          .single
          .kind,
      RiskEventKind.leverageBoundary,
    );

    final marginSeed = thresholdSeed(buffer: 0.50, leverage: 2, marginRatio: 4);
    final marginEntered = reducer.reduce(
      marginSeed.latches.lastSample,
      riskSample(
        at: start.add(const Duration(seconds: 1)),
        buffer: 0.50,
        leverage: 2,
        marginRatio: 3,
      ),
      marginSeed.latches,
      policy,
      now: start.add(const Duration(seconds: 1)),
    );
    expect(marginEntered.events.single.kind, RiskEventKind.marginBoundary);
    final marginInsideMargin = reducer.reduce(
      marginEntered.latches.lastSample,
      riskSample(
        at: start.add(const Duration(seconds: 2)),
        buffer: 0.50,
        leverage: 2,
        marginRatio: 3.09,
      ),
      marginEntered.latches,
      policy,
      now: start.add(const Duration(seconds: 2)),
    );
    expect(marginInsideMargin.latches.rearmSince, isEmpty);
    final marginFirstSafe = reducer.reduce(
      marginInsideMargin.latches.lastSample,
      riskSample(
        at: start.add(const Duration(seconds: 3)),
        buffer: 0.50,
        leverage: 2,
        marginRatio: 3.10,
      ),
      marginInsideMargin.latches,
      policy,
      now: start.add(const Duration(seconds: 3)),
    );
    final marginRearmed = reducer.reduce(
      marginFirstSafe.latches.lastSample,
      riskSample(
        at: start.add(const Duration(seconds: 33)),
        buffer: 0.50,
        leverage: 2,
        marginRatio: 3.10,
      ),
      marginFirstSafe.latches,
      policy,
      now: start.add(const Duration(seconds: 33)),
    );
    expect(marginRearmed.latches.activeFactors, isNot(contains('margin-3.0')));
    expect(
      reducer
          .reduce(
            marginRearmed.latches.lastSample,
            riskSample(
              at: start.add(const Duration(seconds: 34)),
              buffer: 0.50,
              leverage: 2,
              marginRatio: 3,
            ),
            marginRearmed.latches,
            policy,
            now: start.add(const Duration(seconds: 34)),
          )
          .events
          .single
          .kind,
      RiskEventKind.marginBoundary,
    );

    RiskPlanEvaluation plan(
      RiskRule rule,
      RiskRuleState state,
      double value, {
      double? referenceValue,
    }) => RiskPlanEvaluation(
      rules: <RiskRuleEvaluation>[
        RiskRuleEvaluation(
          rule: rule,
          state: state,
          value: value,
          referenceValue: referenceValue,
        ),
      ],
      evaluatedAt: start,
    );

    void verifyRuleRearm({
      required RiskRule rule,
      required double activeValue,
      required double safeValue,
      required double insideValue,
      double? referenceValue,
    }) {
      final seed = reducer.reduce(
        null,
        riskSample(at: start, markPrice: 10),
        const RiskEventLatch(episodeKey: 'episode-a'),
        policy,
        currentPlan: plan(
          rule,
          RiskRuleState.active,
          activeValue,
          referenceValue: referenceValue,
        ),
        now: start,
      );
      final firstSafe = reducer.reduce(
        seed.latches.lastSample,
        riskSample(at: start.add(const Duration(seconds: 1)), markPrice: 10),
        seed.latches,
        policy,
        previousPlan: plan(
          rule,
          RiskRuleState.active,
          activeValue,
          referenceValue: referenceValue,
        ),
        currentPlan: plan(
          rule,
          RiskRuleState.inactive,
          safeValue,
          referenceValue: referenceValue,
        ),
        now: start.add(const Duration(seconds: 1)),
      );
      expect(firstSafe.events, isEmpty);
      final inside = reducer.reduce(
        firstSafe.latches.lastSample,
        riskSample(at: start.add(const Duration(seconds: 2)), markPrice: 10),
        firstSafe.latches,
        policy,
        previousPlan: plan(
          rule,
          RiskRuleState.inactive,
          safeValue,
          referenceValue: referenceValue,
        ),
        currentPlan: plan(
          rule,
          RiskRuleState.inactive,
          insideValue,
          referenceValue: referenceValue,
        ),
        now: start.add(const Duration(seconds: 2)),
      );
      expect(inside.latches.rearmSince, isEmpty);
      final safeAgain = reducer.reduce(
        inside.latches.lastSample,
        riskSample(at: start.add(const Duration(seconds: 3)), markPrice: 10),
        inside.latches,
        policy,
        previousPlan: plan(
          rule,
          RiskRuleState.inactive,
          insideValue,
          referenceValue: referenceValue,
        ),
        currentPlan: plan(
          rule,
          RiskRuleState.inactive,
          safeValue,
          referenceValue: referenceValue,
        ),
        now: start.add(const Duration(seconds: 3)),
      );
      final rearmed = reducer.reduce(
        safeAgain.latches.lastSample,
        riskSample(at: start.add(const Duration(seconds: 33)), markPrice: 10),
        safeAgain.latches,
        policy,
        previousPlan: plan(
          rule,
          RiskRuleState.inactive,
          safeValue,
          referenceValue: referenceValue,
        ),
        currentPlan: plan(
          rule,
          RiskRuleState.inactive,
          safeValue,
          referenceValue: referenceValue,
        ),
        now: start.add(const Duration(seconds: 33)),
      );
      expect(rearmed.latches.activeFactors, isNot(contains('rule:${rule.id}')));
      final reentered = reducer.reduce(
        rearmed.latches.lastSample,
        riskSample(at: start.add(const Duration(seconds: 34)), markPrice: 10),
        rearmed.latches,
        policy,
        previousPlan: plan(
          rule,
          RiskRuleState.inactive,
          safeValue,
          referenceValue: referenceValue,
        ),
        currentPlan: plan(
          rule,
          RiskRuleState.active,
          activeValue,
          referenceValue: referenceValue,
        ),
        now: start.add(const Duration(seconds: 34)),
      );
      expect(reentered.events.single.kind, RiskEventKind.ruleEntry);
    }

    void verifyInclusiveRangeRearm({
      required String id,
      required RiskPlanMetric metric,
      required double lower,
      required double upper,
      required double activeValue,
      required double lowerSafe,
      required double lowerInside,
      required double upperSafe,
      required double upperInside,
    }) {
      verifyRuleRearm(
        rule: riskRule(
          id: '$id-lower',
          metric: metric,
          comparison: RiskPlanComparison.betweenInclusive,
          threshold: lower,
          upperThreshold: upper,
        ),
        activeValue: activeValue,
        safeValue: lowerSafe,
        insideValue: lowerInside,
      );
      verifyRuleRearm(
        rule: riskRule(
          id: '$id-upper',
          metric: metric,
          comparison: RiskPlanComparison.betweenInclusive,
          threshold: lower,
          upperThreshold: upper,
        ),
        activeValue: activeValue,
        safeValue: upperSafe,
        insideValue: upperInside,
      );
    }

    // These are user-authored rules, so they exercise the same reducer path
    // used by the plan editor rather than the built-in policy boundaries.
    verifyRuleRearm(
      rule: riskRule(
        id: 'user-buffer-less',
        metric: RiskPlanMetric.buffer,
        comparison: RiskPlanComparison.lessThan,
        threshold: 0.40,
      ),
      activeValue: 0.39,
      safeValue: 0.41,
      insideValue: 0.409,
    );
    verifyRuleRearm(
      rule: riskRule(
        id: 'user-buffer-less-inclusive',
        metric: RiskPlanMetric.buffer,
        comparison: RiskPlanComparison.lessThanOrEqual,
        threshold: 0.40,
      ),
      activeValue: 0.40,
      safeValue: 0.41,
      insideValue: 0.409,
    );
    verifyRuleRearm(
      rule: riskRule(
        id: 'user-buffer-greater',
        metric: RiskPlanMetric.buffer,
        comparison: RiskPlanComparison.greaterThan,
        threshold: 0.40,
      ),
      activeValue: 0.41,
      safeValue: 0.39,
      insideValue: 0.391,
    );
    verifyRuleRearm(
      rule: riskRule(
        id: 'user-buffer-greater-inclusive',
        metric: RiskPlanMetric.buffer,
        comparison: RiskPlanComparison.greaterThanOrEqual,
        threshold: 0.40,
      ),
      activeValue: 0.40,
      safeValue: 0.39,
      insideValue: 0.391,
    );
    verifyRuleRearm(
      rule: riskRule(
        id: 'user-leverage-less',
        metric: RiskPlanMetric.effectiveLeverage,
        comparison: RiskPlanComparison.lessThan,
        threshold: 3,
      ),
      activeValue: 2.9,
      safeValue: 3.2,
      insideValue: 3.19,
    );
    verifyRuleRearm(
      rule: riskRule(
        id: 'user-leverage-less-inclusive',
        metric: RiskPlanMetric.effectiveLeverage,
        comparison: RiskPlanComparison.lessThanOrEqual,
        threshold: 3,
      ),
      activeValue: 3,
      safeValue: 3.2,
      insideValue: 3.19,
    );
    verifyRuleRearm(
      rule: riskRule(
        id: 'user-leverage-greater',
        metric: RiskPlanMetric.effectiveLeverage,
        comparison: RiskPlanComparison.greaterThan,
        threshold: 3,
      ),
      activeValue: 3.1,
      safeValue: 2.8,
      insideValue: 2.81,
    );
    verifyRuleRearm(
      rule: riskRule(
        id: 'user-leverage-greater-inclusive',
        metric: RiskPlanMetric.effectiveLeverage,
        comparison: RiskPlanComparison.greaterThanOrEqual,
        threshold: 3,
      ),
      activeValue: 3,
      safeValue: 2.8,
      insideValue: 2.81,
    );

    verifyInclusiveRangeRearm(
      id: 'buffer-range',
      metric: RiskPlanMetric.buffer,
      lower: 0.40,
      upper: 0.50,
      activeValue: 0.45,
      lowerSafe: 0.39,
      lowerInside: 0.391,
      upperSafe: 0.51,
      upperInside: 0.509,
    );
    verifyInclusiveRangeRearm(
      id: 'leverage-range',
      metric: RiskPlanMetric.effectiveLeverage,
      lower: 2,
      upper: 3,
      activeValue: 2.5,
      lowerSafe: 1.8,
      lowerInside: 1.81,
      upperSafe: 3.2,
      upperInside: 3.19,
    );
    verifyInclusiveRangeRearm(
      id: 'debt-range',
      metric: RiskPlanMetric.totalDebt,
      lower: 100,
      upper: 110,
      activeValue: 105,
      lowerSafe: 99,
      lowerInside: 99.01,
      upperSafe: 111.1,
      upperInside: 111.099,
    );
    verifyInclusiveRangeRearm(
      id: 'holding-cost-range',
      metric: RiskPlanMetric.dailyHoldingCost,
      lower: 10,
      upper: 20,
      activeValue: 15,
      lowerSafe: 9.9,
      lowerInside: 9.901,
      upperSafe: 20.2,
      upperInside: 20.199,
    );

    verifyRuleRearm(
      rule: riskRule(
        id: 'mark-less',
        metric: RiskPlanMetric.markPrice,
        comparison: RiskPlanComparison.lessThan,
        threshold: 100,
      ),
      activeValue: 99,
      safeValue: 100.5,
      insideValue: 100.499,
    );
    verifyRuleRearm(
      rule: riskRule(
        id: 'mark-less-inclusive',
        metric: RiskPlanMetric.markPrice,
        comparison: RiskPlanComparison.lessThanOrEqual,
        threshold: 100,
      ),
      activeValue: 100,
      safeValue: 100.5,
      insideValue: 100.499,
    );
    verifyRuleRearm(
      rule: riskRule(
        id: 'mark-greater',
        metric: RiskPlanMetric.markPrice,
        comparison: RiskPlanComparison.greaterThan,
        threshold: 100,
      ),
      activeValue: 101,
      safeValue: 99.5,
      insideValue: 99.501,
    );
    verifyRuleRearm(
      rule: riskRule(
        id: 'mark-greater-inclusive',
        metric: RiskPlanMetric.markPrice,
        comparison: RiskPlanComparison.greaterThanOrEqual,
        threshold: 100,
      ),
      activeValue: 100,
      safeValue: 99.5,
      insideValue: 99.501,
    );
    verifyRuleRearm(
      rule: riskRule(
        id: 'mark-range-lower',
        metric: RiskPlanMetric.markPrice,
        comparison: RiskPlanComparison.betweenInclusive,
        threshold: 100,
        upperThreshold: 110,
      ),
      activeValue: 105,
      safeValue: 99.5,
      insideValue: 99.501,
    );
    verifyRuleRearm(
      rule: riskRule(
        id: 'mark-range-upper',
        metric: RiskPlanMetric.markPrice,
        comparison: RiskPlanComparison.betweenInclusive,
        threshold: 100,
        upperThreshold: 110,
      ),
      activeValue: 105,
      safeValue: 110.55,
      insideValue: 110.549,
    );
    verifyRuleRearm(
      rule: riskRule(
        id: 'dynamic-less',
        metric: RiskPlanMetric.priceVsTrueExit,
        comparison: RiskPlanComparison.lessThan,
        threshold: null,
      ),
      activeValue: 99,
      safeValue: 100.5,
      insideValue: 100.499,
      referenceValue: 100,
    );
    verifyRuleRearm(
      rule: riskRule(
        id: 'dynamic-greater',
        metric: RiskPlanMetric.priceVsTrueExit,
        comparison: RiskPlanComparison.greaterThan,
        threshold: null,
      ),
      activeValue: 101,
      safeValue: 99.5,
      insideValue: 99.501,
      referenceValue: 100,
    );
    verifyRuleRearm(
      rule: riskRule(
        id: 'debt-less',
        metric: RiskPlanMetric.totalDebt,
        comparison: RiskPlanComparison.lessThan,
        threshold: 100,
      ),
      activeValue: 99,
      safeValue: 101,
      insideValue: 100.99,
    );
    verifyRuleRearm(
      rule: riskRule(
        id: 'debt-greater',
        metric: RiskPlanMetric.totalDebt,
        comparison: RiskPlanComparison.greaterThan,
        threshold: 100,
      ),
      activeValue: 101,
      safeValue: 99,
      insideValue: 99.01,
    );
    verifyRuleRearm(
      rule: riskRule(
        id: 'debt-less-inclusive',
        metric: RiskPlanMetric.totalDebt,
        comparison: RiskPlanComparison.lessThanOrEqual,
        threshold: 100,
      ),
      activeValue: 100,
      safeValue: 101,
      insideValue: 100.99,
    );
    verifyRuleRearm(
      rule: riskRule(
        id: 'debt-greater-inclusive',
        metric: RiskPlanMetric.totalDebt,
        comparison: RiskPlanComparison.greaterThanOrEqual,
        threshold: 100,
      ),
      activeValue: 100,
      safeValue: 99,
      insideValue: 99.01,
    );
    verifyRuleRearm(
      rule: riskRule(
        id: 'cost-less',
        metric: RiskPlanMetric.dailyHoldingCost,
        comparison: RiskPlanComparison.lessThan,
        threshold: 10,
      ),
      activeValue: 9,
      safeValue: 10.1,
      insideValue: 10.099,
    );
    verifyRuleRearm(
      rule: riskRule(
        id: 'cost-greater',
        metric: RiskPlanMetric.dailyHoldingCost,
        comparison: RiskPlanComparison.greaterThan,
        threshold: 10,
      ),
      activeValue: 11,
      safeValue: 9.9,
      insideValue: 9.901,
    );
    verifyRuleRearm(
      rule: riskRule(
        id: 'cost-less-inclusive',
        metric: RiskPlanMetric.dailyHoldingCost,
        comparison: RiskPlanComparison.lessThanOrEqual,
        threshold: 10,
      ),
      activeValue: 10,
      safeValue: 10.1,
      insideValue: 10.099,
    );
    verifyRuleRearm(
      rule: riskRule(
        id: 'cost-greater-inclusive',
        metric: RiskPlanMetric.dailyHoldingCost,
        comparison: RiskPlanComparison.greaterThanOrEqual,
        threshold: 10,
      ),
      activeValue: 10,
      safeValue: 9.9,
      insideValue: 9.901,
    );

    void verifyZoneRearm({
      required String id,
      required double safeMark,
      required double insideMark,
    }) {
      final zone = riskZone(id: id, lower: 9, upper: 10, at: start);
      RiskPlanEvaluation zonePlan(RiskRuleState state, double mark) =>
          RiskPlanEvaluation(
            rules: const <RiskRuleEvaluation>[],
            zones: <RiskZoneEvaluation>[
              RiskZoneEvaluation(zone: zone, state: state, markPrice: mark),
            ],
            evaluatedAt: start,
          );
      final seed = reducer.reduce(
        null,
        riskSample(at: start, markPrice: 9.5),
        const RiskEventLatch(episodeKey: 'episode-a'),
        policy,
        currentPlan: zonePlan(RiskRuleState.active, 9.5),
        now: start,
      );
      final firstSafe = reducer.reduce(
        seed.latches.lastSample,
        riskSample(at: start.add(const Duration(seconds: 1)), markPrice: 10),
        seed.latches,
        policy,
        previousPlan: zonePlan(RiskRuleState.active, 9.5),
        currentPlan: zonePlan(RiskRuleState.inactive, safeMark),
        now: start.add(const Duration(seconds: 1)),
      );
      final inside = reducer.reduce(
        firstSafe.latches.lastSample,
        riskSample(at: start.add(const Duration(seconds: 2)), markPrice: 10),
        firstSafe.latches,
        policy,
        previousPlan: zonePlan(RiskRuleState.inactive, safeMark),
        currentPlan: zonePlan(RiskRuleState.inactive, insideMark),
        now: start.add(const Duration(seconds: 2)),
      );
      expect(inside.latches.rearmSince, isEmpty);
      final safeAgain = reducer.reduce(
        inside.latches.lastSample,
        riskSample(at: start.add(const Duration(seconds: 3)), markPrice: 10),
        inside.latches,
        policy,
        previousPlan: zonePlan(RiskRuleState.inactive, insideMark),
        currentPlan: zonePlan(RiskRuleState.inactive, safeMark),
        now: start.add(const Duration(seconds: 3)),
      );
      final rearmed = reducer.reduce(
        safeAgain.latches.lastSample,
        riskSample(at: start.add(const Duration(seconds: 33)), markPrice: 10),
        safeAgain.latches,
        policy,
        previousPlan: zonePlan(RiskRuleState.inactive, safeMark),
        currentPlan: zonePlan(RiskRuleState.inactive, safeMark),
        now: start.add(const Duration(seconds: 33)),
      );
      expect(rearmed.latches.activeFactors, isNot(contains('zone:$id')));
      final reentered = reducer.reduce(
        rearmed.latches.lastSample,
        riskSample(at: start.add(const Duration(seconds: 34)), markPrice: 10),
        rearmed.latches,
        policy,
        previousPlan: zonePlan(RiskRuleState.inactive, safeMark),
        currentPlan: zonePlan(RiskRuleState.active, 9.5),
        now: start.add(const Duration(seconds: 34)),
      );
      expect(reentered.events.single.kind, RiskEventKind.zoneEntry);
    }

    verifyZoneRearm(id: 'zone-rearm', safeMark: 10.05, insideMark: 10.049);
  });

  test(
    'RED-003 treats rule and zone definition edits as configuration events',
    () {
      const policy = RiskPolicy();
      const reducer = RiskEventReducer();
      final start = riskTestNow;
      final rule = riskRule(
        id: 'edited-rule',
        metric: RiskPlanMetric.markPrice,
        threshold: 10,
        comparison: RiskPlanComparison.lessThan,
        title: 'Mark below ten',
        at: start,
      );
      final zone = riskZone(id: 'edited-zone', lower: 9, upper: 10, at: start);
      RiskPlanEvaluation plan(
        RiskRule rule,
        RiskRuleState ruleState,
        double ruleValue,
        RiskZone zone,
        RiskRuleState zoneState,
        double zoneMark,
      ) => RiskPlanEvaluation(
        rules: <RiskRuleEvaluation>[
          RiskRuleEvaluation(rule: rule, state: ruleState, value: ruleValue),
        ],
        zones: <RiskZoneEvaluation>[
          RiskZoneEvaluation(zone: zone, state: zoneState, markPrice: zoneMark),
        ],
        evaluatedAt: start,
      );

      final seeded = reducer.reduce(
        null,
        riskSample(at: start, markPrice: 9.5),
        const RiskEventLatch(episodeKey: 'episode-a'),
        policy,
        currentPlan: plan(
          rule,
          RiskRuleState.active,
          9.5,
          zone,
          RiskRuleState.active,
          9.5,
        ),
        now: start,
      );
      final editedRule = rule.copyWith(
        threshold: 8,
        updatedAt: start.add(const Duration(minutes: 1)),
      );
      final editedZone = riskZone(
        id: zone.id,
        lower: 11,
        upper: 12,
        at: start.add(const Duration(minutes: 1)),
      );
      final edited = reducer.reduce(
        seeded.latches.lastSample,
        riskSample(at: start.add(const Duration(minutes: 1)), markPrice: 9.5),
        seeded.latches,
        policy,
        previousPlan: plan(
          rule,
          RiskRuleState.active,
          9.5,
          zone,
          RiskRuleState.active,
          9.5,
        ),
        currentPlan: plan(
          editedRule,
          RiskRuleState.inactive,
          9.5,
          editedZone,
          RiskRuleState.inactive,
          9.5,
        ),
        now: start.add(const Duration(minutes: 1)),
      );

      expect(edited.events, hasLength(1));
      expect(edited.events.single.kind, RiskEventKind.configurationChange);
      expect(edited.events.single.message, contains('configuration'));
      expect(edited.events.single.contributions, hasLength(1));
      expect(edited.latches.activeFactors, isNot(contains('rule:${rule.id}')));
      expect(edited.latches.activeFactors, isNot(contains('zone:${zone.id}')));
    },
  );

  test(
    'GREEN-003 reseeds an edited definition before a later market crossing',
    () {
      const policy = RiskPolicy();
      const reducer = RiskEventReducer();
      final start = riskTestNow;
      final rule = riskRule(
        id: 'reseed-rule',
        metric: RiskPlanMetric.markPrice,
        threshold: 8,
        comparison: RiskPlanComparison.lessThan,
        title: 'Mark below eight',
        at: start,
      );
      final editedRule = rule.copyWith(
        threshold: 10,
        updatedAt: start.add(const Duration(minutes: 1)),
      );
      RiskPlanEvaluation evaluation(RiskRule value, RiskRuleState state) =>
          RiskPlanEvaluation(
            rules: <RiskRuleEvaluation>[
              RiskRuleEvaluation(rule: value, state: state, value: 9),
            ],
            evaluatedAt: start,
          );
      final seeded = reducer.reduce(
        null,
        riskSample(at: start, markPrice: 9),
        const RiskEventLatch(episodeKey: 'episode-a'),
        policy,
        currentPlan: evaluation(rule, RiskRuleState.inactive),
        now: start,
      );
      final edited = reducer.reduce(
        seeded.latches.lastSample,
        riskSample(at: start.add(const Duration(minutes: 1)), markPrice: 9),
        seeded.latches,
        policy,
        previousPlan: evaluation(rule, RiskRuleState.inactive),
        currentPlan: evaluation(editedRule, RiskRuleState.active),
        now: start.add(const Duration(minutes: 1)),
      );
      expect(edited.events.single.kind, RiskEventKind.configurationChange);
      expect(edited.latches.activeFactors, contains('rule:${rule.id}'));

      final marketCrossing = reducer.reduce(
        edited.latches.lastSample,
        riskSample(at: start.add(const Duration(minutes: 2)), markPrice: 9),
        edited.latches,
        policy,
        previousPlan: evaluation(editedRule, RiskRuleState.inactive),
        currentPlan: evaluation(editedRule, RiskRuleState.active),
        now: start.add(const Duration(minutes: 2)),
      );
      expect(marketCrossing.events, isEmpty);
    },
  );

  test('GREEN-003 confirms component improvements after two fresh samples', () {
    const policy = RiskPolicy();
    const reducer = RiskEventReducer();
    final start = riskTestNow;
    final seeded = reducer.reduce(
      null,
      riskSample(
        at: start,
        positionState: RiskSeverity.high,
        recoveryState: RiskSeverity.high,
      ),
      const RiskEventLatch(episodeKey: 'episode-a'),
      policy,
      now: start,
    );
    final first = reducer.reduce(
      seeded.latches.lastSample,
      riskSample(
        at: start.add(const Duration(seconds: 1)),
        positionState: RiskSeverity.watch,
        recoveryState: RiskSeverity.watch,
      ),
      seeded.latches,
      policy,
      now: start.add(const Duration(seconds: 1)),
    );
    expect(first.events, isEmpty);
    final confirmed = reducer.reduce(
      first.latches.lastSample,
      riskSample(
        at: start.add(const Duration(seconds: 31)),
        positionState: RiskSeverity.watch,
        recoveryState: RiskSeverity.watch,
      ),
      first.latches,
      policy,
      now: start.add(const Duration(seconds: 31)),
    );
    expect(confirmed.events, hasLength(1));
    expect(
      confirmed.events.single.contributions.map(
        (contribution) => contribution.message,
      ),
      contains('Recovery risk improvement confirmed'),
    );
    expect(
      confirmed.events.single.contributions.map(
        (contribution) => contribution.factorId,
      ),
      contains('position-state-improvement'),
    );

    final positionWorsened = reducer.reduce(
      confirmed.latches.lastSample,
      riskSample(
        at: start.add(const Duration(minutes: 1)),
        positionState: RiskSeverity.high,
      ),
      confirmed.latches,
      policy,
      now: start.add(const Duration(minutes: 1)),
    );
    expect(
      positionWorsened.events
          .where((event) => event.kind == RiskEventKind.stateChange)
          .single
          .message,
      contains('Position risk worsened'),
    );
  });
}
