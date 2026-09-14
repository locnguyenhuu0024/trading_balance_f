import 'dart:async';

import '../../../core/timezone/app_time_zone.dart';
import '../data/risk/risk_local_store.dart';
import '../data/risk/risk_market_repository.dart';
import '../data/risk/risk_repository.dart';
import '../domain/risk/action_plan.dart';
import '../domain/risk/market_risk_engine.dart';
import '../domain/risk/risk_engine.dart';
import '../domain/risk/risk_events.dart';
import '../domain/risk/risk_history.dart';
import '../domain/risk/risk_models.dart';
import 'risk_monitor_bridge.dart';
import 'risk_notification_sink.dart';

typedef RiskMonitorClock = DateTime Function();

/// The monitor deliberately talks to small source interfaces. Production
/// wiring uses the existing authenticated/public repositories while tests use
/// synthetic sources with no platform channels or credentials.
abstract class RiskMonitorDataSource {
  Future<RiskPositionSelection> loadPosition({
    String? selectedPositionId,
    String? selectedEpisodeKey,
  });

  Future<MarketRiskSnapshot> loadMarket({
    required RiskPosition position,
    DateTime? now,
  });
}

/// Optional aggregate source introduced by T24. Production sources use this
/// seam so one capture discovers the account position set once and receives
/// T24's paced, resumable enrichment for every eligible position. Legacy/test
/// sources may continue implementing [RiskMonitorDataSource] and are treated
/// as a one-position compatibility source.
abstract interface class RiskMonitorBatchDataSource {
  Future<RiskPositionBatch> loadPositionsBatch({int ledgerPageBudget = 2});
}

/// Optional repository seam used to keep one-minute market context fetches
/// separate from the five-minute candle refresh. Legacy/test sources can keep
/// implementing [RiskMonitorDataSource.loadMarket] and receive the old single
/// snapshot request.
abstract interface class RiskMonitorMarketCadenceSource {
  Future<MarketRiskSnapshot> loadMarketCadence({
    required RiskPosition position,
    required DateTime now,
    required bool includeCandles,
  });
}

abstract interface class RiskMonitorCacheInvalidator {
  void clearCaches();
}

/// Optional typed failure metadata exposed by repository-backed sources. The
/// position-selection domain result stays stable while the monitor can still
/// distinguish credential failures and server retry hints.
abstract interface class RiskMonitorSelectionFailureMetadata {
  RiskRepositorySelectionFailure? get lastSelectionFailure;
}

class RepositoryRiskMonitorDataSource
    implements
        RiskMonitorDataSource,
        RiskMonitorBatchDataSource,
        RiskMonitorCacheInvalidator,
        RiskMonitorSelectionFailureMetadata,
        RiskMonitorMarketCadenceSource {
  const RepositoryRiskMonitorDataSource({
    required this.repository,
    required this.marketRepository,
  });

  final RiskRepository repository;
  final RiskMarketRepository marketRepository;

  @override
  RiskRepositorySelectionFailure? get lastSelectionFailure =>
      repository.lastSelectionFailure;

  @override
  Future<RiskPositionSelection> loadPosition({
    String? selectedPositionId,
    String? selectedEpisodeKey,
  }) => repository.loadPosition(
    selectedPositionId: selectedPositionId,
    selectedEpisodeKey: selectedEpisodeKey,
  );

  @override
  Future<RiskPositionBatch> loadPositionsBatch({int ledgerPageBudget = 2}) =>
      repository.loadPositionsBatch(ledgerPageBudget: ledgerPageBudget);

  @override
  Future<MarketRiskSnapshot> loadMarket({
    required RiskPosition position,
    DateTime? now,
  }) {
    final asset = position.baseCurrency;
    if (asset == null || asset.trim().isEmpty) {
      throw const RiskMonitorSourceException('Position asset is unavailable');
    }
    return marketRepository.load(asset: asset, now: now);
  }

  @override
  Future<MarketRiskSnapshot> loadMarketCadence({
    required RiskPosition position,
    required DateTime now,
    required bool includeCandles,
  }) async {
    if (includeCandles) {
      return loadMarket(position: position, now: now);
    }
    final asset = position.baseCurrency;
    if (asset == null || asset.trim().isEmpty) {
      throw const RiskMonitorSourceException('Position asset is unavailable');
    }
    final normalizedAsset = asset.trim().toUpperCase();
    final derivative = '$normalizedAsset-USDT-SWAP';
    final funding = await marketRepository.getFundingResult(instId: derivative);
    final openInterest = await marketRepository.getOpenInterestResult(
      instId: derivative,
    );
    MarketCandleSeries unavailable(String instrument, String interval) =>
        MarketCandleSeries.unavailable(
          instrument: instrument,
          interval: interval,
          endpoint: RiskMarketRepository.candlesEndpoint,
          reason: 'Candle refresh is on the five-minute cadence',
          observedAt: now,
        );
    final assetInstrument = '$normalizedAsset-USDT';
    const btcInstrument = 'BTC-USDT';
    return MarketRiskSnapshot(
      asset: normalizedAsset,
      assetOneHour: unavailable(assetInstrument, '1H'),
      assetFourHour: unavailable(assetInstrument, '4H'),
      btcOneHour: unavailable(btcInstrument, '1H'),
      btcFourHour: unavailable(btcInstrument, '4H'),
      funding: funding.value,
      openInterest: openInterest.value ?? const <MarketOpenInterestSample>[],
      fundingQuality: funding.quality,
      openInterestQuality: openInterest.quality,
      observedAt: now,
    );
  }

  @override
  void clearCaches() => repository.clearCaches();
}

class RiskMonitorSourceException implements Exception {
  const RiskMonitorSourceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _CredentialFence {
  const _CredentialFence({
    required this.wasRunning,
    required this.accountHash,
    required this.episodeKey,
  });

  final bool wasRunning;
  final String? accountHash;
  final String? episodeKey;
}

/// Mutable working state for one position episode. The owning [RiskMonitor]
/// keeps exactly one map/timer/serialized queue; this context only partitions
/// lifecycle and durable state so one episode can never overwrite another.
class _RiskEpisodeMonitorContext {
  _RiskEpisodeMonitorContext({
    required this.accountHash,
    required this.episodeKey,
    required this.position,
  });

  final String accountHash;
  final String episodeKey;
  RiskPosition position;

  RiskEpisodeRecord? record;
  RiskEpisodeRecord? pendingRecord;
  RiskPlan? plan;
  RiskMarketInput? market;
  DateTime? marketFetchedAt;
  MarketRiskSnapshot? marketSnapshot;
  DateTime? candleSnapshotFetchedAt;
  DateTime? lastOiPersistAt;
  DateTime? lastHistoryPersistAt;
  List<RiskHistorySample> persistedSamples = const <RiskHistorySample>[];
  RiskHistorySample? latestAcceptedSample;
  RiskPlanEvaluation? previousPlanEvaluation;
  List<MarketOpenInterestSample> pendingOpenInterest =
      const <MarketOpenInterestSample>[];
  RiskCheckSession? session;
  DateTime? uiDepartureAt;
  RiskHistorySample? uiDepartureBaseline;
  RiskEvaluation? evaluation;
  RiskPlanEvaluation? planEvaluation;
  List<RiskHistorySample> visibleSamples = const <RiskHistorySample>[];
  List<RiskDailySummary> visibleSummaries = const <RiskDailySummary>[];
  List<RiskEvent> visibleEvents = const <RiskEvent>[];
  RiskSessionComparison? previousCheck;
  RiskTrendResult? trend;
  RiskVelocityResult? velocity;
  RiskQuality quality = const RiskQuality.unavailable(
    reason: 'Position has not observed a snapshot',
  );
  bool unsaved = false;
  String? lastError;
  final Set<String> deliveredEventIds = <String>{};

  RiskPositionMonitorViewState toViewState(RiskSettings settings) {
    return RiskPositionMonitorViewState(
      positionId: position.positionId,
      episodeKey: episodeKey,
      positionSide: position.positionSide,
      position: position,
      evaluation: evaluation,
      planEvaluation: planEvaluation,
      plan: plan,
      settings: settings,
      market: market,
      samples: visibleSamples,
      summaries: visibleSummaries,
      previousCheck: previousCheck,
      trend: trend,
      velocity: velocity,
      events: visibleEvents,
      quality: quality,
      unsaved: unsaved,
      lastError: lastError,
      freshnessAt: position.observedAt ?? quality.observedAt,
    );
  }
}

/// Persistence boundary. [RiskLocalStorePersistence] is the production
/// adapter; tests can provide a fake that records call order and failures.
abstract class RiskMonitorPersistence {
  Future<RiskStoreResult<RiskSettings>> loadSettings(String accountHash);

  Future<RiskStoreResult<RiskEpisodeRecord>> loadEpisode({
    required String accountHash,
    required String episodeKey,
  });

  Future<RiskStoreResult<RiskSettings>> saveSettings({
    required String accountHash,
    required RiskSettings settings,
  });

  Future<RiskStoreResult<RiskEpisodeRecord>> saveEpisode({
    required String accountHash,
    required RiskEpisodeRecord record,
  });

  Future<RiskStoreResult<RiskEpisodeRecord>> clearEpisodeHistory({
    required String accountHash,
    required String episodeKey,
  });
}

typedef RiskMonitorStorage = RiskMonitorPersistence;

class RiskLocalStorePersistence implements RiskMonitorPersistence {
  const RiskLocalStorePersistence(this.store);

  final RiskLocalStore store;

  @override
  Future<RiskStoreResult<RiskSettings>> loadSettings(String accountHash) =>
      store.loadSettings(accountHash);

