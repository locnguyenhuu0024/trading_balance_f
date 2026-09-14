import 'dart:math' as math;

import 'risk_models.dart';
import 'risk_policy.dart';

typedef RiskClock = DateTime Function();

/// Pure position/recovery/stress evaluator.
///
/// The engine never performs I/O and never calls a trading endpoint.  The
/// repository supplies a normalized [RiskPosition] and, when available, an
/// independent [RiskMarketInput].
class RiskEngine {
  const RiskEngine({this.clock});

  final RiskClock? clock;

  RiskEvaluation evaluate(
    RiskPosition position, {
    RiskPolicy? policy,
    RiskMarketInput? market,
    DateTime? now,
    Iterable<RiskPriceLevelInput> priceLevels = const <RiskPriceLevelInput>[],
    Iterable<double> customPrices = const <double>[],
  }) {
    final activePolicy = policy ?? RiskPolicy.defaults();
    activePolicy.requireValid();
    final evaluatedAt = now ?? clock?.call() ?? DateTime.now().toUtc();
    final suppliedPriceLevels = List<RiskPriceLevelInput>.from(priceLevels);
    final suppliedCustomPrices = List<double>.from(customPrices);
    final calculation = _calculate(position, activePolicy, market, evaluatedAt);
    final stress = _buildStressScenarios(
      position,
      activePolicy,
      market,
      calculation,
      suppliedPriceLevels,
      suppliedCustomPrices,
      evaluatedAt,
    );
    final map = _buildPriceMap(
      position,
      calculation,
      stress,
      market,
      suppliedPriceLevels,
      suppliedCustomPrices,
      activePolicy,
    );

    final allReasons = <RiskReason>[
      ...calculation.positionAssessment.reasons,
      ...calculation.marketAssessment.reasons,
      ...calculation.recoveryAssessment.reasons,
    ];
    allReasons.sort(_reasonComparator);
    final missingReasons = <String>[
      ...calculation.positionAssessment.missingReasons,
      ...calculation.marketAssessment.missingReasons,
      ...calculation.recoveryAssessment.missingReasons,
    ];
    final quality = _overallQuality(
      position,
      calculation,
      market,
      missingReasons,
      evaluatedAt,
    );

    return RiskEvaluation(
      position: position,
      metrics: calculation.metrics,
      positionAssessment: calculation.positionAssessment,
      marketAssessment: calculation.marketAssessment,
      recoveryAssessment: calculation.recoveryAssessment,
      overallState: RiskSeverityX.maximum(<RiskSeverity?>[
        calculation.positionAssessment.state,
        calculation.marketAssessment.state,
        calculation.recoveryAssessment.state,
      ]),
      quality: quality,
      reasons: List.unmodifiable(allReasons),
      stressScenarios: List.unmodifiable(stress),
      priceMap: List.unmodifiable(map),
      evaluatedAt: evaluatedAt,
      missingReasons: List.unmodifiable(_uniqueStrings(missingReasons)),
      exchangePnlBasis: calculation.exchangePnlBasis,
      policyVersion: activePolicy.version,
    );
  }

  /// Convenience alias for callers that prefer an explicit method name.
  RiskEvaluation evaluatePosition(
    RiskPosition position, {
    RiskPolicy? policy,
    RiskMarketInput? market,
    DateTime? now,
    Iterable<RiskPriceLevelInput> priceLevels = const <RiskPriceLevelInput>[],
    Iterable<double> customPrices = const <double>[],
  }) {
    return evaluate(
      position,
      policy: policy,
      market: market,
      now: now,
      priceLevels: priceLevels,
      customPrices: customPrices,
    );
  }

