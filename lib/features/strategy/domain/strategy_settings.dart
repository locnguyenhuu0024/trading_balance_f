class StrategyJevScreeningThresholds {
  const StrategyJevScreeningThresholds({
    required this.minStructuralQuality,
    required this.minEntrySuitabilityProbability,
    required this.maxFailureRiskProbability,
  });

  static const defaults = StrategyJevScreeningThresholds(
    minStructuralQuality: 4,
    minEntrySuitabilityProbability: 0.6,
    maxFailureRiskProbability: 0.4,
  );

  final int minStructuralQuality;
  final double minEntrySuitabilityProbability;
  final double maxFailureRiskProbability;

  bool get isValid =>
      minStructuralQuality >= 0 &&
      minStructuralQuality <= 5 &&
      minEntrySuitabilityProbability.isFinite &&
      minEntrySuitabilityProbability >= 0 &&
      minEntrySuitabilityProbability <= 1 &&
      maxFailureRiskProbability.isFinite &&
      maxFailureRiskProbability >= 0 &&
      maxFailureRiskProbability <= 1;

  Map<String, Object> toJson() => {
    'minStructuralQuality': minStructuralQuality,
    'minEntrySuitabilityProbability': minEntrySuitabilityProbability,
    'maxFailureRiskProbability': maxFailureRiskProbability,
  };

  static StrategyJevScreeningThresholds? tryParseApi(Object? value) {
    final map = _strictStringMap(value);
    if (map == null ||
        map.length != 3 ||
        !map.containsKey('minStructuralQuality') ||
        !map.containsKey('minEntrySuitabilityProbability') ||
        !map.containsKey('maxFailureRiskProbability')) {
      return null;
    }
    final quality = map['minStructuralQuality'];
    final suitability = map['minEntrySuitabilityProbability'];
    final risk = map['maxFailureRiskProbability'];
    if (quality is! int || suitability is! num || risk is! num) {
      return null;
    }
    final parsed = StrategyJevScreeningThresholds(
      minStructuralQuality: quality,
      minEntrySuitabilityProbability: suitability.toDouble(),
      maxFailureRiskProbability: risk.toDouble(),
    );
    return parsed.isValid ? parsed : null;
  }

  /// Snapshot v1 historically encoded the integer quality as either 4 or 4.0.
  static StrategyJevScreeningThresholds? tryParseSnapshot(Object? value) {
    final map = _strictStringMap(value);
    if (map == null) return null;
    final quality = map['minStructuralQuality'];
    final suitability = map['minEntrySuitabilityProbability'];
    final risk = map['maxFailureRiskProbability'];
    if (quality is! num || suitability is! num || risk is! num) {
      return null;
    }
    final qualityNumber = quality.toDouble();
    if (!qualityNumber.isFinite ||
        qualityNumber != qualityNumber.roundToDouble()) {
      return null;
    }
    final parsed = StrategyJevScreeningThresholds(
      minStructuralQuality: qualityNumber.toInt(),
      minEntrySuitabilityProbability: suitability.toDouble(),
      maxFailureRiskProbability: risk.toDouble(),
    );
    return parsed.isValid ? parsed : null;
  }

  static double? parsePercentage(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    if (!RegExp(r'^(?:\d+(?:\.\d*)?|\.\d+)$').hasMatch(normalized)) {
      return null;
    }
    final parsed = double.tryParse(normalized);
    if (parsed == null || !parsed.isFinite || parsed < 0 || parsed > 100) {
      return null;
    }
    return parsed;
  }

  @override
  bool operator ==(Object other) =>
      other is StrategyJevScreeningThresholds &&
      other.minStructuralQuality == minStructuralQuality &&
      other.minEntrySuitabilityProbability == minEntrySuitabilityProbability &&
      other.maxFailureRiskProbability == maxFailureRiskProbability;

  @override
  int get hashCode => Object.hash(
    minStructuralQuality,
    minEntrySuitabilityProbability,
    maxFailureRiskProbability,
  );
}

class StrategySettings {
  const StrategySettings({
    required this.limitOrderSubmissionMode,
    required this.jevScreeningThresholds,
  });

  final String limitOrderSubmissionMode;
  final StrategyJevScreeningThresholds jevScreeningThresholds;

  bool get isValid =>
      const {'sequential', 'batch'}.contains(limitOrderSubmissionMode) &&
      jevScreeningThresholds.isValid;

  Map<String, Object> toJson() => {
    'limitOrderSubmissionMode': limitOrderSubmissionMode,
    'jevScreeningThresholds': jevScreeningThresholds.toJson(),
  };

  static StrategySettings? tryParse(Object? value) {
    final map = _strictStringMap(value);
    if (map == null) return null;
    final mode = map['limitOrderSubmissionMode'];
    final thresholds = StrategyJevScreeningThresholds.tryParseApi(
      map['jevScreeningThresholds'],
    );
    if (mode is! String || thresholds == null) return null;
    final parsed = StrategySettings(
      limitOrderSubmissionMode: mode,
      jevScreeningThresholds: thresholds,
    );
    return parsed.isValid ? parsed : null;
  }

  @override
  bool operator ==(Object other) =>
      other is StrategySettings &&
      other.limitOrderSubmissionMode == limitOrderSubmissionMode &&
      other.jevScreeningThresholds == jevScreeningThresholds;

  @override
  int get hashCode =>
      Object.hash(limitOrderSubmissionMode, jevScreeningThresholds);
}

Map<String, dynamic>? _strictStringMap(Object? value) =>
    value is Map && value.keys.every((key) => key is String)
    ? Map<String, dynamic>.from(value)
    : null;
