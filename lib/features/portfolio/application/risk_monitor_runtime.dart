import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import '../../../core/services/background_service.dart';
import '../domain/risk/risk_models.dart';
import 'risk_monitor.dart';
import 'risk_monitor_bridge.dart';

enum RiskRuntimePlatformKind { android, ios, web, desktop }

typedef RiskRuntimeClock = DateTime Function();

class RiskRuntimeOwnership {
  const RiskRuntimeOwnership({
    required this.granted,
    required this.ownerLabel,
    this.backgroundAvailable = false,
    this.reason,
    this.owner,
  });

  const RiskRuntimeOwnership.foreground({
    this.ownerLabel = 'foreground',
    this.backgroundAvailable = false,
    this.owner,
  }) : granted = true,
       reason = null;

  const RiskRuntimeOwnership.unavailable({
    this.ownerLabel = 'android-service',
    this.reason = 'Background monitoring unavailable',
  }) : granted = false,
       backgroundAvailable = false,
       owner = null;

  final bool granted;
  final String ownerLabel;
  final bool backgroundAvailable;
  final String? reason;
  final RiskMonitorOwner? owner;
}

abstract class RiskRuntimePlatformAdapter {
  RiskRuntimePlatformKind get kind;

  Future<RiskRuntimeOwnership> acquireOwnership();

  Future<void> releaseOwnership();

  Stream<void> get reconnects;
}

abstract interface class RiskRuntimeServiceHealth {
  Future<bool> confirmServiceStopped();
}

abstract interface class RiskRuntimePlatformDisposable {
  Future<void> dispose();
}

/// Default non-native seam. Production Android uses
/// [FlutterBackgroundRiskRuntimeAdapter]; tests and unsupported hosts can use
/// this deterministic ownership result without touching plugins.
class DefaultRiskRuntimePlatformAdapter
    implements RiskRuntimePlatformAdapter, RiskRuntimeServiceHealth {
  const DefaultRiskRuntimePlatformAdapter({
    this.androidServiceConfigured = false,
  });

  final bool androidServiceConfigured;

  @override
  RiskRuntimePlatformKind get kind {
    if (kIsWeb) return RiskRuntimePlatformKind.web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return RiskRuntimePlatformKind.android;
      case TargetPlatform.iOS:
        return RiskRuntimePlatformKind.ios;
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return RiskRuntimePlatformKind.desktop;
    }
  }

  @override
  Future<RiskRuntimeOwnership> acquireOwnership() async {
    if (kind == RiskRuntimePlatformKind.web) {
      return const RiskRuntimeOwnership.foreground();
    }
    if (kind == RiskRuntimePlatformKind.android && !androidServiceConfigured) {
      return const RiskRuntimeOwnership.unavailable();
    }
    return const RiskRuntimeOwnership.foreground();
  }

  @override
  Future<void> releaseOwnership() async {}

  @override
  Stream<void> get reconnects => const Stream<void>.empty();

  @override
  Future<bool> confirmServiceStopped() async => true;
}

/// A typed UI-side proxy for the actual service-isolate RiskMonitor owner.
/// Every command is acknowledged by id; duplicate ids are answered from the
/// proxy cache without sending a second mutation to the service.
class RiskServiceOwnerProxy implements RiskMonitorOwner, RiskMonitorDisposable {
  RiskServiceOwnerProxy({
    required this.channel,
    this.onDisconnected,
    this.handshakeTimeout = const Duration(seconds: 5),
    Duration? livenessTimeout,
    Duration? silenceTimeout,
    this.commandCompletionTimeout = const Duration(seconds: 30),
    RiskRuntimeClock? clock,
  }) : livenessTimeout =
           livenessTimeout ?? silenceTimeout ?? const Duration(seconds: 15),
       _states = StreamController<RiskMonitorViewState>.broadcast() {
    _stateSubscription = channel
        .on(RiskMonitorWire.state)
        .listen(
          _onState,
          onDone: _markDisconnected,
          onError: (_, __) => _markDisconnected(),
        );
    _ackSubscription = channel
        .on(RiskMonitorWire.acknowledgement)
        .listen(
          _onAck,
          onDone: _markDisconnected,
          onError: (_, __) => _markDisconnected(),
        );
    _handshakeSubscription = channel
        .on(RiskMonitorWire.handshake)
        .listen(
          _onHandshake,
          onDone: _markDisconnected,
          onError: (_, __) => _markDisconnected(),
        );
    _heartbeatSubscription = channel
        .on(RiskMonitorWire.heartbeat)
        .listen(
          _onHeartbeat,
          onDone: _markDisconnected,
          onError: (_, __) => _markDisconnected(),
        );
    _clock = clock ?? DateTime.now;
    _lastActivityAt = _now();
    _silenceTimer = Timer.periodic(
      this.livenessTimeout,
      (_) => _checkSilence(),
    );
  }