  _Calculation _calculate(
    RiskPosition position,
    RiskPolicy policy,
    RiskMarketInput? market,
    DateTime evaluatedAt,
  ) {
    final q = _positive(position.quantity ?? _deriveQuantity(position));
    final p = _positive(position.markPrice);
    final a = _positive(position.entryPrice);
    final l = _positive(position.liquidationPrice);
    final margin = _nonNegative(position.margin);
    final equity = _equity(position, p, margin);
    final exposure = _assetExposure(position, q, margin);
    final quoteCollateral = _quoteCollateral(position, margin);
    final debtResult = _reconcileDebt(
      position,
      exposure,
      quoteCollateral,
      p,
      equity,
    );
    final principalDebt = _principalDebt(
      debtResult.reconciledDebt,
      position.costAttribution,
    );
    final tradeNotional = _multiply(q, p);
    final grossExposure = _multiply(exposure, p);
    final leverage = equity != null && equity > 0
        ? _divide(tradeNotional, equity)
        : null;
    final buffer = p != null && l != null ? _divide(p - l, p) : null;
    final tradeSensitivityPoint = q == null ? null : q * 0.01;
    final tradeSensitivityPercent = q != null && p != null
        ? q * p * 0.01
        : null;
    final equitySensitivityPoint = exposure == null ? null : exposure * 0.01;
    final equitySensitivityPercent = exposure != null && p != null
        ? exposure * p * 0.01
        : null;
    final distanceToEntry = a != null && p != null
        ? _divide(a, p) == null
              ? null
              : (a / p) - 1
        : null;
    final trueExit = _trueExitPrice(
      q: q,
      a: a,
      lifetimeInterest: position.costAttribution.lifetimeInterest,
      additionalCosts: position.costAttribution.additionalActualCosts,
      entryFeeRate: _validFee(position.entryFeeRate),
      exitFeeRate: _validFee(position.exitFeeRate),
      coverage: position.costAttribution.coverage,
    );
    final projectedTrueExit = _projectedTrueExitPrice(
      q: q,
      a: a,
      principalDebt: principalDebt,
      lifetimeInterest: position.costAttribution.lifetimeInterest,
      additionalCosts: position.costAttribution.additionalActualCosts,
      entryFeeRate: _validFee(position.entryFeeRate),
      exitFeeRate: _validFee(position.exitFeeRate),
      coverage: position.costAttribution.coverage,
      hourlyBorrowRate: position.hourlyBorrowRate,
      costObservedAt: position.costAttribution.observedAt,
      evaluatedAt: evaluatedAt,
    );
    final knownExit = _knownCostExitPrice(
      q: q,
      a: a,
      costs: position.costAttribution,
      entryFeeRate: _validFee(position.entryFeeRate),
      exitFeeRate: _validFee(position.exitFeeRate),
    );
    final holdingPerDay = _holdingCost(
      principalDebt,
      position.hourlyBorrowRate,
      24,
    );
    final holding7d = _holdingCost(
      principalDebt,
      position.hourlyBorrowRate,
      24 * 7,
    );
    final holding30d = _holdingCost(
      principalDebt,
      position.hourlyBorrowRate,
      24 * 30,
    );
    final recoveryDistance = trueExit != null && p != null
        ? _clampRecoveryDistance(trueExit / p - 1)
        : null;
    final holdingBurden = holding30d != null && equity != null && equity > 0
        ? _divide(holding30d, equity)
        : null;
    final tradePnl = _tradePnl(position, q, p);

    final metrics = RiskMetrics(
      quantity: _metric(q, 'base', position, evaluatedAt),
      markPrice: _metric(p, 'USDT/base', position, evaluatedAt),
      entryPrice: _metric(a, 'USDT/base', position, evaluatedAt),
      liquidationPrice: _metric(l, 'USDT/base', position, evaluatedAt),
      margin: _metric(margin, 'collateral', position, evaluatedAt),
      equity: _metric(equity, 'USDT', position, evaluatedAt),
      debt: _metric(
        debtResult.displayDebt,
        'USDT',
        position,
        evaluatedAt,
        qualityReason:
            debtResult.reconciledDebt == null || debtResult.precisionLimited
            ? debtResult.reason
            : null,
      ),
      principalDebt: _metric(
        principalDebt,
        'USDT',
        position,
        evaluatedAt,
        qualityReason: debtResult.reconciledDebt == null
            ? debtResult.reason
            : null,
      ),
      tradeNotional: _metric(tradeNotional, 'USDT', position, evaluatedAt),
      grossAssetExposure: _metric(grossExposure, 'USDT', position, evaluatedAt),
      effectiveLeverage: _metric(leverage, 'x', position, evaluatedAt),
      buffer: _metric(buffer, 'fraction', position, evaluatedAt),
      marginRatio: _metric(
        position.marginRatio,
        'ratio',
        position,
        evaluatedAt,
      ),
      maintenanceRequirement: _metric(
        position.maintenanceRequirement,
        'USDT/collateral',
        position,
        evaluatedAt,
      ),
      tradeSensitivityPerPoint: _metric(
        tradeSensitivityPoint,
        'USDT per 0.01',
        position,
        evaluatedAt,
      ),
      tradeSensitivityPerPercent: _metric(
        tradeSensitivityPercent,
        'USDT per 1%',
        position,
        evaluatedAt,
      ),
      equitySensitivityPerPoint: _metric(
        equitySensitivityPoint,
        'USDT per 0.01',
        position,
        evaluatedAt,
      ),
      equitySensitivityPerPercent: _metric(
        equitySensitivityPercent,
        'USDT per 1%',
        position,
        evaluatedAt,
      ),
      distanceToEntry: _metric(
        distanceToEntry,
        'fraction',
        position,
        evaluatedAt,
      ),
      distanceToTrueExit: _metric(
        trueExit != null && p != null ? (trueExit / p) - 1 : null,
        'fraction',
        position,
        evaluatedAt,
      ),
      actualInterestToday: _actualInterestTodayMetric(position, evaluatedAt),
      knownInterestToday: _knownInterestTodayMetric(position, evaluatedAt),
      trueExitPrice: _metric(trueExit, 'USDT', position, evaluatedAt),
      projectedTrueExitPrice: _metric(
        projectedTrueExit,
        'USDT',
        position,
        evaluatedAt,
        qualityReason: projectedTrueExit == null
            ? 'Projected True Exit unavailable or cost observation stale'
            : 'Projected True Exit uses elapsed interest while cost observation is fresh for 10 minutes',
        observedAtOverride: projectedTrueExit == null ? null : evaluatedAt,
        sourceAtOverride: position.updatedAt,
        sourceOverride: position.costAttribution.source,
      ),
      knownCostExitPrice: _metric(knownExit, 'USDT', position, evaluatedAt),
      holdingCostPerDay: _metric(
        holdingPerDay,
        'USDT/day',
        position,
        evaluatedAt,
      ),
      holdingCost7d: _metric(holding7d, 'USDT/7d', position, evaluatedAt),
      holdingCost30d: _metric(holding30d, 'USDT/30d', position, evaluatedAt),
      recoveryDistance: _metric(
        recoveryDistance,
        'fraction',
        position,
        evaluatedAt,
      ),
      holdingBurden: _metric(holdingBurden, 'fraction', position, evaluatedAt),
      tradePnl: _metric(tradePnl, 'USDT', position, evaluatedAt),
    );

    final positionAssessment = _assessPosition(
      position,
      policy,
      market,
      q,
      p,
      l,
      equity,
      leverage,
      buffer,
      debtResult,
      evaluatedAt,
    );
    final marketAssessment = _assessMarket(market, evaluatedAt);
    final recoveryAssessment = _assessRecovery(
      policy,
      recoveryDistance,
      holdingBurden,
      position.source,
      evaluatedAt,
    );
    final exchangePnlBasis =
        position.collateralCurrency == RiskCollateralCurrency.base
        ? 'Current position UPL converted from ${position.positionCurrency ?? position.baseCurrency ?? 'base'} at mark price; exchange-PnL basis'
        : 'Current position UPL reported in quote collateral; exchange-PnL basis';

    return _Calculation(
      metrics: metrics,
      positionAssessment: positionAssessment,
      marketAssessment: marketAssessment,
      recoveryAssessment: recoveryAssessment,
      equity: equity,
      quantity: q,
      markPrice: p,
      baseExposure: exposure,
      exchangePnlBasis: tradePnl == null ? null : exchangePnlBasis,
      trueExitPrice: trueExit,
      holdingCost30d: holding30d,
    );
  }

