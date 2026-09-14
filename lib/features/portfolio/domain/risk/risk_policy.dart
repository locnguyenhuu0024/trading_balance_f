import 'risk_models.dart';

/// Versioned deterministic thresholds for the P01 position, recovery, and
/// stress calculations.  Values are fractions internally (for example 0.30
/// represents a 30% buffer and 1.50 represents a 150% OKX ratio).
class RiskPolicy {
  const RiskPolicy({
    this.version = 'risk.v1',
    this.bufferCritical = 0.20,
    this.bufferHigh = 0.30,
    this.bufferWatch = 0.45,
    this.leverageWatch = 3.0,
    this.leverageHigh = 4.0,
    this.leverageCritical = 6.0,
    this.marginRatioCritical = 1.10,
    this.marginRatioHigh = 1.50,
    this.marginRatioWatch = 3.0,
    this.bufferVolatilityHigh = 3.0,
    this.bufferVolatilityWatch = 4.0,
    this.recoveryDistanceWatch = 0.10,
    this.recoveryDistanceHigh = 0.20,
    this.holdingBurdenWatch = 0.01,
    this.holdingBurdenHigh = 0.03,
    this.stressChanges = const <double>[0, -0.05, -0.10, -0.15, -0.20],
    this.priceDeduplicationTolerance = 1e-9,
  });

  factory RiskPolicy.defaults() => const RiskPolicy();

  final String version;

  /// Position buffer boundaries, as fractions of mark price.
  final double bufferCritical;
  final double bufferHigh;
  final double bufferWatch;

  /// Effective leverage boundaries in x.
  final double leverageWatch;
  final double leverageHigh;
  final double leverageCritical;

  /// Raw OKX maintenance ratio boundaries.  1.10 displays as 110%.
  final double marginRatioCritical;
  final double marginRatioHigh;
  final double marginRatioWatch;

  /// Buffer divided by daily volatility boundaries.
  final double bufferVolatilityHigh;
  final double bufferVolatilityWatch;

  final double recoveryDistanceWatch;
  final double recoveryDistanceHigh;
  final double holdingBurdenWatch;
  final double holdingBurdenHigh;

  /// Proportional stress rows; callers may append positive custom prices.
  final List<double> stressChanges;
  final double priceDeduplicationTolerance;

  // Aliases make threshold intent clear at call sites and keep settings/UI
  // adapters independent from the compact persisted field names.
  double get bufferWatchMinimum => bufferHigh;
  double get bufferHighMinimum => bufferCritical;
  double get bufferNormalMinimum => bufferWatch;
  double get leverageNormalMaximum => leverageWatch;
  double get leverageWatchMaximum => leverageHigh;
  double get leverageHighMaximum => leverageCritical;
  double get marginRatioNormalMinimum => marginRatioWatch;
  double get marginRatioWatchMinimum => marginRatioHigh;
  double get marginRatioHighMinimum => marginRatioCritical;

  List<String> validate() {
    final errors = <String>[];
    void finite(String name, double value) {
      if (!value.isFinite) errors.add('$name must be finite');
    }

    finite('bufferCritical', bufferCritical);
    finite('bufferHigh', bufferHigh);
    finite('bufferWatch', bufferWatch);
    if (bufferCritical < 0 ||
        bufferCritical >= bufferHigh ||
        bufferHigh >= bufferWatch ||
        bufferWatch > 1) {
      errors.add(
        'buffer boundaries must satisfy 0 <= critical < high < watch <= 1',
      );
    }

    finite('leverageWatch', leverageWatch);
    finite('leverageHigh', leverageHigh);
    finite('leverageCritical', leverageCritical);
    if (leverageWatch <= 0 ||
        leverageWatch >= leverageHigh ||
        leverageHigh >= leverageCritical) {
      errors.add(
        'leverage boundaries must satisfy 0 < watch < high < critical',
      );
    }

    finite('marginRatioCritical', marginRatioCritical);
    finite('marginRatioHigh', marginRatioHigh);
    finite('marginRatioWatch', marginRatioWatch);
    if (marginRatioCritical <= 0 ||
        marginRatioCritical >= marginRatioHigh ||
        marginRatioHigh >= marginRatioWatch) {
      errors.add(
        'margin-ratio boundaries must satisfy 0 < critical < high < watch',
      );
    }

    finite('bufferVolatilityHigh', bufferVolatilityHigh);
    finite('bufferVolatilityWatch', bufferVolatilityWatch);
    if (bufferVolatilityHigh <= 0 ||
        bufferVolatilityHigh >= bufferVolatilityWatch) {
      errors.add('buffer/volatility boundaries must satisfy 0 < high < watch');
    }

    finite('recoveryDistanceWatch', recoveryDistanceWatch);
    finite('recoveryDistanceHigh', recoveryDistanceHigh);
    if (recoveryDistanceWatch < 0 ||
        recoveryDistanceWatch >= recoveryDistanceHigh) {
      errors.add('recovery-distance boundaries must satisfy 0 <= watch < high');
    }

    finite('holdingBurdenWatch', holdingBurdenWatch);
    finite('holdingBurdenHigh', holdingBurdenHigh);
    if (holdingBurdenWatch < 0 || holdingBurdenWatch >= holdingBurdenHigh) {
      errors.add('holding-burden boundaries must satisfy 0 <= watch < high');
    }

    finite('priceDeduplicationTolerance', priceDeduplicationTolerance);
    if (priceDeduplicationTolerance < 0) {
      errors.add('priceDeduplicationTolerance must be non-negative');
    }
    if (stressChanges.isEmpty) errors.add('stressChanges must not be empty');
    for (var index = 0; index < stressChanges.length; index++) {
      final change = stressChanges[index];
      if (!change.isFinite || change <= -1) {
        errors.add(
          'stressChanges[$index] must be finite and greater than -100%',
        );
      }
    }
    return List.unmodifiable(errors);
  }

