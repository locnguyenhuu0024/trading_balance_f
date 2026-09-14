import 'market_risk_engine.dart';
import 'risk_models.dart';

enum RiskHistoryInputStatus {
  accepted,
  duplicate,
  outOfOrder,
  stale,
  invalid,
  wrongEpisode,
}

class RiskHistoryAppendResult {
  const RiskHistoryAppendResult(this.status, {this.reason});

  final RiskHistoryInputStatus status;
  final String? reason;

  bool get accepted => status == RiskHistoryInputStatus.accepted;
}

enum RiskTrendLabel {
  collectingHistory,
  deteriorating,
  improving,
  stable,
  positionChanged,
  stale,
  unavailable,
}

extension RiskTrendLabelX on RiskTrendLabel {
  String get text {
    switch (this) {
      case RiskTrendLabel.collectingHistory:
        return '- / Collecting history';
      case RiskTrendLabel.deteriorating:
        return 'Deteriorating';
      case RiskTrendLabel.improving:
        return 'Improving';
      case RiskTrendLabel.stable:
        return 'Stable';
      case RiskTrendLabel.positionChanged:
        return 'Position changed';
      case RiskTrendLabel.stale:
        return 'Stale';
      case RiskTrendLabel.unavailable:
        return '- / Insufficient data';
    }
  }
}

/// A compact, immutable history point.  It deliberately stores derived
/// values and identity rather than an API payload or a full account record.
class RiskHistorySample {
  const RiskHistorySample({
    required this.episodeKey,
    required this.observedAt,
    required this.quality,
    this.overallState,
    this.positionState,
    this.marketState,
    this.recoveryState,
    this.markPrice,
    this.buffer,
    this.effectiveLeverage,
    this.debt,
    this.marginRatio,
    this.trueExit,
    this.trueExitVerified = true,
    this.entryPrice,
    this.entryFeeRate,
    this.exitFeeRate,
    this.actualInterestToday,
    this.knownInterestToday,
    this.actualInterestQuality,
    this.interestCoverageComplete = false,
    this.quantity,
    this.margin,
    String? assetStructureLabel,
    String? structureLabel,
    this.fundingLabel,
    this.openInterestChange,
    this.policyVersion = 'risk.v1',
    this.activeFactorIds = const <String>[],
    this.source,
  }) : assetStructureLabel = assetStructureLabel ?? structureLabel;

  final String episodeKey;
  final DateTime observedAt;
  final RiskQuality quality;
  final RiskSeverity? overallState;
  final RiskSeverity? positionState;
  final RiskSeverity? marketState;
  final RiskSeverity? recoveryState;
  final double? markPrice;
  final double? buffer;
  final double? effectiveLeverage;
  final double? debt;
  final double? marginRatio;
  final double? trueExit;

  /// A non-null True Exit is expected to be verified, but callers restoring
  /// an incomplete record can explicitly keep this false. Projected True
  /// Exit is never copied into this field.
  final bool trueExitVerified;
  final double? entryPrice;
  final double? entryFeeRate;
  final double? exitFeeRate;
  final double? actualInterestToday;
  final double? knownInterestToday;
  final RiskQuality? actualInterestQuality;
  final bool interestCoverageComplete;
  final double? quantity;
  final double? margin;
  final String? assetStructureLabel;

  /// Backward-compatible alias for older callers and records.
  String? get structureLabel => assetStructureLabel;
  final String? fundingLabel;
  final double? openInterestChange;
  final String policyVersion;
  final List<String> activeFactorIds;
  final String? source;

  factory RiskHistorySample.fromEvaluation({
    required String episodeKey,
    required RiskEvaluation evaluation,
    required RiskMarketInput market,
  }) {
    return RiskHistorySample(
      episodeKey: episodeKey,
      observedAt: evaluation.evaluatedAt,
      quality: evaluation.quality,
      overallState: evaluation.overallState,
      positionState: evaluation.positionAssessment.state,
      marketState: evaluation.marketAssessment.state,
      recoveryState: evaluation.recoveryAssessment.state,
      markPrice: evaluation.metrics.markPrice.value,
      buffer: evaluation.metrics.buffer.value,
      effectiveLeverage: evaluation.metrics.effectiveLeverage.value,
      debt: evaluation.metrics.debt.value,
      marginRatio: evaluation.metrics.marginRatio.value,
      trueExit: evaluation.metrics.trueExitPrice.value,
      trueExitVerified:
          evaluation.metrics.trueExitPrice.value != null &&
          evaluation.metrics.trueExitPrice.quality.isComplete &&
          evaluation.position.costAttribution.coverage.isVerifiedComplete,
      entryPrice: evaluation.metrics.entryPrice.value,
      entryFeeRate: evaluation.position.entryFeeRate,
      exitFeeRate: evaluation.position.exitFeeRate,
      actualInterestToday: evaluation.metrics.actualInterestToday.value,
      knownInterestToday: evaluation.metrics.knownInterestToday.value,
      actualInterestQuality: evaluation.metrics.actualInterestToday.quality,
      interestCoverageComplete:
          evaluation
              .position
              .costAttribution
              .actualInterestToday
              ?.coverageComplete ??
          false,
      quantity: evaluation.metrics.quantity.value,
      margin: evaluation.metrics.margin.value,
      assetStructureLabel: market.assetStructureLabel,
      fundingLabel: market.fundingLabel,
      openInterestChange: market.openInterestChange,
      policyVersion: evaluation.policyVersion,
      activeFactorIds: evaluation.reasons
          .where((reason) => reason.factorId.isNotEmpty)
          .map((reason) => reason.factorId)
          .toSet()
          .toList(growable: false),
      source: evaluation.quality.source,
    );
  }