  RiskAssessment _assessPosition(
    RiskPosition position,
    RiskPolicy policy,
    RiskMarketInput? market,
    double? q,
    double? p,
    double? l,
    double? equity,
    double? leverage,
    double? buffer,
    _DebtResult debtResult,
    DateTime at,
  ) {
    final reasons = <RiskReason>[];
    final missing = <String>[];
    final states = <RiskSeverity?>[];
    final source = position.source ?? 'risk-engine';

    if (debtResult.reason != null) {
      // A reason is evidence-bearing only when a finite observed debt value
      // exists. The missing-data path still carries the warning below, but it
      // must not emit a reason with an invented/null observed value.
      final observedDebt = debtResult.displayDebt;
      if (observedDebt != null) {
        reasons.add(
          RiskReason(
            factorId: 'debt-reconciliation',
            message: debtResult.reason!,
            observedValue: observedDebt,
            threshold: 'max(0.01 USDT, 0.1% of implied debt)',
            window: 'current isolated snapshot',
            observedAt: at,
            source: source,
            evidence: debtResult.precisionLimited
                ? 'Both debt interpretations fell within tolerance'
                : null,
          ),
        );
      }
      if (debtResult.reconciledDebt == null) {
        missing.add('Debt reconciliation is incomplete');
      }
    }

    if (position.eligibility != RiskEligibility.eligible ||
        !position.isEligible) {
      missing.add(_eligibilityReason(position));
    }
    if (p == null || l == null) {
      missing.add(
        'Buffer unavailable: mark and liquidation prices must be positive',
      );
    } else {
      final state = policy.classifyBuffer(buffer!);
      states.add(state);
      reasons.add(
        RiskReason(
          factorId: 'buffer',
          message:
              'Liquidation buffer is ${(buffer * 100).toStringAsFixed(2)}%',
          severity: state,
          observedValue: buffer,
          threshold:
              '${_percent(policy.bufferCritical)} / ${_percent(policy.bufferHigh)} / ${_percent(policy.bufferWatch)}',
          unit: 'percent',
          window: 'current isolated snapshot',
          observedAt: at,
          source: source,
        ),
      );
    }

    if (equity == null) {
      missing.add('Effective leverage unavailable: equity is incomplete');
    } else if (equity <= 0) {
      states.add(RiskSeverity.critical);
      reasons.add(
        RiskReason(
          factorId: 'equity-floor',
          message: 'Equity is zero or negative; leverage is not meaningful',
          severity: RiskSeverity.critical,
          observedValue: equity,
          threshold: 'E <= 0',
          unit: 'USDT',
          window: 'current isolated snapshot',
          observedAt: at,
          source: source,
        ),
      );
    } else if (leverage == null) {
      missing.add(
        'Effective leverage unavailable: quantity or mark price is incomplete',
      );
    } else {
      final state = policy.classifyLeverage(leverage);
      states.add(state);
      reasons.add(
        RiskReason(
          factorId: 'leverage',
          message: 'Effective leverage is ${leverage.toStringAsFixed(4)}x',
          severity: state,
          observedValue: leverage,
          threshold:
              '${policy.leverageWatch}x / ${policy.leverageHigh}x / ${policy.leverageCritical}x',
          unit: 'x',
          window: 'current isolated snapshot',
          observedAt: at,
          source: source,
        ),
      );
    }

    final ratio = position.marginRatio;
    if (ratio == null || !ratio.isFinite || ratio < 0) {
      missing.add('OKX margin ratio unavailable');
    } else {
      final state = policy.classifyMarginRatio(ratio);
      states.add(state);
      reasons.add(
        RiskReason(
          factorId: 'margin-ratio',
          message: 'OKX margin ratio is ${(ratio * 100).toStringAsFixed(2)}%',
          severity: state,
          observedValue: ratio,
          threshold:
              '${_percent(policy.marginRatioCritical)} / ${_percent(policy.marginRatioHigh)} / ${_percent(policy.marginRatioWatch)}',
          unit: 'ratio',
          window: 'current isolated snapshot',
          observedAt: at,
          source: source,
        ),
      );
    }

    if (p != null && l != null && p <= l) {
      states.add(RiskSeverity.critical);
      reasons.add(
        RiskReason(
          factorId: 'liquidation-floor',
          message: 'Mark price is at or below the current liquidation estimate',
          severity: RiskSeverity.critical,
          observedValue: p,
          threshold: 'P <= L (${l.toStringAsFixed(8)})',
          unit: 'USDT',
          window: 'current isolated snapshot',
          observedAt: at,
          source: source,
        ),
      );
    }

    final dailyVolatility = market?.dailyVolatility;
    if (buffer == null ||
        dailyVolatility == null ||
        !dailyVolatility.isFinite ||
        dailyVolatility <= 0) {
      missing.add('Buffer / daily volatility is unavailable');
    } else {
      final ratioValue = buffer / dailyVolatility;
      if (ratioValue.isFinite) {
        final state = policy.classifyBufferVolatility(ratioValue);
        states.add(state);
        reasons.add(
          RiskReason(
            factorId: 'buffer-volatility',
            message:
                'Buffer is ${ratioValue.toStringAsFixed(3)} daily-volatility units',
            severity: state,
            observedValue: ratioValue,
            threshold:
                '${policy.bufferVolatilityHigh} / ${policy.bufferVolatilityWatch}',
            unit: 'ratio',
            window: 'market daily volatility',
            observedAt: at,
            source: market?.source ?? source,
          ),
        );
      } else {
        missing.add('Buffer / daily volatility is unavailable');
      }
    }

    final state = RiskSeverityX.maximum(states);
    final computedQuality = missing.isEmpty
        ? RiskQuality.complete(
            source: source,
            observedAt: at,
            sourceAt: position.updatedAt,
          )
        : RiskQuality.partial(
            source: source,
            observedAt: at,
            sourceAt: position.updatedAt,
            reason: _uniqueStrings(missing).join('; '),
          );
    return RiskAssessment(
      state: state,
      quality: position.quality.status == RiskQualityStatus.complete
          ? computedQuality
          : position.quality,
      reasons: List.unmodifiable(reasons),
      missingReasons: List.unmodifiable(_uniqueStrings(missing)),
      label: 'Position',
    );
  }

  RiskAssessment _assessMarket(RiskMarketInput? market, DateTime at) {
    if (market == null) {
      return const RiskAssessment(
        state: null,
        quality: RiskQuality.unavailable(
          source: 'market-input',
          reason: 'Market input is not available',
        ),
        missingReasons: <String>['Market input is unavailable'],
        label: 'Market',
      );
    }
    final missing = <String>[...market.missingReasons];
    if (market.state == null) missing.add('Market state is unavailable');
    return RiskAssessment(
      // Market analytics are capped at HIGH by contract. CRITICAL belongs to
      // the position floor/hard rules even if an upstream input is malformed.
      state: _boundedMarketState(market.state),
      quality: missing.isEmpty && market.complete
          ? RiskQuality.complete(
              source: market.source,
              observedAt: market.observedAt ?? at,
            )
          : RiskQuality.partial(
              source: market.source,
              observedAt: market.observedAt ?? at,
              reason: _uniqueStrings(missing).join('; '),
            ),
      reasons: List.unmodifiable(market.reasons),
      missingReasons: List.unmodifiable(_uniqueStrings(missing)),
      label: 'Market',
    );
  }

  RiskAssessment _assessRecovery(
    RiskPolicy policy,
    double? distance,
    double? burden,
    String? source,
    DateTime at,
  ) {
    final reasons = <RiskReason>[];
    final missing = <String>[];
    final states = <RiskSeverity?>[];
    if (distance == null) {
      missing.add('True Exit is unavailable or partial');
      missing.add('Recovery distance is unavailable: True Exit is incomplete');
    } else {
      final state = policy.classifyRecoveryDistance(distance);
      states.add(state);
      reasons.add(
        RiskReason(
          factorId: 'recovery-distance',
          message:
              'True Exit is ${(distance * 100).toStringAsFixed(2)}% above mark',
          severity: state,
          observedValue: distance,
          threshold:
              '${_percent(policy.recoveryDistanceWatch)} / ${_percent(policy.recoveryDistanceHigh)}',
          unit: 'percent',
          window: 'current isolated snapshot',
          observedAt: at,
          source: source ?? 'risk-engine',
        ),
      );
    }
    if (burden == null) {
      missing.add(
        'Holding burden is unavailable: equity or cost rate is incomplete',
      );
    } else {
      final state = policy.classifyHoldingBurden(burden);
      states.add(state);
      reasons.add(
        RiskReason(
          factorId: 'holding-burden',
          message:
              'Projected 30-day holding burden is ${(burden * 100).toStringAsFixed(2)}% of equity',
          severity: state,
          observedValue: burden,
          threshold:
              '${_percent(policy.holdingBurdenWatch)} / ${_percent(policy.holdingBurdenHigh)}',
          unit: 'percent',
          window: '30 days',
          observedAt: at,
          source: source ?? 'risk-engine',
        ),
      );
    }
    return RiskAssessment(
      state: RiskSeverityX.maximum(states),
      quality: missing.isEmpty
          ? RiskQuality.complete(source: source, observedAt: at)
          : RiskQuality.partial(
              source: source,
              reason: _uniqueStrings(missing).join('; '),
              observedAt: at,
            ),
      reasons: List.unmodifiable(reasons),
      missingReasons: List.unmodifiable(_uniqueStrings(missing)),
      label: 'Recovery',
    );
  }