  final RiskServiceChannel channel;
  final void Function()? onDisconnected;
  final Duration handshakeTimeout;
  final Duration livenessTimeout;
  final Duration commandCompletionTimeout;

  /// Backward-compatible name for callers that configured the old liveness
  /// setting. Command completion has its own deadline now.
  Duration get silenceTimeout => livenessTimeout;
  late final RiskRuntimeClock _clock;

  final StreamController<RiskMonitorViewState> _states;
  final Map<String, RiskMonitorCommandResult> _results =
      <String, RiskMonitorCommandResult>{};
  final Map<String, Completer<RiskMonitorCommandResult>> _pending =
      <String, Completer<RiskMonitorCommandResult>>{};
  StreamSubscription<Map<String, dynamic>?>? _stateSubscription;
  StreamSubscription<Map<String, dynamic>?>? _ackSubscription;
  StreamSubscription<Map<String, dynamic>?>? _handshakeSubscription;
  StreamSubscription<Map<String, dynamic>?>? _heartbeatSubscription;
  Completer<bool>? _handshake;
  Timer? _handshakeTimer;
  Timer? _silenceTimer;
  DateTime? _lastActivityAt;
  RiskMonitorViewState _state = RiskMonitorViewState(
    ownerLabel: 'android-service',
    backgroundAvailable: true,
  );
  bool _disposed = false;
  bool _disconnected = false;

  void _touchActivity() {
    _lastActivityAt = _now();
  }

  void _checkSilence() {
    if (_disposed || _disconnected) return;
    final last = _lastActivityAt;
    if (last == null || _now().difference(last) >= livenessTimeout) {
      _markDisconnected();
    }
  }

  DateTime _now() => _clock().toUtc();

  @override
  Stream<RiskMonitorViewState> get states => _states.stream;

  @override
  RiskMonitorViewState get currentState => _state;

  Future<bool> waitForHandshake() async {
    if (_disposed || _disconnected) return false;
    final existing = _handshake;
    if (existing != null) return existing.future;
    final completer = Completer<bool>();
    _handshake = completer;
    _touchActivity();
    try {
      channel.invoke(RiskMonitorWire.handshakeRequest, <String, dynamic>{
        'protocol': RiskMonitorWire.handshakeRequest,
      });
    } catch (_) {
      _markDisconnected();
      return false;
    }
    _handshakeTimer?.cancel();
    _handshakeTimer = Timer(handshakeTimeout, () {
      if (!completer.isCompleted) completer.complete(false);
      if (!completer.isCompleted || !_disconnected) _markDisconnected();
    });
    return completer.future;
  }

  void _onHandshake(Map<String, dynamic>? payload) {
    if (_disposed || _disconnected || payload == null) return;
    final protocol = payload['protocol']?.toString();
    if (protocol != null && protocol != RiskMonitorWire.handshake) {
      _markDisconnected();
      return;
    }
    _touchActivity();
    final ok = payload['backgroundAvailable'] == true;
    final error = payload['error']?.toString();
    _state = _state.copyWith(
      ownerLabel: payload['owner']?.toString() ?? 'android-service',
      backgroundAvailable: ok,
      lastError: error,
      clearError: error == null,
    );
    _publish(_state);
    final handshake = _handshake;
    if (handshake != null && !handshake.isCompleted) handshake.complete(ok);
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
  }

