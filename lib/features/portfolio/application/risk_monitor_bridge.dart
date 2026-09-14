import 'dart:async';

import '../domain/risk/action_plan.dart';
import '../domain/risk/risk_events.dart';
import '../domain/risk/risk_history.dart';
import '../domain/risk/risk_models.dart';
import 'risk_notification_sink.dart';

enum RiskMonitorCommandType {
  start,
  stop,
  refresh,
  reconnect,
  updatePlan,
  updateSettings,
  clearHistory,
  invalidateCredentials,
  uiDeparture,
  uiResume,
}

enum RiskMonitorCommandStatus { accepted, duplicate, rejected, failed }

class RiskMonitorCommand {
  const RiskMonitorCommand({
    required this.id,
    required this.type,
    required this.issuedAt,
    this.accountHash,
    this.episodeKey,
    this.plan,
    this.settings,
    this.reason,
  });

  final String id;
  final RiskMonitorCommandType type;
  final DateTime issuedAt;
  final String? accountHash;
  final String? episodeKey;
  final RiskPlan? plan;
  final RiskSettings? settings;
  final String? reason;

  factory RiskMonitorCommand.start({
    required String id,
    DateTime? issuedAt,
    String? accountHash,
    String? episodeKey,
  }) => RiskMonitorCommand(
    id: id,
    type: RiskMonitorCommandType.start,
    issuedAt: (issuedAt ?? DateTime.now().toUtc()).toUtc(),
    accountHash: accountHash,
    episodeKey: episodeKey,
  );

  factory RiskMonitorCommand.stop({required String id, DateTime? issuedAt}) =>
      RiskMonitorCommand(
        id: id,
        type: RiskMonitorCommandType.stop,
        issuedAt: (issuedAt ?? DateTime.now().toUtc()).toUtc(),
      );

  factory RiskMonitorCommand.refresh({
    required String id,
    DateTime? issuedAt,
  }) => RiskMonitorCommand(
    id: id,
    type: RiskMonitorCommandType.refresh,
    issuedAt: (issuedAt ?? DateTime.now().toUtc()).toUtc(),
  );

  factory RiskMonitorCommand.reconnect({
    required String id,
    DateTime? issuedAt,
  }) => RiskMonitorCommand(
    id: id,
    type: RiskMonitorCommandType.reconnect,
    issuedAt: (issuedAt ?? DateTime.now().toUtc()).toUtc(),
  );

  factory RiskMonitorCommand.updatePlan({
    required String id,
    required RiskPlan plan,
    String? episodeKey,
    DateTime? issuedAt,
  }) => RiskMonitorCommand(
    id: id,
    type: RiskMonitorCommandType.updatePlan,
    issuedAt: (issuedAt ?? DateTime.now().toUtc()).toUtc(),
    episodeKey: episodeKey ?? plan.episodeKey,
    plan: plan,
  );

  factory RiskMonitorCommand.updateSettings({
    required String id,
    required RiskSettings settings,
    DateTime? issuedAt,
  }) => RiskMonitorCommand(
    id: id,
    type: RiskMonitorCommandType.updateSettings,
    issuedAt: (issuedAt ?? DateTime.now().toUtc()).toUtc(),
    settings: settings,
  );

  factory RiskMonitorCommand.clearHistory({
    required String id,
    String? episodeKey,
    DateTime? issuedAt,
  }) => RiskMonitorCommand(
    id: id,
    type: RiskMonitorCommandType.clearHistory,
    issuedAt: (issuedAt ?? DateTime.now().toUtc()).toUtc(),
    episodeKey: episodeKey,
  );

  factory RiskMonitorCommand.invalidateCredentials({
    required String id,
    String? reason,
    DateTime? issuedAt,
  }) => RiskMonitorCommand(
    id: id,
    type: RiskMonitorCommandType.invalidateCredentials,
    issuedAt: (issuedAt ?? DateTime.now().toUtc()).toUtc(),
    reason: reason,
  );

  factory RiskMonitorCommand.uiDeparture({
    required String id,
    DateTime? issuedAt,
  }) => RiskMonitorCommand(
    id: id,
    type: RiskMonitorCommandType.uiDeparture,
    issuedAt: (issuedAt ?? DateTime.now().toUtc()).toUtc(),
  );

  factory RiskMonitorCommand.uiResume({
    required String id,
    DateTime? issuedAt,
  }) => RiskMonitorCommand(
    id: id,
    type: RiskMonitorCommandType.uiResume,
    issuedAt: (issuedAt ?? DateTime.now().toUtc()).toUtc(),
  );

  Map<String, dynamic> toWire() => <String, dynamic>{
    'id': id,
    'type': type.name,
    'issuedAt': issuedAt.toUtc().toIso8601String(),
    'accountHash': accountHash,
    'episodeKey': episodeKey,
    'plan': plan?.toJson(),
    'settings': settings?.toJson(),
    'reason': reason,
  };

  factory RiskMonitorCommand.fromWire(Map<String, dynamic> wire) {
    final id = wire['id']?.toString() ?? '';
    final typeText = wire['type']?.toString();
    final type = RiskMonitorCommandType.values.firstWhere(
      (value) => value.name == typeText,
      orElse: () => throw const FormatException('Unknown risk command type'),
    );
    final issuedAt = DateTime.tryParse(wire['issuedAt']?.toString() ?? '');
    if (id.trim().isEmpty || issuedAt == null) {
      throw const FormatException('Risk command identity is invalid');
    }
    final planJson = wire['plan'];
    final settingsJson = wire['settings'];
    return RiskMonitorCommand(
      id: id,
      type: type,
      issuedAt: issuedAt.toUtc(),
      accountHash: wire['accountHash']?.toString(),
      episodeKey: wire['episodeKey']?.toString(),
      plan: planJson is Map
          ? RiskPlan.fromJson(Map<String, dynamic>.from(planJson))
          : null,
      settings: settingsJson is Map
          ? RiskSettings.fromJson(Map<String, dynamic>.from(settingsJson))
          : null,
      reason: wire['reason']?.toString(),
    );
  }
}

/// Aggregate request state for the single monitor owner.  This is deliberately
/// separate from [RiskQuality]: quality describes an observation/position,
/// while this value describes the account-wide capture request lifecycle.
enum RiskMonitorRequestStatus {
  ready,
  refreshing,
  backingOff,
  authBlocked,
  partial,
  unavailable,
}

/// Alias for callers that use the shorter request-status terminology.
typedef RiskRequestStatus = RiskMonitorRequestStatus;

/// Immutable state for one active position episode.
///
/// Every field that used to live on the singular monitor state is kept at the
/// episode grain here.  [positionSide] remains explicit even though the
/// current financial contract is long-only, leaving a stable seam for a
/// future short isolated-margin evaluator without changing ownership or
/// persistence routing.
class RiskPositionMonitorViewState {
  RiskPositionMonitorViewState({
    this.positionId,
    this.episodeKey = '',
    String? positionSide,
    String? direction,
    this.position,
    this.evaluation,
    this.planEvaluation,
    RiskPlan? plan,
    RiskSettings? settings,
    this.market,
    List<RiskHistorySample> samples = const <RiskHistorySample>[],
    List<RiskDailySummary> summaries = const <RiskDailySummary>[],
    this.previousCheck,
    this.trend,
    this.velocity,
    List<RiskEvent> events = const <RiskEvent>[],
    this.quality = const RiskQuality.unavailable(
      reason: 'Position has not observed a snapshot',
    ),
    this.unsaved = false,
    this.lastError,
    this.freshnessAt,
  }) : positionSide = direction ?? positionSide ?? 'long',
       plan = _freezePlan(plan),
       settings = _freezeSettings(settings),
       samples = List<RiskHistorySample>.unmodifiable(samples),
       summaries = List<RiskDailySummary>.unmodifiable(summaries),
       events = List<RiskEvent>.unmodifiable(events);

  final String? positionId;
  final String episodeKey;
  final String positionSide;
  final RiskPosition? position;
  final RiskEvaluation? evaluation;
  final RiskPlanEvaluation? planEvaluation;
  final RiskPlan? plan;
  final RiskSettings? settings;
  final RiskMarketInput? market;
  final List<RiskHistorySample> samples;
  final List<RiskDailySummary> summaries;
  final RiskSessionComparison? previousCheck;
  final RiskTrendResult? trend;
  final RiskVelocityResult? velocity;
  final List<RiskEvent> events;
  final RiskQuality quality;
  final bool unsaved;
  final String? lastError;
  final DateTime? freshnessAt;

  /// Direction is intentionally exposed as a string for wire compatibility
  /// with the existing [RiskPosition.positionSide] contract.
  String get direction => positionSide;

  String get positionDirection => positionSide;

  bool get isLong {
    final normalized = positionSide.toLowerCase();
    return normalized != 'short' && normalized != 'sell';
  }

  /// The latest trustworthy freshness marker for this episode.
  DateTime? get freshness =>
      freshnessAt ?? quality.observedAt ?? position?.observedAt;