  bool get isValid => validate().isEmpty;

  void requireValid() {
    final errors = validate();
    if (errors.isNotEmpty) {
      throw ArgumentError.value(errors.join('; '), 'policy');
    }
  }

  RiskPolicy copyWith({
    String? version,
    double? bufferCritical,
    double? bufferHigh,
    double? bufferWatch,
    double? leverageWatch,
    double? leverageHigh,
    double? leverageCritical,
    double? marginRatioCritical,
    double? marginRatioHigh,
    double? marginRatioWatch,
    double? bufferVolatilityHigh,
    double? bufferVolatilityWatch,
    double? recoveryDistanceWatch,
    double? recoveryDistanceHigh,
    double? holdingBurdenWatch,
    double? holdingBurdenHigh,
    List<double>? stressChanges,
    double? priceDeduplicationTolerance,
  }) {
    return RiskPolicy(
      version: version ?? this.version,
      bufferCritical: bufferCritical ?? this.bufferCritical,
      bufferHigh: bufferHigh ?? this.bufferHigh,
      bufferWatch: bufferWatch ?? this.bufferWatch,
      leverageWatch: leverageWatch ?? this.leverageWatch,
      leverageHigh: leverageHigh ?? this.leverageHigh,
      leverageCritical: leverageCritical ?? this.leverageCritical,
      marginRatioCritical: marginRatioCritical ?? this.marginRatioCritical,
      marginRatioHigh: marginRatioHigh ?? this.marginRatioHigh,
      marginRatioWatch: marginRatioWatch ?? this.marginRatioWatch,
      bufferVolatilityHigh: bufferVolatilityHigh ?? this.bufferVolatilityHigh,
      bufferVolatilityWatch:
          bufferVolatilityWatch ?? this.bufferVolatilityWatch,
      recoveryDistanceWatch:
          recoveryDistanceWatch ?? this.recoveryDistanceWatch,
      recoveryDistanceHigh: recoveryDistanceHigh ?? this.recoveryDistanceHigh,
      holdingBurdenWatch: holdingBurdenWatch ?? this.holdingBurdenWatch,
      holdingBurdenHigh: holdingBurdenHigh ?? this.holdingBurdenHigh,
      stressChanges: stressChanges ?? this.stressChanges,
      priceDeduplicationTolerance:
          priceDeduplicationTolerance ?? this.priceDeduplicationTolerance,
    );
  }

  RiskSeverity classifyBuffer(double value) {
    if (value < bufferCritical) return RiskSeverity.critical;
    if (value < bufferHigh) return RiskSeverity.high;
    if (value <= bufferWatch) return RiskSeverity.watch;
    return RiskSeverity.normal;
  }

  RiskSeverity classifyLeverage(double value) {
    if (value >= leverageCritical) return RiskSeverity.critical;
    if (value >= leverageHigh) return RiskSeverity.high;
    if (value >= leverageWatch) return RiskSeverity.watch;
    return RiskSeverity.normal;
  }

  RiskSeverity classifyMarginRatio(double value) {
    if (value <= marginRatioCritical) return RiskSeverity.critical;
    if (value <= marginRatioHigh) return RiskSeverity.high;
    if (value <= marginRatioWatch) return RiskSeverity.watch;
    return RiskSeverity.normal;
  }

  RiskSeverity classifyRecoveryDistance(double value) {
    // Ratios such as T/P-1 can land a few ulps above a configured boundary
    // even when the source prices derive the exact boundary. Keep the
    // documented inclusive endpoints stable under normal floating-point
    // arithmetic without changing materially larger values.
    const epsilon = 1e-12;
    if (value > recoveryDistanceHigh + epsilon) return RiskSeverity.high;
    if (value > recoveryDistanceWatch + epsilon) return RiskSeverity.watch;
    return RiskSeverity.normal;
  }

  RiskSeverity classifyHoldingBurden(double value) {
    const epsilon = 1e-12;
    if (value >= holdingBurdenHigh - epsilon) return RiskSeverity.high;
    if (value >= holdingBurdenWatch - epsilon) return RiskSeverity.watch;
    return RiskSeverity.normal;
  }

  RiskSeverity classifyBufferVolatility(double value) {
    if (value < bufferVolatilityHigh) return RiskSeverity.high;
    if (value < bufferVolatilityWatch) return RiskSeverity.watch;
    return RiskSeverity.normal;
  }
}

/// Result used by settings editors before persisting a policy.
class RiskPolicyValidation {
  const RiskPolicyValidation(this.errors);

  final List<String> errors;
  bool get isValid => errors.isEmpty;
}