  /// Completeness is intentionally stricter than [RiskQuality.isAvailable].
  /// A partial sample can be displayed, but it is not a safe baseline for a
  /// numeric trend or velocity claim.
  bool get isComparable =>
      episodeKey.trim().isNotEmpty &&
      quality.status == RiskQualityStatus.complete &&
      !isStale &&
      buffer != null &&
      buffer!.isFinite &&
      effectiveLeverage != null &&
      effectiveLeverage!.isFinite &&
      debt != null &&
      debt!.isFinite &&
      quantity != null &&
      quantity!.isFinite &&
      margin != null &&
      margin!.isFinite;

  bool get isStale => quality.status == RiskQualityStatus.stale;

  bool get isFresh =>
      quality.status == RiskQualityStatus.complete ||
      quality.status == RiskQualityStatus.partial;

  double? get bufferPercentage => buffer == null ? null : buffer! * 100;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'episodeKey': episodeKey,
    'observedAt': observedAt.toUtc().toIso8601String(),
    'quality': _qualityToJson(quality),
    'overallState': overallState?.name,
    'positionState': positionState?.name,
    'marketState': marketState?.name,
    'recoveryState': recoveryState?.name,
    'markPrice': markPrice,
    'buffer': buffer,
    'effectiveLeverage': effectiveLeverage,
    'debt': debt,
    'marginRatio': marginRatio,
    'trueExit': trueExit,
    'trueExitVerified': trueExitVerified,
    'entryPrice': entryPrice,
    'entryFeeRate': entryFeeRate,
    'exitFeeRate': exitFeeRate,
    'actualInterestToday': actualInterestToday,
    'knownInterestToday': knownInterestToday,
    'actualInterestQuality': actualInterestQuality == null
        ? null
        : _qualityToJson(actualInterestQuality!),
    'interestCoverageComplete': interestCoverageComplete,
    'quantity': quantity,
    'margin': margin,
    'assetStructureLabel': assetStructureLabel,
    'fundingLabel': fundingLabel,
    'openInterestChange': openInterestChange,
    'policyVersion': policyVersion,
    'activeFactorIds': activeFactorIds,
    'source': source,
  };

  factory RiskHistorySample.fromJson(Map<String, dynamic> json) {
    final rawFactors = json['activeFactorIds'];
    if (rawFactors is! List || rawFactors.any((item) => item is! String)) {
      throw const FormatException('activeFactorIds must be a string array');
    }
    final sample = RiskHistorySample(
      episodeKey: _requiredString(json, 'episodeKey'),
      observedAt: _requiredDate(json, 'observedAt'),
      quality: _qualityFromJson(_requiredMap(json, 'quality')),
      overallState: _severityFromJson(json['overallState']),
      positionState: _severityFromJson(json['positionState']),
      marketState: _severityFromJson(json['marketState']),
      recoveryState: _severityFromJson(json['recoveryState']),
      markPrice: _optionalDouble(json['markPrice']),
      buffer: _optionalDouble(json['buffer']),
      effectiveLeverage: _optionalDouble(json['effectiveLeverage']),
      debt: _optionalDouble(json['debt']),
      marginRatio: _optionalDouble(json['marginRatio']),
      trueExit: _optionalDouble(json['trueExit']),
      trueExitVerified: _optionalBool(json['trueExitVerified']) ?? true,
      entryPrice: _optionalDouble(json['entryPrice']),
      entryFeeRate: _optionalDouble(json['entryFeeRate']),
      exitFeeRate: _optionalDouble(json['exitFeeRate']),
      actualInterestToday: _optionalDouble(json['actualInterestToday']),
      knownInterestToday: _optionalDouble(json['knownInterestToday']),
      actualInterestQuality: json['actualInterestQuality'] == null
          ? null
          : _qualityFromJson(_requiredMap(json, 'actualInterestQuality')),
      interestCoverageComplete:
          _optionalBool(json['interestCoverageComplete']) ?? false,
      quantity: _optionalDouble(json['quantity']),
      margin: _optionalDouble(json['margin']),
      assetStructureLabel: _optionalString(
        json['assetStructureLabel'] ?? json['structureLabel'],
      ),
      fundingLabel: _optionalString(json['fundingLabel']),
      openInterestChange: _optionalDouble(json['openInterestChange']),
      policyVersion: _requiredString(json, 'policyVersion'),
      activeFactorIds: List<String>.unmodifiable(rawFactors.cast<String>()),
      source: _optionalString(json['source']),
    );
    _requireFinite(sample.markPrice, 'markPrice');
    _requireFinite(sample.buffer, 'buffer');
    _requireFinite(sample.effectiveLeverage, 'effectiveLeverage');
    _requireFinite(sample.debt, 'debt');
    _requireFinite(sample.marginRatio, 'marginRatio');
    _requireFinite(sample.trueExit, 'trueExit');
    _requireFinite(sample.entryPrice, 'entryPrice');
    _requireFinite(sample.entryFeeRate, 'entryFeeRate');
    _requireFinite(sample.exitFeeRate, 'exitFeeRate');
    _requireFinite(sample.actualInterestToday, 'actualInterestToday');
    _requireFinite(sample.knownInterestToday, 'knownInterestToday');
    _requireFinite(sample.quantity, 'quantity');
    _requireFinite(sample.margin, 'margin');
    _requireFinite(sample.openInterestChange, 'openInterestChange');
    return sample;
  }
}

