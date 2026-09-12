import 'dart:async';

import '../domain/risk/action_plan.dart';
import '../domain/risk/risk_events.dart';
import '../domain/risk/risk_history.dart';
import '../domain/risk/risk_models.dart';

enum RiskMonitorCommandType {
  start,
  stop,
  refresh,
  reconnect,
  updatePlan,
  updateSettings,
  clearHistory,
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
  });

  final String id;
  final RiskMonitorCommandType type;
  final DateTime issuedAt;
  final String? accountHash;
  final String? episodeKey;
  final RiskPlan? plan;
  final RiskSettings? settings;

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
    DateTime? issuedAt,
  }) => RiskMonitorCommand(
    id: id,
    type: RiskMonitorCommandType.updatePlan,
    issuedAt: (issuedAt ?? DateTime.now().toUtc()).toUtc(),
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
    DateTime? issuedAt,
  }) => RiskMonitorCommand(
    id: id,
    type: RiskMonitorCommandType.clearHistory,
    issuedAt: (issuedAt ?? DateTime.now().toUtc()).toUtc(),
  );
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
  }) : plan = _freezePlan(plan),
       settings = _freezeSettings(settings),
       market = _freezeMarket(market),
       samples = samples == null
           ? null
           : List<RiskHistorySample>.unmodifiable(samples),
       summaries = summaries == null
           ? null
           : List<RiskDailySummary>.unmodifiable(summaries),
       events = List<RiskEvent>.unmodifiable(events);

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
}

/// Protocol implemented by the foreground owner and by the later Android
/// service owner. It carries only typed commands/state and has no platform API.
abstract class RiskMonitorOwner {
  Stream<RiskMonitorViewState> get states;
  RiskMonitorViewState get currentState;

  Future<RiskMonitorCommandResult> dispatch(RiskMonitorCommand command);
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
