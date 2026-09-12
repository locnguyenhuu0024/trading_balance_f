// Immutable domain values used by the isolated margin risk feature.
//
// These types deliberately do not depend on Flutter, Dio, Riverpod, or the
// generated Orders models.  A caller can therefore evaluate a snapshot in a
// test, in the foreground, or in the Android owner without duplicating any
// financial formulas.

enum RiskSeverity { normal, watch, high, critical }

extension RiskSeverityX on RiskSeverity {
  int get rank => index;

  String get label {
    switch (this) {
      case RiskSeverity.normal:
        return 'NORMAL';
      case RiskSeverity.watch:
        return 'WATCH';
      case RiskSeverity.high:
        return 'HIGH';
      case RiskSeverity.critical:
        return 'CRITICAL';
    }
  }

  static RiskSeverity? maximum(Iterable<RiskSeverity?> values) {
    RiskSeverity? result;
    for (final value in values) {
      if (value == null || (result != null && result.rank >= value.rank)) {
        continue;
      }
      result = value;
    }
    return result;
  }
}

enum RiskQualityStatus {
  complete,
  partial,
  unavailable,
  stale,
  error,
  unsupported,
  empty,
}

/// A source/freshness description attached to every observation and metric.
class RiskQuality {
  const RiskQuality({
    required this.status,
    this.source,
    this.reason,
    this.observedAt,
    this.sourceAt,
  });

  const RiskQuality.complete({
    String? source,
    DateTime? observedAt,
    DateTime? sourceAt,
  }) : this(
         status: RiskQualityStatus.complete,
         source: source,
         observedAt: observedAt,
         sourceAt: sourceAt,
       );

  const RiskQuality.partial({
    String? source,
    String? reason,
    DateTime? observedAt,
    DateTime? sourceAt,
  }) : this(
         status: RiskQualityStatus.partial,
         source: source,
         reason: reason,
         observedAt: observedAt,
         sourceAt: sourceAt,
       );

  const RiskQuality.unavailable({
    String? source,
    String? reason,
    DateTime? observedAt,
    DateTime? sourceAt,
  }) : this(
         status: RiskQualityStatus.unavailable,
         source: source,
         reason: reason,
         observedAt: observedAt,
         sourceAt: sourceAt,
       );

  const RiskQuality.stale({
    String? source,
    String? reason,
    DateTime? observedAt,
    DateTime? sourceAt,
  }) : this(
         status: RiskQualityStatus.stale,
         source: source,
         reason: reason,
         observedAt: observedAt,
         sourceAt: sourceAt,
       );

  const RiskQuality.error({
    String? source,
    String? reason,
    DateTime? observedAt,
    DateTime? sourceAt,
  }) : this(
         status: RiskQualityStatus.error,
         source: source,
         reason: reason,
         observedAt: observedAt,
         sourceAt: sourceAt,
       );

  const RiskQuality.unsupported({
    String? source,
    String? reason,
    DateTime? observedAt,
    DateTime? sourceAt,
  }) : this(
         status: RiskQualityStatus.unsupported,
         source: source,
         reason: reason,
         observedAt: observedAt,
         sourceAt: sourceAt,
       );

  const RiskQuality.empty({String? source, String? reason})
    : this(status: RiskQualityStatus.empty, source: source, reason: reason);

  final RiskQualityStatus status;
  final String? source;
  final String? reason;
  final DateTime? observedAt;
  final DateTime? sourceAt;

  bool get isAvailable =>
      status == RiskQualityStatus.complete ||
      status == RiskQualityStatus.partial;

  bool get isComplete => status == RiskQualityStatus.complete;

  bool get isPartial => status == RiskQualityStatus.partial;

  bool get isUnavailable =>
      status == RiskQualityStatus.unavailable ||
      status == RiskQualityStatus.error ||
      status == RiskQualityStatus.unsupported ||
      status == RiskQualityStatus.empty;

  RiskQuality withStatus(RiskQualityStatus nextStatus, {String? nextReason}) {
    return RiskQuality(
      status: nextStatus,
      source: source,
      reason: nextReason ?? reason,
      observedAt: observedAt,
      sourceAt: sourceAt,
    );
  }
}