  List<RiskStressScenario> _buildStressScenarios(
    RiskPosition position,
    RiskPolicy policy,
    RiskMarketInput? market,
    _Calculation calculation,
    Iterable<RiskPriceLevelInput> priceLevels,
    Iterable<double> customPrices,
    DateTime evaluatedAt,
  ) {
    final p = calculation.markPrice;
    final q = calculation.quantity;
    final e = calculation.equity;
    final b = calculation.baseExposure;
    if (p == null || !p.isFinite || p <= 0) return const <RiskStressScenario>[];
    final seen = <double>[];
    final result = <RiskStressScenario>[];
    for (final change in policy.stressChanges) {
      final price = p * (1 + change);
      final value = _positive(price);
      if (value == null) continue;
      if (_containsPrice(seen, value, policy.priceDeduplicationTolerance)) {
        continue;
      }
      seen.add(value);
      result.add(
        _scenario(
          position: position,
          policy: policy,
          market: market,
          price: value,
          percentageChange: change,
          label: change == 0 ? 'Current' : '${_formatPercent(change)} scenario',
          quantity: q,
          currentEquity: e,
          baseExposure: b,
          trueExitPrice: calculation.trueExitPrice,
          holdingCost30d: calculation.holdingCost30d,
          evaluatedAt: evaluatedAt,
        ),
      );
    }
    for (final custom in customPrices) {
      if (!custom.isFinite ||
          custom <= 0 ||
          _containsPrice(seen, custom, policy.priceDeduplicationTolerance)) {
        continue;
      }
      seen.add(custom);
      result.add(
        _scenario(
          position: position,
          policy: policy,
          market: market,
          price: custom,
          percentageChange: null,
          label: 'Custom price',
          quantity: q,
          currentEquity: e,
          baseExposure: b,
          trueExitPrice: calculation.trueExitPrice,
          holdingCost30d: calculation.holdingCost30d,
          evaluatedAt: evaluatedAt,
        ),
      );
    }
    final levels = <RiskPriceLevelInput>[
      RiskPriceLevelInput(
        price: calculation.metrics.entryPrice.value ?? double.nan,
        label: 'Entry',
      ),
      RiskPriceLevelInput(
        price: calculation.metrics.liquidationPrice.value ?? double.nan,
        label: 'Liquidation',
      ),
      RiskPriceLevelInput(
        price: calculation.trueExitPrice ?? double.nan,
        label: 'True Exit',
      ),
      ...priceLevels,
    ];
    for (final level in levels) {
      if (!level.price.isFinite ||
          level.price <= 0 ||
          _containsPrice(
            seen,
            level.price,
            policy.priceDeduplicationTolerance,
          )) {
        continue;
      }
      seen.add(level.price);
      result.add(
        _scenario(
          position: position,
          policy: policy,
          market: market,
          price: level.price,
          percentageChange: null,
          label: level.label,
          quantity: q,
          currentEquity: e,
          baseExposure: b,
          trueExitPrice: calculation.trueExitPrice,
          holdingCost30d: calculation.holdingCost30d,
          evaluatedAt: evaluatedAt,
        ),
      );
    }
    return result;
  }

  RiskStressScenario _scenario({
    required RiskPosition position,
    required RiskPolicy policy,
    required RiskMarketInput? market,
    required double price,
    required double? percentageChange,
    required String label,
    required double? quantity,
    required double? currentEquity,
    required double? baseExposure,
    required double? trueExitPrice,
    required double? holdingCost30d,
    required DateTime evaluatedAt,
  }) {
    final equity =
        currentEquity != null &&
            baseExposure != null &&
            position.markPrice != null
        ? currentEquity + baseExposure * (price - position.markPrice!)
        : null;
    final leverage = quantity != null && equity != null && equity > 0
        ? (quantity * price) / equity
        : null;
    final buffer =
        position.liquidationPrice != null && position.liquidationPrice! > 0
        ? (price - position.liquidationPrice!) / price
        : null;
    final tradePnl = _tradePnl(
      position,
      quantity,
      position.markPrice,
      price: price,
    );
    final positionAssessment = _assessScenarioPosition(
      position,
      policy,
      market,
      price,
      equity,
      leverage,
      buffer,
      evaluatedAt,
    );
    final recoveryDistance = trueExitPrice != null
        ? _clampRecoveryDistance(trueExitPrice / price - 1)
        : null;
    final burden = holdingCost30d != null && equity != null && equity > 0
        ? holdingCost30d / equity
        : null;
    final recoveryState = RiskSeverityX.maximum(<RiskSeverity?>[
      recoveryDistance == null
          ? null
          : policy.classifyRecoveryDistance(recoveryDistance),
      burden == null ? null : policy.classifyHoldingBurden(burden),
    ]);
    final marketState = _boundedMarketState(market?.state);
    final overall = RiskSeverityX.maximum(<RiskSeverity?>[
      positionAssessment.state,
      marketState,
      recoveryState,
    ]);
    final reasons = <RiskReason>[...positionAssessment.reasons];
    final source = position.source ?? 'risk-engine';
    if (recoveryDistance != null) {
      final state = policy.classifyRecoveryDistance(recoveryDistance);
      reasons.add(
        RiskReason(
          factorId: 'recovery-distance',
          message:
              'Scenario True Exit is ${(recoveryDistance * 100).toStringAsFixed(2)}% above price',
          severity: state,
          observedValue: recoveryDistance,
          threshold:
              '${_percent(policy.recoveryDistanceWatch)} / ${_percent(policy.recoveryDistanceHigh)}',
          unit: 'percent',
          window: 'frozen-price scenario',
          observedAt: evaluatedAt,
          source: source,
        ),
      );
    }
    if (burden != null) {
      final state = policy.classifyHoldingBurden(burden);
      reasons.add(
        RiskReason(
          factorId: 'holding-burden',
          message:
              'Scenario 30-day holding burden is ${(burden * 100).toStringAsFixed(2)}% of equity',
          severity: state,
          observedValue: burden,
          threshold:
              '${_percent(policy.holdingBurdenWatch)} / ${_percent(policy.holdingBurdenHigh)}',
          unit: 'percent',
          window: '30 days in frozen-price scenario',
          observedAt: evaluatedAt,
          source: source,
        ),
      );
    }
    final atOrBeyondLiquidation =
        position.liquidationPrice != null &&
        price <= position.liquidationPrice!;
    if (atOrBeyondLiquidation) {
      reasons.add(
        RiskReason(
          factorId: 'liquidation-floor',
          message: 'At/beyond current liquidation estimate; hypothetical only',
          severity: RiskSeverity.critical,
          observedValue: price,
          threshold: 'P\' <= L',
          unit: 'USDT',
          window: 'frozen-price scenario',
          observedAt: evaluatedAt,
          source: source,
          evidence: label,
        ),
      );
    }
    final partial =
        equity == null ||
        leverage == null ||
        buffer == null ||
        market == null ||
        !market.complete ||
        market.state == null ||
        recoveryDistance == null ||
        burden == null;
    return RiskStressScenario(
      label: label,
      price: price,
      percentageChange: percentageChange,
      tradePnl: tradePnl,
      equity: equity,
      effectiveLeverage: leverage,
      buffer: buffer,
      marginRatio: null,
      currentMarginRatio: position.marginRatio,
      positionState: positionAssessment.state,
      overallState: overall,
      partial: partial || positionAssessment.partial,
      hypothetical: true,
      reasons: List.unmodifiable(reasons),
    );
  }

