import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_engine.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_models.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_policy.dart';

void main() {
  final engine = RiskEngine(clock: () => DateTime.utc(2026, 9, 10, 12));

  test('RED-001 invalid mark, zero equity, ambiguous debt and boundaries', () {
    final invalidMark = _f1(markPrice: null);
    final invalidEvaluation = engine.evaluate(
      invalidMark,
      market: const RiskMarketInput(
        state: RiskSeverity.normal,
        complete: true,
        dailyVolatility: 0.1,
      ),
    );
    expect(invalidEvaluation.buffer, isNull);
    expect(invalidEvaluation.partial, isTrue);

    final zeroEquity = _f1().copyWith();
    final zeroPosition = RiskPosition(
      instrumentId: zeroEquity.instrumentId,
      instrumentType: zeroEquity.instrumentType,
      mode: zeroEquity.mode,
      collateralCurrency: zeroEquity.collateralCurrency,
      positionSide: zeroEquity.positionSide,
      positionId: zeroEquity.positionId,
      createdAt: zeroEquity.createdAt,
      baseCurrency: zeroEquity.baseCurrency,
      quoteCurrency: zeroEquity.quoteCurrency,
      positionCurrency: zeroEquity.positionCurrency,
      accountCurrency: zeroEquity.accountCurrency,
      liabilityCurrency: zeroEquity.liabilityCurrency,
      rawQuantity: zeroEquity.rawQuantity,
      quantity: zeroEquity.quantity,
      margin: 0,
      markPrice: zeroEquity.markPrice,
      entryPrice: zeroEquity.entryPrice,
      liquidationPrice: zeroEquity.liquidationPrice,
      unrealizedPnl: 0,
      marginRatio: zeroEquity.marginRatio,
      reportedLiability: zeroEquity.reportedLiability,
      reportedInterest: zeroEquity.reportedInterest,
      entryFeeRate: zeroEquity.entryFeeRate,
      exitFeeRate: zeroEquity.exitFeeRate,
      costAttribution: zeroEquity.costAttribution,
      quality: const RiskQuality.complete(source: 'fixture'),
      source: 'fixture',
    );
    final zeroEvaluation = engine.evaluate(
      zeroPosition,
      market: const RiskMarketInput(
        state: RiskSeverity.normal,
        complete: true,
        dailyVolatility: 0.1,
      ),
    );
    expect(zeroEvaluation.equity, 0);
    expect(zeroEvaluation.effectiveLeverage, isNull);
    expect(zeroEvaluation.positionRisk, RiskSeverity.critical);
    expect(zeroEvaluation.overallRisk, RiskSeverity.critical);

    final ambiguous = _f1(reportedLiability: 1000, reportedInterest: 2);
    final ambiguousEvaluation = engine.evaluate(
      ambiguous,
      market: const RiskMarketInput(
        state: RiskSeverity.normal,
        complete: true,
        dailyVolatility: 0.1,
      ),
    );
    expect(ambiguousEvaluation.debt, 1000);
    expect(ambiguousEvaluation.metrics.principalDebt.value, isNull);
    expect(ambiguousEvaluation.holdingCostPerDay, isNull);

    const policy = RiskPolicy();
    expect(policy.classifyBuffer(0.20), RiskSeverity.high);
    expect(policy.classifyBuffer(0.30), RiskSeverity.watch);
    expect(policy.classifyBuffer(0.45), RiskSeverity.watch);
    expect(policy.classifyBuffer(0.4500001), RiskSeverity.normal);
    expect(policy.classifyLeverage(4), RiskSeverity.high);
    expect(policy.classifyLeverage(6), RiskSeverity.critical);
    expect(policy.classifyMarginRatio(1.10), RiskSeverity.critical);
    expect(policy.classifyMarginRatio(1.50), RiskSeverity.high);
    expect(policy.classifyMarginRatio(3.0), RiskSeverity.watch);

    final f2Stress = engine
        .evaluate(
          _f2(),
          market: const RiskMarketInput(
            state: RiskSeverity.normal,
            complete: true,
            dailyVolatility: 0.1,
          ),
        )
        .stressScenarios
        .firstWhere((scenario) => scenario.percentageChange == -0.10);
    expect(f2Stress.equity, closeTo(150, 1e-9));
    expect(f2Stress.effectiveLeverage, closeTo(6, 1e-9));
    expect(f2Stress.positionState, RiskSeverity.critical);

    final malformedMarketState = engine.evaluate(
      _f1(),
      market: const RiskMarketInput(
        state: RiskSeverity.critical,
        complete: true,
        dailyVolatility: 0.1,
      ),
    );
    expect(malformedMarketState.marketRisk, RiskSeverity.high);

    final gapCoverage = RiskCostCoverage(
      complete: true,
      ledgerComplete: true,
      sizeUnchanged: true,
      positionOpenedAt: DateTime.utc(2026, 9, 1),
      coverageFrom: DateTime.utc(2026, 9, 1),
      coverageTo: DateTime.utc(2026, 9, 9),
      nonOverlapAt: DateTime.utc(2026, 9, 10),
    );
    expect(gapCoverage.hasTimestampedCoverage, isFalse);
    expect(gapCoverage.isVerifiedComplete, isFalse);
    final rejectedFactoryGap = RiskCostCoverage.completeForPosition(
      positionOpenedAt: DateTime.utc(2026, 9, 1),
      coverageFrom: DateTime.utc(2026, 9, 1),
      coverageTo: DateTime.utc(2026, 9, 9),
      nonOverlapAt: DateTime.utc(2026, 9, 10),
    );
    expect(rejectedFactoryGap.complete, isFalse);
    expect(rejectedFactoryGap.isVerifiedComplete, isFalse);
    final gapEvaluation = engine.evaluate(
      _f1().withCostAttribution(
        RiskCostAttribution(
          settledInterest: 0,
          unbilledInterest: 2,
          additionalActualCosts: 0,
          coverage: gapCoverage,
          observedAt: DateTime.utc(2026, 9, 10, 11, 55),
        ),
      ),
      market: const RiskMarketInput(
        state: RiskSeverity.normal,
        complete: true,
        dailyVolatility: 0.1,
      ),
    );
    expect(gapEvaluation.trueExitPrice, isNull);
  });

  test(
    'GREEN-001 evaluates F1, F2, old mode, custom stress and reference size',
    () {
      final evaluation = engine.evaluate(
        _f1(),
        market: const RiskMarketInput(
          state: RiskSeverity.normal,
          complete: true,
          dailyVolatility: 0.1,
          support: 7.5,
          resistance: 12.5,
        ),
        priceLevels: const <RiskPriceLevelInput>[
          RiskPriceLevelInput(price: 7, label: 'Action zone'),
        ],
        customPrices: const <double>[12, 12],
      );
      expect(evaluation.buffer, closeTo(0.4, 1e-12));
      expect(evaluation.effectiveLeverage, closeTo(2, 1e-12));
      expect(
        evaluation.metrics.tradeSensitivityPerPoint.value,
        closeTo(1, 1e-12),
      );
      expect(
        evaluation.metrics.tradeSensitivityPerPercent.value,
        closeTo(10, 1e-12),
      );
      expect(evaluation.equity, closeTo(500, 1e-12));
      expect(evaluation.holdingCostPerDay, closeTo(0.28752, 1e-12));
      expect(evaluation.trueExitPrice, closeTo(11.042042042042042, 1e-12));
      expect(evaluation.actualInterestToday, closeTo(0.25, 1e-12));
      expect(evaluation.knownActualInterestToday, closeTo(0.25, 1e-12));
      expect(evaluation.metrics.knownInterestToday.value, closeTo(0.25, 1e-12));
      expect(
        evaluation.metrics.knownInterestToday.quality.status,
        RiskQualityStatus.complete,
      );
      expect(evaluation.policyVersion, 'risk.v1');
      expect(evaluation.projectedTrueExitPrice, isNotNull);
      expect(
        evaluation.projectedTrueExitPrice!,
        greaterThan(evaluation.trueExitPrice!),
      );
      expect(
        evaluation.metrics.projectedTrueExitPrice.quality.status,
        RiskQualityStatus.partial,
      );
      expect(
        evaluation.metrics.projectedTrueExitPrice.quality.reason,
        contains('fresh for 10 minutes'),
      );
      expect(
        evaluation.recoveryDistance,
        isNot(
          equals(
            evaluation.projectedTrueExitPrice! / evaluation.markPrice! - 1,
          ),
        ),
      );
      final exactFreshProjection = engine.evaluate(
        _f1(),
        now: DateTime.utc(2026, 9, 10, 12, 5),
        market: const RiskMarketInput(
          state: RiskSeverity.normal,
          complete: true,
          dailyVolatility: 0.1,
        ),
      );
      expect(exactFreshProjection.projectedTrueExitPrice, isNotNull);
      final staleProjection = engine.evaluate(
        _f1(),
        now: DateTime.utc(2026, 9, 10, 12, 5, 1),
        market: const RiskMarketInput(
          state: RiskSeverity.normal,
          complete: true,
          dailyVolatility: 0.1,
        ),
      );
      expect(staleProjection.projectedTrueExitPrice, isNull);
      expect(staleProjection.trueExitPrice, closeTo(11.042042042042042, 1e-12));
      expect(
        staleProjection.recoveryDistance,
        closeTo(evaluation.recoveryDistance!, 1e-12),
      );
      final versioned = engine.evaluate(
        _f1(),
        policy: const RiskPolicy(version: 'risk.test.v2'),
        market: const RiskMarketInput(
          state: RiskSeverity.normal,
          complete: true,
          dailyVolatility: 0.1,
        ),
      );
      expect(versioned.policyVersion, 'risk.test.v2');
      expect(evaluation.recoveryDistance, closeTo(0.1042042042042042, 1e-12));
      expect(evaluation.distanceToTrueExit, closeTo(0.1042042042042042, 1e-12));
      expect(_f1().episodeKey, 'fixture-account:position-1:1788220800000');

      final partialCosts = engine.evaluate(
        _f1().withCostAttribution(
          const RiskCostAttribution(
            unbilledInterest: 2,
            coverage: RiskCostCoverage.unknown(),
          ),
        ),
        market: const RiskMarketInput(
          state: RiskSeverity.normal,
          complete: true,
          dailyVolatility: 0.1,
        ),
      );
      expect(partialCosts.trueExitPrice, isNull);
      expect(partialCosts.metrics.knownCostExitPrice.value, isNotNull);
      expect(partialCosts.partial, isTrue);
      expect(
        partialCosts.missingReasons,
        contains('True Exit is unavailable or partial'),
      );

      final partialToday = engine.evaluate(
        _f1().withCostAttribution(
          RiskCostAttribution(
            actualInterestToday: RiskActualInterestToday(
              amount: null,
              knownSubtotal: 0.25,
              windowStart: DateTime.utc(2026, 9, 10),
              windowEnd: DateTime.utc(2026, 9, 10, 12),
              quality: const RiskQuality.partial(
                source: 'fixture-costs',
                reason: 'Local-day coverage is incomplete',
              ),
              observedAt: DateTime.utc(2026, 9, 10, 12),
              source: 'fixture-costs',
            ),
            coverage: const RiskCostCoverage.unknown(),
          ),
        ),
        market: const RiskMarketInput(
          state: RiskSeverity.normal,
          complete: true,
          dailyVolatility: 0.1,
        ),
      );
      expect(partialToday.actualInterestToday, isNull);
      expect(partialToday.knownActualInterestToday, closeTo(0.25, 1e-12));
      expect(
        partialToday.metrics.knownInterestToday.quality.status,
        RiskQualityStatus.partial,
      );

      final minusTen = evaluation.stressScenarios.firstWhere(
        (scenario) => scenario.percentageChange == -0.10,
      );
      expect(minusTen.equity, closeTo(400, 1e-12));
      expect(minusTen.effectiveLeverage, closeTo(2.25, 1e-12));
      expect(minusTen.buffer, closeTo(1 / 3, 1e-12));
      expect(minusTen.positionState, RiskSeverity.watch);
      final minusTwenty = evaluation.stressScenarios.firstWhere(
        (scenario) => scenario.percentageChange == -0.20,
      );
      expect(minusTwenty.equity, closeTo(300, 1e-12));
      expect(minusTwenty.effectiveLeverage, closeTo(8 / 3, 1e-12));
      expect(minusTwenty.buffer, closeTo(0.25, 1e-12));
      expect(minusTwenty.positionState, RiskSeverity.high);
      expect(
        evaluation.stressScenarios.where((scenario) => scenario.price == 12),
        hasLength(1),
      );
      expect(
        evaluation.stressScenarios.where((scenario) => scenario.price == 11),
        hasLength(1),
      );
      expect(
        evaluation.stressScenarios.where((scenario) => scenario.price == 6),
        hasLength(1),
      );
      expect(
        evaluation.stressScenarios.where((scenario) => scenario.price == 7),
        hasLength(1),
      );
      expect(
        evaluation.stressScenarios.every(
          (scenario) => scenario.overallState != null,
        ),
        isTrue,
      );
      expect(
        evaluation.stressScenarios
            .firstWhere((scenario) => scenario.price == 7)
            .label,
        'Action zone',
      );
      expect(
        evaluation.stressScenarios.where(
          (scenario) => scenario.label == 'True Exit',
        ),
        hasLength(1),
      );
      expect(
        evaluation.stressScenarios
            .take(5)
            .map((scenario) => scenario.percentageChange)
            .toList(),
        <double?>[0, -0.05, -0.10, -0.15, -0.20],
      );
      expect(
        evaluation.stressScenarios.every(
          (scenario) => scenario.marginRatio == null,
        ),
        isTrue,
      );
      expect(
        evaluation.priceMap.firstWhere((level) => level.price == 7.5).labels,
        contains('Support'),
      );
      expect(
        evaluation.priceMap.firstWhere((level) => level.price == 12.5).labels,
        contains('Resistance'),
      );
      expect(
        evaluation.stressScenarios.every((scenario) => scenario.partial),
        isTrue,
      );

      final f2 = engine.evaluate(
        _f2(),
        market: const RiskMarketInput(
          state: RiskSeverity.normal,
          complete: true,
          dailyVolatility: 0.1,
        ),
      );
      expect(f2.equity, closeTo(300, 1e-12));
      expect(f2.metrics.equitySensitivityPerPoint.value, closeTo(1.5, 1e-12));
      expect(f2.metrics.tradeSensitivityPerPoint.value, closeTo(1, 1e-12));

      final settledAndUnbilled = engine.evaluate(
        _f1().withCostAttribution(
          RiskCostAttribution(
            settledInterest: 5,
            unbilledInterest: 2,
            additionalActualCosts: 0,
            coverage: RiskCostCoverage.completeForPosition(
              positionOpenedAt: DateTime.utc(2026, 9, 1),
              coverageFrom: DateTime.utc(2026, 9, 1),
              coverageTo: DateTime.utc(2026, 9, 10),
              nonOverlapAt: DateTime.utc(2026, 9, 10),
            ),
          ),
        ),
        market: const RiskMarketInput(
          state: RiskSeverity.normal,
          complete: true,
          dailyVolatility: 0.1,
        ),
      );
      expect(
        settledAndUnbilled.metrics.principalDebt.value,
        closeTo(1198, 1e-12),
      );
      expect(settledAndUnbilled.holdingCostPerDay, closeTo(0.28752, 1e-12));

      final unverifiedCoverage = engine.evaluate(
        _f1().withCostAttribution(
          const RiskCostAttribution(
            settledInterest: 5,
            unbilledInterest: 2,
            additionalActualCosts: 0,
            coverage: RiskCostCoverage(
              complete: true,
              ledgerComplete: true,
              sizeUnchanged: true,
            ),
          ),
        ),
        market: const RiskMarketInput(
          state: RiskSeverity.normal,
          complete: true,
          dailyVolatility: 0.1,
        ),
      );
      expect(unverifiedCoverage.trueExitPrice, isNull);

      final stale = engine.evaluate(
        _f1().copyWith(
          quality: RiskQuality.stale(
            source: 'fixture',
            reason: 'position refresh expired',
            observedAt: DateTime.utc(2026, 9, 1),
            sourceAt: DateTime.utc(2026, 8, 31),
          ),
        ),
        market: const RiskMarketInput(
          state: RiskSeverity.normal,
          complete: true,
          dailyVolatility: 0.1,
        ),
      );
      expect(stale.quality.status, RiskQualityStatus.stale);
      expect(stale.metrics.equity.quality.status, RiskQualityStatus.stale);
      expect(stale.metrics.equity.sourceAt, DateTime.utc(2026, 9, 10));

      for (final reason in evaluation.reasons) {
        expect(reason.factorId, isNotEmpty);
        expect(reason.observedValue, isNotNull);
        expect(reason.threshold, isNotNull);
        expect(reason.window, isNotNull);
        expect(reason.observedAt, isNotNull);
        expect(reason.source, isNotNull);
      }

      final oldMode = _f1(
        mode: RiskAccountMode.oldMode,
        rawQuantity: 110,
        quantity: null,
        margin: 10,
        collateralCurrency: RiskCollateralCurrency.base,
        accountCurrency: 'SUI',
        unrealizedPnl: -2,
        reportedLiability: 1020,
        reportedInterest: 0,
      );
      final oldEvaluation = engine.evaluate(
        oldMode,
        market: const RiskMarketInput(
          state: RiskSeverity.normal,
          complete: true,
          dailyVolatility: 0.1,
        ),
      );
      expect(oldEvaluation.quantity, closeTo(100, 1e-12));
      expect(oldMode.collateralCurrency, RiskCollateralCurrency.base);

      final exactNormal = engine.evaluate(
        _f1().copyWith(
          entryFeeRate: 0,
          exitFeeRate: 0,
          hourlyBorrowRate: 0,
          costAttribution: _verifiedCosts(settledInterest: 0),
        ),
        market: const RiskMarketInput(
          state: RiskSeverity.normal,
          complete: true,
          dailyVolatility: 0.1,
        ),
      );
      final exactWatch = engine.evaluate(
        _f1().copyWith(
          entryFeeRate: 0,
          exitFeeRate: 0,
          hourlyBorrowRate: 0,
          costAttribution: _verifiedCosts(settledInterest: 100),
        ),
        market: const RiskMarketInput(
          state: RiskSeverity.normal,
          complete: true,
          dailyVolatility: 0.1,
        ),
      );
      expect(exactNormal.recoveryDistance, closeTo(0.10, 1e-12));
      expect(exactNormal.recoveryRisk, RiskSeverity.normal);
      expect(exactWatch.recoveryDistance, closeTo(0.20, 1e-12));
      expect(exactWatch.recoveryRisk, RiskSeverity.watch);
      expect(
        const RiskPolicy().classifyRecoveryDistance(0.10),
        RiskSeverity.normal,
      );
      expect(
        const RiskPolicy().classifyRecoveryDistance(0.20),
        RiskSeverity.watch,
      );

      final recoveryHigh = engine.evaluate(
        _f1().copyWith(
          liquidationPrice: 4,
          entryFeeRate: 0,
          exitFeeRate: 0,
          hourlyBorrowRate: 0,
          costAttribution: _verifiedCosts(settledInterest: 200),
        ),
        market: const RiskMarketInput(
          state: RiskSeverity.normal,
          complete: true,
          dailyVolatility: 0.1,
        ),
      );
      expect(recoveryHigh.positionRisk, RiskSeverity.normal);
      expect(recoveryHigh.marketRisk, RiskSeverity.normal);
      expect(recoveryHigh.recoveryDistance, closeTo(0.30, 1e-12));
      expect(recoveryHigh.recoveryRisk, RiskSeverity.high);
      expect(recoveryHigh.overallRisk, RiskSeverity.high);
      expect(
        recoveryHigh.recoveryAssessment.reasons,
        contains(isA<RiskReason>()),
      );

      const onePercentRate = 5 / (1198 * 720);
      const threePercentRate = 15 / (1198 * 720);
      final onePercent = engine.evaluate(
        _f1().copyWith(hourlyBorrowRate: onePercentRate),
        market: const RiskMarketInput(
          state: RiskSeverity.normal,
          complete: true,
          dailyVolatility: 0.1,
        ),
      );
      final threePercent = engine.evaluate(
        _f1().copyWith(hourlyBorrowRate: threePercentRate),
        market: const RiskMarketInput(
          state: RiskSeverity.normal,
          complete: true,
          dailyVolatility: 0.1,
        ),
      );
      expect(onePercent.holdingBurden, closeTo(0.01, 1e-12));
      expect(onePercent.recoveryRisk, RiskSeverity.watch);
      expect(threePercent.holdingBurden, closeTo(0.03, 1e-12));
      expect(threePercent.recoveryRisk, RiskSeverity.high);
      expect(
        const RiskPolicy().classifyHoldingBurden(0.01),
        RiskSeverity.watch,
      );
      expect(const RiskPolicy().classifyHoldingBurden(0.03), RiskSeverity.high);
      expect(
        onePercent.recoveryAssessment.reasons
            .where((reason) => reason.factorId == 'holding-burden')
            .single
            .observedValue,
        closeTo(0.01, 1e-12),
      );

      final positionHigh = engine.evaluate(
        _f1().copyWith(
          marginRatio: 1.5,
          hourlyBorrowRate: 0,
          entryFeeRate: 0,
          exitFeeRate: 0,
          costAttribution: _verifiedCosts(settledInterest: 0),
        ),
        market: const RiskMarketInput(
          state: RiskSeverity.normal,
          complete: true,
          dailyVolatility: 0.1,
        ),
      );
      final marketHigh = engine.evaluate(
        _f1().copyWith(
          hourlyBorrowRate: 0,
          entryFeeRate: 0,
          exitFeeRate: 0,
          costAttribution: _verifiedCosts(settledInterest: 0),
        ),
        market: const RiskMarketInput(
          state: RiskSeverity.high,
          complete: true,
          dailyVolatility: 0.1,
        ),
      );
      expect(positionHigh.positionRisk, RiskSeverity.high);
      expect(positionHigh.recoveryRisk, RiskSeverity.normal);
      expect(positionHigh.overallRisk, RiskSeverity.high);
      expect(marketHigh.positionRisk, RiskSeverity.watch);
      expect(marketHigh.marketRisk, RiskSeverity.high);
      expect(marketHigh.recoveryRisk, RiskSeverity.normal);
      expect(marketHigh.overallRisk, RiskSeverity.high);
      expect(threePercent.positionRisk, RiskSeverity.watch);
      expect(threePercent.marketRisk, RiskSeverity.normal);
      expect(threePercent.overallRisk, RiskSeverity.high);

      final changedReasons = engine
          .evaluate(
            _f1().copyWith(marginRatio: 1),
            market: const RiskMarketInput(
              state: RiskSeverity.normal,
              complete: true,
              dailyVolatility: 0.1,
            ),
          )
          .reasons;
      expect(
        changedReasons.map((reason) => reason.message),
        isNot(equals(evaluation.reasons.map((reason) => reason.message))),
      );
      expect(
        changedReasons.any(
          (reason) =>
              reason.factorId == 'margin-ratio' && reason.observedValue == 1,
        ),
        isTrue,
      );
      expect(
        changedReasons
            .where((reason) => reason.factorId == 'margin-ratio')
            .single
            .severity,
        RiskSeverity.critical,
      );

      final reference = engine.evaluate(
        _f1(rawQuantity: 5277.5681, quantity: 5277.5681),
        market: const RiskMarketInput(
          state: RiskSeverity.normal,
          complete: true,
          dailyVolatility: 0.1,
        ),
      );
      expect(
        reference.metrics.tradeSensitivityPerPoint.value,
        closeTo(52.775681, 1e-12),
      );
    },
  );
}