/// A nullable finite value with an explicit display unit and source quality.
class RiskMetricValue {
  const RiskMetricValue({
    required this.value,
    required this.unit,
    required this.quality,
    this.source,
    this.observedAt,
    this.sourceAt,
  });

  RiskMetricValue.unavailable({
    required String unit,
    String? source,
    String? reason,
    DateTime? observedAt,
    DateTime? sourceAt,
  }) : this(
         value: null,
         unit: unit,
         source: source,
         observedAt: observedAt,
         sourceAt: sourceAt,
         quality: RiskQuality.unavailable(
           source: source,
           reason: reason,
           observedAt: observedAt,
           sourceAt: sourceAt,
         ),
       );

  final double? value;
  final String unit;
  final RiskQuality quality;
  final String? source;
  final DateTime? observedAt;
  final DateTime? sourceAt;

  bool get isAvailable => value != null && quality.isAvailable;
}

typedef RiskValue = RiskMetricValue;
typedef RiskDataQuality = RiskQuality;

class RiskReason {
  const RiskReason({
    required this.factorId,
    required this.message,
    this.severity,
    this.observedValue,
    this.threshold,
    this.unit,
    this.window,
    this.observedAt,
    this.source,
    this.evidence,
  });

  final String factorId;
  final String message;
  final RiskSeverity? severity;
  final double? observedValue;
  final String? threshold;
  final String? unit;
  final String? window;
  final DateTime? observedAt;
  final String? source;
  final String? evidence;

  String get summary => message;
}

/// One component's lower-bound assessment.  A null state means that the
/// component had no usable numeric evidence; [partial] means at least one
/// required input was unavailable while another input was observed.
class RiskAssessment {
  const RiskAssessment({
    required this.state,
    required this.quality,
    this.reasons = const <RiskReason>[],
    this.missingReasons = const <String>[],
    this.label,
  });

  final RiskSeverity? state;
  final RiskQuality quality;
  final List<RiskReason> reasons;
  final List<String> missingReasons;
  final String? label;

  bool get available => state != null;
  bool get partial => quality.isPartial || missingReasons.isNotEmpty;
  bool get isUnavailable => state == null;
  String get displayLabel => state?.label ?? '- / Insufficient data';
}

enum RiskAccountMode { newMode, oldMode, unsupported }

extension RiskAccountModeX on RiskAccountMode {
  String get apiValue {
    switch (this) {
      case RiskAccountMode.newMode:
        return 'auto_transfers_ccy';
      case RiskAccountMode.oldMode:
        return 'automatic';
      case RiskAccountMode.unsupported:
        return 'unsupported';
    }
  }
}

enum RiskCollateralCurrency { base, quote, unsupported }

enum RiskEligibility {
  eligible,
  empty,
  unsupported,
  invalid,
  shortPosition,
  zeroPosition,
}

class RiskCostCoverage {
  const RiskCostCoverage({
    required this.complete,
    this.reason,
    this.ledgerComplete = false,
    this.sizeUnchanged = false,
    this.positionOpenedAt,
    this.coverageFrom,
    this.coverageTo,
    this.nonOverlapAt,
  });

  const RiskCostCoverage.unknown()
    : this(complete: false, reason: 'Lifetime cost attribution is incomplete');

  RiskCostCoverage.completeForPosition({
    DateTime? positionOpenedAt,
    DateTime? coverageFrom,
    DateTime? coverageTo,
    DateTime? nonOverlapAt,
  }) : this(
         complete: _hasValidTimestampedCoverage(
           positionOpenedAt,
           coverageFrom,
           coverageTo,
           nonOverlapAt,
         ),
         reason:
             _hasValidTimestampedCoverage(
               positionOpenedAt,
               coverageFrom,
               coverageTo,
               nonOverlapAt,
             )
             ? null
             : 'Timestamped ledger coverage must reach the non-overlap boundary',
         ledgerComplete: true,
         sizeUnchanged: true,
         positionOpenedAt: positionOpenedAt,
         coverageFrom: coverageFrom,
         coverageTo: coverageTo,
         nonOverlapAt: nonOverlapAt,
       );

