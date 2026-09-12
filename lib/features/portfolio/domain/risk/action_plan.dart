import 'risk_models.dart';
import 'risk_policy.dart';

/// User-selectable values that can be compared by a local action rule.
enum RiskPlanMetric {
  markPrice,
  buffer,
  effectiveLeverage,
  totalDebt,
  dailyHoldingCost,

  /// Compares the observed mark price with the current verified True Exit.
  /// It never stores a numeric threshold.
  priceVsTrueExit,

  /// Legacy persisted name. New rules must use [priceVsTrueExit].
  trueExitPrice,
}

/// Comparisons supported by the plan editor.  There is deliberately no free
/// form expression parser: a rule is data that can be validated and audited.
enum RiskPlanComparison {
  lessThan,
  lessThanOrEqual,
  greaterThan,
  greaterThanOrEqual,
  betweenInclusive,
}

enum RiskRuleState { active, inactive, unknown }

String riskPlanMetricName(RiskPlanMetric metric) {
  switch (metric) {
    case RiskPlanMetric.markPrice:
      return 'markPrice';
    case RiskPlanMetric.buffer:
      return 'buffer';
    case RiskPlanMetric.effectiveLeverage:
      return 'effectiveLeverage';
    case RiskPlanMetric.totalDebt:
      return 'totalDebt';
    case RiskPlanMetric.dailyHoldingCost:
      return 'dailyHoldingCost';
    case RiskPlanMetric.priceVsTrueExit:
      return 'priceVsTrueExit';
    case RiskPlanMetric.trueExitPrice:
      return 'trueExitPrice';
  }
}

RiskPlanMetric riskPlanMetricFromName(Object? value) {
  final text = value?.toString();
  return RiskPlanMetric.values.firstWhere(
    (metric) => riskPlanMetricName(metric) == text,
    orElse: () => throw FormatException('Unknown risk plan metric: $value'),
  );
}

String riskPlanComparisonName(RiskPlanComparison comparison) {
  switch (comparison) {
    case RiskPlanComparison.lessThan:
      return 'lessThan';
    case RiskPlanComparison.lessThanOrEqual:
      return 'lessThanOrEqual';
    case RiskPlanComparison.greaterThan:
      return 'greaterThan';
    case RiskPlanComparison.greaterThanOrEqual:
      return 'greaterThanOrEqual';
    case RiskPlanComparison.betweenInclusive:
      return 'betweenInclusive';
  }
}

RiskPlanComparison riskPlanComparisonFromName(Object? value) {
  final text = value?.toString();
  return RiskPlanComparison.values.firstWhere(
    (comparison) => riskPlanComparisonName(comparison) == text,
    orElse: () => throw FormatException('Unknown risk plan comparison: $value'),
  );
}

String riskRuleStateName(RiskRuleState state) {
  switch (state) {
    case RiskRuleState.active:
      return 'active';
    case RiskRuleState.inactive:
      return 'inactive';
    case RiskRuleState.unknown:
      return 'unknown';
  }
}