  RiskPositionMonitorViewState copyWith({
    String? positionId,
    String? episodeKey,
    String? positionSide,
    RiskPosition? position,
    RiskEvaluation? evaluation,
    RiskPlanEvaluation? planEvaluation,
    RiskPlan? plan,
    RiskSettings? settings,
    RiskMarketInput? market,
    List<RiskHistorySample>? samples,
    List<RiskDailySummary>? summaries,
    RiskSessionComparison? previousCheck,
    RiskTrendResult? trend,
    RiskVelocityResult? velocity,
    List<RiskEvent>? events,
    RiskQuality? quality,
    bool? unsaved,
    String? lastError,
    DateTime? freshnessAt,
    bool clearEvaluation = false,
    bool clearPlanEvaluation = false,
    bool clearPlan = false,
    bool clearSettings = false,
    bool clearMarket = false,
    bool clearPreviousCheck = false,
    bool clearTrend = false,
    bool clearVelocity = false,
    bool clearError = false,
    bool clearFreshness = false,
  }) {
    return RiskPositionMonitorViewState(
      positionId: positionId ?? this.positionId,
      episodeKey: episodeKey ?? this.episodeKey,
      positionSide: positionSide ?? this.positionSide,
      position: position ?? this.position,
      evaluation: clearEvaluation ? null : evaluation ?? this.evaluation,
      planEvaluation: clearPlanEvaluation
          ? null
          : planEvaluation ?? this.planEvaluation,
      plan: clearPlan ? null : plan ?? this.plan,
      settings: clearSettings ? null : settings ?? this.settings,
      market: clearMarket ? null : market ?? this.market,
      samples: samples ?? this.samples,
      summaries: summaries ?? this.summaries,
      previousCheck: clearPreviousCheck
          ? null
          : previousCheck ?? this.previousCheck,
      trend: clearTrend ? null : trend ?? this.trend,
      velocity: clearVelocity ? null : velocity ?? this.velocity,
      events: events ?? this.events,
      quality: quality ?? this.quality,
      unsaved: unsaved ?? this.unsaved,
      lastError: clearError ? null : lastError ?? this.lastError,
      freshnessAt: clearFreshness ? null : freshnessAt ?? this.freshnessAt,
    );
  }
}

class RiskMonitorViewState {
  RiskMonitorViewState({
    this.isRunning = false,
    this.backgroundAvailable = false,
    this.ownerLabel = 'foreground',
    this.accountHash,
    this.episodeKey,
    this.evaluation,
    this.planEvaluation,
    RiskPlan? plan,
    RiskSettings? settings,
    RiskMarketInput? market,
    List<RiskHistorySample>? samples,
    List<RiskDailySummary>? summaries,
    this.previousCheck,
    this.trend,
    this.velocity,
    List<RiskEvent> events = const <RiskEvent>[],
    this.quality = const RiskQuality.unavailable(
      reason: 'Monitor has not observed a snapshot',
    ),
    this.unsaved = false,
    this.lastError,
    this.notificationCapability = RiskNotificationCapabilityStatus.unavailable,
    List<RiskPositionMonitorViewState> positions =
        const <RiskPositionMonitorViewState>[],
    this.requestStatus = RiskMonitorRequestStatus.unavailable,
    this.retryAt,
    this.requestEndpointClass,
  }) : plan = _freezePlan(plan),
       settings = _freezeSettings(settings),
       market = _freezeMarket(market),
       samples = samples == null
           ? null
           : List<RiskHistorySample>.unmodifiable(samples),
       summaries = summaries == null
           ? null
           : List<RiskDailySummary>.unmodifiable(summaries),
       events = List<RiskEvent>.unmodifiable(events),
       positions = List<RiskPositionMonitorViewState>.unmodifiable(positions);

  final bool isRunning;
  final bool backgroundAvailable;
  final String ownerLabel;
  final String? accountHash;
  final String? episodeKey;
  final RiskEvaluation? evaluation;
  final RiskPlanEvaluation? planEvaluation;
  final RiskPlan? plan;
  final RiskSettings? settings;
  final RiskMarketInput? market;
  final List<RiskHistorySample>? samples;
  final List<RiskDailySummary>? summaries;
  final RiskSessionComparison? previousCheck;
  final RiskTrendResult? trend;
  final RiskVelocityResult? velocity;
  final List<RiskEvent> events;
  final RiskQuality quality;
  final bool unsaved;
  final String? lastError;
  final RiskNotificationCapabilityStatus notificationCapability;
  final List<RiskPositionMonitorViewState> positions;
  final RiskMonitorRequestStatus requestStatus;
  final DateTime? retryAt;
  final String? requestEndpointClass;

  /// Naming aliases keep bridge consumers independent from the implementation
  /// detail that the aggregate is stored as a list on the root state.
  List<RiskPositionMonitorViewState> get positionStates => positions;
  List<RiskPositionMonitorViewState> get positionEntries => positions;
  List<RiskPositionMonitorViewState> get aggregatePositions => positions;
  RiskMonitorRequestStatus get aggregateRequestStatus => requestStatus;
  DateTime? get nextRetryAt => retryAt;
  String? get endpointClass => requestEndpointClass;
  RiskPositionMonitorViewState? get primaryPosition {
    if (positions.isEmpty) return null;
    final selectedEpisode = episodeKey;
    if (selectedEpisode != null) {
      for (final position in positions) {
        if (position.episodeKey == selectedEpisode) return position;
      }
    }
    return positions.first;
  }

  RiskMonitorViewState copyWith({
    bool? isRunning,
    bool? backgroundAvailable,
    String? ownerLabel,
    String? accountHash,
    String? episodeKey,
    RiskEvaluation? evaluation,
    RiskPlanEvaluation? planEvaluation,
    RiskPlan? plan,
    RiskSettings? settings,
    RiskMarketInput? market,
    List<RiskHistorySample>? samples,
    List<RiskDailySummary>? summaries,
    RiskSessionComparison? previousCheck,
    RiskTrendResult? trend,
    RiskVelocityResult? velocity,
    List<RiskEvent>? events,
    RiskQuality? quality,
    bool? unsaved,
    String? lastError,
    RiskNotificationCapabilityStatus? notificationCapability,
    List<RiskPositionMonitorViewState>? positions,
    RiskMonitorRequestStatus? requestStatus,
    DateTime? retryAt,
    String? requestEndpointClass,
    bool clearEvaluation = false,
    bool clearPlanEvaluation = false,
    bool clearPlan = false,
    bool clearSettings = false,
    bool clearMarket = false,
    bool clearSamples = false,
    bool clearSummaries = false,
    bool clearPreviousCheck = false,
    bool clearTrend = false,
    bool clearVelocity = false,
    bool clearError = false,
    bool clearPositions = false,
    bool clearRetryAt = false,
    bool clearRequestEndpointClass = false,
  }) {
    return RiskMonitorViewState(
      isRunning: isRunning ?? this.isRunning,
      backgroundAvailable: backgroundAvailable ?? this.backgroundAvailable,
      ownerLabel: ownerLabel ?? this.ownerLabel,
      accountHash: accountHash ?? this.accountHash,
      episodeKey: episodeKey ?? this.episodeKey,
      evaluation: clearEvaluation ? null : evaluation ?? this.evaluation,
      planEvaluation: clearPlanEvaluation
          ? null
          : planEvaluation ?? this.planEvaluation,
      plan: clearPlan ? null : plan ?? this.plan,
      settings: clearSettings ? null : settings ?? this.settings,
      market: clearMarket ? null : market ?? this.market,
      samples: clearSamples
          ? const <RiskHistorySample>[]
          : samples ?? this.samples,
      summaries: clearSummaries
          ? const <RiskDailySummary>[]
          : summaries ?? this.summaries,
      previousCheck: clearPreviousCheck
          ? null
          : previousCheck ?? this.previousCheck,
      trend: clearTrend ? null : trend ?? this.trend,
      velocity: clearVelocity ? null : velocity ?? this.velocity,
      events: events ?? this.events,
      quality: quality ?? this.quality,
      unsaved: unsaved ?? this.unsaved,
      lastError: clearError ? null : lastError ?? this.lastError,
      notificationCapability:
          notificationCapability ?? this.notificationCapability,
      positions: clearPositions
          ? const <RiskPositionMonitorViewState>[]
          : positions ?? this.positions,
      requestStatus: requestStatus ?? this.requestStatus,
      retryAt: clearRetryAt ? null : retryAt ?? this.retryAt,
      requestEndpointClass: clearRequestEndpointClass
          ? null
          : requestEndpointClass ?? this.requestEndpointClass,
    );
  }
}

RiskPlan? _freezePlan(RiskPlan? value) {
  if (value == null) return null;
  return RiskPlan(
    episodeKey: value.episodeKey,
    rules: List<RiskRule>.unmodifiable(value.rules),
    zones: List<RiskZone>.unmodifiable(value.zones),
  );
}

RiskSettings? _freezeSettings(RiskSettings? value) {
  if (value == null) return null;
  return value.copyWith(
    customStressChanges: List<double>.unmodifiable(value.customStressChanges),
    customStressPrices: List<double>.unmodifiable(value.customStressPrices),
  );
}

RiskMarketInput? _freezeMarket(RiskMarketInput? value) {
  if (value == null) return null;
  return RiskMarketInput(
    state: value.state,
    complete: value.complete,
    dailyVolatility: value.dailyVolatility,
    reasons: List<RiskReason>.unmodifiable(value.reasons),
    missingReasons: List<String>.unmodifiable(value.missingReasons),
    support: value.support,
    resistance: value.resistance,
    source: value.source,
    observedAt: value.observedAt,
    sourceAt: value.sourceAt,
    marketContextLabel: value.marketContextLabel,
    assetInstrument: value.assetInstrument,
    btcInstrument: value.btcInstrument,
    derivativesInstrument: value.derivativesInstrument,
    volatilityLabel: value.volatilityLabel,
    assetStructureLabel: value.assetStructureLabel,
    btcStructureLabel: value.btcStructureLabel,
    volumePressureLabel: value.volumePressureLabel,
    fundingLabel: value.fundingLabel,
    openInterestLabel: value.openInterestLabel,
    normalizedFunding8h: value.normalizedFunding8h,
    fundingIntervalHours: value.fundingIntervalHours,
    openInterestChange: value.openInterestChange,
    marketPriceChange: value.marketPriceChange,
    fundingQuality: value.fundingQuality,
    openInterestQuality: value.openInterestQuality,
    marketPoints: value.marketPoints,
    assetPoints: value.assetPoints,
    fundingPoints: value.fundingPoints,
    openInterestPoints: value.openInterestPoints,
  );
}