  final bool complete;
  final String? reason;
  final bool ledgerComplete;
  final bool sizeUnchanged;
  final DateTime? positionOpenedAt;
  final DateTime? coverageFrom;
  final DateTime? coverageTo;
  final DateTime? nonOverlapAt;

  static bool _hasValidTimestampedCoverage(
    DateTime? opened,
    DateTime? from,
    DateTime? to,
    DateTime? boundary,
  ) {
    if (opened == null || from == null || to == null || boundary == null) {
      return false;
    }
    return !from.isAfter(opened) &&
        !opened.isAfter(to) &&
        !boundary.isBefore(opened) &&
        !to.isBefore(boundary);
  }

  bool get hasTimestampedCoverage {
    return _hasValidTimestampedCoverage(
      positionOpenedAt,
      coverageFrom,
      coverageTo,
      nonOverlapAt,
    );
  }

  bool get isVerifiedComplete =>
      complete && ledgerComplete && sizeUnchanged && hasTimestampedCoverage;
}

/// Actual interest records observed during the configured/local calendar day.
///
/// [knownSubtotal] remains useful when the day is only partially covered, but
/// [amount] is exposed as a paid/actual value only after the adapter proves the
/// complete day window.  A projected day is never represented by this type.
class RiskActualInterestToday {
  const RiskActualInterestToday({
    required this.amount,
    required this.knownSubtotal,
    required this.windowStart,
    required this.windowEnd,
    required this.quality,
    this.coverageComplete = false,
    this.observedAt,
    this.sourceAt,
    this.source,
  });

  final double? amount;
  final double knownSubtotal;
  final DateTime windowStart;
  final DateTime windowEnd;
  final RiskQuality quality;
  final bool coverageComplete;
  final DateTime? observedAt;
  final DateTime? sourceAt;
  final String? source;

  /// Alias used by callers that describe the field as accrued interest.
  double? get accruedAmount => amount;

  bool get isComplete =>
      coverageComplete && amount != null && quality.isComplete;
}

class RiskCostAttribution {
  const RiskCostAttribution({
    this.settledInterest,
    this.unbilledInterest,
    this.additionalActualCosts,
    this.actualInterestToday,
    this.coverage = const RiskCostCoverage.unknown(),
    this.observedAt,
    this.source,
  });

  final double? settledInterest;
  final double? unbilledInterest;
  final double? additionalActualCosts;
  final RiskActualInterestToday? actualInterestToday;
  final RiskCostCoverage coverage;
  final DateTime? observedAt;
  final String? source;

  RiskActualInterestToday? get accruedInterestToday => actualInterestToday;
  RiskActualInterestToday? get interestToday => actualInterestToday;

  double? get lifetimeInterest {
    final settled = settledInterest;
    final unbilled = unbilledInterest;
    // A lifetime sum is only meaningful once the caller has proved the
    // ledger/episode coverage and the rollover boundary for unbilled
    // interest.  The individual values remain available for the secondary
    // known-cost estimate and details.
    if (!coverage.isVerifiedComplete ||
        settled == null ||
        unbilled == null ||
        settled < 0 ||
        unbilled < 0) {
      return null;
    }
    final total = settled + unbilled;
    return total.isFinite && total >= 0 ? total : null;
  }

  double? get knownCosts {
    final interest = lifetimeInterest;
    final additional = additionalActualCosts;
    if (interest == null || additional == null || additional < 0) {
      return null;
    }
    final total = interest + additional;
    return total.isFinite && total >= 0 ? total : null;
  }
}