  RiskAssessment _assessScenarioPosition(
    RiskPosition position,
    RiskPolicy policy,
    RiskMarketInput? market,
    double price,
    double? equity,
    double? leverage,
    double? buffer,
    DateTime at,
  ) {
    final reasons = <RiskReason>[];
    final missing = <String>[];
    final states = <RiskSeverity?>[];
    final source = position.source ?? 'risk-engine';
    if (buffer == null) {
      missing.add('Scenario buffer unavailable');
    } else {
      final state = policy.classifyBuffer(buffer);
      states.add(state);
      reasons.add(
        RiskReason(
          factorId: 'buffer',
          message: 'Scenario buffer is ${(buffer * 100).toStringAsFixed(2)}%',
          severity: state,
          observedValue: buffer,
          threshold:
              '${_percent(policy.bufferCritical)} / ${_percent(policy.bufferHigh)} / ${_percent(policy.bufferWatch)}',
          unit: 'percent',
          window: 'frozen-price scenario',
          observedAt: at,
          source: source,
        ),
      );
    }
    if (equity == null) {
      missing.add(
        'Scenario equity unavailable: collateral exposure is incomplete',
      );
    } else if (equity <= 0) {
      states.add(RiskSeverity.critical);
      reasons.add(
        RiskReason(
          factorId: 'equity-floor',
          message:
              'Scenario equity is zero or negative; leverage is not meaningful',
          severity: RiskSeverity.critical,
          observedValue: equity,
          threshold: 'E\' <= 0',
          unit: 'USDT',
          window: 'frozen-price scenario',
          observedAt: at,
          source: source,
        ),
      );
    } else if (leverage == null) {
      missing.add('Scenario leverage unavailable');
    } else {
      final state = policy.classifyLeverage(leverage);
      states.add(state);
      reasons.add(
        RiskReason(
          factorId: 'leverage',
          message: 'Scenario leverage is ${leverage.toStringAsFixed(4)}x',
          severity: state,
          observedValue: leverage,
          threshold:
              '${policy.leverageWatch}x / ${policy.leverageHigh}x / ${policy.leverageCritical}x',
          unit: 'x',
          window: 'frozen-price scenario',
          observedAt: at,
          source: source,
        ),
      );
    }
    final ratio = position.marginRatio;
    // The future exchange ratio is not derivable from frozen-debt prices.
    // Retain the current ratio only as a hard floor and keep the scenario
    // partial regardless of whether that current floor exists.
    missing.add('Future OKX margin ratio is unavailable');
    if (ratio == null || !ratio.isFinite || ratio < 0) {
      // No current floor is available either.
    } else {
      final state = policy.classifyMarginRatio(ratio);
      states.add(state);
      reasons.add(
        RiskReason(
          factorId: 'margin-ratio-floor',
          message:
              'Current OKX margin-ratio floor retained; future ratio is not predicted',
          severity: state,
          observedValue: ratio,
          threshold:
              '${_percent(policy.marginRatioCritical)} / ${_percent(policy.marginRatioHigh)} / ${_percent(policy.marginRatioWatch)}',
          unit: 'ratio',
          window: 'current floor in frozen-price scenario',
          observedAt: at,
          source: source,
        ),
      );
    }
    if (position.liquidationPrice != null &&
        price <= position.liquidationPrice!) {
      states.add(RiskSeverity.critical);
    }
    if (buffer != null &&
        market?.dailyVolatility != null &&
        market!.dailyVolatility! > 0) {
      states.add(
        policy.classifyBufferVolatility(buffer / market.dailyVolatility!),
      );
    } else {
      missing.add('Scenario buffer / daily volatility is unavailable');
    }
    return RiskAssessment(
      state: RiskSeverityX.maximum(states),
      quality: missing.isEmpty
          ? RiskQuality.complete(source: 'frozen-market-stress', observedAt: at)
          : RiskQuality.partial(
              source: 'frozen-market-stress',
              reason: _uniqueStrings(missing).join('; '),
              observedAt: at,
            ),
      reasons: List.unmodifiable(reasons),
      missingReasons: List.unmodifiable(_uniqueStrings(missing)),
      label: 'Scenario Position',
    );
  }

  List<RiskPriceMapLevel> _buildPriceMap(
    RiskPosition position,
    _Calculation calculation,
    List<RiskStressScenario> stress,
    RiskMarketInput? market,
    Iterable<RiskPriceLevelInput> priceLevels,
    Iterable<double> customPrices,
    RiskPolicy policy,
  ) {
    final levels = <RiskPriceLevelInput>[];
    void add(String label, double? price) {
      if (price == null || !price.isFinite || price <= 0) return;
      levels.add(RiskPriceLevelInput(price: price, label: label));
    }

    add('Current', calculation.markPrice);
    add('Entry', calculation.metrics.entryPrice.value);
    add('Liquidation', calculation.metrics.liquidationPrice.value);
    add('True Exit', calculation.trueExitPrice);
    add(
      'Known-cost exit estimate',
      calculation.metrics.knownCostExitPrice.value,
    );
    final liquidation = calculation.metrics.liquidationPrice.value;
    if (liquidation != null) {
      add(
        'Buffer ${_percent(policy.bufferHigh)}',
        liquidation / (1 - policy.bufferHigh),
      );
      add(
        'Buffer ${_percent(policy.bufferCritical)}',
        liquidation / (1 - policy.bufferCritical),
      );
    }
    add('Support', market?.support);
    add('Resistance', market?.resistance);
    levels.addAll(
      priceLevels.where((level) => level.price.isFinite && level.price > 0),
    );
    for (final custom in customPrices) {
      add('Custom price', custom);
    }
    for (final scenario in stress) {
      add(scenario.label, scenario.price);
    }

    final grouped = <double, List<String>>{};
    for (final level in levels) {
      double? key;
      for (final existing in grouped.keys) {
        if (_samePrice(
          existing,
          level.price,
          policy.priceDeduplicationTolerance,
        )) {
          key = existing;
          break;
        }
      }
      key ??= level.price;
      grouped.putIfAbsent(key, () => <String>[]).add(level.label);
    }
    final entries = grouped.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return entries
        .map(
          (entry) => RiskPriceMapLevel(
            price: entry.key,
            labels: List.unmodifiable(_uniqueStrings(entry.value)),
          ),
        )
        .toList(growable: false);
  }