String? _wireDate(DateTime? value) => value?.toUtc().toIso8601String();

DateTime? _wireDateValue(Object? value) {
  final text = value?.toString();
  return text == null ? null : DateTime.tryParse(text)?.toUtc();
}

DateTime _wireRequiredDate(Object? value) =>
    _wireDateValue(value) ??
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

Map<String, dynamic>? _wireMap(Object? value) {
  if (value is! Map) return null;
  return Map<String, dynamic>.from(value);
}

double? _wireDouble(Object? value) => value is num
    ? value.toDouble()
    : value == null
    ? null
    : double.tryParse(value.toString());

RiskSeverity? _wireSeverity(Object? value) {
  final text = value?.toString();
  if (text == null) return null;
  return RiskSeverity.values.firstWhere(
    (item) => item.name == text,
    orElse: () => throw FormatException('Unknown risk severity: $text'),
  );
}

RiskQuality _wireQuality(Object? value) {
  final map = _wireMap(value);
  if (map == null) {
    return const RiskQuality.unavailable(reason: 'Quality was not encoded');
  }
  final statusText = map['status']?.toString();
  final status = RiskQualityStatus.values.firstWhere(
    (item) => item.name == statusText,
    orElse: () => RiskQualityStatus.unavailable,
  );
  return RiskQuality(
    status: status,
    source: map['source']?.toString(),
    reason: map['reason']?.toString(),
    observedAt: _wireDateValue(map['observedAt']),
    sourceAt: _wireDateValue(map['sourceAt']),
  );
}

Map<String, dynamic> _qualityWire(RiskQuality value) => <String, dynamic>{
  'status': value.status.name,
  'source': value.source,
  'reason': value.reason,
  'observedAt': _wireDate(value.observedAt),
  'sourceAt': _wireDate(value.sourceAt),
};

Map<String, dynamic> _reasonWire(RiskReason value) => <String, dynamic>{
  'factorId': value.factorId,
  'message': value.message,
  'severity': value.severity?.name,
  'observedValue': value.observedValue,
  'threshold': value.threshold,
  'unit': value.unit,
  'window': value.window,
  'observedAt': _wireDate(value.observedAt),
  'source': value.source,
  'evidence': value.evidence,
};

RiskReason _reasonFromWire(Object? value) {
  final map = _wireMap(value) ?? const <String, dynamic>{};
  return RiskReason(
    factorId: map['factorId']?.toString() ?? '',
    message: map['message']?.toString() ?? '',
    severity: _wireSeverity(map['severity']),
    observedValue: _wireDouble(map['observedValue']),
    threshold: map['threshold']?.toString(),
    unit: map['unit']?.toString(),
    window: map['window']?.toString(),
    observedAt: _wireDateValue(map['observedAt']),
    source: map['source']?.toString(),
    evidence: map['evidence']?.toString(),
  );
}

List<RiskReason> _reasonsFromWire(Object? value) => value is List
    ? value.map(_reasonFromWire).toList(growable: false)
    : const <RiskReason>[];

Map<String, dynamic> _metricWire(RiskMetricValue value) => <String, dynamic>{
  'value': value.value,
  'unit': value.unit,
  'quality': _qualityWire(value.quality),
  'source': value.source,
  'observedAt': _wireDate(value.observedAt),
  'sourceAt': _wireDate(value.sourceAt),
};

RiskMetricValue _metricFromWire(Object? value, {String fallbackUnit = ''}) {
  final map = _wireMap(value) ?? const <String, dynamic>{};
  return RiskMetricValue(
    value: _wireDouble(map['value']),
    unit: map['unit']?.toString() ?? fallbackUnit,
    quality: _wireQuality(map['quality']),
    source: map['source']?.toString(),
    observedAt: _wireDateValue(map['observedAt']),
    sourceAt: _wireDateValue(map['sourceAt']),
  );
}

Map<String, dynamic> _assessmentWire(RiskAssessment value) => <String, dynamic>{
  'state': value.state?.name,
  'quality': _qualityWire(value.quality),
  'reasons': value.reasons.map(_reasonWire).toList(growable: false),
  'missingReasons': value.missingReasons,
  'label': value.label,
};

RiskAssessment _assessmentFromWire(Object? value) {
  final map = _wireMap(value) ?? const <String, dynamic>{};
  return RiskAssessment(
    state: _wireSeverity(map['state']),
    quality: _wireQuality(map['quality']),
    reasons: _reasonsFromWire(map['reasons']),
    missingReasons: map['missingReasons'] is List
        ? List<String>.from(
            (map['missingReasons'] as List).map((item) => item.toString()),
          )
        : const <String>[],
    label: map['label']?.toString(),
  );
}

Map<String, dynamic> _coverageWire(RiskCostCoverage value) => <String, dynamic>{
  'complete': value.complete,
  'reason': value.reason,
  'ledgerComplete': value.ledgerComplete,
  'sizeUnchanged': value.sizeUnchanged,
  'positionOpenedAt': _wireDate(value.positionOpenedAt),
  'coverageFrom': _wireDate(value.coverageFrom),
  'coverageTo': _wireDate(value.coverageTo),
  'nonOverlapAt': _wireDate(value.nonOverlapAt),
};

RiskCostCoverage _coverageFromWire(Object? value) {
  final map = _wireMap(value) ?? const <String, dynamic>{};
  return RiskCostCoverage(
    complete: map['complete'] == true,
    reason: map['reason']?.toString(),
    ledgerComplete: map['ledgerComplete'] == true,
    sizeUnchanged: map['sizeUnchanged'] == true,
    positionOpenedAt: _wireDateValue(map['positionOpenedAt']),
    coverageFrom: _wireDateValue(map['coverageFrom']),
    coverageTo: _wireDateValue(map['coverageTo']),
    nonOverlapAt: _wireDateValue(map['nonOverlapAt']),
  );
}

Map<String, dynamic> _actualInterestWire(RiskActualInterestToday value) =>
    <String, dynamic>{
      'amount': value.amount,
      'knownSubtotal': value.knownSubtotal,
      'windowStart': _wireDate(value.windowStart),
      'windowEnd': _wireDate(value.windowEnd),
      'quality': _qualityWire(value.quality),
      'coverageComplete': value.coverageComplete,
      'observedAt': _wireDate(value.observedAt),
      'sourceAt': _wireDate(value.sourceAt),
      'source': value.source,
    };

RiskActualInterestToday _actualInterestFromWire(Object? value) {
  final map = _wireMap(value) ?? const <String, dynamic>{};
  return RiskActualInterestToday(
    amount: _wireDouble(map['amount']),
    knownSubtotal: _wireDouble(map['knownSubtotal']) ?? 0,
    windowStart: _wireRequiredDate(map['windowStart']),
    windowEnd: _wireRequiredDate(map['windowEnd']),
    quality: _wireQuality(map['quality']),
    coverageComplete: map['coverageComplete'] == true,
    observedAt: _wireDateValue(map['observedAt']),
    sourceAt: _wireDateValue(map['sourceAt']),
    source: map['source']?.toString(),
  );
}

Map<String, dynamic> _costsWire(RiskCostAttribution value) => <String, dynamic>{
  'settledInterest': value.settledInterest,
  'unbilledInterest': value.unbilledInterest,
  'additionalActualCosts': value.additionalActualCosts,
  'actualInterestToday': value.actualInterestToday == null
      ? null
      : _actualInterestWire(value.actualInterestToday!),
  'coverage': _coverageWire(value.coverage),
  'observedAt': _wireDate(value.observedAt),
  'source': value.source,
};

RiskCostAttribution _costsFromWire(Object? value) {
  final map = _wireMap(value) ?? const <String, dynamic>{};
  return RiskCostAttribution(
    settledInterest: _wireDouble(map['settledInterest']),
    unbilledInterest: _wireDouble(map['unbilledInterest']),
    additionalActualCosts: _wireDouble(map['additionalActualCosts']),
    actualInterestToday: map['actualInterestToday'] == null
        ? null
        : _actualInterestFromWire(map['actualInterestToday']),
    coverage: _coverageFromWire(map['coverage']),
    observedAt: _wireDateValue(map['observedAt']),
    source: map['source']?.toString(),
  );
}