/// A normalized long isolated MARGIN position.  Its fields are nullable until
/// the adapter has proved units, currencies, and source quality.
class RiskPosition {
  const RiskPosition({
    required this.instrumentId,
    required this.mode,
    required this.collateralCurrency,
    this.instrumentType = 'MARGIN',
    this.positionSide = 'net',
    this.accountNamespace,
    this.positionId,
    this.createdAt,
    this.updatedAt,
    this.observedAt,
    this.baseCurrency,
    this.quoteCurrency = 'USDT',
    this.positionCurrency,
    this.accountCurrency,
    this.liabilityCurrency,
    this.rawQuantity,
    this.quantity,
    this.margin,
    this.markPrice,
    this.entryPrice,
    this.liquidationPrice,
    this.unrealizedPnl,
    this.reportedLeverage,
    this.marginRatio,
    this.maintenanceRequirement,
    this.reportedLiability,
    this.reportedInterest,
    this.baseBalance,
    this.quoteBalance,
    this.baseBorrowed,
    this.quoteBorrowed,
    this.baseInterest,
    this.quoteInterest,
    this.hourlyBorrowRate,
    this.entryFeeRate,
    this.exitFeeRate,
    this.costAttribution = const RiskCostAttribution(),
    this.quality = const RiskQuality.partial(
      reason: 'Position quality has not been assessed',
    ),
    this.eligibility = RiskEligibility.eligible,
    this.source,
  });

  final String instrumentId;
  final String instrumentType;
  final RiskAccountMode mode;
  final RiskCollateralCurrency collateralCurrency;
  final String positionSide;
  final String? accountNamespace;
  final String? positionId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? observedAt;
  final String? baseCurrency;
  final String quoteCurrency;
  final String? positionCurrency;
  final String? accountCurrency;
  final String? liabilityCurrency;

  final double? rawQuantity;
  final double? quantity;
  final double? margin;
  final double? markPrice;
  final double? entryPrice;
  final double? liquidationPrice;
  final double? unrealizedPnl;
  final double? reportedLeverage;
  final double? marginRatio;
  final double? maintenanceRequirement;
  final double? reportedLiability;
  final double? reportedInterest;
  final double? baseBalance;
  final double? quoteBalance;
  final double? baseBorrowed;
  final double? quoteBorrowed;
  final double? baseInterest;
  final double? quoteInterest;
  final double? hourlyBorrowRate;
  final double? entryFeeRate;
  final double? exitFeeRate;
  final RiskCostAttribution costAttribution;
  final RiskQuality quality;
  final RiskEligibility eligibility;
  final String? source;

  bool get isLong =>
      positionSide.toLowerCase() != 'short' &&
      positionSide.toLowerCase() != 'sell' &&
      (positionCurrency == null ||
          baseCurrency == null ||
          positionCurrency!.toUpperCase() == baseCurrency!.toUpperCase());

  bool get isEligible =>
      eligibility == RiskEligibility.eligible &&
      instrumentType.toUpperCase() == 'MARGIN' &&
      mode != RiskAccountMode.unsupported &&
      collateralCurrency != RiskCollateralCurrency.unsupported &&
      isLong;

  String get episodeKey {
    final namespace = accountNamespace;
    final id = positionId;
    final time = createdAt?.millisecondsSinceEpoch;
    if (namespace == null ||
        namespace.isEmpty ||
        id == null ||
        id.isEmpty ||
        time == null) {
      return '';
    }
    return '$namespace:$id:$time';
  }

  RiskPosition copyWith({
    RiskAccountMode? mode,
    RiskCollateralCurrency? collateralCurrency,
    double? quantity,
    double? markPrice,
    double? entryPrice,
    double? liquidationPrice,
    double? marginRatio,
    double? maintenanceRequirement,
    double? hourlyBorrowRate,
    double? entryFeeRate,
    double? exitFeeRate,
    RiskCostAttribution? costAttribution,
    RiskQuality? quality,
  }) {
    return RiskPosition(
      instrumentId: instrumentId,
      instrumentType: instrumentType,
      mode: mode ?? this.mode,
      collateralCurrency: collateralCurrency ?? this.collateralCurrency,
      positionSide: positionSide,
      accountNamespace: accountNamespace,
      positionId: positionId,
      createdAt: createdAt,
      updatedAt: updatedAt,
      observedAt: observedAt,
      baseCurrency: baseCurrency,
      quoteCurrency: quoteCurrency,
      positionCurrency: positionCurrency,
      accountCurrency: accountCurrency,
      liabilityCurrency: liabilityCurrency,
      rawQuantity: rawQuantity,
      quantity: quantity ?? this.quantity,
      margin: margin,
      markPrice: markPrice ?? this.markPrice,
      entryPrice: entryPrice ?? this.entryPrice,
      liquidationPrice: liquidationPrice ?? this.liquidationPrice,
      unrealizedPnl: unrealizedPnl,
      reportedLeverage: reportedLeverage,
      marginRatio: marginRatio ?? this.marginRatio,
      maintenanceRequirement:
          maintenanceRequirement ?? this.maintenanceRequirement,
      reportedLiability: reportedLiability,
      reportedInterest: reportedInterest,
      baseBalance: baseBalance,
      quoteBalance: quoteBalance,
      baseBorrowed: baseBorrowed,
      quoteBorrowed: quoteBorrowed,
      baseInterest: baseInterest,
      quoteInterest: quoteInterest,
      hourlyBorrowRate: hourlyBorrowRate ?? this.hourlyBorrowRate,
      entryFeeRate: entryFeeRate ?? this.entryFeeRate,
      exitFeeRate: exitFeeRate ?? this.exitFeeRate,
      costAttribution: costAttribution ?? this.costAttribution,
      quality: quality ?? this.quality,
      eligibility: eligibility,
      source: source,
    );
  }