  void _onHeartbeat(Map<String, dynamic>? payload) {
    if (_disposed || _disconnected || payload == null) return;
    final protocol = payload['protocol']?.toString();
    if (protocol != null && protocol != RiskMonitorWire.heartbeat) {
      _markDisconnected();
      return;
    }
    _touchActivity();
  }

  void _onState(Map<String, dynamic>? payload) {
    if (_disposed || _disconnected || payload == null) return;
    _touchActivity();
    try {
      _state = RiskMonitorWire.decodeState(payload);
      _publish(_state);
    } catch (_) {
      _markDisconnected();
    }
  }

  void _onAck(Map<String, dynamic>? payload) {
    if (_disposed || _disconnected || payload == null) return;
    _touchActivity();
    try {
      final result = RiskMonitorWire.decodeAck(payload);
      _state = result.state;
      _publish(_state);
      final pending = _pending.remove(result.commandId);
      if (pending != null && !pending.isCompleted) pending.complete(result);
      _results[result.commandId] = result;
    } catch (_) {
      _markDisconnected();
    }
  }

  void _publish(RiskMonitorViewState value) {
    if (!_states.isClosed) _states.add(value);
  }

  void _markDisconnected() {
    if (_disposed || _disconnected) return;
    _disconnected = true;
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _silenceTimer?.cancel();
    _silenceTimer = null;
    final handshake = _handshake;
    if (handshake != null && !handshake.isCompleted) handshake.complete(false);
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.complete(_failed('Service disconnected'));
      }
    }
    _pending.clear();
    _state = _state.copyWith(
      isRunning: false,
      backgroundAvailable: false,
      quality: const RiskQuality.unavailable(
        reason: 'Android service disconnected',
      ),
      lastError: 'Android service disconnected',
    );
    _publish(_state);
    onDisconnected?.call();
  }

  @override
  Future<RiskMonitorCommandResult> dispatch(RiskMonitorCommand command) async {
    if (_disposed || _disconnected) {
      return _failed('Service unavailable', command);
    }
    final prior = _results[command.id];
    if (prior != null) {
      return RiskMonitorCommandResult(
        commandId: prior.commandId,
        status: prior.status,
        state: prior.state,
        message: prior.message,
        replayed: true,
      );
    }
    final inFlight = _pending[command.id];
    if (inFlight != null) return inFlight.future;
    final completer = Completer<RiskMonitorCommandResult>();
    _pending[command.id] = completer;
    try {
      channel.invoke(
        RiskMonitorWire.command,
        RiskMonitorWire.encodeCommand(command),
      );
    } catch (_) {
      _pending.remove(command.id);
      _markDisconnected();
      return _failed('Service channel unavailable', command);
    }
    return completer.future.timeout(
      commandCompletionTimeout,
      onTimeout: () {
        _pending.remove(command.id);
        _markDisconnected();
        return _failed('Service acknowledgement timed out', command);
      },
    );
  }

  RiskMonitorCommandResult _failed(
    String message, [
    RiskMonitorCommand? command,
  ]) => RiskMonitorCommandResult(
    commandId: command?.id ?? '',
    status: RiskMonitorCommandStatus.failed,
    state: _state,
    message: message,
  );

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _silenceTimer?.cancel();
    _silenceTimer = null;
    try {
      channel.invoke('stopService');
    } catch (_) {}
    await _stateSubscription?.cancel();
    await _ackSubscription?.cancel();
    await _handshakeSubscription?.cancel();
    await _heartbeatSubscription?.cancel();
    for (final pending in _pending.values) {
      if (!pending.isCompleted) pending.complete(_failed('Service disposed'));
    }
    _pending.clear();
    await _states.close();
  }
}