Map<String, dynamic> _positionWire(RiskPosition value) => <String, dynamic>{
  'instrumentId': value.instrumentId,
  'instrumentType': value.instrumentType,
  'mode': value.mode.name,
  'collateralCurrency': value.collateralCurrency.name,
  'positionSide': value.positionSide,
  'accountNamespace': value.accountNamespace,
  'positionId': value.positionId,
  'createdAt': _wireDate(value.createdAt),
  'updatedAt': _wireDate(value.updatedAt),
  'observedAt': _wireDate(value.observedAt),
  'baseCurrency': value.baseCurrency,
  'quoteCurrency': value.quoteCurrency,
  'positionCurrency': value.positionCurrency,
  'accountCurrency': value.accountCurrency,
  'liabilityCurrency': value.liabilityCurrency,
  'rawQuantity': value.rawQuantity,
  'quantity': value.quantity,
  'margin': value.margin,
  'markPrice': value.markPrice,
  'entryPrice': value.entryPrice,
  'liquidationPrice': value.liquidationPrice,
  'unrealizedPnl': value.unrealizedPnl,
  'reportedLeverage': value.reportedLeverage,
  'marginRatio': value.marginRatio,
  'maintenanceRequirement': value.maintenanceRequirement,
  'reportedLiability': value.reportedLiability,
  'reportedInterest': value.reportedInterest,
  'baseBalance': value.baseBalance,
  'quoteBalance': value.quoteBalance,
  'baseBorrowed': value.baseBorrowed,
  'quoteBorrowed': value.quoteBorrowed,
  'baseInterest': value.baseInterest,
  'quoteInterest': value.quoteInterest,
  'hourlyBorrowRate': value.hourlyBorrowRate,
  'entryFeeRate': value.entryFeeRate,
  'exitFeeRate': value.exitFeeRate,
  'costAttribution': _costsWire(value.costAttribution),
  'quality': _qualityWire(value.quality),
  'eligibility': value.eligibility.name,
  'source': value.source,
};

RiskPosition _positionFromWire(Object? value) {
  final map = _wireMap(value) ?? const <String, dynamic>{};
  T enumValue<T>(Iterable<T> values, String? name, T fallback) =>
      values.firstWhere(
        (item) => item.toString().split('.').last == name,
        orElse: () => fallback,
      );
  return RiskPosition(
    instrumentId: map['instrumentId']?.toString() ?? '',
    instrumentType: map['instrumentType']?.toString() ?? 'MARGIN',
    mode: enumValue(
      RiskAccountMode.values,
      map['mode']?.toString(),
      RiskAccountMode.unsupported,
    ),
    collateralCurrency: enumValue(
      RiskCollateralCurrency.values,
      map['collateralCurrency']?.toString(),
      RiskCollateralCurrency.unsupported,
    ),
    positionSide: map['positionSide']?.toString() ?? 'net',
    accountNamespace: map['accountNamespace']?.toString(),
    positionId: map['positionId']?.toString(),
    createdAt: _wireDateValue(map['createdAt']),
    updatedAt: _wireDateValue(map['updatedAt']),
    observedAt: _wireDateValue(map['observedAt']),
    baseCurrency: map['baseCurrency']?.toString(),
    quoteCurrency: map['quoteCurrency']?.toString() ?? 'USDT',
    positionCurrency: map['positionCurrency']?.toString(),
    accountCurrency: map['accountCurrency']?.toString(),
    liabilityCurrency: map['liabilityCurrency']?.toString(),
    rawQuantity: _wireDouble(map['rawQuantity']),
    quantity: _wireDouble(map['quantity']),
    margin: _wireDouble(map['margin']),
    markPrice: _wireDouble(map['markPrice']),
    entryPrice: _wireDouble(map['entryPrice']),
    liquidationPrice: _wireDouble(map['liquidationPrice']),
    unrealizedPnl: _wireDouble(map['unrealizedPnl']),
    reportedLeverage: _wireDouble(map['reportedLeverage']),
    marginRatio: _wireDouble(map['marginRatio']),
    maintenanceRequirement: _wireDouble(map['maintenanceRequirement']),
    reportedLiability: _wireDouble(map['reportedLiability']),
    reportedInterest: _wireDouble(map['reportedInterest']),
    baseBalance: _wireDouble(map['baseBalance']),
    quoteBalance: _wireDouble(map['quoteBalance']),
    baseBorrowed: _wireDouble(map['baseBorrowed']),
    quoteBorrowed: _wireDouble(map['quoteBorrowed']),
    baseInterest: _wireDouble(map['baseInterest']),
    quoteInterest: _wireDouble(map['quoteInterest']),
    hourlyBorrowRate: _wireDouble(map['hourlyBorrowRate']),
    entryFeeRate: _wireDouble(map['entryFeeRate']),
    exitFeeRate: _wireDouble(map['exitFeeRate']),
    costAttribution: _costsFromWire(map['costAttribution']),
    quality: _wireQuality(map['quality']),
    eligibility: enumValue(
      RiskEligibility.values,
      map['eligibility']?.toString(),
      RiskEligibility.invalid,
    ),
    source: map['source']?.toString(),
  );
}

Map<String, dynamic> _evaluationWire(RiskEvaluation value) => <String, dynamic>{
  'position': _positionWire(value.position),
  'metrics': <String, dynamic>{
    'quantity': _metricWire(value.metrics.quantity),
    'markPrice': _metricWire(value.metrics.markPrice),
    'entryPrice': _metricWire(value.metrics.entryPrice),
    'liquidationPrice': _metricWire(value.metrics.liquidationPrice),
    'margin': _metricWire(value.metrics.margin),
    'equity': _metricWire(value.metrics.equity),
    'debt': _metricWire(value.metrics.debt),
    'principalDebt': _metricWire(value.metrics.principalDebt),
    'tradeNotional': _metricWire(value.metrics.tradeNotional),
    'grossAssetExposure': _metricWire(value.metrics.grossAssetExposure),
    'effectiveLeverage': _metricWire(value.metrics.effectiveLeverage),
    'buffer': _metricWire(value.metrics.buffer),
    'marginRatio': _metricWire(value.metrics.marginRatio),
    'maintenanceRequirement': _metricWire(value.metrics.maintenanceRequirement),
    'tradeSensitivityPerPoint': _metricWire(
      value.metrics.tradeSensitivityPerPoint,
    ),
    'tradeSensitivityPerPercent': _metricWire(
      value.metrics.tradeSensitivityPerPercent,
    ),
    'equitySensitivityPerPoint': _metricWire(
      value.metrics.equitySensitivityPerPoint,
    ),
    'equitySensitivityPerPercent': _metricWire(
      value.metrics.equitySensitivityPerPercent,
    ),
    'distanceToEntry': _metricWire(value.metrics.distanceToEntry),
    'distanceToTrueExit': _metricWire(value.metrics.distanceToTrueExit),
    'actualInterestToday': _metricWire(value.metrics.actualInterestToday),
    'knownInterestToday': _metricWire(value.metrics.knownInterestToday),
    'trueExitPrice': _metricWire(value.metrics.trueExitPrice),
    'projectedTrueExitPrice': _metricWire(value.metrics.projectedTrueExitPrice),
    'knownCostExitPrice': _metricWire(value.metrics.knownCostExitPrice),
    'holdingCostPerDay': _metricWire(value.metrics.holdingCostPerDay),
    'holdingCost7d': _metricWire(value.metrics.holdingCost7d),
    'holdingCost30d': _metricWire(value.metrics.holdingCost30d),
    'recoveryDistance': _metricWire(value.metrics.recoveryDistance),
    'holdingBurden': _metricWire(value.metrics.holdingBurden),
    'tradePnl': _metricWire(value.metrics.tradePnl),
  },
  'positionAssessment': _assessmentWire(value.positionAssessment),
  'marketAssessment': _assessmentWire(value.marketAssessment),
  'recoveryAssessment': _assessmentWire(value.recoveryAssessment),
  'overallState': value.overallState?.name,
  'quality': _qualityWire(value.quality),
  'reasons': value.reasons.map(_reasonWire).toList(growable: false),
  'stressScenarios': value.stressScenarios
      .map(_stressWire)
      .toList(growable: false),
  'priceMap': value.priceMap.map(_priceMapWire).toList(growable: false),
  'evaluatedAt': _wireDate(value.evaluatedAt),
  'policyVersion': value.policyVersion,
  'missingReasons': value.missingReasons,
  'exchangePnlBasis': value.exchangePnlBasis,
};

Map<String, dynamic> _stressWire(RiskStressScenario value) => <String, dynamic>{
  'label': value.label,
  'price': value.price,
  'percentageChange': value.percentageChange,
  'tradePnl': value.tradePnl,
  'equity': value.equity,
  'effectiveLeverage': value.effectiveLeverage,
  'buffer': value.buffer,
  'marginRatio': value.marginRatio,
  'currentMarginRatio': value.currentMarginRatio,
  'marketFrozen': value.marketFrozen,
  'marketContextLabel': value.marketContextLabel,
  'positionState': value.positionState?.name,
  'overallState': value.overallState?.name,
  'partial': value.partial,
  'hypothetical': value.hypothetical,
  'reasons': value.reasons.map(_reasonWire).toList(growable: false),
};

RiskStressScenario _stressFromWire(Object? value) {
  final map = _wireMap(value) ?? const <String, dynamic>{};
  return RiskStressScenario(
    label: map['label']?.toString() ?? '',
    price: _wireDouble(map['price']) ?? 0,
    percentageChange: _wireDouble(map['percentageChange']),
    tradePnl: _wireDouble(map['tradePnl']),
    equity: _wireDouble(map['equity']),
    effectiveLeverage: _wireDouble(map['effectiveLeverage']),
    buffer: _wireDouble(map['buffer']),
    marginRatio: _wireDouble(map['marginRatio']),
    currentMarginRatio: _wireDouble(map['currentMarginRatio']),
    marketFrozen: map['marketFrozen'] != false,
    marketContextLabel:
        map['marketContextLabel']?.toString() ?? 'Frozen market context',
    positionState: _wireSeverity(map['positionState']),
    overallState: _wireSeverity(map['overallState']),
    partial: map['partial'] == true,
    hypothetical: map['hypothetical'] != false,
    reasons: _reasonsFromWire(map['reasons']),
  );
}

Map<String, dynamic> _priceMapWire(RiskPriceMapLevel value) =>
    <String, dynamic>{'price': value.price, 'labels': value.labels};