  /// Apply an attribution produced by a verified ledger/history adapter.  The
  /// engine checks the complete coverage proof before exposing True Exit;
  /// partial evidence remains useful for the known-cost estimate and details.
  RiskPosition withCostAttribution(RiskCostAttribution attribution) {
    return copyWith(costAttribution: attribution);
  }
}

class RiskPositionSelection {
  const RiskPositionSelection({
    required this.status,
    required this.quality,
    this.position,
    this.candidates = const <RiskPosition>[],
    this.selectionChanged = false,
    this.message,
  });

  final RiskEligibility status;
  final RiskQuality quality;
  final RiskPosition? position;
  final List<RiskPosition> candidates;
  final bool selectionChanged;
  final String? message;

  bool get isEmpty => status == RiskEligibility.empty;
  bool get isError => quality.status == RiskQualityStatus.error;
  bool get isUnsupported => status == RiskEligibility.unsupported;
}

/// Typed market values supplied by the pure market adapter. Position math
/// remains independent from the public market sources.
class RiskMarketInput {
  const RiskMarketInput({
    this.state,
    this.complete = false,
    this.dailyVolatility,
    this.reasons = const <RiskReason>[],
    this.missingReasons = const <String>[],
    this.support,
    this.resistance,
    this.source,
    this.observedAt,
    this.sourceAt,
    this.marketContextLabel = 'OKX perpetual context',
    this.assetInstrument,
    this.btcInstrument,
    this.derivativesInstrument,
    this.volatilityLabel,
    this.assetStructureLabel,
    this.btcStructureLabel,
    this.volumePressureLabel,
    this.fundingLabel,
    this.openInterestLabel,
    this.normalizedFunding8h,
    this.fundingIntervalHours,
    this.openInterestChange,
    this.marketPriceChange,
    this.fundingQuality,
    this.openInterestQuality,
    this.marketPoints = 0,
    this.assetPoints = 0,
    this.fundingPoints = 0,
    this.openInterestPoints = 0,
  });

  final RiskSeverity? state;
  final bool complete;
  final double? dailyVolatility;
  final List<RiskReason> reasons;
  final List<String> missingReasons;
  final double? support;
  final double? resistance;
  final String? source;
  final DateTime? observedAt;
  final DateTime? sourceAt;
  final String marketContextLabel;
  final String? assetInstrument;
  final String? btcInstrument;
  final String? derivativesInstrument;
  final String? volatilityLabel;
  final String? assetStructureLabel;
  final String? btcStructureLabel;
  final String? volumePressureLabel;
  final String? fundingLabel;
  final String? openInterestLabel;
  final double? normalizedFunding8h;
  final double? fundingIntervalHours;
  final double? openInterestChange;
  final double? marketPriceChange;
  final RiskQuality? fundingQuality;
  final RiskQuality? openInterestQuality;
  final int marketPoints;
  final int assetPoints;
  final int fundingPoints;
  final int openInterestPoints;