  @override
  Future<RiskStoreResult<RiskEpisodeRecord>> loadEpisode({
    required String accountHash,
    required String episodeKey,
  }) => store.loadEpisode(accountHash: accountHash, episodeKey: episodeKey);

  @override
  Future<RiskStoreResult<RiskSettings>> saveSettings({
    required String accountHash,
    required RiskSettings settings,
  }) => store.saveSettings(accountHash: accountHash, settings: settings);

  @override
  Future<RiskStoreResult<RiskEpisodeRecord>> saveEpisode({
    required String accountHash,
    required RiskEpisodeRecord record,
  }) => store.saveEpisode(accountHash: accountHash, record: record);

  @override
  Future<RiskStoreResult<RiskEpisodeRecord>> clearEpisodeHistory({
    required String accountHash,
    required String episodeKey,
  }) => store.clearEpisodeHistory(
    accountHash: accountHash,
    episodeKey: episodeKey,
    confirmed: true,
  );
}

/// Single serialized capture owner for foreground and service runtimes.
/// Capture, event reduction, persistence and notification delivery are kept in
/// this class so an Android reconnect cannot create a second poller.
class RiskMonitor
    implements
        RiskMonitorOwner,
        RiskMonitorDisposable,
        RiskMonitorCredentialInvalidator {
  RiskMonitor({
    required this.dataSource,
    required this.persistence,
    RiskEngine? engine,
    MarketRiskEngine? marketEngine,
    ActionPlanEvaluator? actionPlanEvaluator,
    RiskEventReducer? eventReducer,
    RiskMonitorClock? clock,
    RiskNotificationSink? notificationSink,
    this.foregroundCadence = const Duration(seconds: 15),
    this.backgroundCadence = const Duration(minutes: 1),
    this.marketCadence = const Duration(minutes: 1),
    this.candleCadence = const Duration(minutes: 5),
    this.historySampleCadence = const Duration(minutes: 15),
    this.oiPersistCadence = const Duration(minutes: 5),
  }) : engine = engine ?? RiskEngine(clock: clock),
       marketEngine = marketEngine ?? MarketRiskEngine(clock: clock),
       actionPlanEvaluator = actionPlanEvaluator ?? const ActionPlanEvaluator(),
       eventReducer = eventReducer ?? RiskEventReducer(clock: clock),
       clock = clock ?? DateTime.now,
       notificationSink = notificationSink ?? const InAppRiskNotificationSink(),
       _states = StreamController<RiskMonitorViewState>.broadcast();

  factory RiskMonitor.fromRepositories({
    required RiskRepository repository,
    required RiskMarketRepository marketRepository,
    required RiskLocalStore store,
    RiskEngine? engine,
    MarketRiskEngine? marketEngine,
    ActionPlanEvaluator? actionPlanEvaluator,
    RiskEventReducer? eventReducer,
    RiskMonitorClock? clock,
    RiskNotificationSink? notificationSink,
    Duration foregroundCadence = const Duration(seconds: 15),
    Duration backgroundCadence = const Duration(minutes: 1),
    Duration marketCadence = const Duration(minutes: 1),
    Duration candleCadence = const Duration(minutes: 5),
    Duration historySampleCadence = const Duration(minutes: 15),
    Duration oiPersistCadence = const Duration(minutes: 5),
  }) {
    return RiskMonitor(
      dataSource: RepositoryRiskMonitorDataSource(
        repository: repository,
        marketRepository: marketRepository,
      ),
      persistence: RiskLocalStorePersistence(store),
      engine: engine,
      marketEngine: marketEngine,
      actionPlanEvaluator: actionPlanEvaluator,
      eventReducer: eventReducer,
      clock: clock,
      notificationSink: notificationSink,
      foregroundCadence: foregroundCadence,
      backgroundCadence: backgroundCadence,
      marketCadence: marketCadence,
      candleCadence: candleCadence,
      historySampleCadence: historySampleCadence,
      oiPersistCadence: oiPersistCadence,
    );
  }

  final RiskMonitorDataSource dataSource;
  final RiskMonitorPersistence persistence;
  final RiskEngine engine;
  final MarketRiskEngine marketEngine;
  final ActionPlanEvaluator actionPlanEvaluator;
  final RiskEventReducer eventReducer;
  final RiskMonitorClock clock;
  final RiskNotificationSink notificationSink;
  final Duration foregroundCadence;
  final Duration backgroundCadence;
  final Duration marketCadence;
  final Duration candleCadence;
  final Duration historySampleCadence;
  final Duration oiPersistCadence;

  final StreamController<RiskMonitorViewState> _states;
  final Map<String, RiskMonitorCommandResult> _commandResults =
      <String, RiskMonitorCommandResult>{};
  Future<void> _workTail = Future<void>.value();
  Future<RiskMonitorCommandResult>? _refreshCommandFuture;

  RiskMonitorViewState _state = RiskMonitorViewState();
  RiskSettings _settings = const RiskSettings();
  final Map<String, _RiskEpisodeMonitorContext> _contexts =
      <String, _RiskEpisodeMonitorContext>{};
  RiskPositionBatch? _positionBatch;
  DateTime? _batchFetchedAt;
  RiskPositionSelection? _positionSelection;
  DateTime? _positionFetchedAt;
  DateTime? _lastStoppedAt;
  DateTime? _nextRetryAt;
  int _failureCount = 0;
  int _generation = 0;
  bool _running = false;
  bool _backgroundMode = false;
  bool _captureInFlight = false;
  Future<void>? _captureFuture;
  Timer? _timer;
  bool _timerCaptureQueued = false;
  bool _reconnectPending = false;
  bool _authBlocked = false;
  final Set<String> _deliveredEventIds = <String>{};
  final Map<String, _CredentialFence> _credentialFences =
      <String, _CredentialFence>{};
  RiskNotificationCapabilityStatus _notificationCapability =
      RiskNotificationCapabilityStatus.unavailable;
  bool _disposed = false;
  RiskMonitorRequestStatus _requestStatus =
      RiskMonitorRequestStatus.unavailable;
  String? _requestEndpointClass;
  RiskQuality _aggregateQuality = const RiskQuality.unavailable(
    reason: 'Monitor has not observed a snapshot',
  );
  String? _aggregateError;

  String? _accountHash;
  String? _episodeKey;
  String? _selectedPositionId;

  @override
  Stream<RiskMonitorViewState> get states => _states.stream;

  @override
  RiskMonitorViewState get currentState => _state;

  bool get isRunning => _running;
  int get generation => _generation;
  Duration get activeCadence =>
      _backgroundMode ? backgroundCadence : foregroundCadence;
  bool get captureInFlight => _captureInFlight;

  /// Used by runtime ownership to publish the owner/capability without
  /// starting a competing monitor.
  void setRuntimeStatus({
    required String ownerLabel,
    required bool backgroundAvailable,
    String? error,
  }) {
    if (_disposed) return;
    _aggregateError = error;
    _publish(
      RiskMonitorViewState(
        isRunning: _running,
        backgroundAvailable: backgroundAvailable,
        ownerLabel: ownerLabel,
        accountHash: _accountHash,
        episodeKey: _episodeKey,
        settings: _settings,
        quality: _aggregateQuality,
        lastError: error,
        notificationCapability: _notificationCapability,
        positions: _orderedContexts()
            .map((context) => context.toViewState(_settings))
            .toList(growable: false),
        requestStatus: _requestStatus,
        retryAt: _nextRetryAt,
        requestEndpointClass: _requestEndpointClass,
      ),
    );
  }

  void setBackgroundMode(bool value) {
    _backgroundMode = value;
    if (_running) _restartTimer();
  }

  /// Permission can change while the app is paused or while the user visits
  /// system settings. Drop the native capability cache before the next
  /// serialized capture so a newly granted/denied state is visible.
  void invalidateNotificationCapability() {
    final sink = notificationSink;
    if (sink is RiskNotificationCapabilityInvalidator) {
      (sink as RiskNotificationCapabilityInvalidator).invalidateCapability();
    }
    _notificationCapability = RiskNotificationCapabilityStatus.unavailable;
    _publishAggregate();
  }

  /// Invalidates all in-flight work immediately. This is called by credential
  /// mutation listeners before a new account can be sampled.
  void invalidateCredentials({String? reason}) {
    _generation++;
    final invalidator = dataSource;
    if (invalidator is RiskMonitorCacheInvalidator) {
      (invalidator as RiskMonitorCacheInvalidator).clearCaches();
    }
    _authBlocked = false;
    _nextRetryAt = null;
    _failureCount = 0;
    _cancelTimer();
    _contexts.clear();
    _positionBatch = null;
    _batchFetchedAt = null;
    _positionSelection = null;
    _positionFetchedAt = null;
    _accountHash = null;
    _episodeKey = null;
    _selectedPositionId = null;
    _deliveredEventIds.clear();
    _requestStatus = RiskMonitorRequestStatus.unavailable;
    _requestEndpointClass = null;
    _aggregateQuality = const RiskQuality.unavailable(
      reason: 'Credentials changed; monitoring is restarting',
    );
    _aggregateError = reason;
    _running = false;
    _publish(
      RiskMonitorViewState(
        isRunning: false,
        backgroundAvailable: _state.backgroundAvailable,
        ownerLabel: _state.ownerLabel,
        quality: const RiskQuality.unavailable(
          reason: 'Credentials changed; monitoring is restarting',
        ),
        lastError: reason,
        positions: const <RiskPositionMonitorViewState>[],
        requestStatus: RiskMonitorRequestStatus.unavailable,
      ),
    );
  }

  @override
  void fenceCredentialsForCommand(String commandId, {String? reason}) {
    final key = commandId.trim();
    if (_disposed || key.isEmpty) return;
    if (_commandResults.containsKey(key) ||
        _credentialFences.containsKey(key)) {
      return;
    }
    _credentialFences[key] = _CredentialFence(
      wasRunning: _running,
      accountHash: _accountHash,
      episodeKey: _episodeKey,
    );
    invalidateCredentials(reason: reason);
  }

  /// Allows a runtime to publish an unavailable Android capability while
  /// preserving the typed state protocol.
  void publishRuntimeState(RiskMonitorViewState state) => _publish(state);

  @override
  Future<RiskMonitorCommandResult> dispatch(RiskMonitorCommand command) {
    if (command.type == RiskMonitorCommandType.refresh &&
        !_disposed &&
        command.id.trim().isNotEmpty) {
      final existingRefresh = _refreshCommandFuture;
      if (existingRefresh != null) {
        return existingRefresh.then((result) {
          final coalesced = RiskMonitorCommandResult(
            commandId: command.id,
            status: result.status,
            state: result.state,
            message: result.message,
            replayed: true,
          );
          _commandResults[command.id.trim()] = coalesced;
          return coalesced;
        });
      }
    }
    if (command.type == RiskMonitorCommandType.invalidateCredentials &&
        !_disposed &&
        command.id.trim().isNotEmpty &&
        !_commandResults.containsKey(command.id.trim()) &&
        !_credentialFences.containsKey(command.id.trim())) {
      // Fence before joining the serialized work queue. An in-flight capture
      // will observe the generation change and cannot persist old identity
      // data while this command waits its turn to restart.
      fenceCredentialsForCommand(command.id, reason: command.reason);
    }
    final completer = Completer<RiskMonitorCommandResult>();
    final resultFuture = completer.future;
    if (command.type == RiskMonitorCommandType.refresh &&
        !_disposed &&
        command.id.trim().isNotEmpty) {
      _refreshCommandFuture = resultFuture;
      resultFuture.then<void>(
        (_) {
          if (identical(_refreshCommandFuture, resultFuture)) {
            _refreshCommandFuture = null;
          }
        },
        onError: (Object _, StackTrace __) {
          if (identical(_refreshCommandFuture, resultFuture)) {
            _refreshCommandFuture = null;
          }
        },
      );
    }
    _workTail = _workTail.then<void>((_) async {
      try {
        completer.complete(await _dispatchInternal(command));
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return resultFuture;
  }

  Future<void> _enqueueWork(Future<void> Function() work) {
    final completer = Completer<void>();
    _workTail = _workTail.then<void>((_) async {
      try {
        await work();
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<RiskMonitorCommandResult> _dispatchInternal(
    RiskMonitorCommand command,
  ) async {
    if (_disposed) {
      return RiskMonitorCommandResult(
        commandId: command.id,
        status: RiskMonitorCommandStatus.failed,
        state: _state,
        message: 'Monitor is disposed',
      );
    }
    final id = command.id.trim();
    if (id.isEmpty) {
      return RiskMonitorCommandResult(
        commandId: command.id,
        status: RiskMonitorCommandStatus.rejected,
        state: _state,
        message: 'Command id is required',
      );
    }
    final existing = _commandResults[id];
    if (existing != null) {
      return RiskMonitorCommandResult(
        commandId: existing.commandId,
        status: existing.status,
        state: existing.state,
        message: existing.message,
        replayed: true,
      );
    }

    late final RiskMonitorCommandResult result;
    try {
      switch (command.type) {
        case RiskMonitorCommandType.start:
          result = await _start(command);
        case RiskMonitorCommandType.stop:
          result = await _stop(command);
        case RiskMonitorCommandType.refresh:
          result = await _refresh(command);
        case RiskMonitorCommandType.reconnect:
          result = await _reconnect(command);
        case RiskMonitorCommandType.updatePlan:
          result = await _updatePlan(command);
        case RiskMonitorCommandType.updateSettings:
          result = await _updateSettings(command);
        case RiskMonitorCommandType.clearHistory:
          result = await _clearHistory(command);
        case RiskMonitorCommandType.invalidateCredentials:
          result = await _invalidateCredentialsCommand(command);
        case RiskMonitorCommandType.uiDeparture:
          result = await _uiDeparture(command);
        case RiskMonitorCommandType.uiResume:
          result = await _uiResume(command);
      }
    } catch (_) {
      result = RiskMonitorCommandResult(
        commandId: command.id,
        status: RiskMonitorCommandStatus.failed,
        state: _state,
        message: 'Risk monitor command failed',
      );
    }
    _commandResults[id] = result;
    return result;
  }

  Future<RiskMonitorCommandResult> _start(RiskMonitorCommand command) async {
    final requestedAccount = _normalize(command.accountHash);
    final requestedEpisode = _normalize(command.episodeKey);
    final sameIdentity =
        _running &&
        (requestedAccount == null || requestedAccount == _accountHash) &&
        (requestedEpisode == null || requestedEpisode == _episodeKey);
    if (!sameIdentity) {
      if (_running) _generation++;
      _cancelTimer();
      _running = true;
      _authBlocked = false;
      _nextRetryAt = null;
      _failureCount = 0;
      _accountHash = requestedAccount;
      _episodeKey = requestedEpisode;
      _settings = const RiskSettings();
      _contexts.clear();
      _positionBatch = null;
      _batchFetchedAt = null;
      _positionSelection = null;
      _positionFetchedAt = null;
      _reconnectPending = false;
      _deliveredEventIds.clear();
      _requestStatus = RiskMonitorRequestStatus.ready;
      _requestEndpointClass = null;
      _aggregateQuality = const RiskQuality.unavailable(
        reason: 'Monitor has not observed a snapshot',
      );
      _aggregateError = null;
      _resetPublishedIdentity();
      if (_accountHash != null) await _loadSettings(_generation);
    }
    _running = true;
    _restartTimer();
    invalidateNotificationCapability();
    await _refreshNotificationCapability(_generation);
    await _requestCapture(force: true);
    return _accepted(command, 'Monitor started');
  }

  Future<RiskMonitorCommandResult> _stop(RiskMonitorCommand command) async {
    if (!_running) return _accepted(command, 'Monitor already stopped');
    _generation++;
    _cancelTimer();
    _running = false;
    final generation = _generation;
    await _flushAllOpenInterest(generation);
    await _persistAllDepartureBaselines(generation);
    _lastStoppedAt = _now();
    _requestStatus = RiskMonitorRequestStatus.ready;
    _publishAggregate(isRunning: false);
    return _accepted(command, 'Monitor stopped');
  }

  Future<RiskMonitorCommandResult> _refresh(RiskMonitorCommand command) async {
    if (!_running) return _rejected(command, 'Monitor is not running');
    invalidateNotificationCapability();
    await _refreshNotificationCapability(_generation);
    if (_authBlocked) {
      // A user-triggered refresh is the explicit retry gate after a 401. It
      // clears only the blocked generation's retry state and repository
      // caches; credential mutation still remains the stronger identity
      // fence used by the runtime bus.
      _authBlocked = false;
      _nextRetryAt = null;
      _failureCount = 0;
      final invalidator = dataSource;
      if (invalidator is RiskMonitorCacheInvalidator) {
        (invalidator as RiskMonitorCacheInvalidator).clearCaches();
      }
      _positionBatch = null;
      _batchFetchedAt = null;
      _positionSelection = null;
      _positionFetchedAt = null;
    }
    await _requestCapture(force: true);
    return _accepted(command, 'Refresh completed');
  }

  Future<RiskMonitorCommandResult> _invalidateCredentialsCommand(
    RiskMonitorCommand command,
  ) async {
    final fence = _credentialFences.remove(command.id.trim());
    final wasRunning = fence?.wasRunning ?? _running;
    final account = fence?.accountHash ?? _accountHash;
    final episode = fence?.episodeKey ?? _episodeKey;
    if (fence == null) {
      invalidateCredentials(reason: command.reason ?? 'Credentials changed');
    }
    if (!wasRunning && account == null && episode == null) {
      return _accepted(command, 'Credentials invalidated');
    }
    // The service owner must fence and clear the old generation before it
    // restarts the same requested identity against the newly saved keys.
    if (!wasRunning) {
      return _accepted(command, 'Credentials invalidated');
    }
    final restart = RiskMonitorCommand.start(
      id: '${command.id}:restart',
      accountHash: account,
      episodeKey: episode,
    );
    await _start(restart);
    return _accepted(command, 'Credentials invalidated and monitor restarted');
  }

  Future<RiskMonitorCommandResult> _uiDeparture(
    RiskMonitorCommand command,
  ) async {
    if (!_running) return _rejected(command, 'Monitor is not running');
    final generation = _generation;
    final departureAt = _now();
    var allSaved = true;
    var savedAny = false;
    for (final context in _contexts.values.toList(growable: false)) {
      final record = _recordWithPendingOpenInterest(context);
      final baseline =
          context.latestAcceptedSample ??
          record?.latches.lastSample ??
          record?.currentSample ??
          context.session?.departure();
      context.uiDepartureAt = departureAt;
      context.uiDepartureBaseline = baseline;
      if (baseline == null || record == null) continue;
      final next = record.copyWith(lastCheckBaseline: baseline);
      final saved = await persistence.saveEpisode(
        accountHash: context.accountHash,
        record: next,
      );
      if (!_isGenerationCurrent(generation)) {
        return _failed(command, 'UI departure was invalidated');
      }
      if (!saved.isSuccess) {
        allSaved = false;
        context.unsaved = true;
        context.lastError = 'UI departure baseline was not saved';
      } else {
        savedAny = true;
        context.record = saved.value ?? next;
        context.pendingRecord = null;
        context.pendingOpenInterest = const <MarketOpenInterestSample>[];
        context.lastOiPersistAt = context.record?.openInterest.isEmpty == true
            ? context.lastOiPersistAt
            : context.record?.openInterest.last.timestamp;
        context.unsaved = false;
      }
    }
    _publishAggregate();
    if (!allSaved) {
      return _failed(command, 'UI departure baseline was not saved');
    }
    return _accepted(
      command,
      savedAny
          ? 'UI departure baselines saved'
          : 'UI departure recorded without a baseline',
    );
  }

  Future<RiskMonitorCommandResult> _uiResume(RiskMonitorCommand command) async {
    if (!_running) return _rejected(command, 'Monitor is not running');
    final now = _now();
    for (final context in _contexts.values) {
      final departureAt = context.uiDepartureAt;
      final baseline = context.uiDepartureBaseline;
      final away = departureAt == null
          ? Duration.zero
          : now.difference(departureAt).isNegative
          ? Duration.zero
          : now.difference(departureAt);
      // Service polling continues during the UI departure. Freeze each visit
      // session while it is away, then seed a new comparison only after the
      // complete >60-second departure window has elapsed.
      if (departureAt != null &&
          baseline != null &&
          away > const Duration(seconds: 60)) {
        context.session = RiskCheckSession.start(
          episodeKey: context.episodeKey,
          now: now,
          savedBaseline: baseline,
          awayDuration: away,
        );
      }
      context.uiDepartureAt = null;
      context.uiDepartureBaseline = null;
    }
    // The service owner may have cached a native permission result while the
    // UI was away. Invalidate and re-read it before the resume capture so any
    // event produced by that capture is classified against current permission.
    invalidateNotificationCapability();
    await _refreshNotificationCapability(_generation);
    await _requestCapture(force: true);
    return _accepted(command, 'UI resume acknowledged');
  }

  Future<RiskMonitorCommandResult> _reconnect(
    RiskMonitorCommand command,
  ) async {
    if (!_running) return _rejected(command, 'Monitor is not running');
    _reconnectPending = true;
    await _requestCapture(force: true);
    return _accepted(command, 'Reconnect acknowledged');
  }

  Future<RiskMonitorCommandResult> _updatePlan(
    RiskMonitorCommand command,
  ) async {
    final generation = _generation;
    final plan = command.plan;
    if (plan == null || !plan.isValid) {
      return _rejected(command, 'Plan validation failed');
    }
    final context = _contextForCommand(command);
    if (context == null && command.episodeKey != null) {
      return _rejected(command, 'Plan episode does not match monitor');
    }
    if (context != null && plan.episodeKey != context.episodeKey) {
      return _rejected(command, 'Plan episode does not match monitor');
    }
    if (context == null) {
      _publishAggregate(unsaved: true);
      return _accepted(command, 'Plan updated locally; account is unresolved');
    }
    context.plan = plan;
    final existing =
        _recordWithPendingOpenInterest(context) ??
        _newRecord(context.accountHash, plan.episodeKey);
    final next = existing.copyWith(plan: plan);
    // Keep an immutable retry candidate when persistence is temporarily
    // unavailable so stop/close handling cannot discard a valid plan edit.
    context.pendingRecord = next;
    late final RiskStoreResult<RiskEpisodeRecord> saved;
    try {
      saved = await persistence.saveEpisode(
        accountHash: context.accountHash,
        record: next,
      );
    } catch (_) {
      context.unsaved = true;
      context.lastError = 'Plan was not saved';
      _publishAggregate();
      return _failed(command, 'Plan was not saved');
    }
    if (!_isGenerationCurrent(generation)) {
      return _failed(command, 'Plan update was invalidated');
    }
    if (!saved.isSuccess) {
      context.unsaved = true;
      context.lastError = 'Plan was not saved';
      _publishAggregate();
      return _failed(command, 'Plan was not saved');
    }
    context.record = saved.value ?? next;
    context.pendingRecord = null;
    context.plan = plan;
    context.unsaved = false;
    context.lastError = null;
    _publishAggregate();
    return _accepted(command, 'Plan updated');
  }

  Future<RiskMonitorCommandResult> _updateSettings(
    RiskMonitorCommand command,
  ) async {
    final generation = _generation;
    final settings = command.settings;
    if (settings == null || !settings.isValid) {
      return _rejected(command, 'Settings validation failed');
    }
    final account = _accountHash;
    if (account == null) {
      _settings = settings;
      _publishAggregate(unsaved: true);
      return _accepted(
        command,
        'Settings updated locally; account is unresolved',
      );
    }
    final saved = await persistence.saveSettings(
      accountHash: account,
      settings: settings,
    );
    if (!_isGenerationCurrent(generation)) {
      return _failed(command, 'Settings update was invalidated');
    }
    if (!saved.isSuccess) {
      _settings = settings;
      _publishAggregate(unsaved: true);
      return _failed(command, 'Settings were not saved');
    }
    _settings = settings;
    _publishAggregate(unsaved: false);
    return _accepted(command, 'Settings updated');
  }

  Future<RiskMonitorCommandResult> _clearHistory(
    RiskMonitorCommand command,
  ) async {
    final generation = _generation;
    final context = _contextForCommand(command);
    if (context == null) {
      return _rejected(command, 'Account and episode are required');
    }
    final account = context.accountHash;
    final episode = context.episodeKey;
    final result = await persistence.clearEpisodeHistory(
      accountHash: account,
      episodeKey: episode,
    );
    if (!_isGenerationCurrent(generation)) {
      return _failed(command, 'History clear was invalidated');
    }
    if (!result.isSuccess) return _failed(command, 'History was not cleared');
    context.record =
        result.value ??
        context.record?.copyWith(
          samples: const <RiskHistorySample>[],
          openInterest: const <MarketOpenInterestSample>[],
          events: const <RiskEvent>[],
          summaries: const <RiskDailySummary>[],
          latches: RiskEventLatch(episodeKey: episode),
          clearLastCheckBaseline: true,
        );
    context.pendingRecord = null;
    // Clear every derived history cursor together with the durable history.
    // Otherwise a later OI flush or a sparse sample can reintroduce data that
    // the user just cleared.
    context.persistedSamples = const <RiskHistorySample>[];
    context.pendingOpenInterest = const <MarketOpenInterestSample>[];
    context.lastHistoryPersistAt = null;
    context.lastOiPersistAt = null;
    context.previousPlanEvaluation = null;
    context.deliveredEventIds.clear();
    context.session = RiskCheckSession.start(
      episodeKey: episode,
      now: _now(),
      awayDuration: Duration.zero,
    );
    context.uiDepartureAt = null;
    context.uiDepartureBaseline = null;
    context.latestAcceptedSample = null;
    context.visibleEvents = const <RiskEvent>[];
    context.visibleSamples = const <RiskHistorySample>[];
    context.visibleSummaries = const <RiskDailySummary>[];
    context.previousCheck = null;
    context.trend = null;
    context.velocity = null;
    context.unsaved = false;
    context.lastError = null;
    _publishAggregate();
    return _accepted(command, 'History cleared');
  }

  Future<void> _requestCapture({required bool force}) {
    final existing = _captureFuture;
    if (existing != null) return existing;
    final future = _capture(force: force);
    _captureFuture = future;
    future.whenComplete(() {
      if (identical(_captureFuture, future)) _captureFuture = null;
    });
    return future;
  }

  Future<void> _capture({required bool force}) async {
    if (!_running || _disposed) return;
    final now = _now();
    if (_nextRetryAt != null && now.isBefore(_nextRetryAt!)) {
      _requestStatus = RiskMonitorRequestStatus.backingOff;
      _publishAggregate();
      return;
    }
    if (_authBlocked) {
      _requestStatus = RiskMonitorRequestStatus.authBlocked;
      _publishAggregate();
      return;
    }
    _captureInFlight = true;
    _requestStatus = RiskMonitorRequestStatus.refreshing;
    _publishAggregate();
    final initialGeneration = _generation;
    try {
      final batch = await _loadPositionBatch(initialGeneration, force: force);
      if (!_isCurrent(initialGeneration) || batch == null) return;
      final selectionFailure =
          _positionBatchFetchedThisCapture &&
              dataSource is RiskMonitorSelectionFailureMetadata
          ? (dataSource as RiskMonitorSelectionFailureMetadata)
                .lastSelectionFailure
          : null;
      final selectionFailureAuth =
          selectionFailure?.credentialFailure == true ||
          selectionFailure?.statusCode == 401;
      if (selectionFailure != null) {
        _registerFailure(
          selectionFailureAuth,
          retryAfter: selectionFailure.retryAfter,
        );
        _requestEndpointClass = selectionFailure.endpoint;
      } else if (batch.quality.status == RiskQualityStatus.error) {
        // Batch implementations that cannot expose typed selection metadata
        // still participate in the shared retry policy through their quality.
        _registerFailure(false);
      }

      _aggregateQuality = batch.quality;
      final positions = batch.positions
          .where(_isSupportedPosition)
          .where((position) => position.episodeKey.trim().isNotEmpty)
          .toList(growable: false);
      final account = positions
          .map((position) => _normalize(position.accountNamespace))
          .whereType<String>()
          .firstWhere((value) => value.isNotEmpty, orElse: () => '');
      if (account.isNotEmpty &&
          _accountHash != null &&
          _accountHash != account) {
        _generation++;
        if (!_running || _disposed) return;
        _contexts.clear();
        _settings = const RiskSettings();
        _positionBatch = batch;
        _batchFetchedAt = _now();
        _accountHash = account;
        _episodeKey = null;
        await _loadSettings(_generation);
      } else if (account.isNotEmpty && _accountHash == null) {
        _accountHash = account;
        await _loadSettings(_generation);
      }
      if (!_isCurrent(_generation)) return;

      final seen = <String>{};
      for (final position in positions) {
        final positionAccount = _normalize(position.accountNamespace);
        if (positionAccount == null ||
            (_accountHash != null && positionAccount != _accountHash)) {
          continue;
        }
        final episode = position.episodeKey.trim();
        if (episode.isEmpty) continue;
        seen.add(episode);
        _RiskEpisodeMonitorContext? context = _contexts[episode];
        try {
          if (context == null) {
            context = _RiskEpisodeMonitorContext(
              accountHash: positionAccount,
              episodeKey: episode,
              position: position,
            );
            _contexts[episode] = context;
            await _loadEpisodeContext(context, _generation);
            if (!_isCurrent(_generation)) return;
          } else {
            context.position = position;
          }
          await _captureEpisode(context, _generation);
        } catch (_) {
          if (!_isCurrent(_generation)) return;
          // Evaluation/storage failures are scoped to this episode. Keep its
          // last-good values and let the remaining positions continue.
          context?.quality = const RiskQuality.stale(
            reason: 'Position risk evaluation failed',
          );
          context?.unsaved = true;
          context?.lastError = 'Position risk evaluation failed';
        }
        if (!_isCurrent(_generation)) return;
      }

      // A failed/unavailable account discovery is not evidence that existing
      // positions were closed. Reconcile episode closure only after a usable
      // batch result, while still allowing partial enrichment to close rows
      // that the authoritative position list no longer contains.
      final lifecycleRows = batch.positions.isNotEmpty
          ? batch.positions
          : batch.candidates;
      final hasUnresolvedIdentity = lifecycleRows.any(
        (position) =>
            _normalize(position.accountNamespace) == null ||
            position.episodeKey.trim().isEmpty,
      );
      final canReconcileLifecycle =
          batch.status != RiskEligibility.invalid &&
          batch.quality.status != RiskQualityStatus.error &&
          batch.quality.status != RiskQualityStatus.unavailable &&
          !hasUnresolvedIdentity;
      if (canReconcileLifecycle) {
        await _closeMissingContexts(seen, _generation);
      }
      if (!_isCurrent(_generation)) return;
      _reconnectPending = false;
      if (selectionFailure != null) {
        final message = selectionFailureAuth
            ? 'Credentials were rejected during risk enrichment'
            : 'Risk enrichment request failed'
                  '${selectionFailure.statusCode == null ? '' : ' (HTTP ${selectionFailure.statusCode})'}';
        for (final episode in seen) {
          final context = _contexts[episode];
          if (context == null) continue;
          if (selectionFailureAuth) {
            context.lastError = message;
          } else {
            context.lastError ??= message;
          }
        }
      }
      final retryAt = _nextRetryAt;
      final retryExpired = retryAt == null || !_now().isBefore(retryAt);
      if (selectionFailure == null &&
          batch.quality.status != RiskQualityStatus.error &&
          retryExpired &&
          !_authBlocked) {
        _clearFailure();
      }
      _aggregateError = selectionFailure == null
          ? batch.message
          : selectionFailureAuth
          ? 'Credentials were rejected during risk enrichment'
          : 'Risk enrichment request failed'
                '${selectionFailure.statusCode == null ? '' : ' (HTTP ${selectionFailure.statusCode})'}';
      _requestStatus = _deriveRequestStatus();
      _publishAggregate();
    } on RiskRepositoryException catch (error) {
      if (!_isCurrent(initialGeneration)) return;
      _registerFailure(
        error.credentialFailure || error.statusCode == 401,
        retryAfter: error.retryAfter,
      );
      _requestEndpointClass = error.endpoint;
      _aggregateQuality = RiskQuality.error(
        source: error.endpoint,
        reason: 'Risk source request failed',
      );
      _aggregateError = error.credentialFailure || error.statusCode == 401
          ? 'Credentials were rejected; monitoring is paused'
          : 'Risk source is unavailable';
      _requestStatus = _deriveRequestStatus();
      _publishAggregate();
    } catch (_) {
      if (!_isCurrent(initialGeneration)) return;
      _registerFailure(false);
      _aggregateQuality = const RiskQuality.error(
        reason: 'Risk monitor capture failed',
      );
      _aggregateError = 'Risk monitor capture failed';
      _requestStatus = _deriveRequestStatus();
      _publishAggregate();
    } finally {
      _captureInFlight = false;
      if (_isGenerationCurrent(initialGeneration) && _running) {
        _requestStatus = _deriveRequestStatus();
        _publishAggregate();
      }
    }
  }

  bool _positionBatchFetchedThisCapture = false;

  Future<RiskPositionBatch?> _loadPositionBatch(
    int generation, {
    required bool force,
  }) async {
    final before = _now();
    final cached = _positionBatch;
    final fresh =
        cached != null &&
        _batchFetchedAt != null &&
        before.difference(_batchFetchedAt!) < activeCadence &&
        !force;
    _positionBatchFetchedThisCapture = !fresh;
    if (fresh) return cached;

    final source = dataSource;
    final batch = source is RiskMonitorBatchDataSource
        ? await (source as RiskMonitorBatchDataSource).loadPositionsBatch()
        : await _loadLegacyPositionBatch(force: force);
    if (!_isGenerationCurrent(generation)) return null;
    _positionBatch = batch;
    _batchFetchedAt = _now();
    return batch;
  }

  Future<RiskPositionBatch> _loadLegacyPositionBatch({
    required bool force,
  }) async {
    final before = _now();
    final cachedSelection = _positionSelection;
    final fresh =
        cachedSelection != null &&
        _positionFetchedAt != null &&
        before.difference(_positionFetchedAt!) < activeCadence &&
        !force;
    final selection = fresh
        ? cachedSelection
        : await dataSource.loadPosition(
            selectedPositionId: _selectedPositionId,
            selectedEpisodeKey: _episodeKey,
          );
    if (!fresh) {
      _positionSelection = selection;
      _positionFetchedAt = _now();
    }
    final position = selection.position;
    return RiskPositionBatch(
      status: selection.status,
      quality: selection.quality,
      positions: position == null
          ? const <RiskPosition>[]
          : <RiskPosition>[position],
      candidates: selection.candidates,
      message: selection.message,
    );
  }

  bool _isSupportedPosition(RiskPosition position) =>
      position.isEligible &&
      position.quoteCurrency.trim().toUpperCase() == 'USDT';

  Future<void> _captureEpisode(
    _RiskEpisodeMonitorContext context,
    int generation,
  ) async {
    if (!_isCurrent(generation)) return;
    if (_authBlocked ||
        (_nextRetryAt != null && _now().isBefore(_nextRetryAt!))) {
      context.quality = _authBlocked
          ? const RiskQuality.stale(
              reason: 'Credentials were rejected by the risk source',
            )
          : const RiskQuality.stale(
              reason: 'Risk source is backing off after a failed request',
            );
      context.lastError = _authBlocked
          ? 'Credentials were rejected by the risk source'
          : 'Risk source is backing off after a failed request';
      return;
    }
    final position = context.position;
    final now = _now();
    var market = context.market;
    final marketIsFresh =
        market != null &&
        context.marketFetchedAt != null &&
        now.difference(context.marketFetchedAt!) < marketCadence;
    if (!marketIsFresh) {
      try {
        final includeCandles =
            context.marketSnapshot == null ||
            context.candleSnapshotFetchedAt == null ||
            now.difference(context.candleSnapshotFetchedAt!) >= candleCadence;
        final snapshot = dataSource is RiskMonitorMarketCadenceSource
            ? await (dataSource as RiskMonitorMarketCadenceSource)
                  .loadMarketCadence(
                    position: position,
                    now: now,
                    includeCandles: includeCandles,
                  )
            : await dataSource.loadMarket(position: position, now: now);
        if (!_isCurrent(generation)) return;
        final effectiveSnapshot = _mergeMarketSnapshot(
          context,
          snapshot,
          includeCandles: dataSource is RiskMonitorMarketCadenceSource
              ? includeCandles
              : true,
        );
        context.marketSnapshot = effectiveSnapshot;
        if (dataSource is! RiskMonitorMarketCadenceSource || includeCandles) {
          context.candleSnapshotFetchedAt = now;
        }
        market = marketEngine
            .evaluate(
              effectiveSnapshot,
              isBtcPosition: position.baseCurrency?.toUpperCase() == 'BTC',
              now: now,
            )
            .input;
        context.market = market;
        context.marketFetchedAt = now;
      } on RiskRepositoryException catch (error) {
        if (error.credentialFailure || error.statusCode == 401) {
          _registerFailure(true, retryAfter: error.retryAfter);
          _requestEndpointClass = error.endpoint;
        } else {
          _registerFailure(false, retryAfter: error.retryAfter);
          _requestEndpointClass = error.endpoint;
        }
        context.quality = const RiskQuality.stale(
          reason: 'Market source is unavailable',
        );
        context.lastError = 'Market source is unavailable';
        return;
      } catch (_) {
        // Preserve the last published risk and expose a per-position quality
        // problem; a failing market source cannot stop another episode.
        context.quality = const RiskQuality.stale(
          reason: 'Market source is unavailable',
        );
        context.lastError = 'Market source is unavailable';
        return;
      }
    }

    final evaluation = engine.evaluate(
      position,
      policy: _settings.policy,
      market: market,
      now: now,
      customPrices: _settings.customStressPrices,
    );
    final plan = context.plan ?? RiskPlan(episodeKey: context.episodeKey);
    final planEvaluation = actionPlanEvaluator.evaluatePlan(
      plan,
      evaluation,
      at: now,
    );
    final sample = RiskHistorySample.fromEvaluation(
      episodeKey: context.episodeKey,
      evaluation: evaluation,
      market: market,
    );
    final hasPendingRecord = context.pendingRecord != null;
    final currentRecord =
        context.pendingRecord ??
        context.record ??
        _newRecord(context.accountHash, context.episodeKey, plan: plan);
    final priorSample =
        context.latestAcceptedSample ?? currentRecord.currentSample;
    final reduction = eventReducer.reduce(
      priorSample,
      sample,
      currentRecord.latches,
      _settings.policy,
      previousPlan: context.previousPlanEvaluation,
      currentPlan: planEvaluation,
      now: now,
      reconnected:
          _reconnectPending &&
          priorSample != null &&
          now.difference(priorSample.observedAt) > const Duration(minutes: 5),
    );
    context.previousPlanEvaluation = planEvaluation;

    final nextSummary = RiskDailySummaryCapture.capture(
      sample: sample,
      timeZone: _timeZone(_settings.timeZone, now),
      summaryHour: _settings.summaryHour,
      summaryMinute: _settings.summaryMinute,
      existing: currentRecord.summaries,
      majorChange: reduction.events.isEmpty
          ? null
          : reduction.events.first.message,
      activeRuleCount:
          planEvaluation.activeCount + planEvaluation.activeZoneCount,
      unknownRuleCount: planEvaluation.unknownCount,
    );
    final summaries = <RiskDailySummary>[
      ...currentRecord.summaries,
      if (nextSummary != null) nextSummary,
    ];
    final lastHistoryAt = context.lastHistoryPersistAt;
    final historyDue =
        context.persistedSamples.isEmpty ||
        lastHistoryAt == null ||
        now.difference(lastHistoryAt) >= historySampleCadence;
    final eventDue = reduction.events.isNotEmpty;
    final persistedSampleBase = _mergeHistorySamples(
      context.persistedSamples,
      currentRecord.samples,
    );
    final persistedSamples = historyDue || eventDue
        ? _appendFreshSample(persistedSampleBase, sample)
        : persistedSampleBase;
    final lastOiAt = context.lastOiPersistAt;
    final oiDue =
        context.pendingOpenInterest.isNotEmpty &&
        (currentRecord.openInterest.isEmpty ||
            lastOiAt == null ||
            now.difference(lastOiAt) >= oiPersistCadence);
    final persistedOpenInterest = oiDue
        ? context.pendingOpenInterest
        : currentRecord.openInterest;
    final persistedLatches = reduction.events.isEmpty
        ? reduction.latches
        : reduction.latches.copyWith(
            emittedEventIds: <String>{
              ...reduction.latches.emittedEventIds,
              ...reduction.events.map((event) => event.id),
            }.toList(growable: false),
          );
    final nextRecord = currentRecord.copyWith(
      plan: plan,
      updatedAt: now,
      samples: persistedSamples,
      openInterest: persistedOpenInterest,
      events: <RiskEvent>[...currentRecord.events, ...reduction.events],
      summaries: summaries,
      latches: persistedLatches,
      clearClosedAt: true,
    );
    RiskStoreResult<RiskEpisodeRecord>? saved;
    final needsPersistence =
        hasPendingRecord ||
        historyDue ||
        eventDue ||
        oiDue ||
        nextSummary != null;
    if (needsPersistence) {
      context.pendingRecord = nextRecord;
      saved = await persistence.saveEpisode(
        accountHash: context.accountHash,
        record: nextRecord,
      );
      if (!_isCurrent(generation)) return;
      if (saved.isSuccess) {
        context.record = saved.value ?? nextRecord;
        context.pendingRecord = null;
        context.persistedSamples =
            saved.value?.samples ??
            List<RiskHistorySample>.unmodifiable(persistedSamples);
        if (historyDue || eventDue) context.lastHistoryPersistAt = now;
        if (oiDue) context.lastOiPersistAt = now;
        context.unsaved = false;
        context.lastError = null;
      } else {
        context.unsaved = true;
        context.lastError = 'Episode state was not saved';
      }
    } else {
      // Keep the in-memory record aligned with durable cadence. The latest
      // accepted observation is carried separately for event comparison;
      // appending it to the record would make an OI-only flush look persisted.
      context.record = nextRecord;
      context.pendingRecord = null;
    }

    context.latestAcceptedSample = sample;
    final persisted =
        !needsPersistence || saved?.notificationDeliveryAllowed == true;
    final visibleRecord = saved?.value ?? nextRecord;
    final visibleSamples = _appendFreshSample(visibleRecord.samples, sample);
    context.evaluation = evaluation;
    context.planEvaluation = planEvaluation;
    context.plan = plan;
    context.visibleSamples = visibleSamples;
    context.visibleSummaries = visibleRecord.summaries;
    context.visibleEvents = visibleRecord.events;
    if (context.uiDepartureAt == null) {
      context.session =
          (context.session ??
                  RiskCheckSession.start(
                    episodeKey: context.episodeKey,
                    now: now,
                    savedBaseline: currentRecord.lastCheckBaseline,
                    awayDuration: _awayDuration(now),
                  ))
              .observe(sample);
    }
    context.previousCheck = context.session?.comparison;
    context.trend = RiskHistoryAnalytics.trend(
      current: sample,
      history: visibleSamples,
      now: now,
    );
    context.velocity = RiskHistoryAnalytics.velocity(
      current: sample,
      history: visibleSamples,
      now: now,
    );
    context.quality = evaluation.quality;
    if (!context.unsaved && !position.quality.isPartial) {
      context.lastError = null;
    }
    if (position.quality.isPartial && context.lastError == null) {
      context.lastError = position.quality.reason;
    }
    if (persisted && reduction.events.isNotEmpty) {
      await _deliver(context, reduction.events, generation);
    }
  }

  Future<void> _closeMissingContexts(
    Set<String> activeEpisodeKeys,
    int generation,
  ) async {
    final missing = _contexts.entries
        .where((entry) => !activeEpisodeKeys.contains(entry.key))
        .map((entry) => entry.value)
        .toList(growable: false);
    for (final context in missing) {
      if (!_isGenerationCurrent(generation)) return;
      await _flushOpenInterest(context, generation);
      await _persistDepartureBaseline(context, generation);
      if (!_isGenerationCurrent(generation)) return;
      final record = _recordWithPendingOpenInterest(context);
      if (record != null && !record.isClosed) {
        final closed = record.copyWith(closedAt: _now());
        final saved = await persistence.saveEpisode(
          accountHash: context.accountHash,
          record: closed,
        );
        if (!_isGenerationCurrent(generation)) return;
        if (!saved.isSuccess) {
          // Keep the context available with its retained history when a close
          // write fails; the next batch can retry without data loss.
          context.unsaved = true;
          context.lastError = 'Closed episode was not saved';
          continue;
        }
        context.record = saved.value ?? closed;
        context.pendingRecord = null;
      }
      _contexts.remove(context.episodeKey);
    }
  }

  Future<void> _deliver(
    _RiskEpisodeMonitorContext context,
    List<RiskEvent> events,
    int generation,
  ) async {
    if (!_isCurrent(generation)) return;
    RiskNotificationCapability capability;
    try {
      capability = await notificationSink.capability();
    } catch (_) {
      capability = const RiskNotificationCapability.unavailable(
        'Notification capability unavailable',
      );
    }
    _notificationCapability = capability.status;
    _publishAggregate();
    if (!capability.canDeliver) return;
    for (final event in events) {
      if (!_isCurrent(generation) || !context.deliveredEventIds.add(event.id)) {
        continue;
      }
      final notification = RiskNotification.fromEvent(event);
      if (!notification.isPrivacySafe) {
        context.deliveredEventIds.remove(event.id);
        continue;
      }
      try {
        final result = await notificationSink.deliver(notification);
        if (!result.delivered) context.deliveredEventIds.remove(event.id);
      } catch (_) {
        context.deliveredEventIds.remove(event.id);
      }
    }
  }

  Future<void> _refreshNotificationCapability(int generation) async {
    if (!_isCurrent(generation)) return;
    RiskNotificationCapability capability;
    try {
      capability = await notificationSink.capability();
    } catch (_) {
      capability = const RiskNotificationCapability.unavailable(
        'Notification capability unavailable',
      );
    }
    if (!_isCurrent(generation)) return;
    _notificationCapability = capability.status;
    _publishAggregate();
  }

  Future<void> _loadEpisodeContext(
    _RiskEpisodeMonitorContext context,
    int generation,
  ) async {
    if (!_isCurrent(generation)) return;
    final result = await persistence.loadEpisode(
      accountHash: context.accountHash,
      episodeKey: context.episodeKey,
    );
    if (!_isCurrent(generation)) return;
    if (result.isSuccess && result.value != null) {
      context.record = result.value!.isClosed
          ? result.value!.copyWith(clearClosedAt: true)
          : result.value;
      context.persistedSamples = result.value!.samples;
      context.visibleSamples = result.value!.samples;
      context.visibleSummaries = result.value!.summaries;
      context.visibleEvents = result.value!.events;
      // The sampled history is intentionally sparse (and an OI-only flush can
      // save no new history row). The event reducer's restart baseline is the
      // accepted sample latched with every evaluation, so prefer that durable
      // cursor over the downsampled currentSample field.
      context.latestAcceptedSample =
          result.value!.latches.lastSample ?? result.value!.currentSample;
      context.lastHistoryPersistAt = result.value!.samples.isEmpty
          ? null
          : result.value!.samples.last.observedAt;
      context.lastOiPersistAt = result.value!.openInterest.isEmpty
          ? null
          : result.value!.openInterest.last.timestamp;
      context.plan = result.value!.plan;
      final loadedAt = _now();
      final savedBaseline = result.value!.lastCheckBaseline;
      context.session = RiskCheckSession.start(
        episodeKey: context.episodeKey,
        now: loadedAt,
        savedBaseline: savedBaseline,
        awayDuration: savedBaseline == null
            ? _awayDuration(loadedAt)
            : _awayDurationFromBaseline(loadedAt, savedBaseline),
      );
    } else if (result.isMissing) {
      context.record = _newRecord(context.accountHash, context.episodeKey);
      context.persistedSamples = const <RiskHistorySample>[];
      context.latestAcceptedSample = null;
      context.lastHistoryPersistAt = null;
      context.lastOiPersistAt = null;
      context.plan = context.record!.plan;
      context.session = RiskCheckSession.start(
        episodeKey: context.episodeKey,
        now: _now(),
        awayDuration: _awayDuration(_now()),
      );
    } else if (result.isReadOnly) {
      context.unsaved = true;
      context.lastError = 'Local risk data is read-only; reset is required';
      _publishAggregate();
    }
  }

  Future<void> _loadSettings(int generation) async {
    final account = _accountHash;
    if (account == null) return;
    final result = await persistence.loadSettings(account);
    if (!_isCurrent(generation)) return;
    if (result.isSuccess && result.value != null) {
      _settings = result.value!;
    } else if (result.isMissing) {
      _settings = const RiskSettings();
    } else if (result.isReadOnly) {
      _aggregateError = 'Risk settings are read-only; reset is required';
      _aggregateQuality = const RiskQuality.error(
        reason: 'Risk settings are read-only; reset is required',
      );
      _publishAggregate(unsaved: true);
    }
  }

  Future<void> _persistDepartureBaseline(
    _RiskEpisodeMonitorContext context,
    int generation,
  ) async {
    final record = _recordWithPendingOpenInterest(context);
    final baseline = context.session?.departure();
    if (record == null || baseline == null) return;
    if (!_isGenerationCurrent(generation)) return;
    final saved = await persistence.saveEpisode(
      accountHash: context.accountHash,
      record: record.copyWith(lastCheckBaseline: baseline),
    );
    if (_isGenerationCurrent(generation) && saved.isSuccess) {
      context.record =
          saved.value ?? record.copyWith(lastCheckBaseline: baseline);
      context.pendingRecord = null;
      context.pendingOpenInterest = const <MarketOpenInterestSample>[];
      context.unsaved = false;
    } else if (_isGenerationCurrent(generation)) {
      context.unsaved = true;
      context.lastError = 'UI departure baseline was not saved';
    }
  }

  Future<void> _persistAllDepartureBaselines(int generation) async {
    for (final context in _contexts.values.toList(growable: false)) {
      await _persistDepartureBaseline(context, generation);
    }
  }

  Future<void> _flushOpenInterest(
    _RiskEpisodeMonitorContext context,
    int generation,
  ) async {
    final record = _recordWithPendingOpenInterest(context);
    if (record == null ||
        (context.pendingOpenInterest.isEmpty &&
            context.pendingRecord == null) ||
        !_isGenerationCurrent(generation)) {
      return;
    }
    final next = record;
    if (!_isGenerationCurrent(generation)) return;
    final saved = await persistence.saveEpisode(
      accountHash: context.accountHash,
      record: next,
    );
    if (!_isGenerationCurrent(generation)) return;
    if (saved.isSuccess) {
      context.record = saved.value ?? next;
      context.pendingRecord = null;
      context.pendingOpenInterest = const <MarketOpenInterestSample>[];
      context.lastOiPersistAt = _now();
      context.unsaved = false;
    } else {
      context.unsaved = true;
      context.lastError = 'Open-interest history was not saved';
    }
  }

  Future<void> _flushAllOpenInterest(int generation) async {
    for (final context in _contexts.values.toList(growable: false)) {
      await _flushOpenInterest(context, generation);
    }
  }

  RiskEpisodeRecord? _recordWithPendingOpenInterest(
    _RiskEpisodeMonitorContext context,
  ) {
    final record = context.pendingRecord ?? context.record;
    final pending = context.pendingOpenInterest;
    if (record == null || pending.isEmpty) return record;
    final merged = <String, MarketOpenInterestSample>{};
    String key(MarketOpenInterestSample sample) =>
        '${sample.instrument.toUpperCase()}|'
        '${sample.timestamp.toUtc().toIso8601String()}';
    for (final sample in record.openInterest) {
      merged[key(sample)] = sample;
    }
    for (final sample in pending) {
      merged[key(sample)] = sample;
    }
    final ordered = merged.values.toList()
      ..sort((left, right) => left.timestamp.compareTo(right.timestamp));
    final bounded = ordered.length <= 1500
        ? ordered
        : ordered.sublist(ordered.length - 1500);
    return record.copyWith(
      openInterest: List<MarketOpenInterestSample>.unmodifiable(bounded),
    );
  }

  RiskEpisodeRecord _newRecord(
    String account,
    String episode, {
    RiskPlan? plan,
  }) => RiskEpisodeRecord(
    accountHash: account,
    episodeKey: episode,
    plan: plan ?? RiskPlan(episodeKey: episode),
    updatedAt: _now(),
  );

  RiskLocalTimeZone _timeZone(String name, DateTime at) {
    // RiskLocalTimeZone is intentionally offset-based. Resolve the configured
    // supported IANA offset without storing any account data in the setting.
    try {
      final normalized = AppTimeZone.normalizeId(name);
      final local = AppTimeZone.now(normalized, instant: at);
      return RiskLocalTimeZone(name: normalized, offset: local.timeZoneOffset);
    } catch (_) {
      return RiskLocalTimeZone(name: AppTimeZone.normalizeId(name));
    }
  }

  MarketRiskSnapshot _mergeMarketSnapshot(
    _RiskEpisodeMonitorContext context,
    MarketRiskSnapshot current, {
    required bool includeCandles,
  }) {
    final previous = context.marketSnapshot;
    final keepCandles = previous != null && !includeCandles;
    final merged = <String, MarketOpenInterestSample>{};
    for (final item in <MarketOpenInterestSample>[
      ...?context.record?.openInterest,
      ...?previous?.openInterest,
      ...current.openInterest,
    ]) {
      final key =
          '${item.instrument.toUpperCase()}|${item.timestamp.toUtc().toIso8601String()}';
      merged[key] = item;
    }
    final history = merged.values.toList()
      ..sort((left, right) => left.timestamp.compareTo(right.timestamp));
    final bounded = history.length <= 1500
        ? history
        : history.sublist(history.length - 1500);
    context.pendingOpenInterest = List<MarketOpenInterestSample>.unmodifiable(
      bounded,
    );
    return MarketRiskSnapshot(
      asset: current.asset,
      assetOneHour: keepCandles
          ? previous.assetOneHour
          : _mergeCandleSeries(previous?.assetOneHour, current.assetOneHour),
      assetFourHour: keepCandles
          ? previous.assetFourHour
          : _mergeCandleSeries(previous?.assetFourHour, current.assetFourHour),
      btcOneHour: keepCandles
          ? previous.btcOneHour
          : _mergeCandleSeries(previous?.btcOneHour, current.btcOneHour),
      btcFourHour: keepCandles
          ? previous.btcFourHour
          : _mergeCandleSeries(previous?.btcFourHour, current.btcFourHour),
      funding: current.funding ?? previous?.funding,
      openInterest: context.pendingOpenInterest,
      fundingQuality: current.fundingQuality ?? previous?.fundingQuality,
      openInterestQuality:
          current.openInterestQuality ?? previous?.openInterestQuality,
      observedAt: current.observedAt ?? previous?.observedAt ?? _now(),
    );
  }

  MarketCandleSeries _mergeCandleSeries(
    MarketCandleSeries? previous,
    MarketCandleSeries current,
  ) {
    if (previous == null ||
        previous.instrument.toUpperCase() != current.instrument.toUpperCase() ||
        previous.interval.toUpperCase() != current.interval.toUpperCase()) {
      return current;
    }
    final currentIsComplete =
        current.complete &&
        _candleSeriesIsContiguous(current.candles, current.interval);
    if (currentIsComplete) {
      // A complete refresh is authoritative.  Merging two independently
      // sampled complete windows can interleave their timestamps (for
      // example, 13:59, 14:00, 14:59, 15:00) and make an otherwise valid
      // candle window look discontinuous to the market engine.
      final bounded = current.candles.length <= 300
          ? current.candles
          : current.candles.sublist(current.candles.length - 300);
      return MarketCandleSeries(
        instrument: current.instrument,
        interval: current.interval,
        candles: List<MarketCandle>.unmodifiable(bounded),
        source: current.source,
        complete: true,
      );
    }
    final byTimestamp = <DateTime, MarketCandle>{
      for (final candle in previous.candles) candle.timestamp.toUtc(): candle,
      for (final candle in current.candles) candle.timestamp.toUtc(): candle,
    };
    final candles = byTimestamp.values.toList()
      ..sort((left, right) => left.timestamp.compareTo(right.timestamp));
    final bounded = candles.length <= 300
        ? candles
        : candles.sublist(candles.length - 300);
    // A complete refresh is authoritative for the current candle window and
    // can recover after a prior partial/failed refresh. Validate the fetched
    // series itself; an earlier partial snapshot must not permanently poison
    // later five-minute candle refreshes.
    final complete =
        current.complete &&
        _candleSeriesIsContiguous(current.candles, current.interval);
    return MarketCandleSeries(
      instrument: current.instrument,
      interval: current.interval,
      candles: List<MarketCandle>.unmodifiable(bounded),
      source: current.source,
      complete: complete,
      missingReason: complete
          ? null
          : current.missingReason ??
                'Candle history is partial across refresh boundaries',
    );
  }

  bool _candleSeriesIsContiguous(List<MarketCandle> candles, String interval) {
    final step = interval.toUpperCase() == '1H'
        ? const Duration(hours: 1)
        : const Duration(hours: 4);
    for (var index = 1; index < candles.length; index++) {
      if (candles[index].timestamp.difference(candles[index - 1].timestamp) !=
          step) {
        return false;
      }
    }
    return true;
  }

  Duration _awayDuration(DateTime now) {
    final last = _lastStoppedAt;
    if (last == null) return const Duration(seconds: 60);
    final result = now.difference(last);
    return result.isNegative ? Duration.zero : result;
  }

  Duration _awayDurationFromBaseline(DateTime now, RiskHistorySample baseline) {
    final stopped = _lastStoppedAt;
    if (stopped != null) return _awayDuration(now);
    final result = now.difference(baseline.observedAt);
    return result.isNegative ? Duration.zero : result;
  }

  List<RiskHistorySample> _appendFreshSample(
    List<RiskHistorySample> existing,
    RiskHistorySample sample,
  ) {
    if (existing.isNotEmpty &&
        !sample.observedAt.isAfter(existing.last.observedAt)) {
      return List<RiskHistorySample>.unmodifiable(existing);
    }
    return List<RiskHistorySample>.unmodifiable(<RiskHistorySample>[
      ...existing,
      sample,
    ]);
  }

  List<RiskHistorySample> _mergeHistorySamples(
    List<RiskHistorySample> persisted,
    List<RiskHistorySample> candidate,
  ) {
    final merged = <String, RiskHistorySample>{};
    String key(RiskHistorySample sample) =>
        '${sample.episodeKey}|${sample.observedAt.toUtc().toIso8601String()}';
    for (final sample in persisted) {
      merged[key(sample)] = sample;
    }
    for (final sample in candidate) {
      merged[key(sample)] = sample;
    }
    final ordered = merged.values.toList()
      ..sort((left, right) => left.observedAt.compareTo(right.observedAt));
    return List<RiskHistorySample>.unmodifiable(ordered);
  }

  bool _isCurrent(int generation) =>
      !_disposed && _running && generation == _generation;

  bool _isGenerationCurrent(int generation) =>
      !_disposed && generation == _generation;

  DateTime _now() => clock().toUtc();

  String? _normalize(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  void _registerFailure(bool auth, {Duration? retryAfter}) {
    if (auth) {
      _authBlocked = true;
      _nextRetryAt = null;
      return;
    }
    _failureCount = (_failureCount + 1).clamp(1, 4);
    const delays = <Duration>[
      Duration(seconds: 30),
      Duration(minutes: 1),
      Duration(minutes: 2),
      Duration(minutes: 5),
    ];
    final bounded = delays[_failureCount - 1];
    final requested = retryAfter;
    final delay = requested != null && requested > bounded
        ? requested
        : bounded;
    _nextRetryAt = _now().add(delay);
  }

  void _clearFailure() {
    _failureCount = 0;
    _nextRetryAt = null;
    _authBlocked = false;
    _requestEndpointClass = null;
  }

  _RiskEpisodeMonitorContext? _contextForCommand(RiskMonitorCommand command) {
    final requested = _normalize(command.episodeKey);
    if (requested != null) return _contexts[requested];
    final primaryEpisode = _normalize(_episodeKey);
    if (primaryEpisode != null) return _contexts[primaryEpisode];
    final ordered = _orderedContexts();
    return ordered.isEmpty ? null : ordered.first;
  }

  List<_RiskEpisodeMonitorContext> _orderedContexts() {
    final values = _contexts.values.toList(growable: false)
      ..sort(_contextComparator);
    return values;
  }

  int _contextComparator(
    _RiskEpisodeMonitorContext left,
    _RiskEpisodeMonitorContext right,
  ) {
    final byInstrument = left.position.instrumentId.compareTo(
      right.position.instrumentId,
    );
    if (byInstrument != 0) return byInstrument;
    final byPosition = (left.position.positionId ?? '').compareTo(
      right.position.positionId ?? '',
    );
    if (byPosition != 0) return byPosition;
    return (left.position.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
        .compareTo(
          right.position.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        );
  }

  RiskMonitorRequestStatus _deriveRequestStatus() {
    if (_authBlocked) return RiskMonitorRequestStatus.authBlocked;
    final retryAt = _nextRetryAt;
    if (retryAt != null && _now().isBefore(retryAt)) {
      return RiskMonitorRequestStatus.backingOff;
    }
    if (_captureInFlight) return RiskMonitorRequestStatus.refreshing;
    if (_contexts.values.any(
      (context) =>
          context.lastError != null ||
          context.quality.status == RiskQualityStatus.error ||
          context.quality.status == RiskQualityStatus.stale ||
          context.quality.status == RiskQualityStatus.partial,
    )) {
      return RiskMonitorRequestStatus.partial;
    }
    if (_contexts.isEmpty &&
        (_aggregateQuality.status == RiskQualityStatus.error ||
            _aggregateQuality.status == RiskQualityStatus.unavailable)) {
      return RiskMonitorRequestStatus.unavailable;
    }
    return RiskMonitorRequestStatus.ready;
  }

  /// Rebuild the immutable root state from the episode map. Singular fields
  /// deliberately project the selected/first row so the current dashboard can
  /// stay buildable while later UI work consumes [RiskMonitorViewState.positions].
  void _publishAggregate({bool? isRunning, bool? unsaved}) {
    final ordered = _orderedContexts();
    _requestStatus = _deriveRequestStatus();
    final primary = _contextForCommand(
      RiskMonitorCommand.start(id: 'aggregate-primary'),
    );
    final selected = primary ?? (ordered.isEmpty ? null : ordered.first);
    final status = _requestStatus;
    _publish(
      RiskMonitorViewState(
        isRunning: isRunning ?? _running,
        backgroundAvailable: _state.backgroundAvailable,
        ownerLabel: _state.ownerLabel,
        accountHash: _accountHash ?? selected?.accountHash,
        episodeKey: selected?.episodeKey ?? _episodeKey,
        evaluation: selected?.evaluation,
        planEvaluation: selected?.planEvaluation,
        plan: selected?.plan,
        settings: _settings,
        market: selected?.market,
        samples: selected?.visibleSamples,
        summaries: selected?.visibleSummaries,
        previousCheck: selected?.previousCheck,
        trend: selected?.trend,
        velocity: selected?.velocity,
        events: selected?.visibleEvents ?? const <RiskEvent>[],
        quality: selected?.quality ?? _aggregateQuality,
        unsaved: unsaved ?? selected?.unsaved ?? false,
        lastError: selected?.lastError ?? _aggregateError,
        notificationCapability: _notificationCapability,
        positions: ordered
            .map((context) => context.toViewState(_settings))
            .toList(growable: false),
        requestStatus: status,
        retryAt: _nextRetryAt,
        requestEndpointClass: _requestEndpointClass,
      ),
    );
  }

  void _resetPublishedIdentity() {
    _publishAggregate();
  }

  void _restartTimer() {
    _cancelTimer();
    if (!_running || _disposed) return;
    _timer = Timer.periodic(activeCadence, (_) {
      if (!_running ||
          _captureInFlight ||
          _captureFuture != null ||
          _timerCaptureQueued) {
        return;
      }
      _timerCaptureQueued = true;
      unawaited(
        _enqueueWork(() async {
          try {
            await _requestCapture(force: false);
          } finally {
            _timerCaptureQueued = false;
          }
        }),
      );
    });
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _publish(RiskMonitorViewState state) {
    if (_disposed) return;
    _state = state;
    if (!_states.isClosed) _states.add(_state);
  }

  RiskMonitorCommandResult _accepted(
    RiskMonitorCommand command,
    String message,
  ) => RiskMonitorCommandResult(
    commandId: command.id,
    status: RiskMonitorCommandStatus.accepted,
    state: _state,
    message: message,
  );

  RiskMonitorCommandResult _rejected(
    RiskMonitorCommand command,
    String message,
  ) => RiskMonitorCommandResult(
    commandId: command.id,
    status: RiskMonitorCommandStatus.rejected,
    state: _state,
    message: message,
  );

  RiskMonitorCommandResult _failed(
    RiskMonitorCommand command,
    String message,
  ) => RiskMonitorCommandResult(
    commandId: command.id,
    status: RiskMonitorCommandStatus.failed,
    state: _state,
    message: message,
  );

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    final completer = Completer<void>();
    _workTail = _workTail.then<void>((_) async {
      try {
        await _disposeInternal();
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _disposeInternal() async {
    if (_disposed) return;
    _generation++;
    _cancelTimer();
    final generation = _generation;
    final wasRunning = _running;
    _running = false;
    if (wasRunning) {
      await _flushAllOpenInterest(generation);
      await _persistAllDepartureBaselines(generation);
    }
    _disposed = true;
    await _states.close();
  }
}
