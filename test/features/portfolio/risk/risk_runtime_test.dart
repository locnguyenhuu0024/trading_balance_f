import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:trading_balance_f/core/services/background_service.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/features/portfolio/application/risk_monitor.dart';
import 'package:trading_balance_f/features/portfolio/application/risk_monitor_bridge.dart';
import 'package:trading_balance_f/features/portfolio/application/risk_notification_sink.dart';
import 'package:trading_balance_f/features/portfolio/application/risk_monitor_runtime.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_models.dart';

import 'fixtures/risk_monitor_fixtures.dart';

class FakeRuntimePlatform implements RiskRuntimePlatformAdapter {
  FakeRuntimePlatform({
    required this.platformKind,
    required this.ownership,
    this.ownershipForAcquire,
  });

  final RiskRuntimePlatformKind platformKind;
  final RiskRuntimeOwnership ownership;
  final RiskRuntimeOwnership Function(int call)? ownershipForAcquire;
  final StreamController<void> reconnectController =
      StreamController<void>.broadcast();
  int acquireCalls = 0;
  int releaseCalls = 0;

  @override
  RiskRuntimePlatformKind get kind => platformKind;

  @override
  Future<RiskRuntimeOwnership> acquireOwnership() async {
    acquireCalls++;
    return ownershipForAcquire?.call(acquireCalls) ?? ownership;
  }

  @override
  Future<void> releaseOwnership() async {
    releaseCalls++;
  }

  @override
  Stream<void> get reconnects => reconnectController.stream;

  Future<void> dispose() => reconnectController.close();
}

class FakeLifecycle implements RiskLifecycleAdapter {
  final StreamController<AppLifecycleState> _controller =
      StreamController<AppLifecycleState>.broadcast();
  int disposeCalls = 0;

  @override
  Stream<AppLifecycleState> get changes => _controller.stream;

  void emit(AppLifecycleState state) => _controller.add(state);

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await _controller.close();
  }
}

class FakeServiceChannel implements RiskServiceChannel {
  final Map<String, StreamController<Map<String, dynamic>?>> _channels =
      <String, StreamController<Map<String, dynamic>?>>{};
  final List<String> invocations = <String>[];

  StreamController<Map<String, dynamic>?> _channel(String method) =>
      _channels.putIfAbsent(
        method,
        () => StreamController<Map<String, dynamic>?>.broadcast(),
      );

  @override
  Stream<Map<String, dynamic>?> on(String method) => _channel(method).stream;

  @override
  void invoke(String method, [Map<String, dynamic>? arguments]) {
    invocations.add(method);
    if (method == 'stopService') return;
    _channel(method).add(arguments);
  }

  void emit(String method, Map<String, dynamic> arguments) =>
      _channel(method).add(arguments);

  Future<void> disconnect() async {
    for (final channel in _channels.values) {
      await channel.close();
    }
  }
}