  RiskAssessment get assessment => RiskAssessment(
    state: state,
    quality: complete && missingReasons.isEmpty
        ? RiskQuality.complete(source: source, observedAt: observedAt)
        : RiskQuality.partial(
            source: source,
            observedAt: observedAt,
            reason: missingReasons.join('; '),
          ),
    reasons: reasons,
    missingReasons: missingReasons,
  );
}

typedef MarketRiskInput = RiskMarketInput;

class RiskMetrics {
  const RiskMetrics({
    required this.quantity,
    required this.markPrice,
    required this.entryPrice,
    required this.liquidationPrice,
    required this.margin,
    required this.equity,
    required this.debt,
    required this.principalDebt,
    required this.tradeNotional,
    required this.grossAssetExposure,
    required this.effectiveLeverage,
    required this.buffer,
    required this.marginRatio,
    required this.maintenanceRequirement,
    required this.tradeSensitivityPerPoint,
    required this.tradeSensitivityPerPercent,
    required this.equitySensitivityPerPoint,
    required this.equitySensitivityPerPercent,
    required this.distanceToEntry,
    this.distanceToTrueExit = const RiskMetricValue(
      value: null,
      unit: 'fraction',
      quality: RiskQuality.unavailable(reason: 'True Exit unavailable'),
    ),
    this.actualInterestToday = const RiskMetricValue(
      value: null,
      unit: 'USDT/today',
      quality: RiskQuality.unavailable(
        reason: 'Actual interest accrued today unavailable',
      ),
    ),
    this.knownInterestToday = const RiskMetricValue(
      value: null,
      unit: 'USDT/today',
      quality: RiskQuality.unavailable(
        reason: 'Known interest subtotal for today unavailable',
      ),
    ),
    required this.trueExitPrice,
    this.projectedTrueExitPrice = const RiskMetricValue(
      value: null,
      unit: 'USDT',
      quality: RiskQuality.unavailable(
        reason: 'Projected True Exit unavailable or cost observation stale',
      ),
    ),
    required this.knownCostExitPrice,
    required this.holdingCostPerDay,
    required this.holdingCost7d,
    required this.holdingCost30d,
    required this.recoveryDistance,
    required this.holdingBurden,
    required this.tradePnl,
  });

  final RiskMetricValue quantity;
  final RiskMetricValue markPrice;
  final RiskMetricValue entryPrice;
  final RiskMetricValue liquidationPrice;
  final RiskMetricValue margin;
  final RiskMetricValue equity;
  final RiskMetricValue debt;
  final RiskMetricValue principalDebt;
  final RiskMetricValue tradeNotional;
  final RiskMetricValue grossAssetExposure;
  final RiskMetricValue effectiveLeverage;
  final RiskMetricValue buffer;
  final RiskMetricValue marginRatio;
  final RiskMetricValue maintenanceRequirement;
  final RiskMetricValue tradeSensitivityPerPoint;
  final RiskMetricValue tradeSensitivityPerPercent;
  final RiskMetricValue equitySensitivityPerPoint;
  final RiskMetricValue equitySensitivityPerPercent;
  final RiskMetricValue distanceToEntry;
  final RiskMetricValue distanceToTrueExit;
  final RiskMetricValue actualInterestToday;
  final RiskMetricValue knownInterestToday;
  final RiskMetricValue trueExitPrice;
  final RiskMetricValue projectedTrueExitPrice;
  final RiskMetricValue knownCostExitPrice;
  final RiskMetricValue holdingCostPerDay;
  final RiskMetricValue holdingCost7d;
  final RiskMetricValue holdingCost30d;
  final RiskMetricValue recoveryDistance;
  final RiskMetricValue holdingBurden;
  final RiskMetricValue tradePnl;

  RiskMetricValue get accruedInterestToday => actualInterestToday;
  RiskMetricValue get knownAccruedInterestToday => knownInterestToday;
  RiskMetricValue get projectedTrueExit => projectedTrueExitPrice;
}