/// Production Android ownership adapter. It checks the service state, starts
/// it only when needed, waits for the typed handshake, and refuses foreground
/// fallback if the service cannot prove exclusive ownership.
class FlutterBackgroundRiskRuntimeAdapter
    implements
        RiskRuntimePlatformAdapter,
        RiskRuntimeServiceHealth,
        RiskRuntimePlatformDisposable {
  FlutterBackgroundRiskRuntimeAdapter({FlutterBackgroundService? service})
    : service = service ?? FlutterBackgroundService();

  final FlutterBackgroundService service;
  final StreamController<void> _reconnects = StreamController<void>.broadcast();
  RiskServiceOwnerProxy? _proxy;
  bool _released = false;

  @override
  RiskRuntimePlatformKind get kind {
    if (kIsWeb) return RiskRuntimePlatformKind.web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return RiskRuntimePlatformKind.android;
      case TargetPlatform.iOS:
        return RiskRuntimePlatformKind.ios;
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return RiskRuntimePlatformKind.desktop;
    }
  }

  @override
  Future<RiskRuntimeOwnership> acquireOwnership() async {
    if (kind != RiskRuntimePlatformKind.android) {
      return const RiskRuntimeOwnership.foreground();
    }
    try {
      _released = false;
      var running = await service.isRunning();
      if (!running) {
        final started = await service.startService();
        if (!started) {
          final stopped = await confirmServiceStopped();
          return RiskRuntimeOwnership.unavailable(
            reason: stopped
                ? 'Android service could not be started'
                : 'Android service ownership could not be confirmed',
          );
        }
        running = await service.isRunning();
      }
      if (!running) {
        final stopped = await confirmServiceStopped();
        return RiskRuntimeOwnership.unavailable(
          reason: stopped
              ? 'Android service did not become ready'
              : 'Android service ownership could not be confirmed',
        );
      }
      final proxy = RiskServiceOwnerProxy(
        channel: FlutterBackgroundServiceChannel(service),
        onDisconnected: () {
          if (!_released && !_reconnects.isClosed) _reconnects.add(null);
        },
      );
      _proxy = proxy;
      if (!await proxy.waitForHandshake()) {
        await proxy.dispose();
        final stopped = await confirmServiceStopped();
        if (!stopped) {
          return const RiskRuntimeOwnership.unavailable(
            reason: 'Android service ownership could not be confirmed',
          );
        }
        return const RiskRuntimeOwnership.unavailable(
          reason: 'Android service handshake unavailable',
        );
      }
      return RiskRuntimeOwnership(
        granted: true,
        ownerLabel: 'android-service',
        backgroundAvailable: true,
        owner: proxy,
      );
    } catch (_) {
      _proxy = null;
      return const RiskRuntimeOwnership.unavailable(
        reason: 'Android service platform is unavailable',
      );
    }
  }

  @override
  Future<void> releaseOwnership() async {
    if (_released) return;
    _released = true;
    await _proxy?.dispose();
    _proxy = null;
    await confirmServiceStopped();
  }

  @override
  Future<bool> confirmServiceStopped() async {
    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        if (!await service.isRunning()) return true;
        service.invoke('stopService');
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return !(await service.isRunning());
    } catch (_) {
      // The platform adapter is unavailable on a host where the plugin has no
      // implementation. The runtime already publishes Android unavailable;
      // this result only prevents disposal from surfacing a late plugin error.
      return true;
    }
  }

  @override
  Stream<void> get reconnects => _reconnects.stream;

  @override
  Future<void> dispose() async {
    await releaseOwnership();
    await _reconnects.close();
  }
}

abstract interface class RiskLifecycleAdapter {
  Stream<AppLifecycleState> get changes;

  Future<void> dispose();
}

class WidgetsRiskLifecycleAdapter implements RiskLifecycleAdapter {
  WidgetsRiskLifecycleAdapter({WidgetsBinding? binding})
    : _binding = binding ?? WidgetsFlutterBinding.ensureInitialized() {
    _binding.addObserver(_observer);
  }

  final WidgetsBinding _binding;
  final StreamController<AppLifecycleState> _changes =
      StreamController<AppLifecycleState>.broadcast();
  late final WidgetsBindingObserver _observer = _LifecycleObserver(_changes);

  @override
  Stream<AppLifecycleState> get changes => _changes.stream;

  @override
  Future<void> dispose() async {
    _binding.removeObserver(_observer);
    await _changes.close();
  }
}

class _LifecycleObserver with WidgetsBindingObserver {
  _LifecycleObserver(this.controller);

  final StreamController<AppLifecycleState> controller;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!controller.isClosed) controller.add(state);
  }
}