/// A bounded append-only ring for public currency-unit OI samples.  Input
/// order is evidence: late or duplicate samples are rejected rather than
/// sorted into a plausible history.
class RiskOiRingBuffer {
  RiskOiRingBuffer({
    Iterable<MarketOpenInterestSample> initial =
        const <MarketOpenInterestSample>[],
    this.maxSamples = 1500,
    this.retention = const Duration(hours: 25),
  }) : _samples = <MarketOpenInterestSample>[] {
    if (maxSamples <= 0) throw ArgumentError.value(maxSamples, 'maxSamples');
    for (final sample in initial) {
      final result = append(sample, now: sample.timestamp);
      if (!result.accepted) {
        throw ArgumentError.value(sample, 'initial', result.reason);
      }
    }
  }

  final int maxSamples;
  final Duration retention;
  final List<MarketOpenInterestSample> _samples;

  List<MarketOpenInterestSample> get samples =>
      List<MarketOpenInterestSample>.unmodifiable(_samples);

  MarketOpenInterestSample? get latest =>
      _samples.isEmpty ? null : _samples.last;

  RiskHistoryAppendResult append(
    MarketOpenInterestSample sample, {
    DateTime? now,
  }) {
    final currentTime = (now ?? DateTime.now().toUtc()).toUtc();
    if (sample.oiCcy == null ||
        !sample.oiCcy!.isFinite ||
        sample.oiCcy! <= 0 ||
        sample.instrument.trim().isEmpty) {
      return const RiskHistoryAppendResult(
        RiskHistoryInputStatus.invalid,
        reason: 'OI sample is malformed',
      );
    }
    final quality = sample.source.quality.status;
    if (quality == RiskQualityStatus.stale ||
        quality == RiskQualityStatus.error ||
        quality == RiskQualityStatus.empty ||
        quality == RiskQualityStatus.unavailable ||
        quality == RiskQualityStatus.unsupported) {
      return const RiskHistoryAppendResult(
        RiskHistoryInputStatus.stale,
        reason: 'Stale or unavailable OI sample is not retained',
      );
    }
    if (sample.timestamp.isAfter(currentTime)) {
      return const RiskHistoryAppendResult(
        RiskHistoryInputStatus.invalid,
        reason: 'Future OI sample is not retained',
      );
    }
    if (_samples.isNotEmpty) {
      final last = _samples.last.timestamp;
      if (sample.timestamp == last) {
        return const RiskHistoryAppendResult(
          RiskHistoryInputStatus.duplicate,
          reason: 'Duplicate OI timestamp',
        );
      }
      if (sample.timestamp.isBefore(last)) {
        return const RiskHistoryAppendResult(
          RiskHistoryInputStatus.outOfOrder,
          reason: 'Out-of-order OI timestamp',
        );
      }
    }
    _samples.add(sample);
    final cutoff = currentTime.subtract(retention);
    _samples.removeWhere((item) => item.timestamp.isBefore(cutoff));
    if (_samples.length > maxSamples) {
      _samples.removeRange(0, _samples.length - maxSamples);
    }
    return const RiskHistoryAppendResult(RiskHistoryInputStatus.accepted);
  }