class RiskStressScenario {
  const RiskStressScenario({
    required this.label,
    required this.price,
    this.percentageChange,
    this.tradePnl,
    this.equity,
    this.effectiveLeverage,
    this.buffer,
    this.marginRatio,
    this.currentMarginRatio,
    this.marketFrozen = true,
    this.marketContextLabel = 'Frozen market context',
    this.positionState,
    this.overallState,
    this.partial = false,
    this.hypothetical = true,
    this.reasons = const <RiskReason>[],
  });

  final String label;
  final double price;
  final double? percentageChange;
  final double? tradePnl;
  final double? equity;
  final double? effectiveLeverage;
  final double? buffer;

  /// Future OKX ratio is intentionally unavailable for frozen-price stress.
  final double? marginRatio;

  /// Current observed ratio retained only as a hard-floor input.
  final double? currentMarginRatio;
  final bool marketFrozen;
  final String marketContextLabel;
  final RiskSeverity? positionState;
  final RiskSeverity? overallState;
  final bool partial;
  final bool hypothetical;
  final List<RiskReason> reasons;

  bool get atOrBeyondLiquidation =>
      positionState == RiskSeverity.critical &&
      reasons.any((reason) => reason.factorId == 'liquidation-floor');
}

class RiskPriceMapLevel {
  const RiskPriceMapLevel({required this.price, required this.labels});

  final double price;
  final List<String> labels;
}

/// A caller supplied map level, such as a user zone or a support/resistance
/// observation.  It is context only; the engine never turns it into an
/// executable action.
class RiskPriceLevelInput {
  const RiskPriceLevelInput({required this.price, required this.label});

  final double price;
  final String label;
}

class RiskEvaluation {
  const RiskEvaluation({
    required this.position,
    required this.metrics,
    required this.positionAssessment,
    required this.marketAssessment,
    required this.recoveryAssessment,
    required this.overallState,
    required this.quality,
    required this.reasons,
    required this.stressScenarios,
    required this.priceMap,
    required this.evaluatedAt,
    this.policyVersion = 'risk.v1',
    this.missingReasons = const <String>[],
    this.exchangePnlBasis,
  });

  final RiskPosition position;
  final RiskMetrics metrics;
  final RiskAssessment positionAssessment;
  final RiskAssessment marketAssessment;
  final RiskAssessment recoveryAssessment;
  final RiskSeverity? overallState;
  final RiskQuality quality;
  final List<RiskReason> reasons;
  final List<RiskStressScenario> stressScenarios;
  final List<RiskPriceMapLevel> priceMap;
  final DateTime evaluatedAt;
  final String policyVersion;
  final List<String> missingReasons;
  final String? exchangePnlBasis;

  RiskSeverity? get overallRisk => overallState;
  RiskSeverity? get positionRisk => positionAssessment.state;
  RiskSeverity? get marketRisk => marketAssessment.state;
  RiskSeverity? get recoveryRisk => recoveryAssessment.state;
  bool get partial => quality.isPartial || missingReasons.isNotEmpty;

  double? get quantity => metrics.quantity.value;
  double? get markPrice => metrics.markPrice.value;
  double? get entryPrice => metrics.entryPrice.value;
  double? get liquidationPrice => metrics.liquidationPrice.value;
  double? get equity => metrics.equity.value;
  double? get debt => metrics.debt.value;
  double? get effectiveLeverage => metrics.effectiveLeverage.value;
  double? get buffer => metrics.buffer.value;
  double? get trueExitPrice => metrics.trueExitPrice.value;
  double? get projectedTrueExitPrice => metrics.projectedTrueExitPrice.value;
  double? get actualInterestToday => metrics.actualInterestToday.value;
  double? get knownActualInterestToday =>
      position.costAttribution.actualInterestToday?.knownSubtotal;
  RiskMetricValue get knownActualInterestTodayMetric =>
      metrics.knownInterestToday;
  double? get distanceToTrueExit => metrics.distanceToTrueExit.value;
  double? get holdingCostPerDay => metrics.holdingCostPerDay.value;
  double? get holdingCost30d => metrics.holdingCost30d.value;
  double? get recoveryDistance => metrics.recoveryDistance.value;
  double? get holdingBurden => metrics.holdingBurden.value;
}

typedef RiskSnapshot = RiskEvaluation;