RiskPosition _f1({
  RiskAccountMode mode = RiskAccountMode.newMode,
  double rawQuantity = 100,
  double? quantity = 100,
  double? markPrice = 10,
  double margin = 700,
  double? reportedLiability = 1198,
  double? reportedInterest = 2,
  RiskCollateralCurrency collateralCurrency = RiskCollateralCurrency.quote,
  String accountCurrency = 'USDT',
  double unrealizedPnl = -200,
}) {
  return RiskPosition(
    instrumentId: 'SUI-USDT',
    instrumentType: 'MARGIN',
    mode: mode,
    collateralCurrency: collateralCurrency,
    positionSide: 'net',
    accountNamespace: 'fixture-account',
    positionId: 'position-1',
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 10),
    observedAt: DateTime.utc(2026, 9, 10),
    baseCurrency: 'SUI',
    quoteCurrency: 'USDT',
    positionCurrency: 'SUI',
    accountCurrency: accountCurrency,
    liabilityCurrency: 'USDT',
    rawQuantity: rawQuantity,
    quantity: quantity,
    margin: margin,
    markPrice: markPrice,
    entryPrice: 11,
    liquidationPrice: 6,
    unrealizedPnl: unrealizedPnl,
    marginRatio: 4,
    maintenanceRequirement: 100,
    reportedLiability: reportedLiability,
    reportedInterest: reportedInterest,
    hourlyBorrowRate: 0.00001,
    entryFeeRate: 0.001,
    exitFeeRate: 0.001,
    costAttribution: RiskCostAttribution(
      settledInterest: 0,
      unbilledInterest: 2,
      additionalActualCosts: 0,
      actualInterestToday: _actualTodayFixture(),
      coverage: RiskCostCoverage.completeForPosition(
        positionOpenedAt: DateTime.utc(2026, 9, 1),
        coverageFrom: DateTime.utc(2026, 9, 1),
        coverageTo: DateTime.utc(2026, 9, 10),
        nonOverlapAt: DateTime.utc(2026, 9, 10),
      ),
      observedAt: DateTime.utc(2026, 9, 10, 11, 55),
      source: 'fixture-costs',
    ),
    quality: const RiskQuality.complete(source: 'fixture'),
    source: 'fixture',
  );
}