class TrackingDisposableOwner extends InMemoryRiskMonitorOwner
    implements RiskMonitorDisposable {
  TrackingDisposableOwner({super.initial});

  int dispatchCalls = 0;
  int disposeCalls = 0;

  @override
  Future<RiskMonitorCommandResult> dispatch(RiskMonitorCommand command) {
    dispatchCalls++;
    return super.dispatch(command);
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

class TrackingMonitor extends RiskMonitor {
  TrackingMonitor({
    required super.dataSource,
    required super.persistence,
    super.clock,
  }) : super();

  int disposeCalls = 0;

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await super.dispose();
  }
}

class OrderedServiceOwner implements RiskMonitorOwner, RiskMonitorDisposable {
  final StreamController<RiskMonitorViewState> _states =
      StreamController<RiskMonitorViewState>.broadcast();
  final List<String> dispatchOrder = <String>[];
  RiskMonitorViewState _state = RiskMonitorViewState(
    ownerLabel: 'android-service',
    backgroundAvailable: true,
  );
  Completer<void>? gate;

  @override
  Stream<RiskMonitorViewState> get states => _states.stream;

  @override
  RiskMonitorViewState get currentState => _state;

  @override
  Future<RiskMonitorCommandResult> dispatch(RiskMonitorCommand command) async {
    dispatchOrder.add(command.id);
    final pending = gate;
    gate = null;
    if (pending != null) await pending.future;
    _state = _state.copyWith(
      isRunning: command.type == RiskMonitorCommandType.start,
    );
    if (!_states.isClosed) _states.add(_state);
    return RiskMonitorCommandResult(
      commandId: command.id,
      status: RiskMonitorCommandStatus.accepted,
      state: _state,
    );
  }

  @override
  Future<void> dispose() => _states.close();
}

class CachedCapabilitySink
    implements RiskNotificationSink, RiskNotificationCapabilityInvalidator {
  CachedCapabilitySink({
    required RiskNotificationCapability initial,
    required this.permission,
  }) : _cached = initial;

  RiskNotificationCapability permission;
  RiskNotificationCapability _cached;
  int invalidateCalls = 0;
  int capabilityCalls = 0;
  final List<RiskNotification> delivered = <RiskNotification>[];

  @override
  void invalidateCapability() {
    invalidateCalls++;
    _cached = permission;
  }

  @override
  Future<RiskNotificationCapability> capability() async {
    capabilityCalls++;
    return _cached;
  }

  @override
  Future<RiskNotificationDelivery> deliver(
    RiskNotification notification,
  ) async {
    if (!_cached.canDeliver) {
      return RiskNotificationDelivery.denied(_cached.reason);
    }
    delivered.add(notification);
    return const RiskNotificationDelivery.delivered();
  }
}

void main() {
  test(
    'RED-005 Android ownership failure publishes unavailable without polling',
    () async {
      final clock = FakeRiskClock();
      final source = FakeRiskSource(
        clock: clock,
        position: () => syntheticRiskPosition(observedAt: clock.value),
      );
      final persistence = FakeRiskPersistence();
      final monitor = RiskMonitor(
        dataSource: source,
        persistence: persistence,
        clock: clock.now,
      );
      final platform = FakeRuntimePlatform(
        platformKind: RiskRuntimePlatformKind.android,
        ownership: const RiskRuntimeOwnership.unavailable(
          reason: 'service disconnected',
        ),
      );
      final runtime = RiskMonitorRuntime(monitor: monitor, platform: platform);

      final result = await runtime.dispatch(
        RiskMonitorCommand.start(id: 'android-unavailable'),
      );
      expect(result.status, RiskMonitorCommandStatus.failed);
      expect(result.state.backgroundAvailable, isFalse);
      expect(result.state.isRunning, isFalse);
      expect(source.positionCalls, 0);
      await runtime.dispose();
      await platform.dispose();
    },
  );

  test(
    'GREEN-005 service owner and reconnect keep one serialized poller',
    () async {
      final clock = FakeRiskClock();
      final source = FakeRiskSource(
        clock: clock,
        position: () => syntheticRiskPosition(observedAt: clock.value),
      );
      final monitor = RiskMonitor(
        dataSource: source,
        persistence: FakeRiskPersistence(),
        clock: clock.now,
      );
      final serviceOwner = TrackingDisposableOwner(
        initial: RiskMonitorViewState(
          ownerLabel: 'android-service',
          backgroundAvailable: true,
        ),
      );
      final restartedOwner = TrackingDisposableOwner(
        initial: RiskMonitorViewState(
          ownerLabel: 'android-service',
          backgroundAvailable: true,
        ),
      );
      final platform = FakeRuntimePlatform(
        platformKind: RiskRuntimePlatformKind.android,
        ownership: RiskRuntimeOwnership(
          granted: true,
          ownerLabel: 'android-service',
          backgroundAvailable: true,
          owner: serviceOwner,
        ),
        ownershipForAcquire: (call) => call == 1
            ? RiskRuntimeOwnership(
                granted: true,
                ownerLabel: 'android-service',
                backgroundAvailable: true,
                owner: serviceOwner,
              )
            : RiskRuntimeOwnership(
                granted: true,
                ownerLabel: 'android-service',
                backgroundAvailable: true,
                owner: restartedOwner,
              ),
      );
      final runtime = RiskMonitorRuntime(monitor: monitor, platform: platform);

      final first = await runtime.dispatch(
        RiskMonitorCommand.start(id: 'android-start'),
      );
      expect(first.accepted, isTrue);
      expect(first.state.ownerLabel, 'android-service');
      expect(first.state.backgroundAvailable, isTrue);
      final callsAfterStart = source.positionCalls;

      final duplicate = await runtime.dispatch(
        RiskMonitorCommand.start(id: 'android-start'),
      );
      expect(duplicate.replayed, isTrue);
      expect(source.positionCalls, callsAfterStart);

      clock.advance(const Duration(minutes: 1));
      platform.reconnectController.add(null);
      await Future<void>.delayed(Duration.zero);
      // A service reconnect releases the stale ownership and reacquires it
      // only after the old owner is confirmed stopped.  The foreground
      // monitor is never started as a competing fallback.
      expect(platform.acquireCalls, 2);
      expect(source.positionCalls, 0);

      await runtime.dispose();
      await platform.dispose();
      expect(serviceOwner.disposeCalls, 1);
      expect(restartedOwner.disposeCalls, 1);
    },
  );

  test('GREEN-005 web ownership uses the foreground owner only', () async {
    final clock = FakeRiskClock();
    final source = FakeRiskSource(
      clock: clock,
      position: () => syntheticRiskPosition(observedAt: clock.value),
    );
    final monitor = RiskMonitor(
      dataSource: source,
      persistence: FakeRiskPersistence(),
      clock: clock.now,
    );
    final platform = FakeRuntimePlatform(
      platformKind: RiskRuntimePlatformKind.web,
      ownership: const RiskRuntimeOwnership.foreground(),
    );
    final runtime = RiskMonitorRuntime(monitor: monitor, platform: platform);
    final result = await runtime.dispatch(
      RiskMonitorCommand.start(id: 'web-start'),
    );
    expect(result.accepted, isTrue);
    expect(result.state.ownerLabel, 'foreground');
    expect(result.state.backgroundAvailable, isFalse);
    expect(platform.acquireCalls, 1);
    await runtime.dispose();
    await platform.dispose();
  });

  test(
    'GREEN-005 service channel handshake, ack and duplicate command are idempotent',
    () async {
      final channel = FakeServiceChannel();
      final serviceOwner = TrackingDisposableOwner();
      final controller = RiskServiceOwnerController(
        channel: channel,
        owner: serviceOwner,
      );
      var disconnects = 0;
      final proxy = RiskServiceOwnerProxy(
        channel: channel,
        handshakeTimeout: const Duration(seconds: 1),
        onDisconnected: () => disconnects++,
      );

      expect(await proxy.waitForHandshake(), isTrue);
      final command = RiskMonitorCommand.start(id: 'service-idempotent-start');
      final first = await proxy.dispatch(command);
      final replay = await proxy.dispatch(command);
      expect(first.accepted, isTrue);
      expect(replay.replayed, isTrue);
      expect(serviceOwner.dispatchCalls, 1);
      expect(
        channel.invocations.where((item) => item == RiskMonitorWire.command),
        hasLength(1),
      );

      await channel.disconnect();
      await Future<void>.delayed(Duration.zero);
      expect(disconnects, greaterThan(0));
      final failed = await proxy.dispatch(
        RiskMonitorCommand.refresh(id: 'service-disconnected-refresh'),
      );
      expect(failed.status, RiskMonitorCommandStatus.failed);
      await proxy.dispose();
      await controller.dispose();
      expect(serviceOwner.disposeCalls, 1);
    },
  );

  test(
    'GREEN-005 R22-002 populated monitor state survives the service controller/proxy wire',
    () async {
      final clock = FakeRiskClock();
      var mark = 10.0;
      final source = FakeRiskSource(
        clock: clock,
        position: () =>
            syntheticRiskPosition(observedAt: clock.value, markPrice: mark),
      );
      final monitor = TrackingMonitor(
        dataSource: source,
        persistence: FakeRiskPersistence(),
        clock: clock.now,
      );
      final channel = FakeServiceChannel();
      final controller = RiskServiceOwnerController(
        channel: channel,
        owner: monitor,
      );
      final proxy = RiskServiceOwnerProxy(
        channel: channel,
        handshakeTimeout: const Duration(milliseconds: 100),
        silenceTimeout: const Duration(seconds: 1),
      );

      expect(await proxy.waitForHandshake(), isTrue);
      final started = await proxy.dispatch(
        RiskMonitorCommand.start(id: 'wire-populated-start'),
      );
      expect(started.accepted, isTrue);
      clock.advance(const Duration(minutes: 1));
      mark = 8;
      final refreshed = await proxy.dispatch(
        RiskMonitorCommand.refresh(id: 'wire-populated-refresh'),
      );
      expect(refreshed.accepted, isTrue);

      final original = monitor.currentState;
      final received = proxy.currentState;
      expect(original.evaluation, isNotNull);
      expect(original.market, isNotNull);
      expect(original.samples, isNotEmpty);
      expect(original.trend, isNotNull);
      expect(original.velocity, isNotNull);
      expect(received.accountHash, original.accountHash);
      expect(received.episodeKey, original.episodeKey);
      expect(
        received.evaluation?.metrics.markPrice.value,
        closeTo(original.evaluation!.metrics.markPrice.value!, 1e-12),
      );
      expect(received.market?.marketPoints, original.market?.marketPoints);
      expect(received.samples?.length, original.samples?.length);
      expect(received.trend?.label, original.trend?.label);
      expect(received.velocity?.label, original.velocity?.label);
      expect(
        received.events.map((event) => event.id),
        original.events.map((event) => event.id),
      );

      await proxy.dispose();
      await controller.dispose();
      expect(monitor.disposeCalls, 1);
    },
  );

  test(
    'GREEN-005 R22-002 service controller serializes command delivery',
    () async {
      final channel = FakeServiceChannel();
      final gate = Completer<void>();
      final owner = OrderedServiceOwner()..gate = gate;
      final controller = RiskServiceOwnerController(
        channel: channel,
        owner: owner,
      );
      final first = RiskMonitorCommand.start(id: 'service-queue-one');
      final second = RiskMonitorCommand.refresh(id: 'service-queue-two');

      channel.emit(
        RiskMonitorWire.command,
        RiskMonitorWire.encodeCommand(first),
      );
      channel.emit(
        RiskMonitorWire.command,
        RiskMonitorWire.encodeCommand(second),
      );
      await Future<void>.delayed(Duration.zero);
      expect(owner.dispatchOrder, <String>['service-queue-one']);

      gate.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(owner.dispatchOrder, <String>[
        'service-queue-one',
        'service-queue-two',
      ]);
      await controller.dispose();
      await owner.dispose();
    },
  );

  test(
    'GREEN-005 R22-002 service heartbeat keeps a healthy owner alive while idle',
    () async {
      final channel = FakeServiceChannel();
      final owner = TrackingDisposableOwner(
        initial: RiskMonitorViewState(
          ownerLabel: 'android-service',
          backgroundAvailable: true,
        ),
      );
      final controller = RiskServiceOwnerController(
        channel: channel,
        owner: owner,
        heartbeatInterval: const Duration(milliseconds: 5),
      );
      var disconnects = 0;
      final proxy = RiskServiceOwnerProxy(
        channel: channel,
        handshakeTimeout: const Duration(milliseconds: 100),
        silenceTimeout: const Duration(milliseconds: 30),
        onDisconnected: () => disconnects++,
      );

      expect(await proxy.waitForHandshake(), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(disconnects, 0);
      expect(proxy.currentState.backgroundAvailable, isTrue);

      await proxy.dispose();
      await controller.dispose();
    },
  );

  test(
    'GREEN-005 R22-003 slow acknowledged command survives handshake timeout with heartbeats',
    () async {
      final channel = FakeServiceChannel();
      final gate = Completer<void>();
      final owner = OrderedServiceOwner()..gate = gate;
      final controller = RiskServiceOwnerController(
        channel: channel,
        owner: owner,
        heartbeatInterval: const Duration(milliseconds: 5),
      );
      var disconnects = 0;
      final proxy = RiskServiceOwnerProxy(
        channel: channel,
        handshakeTimeout: const Duration(milliseconds: 10),
        livenessTimeout: const Duration(milliseconds: 30),
        commandCompletionTimeout: const Duration(milliseconds: 200),
        onDisconnected: () => disconnects++,
      );

      expect(await proxy.waitForHandshake(), isTrue);
      final pending = proxy.dispatch(
        RiskMonitorCommand.start(id: 'slow-healthy-start'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(disconnects, 0);
      expect(proxy.currentState.backgroundAvailable, isTrue);

      gate.complete();
      final result = await pending;
      expect(result.accepted, isTrue);
      expect(disconnects, 0);

      await proxy.dispose();
      await controller.dispose();
    },
  );

  test(
    'GREEN-005 foreground lifecycle waits for a sixty-second departure',
    () async {
      final clock = FakeRiskClock();
      final source = FakeRiskSource(
        clock: clock,
        position: () => syntheticRiskPosition(observedAt: clock.value),
      );
      final persistence = FakeRiskPersistence();
      final monitor = RiskMonitor(
        dataSource: source,
        persistence: persistence,
        clock: clock.now,
      );
      final platform = FakeRuntimePlatform(
        platformKind: RiskRuntimePlatformKind.desktop,
        ownership: const RiskRuntimeOwnership.foreground(),
      );
      final lifecycle = FakeLifecycle();
      final runtime = RiskMonitorRuntime(
        monitor: monitor,
        platform: platform,
        lifecycle: lifecycle,
        clock: clock.now,
      );
      await runtime.dispatch(RiskMonitorCommand.start(id: 'lifecycle-start'));
      lifecycle.emit(AppLifecycleState.paused);
      await Future<void>.delayed(Duration.zero);
      expect(monitor.currentState.isRunning, isFalse);
      expect(persistence.episodes.values.single.lastCheckBaseline, isNotNull);

      clock.advance(const Duration(seconds: 30));
      lifecycle.emit(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(monitor.currentState.isRunning, isTrue);
      await runtime.dispose();
      await platform.dispose();
      expect(lifecycle.disposeCalls, 1);
    },
  );

  test(
    'GREEN-005 R22-002 a later foreground pause cancels an in-flight immediate resume',
    () async {
      final clock = FakeRiskClock();
      final source = FakeRiskSource(
        clock: clock,
        position: () => syntheticRiskPosition(observedAt: clock.value),
      );
      final persistence = FakeRiskPersistence();
      final monitor = RiskMonitor(
        dataSource: source,
        persistence: persistence,
        clock: clock.now,
      );
      final platform = FakeRuntimePlatform(
        platformKind: RiskRuntimePlatformKind.desktop,
        ownership: const RiskRuntimeOwnership.foreground(),
      );
      final lifecycle = FakeLifecycle();
      final runtime = RiskMonitorRuntime(
        monitor: monitor,
        platform: platform,
        lifecycle: lifecycle,
        clock: clock.now,
      );

      await runtime.dispatch(
        RiskMonitorCommand.start(id: 'lifecycle-cancel-start'),
      );
      lifecycle.emit(AppLifecycleState.paused);
      await Future<void>.delayed(Duration.zero);
      expect(monitor.currentState.isRunning, isFalse);

      final pending = Completer<RiskPositionSelection>();
      source.pendingPosition = pending.future;
      lifecycle.emit(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      lifecycle.emit(AppLifecycleState.paused);
      await Future<void>.delayed(Duration.zero);
      pending.complete(
        RiskPositionSelection(
          status: RiskEligibility.eligible,
          quality: RiskQuality.complete(
            source: 'synthetic-position',
            observedAt: clock.value,
            sourceAt: clock.value,
          ),
          position: syntheticRiskPosition(observedAt: clock.value),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(monitor.currentState.isRunning, isFalse);

      await runtime.dispose();
      await platform.dispose();
    },
  );

  test(
    'GREEN-005 credential mutation bus invalidates the old generation',
    () async {
      final clock = FakeRiskClock();
      final source = FakeRiskSource(
        clock: clock,
        position: () => syntheticRiskPosition(observedAt: clock.value),
      );
      final monitor = RiskMonitor(
        dataSource: source,
        persistence: FakeRiskPersistence(),
        clock: clock.now,
      );
      final platform = FakeRuntimePlatform(
        platformKind: RiskRuntimePlatformKind.desktop,
        ownership: const RiskRuntimeOwnership.foreground(),
      );
      final runtime = RiskMonitorRuntime(
        monitor: monitor,
        platform: platform,
        credentialChanges: CredentialMutationBus.changes,
      );
      await runtime.dispatch(RiskMonitorCommand.start(id: 'credential-start'));
      final oldGeneration = monitor.generation;
      CredentialMutationBus.notify();
      await Future<void>.delayed(Duration.zero);
      expect(monitor.generation, greaterThan(oldGeneration));
      expect(monitor.currentState.isRunning, isFalse);
      await runtime.dispose();
      await platform.dispose();
    },
  );

  test(
    'GREEN-005 runtime disposes active service and unused foreground owner once',
    () async {
      final clock = FakeRiskClock();
      final monitor = TrackingMonitor(
        dataSource: FakeRiskSource(
          clock: clock,
          position: () => syntheticRiskPosition(observedAt: clock.value),
        ),
        persistence: FakeRiskPersistence(),
        clock: clock.now,
      );
      final serviceOwner = TrackingDisposableOwner();
      final platform = FakeRuntimePlatform(
        platformKind: RiskRuntimePlatformKind.android,
        ownership: RiskRuntimeOwnership(
          granted: true,
          ownerLabel: 'android-service',
          backgroundAvailable: true,
          owner: serviceOwner,
        ),
      );
      final runtime = RiskMonitorRuntime(monitor: monitor, platform: platform);
      await runtime.dispatch(RiskMonitorCommand.start(id: 'dispose-start'));
      await runtime.dispose();
      await runtime.dispose();
      expect(serviceOwner.disposeCalls, 1);
      expect(monitor.disposeCalls, 1);
      expect(platform.releaseCalls, 1);
      await platform.dispose();
    },
  );

  test(
    'GREEN-005 R22-002 service credential invalidation fences, clears and restarts identity',
    () async {
      final clock = FakeRiskClock();
      final source = FakeRiskSource(
        clock: clock,
        position: () => syntheticRiskPosition(observedAt: clock.value),
      );
      final monitor = TrackingMonitor(
        dataSource: source,
        persistence: FakeRiskPersistence(),
        clock: clock.now,
      );
      final channel = FakeServiceChannel();
      final controller = RiskServiceOwnerController(
        channel: channel,
        owner: monitor,
      );
      final proxy = RiskServiceOwnerProxy(
        channel: channel,
        handshakeTimeout: const Duration(milliseconds: 100),
        silenceTimeout: const Duration(seconds: 1),
      );

      expect(await proxy.waitForHandshake(), isTrue);
      final started = await proxy.dispatch(
        RiskMonitorCommand.start(id: 'service-credential-start'),
      );
      expect(started.accepted, isTrue);
      final oldGeneration = monitor.generation;
      final oldCalls = source.positionCalls;
      final oldAccount = monitor.currentState.accountHash;
      final oldEpisode = monitor.currentState.episodeKey;

      final invalidated = await proxy.dispatch(
        RiskMonitorCommand.invalidateCredentials(
          id: 'service-credential-invalidate',
          reason: 'synthetic credential rotation',
        ),
      );
      expect(invalidated.accepted, isTrue);
      expect(monitor.generation, greaterThan(oldGeneration));
      expect(source.clearCachesCalls, greaterThanOrEqualTo(1));
      expect(source.positionCalls, greaterThan(oldCalls));
      expect(monitor.currentState.isRunning, isTrue);
      expect(monitor.currentState.accountHash, oldAccount);
      expect(monitor.currentState.episodeKey, oldEpisode);

      final replay = await proxy.dispatch(
        RiskMonitorCommand.invalidateCredentials(
          id: 'service-credential-invalidate',
        ),
      );
      expect(replay.replayed, isTrue);
      expect(source.positionCalls, greaterThan(oldCalls));

      await proxy.dispose();
      await controller.dispose();
      expect(monitor.disposeCalls, 1);
    },
  );

  test(
    'RED-005 R22-002 service invalidation fences a deferred old-account capture',
    () async {
      final clock = FakeRiskClock();
      var currentAccount = 'account-a';
      final source = FakeRiskSource(
        clock: clock,
        position: () => syntheticRiskPosition(
          observedAt: clock.value,
          account: currentAccount,
        ),
      );
      final pending = Completer<RiskPositionSelection>();
      final persistence = FakeRiskPersistence();
      final monitor = TrackingMonitor(
        dataSource: source,
        persistence: persistence,
        clock: clock.now,
      );
      final channel = FakeServiceChannel();
      final controller = RiskServiceOwnerController(
        channel: channel,
        owner: monitor,
      );
      final proxy = RiskServiceOwnerProxy(
        channel: channel,
        handshakeTimeout: const Duration(milliseconds: 100),
        silenceTimeout: const Duration(seconds: 1),
      );

      expect(await proxy.waitForHandshake(), isTrue);
      expect(
        await proxy.dispatch(
          RiskMonitorCommand.start(id: 'service-fence-start'),
        ),
        isA<RiskMonitorCommandResult>().having(
          (result) => result.status,
          'status',
          RiskMonitorCommandStatus.accepted,
        ),
      );
      clock.advance(const Duration(minutes: 1));
      source.pendingPosition = pending.future;
      final savesBeforeCapture = persistence.saveHistory.length;
      final refresh = proxy.dispatch(
        RiskMonitorCommand.refresh(id: 'service-fence-refresh'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(monitor.captureInFlight, isTrue);

      currentAccount = 'account-b';
      final invalidated = proxy.dispatch(
        RiskMonitorCommand.invalidateCredentials(
          id: 'service-fence-invalidate',
          reason: 'synthetic credential rotation',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(monitor.currentState.isRunning, isFalse);

      pending.complete(
        RiskPositionSelection(
          status: RiskEligibility.eligible,
          quality: RiskQuality.complete(
            source: 'old-account',
            observedAt: clock.value,
            sourceAt: clock.value,
          ),
          position: syntheticRiskPosition(
            observedAt: clock.value,
            account: 'account-a',
          ),
        ),
      );
      await refresh;
      await invalidated;

      final postFenceSaves = persistence.saveHistory.skip(savesBeforeCapture);
      expect(postFenceSaves, isNotEmpty);
      expect(
        postFenceSaves.every((record) => record.accountHash == 'account-b'),
        isTrue,
      );
      expect(monitor.currentState.isRunning, isTrue);
      expect(monitor.currentState.accountHash, 'account-b');
      expect(source.clearCachesCalls, greaterThanOrEqualTo(1));

      await proxy.dispose();
      await controller.dispose();
      expect(monitor.disposeCalls, 1);
    },
  );

  test(
    'RED-005 R22-002 silent service ack timeout loses ownership and cleans timers',
    () async {
      final channel = FakeServiceChannel();
      var disconnects = 0;
      final proxy = RiskServiceOwnerProxy(
        channel: channel,
        handshakeTimeout: const Duration(milliseconds: 40),
        silenceTimeout: const Duration(seconds: 1),
        commandCompletionTimeout: const Duration(milliseconds: 40),
        onDisconnected: () => disconnects++,
      );
      final handshake = proxy.waitForHandshake();
      channel.emit(RiskMonitorWire.handshake, <String, dynamic>{
        'protocol': RiskMonitorWire.handshake,
        'owner': 'android-service',
        'backgroundAvailable': true,
      });
      expect(await handshake, isTrue);

      final failed = await proxy.dispatch(
        RiskMonitorCommand.refresh(id: 'silent-service-command'),
      );
      expect(failed.status, RiskMonitorCommandStatus.failed);
      expect(proxy.currentState.isRunning, isFalse);
      expect(proxy.currentState.backgroundAvailable, isFalse);
      expect(proxy.currentState.quality.status, RiskQualityStatus.unavailable);
      expect(disconnects, 1);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(disconnects, 1);
      expect(
        await proxy.dispatch(
          RiskMonitorCommand.refresh(id: 'silent-service-after-loss'),
        ),
        isA<RiskMonitorCommandResult>().having(
          (result) => result.status,
          'status',
          RiskMonitorCommandStatus.failed,
        ),
      );
      await proxy.dispose();
      expect(channel.invocations, contains('stopService'));
    },
  );

  test(
    'GREEN-005 R22-002 Android service keeps monitoring while UI lifecycle pauses',
    () async {
      final clock = FakeRiskClock();
      final source = FakeRiskSource(
        clock: clock,
        position: () => syntheticRiskPosition(observedAt: clock.value),
      );
      final monitor = RiskMonitor(
        dataSource: source,
        persistence: FakeRiskPersistence(),
        clock: clock.now,
      );
      final serviceOwner = TrackingDisposableOwner(
        initial: RiskMonitorViewState(
          ownerLabel: 'android-service',
          backgroundAvailable: true,
        ),
      );
      final platform = FakeRuntimePlatform(
        platformKind: RiskRuntimePlatformKind.android,
        ownership: RiskRuntimeOwnership(
          granted: true,
          ownerLabel: 'android-service',
          backgroundAvailable: true,
          owner: serviceOwner,
        ),
      );
      final lifecycle = FakeLifecycle();
      final runtime = RiskMonitorRuntime(
        monitor: monitor,
        platform: platform,
        lifecycle: lifecycle,
      );

      await runtime.dispatch(RiskMonitorCommand.start(id: 'service-ui-start'));
      lifecycle.emit(AppLifecycleState.paused);
      await Future<void>.delayed(Duration.zero);
      expect(serviceOwner.currentState.isRunning, isTrue);
      final callsWhilePaused = serviceOwner.dispatchCalls;

      lifecycle.emit(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(serviceOwner.currentState.isRunning, isTrue);
      expect(serviceOwner.dispatchCalls, greaterThan(callsWhilePaused));
      await runtime.dispose();
      await platform.dispose();
    },
  );

  test(
    'GREEN-005 R22-003 Android UI departure persists a frozen baseline while service polls',
    () async {
      final clock = FakeRiskClock();
      var mark = 10.0;
      final source = FakeRiskSource(
        clock: clock,
        position: () =>
            syntheticRiskPosition(observedAt: clock.value, markPrice: mark),
      );
      final persistence = FakeRiskPersistence();
      final monitor = TrackingMonitor(
        dataSource: source,
        persistence: persistence,
        clock: clock.now,
      );
      final channel = FakeServiceChannel();
      final controller = RiskServiceOwnerController(
        channel: channel,
        owner: monitor,
        heartbeatInterval: const Duration(milliseconds: 5),
      );
      final proxy = RiskServiceOwnerProxy(
        channel: channel,
        handshakeTimeout: const Duration(milliseconds: 100),
        livenessTimeout: const Duration(seconds: 1),
        commandCompletionTimeout: const Duration(seconds: 1),
      );
      final platform = FakeRuntimePlatform(
        platformKind: RiskRuntimePlatformKind.android,
        ownership: RiskRuntimeOwnership(
          granted: true,
          ownerLabel: 'android-service',
          backgroundAvailable: true,
          owner: proxy,
        ),
      );
      final lifecycle = FakeLifecycle();
      final runtime = RiskMonitorRuntime(
        monitor: monitor,
        platform: platform,
        lifecycle: lifecycle,
        clock: clock.now,
      );

      await runtime.dispatch(
        RiskMonitorCommand.start(
          id: 'ui-baseline-start',
          accountHash: 'account-a',
          episodeKey: syntheticRiskPosition(observedAt: clock.value).episodeKey,
        ),
      );
      final initial = monitor.currentState.samples!.last;
      lifecycle.emit(AppLifecycleState.paused);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final persistedBaseline =
          persistence.episodes.values.single.lastCheckBaseline;
      expect(monitor.currentState.isRunning, isTrue);
      expect(persistedBaseline, isNotNull);
      expect(persistedBaseline!.observedAt, initial.observedAt);
      expect(
        channel.invocations.where((item) => item == 'stopService'),
        isEmpty,
      );

      clock.advance(const Duration(seconds: 30));
      await runtime.dispatch(
        RiskMonitorCommand.refresh(id: 'ui-baseline-away-refresh'),
      );
      expect(
        persistence.episodes.values.single.lastCheckBaseline!.observedAt,
        persistedBaseline.observedAt,
      );
      expect(monitor.currentState.isRunning, isTrue);

      mark = 9;
      clock.advance(const Duration(seconds: 31));
      lifecycle.emit(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final comparison = monitor.currentState.previousCheck;
      expect(monitor.currentState.isRunning, isTrue);
      expect(comparison, isNotNull);
      expect(comparison!.baseline.observedAt, persistedBaseline.observedAt);
      expect(comparison.current.observedAt, clock.value);
      expect(
        channel.invocations.where((item) => item == 'stopService'),
        isEmpty,
      );

      await runtime.dispose();
      await controller.dispose();
      await platform.dispose();
    },
  );

  test(
    'GREEN-005 R22-004 Android UI resume refreshes permission before service delivery',
    () async {
      final clock = FakeRiskClock();
      var mark = 10.0;
      final source = FakeRiskSource(
        clock: clock,
        position: () =>
            syntheticRiskPosition(observedAt: clock.value, markPrice: mark),
      );
      final persistence = FakeRiskPersistence();
      final sink = CachedCapabilitySink(
        initial: const RiskNotificationCapability.denied('paused permission'),
        permission: const RiskNotificationCapability.denied(
          'paused permission',
        ),
      );
      final monitor = RiskMonitor(
        dataSource: source,
        persistence: persistence,
        clock: clock.now,
        notificationSink: sink,
      );
      final channel = FakeServiceChannel();
      final controller = RiskServiceOwnerController(
        channel: channel,
        owner: monitor,
        heartbeatInterval: const Duration(milliseconds: 5),
      );
      final proxy = RiskServiceOwnerProxy(
        channel: channel,
        handshakeTimeout: const Duration(milliseconds: 100),
        livenessTimeout: const Duration(seconds: 1),
        commandCompletionTimeout: const Duration(seconds: 1),
      );
      final platform = FakeRuntimePlatform(
        platformKind: RiskRuntimePlatformKind.android,
        ownership: RiskRuntimeOwnership(
          granted: true,
          ownerLabel: 'android-service',
          backgroundAvailable: true,
          owner: proxy,
        ),
      );
      final lifecycle = FakeLifecycle();
      final runtime = RiskMonitorRuntime(
        monitor: monitor,
        platform: platform,
        lifecycle: lifecycle,
        clock: clock.now,
      );

      await runtime.dispatch(
        RiskMonitorCommand.start(
          id: 'capability-resume-start',
          accountHash: 'account-a',
          episodeKey: syntheticRiskPosition(observedAt: clock.value).episodeKey,
        ),
      );
      expect(
        monitor.currentState.notificationCapability,
        RiskNotificationCapabilityStatus.denied,
      );
      lifecycle.emit(AppLifecycleState.paused);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // The native permission is granted while the service remains the owner,
      // but its old denied capability is still cached until resume invalidates it.
      sink.permission = const RiskNotificationCapability.granted();
      mark = 5;
      clock.advance(const Duration(seconds: 61));
      lifecycle.emit(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(sink.invalidateCalls, greaterThan(0));
      expect(sink.capabilityCalls, greaterThan(1));
      expect(
        monitor.currentState.notificationCapability,
        RiskNotificationCapabilityStatus.granted,
      );
      expect(sink.delivered, isNotEmpty);
      expect(monitor.currentState.isRunning, isTrue);
      expect(
        channel.invocations.where((item) => item == 'stopService'),
        isEmpty,
      );

      await runtime.dispose();
      await controller.dispose();
      await platform.dispose();
    },
  );
}