  RiskHistoryAppendResult add(
    MarketOpenInterestSample sample, {
    DateTime? now,
  }) => append(sample, now: now);
}

class RiskHistoryBuffer {
  RiskHistoryBuffer({
    Iterable<RiskHistorySample> initial = const <RiskHistorySample>[],
    this.maxSamples = 2880,
    this.retention = const Duration(days: 30),
  }) : _samples = <RiskHistorySample>[] {
    if (maxSamples <= 0) throw ArgumentError.value(maxSamples, 'maxSamples');
    for (final sample in initial) {
      final result = append(sample, now: sample.observedAt);
      if (!result.accepted) {
        throw ArgumentError.value(sample, 'initial', result.reason);
      }
    }
  }

  final int maxSamples;
  final Duration retention;
  final List<RiskHistorySample> _samples;

  List<RiskHistorySample> get samples =>
      List<RiskHistorySample>.unmodifiable(_samples);

  RiskHistorySample? get latest => _samples.isEmpty ? null : _samples.last;

  RiskHistoryAppendResult append(RiskHistorySample sample, {DateTime? now}) {
    final currentTime = (now ?? DateTime.now().toUtc()).toUtc();
    if (sample.episodeKey.trim().isEmpty) {
      return const RiskHistoryAppendResult(
        RiskHistoryInputStatus.invalid,
        reason: 'History sample episodeKey is required',
      );
    }
    if (!sample.isFresh) {
      return const RiskHistoryAppendResult(
        RiskHistoryInputStatus.stale,
        reason: 'Stale or unavailable sample is not retained for comparison',
      );
    }
    if (sample.observedAt.isAfter(currentTime)) {
      return const RiskHistoryAppendResult(
        RiskHistoryInputStatus.invalid,
        reason: 'Future sample is not retained',
      );
    }
    if (_samples.isNotEmpty) {
      if (sample.episodeKey != _samples.last.episodeKey) {
        return const RiskHistoryAppendResult(
          RiskHistoryInputStatus.wrongEpisode,
          reason: 'History cannot cross position episodes',
        );
      }
      final last = _samples.last.observedAt;
      if (sample.observedAt == last) {
        return const RiskHistoryAppendResult(
          RiskHistoryInputStatus.duplicate,
          reason: 'Duplicate history observation',
        );
      }
      if (sample.observedAt.isBefore(last)) {
        return const RiskHistoryAppendResult(
          RiskHistoryInputStatus.outOfOrder,
          reason: 'Out-of-order history observation',
        );
      }
    }
    _samples.add(sample);
    final cutoff = currentTime.subtract(retention);
    _samples.removeWhere((item) => item.observedAt.isBefore(cutoff));
    if (_samples.length > maxSamples) {
      _samples.removeRange(0, _samples.length - maxSamples);
    }
    return const RiskHistoryAppendResult(RiskHistoryInputStatus.accepted);
  }
}

class RiskTrendResult {
  const RiskTrendResult({
    required this.label,
    this.baseline,
    this.current,
    this.bufferDeltaPoints,
    this.leverageDelta,
    this.reason,
  });

  final RiskTrendLabel label;
  final RiskHistorySample? baseline;
  final RiskHistorySample? current;
  final double? bufferDeltaPoints;
  final double? leverageDelta;
  final String? reason;

  String get text => label.text;
}

class RiskVelocityResult {
  const RiskVelocityResult({
    required this.label,
    this.baseline,
    this.current,
    this.pointsPerHour,
    this.elapsedHours,
    this.reason,
  });

  final RiskTrendLabel label;
  final RiskHistorySample? baseline;
  final RiskHistorySample? current;
  final double? pointsPerHour;
  final double? elapsedHours;
  final String? reason;

  String get text {
    switch (label) {
      case RiskTrendLabel.deteriorating:
        return 'Deteriorating fast';
      case RiskTrendLabel.improving:
        return 'Improving fast';
      default:
        return label.text;
    }
  }
}

class RiskHistoryAnalytics {
  const RiskHistoryAnalytics._();