  RiskQuality _overallQuality(
    RiskPosition position,
    _Calculation calculation,
    RiskMarketInput? market,
    List<String> missing,
    DateTime at,
  ) {
    final reasons = _uniqueStrings([
      ...missing,
      ..._missingMetricReasons(calculation.metrics),
    ]);
    if (position.quality.status != RiskQualityStatus.complete) {
      return position.quality;
    }
    if (reasons.isEmpty && market != null && market.complete) {
      return RiskQuality.complete(
        source: position.source,
        observedAt: at,
        sourceAt: position.updatedAt,
      );
    }
    return RiskQuality.partial(
      source: position.source,
      observedAt: at,
      sourceAt: position.updatedAt,
      reason: reasons.join('; '),
    );
  }

  RiskSeverity? _boundedMarketState(RiskSeverity? state) {
    if (state == RiskSeverity.critical) return RiskSeverity.high;
    return state;
  }

  List<String> _missingMetricReasons(RiskMetrics metrics) {
    final values = <String, RiskMetricValue>{
      'quantity': metrics.quantity,
      'mark price': metrics.markPrice,
      'entry price': metrics.entryPrice,
      'liquidation price': metrics.liquidationPrice,
      'margin': metrics.margin,
      'equity': metrics.equity,
      'debt': metrics.debt,
      'principal debt': metrics.principalDebt,
      'trade notional': metrics.tradeNotional,
      'gross asset exposure': metrics.grossAssetExposure,
      'effective leverage': metrics.effectiveLeverage,
      'buffer': metrics.buffer,
      'margin ratio': metrics.marginRatio,
      'maintenance requirement': metrics.maintenanceRequirement,
      'trade sensitivity': metrics.tradeSensitivityPerPoint,
      'equity sensitivity': metrics.equitySensitivityPerPoint,
      'entry distance': metrics.distanceToEntry,
      'True Exit distance': metrics.distanceToTrueExit,
      'True Exit': metrics.trueExitPrice,
      'actual interest today': metrics.actualInterestToday,
      'known interest subtotal today': metrics.knownInterestToday,
      'known-cost exit estimate': metrics.knownCostExitPrice,
      'holding cost': metrics.holdingCostPerDay,
      'recovery distance': metrics.recoveryDistance,
      'holding burden': metrics.holdingBurden,
      'trade PnL': metrics.tradePnl,
    };
    final missing = <String>[];
    for (final entry in values.entries) {
      if (!entry.value.isAvailable ||
          entry.value.quality.status != RiskQualityStatus.complete) {
        missing.add('${entry.key} is unavailable or partial');
      }
    }
    return missing;
  }

  RiskMetricValue _metric(
    double? value,
    String unit,
    RiskPosition position,
    DateTime at, {
    String? qualityReason,
    RiskQuality? qualityOverride,
    DateTime? observedAtOverride,
    DateTime? sourceAtOverride,
    String? sourceOverride,
  }) {
    final observedAt = observedAtOverride ?? position.observedAt ?? at;
    final sourceAt = sourceAtOverride ?? position.updatedAt;
    final source = sourceOverride ?? position.source;
    final preservedQuality = switch (position.quality.status) {
      // A stale/error/unsupported snapshot must not be made trustworthy by a
      // numeric value that happens to be present. A partial position can,
      // however, still expose a separately verified submetric such as the
      // local-day interest window with its own quality evidence.
      RiskQualityStatus.stale ||
      RiskQualityStatus.unavailable ||
      RiskQualityStatus.error ||
      RiskQualityStatus.unsupported ||
      RiskQualityStatus.empty => position.quality,
      _ => null,
    };
    if (value == null || !value.isFinite) {
      return RiskMetricValue(
        value: null,
        unit: unit,
        source: source,
        observedAt: observedAt,
        sourceAt: sourceAt,
        quality:
            preservedQuality ??
            qualityOverride ??
            RiskQuality.unavailable(
              source: source,
              reason: qualityReason ?? 'Verified input unavailable',
              observedAt: observedAt,
              sourceAt: sourceAt,
            ),
      );
    }
    final quality =
        preservedQuality ??
        qualityOverride ??
        (qualityReason == null
            ? RiskQuality.complete(
                source: source,
                observedAt: observedAt,
                sourceAt: sourceAt,
              )
            : RiskQuality.partial(
                source: source,
                reason: qualityReason,
                observedAt: observedAt,
                sourceAt: sourceAt,
              ));
    return RiskMetricValue(
      value: value,
      unit: unit,
      source: source,
      observedAt: observedAt,
      sourceAt: sourceAt,
      quality: quality,
    );
  }

  RiskMetricValue _actualInterestTodayMetric(
    RiskPosition position,
    DateTime evaluatedAt,
  ) {
    final today = position.costAttribution.actualInterestToday;
    if (today == null) {
      return _metric(
        null,
        'USDT/today',
        position,
        evaluatedAt,
        qualityReason: 'Actual interest accrued today unavailable',
      );
    }
    return _metric(
      today.amount,
      'USDT/today',
      position,
      evaluatedAt,
      qualityReason: today.quality.reason,
      qualityOverride: today.quality,
      observedAtOverride: today.observedAt,
      sourceAtOverride: today.sourceAt,
      sourceOverride: today.source,
    );
  }

  RiskMetricValue _knownInterestTodayMetric(
    RiskPosition position,
    DateTime evaluatedAt,
  ) {
    final today = position.costAttribution.actualInterestToday;
    if (today == null) {
      return _metric(
        null,
        'USDT/today',
        position,
        evaluatedAt,
        qualityReason: 'Known interest subtotal for today unavailable',
      );
    }
    return _metric(
      today.knownSubtotal,
      'USDT/today',
      position,
      evaluatedAt,
      qualityReason:
          today.quality.reason ??
          'Known subtotal is partial until the local-day window is covered',
      qualityOverride: today.quality,
      observedAtOverride: today.observedAt,
      sourceAtOverride: today.sourceAt,
      sourceOverride: today.source,
    );
  }