RiskCostAttribution _verifiedCosts({required double settledInterest}) {
  return RiskCostAttribution(
    settledInterest: settledInterest,
    unbilledInterest: 0,
    additionalActualCosts: 0,
    actualInterestToday: _actualTodayFixture(),
    coverage: RiskCostCoverage.completeForPosition(
      positionOpenedAt: DateTime.utc(2026, 9, 1),
      coverageFrom: DateTime.utc(2026, 9, 1),
      coverageTo: DateTime.utc(2026, 9, 10),
      nonOverlapAt: DateTime.utc(2026, 9, 10),
    ),
    observedAt: DateTime.utc(2026, 9, 10, 11, 55),
    source: 'fixture-costs',
  );
}

RiskActualInterestToday _actualTodayFixture() {
  return RiskActualInterestToday(
    amount: 0.25,
    knownSubtotal: 0.25,
    windowStart: DateTime.utc(2026, 9, 10),
    windowEnd: DateTime.utc(2026, 9, 10, 12),
    quality: const RiskQuality.complete(source: 'fixture-costs'),
    coverageComplete: true,
    observedAt: DateTime.utc(2026, 9, 10, 11, 55),
    sourceAt: DateTime.utc(2026, 9, 10, 12),
    source: 'fixture-costs',
  );
}