  static RiskTrendResult trend({
    required RiskHistorySample current,
    required Iterable<RiskHistorySample> history,
    required DateTime now,
  }) {
    if (!current.isFresh) {
      return RiskTrendResult(
        label: RiskTrendLabel.stale,
        current: current,
        reason: 'Current sample is stale or unavailable',
      );
    }
    final baseline = _findBaseline(
      current: current,
      history: history,
      now: now,
      lookback: const Duration(hours: 1),
      tolerance: const Duration(minutes: 15),
    );
    if (baseline == null ||
        !current.isComparable ||
        !_hasComparableChain(
          baseline: baseline,
          current: current,
          history: history,
        )) {
      return RiskTrendResult(
        label: RiskTrendLabel.collectingHistory,
        current: current,
        reason: baseline == null
            ? 'No comparable valid sample at or before now-1h'
            : 'Comparable history has a gap greater than 30 minutes',
      );
    }
    if (!baseline.isComparable) {
      return RiskTrendResult(
        label: RiskTrendLabel.collectingHistory,
        baseline: baseline,
        current: current,
        reason: 'Baseline positional inputs are incomplete',
      );
    }
    final bufferDelta = current.bufferPercentage! - baseline.bufferPercentage!;
    final leverageDelta =
        current.effectiveLeverage! - baseline.effectiveLeverage!;
    final stateDelta =
        _rank(current.overallState) - _rank(baseline.overallState);
    final deteriorating =
        stateDelta > 0 || bufferDelta <= -2 || leverageDelta >= 0.25;
    final improving =
        !deteriorating &&
        (stateDelta < 0 || bufferDelta >= 2 || leverageDelta <= -0.25);
    return RiskTrendResult(
      label: deteriorating
          ? RiskTrendLabel.deteriorating
          : improving
          ? RiskTrendLabel.improving
          : RiskTrendLabel.stable,
      baseline: baseline,
      current: current,
      bufferDeltaPoints: bufferDelta,
      leverageDelta: leverageDelta,
    );
  }

  static RiskVelocityResult velocity({
    required RiskHistorySample current,
    required Iterable<RiskHistorySample> history,
    required DateTime now,
  }) {
    if (!current.isFresh) {
      return RiskVelocityResult(
        label: RiskTrendLabel.stale,
        current: current,
        reason: 'Current sample is stale or unavailable',
      );
    }
    final historyList = history.toList(growable: false);
    final baseline = _findBaseline(
      current: current,
      history: historyList,
      now: now,
      lookback: const Duration(hours: 6),
      tolerance: const Duration(minutes: 30),
    );
    if (baseline == null ||
        !current.isComparable ||
        !baseline.isComparable ||
        !_hasComparableChain(
          baseline: baseline,
          current: current,
          history: historyList,
        )) {
      return RiskVelocityResult(
        label: RiskTrendLabel.collectingHistory,
        baseline: baseline,
        current: current,
        reason: baseline == null
            ? 'No comparable valid sample at or before now-6h'
            : 'Comparable history has a gap greater than 30 minutes',
      );
    }
    if (!_samePosition(baseline, current)) {
      return RiskVelocityResult(
        label: RiskTrendLabel.positionChanged,
        baseline: baseline,
        current: current,
        reason: 'Quantity, margin or debt changed by more than 0.1%',
      );
    }
    final elapsedHours =
        current.observedAt.difference(baseline.observedAt).inMilliseconds /
        Duration.millisecondsPerHour;
    if (!elapsedHours.isFinite || elapsedHours <= 0) {
      return RiskVelocityResult(
        label: RiskTrendLabel.unavailable,
        baseline: baseline,
        current: current,
        reason: 'Velocity elapsed time is unavailable',
      );
    }
    final pointsPerHour =
        (current.bufferPercentage! - baseline.bufferPercentage!) / elapsedHours;
    final hourlyLabel = pointsPerHour <= -1
        ? RiskTrendLabel.deteriorating
        : pointsPerHour >= 1
        ? RiskTrendLabel.improving
        : null;
    // The velocity threshold is intentionally stricter than the one-hour
    // trend. When it is not crossed, preserve the independently computed
    // one-hour direction instead of manufacturing a stable label.
    final label =
        hourlyLabel ??
        RiskHistoryAnalytics.trend(
          current: current,
          history: historyList,
          now: now,
        ).label;
    return RiskVelocityResult(
      label: label,
      baseline: baseline,
      current: current,
      pointsPerHour: pointsPerHour,
      elapsedHours: elapsedHours,
    );
  }

  static RiskHistorySample? _findBaseline({
    required RiskHistorySample current,
    required Iterable<RiskHistorySample> history,
    required DateTime now,
    required Duration lookback,
    required Duration tolerance,
  }) {
    final target = now.toUtc().subtract(lookback);
    RiskHistorySample? result;
    for (final sample in history) {
      if (sample.episodeKey != current.episodeKey ||
          !sample.isComparable ||
          sample.observedAt.isAfter(target) ||
          target.difference(sample.observedAt) > tolerance) {
        continue;
      }
      if (result == null || sample.observedAt.isAfter(result.observedAt)) {
        result = sample;
      }
    }
    return result;
  }