  double? _deriveQuantity(RiskPosition position) {
    final raw = position.rawQuantity;
    if (raw == null || !raw.isFinite) return null;
    if (position.mode == RiskAccountMode.oldMode) {
      final margin = position.margin;
      if (margin == null || !margin.isFinite) return null;
      return raw - margin;
    }
    return raw;
  }

  double? _equity(RiskPosition position, double? mark, double? margin) {
    final upl = position.unrealizedPnl;
    if (mark == null || margin == null || upl == null) return null;
    final collateral = margin + upl;
    if (!collateral.isFinite) return null;
    switch (position.collateralCurrency) {
      case RiskCollateralCurrency.base:
        final value = collateral * mark;
        return value.isFinite ? value : null;
      case RiskCollateralCurrency.quote:
        return collateral;
      case RiskCollateralCurrency.unsupported:
        return null;
    }
  }

  double? _assetExposure(RiskPosition position, double? q, double? margin) {
    final raw = position.rawQuantity ?? q;
    if (raw == null || !raw.isFinite) return null;
    switch (position.mode) {
      case RiskAccountMode.newMode:
        if (position.collateralCurrency == RiskCollateralCurrency.base) {
          return margin == null ? null : raw + margin;
        }
        return raw;
      case RiskAccountMode.oldMode:
        return position.collateralCurrency == RiskCollateralCurrency.base
            ? raw
            : null;
      case RiskAccountMode.unsupported:
        return null;
    }
  }

  double? _quoteCollateral(RiskPosition position, double? margin) {
    if (position.mode == RiskAccountMode.newMode &&
        position.collateralCurrency == RiskCollateralCurrency.quote) {
      return margin;
    }
    return 0;
  }

  _DebtResult _reconcileDebt(
    RiskPosition position,
    double? baseExposure,
    double? quoteCollateral,
    double? mark,
    double? equity,
  ) {
    final reported = _nonNegative(position.reportedLiability?.abs());
    if (baseExposure == null ||
        quoteCollateral == null ||
        mark == null ||
        equity == null) {
      return _DebtResult(
        displayDebt: reported,
        reconciledDebt: null,
        reason: 'Debt reconciliation inputs are incomplete',
      );
    }
    final implied = baseExposure * mark + quoteCollateral - equity;
    if (!implied.isFinite || implied < 0) {
      return _DebtResult(
        displayDebt: reported,
        reconciledDebt: null,
        reason: 'Implied isolated debt is invalid',
      );
    }
    if (reported == null) {
      return const _DebtResult(
        displayDebt: null,
        reconciledDebt: null,
        reason: 'Reported liability is unavailable for reconciliation',
      );
    }
    final interest = _nonNegative(position.reportedInterest?.abs());
    final tolerance = _debtTolerance(implied);
    final principalMatches = (reported - implied).abs() <= tolerance;
    final withInterestMatches =
        interest != null && (reported + interest - implied).abs() <= tolerance;
    if (principalMatches && withInterestMatches) {
      return _DebtResult(
        displayDebt: implied,
        reconciledDebt: implied,
        reason:
            'Reported liability and liability plus interest both match within tolerance; precision is limited',
        precisionLimited: true,
      );
    }
    if (withInterestMatches) {
      return _DebtResult(
        displayDebt: implied,
        reconciledDebt: implied,
        reason: 'Debt reconciled as reported liability plus current interest',
      );
    }
    if (principalMatches) {
      return _DebtResult(
        displayDebt: implied,
        reconciledDebt: implied,
        reason: 'Debt reconciled as reported liability',
      );
    }
    return _DebtResult(
      displayDebt: reported,
      reconciledDebt: null,
      reason:
          'Reported liability does not reconcile with isolated equity within tolerance',
    );
  }

  double? _principalDebt(double? debt, RiskCostAttribution costs) {
    // Borrow principal excludes only the currently unbilled/outstanding
    // interest. Settled lifetime interest is a cost for True Exit, not part
    // of today's principal used for the hourly holding projection.
    final interest = costs.unbilledInterest;
    if (debt == null || interest == null || interest < 0 || interest > debt) {
      return null;
    }
    final principal = debt - interest;
    return principal.isFinite && principal >= 0 ? principal : null;
  }

  double? _trueExitPrice({
    required double? q,
    required double? a,
    required double? lifetimeInterest,
    required double? additionalCosts,
    required double? entryFeeRate,
    required double? exitFeeRate,
    required RiskCostCoverage coverage,
  }) {
    if (q == null ||
        q <= 0 ||
        a == null ||
        a <= 0 ||
        !coverage.isVerifiedComplete) {
      return null;
    }
    if (lifetimeInterest == null ||
        additionalCosts == null ||
        lifetimeInterest < 0 ||
        additionalCosts < 0 ||
        entryFeeRate == null ||
        entryFeeRate < 0 ||
        exitFeeRate == null ||
        exitFeeRate < 0 ||
        exitFeeRate >= 1) {
      return null;
    }
    final numerator =
        q * a + lifetimeInterest + additionalCosts + q * a * entryFeeRate;
    final denominator = q * (1 - exitFeeRate);
    if (!numerator.isFinite || !denominator.isFinite || denominator <= 0) {
      return null;
    }
    final result = numerator / denominator;
    return result.isFinite && result > 0 ? result : null;
  }

  /// Interpolates elapsed interest only while the verified cost observation is
  /// fresh. This is a display metric and never feeds recovery, stress, or the
  /// persisted cost attribution.
  double? _projectedTrueExitPrice({
    required double? q,
    required double? a,
    required double? principalDebt,
    required double? lifetimeInterest,
    required double? additionalCosts,
    required double? entryFeeRate,
    required double? exitFeeRate,
    required RiskCostCoverage coverage,
    required double? hourlyBorrowRate,
    required DateTime? costObservedAt,
    required DateTime evaluatedAt,
  }) {
    if (costObservedAt == null ||
        evaluatedAt.isBefore(costObservedAt) ||
        evaluatedAt.difference(costObservedAt) > const Duration(minutes: 10)) {
      return null;
    }
    final elapsedHours =
        evaluatedAt.difference(costObservedAt).inMicroseconds /
        Duration.microsecondsPerHour;
    final elapsedInterest = _holdingCost(
      principalDebt,
      hourlyBorrowRate,
      elapsedHours,
    );
    if (elapsedInterest == null || lifetimeInterest == null) return null;
    final projectedLifetime = lifetimeInterest + elapsedInterest;
    if (!projectedLifetime.isFinite || projectedLifetime < 0) return null;
    return _trueExitPrice(
      q: q,
      a: a,
      lifetimeInterest: projectedLifetime,
      additionalCosts: additionalCosts,
      entryFeeRate: entryFeeRate,
      exitFeeRate: exitFeeRate,
      coverage: coverage,
    );
  }