RiskPriceMapLevel _priceMapFromWire(Object? value) {
  final map = _wireMap(value) ?? const <String, dynamic>{};
  return RiskPriceMapLevel(
    price: _wireDouble(map['price']) ?? 0,
    labels: map['labels'] is List
        ? List<String>.from(
            (map['labels'] as List).map((item) => item.toString()),
          )
        : const <String>[],
  );
}

RiskMetrics _metricsFromWire(Object? value) {
  final map = _wireMap(value) ?? const <String, dynamic>{};
  return RiskMetrics(
    quantity: _metricFromWire(map['quantity'], fallbackUnit: 'units'),
    markPrice: _metricFromWire(map['markPrice'], fallbackUnit: 'USDT'),
    entryPrice: _metricFromWire(map['entryPrice'], fallbackUnit: 'USDT'),
    liquidationPrice: _metricFromWire(
      map['liquidationPrice'],
      fallbackUnit: 'USDT',
    ),
    margin: _metricFromWire(map['margin'], fallbackUnit: 'USDT'),
    equity: _metricFromWire(map['equity'], fallbackUnit: 'USDT'),
    debt: _metricFromWire(map['debt'], fallbackUnit: 'USDT'),
    principalDebt: _metricFromWire(map['principalDebt'], fallbackUnit: 'USDT'),
    tradeNotional: _metricFromWire(map['tradeNotional'], fallbackUnit: 'USDT'),
    grossAssetExposure: _metricFromWire(
      map['grossAssetExposure'],
      fallbackUnit: 'USDT',
    ),
    effectiveLeverage: _metricFromWire(
      map['effectiveLeverage'],
      fallbackUnit: 'x',
    ),
    buffer: _metricFromWire(map['buffer'], fallbackUnit: 'fraction'),
    marginRatio: _metricFromWire(map['marginRatio'], fallbackUnit: 'ratio'),
    maintenanceRequirement: _metricFromWire(
      map['maintenanceRequirement'],
      fallbackUnit: 'ratio',
    ),
    tradeSensitivityPerPoint: _metricFromWire(
      map['tradeSensitivityPerPoint'],
      fallbackUnit: 'USDT',
    ),
    tradeSensitivityPerPercent: _metricFromWire(
      map['tradeSensitivityPerPercent'],
      fallbackUnit: 'USDT',
    ),
    equitySensitivityPerPoint: _metricFromWire(
      map['equitySensitivityPerPoint'],
      fallbackUnit: 'USDT',
    ),
    equitySensitivityPerPercent: _metricFromWire(
      map['equitySensitivityPerPercent'],
      fallbackUnit: 'USDT',
    ),
    distanceToEntry: _metricFromWire(
      map['distanceToEntry'],
      fallbackUnit: 'fraction',
    ),
    distanceToTrueExit: _metricFromWire(
      map['distanceToTrueExit'],
      fallbackUnit: 'fraction',
    ),
    actualInterestToday: _metricFromWire(
      map['actualInterestToday'],
      fallbackUnit: 'USDT/today',
    ),
    knownInterestToday: _metricFromWire(
      map['knownInterestToday'],
      fallbackUnit: 'USDT/today',
    ),
    trueExitPrice: _metricFromWire(map['trueExitPrice'], fallbackUnit: 'USDT'),
    projectedTrueExitPrice: _metricFromWire(
      map['projectedTrueExitPrice'],
      fallbackUnit: 'USDT',
    ),
    knownCostExitPrice: _metricFromWire(
      map['knownCostExitPrice'],
      fallbackUnit: 'USDT',
    ),
    holdingCostPerDay: _metricFromWire(
      map['holdingCostPerDay'],
      fallbackUnit: 'USDT/day',
    ),
    holdingCost7d: _metricFromWire(map['holdingCost7d'], fallbackUnit: 'USDT'),
    holdingCost30d: _metricFromWire(
      map['holdingCost30d'],
      fallbackUnit: 'USDT',
    ),
    recoveryDistance: _metricFromWire(
      map['recoveryDistance'],
      fallbackUnit: 'fraction',
    ),
    holdingBurden: _metricFromWire(
      map['holdingBurden'],
      fallbackUnit: 'fraction',
    ),
    tradePnl: _metricFromWire(map['tradePnl'], fallbackUnit: 'USDT'),
  );
}

RiskEvaluation _evaluationFromWire(Object? value) {
  final map = _wireMap(value) ?? const <String, dynamic>{};
  return RiskEvaluation(
    position: _positionFromWire(map['position']),
    metrics: _metricsFromWire(map['metrics']),
    positionAssessment: _assessmentFromWire(map['positionAssessment']),
    marketAssessment: _assessmentFromWire(map['marketAssessment']),
    recoveryAssessment: _assessmentFromWire(map['recoveryAssessment']),
    overallState: _wireSeverity(map['overallState']),
    quality: _wireQuality(map['quality']),
    reasons: _reasonsFromWire(map['reasons']),
    stressScenarios: map['stressScenarios'] is List
        ? (map['stressScenarios'] as List)
              .map(_stressFromWire)
              .toList(growable: false)
        : const <RiskStressScenario>[],
    priceMap: map['priceMap'] is List
        ? (map['priceMap'] as List)
              .map(_priceMapFromWire)
              .toList(growable: false)
        : const <RiskPriceMapLevel>[],
    evaluatedAt: _wireRequiredDate(map['evaluatedAt']),
    policyVersion: map['policyVersion']?.toString() ?? 'risk.v1',
    missingReasons: map['missingReasons'] is List
        ? List<String>.from(
            (map['missingReasons'] as List).map((item) => item.toString()),
          )
        : const <String>[],
    exchangePnlBasis: map['exchangePnlBasis']?.toString(),
  );
}

Map<String, dynamic> _marketWire(RiskMarketInput value) => <String, dynamic>{
  'state': value.state?.name,
  'complete': value.complete,
  'dailyVolatility': value.dailyVolatility,
  'reasons': value.reasons.map(_reasonWire).toList(growable: false),
  'missingReasons': value.missingReasons,
  'support': value.support,
  'resistance': value.resistance,
  'source': value.source,
  'observedAt': _wireDate(value.observedAt),
  'sourceAt': _wireDate(value.sourceAt),
  'marketContextLabel': value.marketContextLabel,
  'assetInstrument': value.assetInstrument,
  'btcInstrument': value.btcInstrument,
  'derivativesInstrument': value.derivativesInstrument,
  'volatilityLabel': value.volatilityLabel,
  'assetStructureLabel': value.assetStructureLabel,
  'btcStructureLabel': value.btcStructureLabel,
  'volumePressureLabel': value.volumePressureLabel,
  'fundingLabel': value.fundingLabel,
  'openInterestLabel': value.openInterestLabel,
  'normalizedFunding8h': value.normalizedFunding8h,
  'fundingIntervalHours': value.fundingIntervalHours,
  'openInterestChange': value.openInterestChange,
  'marketPriceChange': value.marketPriceChange,
  'fundingQuality': value.fundingQuality == null
      ? null
      : _qualityWire(value.fundingQuality!),
  'openInterestQuality': value.openInterestQuality == null
      ? null
      : _qualityWire(value.openInterestQuality!),
  'marketPoints': value.marketPoints,
  'assetPoints': value.assetPoints,
  'fundingPoints': value.fundingPoints,
  'openInterestPoints': value.openInterestPoints,
};

RiskMarketInput _marketFromWire(Object? value) {
  final map = _wireMap(value) ?? const <String, dynamic>{};
  return RiskMarketInput(
    state: _wireSeverity(map['state']),
    complete: map['complete'] == true,
    dailyVolatility: _wireDouble(map['dailyVolatility']),
    reasons: _reasonsFromWire(map['reasons']),
    missingReasons: map['missingReasons'] is List
        ? List<String>.from(
            (map['missingReasons'] as List).map((item) => item.toString()),
          )
        : const <String>[],
    support: _wireDouble(map['support']),
    resistance: _wireDouble(map['resistance']),
    source: map['source']?.toString(),
    observedAt: _wireDateValue(map['observedAt']),
    sourceAt: _wireDateValue(map['sourceAt']),
    marketContextLabel:
        map['marketContextLabel']?.toString() ?? 'OKX perpetual context',
    assetInstrument: map['assetInstrument']?.toString(),
    btcInstrument: map['btcInstrument']?.toString(),
    derivativesInstrument: map['derivativesInstrument']?.toString(),
    volatilityLabel: map['volatilityLabel']?.toString(),
    assetStructureLabel: map['assetStructureLabel']?.toString(),
    btcStructureLabel: map['btcStructureLabel']?.toString(),
    volumePressureLabel: map['volumePressureLabel']?.toString(),
    fundingLabel: map['fundingLabel']?.toString(),
    openInterestLabel: map['openInterestLabel']?.toString(),
    normalizedFunding8h: _wireDouble(map['normalizedFunding8h']),
    fundingIntervalHours: _wireDouble(map['fundingIntervalHours']),
    openInterestChange: _wireDouble(map['openInterestChange']),
    marketPriceChange: _wireDouble(map['marketPriceChange']),
    fundingQuality: map['fundingQuality'] == null
        ? null
        : _wireQuality(map['fundingQuality']),
    openInterestQuality: map['openInterestQuality'] == null
        ? null
        : _wireQuality(map['openInterestQuality']),
    marketPoints: (map['marketPoints'] as num?)?.toInt() ?? 0,
    assetPoints: (map['assetPoints'] as num?)?.toInt() ?? 0,
    fundingPoints: (map['fundingPoints'] as num?)?.toInt() ?? 0,
    openInterestPoints: (map['openInterestPoints'] as num?)?.toInt() ?? 0,
  );
}