/// One user-authored rule.  [threshold] is the lower/single threshold and
/// [upperThreshold] is required only for inclusive ranges.
class RiskRule {
  const RiskRule({
    required this.id,
    required this.episodeKey,
    required this.metric,
    required this.comparison,
    this.threshold,
    this.upperThreshold,
    this.enabled = true,
    this.title,
    this.label,
    this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String episodeKey;
  final bool enabled;
  final RiskPlanMetric metric;
  final RiskPlanComparison comparison;
  final double? threshold;
  final double? upperThreshold;
  final String? title;
  final String? label;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get displayLabel {
    for (final candidate in <String?>[title, label]) {
      final text = candidate?.trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return '';
  }

  List<String> validate() {
    final errors = <String>[];
    final trimmedId = id.trim();
    if (trimmedId.isEmpty) errors.add('Rule id is required');
    if (episodeKey.trim().isEmpty) errors.add('Rule episodeKey is required');
    if (displayLabel.isEmpty || displayLabel.length > 80) {
      errors.add('Rule label must contain 1 to 80 characters');
    }
    if (note != null && (note!.trim().isEmpty || note!.length > 300)) {
      errors.add('Rule note must contain 1 to 300 characters when provided');
    }
    if (updatedAt.isBefore(createdAt)) {
      errors.add('Rule updatedAt cannot precede createdAt');
    }
    if (metric == RiskPlanMetric.priceVsTrueExit) {
      if (comparison != RiskPlanComparison.lessThan &&
          comparison != RiskPlanComparison.greaterThan) {
        errors.add('priceVsTrueExit supports only above/below comparisons');
      }
      if (threshold != null || upperThreshold != null) {
        errors.add('priceVsTrueExit does not accept numeric thresholds');
      }
      return List.unmodifiable(errors);
    }
    if (metric == RiskPlanMetric.trueExitPrice) {
      errors.add('trueExitPrice is legacy; use priceVsTrueExit');
      return List.unmodifiable(errors);
    }
    if (comparison == RiskPlanComparison.betweenInclusive) {
      if (!_finite(threshold) || !_finite(upperThreshold)) {
        errors.add('Inclusive range requires two finite thresholds');
      } else if (upperThreshold! < threshold!) {
        errors.add('Inclusive range thresholds must be ordered');
      }
    } else if (!_finite(threshold)) {
      errors.add('Rule threshold must be finite');
    } else if (metric != RiskPlanMetric.buffer && threshold! <= 0) {
      errors.add('Rule threshold must be finite and positive');
    }

    for (final value in <double?>[threshold, upperThreshold]) {
      if (value != null && !value.isFinite) {
        errors.add('Rule thresholds must be finite');
      }
    }
    if (metric == RiskPlanMetric.buffer) {
      for (final value in <double?>[threshold, upperThreshold]) {
        if (value != null && (value < 0 || value > 1)) {
          errors.add('Buffer thresholds must be between 0% and 100%');
        }
      }
    } else {
      for (final value in <double?>[threshold, upperThreshold]) {
        if (value != null && value <= 0) {
          errors.add('Rule thresholds must be finite and positive');
        }
      }
    }
    if (comparison != RiskPlanComparison.betweenInclusive &&
        upperThreshold != null) {
      errors.add('Upper threshold is only valid for inclusive ranges');
    }
    return List.unmodifiable(errors);
  }

  bool get isValid => validate().isEmpty;

  RiskRule copyWith({
    bool? enabled,
    RiskPlanMetric? metric,
    RiskPlanComparison? comparison,
    double? threshold,
    double? upperThreshold,
    String? title,
    String? label,
    String? note,
    DateTime? updatedAt,
  }) {
    return RiskRule(
      id: id,
      episodeKey: episodeKey,
      enabled: enabled ?? this.enabled,
      metric: metric ?? this.metric,
      comparison: comparison ?? this.comparison,
      threshold: threshold ?? this.threshold,
      upperThreshold: upperThreshold ?? this.upperThreshold,
      title: title ?? this.title,
      label: label ?? this.label,
      note: note ?? this.note,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'episodeKey': episodeKey,
    'enabled': enabled,
    'metric': riskPlanMetricName(metric),
    'comparison': riskPlanComparisonName(comparison),
    'threshold': threshold,
    'upperThreshold': upperThreshold,
    'title': title,
    'label': label,
    'note': note,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory RiskRule.fromJson(Map<String, dynamic> json) {
    final rule = RiskRule(
      id: _requiredString(json, 'id'),
      episodeKey: _requiredString(json, 'episodeKey'),
      enabled: _requiredBool(json, 'enabled'),
      metric: riskPlanMetricFromName(json['metric']),
      comparison: riskPlanComparisonFromName(json['comparison']),
      threshold: _optionalDouble(json['threshold']),
      upperThreshold: _optionalDouble(json['upperThreshold']),
      title: _optionalString(json['title']),
      label: _optionalString(json['label']),
      note: _optionalString(json['note']),
      createdAt: _requiredDate(json, 'createdAt'),
      updatedAt: _requiredDate(json, 'updatedAt'),
    );
    final errors = rule.validate();
    if (errors.isNotEmpty) throw FormatException(errors.join('; '));
    return rule;
  }
}

typedef RiskPlanRule = RiskRule;

/// A user zone is an inclusive price interval.  Enter and exit are both
/// evaluated from mark price; the interval is never an executable action.
class RiskZone {
  const RiskZone({
    required this.id,
    required this.episodeKey,
    required this.title,
    required this.lowerPrice,
    required this.upperPrice,
    this.enabled = true,
    this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String episodeKey;
  final String title;
  final double lowerPrice;
  final double upperPrice;
  final bool enabled;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  double get entryPrice => lowerPrice;
  double get exitPrice => upperPrice;

  List<String> validate() {
    final errors = <String>[];
    final trimmed = title.trim();
    if (id.trim().isEmpty) errors.add('Zone id is required');
    if (episodeKey.trim().isEmpty) errors.add('Zone episodeKey is required');
    if (trimmed.isEmpty || trimmed.length > 80) {
      errors.add('Zone title must contain 1 to 80 characters');
    }
    if (!lowerPrice.isFinite ||
        !upperPrice.isFinite ||
        lowerPrice <= 0 ||
        upperPrice <= 0 ||
        lowerPrice > upperPrice) {
      errors.add('Zone prices must be finite, positive and ordered');
    }
    if (note != null && (note!.trim().isEmpty || note!.length > 300)) {
      errors.add('Zone note must contain 1 to 300 characters when provided');
    }
    if (updatedAt.isBefore(createdAt)) {
      errors.add('Zone updatedAt cannot precede createdAt');
    }
    return List.unmodifiable(errors);
  }

  bool get isValid => validate().isEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'episodeKey': episodeKey,
    'title': title,
    'lowerPrice': lowerPrice,
    'upperPrice': upperPrice,
    'enabled': enabled,
    'note': note,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory RiskZone.fromJson(Map<String, dynamic> json) {
    final zone = RiskZone(
      id: _requiredString(json, 'id'),
      episodeKey: _requiredString(json, 'episodeKey'),
      title: _requiredString(json, 'title'),
      lowerPrice: _requiredFiniteDouble(json, 'lowerPrice'),
      upperPrice: _requiredFiniteDouble(json, 'upperPrice'),
      enabled: _requiredBool(json, 'enabled'),
      note: _optionalString(json['note']),
      createdAt: _requiredDate(json, 'createdAt'),
      updatedAt: _requiredDate(json, 'updatedAt'),
    );
    final errors = zone.validate();
    if (errors.isNotEmpty) throw FormatException(errors.join('; '));
    return zone;
  }
}

typedef RiskPlanZone = RiskZone;

class RiskPlan {
  const RiskPlan({
    required this.episodeKey,
    this.rules = const <RiskRule>[],
    this.zones = const <RiskZone>[],
  });

  final String episodeKey;
  final List<RiskRule> rules;
  final List<RiskZone> zones;

  List<String> validate() {
    final errors = <String>[];
    if (episodeKey.trim().isEmpty) errors.add('Plan episodeKey is required');
    if (rules.length > 50) errors.add('A plan can contain at most 50 rules');
    final ruleIds = <String>{};
    for (final rule in rules) {
      if (!ruleIds.add(rule.id)) errors.add('Duplicate rule id: ${rule.id}');
      if (rule.episodeKey != episodeKey) {
        errors.add('Rule ${rule.id} belongs to another episode');
      }
      errors.addAll(rule.validate());
    }
    final zoneIds = <String>{};
    for (final zone in zones) {
      if (!zoneIds.add(zone.id)) errors.add('Duplicate zone id: ${zone.id}');
      if (zone.episodeKey != episodeKey) {
        errors.add('Zone ${zone.id} belongs to another episode');
      }
      errors.addAll(zone.validate());
    }
    for (var left = 0; left < zones.length; left++) {
      for (var right = left + 1; right < zones.length; right++) {
        final first = zones[left];
        final second = zones[right];
        if (first.enabled &&
            second.enabled &&
            first.lowerPrice <= second.upperPrice &&
            second.lowerPrice <= first.upperPrice) {
          errors.add(
            'Zones ${first.id} and ${second.id} overlap; split or disable one',
          );
        }
      }
    }
    return List.unmodifiable(errors);
  }

  bool get isValid => validate().isEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'episodeKey': episodeKey,
    'rules': rules.map((rule) => rule.toJson()).toList(growable: false),
    'zones': zones.map((zone) => zone.toJson()).toList(growable: false),
  };

  factory RiskPlan.fromJson(Map<String, dynamic> json) {
    final rawRules = json['rules'];
    final rawZones = json['zones'];
    if (rawRules is! List || rawZones is! List) {
      throw const FormatException('Plan rules/zones must be arrays');
    }
    final plan = RiskPlan(
      episodeKey: _requiredString(json, 'episodeKey'),
      rules: rawRules
          .map((item) => RiskRule.fromJson(_map(item, 'rule')))
          .toList(growable: false),
      zones: rawZones
          .map((item) => RiskZone.fromJson(_map(item, 'zone')))
          .toList(growable: false),
    );
    final errors = plan.validate();
    if (errors.isNotEmpty) throw FormatException(errors.join('; '));
    return plan;
  }
}

class RiskRuleEvaluation {
  const RiskRuleEvaluation({
    required this.rule,
    required this.state,
    this.value,
    this.referenceValue,
    this.reason,
  });

  final RiskRule rule;
  final RiskRuleState state;

  /// Observed value used by the rule. For [RiskPlanMetric.priceVsTrueExit]
  /// this is the current mark price.
  final double? value;

  /// Dynamic reference used by the rule, currently the verified True Exit.
  final double? referenceValue;
  final String? reason;

  double? get observedValue => value;

  bool get active => state == RiskRuleState.active;
  bool get unknown => state == RiskRuleState.unknown;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'ruleId': rule.id,
    'state': riskRuleStateName(state),
    'value': value,
    'referenceValue': referenceValue,
    'reason': reason,
  };
}

class RiskZoneEvaluation {
  const RiskZoneEvaluation({
    required this.zone,
    required this.state,
    this.markPrice,
    this.reason,
  });

  final RiskZone zone;
  final RiskRuleState state;
  final double? markPrice;
  final String? reason;

  bool get active => state == RiskRuleState.active;
  bool get unknown => state == RiskRuleState.unknown;
}

class RiskPlanEvaluation {
  const RiskPlanEvaluation({
    required this.rules,
    this.zones = const <RiskZoneEvaluation>[],
    this.evaluatedAt,
  });

  final List<RiskRuleEvaluation> rules;
  final List<RiskZoneEvaluation> zones;
  final DateTime? evaluatedAt;

  int get activeCount => rules.where((rule) => rule.active).length;
  int get unknownCount => rules.where((rule) => rule.unknown).length;
  int get inactiveCount => rules.length - activeCount - unknownCount;
  int get activeZoneCount => zones.where((zone) => zone.active).length;
  bool get hasPlan => rules.isNotEmpty || zones.isNotEmpty;
  String get statusLabel => hasPlan ? 'Plan configured' : 'No plan defined';

  RiskRuleEvaluation? byId(String id) {
    for (final result in rules) {
      if (result.rule.id == id) return result;
    }
    return null;
  }
}

/// User settings are kept separate from episode rules and can be persisted as
/// a versioned account record.  Durations are expressed as bounded scalar
/// settings so JSON remains portable between SharedPreferences and web.
class RiskSettings {
  const RiskSettings({
    this.policy = const RiskPolicy(),
    this.customStressChanges = const <double>[],
    this.customStressPrices = const <double>[],
    this.timeZone = 'UTC',
    this.summaryHour = 8,
    this.summaryMinute = 0,
    this.sampleRetentionDays = 30,
    this.oiRetentionHours = 25,
    this.eventRetentionDays = 90,
    this.summaryRetentionDays = 90,
    this.maxSamples = 2880,
    this.maxOiSamples = 1500,
    this.maxEvents = 1000,
    this.maxEpisodes = 20,
  });

  final RiskPolicy policy;
  final List<double> customStressChanges;
  final List<double> customStressPrices;
  final String timeZone;
  final int summaryHour;
  final int summaryMinute;
  final int sampleRetentionDays;
  final int oiRetentionHours;
  final int eventRetentionDays;
  final int summaryRetentionDays;
  final int maxSamples;
  final int maxOiSamples;
  final int maxEvents;
  final int maxEpisodes;

  List<String> validate() {
    final errors = <String>[...policy.validate()];
    if (timeZone.trim().isEmpty || timeZone.length > 64) {
      errors.add('timeZone must contain 1 to 64 characters');
    }
    if (summaryHour < 0 ||
        summaryHour > 23 ||
        summaryMinute < 0 ||
        summaryMinute > 59) {
      errors.add('Summary time must be a valid local clock time');
    }
    for (var index = 0; index < customStressChanges.length; index++) {
      final value = customStressChanges[index];
      if (!value.isFinite || value <= -1) {
        errors.add('customStressChanges[$index] must be > -100% and finite');
      }
    }
    for (var index = 0; index < customStressPrices.length; index++) {
      final value = customStressPrices[index];
      if (!value.isFinite || value <= 0) {
        errors.add('customStressPrices[$index] must be finite and positive');
      }
    }
    if (customStressChanges.length + customStressPrices.length > 50) {
      errors.add('At most 50 custom stress levels are supported');
    }
    void positive(String name, int value) {
      if (value <= 0) errors.add('$name must be positive');
    }

    positive('sampleRetentionDays', sampleRetentionDays);
    positive('oiRetentionHours', oiRetentionHours);
    positive('eventRetentionDays', eventRetentionDays);
    positive('summaryRetentionDays', summaryRetentionDays);
    positive('maxSamples', maxSamples);
    positive('maxOiSamples', maxOiSamples);
    positive('maxEvents', maxEvents);
    if (maxSamples > 2880) errors.add('maxSamples cannot exceed 2880');
    if (maxOiSamples > 1500) errors.add('maxOiSamples cannot exceed 1500');
    if (maxEvents > 1000) errors.add('maxEvents cannot exceed 1000');
    if (maxEpisodes < 1 || maxEpisodes > 20) {
      errors.add('maxEpisodes must be between 1 and 20');
    }
    return List.unmodifiable(errors);
  }

  bool get isValid => validate().isEmpty;

  RiskSettings copyWith({
    RiskPolicy? policy,
    List<double>? customStressChanges,
    List<double>? customStressPrices,
    String? timeZone,
    int? summaryHour,
    int? summaryMinute,
    int? sampleRetentionDays,
    int? oiRetentionHours,
    int? eventRetentionDays,
    int? summaryRetentionDays,
    int? maxSamples,
    int? maxOiSamples,
    int? maxEvents,
    int? maxEpisodes,
  }) {
    return RiskSettings(
      policy: policy ?? this.policy,
      customStressChanges: customStressChanges ?? this.customStressChanges,
      customStressPrices: customStressPrices ?? this.customStressPrices,
      timeZone: timeZone ?? this.timeZone,
      summaryHour: summaryHour ?? this.summaryHour,
      summaryMinute: summaryMinute ?? this.summaryMinute,
      sampleRetentionDays: sampleRetentionDays ?? this.sampleRetentionDays,
      oiRetentionHours: oiRetentionHours ?? this.oiRetentionHours,
      eventRetentionDays: eventRetentionDays ?? this.eventRetentionDays,
      summaryRetentionDays: summaryRetentionDays ?? this.summaryRetentionDays,
      maxSamples: maxSamples ?? this.maxSamples,
      maxOiSamples: maxOiSamples ?? this.maxOiSamples,
      maxEvents: maxEvents ?? this.maxEvents,
      maxEpisodes: maxEpisodes ?? this.maxEpisodes,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'policy': <String, dynamic>{
      'version': policy.version,
      'bufferCritical': policy.bufferCritical,
      'bufferHigh': policy.bufferHigh,
      'bufferWatch': policy.bufferWatch,
      'leverageWatch': policy.leverageWatch,
      'leverageHigh': policy.leverageHigh,
      'leverageCritical': policy.leverageCritical,
      'marginRatioCritical': policy.marginRatioCritical,
      'marginRatioHigh': policy.marginRatioHigh,
      'marginRatioWatch': policy.marginRatioWatch,
      'bufferVolatilityHigh': policy.bufferVolatilityHigh,
      'bufferVolatilityWatch': policy.bufferVolatilityWatch,
      'recoveryDistanceWatch': policy.recoveryDistanceWatch,
      'recoveryDistanceHigh': policy.recoveryDistanceHigh,
      'holdingBurdenWatch': policy.holdingBurdenWatch,
      'holdingBurdenHigh': policy.holdingBurdenHigh,
      'stressChanges': policy.stressChanges,
      'priceDeduplicationTolerance': policy.priceDeduplicationTolerance,
    },
    'customStressChanges': customStressChanges,
    'customStressPrices': customStressPrices,
    'timeZone': timeZone,
    'summaryHour': summaryHour,
    'summaryMinute': summaryMinute,
    'sampleRetentionDays': sampleRetentionDays,
    'oiRetentionHours': oiRetentionHours,
    'eventRetentionDays': eventRetentionDays,
    'summaryRetentionDays': summaryRetentionDays,
    'maxSamples': maxSamples,
    'maxOiSamples': maxOiSamples,
    'maxEvents': maxEvents,
    'maxEpisodes': maxEpisodes,
  };

  factory RiskSettings.fromJson(Map<String, dynamic> json) {
    final rawPolicy = json['policy'];
    if (rawPolicy is! Map) throw const FormatException('Policy is required');
    final policyMap = rawPolicy.map<String, dynamic>(
      (key, value) => MapEntry(key.toString(), value),
    );
    final settings = RiskSettings(
      policy: _policyFromJson(policyMap),
      customStressChanges: _doubleList(json['customStressChanges']),
      customStressPrices: _doubleList(json['customStressPrices']),
      timeZone: _requiredString(json, 'timeZone'),
      summaryHour: _requiredInt(json, 'summaryHour'),
      summaryMinute: _requiredInt(json, 'summaryMinute'),
      sampleRetentionDays: _requiredInt(json, 'sampleRetentionDays'),
      oiRetentionHours: _requiredInt(json, 'oiRetentionHours'),
      eventRetentionDays: _requiredInt(json, 'eventRetentionDays'),
      summaryRetentionDays: _requiredInt(json, 'summaryRetentionDays'),
      maxSamples: _requiredInt(json, 'maxSamples'),
      maxOiSamples: _requiredInt(json, 'maxOiSamples'),
      maxEvents: _requiredInt(json, 'maxEvents'),
      maxEpisodes: _requiredInt(json, 'maxEpisodes'),
    );
    final errors = settings.validate();
    if (errors.isNotEmpty) throw FormatException(errors.join('; '));
    return settings;
  }
}

class ActionPlanEvaluator {
  const ActionPlanEvaluator();

  RiskPlanEvaluation evaluate(
    Iterable<RiskRule> rules,
    RiskEvaluation evaluation, {
    DateTime? at,
  }) {
    final results = rules
        .map((rule) => _evaluateRule(rule, evaluation))
        .toList(growable: false);
    return RiskPlanEvaluation(
      rules: List.unmodifiable(results),
      evaluatedAt: at ?? evaluation.evaluatedAt,
    );
  }

  RiskPlanEvaluation evaluatePlan(
    RiskPlan plan,
    RiskEvaluation evaluation, {
    DateTime? at,
  }) {
    final rules = evaluate(plan.rules, evaluation, at: at);
    final mark = evaluation.metrics.markPrice;
    final zones = plan.zones
        .map((zone) {
          if (!zone.enabled) {
            return RiskZoneEvaluation(
              zone: zone,
              state: RiskRuleState.inactive,
              markPrice: mark.value,
            );
          }
          if (mark.quality.status != RiskQualityStatus.complete ||
              mark.value == null) {
            return RiskZoneEvaluation(
              zone: zone,
              state: RiskRuleState.unknown,
              reason: 'Mark price is unavailable',
            );
          }
          final active =
              mark.value! >= zone.lowerPrice && mark.value! <= zone.upperPrice;
          return RiskZoneEvaluation(
            zone: zone,
            state: active ? RiskRuleState.active : RiskRuleState.inactive,
            markPrice: mark.value,
          );
        })
        .toList(growable: false);
    return RiskPlanEvaluation(
      rules: rules.rules,
      zones: List.unmodifiable(zones),
      evaluatedAt: rules.evaluatedAt,
    );
  }

  RiskRuleEvaluation _evaluateRule(RiskRule rule, RiskEvaluation evaluation) {
    if (!rule.enabled) {
      return RiskRuleEvaluation(rule: rule, state: RiskRuleState.inactive);
    }
    if (rule.metric == RiskPlanMetric.priceVsTrueExit) {
      return _evaluatePriceVsTrueExit(rule, evaluation);
    }
    final metric = _metricValue(rule.metric, evaluation);
    if (metric == null ||
        metric.quality.status != RiskQualityStatus.complete ||
        metric.value == null) {
      return RiskRuleEvaluation(
        rule: rule,
        state: RiskRuleState.unknown,
        reason: 'Required ${riskPlanMetricName(rule.metric)} is unavailable',
      );
    }
    final errors = rule.validate();
    if (errors.isNotEmpty) {
      return RiskRuleEvaluation(
        rule: rule,
        state: RiskRuleState.unknown,
        value: metric.value,
        reason: errors.join('; '),
      );
    }
    final value = metric.value!;
    final threshold = rule.threshold;
    final active = switch (rule.comparison) {
      RiskPlanComparison.lessThan => value < threshold!,
      RiskPlanComparison.lessThanOrEqual => value <= threshold!,
      RiskPlanComparison.greaterThan => value > threshold!,
      RiskPlanComparison.greaterThanOrEqual => value >= threshold!,
      RiskPlanComparison.betweenInclusive =>
        value >= threshold! && value <= rule.upperThreshold!,
    };
    return RiskRuleEvaluation(
      rule: rule,
      state: active ? RiskRuleState.active : RiskRuleState.inactive,
      value: value,
    );
  }

  RiskMetricValue? _metricValue(
    RiskPlanMetric metric,
    RiskEvaluation evaluation,
  ) {
    switch (metric) {
      case RiskPlanMetric.markPrice:
        return evaluation.metrics.markPrice;
      case RiskPlanMetric.buffer:
        return evaluation.metrics.buffer;
      case RiskPlanMetric.effectiveLeverage:
        return evaluation.metrics.effectiveLeverage;
      case RiskPlanMetric.totalDebt:
        return evaluation.metrics.debt;
      case RiskPlanMetric.dailyHoldingCost:
        return evaluation.metrics.holdingCostPerDay;
      case RiskPlanMetric.priceVsTrueExit:
        return evaluation.metrics.markPrice;
      case RiskPlanMetric.trueExitPrice:
        return evaluation.metrics.trueExitPrice;
    }
  }

  RiskRuleEvaluation _evaluatePriceVsTrueExit(
    RiskRule rule,
    RiskEvaluation evaluation,
  ) {
    final mark = evaluation.metrics.markPrice;
    final trueExit = evaluation.metrics.trueExitPrice;
    final markValue = mark.value;
    final trueExitValue = trueExit.value;
    final verifiedTrueExit =
        trueExit.quality.status == RiskQualityStatus.complete &&
        _finite(trueExitValue) &&
        evaluation.position.costAttribution.coverage.isVerifiedComplete;
    final errors = rule.validate();
    if (errors.isNotEmpty) {
      return RiskRuleEvaluation(
        rule: rule,
        state: RiskRuleState.unknown,
        value: markValue,
        referenceValue: trueExitValue,
        reason: errors.join('; '),
      );
    }
    if (mark.quality.status != RiskQualityStatus.complete ||
        !_finite(markValue) ||
        !verifiedTrueExit) {
      return RiskRuleEvaluation(
        rule: rule,
        state: RiskRuleState.unknown,
        value: markValue,
        referenceValue: trueExitValue,
        reason: 'Complete mark and verified True Exit are required',
      );
    }
    final active = rule.comparison == RiskPlanComparison.lessThan
        ? markValue! < trueExitValue!
        : markValue! > trueExitValue!;
    return RiskRuleEvaluation(
      rule: rule,
      state: active ? RiskRuleState.active : RiskRuleState.inactive,
      value: markValue,
      referenceValue: trueExitValue,
    );
  }
}

bool _finite(double? value) => value != null && value.isFinite;

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string');
  }
  return value;
}

String? _optionalString(Object? value) => value is String ? value : null;

bool _requiredBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('$key must be boolean');
  return value;
}

double? _optionalDouble(Object? value) {
  if (value == null) return null;
  if (value is num && value.toDouble().isFinite) return value.toDouble();
  throw const FormatException('Expected a finite number');
}

double _requiredFiniteDouble(Map<String, dynamic> json, String key) {
  final value = _optionalDouble(json[key]);
  if (value == null) throw FormatException('$key must be a number');
  return value;
}

DateTime _requiredDate(Map<String, dynamic> json, String key) {
  final raw = json[key];
  if (raw is! String) throw FormatException('$key must be an ISO timestamp');
  final value = DateTime.tryParse(raw);
  if (value == null) throw FormatException('$key must be an ISO timestamp');
  return value.toUtc();
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final raw = json[key];
  if (raw is! num || raw % 1 != 0) {
    throw FormatException('$key must be integer');
  }
  return raw.toInt();
}

Map<String, dynamic> _map(Object? value, String name) {
  if (value is! Map) throw FormatException('$name must be an object');
  return value.map<String, dynamic>(
    (key, item) => MapEntry(key.toString(), item),
  );
}

List<double> _doubleList(Object? value) {
  if (value is! List) throw const FormatException('Expected a number array');
  return value
      .map((item) {
        if (item is! num || !item.toDouble().isFinite) {
          throw const FormatException('Expected finite numeric array values');
        }
        return item.toDouble();
      })
      .toList(growable: false);
}

RiskPolicy _policyFromJson(Map<String, dynamic> json) {
  final stress = _doubleList(json['stressChanges']);
  final policy = RiskPolicy(
    version: _requiredString(json, 'version'),
    bufferCritical: _requiredFiniteDouble(json, 'bufferCritical'),
    bufferHigh: _requiredFiniteDouble(json, 'bufferHigh'),
    bufferWatch: _requiredFiniteDouble(json, 'bufferWatch'),
    leverageWatch: _requiredFiniteDouble(json, 'leverageWatch'),
    leverageHigh: _requiredFiniteDouble(json, 'leverageHigh'),
    leverageCritical: _requiredFiniteDouble(json, 'leverageCritical'),
    marginRatioCritical: _requiredFiniteDouble(json, 'marginRatioCritical'),
    marginRatioHigh: _requiredFiniteDouble(json, 'marginRatioHigh'),
    marginRatioWatch: _requiredFiniteDouble(json, 'marginRatioWatch'),
    bufferVolatilityHigh: _requiredFiniteDouble(json, 'bufferVolatilityHigh'),
    bufferVolatilityWatch: _requiredFiniteDouble(json, 'bufferVolatilityWatch'),
    recoveryDistanceWatch: _requiredFiniteDouble(json, 'recoveryDistanceWatch'),
    recoveryDistanceHigh: _requiredFiniteDouble(json, 'recoveryDistanceHigh'),
    holdingBurdenWatch: _requiredFiniteDouble(json, 'holdingBurdenWatch'),
    holdingBurdenHigh: _requiredFiniteDouble(json, 'holdingBurdenHigh'),
    stressChanges: stress,
    priceDeduplicationTolerance: _requiredFiniteDouble(
      json,
      'priceDeduplicationTolerance',
    ),
  );
  policy.requireValid();
  return policy;
}