  /// Secondary estimate for incomplete lifetime attribution. It includes only
  /// explicitly observed costs (or the current unbilled interest) and may use
  /// zero for the additional-cost term solely when that term is marked
  /// partial/unknown. It is never used for recovery rules or alerts.
  double? _knownCostExitPrice({
    required double? q,
    required double? a,
    required RiskCostAttribution costs,
    required double? entryFeeRate,
    required double? exitFeeRate,
  }) {
    if (q == null ||
        q <= 0 ||
        a == null ||
        a <= 0 ||
        entryFeeRate == null ||
        entryFeeRate < 0 ||
        exitFeeRate == null ||
        exitFeeRate < 0 ||
        exitFeeRate >= 1) {
      return null;
    }
    final interest = costs.lifetimeInterest ?? costs.unbilledInterest;
    if (interest != null && (!interest.isFinite || interest < 0)) return null;
    final hasObservedCost =
        interest != null || costs.additionalActualCosts != null;
    if (!hasObservedCost) return null;
    final knownAdditional = costs.additionalActualCosts ?? 0;
    if (knownAdditional < 0) return null;
    final numerator =
        q * a + (interest ?? 0) + knownAdditional + q * a * entryFeeRate;
    final denominator = q * (1 - exitFeeRate);
    if (!numerator.isFinite || denominator <= 0 || !denominator.isFinite) {
      return null;
    }
    final result = numerator / denominator;
    return result.isFinite && result > 0 ? result : null;
  }

  double? _holdingCost(double? principal, double? hourlyRate, double hours) {
    if (principal == null ||
        hourlyRate == null ||
        !hourlyRate.isFinite ||
        hourlyRate < 0) {
      return null;
    }
    final result = principal * hourlyRate * hours;
    return result.isFinite && result >= 0 ? result : null;
  }

  double? _tradePnl(
    RiskPosition position,
    double? quantity,
    double? currentPrice, {
    double? price,
  }) {
    final currentUpl = position.unrealizedPnl;
    if (quantity == null || currentPrice == null || currentUpl == null) {
      return null;
    }
    final currentQuotePnl =
        position.collateralCurrency == RiskCollateralCurrency.base
        ? currentUpl * currentPrice
        : currentUpl;
    final targetPrice = price ?? currentPrice;
    final result = currentQuotePnl + quantity * (targetPrice - currentPrice);
    return result.isFinite ? result : null;
  }

  double? _validFee(double? value) {
    if (value == null || !value.isFinite) return null;
    if (value < 0) return -value;
    // A positive fee field from a rebate source is not an expense.  Callers
    // normalize exchange fee rates to expense fractions; this branch is kept
    // conservative for a positive rebate represented as a negative rate.
    return value;
  }

  double? _positive(double? value) {
    if (value == null || !value.isFinite || value <= 0) return null;
    return value;
  }

  double? _nonNegative(double? value) {
    if (value == null || !value.isFinite || value < 0) return null;
    return value;
  }

  double? _clampRecoveryDistance(double value) {
    if (!value.isFinite) return null;
    return value < 0 ? 0 : value;
  }

  double? _multiply(double? first, double? second) {
    if (first == null || second == null) {
      return null;
    }
    final result = first * second;
    return result.isFinite ? result : null;
  }

  double? _divide(double? numerator, double? denominator) {
    if (numerator == null || denominator == null || denominator == 0) {
      return null;
    }
    final result = numerator / denominator;
    return result.isFinite ? result : null;
  }

  double _debtTolerance(double implied) =>
      (implied.abs() * 0.001).clamp(0.01, double.infinity).toDouble();

  String _eligibilityReason(RiskPosition position) {
    switch (position.eligibility) {
      case RiskEligibility.empty:
        return 'Position is empty';
      case RiskEligibility.unsupported:
        return 'Position mode, currency, or instrument is unsupported';
      case RiskEligibility.shortPosition:
        return 'Short position is outside the v1 long-only scope';
      case RiskEligibility.zeroPosition:
        return 'Position quantity is zero';
      case RiskEligibility.invalid:
        return 'Position identity or source fields are invalid';
      case RiskEligibility.eligible:
        return 'Position eligibility is incomplete';
    }
  }

  String _formatPercent(double value) {
    final percent = value * 100;
    final rendered = percent.abs() == percent.abs().roundToDouble()
        ? percent.toStringAsFixed(0)
        : percent.toStringAsFixed(2);
    return '${percent >= 0 ? '+' : ''}$rendered%';
  }

  String _percent(double fraction) {
    final percent = fraction * 100;
    final rendered = percent == percent.roundToDouble()
        ? percent.toStringAsFixed(0)
        : percent.toStringAsFixed(2);
    return '$rendered%';
  }

  int _reasonComparator(RiskReason left, RiskReason right) {
    int priority(RiskReason reason) {
      if (reason.factorId.contains('floor')) return 0;
      if (reason.factorId == 'buffer') return 1;
      if (reason.factorId == 'leverage' || reason.factorId.contains('ratio')) {
        return 2;
      }
      if (reason.factorId.contains('market')) return 3;
      if (reason.factorId.contains('recovery') ||
          reason.factorId.contains('holding')) {
        return 4;
      }
      return 5;
    }

    final byPriority = priority(left).compareTo(priority(right));
    if (byPriority != 0) return byPriority;
    return left.factorId.compareTo(right.factorId);
  }

  bool _containsPrice(
    List<double> values,
    double candidate,
    double tolerance,
  ) => values.any((value) => _samePrice(value, candidate, tolerance));

  bool _samePrice(double first, double second, double tolerance) =>
      (first - second).abs() <=
      tolerance * (1 + math.max(first.abs(), second.abs()));

  List<String> _uniqueStrings(Iterable<String> values) {
    final result = <String>[];
    for (final value in values) {
      if (value.isNotEmpty && !result.contains(value)) result.add(value);
    }
    return result;
  }
}

class _DebtResult {
  const _DebtResult({
    required this.displayDebt,
    required this.reconciledDebt,
    this.reason,
    this.precisionLimited = false,
  });

  final double? displayDebt;
  final double? reconciledDebt;
  final String? reason;
  final bool precisionLimited;
}

class _Calculation {
  const _Calculation({
    required this.metrics,
    required this.positionAssessment,
    required this.marketAssessment,
    required this.recoveryAssessment,
    required this.equity,
    required this.quantity,
    required this.markPrice,
    required this.baseExposure,
    required this.exchangePnlBasis,
    required this.trueExitPrice,
    required this.holdingCost30d,
  });

  final RiskMetrics metrics;
  final RiskAssessment positionAssessment;
  final RiskAssessment marketAssessment;
  final RiskAssessment recoveryAssessment;
  final double? equity;
  final double? quantity;
  final double? markPrice;
  final double? baseExposure;
  final String? exchangePnlBasis;
  final double? trueExitPrice;
  final double? holdingCost30d;
}