/// Selects exactly one owner and handles foreground lifecycle without editing
/// PortfolioScreen. Service-owned monitors continue while the UI is paused;
/// foreground-owned monitors persist a departure baseline and stop sampling;
/// Android service ownership keeps polling and records the UI check lifecycle
/// through typed departure/resume commands.
class RiskMonitorRuntime implements RiskMonitorOwner, RiskMonitorDisposable {
  RiskMonitorRuntime({
    required this.monitor,
    RiskRuntimePlatformAdapter? platform,
    this.androidServiceOwner,
    Stream<void>? credentialChanges,
    RiskLifecycleAdapter? lifecycle,
    RiskRuntimeClock? clock,
  }) : platform = platform ?? const DefaultRiskRuntimePlatformAdapter(),
       _credentialChanges = credentialChanges,
       _lifecycle = lifecycle ?? WidgetsRiskLifecycleAdapter(),
       _clock = clock ?? DateTime.now,
       _states = StreamController<RiskMonitorViewState>.broadcast() {
    _attachOwner(monitor);
    _reconnectSubscription = this.platform.reconnects.listen((_) {
      _schedulePlatformReconnect();
    });
    final changes = _credentialChanges;
    if (changes != null) {
      _credentialSubscription = changes.listen((_) {
        final owner = _activeOwner;
        final id =
            'runtime-credential-invalidate-${DateTime.now().microsecondsSinceEpoch}';
        if (owner != null && !identical(owner, monitor)) {
          // The service isolate performs the generation fence, cache clear,
          // and identity restart on its own serialized command queue.
          unawaited(
            owner.dispatch(
              RiskMonitorCommand.invalidateCredentials(
                id: id,
                reason: 'Credentials changed',
              ),
            ),
          );
        } else {
          monitor.invalidateCredentials(reason: 'Credentials changed');
        }
      });
    }
    _lifecycleSubscription = _lifecycle.changes.listen(_handleLifecycle);
  }

  final RiskMonitor monitor;
  final RiskRuntimePlatformAdapter platform;
  final RiskMonitorOwner? androidServiceOwner;
  final Stream<void>? _credentialChanges;
  final RiskLifecycleAdapter _lifecycle;
  final RiskRuntimeClock _clock;
  final StreamController<RiskMonitorViewState> _states;

  RiskMonitorOwner? _activeOwner;
  StreamSubscription<RiskMonitorViewState>? _ownerSubscription;
  StreamSubscription<void>? _reconnectSubscription;
  StreamSubscription<void>? _credentialSubscription;
  StreamSubscription<AppLifecycleState>? _lifecycleSubscription;
  final Map<String, RiskMonitorCommandResult> _results =
      <String, RiskMonitorCommandResult>{};
  Future<void> _dispatchTail = Future<void>.value();
  RiskMonitorViewState _state = RiskMonitorViewState();
  bool _ownershipAcquired = false;
  bool _disposed = false;
  bool _foregroundPaused = false;
  bool _resumeInFlight = false;
  bool _lifecycleStopQueued = false;
  bool _reconnectInFlight = false;
  Timer? _resumeTimer;
  RiskMonitorCommand? _lastStart;
  int _lifecycleEpoch = 0;
  int _lifecycleCommandSequence = 0;

  String _nextLifecycleCommandId(String prefix) {
    _lifecycleCommandSequence++;
    return '$prefix-$_lifecycleEpoch-${_clock().microsecondsSinceEpoch}-$_lifecycleCommandSequence';
  }

  void _schedulePlatformReconnect() {
    if (_reconnectInFlight || _disposed) return;
    _reconnectInFlight = true;
    unawaited(
      _handlePlatformReconnect().whenComplete(() {
        _reconnectInFlight = false;
      }),
    );
  }

  @override
  Stream<RiskMonitorViewState> get states => _states.stream;

  @override
  RiskMonitorViewState get currentState => _state;

  Future<void> _attachOwner(RiskMonitorOwner owner) async {
    await _ownerSubscription?.cancel();
    _activeOwner = owner;
    _state = owner.currentState;
    if (!_states.isClosed) _states.add(_state);
    _ownerSubscription = owner.states.listen((state) {
      if (_disposed) return;
      _state = state;
      if (!_states.isClosed) _states.add(state);
    });
  }