  static bool _hasComparableChain({
    required RiskHistorySample baseline,
    required RiskHistorySample current,
    required Iterable<RiskHistorySample> history,
  }) {
    final points = history
        .where(
          (sample) =>
              sample.episodeKey == current.episodeKey &&
              sample.isComparable &&
              !sample.observedAt.isBefore(baseline.observedAt) &&
              !sample.observedAt.isAfter(current.observedAt),
        )
        .toList(growable: true);
    if (!points.any((sample) => sample.observedAt == baseline.observedAt)) {
      points.add(baseline);
    }
    if (!points.any((sample) => sample.observedAt == current.observedAt)) {
      points.add(current);
    }
    points.sort((left, right) => left.observedAt.compareTo(right.observedAt));
    for (var index = 1; index < points.length; index++) {
      if (points[index].observedAt.difference(points[index - 1].observedAt) >
          const Duration(minutes: 30)) {
        return false;
      }
    }
    return points.length >= 2;
  }
}

class RiskSessionComparison {
  const RiskSessionComparison({
    required this.baseline,
    required this.current,
    this.bufferDeltaPoints,
    this.leverageDelta,
    this.debtDelta,
    this.trueExitChanged = false,
    this.structureChanged = false,
    this.fundingChanged = false,
    this.openInterestChanged = false,
    this.overallChanged = false,
    this.positionChanged = false,
  });

  final RiskHistorySample baseline;
  final RiskHistorySample current;
  final double? bufferDeltaPoints;
  final double? leverageDelta;
  final double? debtDelta;
  final bool trueExitChanged;
  final bool structureChanged;
  final bool fundingChanged;
  final bool openInterestChanged;
  final bool overallChanged;
  final bool positionChanged;

  bool get hasChange =>
      (bufferDeltaPoints != null && bufferDeltaPoints!.abs() > 0) ||
      (leverageDelta != null && leverageDelta!.abs() > 0) ||
      (debtDelta != null && debtDelta!.abs() > 0) ||
      trueExitChanged ||
      structureChanged ||
      fundingChanged ||
      openInterestChanged ||
      overallChanged ||
      positionChanged;
}

/// Visit-scoped previous-check state.  [baseline] never moves while the
/// session is active; the latest valid point is saved only by [departure].
class RiskCheckSession {
  const RiskCheckSession({
    required this.episodeKey,
    required this.startedAt,
    this.baseline,
    this.firstCurrent,
    this.latest,
    this.comparison,
  });

  final String episodeKey;
  final DateTime startedAt;
  final RiskHistorySample? baseline;
  final RiskHistorySample? firstCurrent;
  final RiskHistorySample? latest;
  final RiskSessionComparison? comparison;

  bool get hasPreviousCheck => baseline != null;

  factory RiskCheckSession.start({
    required String episodeKey,
    required DateTime now,
    RiskHistorySample? savedBaseline,
    Duration awayDuration = const Duration(seconds: 60),
  }) {
    final startedAt = now.toUtc();
    final baseline =
        awayDuration >= const Duration(seconds: 60) &&
            savedBaseline?.episodeKey == episodeKey &&
            savedBaseline!.isFresh &&
            !savedBaseline.observedAt.isAfter(startedAt)
        ? savedBaseline
        : null;
    return RiskCheckSession(
      episodeKey: episodeKey,
      startedAt: startedAt,
      baseline: baseline,
    );
  }

  RiskCheckSession observe(RiskHistorySample sample) {
    if (sample.episodeKey != episodeKey ||
        !sample.isFresh ||
        (latest != null && !sample.observedAt.isAfter(latest!.observedAt))) {
      return this;
    }
    final current = firstCurrent ?? sample;
    final nextComparison =
        baseline == null || !baseline!.isComparable || !current.isComparable
        ? null
        : _comparison(baseline!, current);
    return RiskCheckSession(
      episodeKey: episodeKey,
      startedAt: startedAt,
      baseline: baseline,
      firstCurrent: current,
      latest: sample,
      comparison: nextComparison,
    );
  }

  RiskHistorySample? get departureBaseline => latest ?? firstCurrent;

  RiskHistorySample? departure() => departureBaseline;

  static RiskSessionComparison _comparison(
    RiskHistorySample baseline,
    RiskHistorySample current,
  ) {
    double? delta(double? a, double? b) =>
        a != null && b != null ? b - a : null;
    final positionChanged = !_samePosition(baseline, current);
    return RiskSessionComparison(
      baseline: baseline,
      current: current,
      bufferDeltaPoints: positionChanged
          ? null
          : delta(baseline.bufferPercentage, current.bufferPercentage),
      leverageDelta: positionChanged
          ? null
          : delta(baseline.effectiveLeverage, current.effectiveLeverage),
      debtDelta: positionChanged ? null : delta(baseline.debt, current.debt),
      trueExitChanged:
          !positionChanged && baseline.trueExit != current.trueExit,
      structureChanged:
          !positionChanged && baseline.structureLabel != current.structureLabel,
      fundingChanged:
          !positionChanged && baseline.fundingLabel != current.fundingLabel,
      openInterestChanged:
          !positionChanged &&
          baseline.openInterestChange != current.openInterestChange,
      overallChanged:
          !positionChanged && baseline.overallState != current.overallState,
      positionChanged: positionChanged,
    );
  }
}

