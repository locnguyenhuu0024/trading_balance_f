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

  RiskMonitorViewState _state = RiskMonitorViewState();
  RiskEpisodeRecord? _record;
  RiskSettings _settings = const RiskSettings();
  RiskPlan? _plan;
  RiskMarketInput? _market;
  DateTime? _marketFetchedAt;
  MarketRiskSnapshot? _marketSnapshot;
  DateTime? _candleSnapshotFetchedAt;
  RiskPositionSelection? _positionSelection;
  DateTime? _positionFetchedAt;
  DateTime? _lastOiPersistAt;
  DateTime? _lastHistoryPersistAt;
  List<RiskHistorySample> _persistedSamples = const <RiskHistorySample>[];
  RiskHistorySample? _latestAcceptedSample;
  RiskPlanEvaluation? _previousPlanEvaluation;
  List<MarketOpenInterestSample> _pendingOpenInterest =
      const <MarketOpenInterestSample>[];
  RiskCheckSession? _session;
  DateTime? _lastStoppedAt;
  DateTime? _uiDepartureAt;
  RiskHistorySample? _uiDepartureBaseline;
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
    _publish(
      _state.copyWith(
        ownerLabel: ownerLabel,
        backgroundAvailable: backgroundAvailable,
        lastError: error,
        clearError: error == null,
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
    _publish(_state.copyWith(notificationCapability: _notificationCapability));
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
    _record = null;
    _session = null;
    _uiDepartureAt = null;
    _uiDepartureBaseline = null;
    _market = null;
    _marketFetchedAt = null;
    _marketSnapshot = null;
    _candleSnapshotFetchedAt = null;
    _positionSelection = null;
    _positionFetchedAt = null;
    _lastOiPersistAt = null;
    _lastHistoryPersistAt = null;
    _persistedSamples = const <RiskHistorySample>[];
    _latestAcceptedSample = null;
    _previousPlanEvaluation = null;
    _pendingOpenInterest = const <MarketOpenInterestSample>[];
    _deliveredEventIds.clear();
    _accountHash = null;
    _episodeKey = null;
    _plan = null;
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
    _workTail = _workTail.then<void>((_) async {
      try {
        completer.complete(await _dispatchInternal(command));
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
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
      _record = null;
      _plan = requestedEpisode == null
          ? null
          : RiskPlan(episodeKey: requestedEpisode);
      _settings = const RiskSettings();
      _market = null;
      _marketFetchedAt = null;
      _marketSnapshot = null;
      _candleSnapshotFetchedAt = null;
      _positionSelection = null;
      _positionFetchedAt = null;
      _lastOiPersistAt = null;
      _lastHistoryPersistAt = null;
      _persistedSamples = const <RiskHistorySample>[];
      _latestAcceptedSample = null;
      _previousPlanEvaluation = null;
      _pendingOpenInterest = const <MarketOpenInterestSample>[];
      _session = null;
      _uiDepartureAt = null;
      _uiDepartureBaseline = null;
      _reconnectPending = false;
      _deliveredEventIds.clear();
      _resetPublishedIdentity();
      if (_accountHash != null && _episodeKey != null) {
        await _loadContext(_generation);
      } else if (_accountHash != null) {
        await _loadSettings(_generation);
      }
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
    await _flushOpenInterest(_generation);
    await _persistDepartureBaseline(_generation);
    _lastStoppedAt = _now();
    _publish(_state.copyWith(isRunning: false));
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
    final account = _accountHash;
    final episode = _episodeKey;
    final record = _record;
    final baseline =
        _latestAcceptedSample ??
        record?.latches.lastSample ??
        record?.currentSample ??
        _session?.departure();
    _uiDepartureAt = _now();
    _uiDepartureBaseline = baseline;
    if (baseline == null ||
        account == null ||
        episode == null ||
        record == null) {
      return _accepted(command, 'UI departure recorded without a baseline');
    }
    final next = record.copyWith(lastCheckBaseline: baseline);
    final saved = await persistence.saveEpisode(
      accountHash: account,
      record: next,
    );
    if (!_isGenerationCurrent(generation)) {
      return _failed(command, 'UI departure was invalidated');
    }
    if (!saved.isSuccess) {
      _publish(_state.copyWith(unsaved: true));
      return _failed(command, 'UI departure baseline was not saved');
    }
    _record = saved.value ?? next;
    _publish(_state.copyWith(unsaved: false));
    return _accepted(command, 'UI departure baseline saved');
  }

  Future<RiskMonitorCommandResult> _uiResume(RiskMonitorCommand command) async {
    if (!_running) return _rejected(command, 'Monitor is not running');
    final now = _now();
    final departureAt = _uiDepartureAt;
    final baseline = _uiDepartureBaseline;
    final away = departureAt == null
        ? Duration.zero
        : now.difference(departureAt).isNegative
        ? Duration.zero
        : now.difference(departureAt);
    // Service polling continues during the UI departure. Freeze the visit
    // session while it is away, then seed a new comparison only after the
    // complete >60-second departure window has elapsed.
    if (departureAt != null &&
        baseline != null &&
        away > const Duration(seconds: 60)) {
      final episode = _episodeKey;
      if (episode != null) {
        _session = RiskCheckSession.start(
          episodeKey: episode,
          now: now,
          savedBaseline: baseline,
          awayDuration: away,
        );
      }
    }
    _uiDepartureAt = null;
    _uiDepartureBaseline = null;
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
    if (_episodeKey != null && plan.episodeKey != _episodeKey) {
      return _rejected(command, 'Plan episode does not match monitor');
    }
    _plan = plan;
    final account = _accountHash;
    if (account == null || _episodeKey == null) {
      _publish(_state.copyWith(plan: plan, unsaved: true));
      return _accepted(command, 'Plan updated locally; account is unresolved');
    }
    final existing = _record ?? _newRecord(account, plan.episodeKey);
    final next = existing.copyWith(plan: plan);
    final saved = await persistence.saveEpisode(
      accountHash: account,
      record: next,
    );
    if (!_isGenerationCurrent(generation)) {
      return _failed(command, 'Plan update was invalidated');
    }
    if (!saved.isSuccess) {
      _publish(_state.copyWith(plan: plan, unsaved: true));
      return _failed(command, 'Plan was not saved');
    }
    _record = saved.value ?? next;
    _publish(_state.copyWith(plan: plan, unsaved: false));
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
      _publish(_state.copyWith(settings: settings, unsaved: true));
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
      _publish(_state.copyWith(settings: settings, unsaved: true));
      return _failed(command, 'Settings were not saved');
    }
    _settings = settings;
    _publish(_state.copyWith(settings: settings, unsaved: false));
    return _accepted(command, 'Settings updated');
  }

  Future<RiskMonitorCommandResult> _clearHistory(
    RiskMonitorCommand command,
  ) async {
    final generation = _generation;
    final account = _accountHash;
    final episode = _episodeKey;
    if (account == null || episode == null) {
      return _rejected(command, 'Account and episode are required');
    }
    final result = await persistence.clearEpisodeHistory(
      accountHash: account,
      episodeKey: episode,
    );
    if (!_isGenerationCurrent(generation)) {
      return _failed(command, 'History clear was invalidated');
    }
    if (!result.isSuccess) return _failed(command, 'History was not cleared');
    _record =
        result.value ??
        _record?.copyWith(
          samples: const <RiskHistorySample>[],
          openInterest: const <MarketOpenInterestSample>[],
          events: const <RiskEvent>[],
          summaries: const <RiskDailySummary>[],
          latches: RiskEventLatch(episodeKey: episode),
          clearLastCheckBaseline: true,
        );
    // Clear every derived history cursor together with the durable history.
    // Otherwise a later OI flush or a sparse sample can reintroduce data that
    // the user just cleared.
    _persistedSamples = const <RiskHistorySample>[];
    _pendingOpenInterest = const <MarketOpenInterestSample>[];
    _lastHistoryPersistAt = null;
    _lastOiPersistAt = null;
    _previousPlanEvaluation = null;
    _deliveredEventIds.clear();
    _session = RiskCheckSession.start(
      episodeKey: episode,
      now: _now(),
      awayDuration: Duration.zero,
    );
    _uiDepartureAt = null;
    _uiDepartureBaseline = null;
    _latestAcceptedSample = null;
    _publish(
      _state.copyWith(
        events: const <RiskEvent>[],
        samples: const <RiskHistorySample>[],
        summaries: const <RiskDailySummary>[],
        clearPreviousCheck: true,
        clearTrend: true,
        clearVelocity: true,
        unsaved: false,
      ),
    );
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
    if (_nextRetryAt != null && _now().isBefore(_nextRetryAt!)) {
      return;
    }
    if (_authBlocked) return;
    _captureInFlight = true;
    final initialGeneration = _generation;
    try {
      final beforePosition = _now();
      final cachedSelection = _positionSelection;
      final positionFresh =
          cachedSelection != null &&
          _positionFetchedAt != null &&
          beforePosition.difference(_positionFetchedAt!) < activeCadence;
      final selection = positionFresh
          ? cachedSelection
          : await dataSource.loadPosition(
              selectedPositionId: _selectedPositionId,
              selectedEpisodeKey: _episodeKey,
            );
      if (!_isCurrent(initialGeneration)) return;
      if (!positionFresh) {
        _positionSelection = selection;
        _positionFetchedAt = _now();
      }
      // Selection failure metadata belongs to the fetch that produced the
      // selection. A cached position must not replay an old enrichment error
      // on every market-only capture and keep retry backoff alive forever.
      final selectionFailure =
          !positionFresh && dataSource is RiskMonitorSelectionFailureMetadata
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
      }
      final selectionFailureMessage = selectionFailure == null
          ? null
          : selectionFailureAuth
          ? 'Credentials were rejected during risk enrichment'
          : 'Risk enrichment request failed'
                '${selectionFailure.statusCode == null ? '' : ' (HTTP ${selectionFailure.statusCode})'}';
      final position = selection.position;
      if (position == null) {
        final failure = dataSource is RiskMonitorSelectionFailureMetadata
            ? (dataSource as RiskMonitorSelectionFailureMetadata)
                  .lastSelectionFailure
            : null;
        final credentialFailure =
            failure?.credentialFailure == true || failure?.statusCode == 401;
        if (failure == null) {
          _registerFailure(false);
        }
        _publish(
          _state.copyWith(
            isRunning: _running,
            quality: selection.quality,
            lastError: credentialFailure
                ? 'Credentials were rejected; monitoring is paused'
                : selection.message ?? 'Risk position is unavailable',
          ),
        );
        return;
      }
      final account = _normalize(position.accountNamespace);
      final episode = _normalize(position.episodeKey);
      if (account == null || episode == null) {
        _publish(
          _state.copyWith(
            quality: position.quality,
            lastError: 'Risk account or episode identity is unavailable',
          ),
        );
        return;
      }
      var generation = initialGeneration;
      if (account != _accountHash || episode != _episodeKey) {
        _generation++;
        generation = _generation;
        _accountHash = account;
        _episodeKey = episode;
        _record = null;
        _plan = RiskPlan(episodeKey: episode);
        _settings = const RiskSettings();
        _market = null;
        _marketFetchedAt = null;
        _marketSnapshot = null;
        _candleSnapshotFetchedAt = null;
        _lastOiPersistAt = null;
        _lastHistoryPersistAt = null;
        _persistedSamples = const <RiskHistorySample>[];
        _latestAcceptedSample = null;
        _previousPlanEvaluation = null;
        _pendingOpenInterest = const <MarketOpenInterestSample>[];
        _session = null;
        _deliveredEventIds.clear();
        _resetPublishedIdentity();
        await _loadContext(generation);
        if (!_isCurrent(generation)) return;
      }

      final now = _now();
      var market = _market;
      final marketIsFresh =
          market != null &&
          _marketFetchedAt != null &&
          now.difference(_marketFetchedAt!) < marketCadence;
      if (!marketIsFresh) {
        try {
          final includeCandles =
              _marketSnapshot == null ||
              _candleSnapshotFetchedAt == null ||
              now.difference(_candleSnapshotFetchedAt!) >= candleCadence;
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
            snapshot,
            includeCandles: dataSource is RiskMonitorMarketCadenceSource
                ? includeCandles
                : true,
          );
          _marketSnapshot = effectiveSnapshot;
          if (dataSource is! RiskMonitorMarketCadenceSource || includeCandles) {
            _candleSnapshotFetchedAt = now;
          }
          market = marketEngine
              .evaluate(
                effectiveSnapshot,
                isBtcPosition: position.baseCurrency?.toUpperCase() == 'BTC',
                now: now,
              )
              .input;
          _market = market;
          _marketFetchedAt = now;
        } catch (_) {
          _registerFailure(false);
          // Preserve the last published risk and expose a quality problem;
          // stale market factors must not create a new event.
          _publish(
            _state.copyWith(
              quality: const RiskQuality.stale(
                reason: 'Market source is unavailable',
              ),
              lastError: 'Market source is unavailable',
            ),
          );
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
      final plan = _plan ?? RiskPlan(episodeKey: episode);
      final planEvaluation = actionPlanEvaluator.evaluatePlan(
        plan,
        evaluation,
        at: now,
      );
      final sample = RiskHistorySample.fromEvaluation(
        episodeKey: episode,
        evaluation: evaluation,
        market: market,
      );
      final currentRecord = _record ?? _newRecord(account, episode, plan: plan);
      final priorSample = _latestAcceptedSample ?? currentRecord.currentSample;
      final reduction = eventReducer.reduce(
        priorSample,
        sample,
        currentRecord.latches,
        _settings.policy,
        previousPlan: _previousPlanEvaluation,
        currentPlan: planEvaluation,
        now: now,
        reconnected:
            _reconnectPending &&
            priorSample != null &&
            now.difference(priorSample.observedAt) > const Duration(minutes: 5),
      );
      _reconnectPending = false;
      _previousPlanEvaluation = planEvaluation;

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
      final lastHistoryAt = _lastHistoryPersistAt;
      final historyDue =
          _persistedSamples.isEmpty ||
          lastHistoryAt == null ||
          now.difference(lastHistoryAt) >= historySampleCadence;
      final eventDue = reduction.events.isNotEmpty;
      final persistedSamples = historyDue || eventDue
          ? _appendFreshSample(_persistedSamples, sample)
          : _persistedSamples;
      final lastOiAt = _lastOiPersistAt;
      final oiDue =
          _pendingOpenInterest.isNotEmpty &&
          (currentRecord.openInterest.isEmpty ||
              lastOiAt == null ||
              now.difference(lastOiAt) >= oiPersistCadence);
      final persistedOpenInterest = oiDue
          ? _pendingOpenInterest
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
      );
      RiskStoreResult<RiskEpisodeRecord>? saved;
      final needsPersistence =
          historyDue || eventDue || oiDue || nextSummary != null;
      if (needsPersistence && account.isNotEmpty && episode.isNotEmpty) {
        saved = await persistence.saveEpisode(
          accountHash: account,
          record: nextRecord,
        );
        if (!_isCurrent(generation)) return;
        if (saved.isSuccess) {
          _record = saved.value ?? nextRecord;
          _persistedSamples =
              saved.value?.samples ??
              List<RiskHistorySample>.unmodifiable(persistedSamples);
          if (historyDue || eventDue) _lastHistoryPersistAt = now;
          if (oiDue) _lastOiPersistAt = now;
          if (selectionFailure == null) _clearFailure();
        }
      } else {
        // Keep the in-memory record aligned with the durable cadence. The
        // latest accepted observation is carried separately for event
        // comparison and the UI receives it through visibleSamples below;
        // appending it to _record here would make an OI-only flush look like
        // a persisted history sample after a restart.
        _record = nextRecord;
      }

      // Event comparison follows every accepted evaluation, even when the
      // durable history cadence or OI flush intentionally skips this sample.
      _latestAcceptedSample = sample;

      final persisted =
          !needsPersistence || saved?.notificationDeliveryAllowed == true;
      final visibleRecord = saved?.value ?? nextRecord;
      final visibleSamples = _appendFreshSample(visibleRecord.samples, sample);
      if (_uiDepartureAt == null) {
        _session =
            (_session ??
                    RiskCheckSession.start(
                      episodeKey: episode,
                      now: now,
                      savedBaseline: currentRecord.lastCheckBaseline,
                      awayDuration: _awayDuration(now),
                    ))
                .observe(sample);
      }
      final trend = RiskHistoryAnalytics.trend(
        current: sample,
        history: visibleSamples,
        now: now,
      );
      final velocity = RiskHistoryAnalytics.velocity(
        current: sample,
        history: visibleSamples,
        now: now,
      );
      _publish(
        _state.copyWith(
          isRunning: true,
          accountHash: account,
          episodeKey: episode,
          evaluation: evaluation,
          planEvaluation: planEvaluation,
          plan: plan,
          settings: _settings,
          market: market,
          samples: visibleSamples,
          summaries: visibleRecord.summaries,
          previousCheck: _session?.comparison,
          trend: trend,
          velocity: velocity,
          events: visibleRecord.events,
          quality: evaluation.quality,
          unsaved: !persisted,
          lastError: selectionFailureMessage,
          clearError: persisted && selectionFailureMessage == null,
        ),
      );
      if (persisted && reduction.events.isNotEmpty) {
        await _deliver(reduction.events, generation);
      }
    } on RiskRepositoryException catch (error) {
      if (!_isCurrent(initialGeneration)) return;
      _registerFailure(
        error.credentialFailure || error.statusCode == 401,
        retryAfter: error.retryAfter,
      );
      _publish(
        _state.copyWith(
          quality: RiskQuality.error(
            source: error.endpoint,
            reason: 'Risk source request failed',
          ),
          lastError: error.credentialFailure || error.statusCode == 401
              ? 'Credentials were rejected; monitoring is paused'
              : 'Risk source is unavailable',
        ),
      );
    } catch (_) {
      if (!_isCurrent(initialGeneration)) return;
      _registerFailure(false);
      _publish(
        _state.copyWith(
          quality: const RiskQuality.error(
            reason: 'Risk monitor capture failed',
          ),
          lastError: 'Risk monitor capture failed',
        ),
      );
    } finally {
      _captureInFlight = false;
    }
  }

  Future<void> _deliver(List<RiskEvent> events, int generation) async {
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
    _publish(_state.copyWith(notificationCapability: _notificationCapability));
    if (!capability.canDeliver) return;
    for (final event in events) {
      if (!_isCurrent(generation) || !_deliveredEventIds.add(event.id)) {
        continue;
      }
      final notification = RiskNotification.fromEvent(event);
      if (!notification.isPrivacySafe) {
        _deliveredEventIds.remove(event.id);
        continue;
      }
      try {
        final result = await notificationSink.deliver(notification);
        if (!result.delivered) _deliveredEventIds.remove(event.id);
      } catch (_) {
        _deliveredEventIds.remove(event.id);
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
    _publish(_state.copyWith(notificationCapability: _notificationCapability));
  }

  Future<void> _loadContext(int generation) async {
    final account = _accountHash;
    final episode = _episodeKey;
    if (account == null) return;
    await _loadSettings(generation);
    if (!_isCurrent(generation) || episode == null) return;
    final result = await persistence.loadEpisode(
      accountHash: account,
      episodeKey: episode,
    );
    if (!_isCurrent(generation)) return;
    if (result.isSuccess && result.value != null) {
      _record = result.value;
      _persistedSamples = result.value!.samples;
      // The sampled history is intentionally sparse (and an OI-only flush can
      // save no new history row). The event reducer's restart baseline is the
      // accepted sample latched with every evaluation, so prefer that durable
      // cursor over the downsampled currentSample field.
      _latestAcceptedSample =
          result.value!.latches.lastSample ?? result.value!.currentSample;
      _lastHistoryPersistAt = result.value!.samples.isEmpty
          ? null
          : result.value!.samples.last.observedAt;
      _lastOiPersistAt = result.value!.openInterest.isEmpty
          ? null
          : result.value!.openInterest.last.timestamp;
      _plan = result.value!.plan;
      final loadedAt = _now();
      final savedBaseline = result.value!.lastCheckBaseline;
      _session = RiskCheckSession.start(
        episodeKey: episode,
        now: loadedAt,
        savedBaseline: savedBaseline,
        awayDuration: savedBaseline == null
            ? _awayDuration(loadedAt)
            : _awayDurationFromBaseline(loadedAt, savedBaseline),
      );
    } else if (result.isMissing) {
      _record = _newRecord(account, episode);
      _persistedSamples = const <RiskHistorySample>[];
      _latestAcceptedSample = null;
      _lastHistoryPersistAt = null;
      _lastOiPersistAt = null;
      _plan = _record!.plan;
      _session = RiskCheckSession.start(
        episodeKey: episode,
        now: _now(),
        awayDuration: _awayDuration(_now()),
      );
    } else if (result.isReadOnly) {
      _publish(
        _state.copyWith(
          unsaved: true,
          lastError: 'Local risk data is read-only; reset is required',
        ),
      );
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
      _publish(
        _state.copyWith(
          unsaved: true,
          lastError: 'Risk settings are read-only; reset is required',
        ),
      );
    }
  }

  Future<void> _persistDepartureBaseline(int generation) async {
    final account = _accountHash;
    final episode = _episodeKey;
    final record = _record;
    final baseline = _session?.departure();
    if (account == null ||
        episode == null ||
        record == null ||
        baseline == null) {
      return;
    }
    if (!_isGenerationCurrent(generation)) return;
    final saved = await persistence.saveEpisode(
      accountHash: account,
      record: record.copyWith(lastCheckBaseline: baseline),
    );
    if (_isGenerationCurrent(generation) && saved.isSuccess) {
      _record = saved.value ?? record.copyWith(lastCheckBaseline: baseline);
    }
  }

  Future<void> _flushOpenInterest(int generation) async {
    final account = _accountHash;
    final episode = _episodeKey;
    final record = _record;
    if (account == null || episode == null || record == null) return;
    if (_pendingOpenInterest.isEmpty || !_isGenerationCurrent(generation)) {
      return;
    }
    final next = record.copyWith(openInterest: _pendingOpenInterest);
    if (!_isGenerationCurrent(generation)) return;
    final saved = await persistence.saveEpisode(
      accountHash: account,
      record: next,
    );
    if (!_isGenerationCurrent(generation)) return;
    if (saved.isSuccess) {
      _record = saved.value ?? next;
      _lastOiPersistAt = _now();
    }
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
    MarketRiskSnapshot current, {
    required bool includeCandles,
  }) {
    final previous = _marketSnapshot;
    final keepCandles = previous != null && !includeCandles;
    final merged = <String, MarketOpenInterestSample>{};
    for (final item in <MarketOpenInterestSample>[
      ...?_record?.openInterest,
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
    _pendingOpenInterest = List<MarketOpenInterestSample>.unmodifiable(bounded);
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
      openInterest: _pendingOpenInterest,
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
  }

  void _resetPublishedIdentity() {
    _publish(
      RiskMonitorViewState(
        isRunning: _running,
        backgroundAvailable: _state.backgroundAvailable,
        ownerLabel: _state.ownerLabel,
        accountHash: _accountHash,
        episodeKey: _episodeKey,
        plan: _plan,
        settings: _settings,
        notificationCapability: _notificationCapability,
        quality: const RiskQuality.unavailable(
          reason: 'Monitor has not observed a snapshot',
        ),
      ),
    );
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
      await _flushOpenInterest(generation);
      await _persistDepartureBaseline(generation);
    }
    _disposed = true;
    await _states.close();
  }
}