  @override
  Future<RiskMonitorCommandResult> dispatch(RiskMonitorCommand command) {
    final completer = Completer<RiskMonitorCommandResult>();
    _dispatchTail = _dispatchTail.then<void>((_) async {
      try {
        completer.complete(await _dispatchInternal(command));
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<RiskMonitorCommandResult> _dispatchInternal(
    RiskMonitorCommand command,
  ) async {
    if (_disposed) return _failed(command, 'Runtime is disposed');
    final prior = _results[command.id];
    if (prior != null) {
      return RiskMonitorCommandResult(
        commandId: prior.commandId,
        status: prior.status,
        state: prior.state,
        message: prior.message,
        replayed: true,
      );
    }
    if (command.type == RiskMonitorCommandType.start) {
      _lastStart = command;
    }
    late final RiskMonitorCommandResult result;
    if (command.type == RiskMonitorCommandType.start) {
      result = await _start(command);
    } else if (!_ownershipAcquired) {
      result = _failed(command, 'Monitor owner is not available');
    } else {
      result = await (_activeOwner ?? monitor).dispatch(command);
    }
    _results[command.id] = result;
    return result;
  }

  Future<RiskMonitorCommandResult> _start(RiskMonitorCommand command) async {
    if (!_ownershipAcquired) {
      final ownership = await platform.acquireOwnership();
      if (!ownership.granted) {
        monitor.setRuntimeStatus(
          ownerLabel: ownership.ownerLabel,
          backgroundAvailable: false,
          error: ownership.reason ?? 'Background monitoring unavailable',
        );
        _state = monitor.currentState;
        return _failed(
          command,
          ownership.reason ?? 'Background monitoring unavailable',
        );
      }
      _ownershipAcquired = true;
      final serviceOwner =
          ownership.owner ??
          (platform.kind == RiskRuntimePlatformKind.android
              ? androidServiceOwner
              : null);
      if (serviceOwner != null) {
        await _attachOwner(serviceOwner);
      } else {
        await _attachOwner(monitor);
        monitor.setRuntimeStatus(
          ownerLabel: ownership.ownerLabel,
          backgroundAvailable: ownership.backgroundAvailable,
        );
        monitor.setBackgroundMode(ownership.backgroundAvailable);
      }
    }
    return (_activeOwner ?? monitor).dispatch(command);
  }

  Future<void> _handlePlatformReconnect() async {
    if (_disposed || !_ownershipAcquired) return;
    if (platform.kind != RiskRuntimePlatformKind.android) {
      if (_activeOwner != null) {
        await dispatch(
          RiskMonitorCommand.reconnect(
            id: 'runtime-reconnect-${DateTime.now().microsecondsSinceEpoch}',
          ),
        );
      }
      return;
    }
    _ownershipAcquired = false;
    monitor.setRuntimeStatus(
      ownerLabel: 'android-service',
      backgroundAvailable: false,
      error: 'Android service disconnected',
    );
    final old = _activeOwner;
    if (old != null && !identical(old, monitor)) {
      await old.dispatch(
        RiskMonitorCommand.stop(
          id: 'runtime-service-loss-stop-${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      if (old is RiskMonitorDisposable) {
        await (old as RiskMonitorDisposable).dispose();
      }
    }
    await _confirmServiceStopped();
    final recovered = await platform.acquireOwnership();
    if (!recovered.granted) {
      await _confirmServiceStopped();
      monitor.setRuntimeStatus(
        ownerLabel: recovered.ownerLabel,
        backgroundAvailable: false,
        error: recovered.reason ?? 'Android service disconnected',
      );
      _state = monitor.currentState;
      return;
    }
    _ownershipAcquired = true;
    final owner = recovered.owner ?? androidServiceOwner;
    if (owner != null) await _attachOwner(owner);
    final last = _lastStart;
    if (last != null) {
      await (_activeOwner ?? monitor).dispatch(
        RiskMonitorCommand.start(
          id: 'runtime-service-restart-${DateTime.now().microsecondsSinceEpoch}',
          accountHash: last.accountHash,
          episodeKey: last.episodeKey,
        ),
      );
    }
  }

  Future<void> _handleLifecycle(AppLifecycleState state) async {
    if (_disposed || !_ownershipAcquired) return;
    final foregroundOwner = identical(_activeOwner, monitor);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _lifecycleEpoch++;
      _resumeTimer?.cancel();
      _resumeTimer = null;
      final alreadyPaused = _foregroundPaused;
      _foregroundPaused = true;
      if (foregroundOwner) monitor.invalidateNotificationCapability();
      if (foregroundOwner &&
          !_lifecycleStopQueued &&
          (!alreadyPaused || _resumeInFlight)) {
        _lifecycleStopQueued = true;
        try {
          await dispatch(
            RiskMonitorCommand.stop(
              id: _nextLifecycleCommandId('runtime-lifecycle-stop'),
            ),
          );
        } finally {
          _lifecycleStopQueued = false;
        }
      } else if (!foregroundOwner &&
          !_lifecycleStopQueued &&
          (!alreadyPaused || _resumeInFlight)) {
        _lifecycleStopQueued = true;
        try {
          await dispatch(
            RiskMonitorCommand.uiDeparture(
              id: _nextLifecycleCommandId('runtime-lifecycle-ui-departure'),
            ),
          );
        } finally {
          _lifecycleStopQueued = false;
        }
      }
    } else if (state == AppLifecycleState.resumed && _foregroundPaused) {
      await _resumeWhenReady();
    }
  }

  Future<void> _resumeWhenReady() async {
    if (_disposed || !_foregroundPaused || _resumeInFlight) return;
    final epoch = _lifecycleEpoch;
    await _resumeNow(epoch);
  }

  Future<void> _resumeNow(int epoch) async {
    if (_disposed || !_foregroundPaused || epoch != _lifecycleEpoch) return;
    _resumeTimer?.cancel();
    _resumeTimer = null;
    _resumeInFlight = true;
    final last = _lastStart;
    late final RiskMonitorCommandResult result;
    try {
      if (identical(_activeOwner, monitor)) {
        result = await dispatch(
          RiskMonitorCommand.start(
            id: _nextLifecycleCommandId('runtime-lifecycle-start'),
            accountHash: last?.accountHash,
            episodeKey: last?.episodeKey,
          ),
        );
      } else if (_activeOwner != null) {
        result = await dispatch(
          RiskMonitorCommand.uiResume(
            id: _nextLifecycleCommandId('runtime-lifecycle-ui-resume'),
          ),
        );
      } else {
        _resumeInFlight = false;
        return;
      }
    } catch (_) {
      _resumeInFlight = false;
      return;
    }
    // Keep the paused flag until the immediate resume command has completed.
    // A pause received while it was in flight increments the epoch and queues
    // its stop behind this command, so no stale resume can reopen sampling.
    if (_lifecycleEpoch == epoch &&
        result.status != RiskMonitorCommandStatus.failed &&
        result.status != RiskMonitorCommandStatus.rejected) {
      _foregroundPaused = false;
    }
    _resumeInFlight = false;
  }

  RiskMonitorCommandResult _failed(
    RiskMonitorCommand command,
    String message,
  ) => RiskMonitorCommandResult(
    commandId: command.id,
    status: RiskMonitorCommandStatus.failed,
    state: _state,
    message: message,
  );

  Future<bool> _confirmServiceStopped() async {
    final health = platform;
    if (health is RiskRuntimeServiceHealth) {
      return (health as RiskRuntimeServiceHealth).confirmServiceStopped();
    }
    return true;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _ownerSubscription?.cancel();
    await _reconnectSubscription?.cancel();
    await _credentialSubscription?.cancel();
    await _lifecycleSubscription?.cancel();
    _resumeTimer?.cancel();
    _resumeTimer = null;
    final owner = _activeOwner;
    if (owner != null && !identical(owner, monitor)) {
      if (owner is RiskMonitorDisposable) {
        await (owner as RiskMonitorDisposable).dispose();
      }
    }
    await monitor.dispose();
    await platform.releaseOwnership();
    if (platform is RiskRuntimePlatformDisposable) {
      await (platform as RiskRuntimePlatformDisposable).dispose();
    }
    await _lifecycle.dispose();
    await _states.close();
  }
}