Map<String, dynamic> _planEvaluationWire(RiskPlanEvaluation value) =>
    <String, dynamic>{
      'rules': value.rules
          .map(
            (item) => <String, dynamic>{
              'rule': item.rule.toJson(),
              'state': riskRuleStateName(item.state),
              'value': item.value,
              'referenceValue': item.referenceValue,
              'reason': item.reason,
            },
          )
          .toList(growable: false),
      'zones': value.zones
          .map(
            (item) => <String, dynamic>{
              'zone': item.zone.toJson(),
              'state': riskRuleStateName(item.state),
              'markPrice': item.markPrice,
              'reason': item.reason,
            },
          )
          .toList(growable: false),
      'evaluatedAt': _wireDate(value.evaluatedAt),
    };

RiskRuleState _ruleStateFromWire(Object? value) =>
    RiskRuleState.values.firstWhere(
      (item) => riskRuleStateName(item) == value?.toString(),
      orElse: () => RiskRuleState.unknown,
    );

RiskPlanEvaluation _planEvaluationFromWire(Object? value) {
  final map = _wireMap(value) ?? const <String, dynamic>{};
  final rules = map['rules'] is List
      ? (map['rules'] as List)
            .map((item) {
              final row = _wireMap(item) ?? const <String, dynamic>{};
              return RiskRuleEvaluation(
                rule: RiskRule.fromJson(
                  _wireMap(row['rule']) ?? const <String, dynamic>{},
                ),
                state: _ruleStateFromWire(row['state']),
                value: _wireDouble(row['value']),
                referenceValue: _wireDouble(row['referenceValue']),
                reason: row['reason']?.toString(),
              );
            })
            .toList(growable: false)
      : const <RiskRuleEvaluation>[];
  final zones = map['zones'] is List
      ? (map['zones'] as List)
            .map((item) {
              final row = _wireMap(item) ?? const <String, dynamic>{};
              return RiskZoneEvaluation(
                zone: RiskZone.fromJson(
                  _wireMap(row['zone']) ?? const <String, dynamic>{},
                ),
                state: _ruleStateFromWire(row['state']),
                markPrice: _wireDouble(row['markPrice']),
                reason: row['reason']?.toString(),
              );
            })
            .toList(growable: false)
      : const <RiskZoneEvaluation>[];
  return RiskPlanEvaluation(
    rules: rules,
    zones: zones,
    evaluatedAt: _wireDateValue(map['evaluatedAt']),
  );
}

Map<String, dynamic> _trendWire(RiskTrendResult value) => <String, dynamic>{
  'label': value.label.name,
  'baseline': value.baseline?.toJson(),
  'current': value.current?.toJson(),
  'bufferDeltaPoints': value.bufferDeltaPoints,
  'leverageDelta': value.leverageDelta,
  'reason': value.reason,
};

RiskTrendResult _trendFromWire(Object? value) {
  final map = _wireMap(value) ?? const <String, dynamic>{};
  return RiskTrendResult(
    label: RiskTrendLabel.values.firstWhere(
      (item) => item.name == map['label']?.toString(),
      orElse: () => RiskTrendLabel.unavailable,
    ),
    baseline: map['baseline'] == null
        ? null
        : RiskHistorySample.fromJson(_wireMap(map['baseline'])!),
    current: map['current'] == null
        ? null
        : RiskHistorySample.fromJson(_wireMap(map['current'])!),
    bufferDeltaPoints: _wireDouble(map['bufferDeltaPoints']),
    leverageDelta: _wireDouble(map['leverageDelta']),
    reason: map['reason']?.toString(),
  );
}

Map<String, dynamic> _velocityWire(RiskVelocityResult value) =>
    <String, dynamic>{
      'label': value.label.name,
      'baseline': value.baseline?.toJson(),
      'current': value.current?.toJson(),
      'pointsPerHour': value.pointsPerHour,
      'elapsedHours': value.elapsedHours,
      'reason': value.reason,
    };

RiskVelocityResult _velocityFromWire(Object? value) {
  final map = _wireMap(value) ?? const <String, dynamic>{};
  return RiskVelocityResult(
    label: RiskTrendLabel.values.firstWhere(
      (item) => item.name == map['label']?.toString(),
      orElse: () => RiskTrendLabel.unavailable,
    ),
    baseline: map['baseline'] == null
        ? null
        : RiskHistorySample.fromJson(_wireMap(map['baseline'])!),
    current: map['current'] == null
        ? null
        : RiskHistorySample.fromJson(_wireMap(map['current'])!),
    pointsPerHour: _wireDouble(map['pointsPerHour']),
    elapsedHours: _wireDouble(map['elapsedHours']),
    reason: map['reason']?.toString(),
  );
}

Map<String, dynamic> _comparisonWire(RiskSessionComparison value) =>
    <String, dynamic>{
      'baseline': value.baseline.toJson(),
      'current': value.current.toJson(),
      'bufferDeltaPoints': value.bufferDeltaPoints,
      'leverageDelta': value.leverageDelta,
      'debtDelta': value.debtDelta,
      'trueExitChanged': value.trueExitChanged,
      'structureChanged': value.structureChanged,
      'fundingChanged': value.fundingChanged,
      'openInterestChanged': value.openInterestChanged,
      'overallChanged': value.overallChanged,
      'positionChanged': value.positionChanged,
    };

RiskSessionComparison _comparisonFromWire(Object? value) {
  final map = _wireMap(value) ?? const <String, dynamic>{};
  return RiskSessionComparison(
    baseline: RiskHistorySample.fromJson(_wireMap(map['baseline'])!),
    current: RiskHistorySample.fromJson(_wireMap(map['current'])!),
    bufferDeltaPoints: _wireDouble(map['bufferDeltaPoints']),
    leverageDelta: _wireDouble(map['leverageDelta']),
    debtDelta: _wireDouble(map['debtDelta']),
    trueExitChanged: map['trueExitChanged'] == true,
    structureChanged: map['structureChanged'] == true,
    fundingChanged: map['fundingChanged'] == true,
    openInterestChanged: map['openInterestChanged'] == true,
    overallChanged: map['overallChanged'] == true,
    positionChanged: map['positionChanged'] == true,
  );
}

Map<String, dynamic> _positionMonitorWire(
  RiskPositionMonitorViewState value,
) => <String, dynamic>{
  'positionId': value.positionId,
  'episodeKey': value.episodeKey,
  'positionSide': value.positionSide,
  'direction': value.direction,
  'position': value.position == null ? null : _positionWire(value.position!),
  'evaluation': value.evaluation == null
      ? null
      : _evaluationWire(value.evaluation!),
  'planEvaluation': value.planEvaluation == null
      ? null
      : _planEvaluationWire(value.planEvaluation!),
  'plan': value.plan?.toJson(),
  'settings': value.settings?.toJson(),
  'market': value.market == null ? null : _marketWire(value.market!),
  'samples': value.samples
      .map((sample) => sample.toJson())
      .toList(growable: false),
  'summaries': value.summaries
      .map((summary) => summary.toJson())
      .toList(growable: false),
  'previousCheck': value.previousCheck == null
      ? null
      : _comparisonWire(value.previousCheck!),
  'trend': value.trend == null ? null : _trendWire(value.trend!),
  'velocity': value.velocity == null ? null : _velocityWire(value.velocity!),
  'events': value.events.map((event) => event.toJson()).toList(growable: false),
  'eventIds': value.events.map((event) => event.id).toList(growable: false),
  'quality': _qualityWire(value.quality),
  'unsaved': value.unsaved,
  'lastError': value.lastError,
  'freshnessAt': _wireDate(value.freshnessAt),
};