class RiskLocalTimeZone {
  const RiskLocalTimeZone({required this.name, this.offset = Duration.zero});

  final String name;
  final Duration offset;

  DateTime toLocal(DateTime utc) => utc.toUtc().add(offset);

  String dateKey(DateTime utc) {
    final value = toLocal(utc);
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year.toString().padLeft(4, '0')}-$month-$day';
  }
}

class RiskDailySummary {
  const RiskDailySummary({
    required this.episodeKey,
    required this.dateKey,
    required this.timeZone,
    required this.capturedAt,
    required this.quality,
    this.overallState,
    this.positionState,
    this.marketState,
    this.recoveryState,
    this.buffer,
    this.effectiveLeverage,
    this.actualInterestToday,
    this.knownInterestToday,
    this.actualInterestQuality,
    this.interestCoverageComplete = false,
    this.majorChange,
    this.activeRuleCount = 0,
    this.unknownRuleCount = 0,
  });

  final String episodeKey;
  final String dateKey;
  final String timeZone;
  final DateTime capturedAt;
  final RiskQuality quality;
  final RiskSeverity? overallState;
  final RiskSeverity? positionState;
  final RiskSeverity? marketState;
  final RiskSeverity? recoveryState;
  final double? buffer;
  final double? effectiveLeverage;
  final double? actualInterestToday;
  final double? knownInterestToday;
  final RiskQuality? actualInterestQuality;
  final bool interestCoverageComplete;
  final String? majorChange;
  final int activeRuleCount;
  final int unknownRuleCount;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'episodeKey': episodeKey,
    'dateKey': dateKey,
    'timeZone': timeZone,
    'capturedAt': capturedAt.toUtc().toIso8601String(),
    'quality': _qualityToJson(quality),
    'overallState': overallState?.name,
    'positionState': positionState?.name,
    'marketState': marketState?.name,
    'recoveryState': recoveryState?.name,
    'buffer': buffer,
    'effectiveLeverage': effectiveLeverage,
    'actualInterestToday': actualInterestToday,
    'knownInterestToday': knownInterestToday,
    'actualInterestQuality': actualInterestQuality == null
        ? null
        : _qualityToJson(actualInterestQuality!),
    'interestCoverageComplete': interestCoverageComplete,
    'majorChange': majorChange,
    'activeRuleCount': activeRuleCount,
    'unknownRuleCount': unknownRuleCount,
  };

  factory RiskDailySummary.fromJson(Map<String, dynamic> json) =>
      RiskDailySummary(
        episodeKey: _requiredString(json, 'episodeKey'),
        dateKey: _requiredString(json, 'dateKey'),
        timeZone: _requiredString(json, 'timeZone'),
        capturedAt: _requiredDate(json, 'capturedAt'),
        quality: _qualityFromJson(_requiredMap(json, 'quality')),
        overallState: _severityFromJson(json['overallState']),
        positionState: _severityFromJson(json['positionState']),
        marketState: _severityFromJson(json['marketState']),
        recoveryState: _severityFromJson(json['recoveryState']),
        buffer: _optionalDouble(json['buffer']),
        effectiveLeverage: _optionalDouble(json['effectiveLeverage']),
        actualInterestToday: _optionalDouble(json['actualInterestToday']),
        knownInterestToday: _optionalDouble(json['knownInterestToday']),
        actualInterestQuality: json['actualInterestQuality'] == null
            ? null
            : _qualityFromJson(_requiredMap(json, 'actualInterestQuality')),
        interestCoverageComplete:
            _optionalBool(json['interestCoverageComplete']) ?? false,
        majorChange: _optionalString(json['majorChange']),
        activeRuleCount: _requiredInt(json, 'activeRuleCount'),
        unknownRuleCount: _requiredInt(json, 'unknownRuleCount'),
      ).._validate();

  void _validate() {
    if (activeRuleCount < 0 || unknownRuleCount < 0) {
      throw const FormatException('Summary rule counts must be non-negative');
    }
  }
}

class RiskDailySummaryCapture {
  const RiskDailySummaryCapture._();