RiskPosition _f2() {
  return RiskPosition(
    instrumentId: 'SUI-USDT',
    instrumentType: 'MARGIN',
    mode: RiskAccountMode.newMode,
    collateralCurrency: RiskCollateralCurrency.base,
    positionSide: 'net',
    positionId: 'position-2',
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 10),
    observedAt: DateTime.utc(2026, 9, 10),
    baseCurrency: 'SUI',
    quoteCurrency: 'USDT',
    positionCurrency: 'SUI',
    accountCurrency: 'SUI',
    liabilityCurrency: 'USDT',
    rawQuantity: 100,
    quantity: 100,
    margin: 50,
    markPrice: 10,
    entryPrice: 11,
    liquidationPrice: 6,
    unrealizedPnl: -20,
    marginRatio: 4,
    reportedLiability: 1200,
    reportedInterest: 0,
    hourlyBorrowRate: 0.00001,
    entryFeeRate: 0.001,
    exitFeeRate: 0.001,
    costAttribution: RiskCostAttribution(
      settledInterest: 0,
      unbilledInterest: 0,
      additionalActualCosts: 0,
      coverage: RiskCostCoverage.completeForPosition(
        positionOpenedAt: DateTime.utc(2026, 9, 1),
        coverageFrom: DateTime.utc(2026, 9, 1),
        coverageTo: DateTime.utc(2026, 9, 10),
        nonOverlapAt: DateTime.utc(2026, 9, 10),
      ),
    ),
    quality: const RiskQuality.complete(source: 'fixture'),
    source: 'fixture',
  );
}