RiskPositionMonitorViewState _positionMonitorFromWire(Object? value) {
  final map = _wireMap(value) ?? const <String, dynamic>{};
  final position = map['position'] == null
      ? null
      : _positionFromWire(map['position']);
  final rawEvents = map['events'];
  final events = <RiskEvent>[];
  if (rawEvents is List) {
    for (final item in rawEvents) {
      final event = _wireMap(item);
      if (event == null) continue;
      try {
        events.add(RiskEvent.fromJson(event));
      } catch (_) {
        // Keep decoding the remaining aggregate entries. Event ids below
        // preserve dedupe identity without transporting private details.
      }
    }
  }
  final knownIds = events.map((event) => event.id).toSet();
  final eventIds = map['eventIds'];
  if (eventIds is List) {
    for (final rawId in eventIds) {
      final id = rawId.toString();
      if (!knownIds.add(id)) continue;
      events.add(
        RiskEvent(
          id: id,
          episodeKey:
              map['episodeKey']?.toString() ?? position?.episodeKey ?? '',
          kind: RiskEventKind.stateChange,
          message: 'Risk update',
          createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          observedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        ),
      );
    }
  }
  List<RiskHistorySample> samples() {
    final raw = map['samples'];
    if (raw is! List) return const <RiskHistorySample>[];
    return raw
        .whereType<Map>()
        .map(
          (item) => RiskHistorySample.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
  }

  List<RiskDailySummary> summaries() {
    final raw = map['summaries'];
    if (raw is! List) return const <RiskDailySummary>[];
    return raw
        .whereType<Map>()
        .map(
          (item) => RiskDailySummary.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
  }

  return RiskPositionMonitorViewState(
    positionId: map['positionId']?.toString() ?? position?.positionId,
    episodeKey: map['episodeKey']?.toString() ?? position?.episodeKey ?? '',
    positionSide:
        map['positionSide']?.toString() ??
        map['direction']?.toString() ??
        position?.positionSide ??
        'long',
    position: position,
    evaluation: map['evaluation'] == null
        ? null
        : _evaluationFromWire(map['evaluation']),
    planEvaluation: map['planEvaluation'] == null
        ? null
        : _planEvaluationFromWire(map['planEvaluation']),
    plan: map['plan'] == null
        ? null
        : RiskPlan.fromJson(_wireMap(map['plan'])!),
    settings: map['settings'] == null
        ? null
        : RiskSettings.fromJson(_wireMap(map['settings'])!),
    market: map['market'] == null ? null : _marketFromWire(map['market']),
    samples: samples(),
    summaries: summaries(),
    previousCheck: map['previousCheck'] == null
        ? null
        : _comparisonFromWire(map['previousCheck']),
    trend: map['trend'] == null ? null : _trendFromWire(map['trend']),
    velocity: map['velocity'] == null
        ? null
        : _velocityFromWire(map['velocity']),
    events: events,
    quality: _wireQuality(map['quality']),
    unsaved: map['unsaved'] == true,
    lastError: map['lastError']?.toString(),
    freshnessAt: _wireDateValue(map['freshnessAt']),
  );
}

RiskMonitorRequestStatus _requestStatusFromWire(Object? value) {
  final text = value?.toString();
  return RiskMonitorRequestStatus.values.firstWhere(
    (item) => item.name == text,
    orElse: () => RiskMonitorRequestStatus.unavailable,
  );
}

Map<String, dynamic> _stateWire(
  RiskMonitorViewState value,
) => <String, dynamic>{
  'protocol': RiskMonitorWire.state,
  'isRunning': value.isRunning,
  'backgroundAvailable': value.backgroundAvailable,
  'ownerLabel': value.ownerLabel,
  'accountHash': value.accountHash,
  'episodeKey': value.episodeKey,
  'evaluation': value.evaluation == null
      ? null
      : _evaluationWire(value.evaluation!),
  'planEvaluation': value.planEvaluation == null
      ? null
      : _planEvaluationWire(value.planEvaluation!),
  'plan': value.plan?.toJson(),
  'settings': value.settings?.toJson(),
  'market': value.market == null ? null : _marketWire(value.market!),
  'samples': value.samples
      ?.map((sample) => sample.toJson())
      .toList(growable: false),
  'summaries': value.summaries
      ?.map((summary) => summary.toJson())
      .toList(growable: false),
  'previousCheck': value.previousCheck == null
      ? null
      : _comparisonWire(value.previousCheck!),
  'trend': value.trend == null ? null : _trendWire(value.trend!),
  'velocity': value.velocity == null ? null : _velocityWire(value.velocity!),
  'events': value.events.map((event) => event.toJson()).toList(growable: false),
  'eventIds': value.events.map((event) => event.id).toList(growable: false),
  'quality': _qualityWire(value.quality),
  'unsaved': value.unsaved,
  'lastError': value.lastError,
  'notificationCapability': value.notificationCapability.name,
  'positions': value.positions
      .map(_positionMonitorWire)
      .toList(growable: false),
  'requestStatus': value.requestStatus.name,
  'retryAt': _wireDate(value.retryAt),
  'requestEndpointClass': value.requestEndpointClass,
};

RiskMonitorViewState _stateFromWire(Map<String, dynamic> value) {
  final rawEvents = value['events'];
  final events = <RiskEvent>[];
  if (rawEvents is List) {
    for (final item in rawEvents) {
      final map = _wireMap(item);
      if (map == null) continue;
      try {
        events.add(RiskEvent.fromJson(map));
      } catch (_) {
        // Older peers may include only event ids; the fallback below retains
        // the dedupe identity without inventing private event details.
      }
    }
  }
  final eventIds = value['eventIds'];
  final knownIds = events.map((event) => event.id).toSet();
  if (eventIds is List) {
    for (final rawId in eventIds) {
      final id = rawId.toString();
      if (!knownIds.add(id)) continue;
      events.add(
        RiskEvent(
          id: id,
          episodeKey: value['episodeKey']?.toString() ?? '',
          kind: RiskEventKind.stateChange,
          message: 'Risk update',
          createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          observedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        ),
      );
    }
  }
  final capability = RiskNotificationCapabilityStatus.values.firstWhere(
    (item) => item.name == value['notificationCapability']?.toString(),
    orElse: () => RiskNotificationCapabilityStatus.unavailable,
  );
  List<RiskHistorySample>? samples;
  if (value['samples'] is List) {
    samples = (value['samples'] as List)
        .map((item) => RiskHistorySample.fromJson(_wireMap(item)!))
        .toList(growable: false);
  }
  List<RiskDailySummary>? summaries;
  if (value['summaries'] is List) {
    summaries = (value['summaries'] as List)
        .map((item) => RiskDailySummary.fromJson(_wireMap(item)!))
        .toList(growable: false);
  }
  var positions = <RiskPositionMonitorViewState>[];
  final rawPositions = value['positions'];
  if (rawPositions is List) {
    positions = rawPositions
        .map(_positionMonitorFromWire)
        .toList(growable: false);
  }
  // Older service peers only know the singular projection. Preserve that
  // state as a one-entry aggregate until both sides have upgraded.
  if (positions.isEmpty && value['episodeKey']?.toString().isNotEmpty == true) {
    positions = <RiskPositionMonitorViewState>[
      RiskPositionMonitorViewState(
        positionId: (value['evaluation'] is Map)
            ? _positionFromWire(
                _wireMap(value['evaluation'])?['position'],
              ).positionId
            : null,
        episodeKey: value['episodeKey']?.toString() ?? '',
        positionSide: (value['evaluation'] is Map)
            ? _positionFromWire(
                _wireMap(value['evaluation'])?['position'],
              ).positionSide
            : 'long',
        evaluation: value['evaluation'] == null
            ? null
            : _evaluationFromWire(value['evaluation']),
        planEvaluation: value['planEvaluation'] == null
            ? null
            : _planEvaluationFromWire(value['planEvaluation']),
        plan: value['plan'] == null
            ? null
            : RiskPlan.fromJson(_wireMap(value['plan'])!),
        settings: value['settings'] == null
            ? null
            : RiskSettings.fromJson(_wireMap(value['settings'])!),
        market: value['market'] == null
            ? null
            : _marketFromWire(value['market']),
        samples: samples ?? const <RiskHistorySample>[],
        summaries: summaries ?? const <RiskDailySummary>[],
        previousCheck: value['previousCheck'] == null
            ? null
            : _comparisonFromWire(value['previousCheck']),
        trend: value['trend'] == null ? null : _trendFromWire(value['trend']),
        velocity: value['velocity'] == null
            ? null
            : _velocityFromWire(value['velocity']),
        events: events,
        quality: _wireQuality(value['quality']),
        unsaved: value['unsaved'] == true,
        lastError: value['lastError']?.toString(),
      ),
    ];
  }
  return RiskMonitorViewState(
    isRunning: value['isRunning'] == true,
    backgroundAvailable: value['backgroundAvailable'] == true,
    ownerLabel: value['ownerLabel']?.toString() ?? 'android-service',
    accountHash: value['accountHash']?.toString(),
    episodeKey: value['episodeKey']?.toString(),
    evaluation: value['evaluation'] == null
        ? null
        : _evaluationFromWire(value['evaluation']),
    planEvaluation: value['planEvaluation'] == null
        ? null
        : _planEvaluationFromWire(value['planEvaluation']),
    plan: value['plan'] == null
        ? null
        : RiskPlan.fromJson(_wireMap(value['plan'])!),
    settings: value['settings'] == null
        ? null
        : RiskSettings.fromJson(_wireMap(value['settings'])!),
    market: value['market'] == null ? null : _marketFromWire(value['market']),
    samples: samples,
    summaries: summaries,
    previousCheck: value['previousCheck'] == null
        ? null
        : _comparisonFromWire(value['previousCheck']),
    trend: value['trend'] == null ? null : _trendFromWire(value['trend']),
    velocity: value['velocity'] == null
        ? null
        : _velocityFromWire(value['velocity']),
    events: events,
    quality: _wireQuality(value['quality']),
    unsaved: value['unsaved'] == true,
    lastError: value['lastError']?.toString(),
    notificationCapability: capability,
    positions: positions,
    requestStatus: _requestStatusFromWire(value['requestStatus']),
    retryAt: _wireDateValue(value['retryAt']),
    requestEndpointClass: value['requestEndpointClass']?.toString(),
  );
}

class RiskMonitorCommandResult {
  const RiskMonitorCommandResult({
    required this.commandId,
    required this.status,
    required this.state,
    this.message,
    this.replayed = false,
  });

  final String commandId;
  final RiskMonitorCommandStatus status;
  final RiskMonitorViewState state;
  final String? message;
  final bool replayed;

  bool get accepted => status == RiskMonitorCommandStatus.accepted;
  bool get duplicate => replayed;

  Map<String, dynamic> toWire() => <String, dynamic>{
    'commandId': commandId,
    'status': status.name,
    'message': message,
    'replayed': replayed,
    'state': RiskMonitorWire.encodeState(state),
  };
}

/// JSON-compatible command/state/ack protocol used by the Android service.
/// The protocol deliberately transports only typed state metadata; account
/// payloads, credentials and risk values never cross the platform channel.
abstract final class RiskMonitorWire {
  static const String handshake = 'risk.monitor.handshake.v1';
  static const String handshakeRequest = 'risk.monitor.handshake.request.v1';
  static const String heartbeat = 'risk.monitor.heartbeat.v1';
  static const String command = 'risk.monitor.command.v1';
  static const String acknowledgement = 'risk.monitor.ack.v1';
  static const String state = 'risk.monitor.state.v1';

  static Map<String, dynamic> encodeCommand(RiskMonitorCommand value) =>
      <String, dynamic>{'protocol': command, 'command': value.toWire()};

  static RiskMonitorCommand decodeCommand(Map<String, dynamic> value) {
    _requireProtocol(value, command);
    final payload = value['command'];
    if (payload is! Map) {
      throw const FormatException('Risk command payload is missing');
    }
    return RiskMonitorCommand.fromWire(Map<String, dynamic>.from(payload));
  }

  static Map<String, dynamic> encodeAck(RiskMonitorCommandResult value) =>
      <String, dynamic>{'protocol': acknowledgement, 'ack': value.toWire()};

  static RiskMonitorCommandResult decodeAck(Map<String, dynamic> value) {
    _requireProtocol(value, acknowledgement);
    final payload = value['ack'];
    if (payload is! Map) {
      throw const FormatException('Risk acknowledgement payload is missing');
    }
    final ack = Map<String, dynamic>.from(payload);
    final commandId = ack['commandId']?.toString().trim() ?? '';
    if (commandId.isEmpty) {
      throw const FormatException('Risk acknowledgement command id is missing');
    }
    final statusText = ack['status']?.toString();
    final status = RiskMonitorCommandStatus.values.firstWhere(
      (item) => item.name == statusText,
      orElse: () => throw const FormatException('Unknown risk ack status'),
    );
    final state = ack['state'];
    return RiskMonitorCommandResult(
      commandId: commandId,
      status: status,
      state: state is Map
          ? decodeState(Map<String, dynamic>.from(state))
          : RiskMonitorViewState(),
      message: ack['message']?.toString(),
      replayed: ack['replayed'] == true,
    );
  }

  static Map<String, dynamic> encodeState(RiskMonitorViewState value) =>
      _stateWire(value);

  static RiskMonitorViewState decodeState(Map<String, dynamic> value) {
    _requireProtocol(value, state);
    return _stateFromWire(value);
  }

  static void _requireProtocol(Map<String, dynamic> value, String expected) {
    final actual = value['protocol'];
    if (actual != null && actual.toString() != expected) {
      throw FormatException('Unexpected risk protocol: ${actual.toString()}');
    }
  }
}

/// Protocol implemented by the foreground owner and by the later Android
/// service owner. It carries only typed commands/state and has no platform API.
abstract class RiskMonitorOwner {
  Stream<RiskMonitorViewState> get states;
  RiskMonitorViewState get currentState;

  Future<RiskMonitorCommandResult> dispatch(RiskMonitorCommand command);
}

abstract interface class RiskMonitorDisposable {
  Future<void> dispose();
}

/// The service controller uses this narrow seam to fence a credential
/// mutation before an earlier queued command can finish. The follow-up
/// dispatch still owns the restart and acknowledgement.
abstract interface class RiskMonitorCredentialInvalidator {
  void fenceCredentialsForCommand(String commandId, {String? reason});
}

class RiskMonitorBridge {
  const RiskMonitorBridge(this.owner);

  final RiskMonitorOwner owner;

  Stream<RiskMonitorViewState> get states => owner.states;
  RiskMonitorViewState get currentState => owner.currentState;

  Future<RiskMonitorCommandResult> send(RiskMonitorCommand command) =>
      owner.dispatch(command);

  Future<RiskMonitorCommandResult> start({
    required String commandId,
    String? accountHash,
    String? episodeKey,
  }) => send(
    RiskMonitorCommand.start(
      id: commandId,
      accountHash: accountHash,
      episodeKey: episodeKey,
    ),
  );

  Future<RiskMonitorCommandResult> stop({required String commandId}) =>
      send(RiskMonitorCommand.stop(id: commandId));
}

/// In-memory owner used by P04 and unit tests. Command ids are idempotent:
/// duplicates return the original result and never repeat a mutation.
class InMemoryRiskMonitorOwner implements RiskMonitorOwner {
  InMemoryRiskMonitorOwner({RiskMonitorViewState? initial})
    : _state = initial ?? RiskMonitorViewState(),
      _plan = initial?.plan,
      _settings = initial?.settings,
      _states = StreamController<RiskMonitorViewState>.broadcast();

  RiskMonitorViewState _state;
  final StreamController<RiskMonitorViewState> _states;
  final Map<String, RiskMonitorCommandResult> _results =
      <String, RiskMonitorCommandResult>{};
  RiskPlan? _plan;
  RiskSettings? _settings;

  @override
  Stream<RiskMonitorViewState> get states => _states.stream;

  @override
  RiskMonitorViewState get currentState => _state;

  RiskPlan? get plan => _plan;
  RiskSettings? get settings => _settings;

  @override
  Future<RiskMonitorCommandResult> dispatch(RiskMonitorCommand command) async {
    final id = command.id.trim();
    if (id.isEmpty) {
      return RiskMonitorCommandResult(
        commandId: command.id,
        status: RiskMonitorCommandStatus.rejected,
        state: _state,
        message: 'Command id is required',
      );
    }
    final existing = _results[id];
    if (existing != null) {
      return RiskMonitorCommandResult(
        commandId: existing.commandId,
        status: existing.status,
        state: existing.state,
        message: existing.message,
        replayed: true,
      );
    }
    late RiskMonitorCommandResult result;
    switch (command.type) {
      case RiskMonitorCommandType.start:
        final accountChanged =
            command.accountHash != null &&
            command.accountHash != _state.accountHash;
        final episodeChanged =
            command.episodeKey != null &&
            command.episodeKey != _state.episodeKey;
        if (accountChanged || episodeChanged) {
          _plan = null;
          if (accountChanged) _settings = null;
        }
        _state = _state.copyWith(
          isRunning: true,
          accountHash: command.accountHash,
          episodeKey: command.episodeKey,
          clearError: true,
          clearEvaluation: accountChanged || episodeChanged,
          clearPlanEvaluation: accountChanged || episodeChanged,
          clearPlan: accountChanged || episodeChanged,
          clearSettings: accountChanged,
          clearMarket: accountChanged || episodeChanged,
          clearSamples: accountChanged || episodeChanged,
          clearSummaries: accountChanged || episodeChanged,
          clearPreviousCheck: accountChanged || episodeChanged,
          clearTrend: accountChanged || episodeChanged,
          clearVelocity: accountChanged || episodeChanged,
          events: accountChanged || episodeChanged
              ? const <RiskEvent>[]
              : _state.events,
        );
        result = _accept(command, message: 'Monitor started');
      case RiskMonitorCommandType.stop:
        _state = _state.copyWith(isRunning: false);
        result = _accept(command, message: 'Monitor stopped');
      case RiskMonitorCommandType.refresh:
        if (!_state.isRunning) {
          result = _reject(command, 'Monitor is not running');
        } else {
          result = _accept(command, message: 'Refresh requested');
        }
      case RiskMonitorCommandType.reconnect:
        result = _accept(command, message: 'Reconnect acknowledged');
      case RiskMonitorCommandType.updatePlan:
        final plan = command.plan;
        if (plan == null ||
            !plan.isValid ||
            (_state.episodeKey != null &&
                plan.episodeKey != _state.episodeKey)) {
          result = _reject(command, 'Plan validation failed');
        } else {
          _plan = plan;
          _state = _state.copyWith(plan: plan);
          result = _accept(command, message: 'Plan updated');
        }
      case RiskMonitorCommandType.updateSettings:
        final settings = command.settings;
        if (settings == null || !settings.isValid) {
          result = _reject(command, 'Settings validation failed');
        } else {
          _settings = settings;
          _state = _state.copyWith(settings: settings);
          result = _accept(command, message: 'Settings updated');
        }
      case RiskMonitorCommandType.clearHistory:
        _state = _state.copyWith(
          events: const <RiskEvent>[],
          clearSamples: true,
          clearSummaries: true,
          clearPreviousCheck: true,
          clearTrend: true,
          clearVelocity: true,
        );
        result = _accept(command, message: 'History clear requested');
      case RiskMonitorCommandType.invalidateCredentials:
        _state = RiskMonitorViewState(
          ownerLabel: _state.ownerLabel,
          backgroundAvailable: _state.backgroundAvailable,
          quality: const RiskQuality.unavailable(
            reason: 'Credentials changed; monitoring is restarting',
          ),
        );
        _plan = null;
        _settings = null;
        result = _accept(command, message: 'Credentials invalidated');
      case RiskMonitorCommandType.uiDeparture:
        result = _accept(command, message: 'UI departure recorded');
      case RiskMonitorCommandType.uiResume:
        result = _accept(command, message: 'UI resume acknowledged');
    }
    _results[id] = result;
    return result;
  }

  /// Publish a state already produced by the pure owner pipeline. This is a
  /// test/P04 seam and does not persist or deliver anything.
  void publish(RiskMonitorViewState state) {
    _state = state;
    _plan = state.plan;
    _settings = state.settings;
    if (!_states.isClosed) _states.add(state);
  }

  Future<void> dispose() => _states.close();

  RiskMonitorCommandResult _accept(
    RiskMonitorCommand command, {
    String? message,
  }) {
    final result = RiskMonitorCommandResult(
      commandId: command.id,
      status: RiskMonitorCommandStatus.accepted,
      state: _state,
      message: message,
    );
    if (!_states.isClosed) _states.add(_state);
    return result;
  }

  RiskMonitorCommandResult _reject(
    RiskMonitorCommand command,
    String message,
  ) => RiskMonitorCommandResult(
    commandId: command.id,
    status: RiskMonitorCommandStatus.rejected,
    state: _state,
    message: message,
  );
}