  static RiskDailySummary? capture({
    required RiskHistorySample sample,
    required RiskLocalTimeZone timeZone,
    required int summaryHour,
    int summaryMinute = 0,
    Iterable<RiskDailySummary> existing = const <RiskDailySummary>[],
    double? actualInterestToday,
    double? knownInterestToday,
    String? majorChange,
    int activeRuleCount = 0,
    int unknownRuleCount = 0,
  }) {
    if (!sample.isFresh || sample.episodeKey.trim().isEmpty) return null;
    final local = timeZone.toLocal(sample.observedAt);
    final afterSummary =
        local.hour > summaryHour ||
        (local.hour == summaryHour && local.minute >= summaryMinute);
    if (!afterSummary) return null;
    final date = timeZone.dateKey(sample.observedAt);
    if (existing.any(
      (item) =>
          item.episodeKey == sample.episodeKey &&
          item.dateKey == date &&
          item.timeZone == timeZone.name,
    )) {
      return null;
    }
    return RiskDailySummary(
      episodeKey: sample.episodeKey,
      dateKey: date,
      timeZone: timeZone.name,
      capturedAt: sample.observedAt,
      quality: sample.quality,
      overallState: sample.overallState,
      positionState: sample.positionState,
      marketState: sample.marketState,
      recoveryState: sample.recoveryState,
      buffer: sample.buffer,
      effectiveLeverage: sample.effectiveLeverage,
      actualInterestToday: actualInterestToday ?? sample.actualInterestToday,
      knownInterestToday: knownInterestToday ?? sample.knownInterestToday,
      actualInterestQuality: sample.actualInterestQuality,
      interestCoverageComplete: sample.interestCoverageComplete,
      majorChange: majorChange,
      activeRuleCount: activeRuleCount,
      unknownRuleCount: unknownRuleCount,
    );
  }
}

int _rank(RiskSeverity? value) => value?.rank ?? -1;

bool _samePosition(RiskHistorySample first, RiskHistorySample second) {
  bool same(double? a, double? b) {
    if (a == null || b == null || !a.isFinite || !b.isFinite) return false;
    final magnitude = a.abs() > b.abs() ? a.abs() : b.abs();
    final denominator = magnitude > 1e-12 ? magnitude : 1;
    return (a - b).abs() / denominator <= 0.001;
  }

  return same(first.quantity, second.quantity) &&
      same(first.margin, second.margin) &&
      same(first.debt, second.debt);
}

Map<String, dynamic> _qualityToJson(RiskQuality quality) => <String, dynamic>{
  'status': quality.status.name,
  'source': quality.source,
  'reason': quality.reason,
  'observedAt': quality.observedAt?.toUtc().toIso8601String(),
  'sourceAt': quality.sourceAt?.toUtc().toIso8601String(),
};

RiskQuality _qualityFromJson(Map<String, dynamic> json) {
  final statusText = _requiredString(json, 'status');
  final status = RiskQualityStatus.values.firstWhere(
    (value) => value.name == statusText,
    orElse: () => throw FormatException('Unknown quality status: $statusText'),
  );
  return RiskQuality(
    status: status,
    source: _optionalString(json['source']),
    reason: _optionalString(json['reason']),
    observedAt: _optionalDate(json['observedAt']),
    sourceAt: _optionalDate(json['sourceAt']),
  );
}

RiskSeverity? _severityFromJson(Object? value) {
  if (value == null) return null;
  if (value is! String) throw const FormatException('Invalid severity');
  return RiskSeverity.values.firstWhere(
    (item) => item.name == value,
    orElse: () => throw FormatException('Unknown severity: $value'),
  );
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string');
  }
  return value;
}

String? _optionalString(Object? value) => value is String ? value : null;

bool? _optionalBool(Object? value) {
  if (value == null) return null;
  if (value is! bool) throw const FormatException('Expected boolean');
  return value;
}

DateTime _requiredDate(Map<String, dynamic> json, String key) {
  final value = _optionalDate(json[key]);
  if (value == null) throw FormatException('$key must be an ISO timestamp');
  return value;
}

DateTime? _optionalDate(Object? value) {
  if (value == null) return null;
  if (value is! String) throw const FormatException('Invalid timestamp');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw const FormatException('Invalid timestamp');
  return parsed.toUtc();
}

double? _optionalDouble(Object? value) {
  if (value == null) return null;
  if (value is! num || !value.toDouble().isFinite) {
    throw const FormatException('Expected finite number');
  }
  return value.toDouble();
}

void _requireFinite(double? value, String name) {
  if (value != null && !value.isFinite) {
    throw FormatException('$name is not finite');
  }
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! Map) throw FormatException('$key must be an object');
  return value.map<String, dynamic>(
    (itemKey, itemValue) => MapEntry(itemKey.toString(), itemValue),
  );
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num || value % 1 != 0) {
    throw FormatException('$key must be integer');
  }
  return value.toInt();
}
