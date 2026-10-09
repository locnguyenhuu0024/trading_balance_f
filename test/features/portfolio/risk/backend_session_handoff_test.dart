import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:trading_balance_f/core/network/backend_data_session.dart';
import 'package:trading_balance_f/core/services/background_service.dart';
import 'package:trading_balance_f/features/orders/data/trade_api_client.dart';
import 'package:trading_balance_f/features/portfolio/application/risk_monitor.dart';
import 'package:trading_balance_f/features/portfolio/application/risk_monitor_bridge.dart';
import 'package:trading_balance_f/features/portfolio/application/risk_monitor_runtime.dart';
import 'package:trading_balance_f/features/portfolio/data/risk/risk_local_store.dart';
import 'package:trading_balance_f/features/portfolio/data/risk/risk_repository.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/market_risk_engine.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_models.dart';

import 'fixtures/risk_monitor_fixtures.dart';
import 'fixtures/risk_test_fixtures.dart';

const _sessionInputProtocol = 'risk.monitor.session.input.v1';
const _sessionAckProtocol = 'risk.monitor.session.ack.v1';

void main() {
  test(
    'RED-008 Start waits for an acknowledged active session handoff',
    () async {
      final session = BackendDataSession();
      final channel = _SessionChannel();
      final owner = _CountingOwner();
      final controller = _sessionController(
        channel: channel,
        owner: owner,
        session: session,
      );
      final proxy = RiskServiceOwnerProxy(
        channel: channel,
        handshakeTimeout: const Duration(seconds: 1),
        commandCompletionTimeout: const Duration(seconds: 1),
      );

      expect(await proxy.waitForHandshake(), isTrue);
      final dynamic proxyApi = proxy;
      final handoff = proxyApi.handoffSession(_session('session-secret'));
      final startBeforeAck = proxy.dispatch(
        RiskMonitorCommand.start(id: 'session-start-before-ack'),
      );

      final handoffAck = await handoff;
      final startResult = await startBeforeAck;
      expect(handoffAck.accepted, isTrue);
      expect(startResult.status, RiskMonitorCommandStatus.rejected);
      expect(owner.dispatchCalls, 0);
      expect(session.current?.bearerToken, 'session-secret');

      final started = await proxy.dispatch(
        RiskMonitorCommand.start(id: 'session-start-after-ack'),
      );
      expect(started.accepted, isTrue);
      expect(owner.dispatchCalls, 1);
      await proxy.dispose();
      await controller.dispose();
      session.dispose();
    },
  );

  test('RED-008 service accepts only monotonic identical replays', () async {
    final session = BackendDataSession();
    final channel = _SessionChannel();
    final owner = _CountingOwner();
    final controller = _sessionController(
      channel: channel,
      owner: owner,
      session: session,
    );
    final proxy = RiskServiceOwnerProxy(
      channel: channel,
      handshakeTimeout: const Duration(seconds: 1),
    );

    expect(await proxy.waitForHandshake(), isTrue);
    final dynamic proxyApi = proxy;
    final firstSession = _session('first-secret');
    final first = await proxyApi.handoffSession(firstSession);
    expect(first.accepted, isTrue);
    expect(proxyApi.sessionGenerationWatermark, 1);

    channel.emit(
      _sessionInputProtocol,
      _sessionInput(0, _session('old-secret')),
    );
    await _flushEvents();
    expect(_lastSessionAck(channel)['accepted'], isFalse);
    expect(session.current?.bearerToken, 'first-secret');

    channel.emit(
      _sessionInputProtocol,
      _sessionInput(1, _session('other-secret')),
    );
    await _flushEvents();
    expect(_lastSessionAck(channel)['accepted'], isFalse);
    expect(session.current?.bearerToken, 'first-secret');

    channel.emit(_sessionInputProtocol, _sessionInput(1, firstSession));
    await _flushEvents();
    expect(_lastSessionAck(channel)['accepted'], isTrue);

    channel.emit(
      _sessionInputProtocol,
      _sessionInput(
        1,
        TradeSession(
          bearerToken: firstSession.bearerToken,
          accountIdentifier: firstSession.accountIdentifier,
          expiresAt: firstSession.expiresAt.add(const Duration(seconds: 1)),
        ),
      ),
    );
    await _flushEvents();
    expect(_lastSessionAck(channel)['accepted'], isFalse);
    expect(session.current?.expiresAt, firstSession.expiresAt);
    await proxy.dispose();
    await controller.dispose();
    session.dispose();
  });

  test(
    'RED-008 queued Start cannot dispatch after its handoff is revoked',
    () async {
      final session = BackendDataSession();
      final channel = _SessionChannel();
      final owner = _BlockingRefreshOwner();
      final controller = _sessionController(
        channel: channel,
        owner: owner,
        session: session,
      );
      final proxy = RiskServiceOwnerProxy(
        channel: channel,
        handshakeTimeout: const Duration(seconds: 1),
        commandCompletionTimeout: const Duration(seconds: 1),
      );

      expect(await proxy.waitForHandshake(), isTrue);
      final dynamic proxyApi = proxy;
      final activeSession = _session('queued-start-secret');
      expect((await proxyApi.handoffSession(activeSession)).accepted, isTrue);

      final blocked = proxy.dispatch(
        RiskMonitorCommand.refresh(id: 'block-service-command-tail'),
      );
      await owner.refreshEntered.future;
      final queuedStart = proxy.dispatch(
        RiskMonitorCommand.start(id: 'queued-start-from-revoked-session'),
      );

      final logout = await proxyApi.handoffSession(null);
      expect(logout.accepted, isTrue);
      owner.releaseRefresh.complete();
      await blocked;
      final result = await queuedStart;

      expect(result.status, RiskMonitorCommandStatus.rejected);
      expect(owner.startDispatches, 0);
      expect(session.current, isNull);
      await proxy.dispose();
      await controller.dispose();
      session.dispose();
    },
  );

  test(
    'RED-008 logout clears runtime state and rejects old-generation state',
    () async {
      final foregroundSession = BackendDataSession(
        initialSession: _session('foreground-session-secret'),
      );
      final serviceSession = BackendDataSession();
      final channel = _SessionChannel();
      final serviceMonitor = RiskMonitor(
        dataSource: _EmptyRiskSource(),
        persistence: FakeRiskPersistence(),
        clock: FakeRiskClock().now,
      );
      final controller = _sessionController(
        channel: channel,
        owner: serviceMonitor,
        session: serviceSession,
      );
      final foregroundMonitor = RiskMonitor(
        dataSource: _EmptyRiskSource(),
        persistence: FakeRiskPersistence(),
        clock: FakeRiskClock().now,
      );
      final platform = _SessionTestPlatform(
        channel: channel,
        session: foregroundSession,
      );
      final runtime = RiskMonitorRuntime(
        monitor: foregroundMonitor,
        platform: platform,
        backendDataSession: foregroundSession,
        lifecycle: _NoopLifecycle(),
      );

      final start = await runtime.dispatch(
        RiskMonitorCommand.start(id: 'session-ui-clearing-start'),
      );
      expect(start.accepted, isTrue);
      final proxy = platform.proxy!;
      final oldGeneration = proxy.sessionGenerationWatermark;
      final staleState = RiskMonitorWire.encodeState(
        RiskMonitorViewState(
          isRunning: true,
          accountHash: 'old-private-account-state',
          lastError: 'old private risk state',
        ),
      )..['appliedSessionGeneration'] = oldGeneration;
      channel.emit(RiskMonitorWire.state, staleState);
      await _flushEvents();
      expect(runtime.currentState.accountHash, 'old-private-account-state');

      foregroundSession.update(null);
      expect(runtime.currentState.accountHash, isNull);
      channel.emit(RiskMonitorWire.state, staleState);
      await _flushEvents();
      expect(runtime.currentState.accountHash, isNull);
      expect(runtime.currentState.lastError, isNot('old private risk state'));

      await runtime.dispose();
      await controller.dispose();
      serviceSession.dispose();
      foregroundSession.dispose();
    },
  );

  test(
    'RED-008 handshake and acknowledgements never contain the bearer',
    () async {
      final session = BackendDataSession();
      final channel = _SessionChannel();
      final controller = _sessionController(
        channel: channel,
        owner: _CountingOwner(),
        session: session,
      );
      final proxy = RiskServiceOwnerProxy(
        channel: channel,
        handshakeTimeout: const Duration(seconds: 1),
      );
      const secret = 'must-not-appear-outside-session-input';

      expect(await proxy.waitForHandshake(), isTrue);
      final dynamic proxyApi = proxy;
      await proxyApi.handoffSession(_session(secret));
      final protectedMessages = channel.sent
          .where(
            (message) =>
                message.$1 == RiskMonitorWire.handshake ||
                message.$1 == _sessionAckProtocol ||
                message.$1 == RiskMonitorWire.state,
          )
          .map((message) => jsonEncode(message.$2))
          .join('\n');
      expect(protectedMessages, isNot(contains(secret)));

      await proxy.dispose();
      await controller.dispose();
      session.dispose();
    },
  );

  test(
    'RED-008 prior-generation state is ignored before and after new ack',
    () async {
      final serviceSession = BackendDataSession();
      final channel = _SessionChannel();
      final serviceMonitor = RiskMonitor(
        dataSource: _EmptyRiskSource(),
        persistence: FakeRiskPersistence(),
        clock: FakeRiskClock().now,
      );
      final controller = _sessionController(
        channel: channel,
        owner: serviceMonitor,
        session: serviceSession,
      );
      final proxy = RiskServiceOwnerProxy(
        channel: channel,
        handshakeTimeout: const Duration(seconds: 1),
      );

      expect(await proxy.waitForHandshake(), isTrue);
      final firstAck = await proxy.handoffSession(_session('state-session-a'));
      expect(firstAck.accepted, isTrue);
      final oldGeneration = firstAck.generation;
      final oldState = RiskMonitorWire.encodeState(
        RiskMonitorViewState(
          isRunning: true,
          accountHash: 'state-from-account-a',
          lastError: 'old-session-state',
        ),
      )..['appliedSessionGeneration'] = oldGeneration;

      final secondHandoff = proxy.handoffSession(_session('state-session-b'));
      channel.emit(RiskMonitorWire.state, oldState);
      expect(proxy.currentState.accountHash, isNull);
      final secondAck = await secondHandoff;
      expect(secondAck.accepted, isTrue);
      channel.emit(RiskMonitorWire.state, oldState);
      await _flushEvents();

      expect(proxy.currentState.accountHash, isNull);
      expect(proxy.currentState.lastError, isNot('old-session-state'));
      final secondGenerationStates = channel.sent
          .where(
            (message) =>
                message.$1 == RiskMonitorWire.state &&
                message.$2['appliedSessionGeneration'] == secondAck.generation,
          )
          .map((message) => RiskMonitorWire.decodeState(message.$2));
      expect(
        secondGenerationStates.any(
          (state) => state.accountHash == 'state-from-account-a',
        ),
        isFalse,
      );

      await proxy.dispose();
      await controller.dispose();
      serviceSession.dispose();
    },
  );

  test(
    'RED-008 queued old owner state is never labeled with a new generation',
    () async {
      final serviceSession = BackendDataSession();
      final channel = _SessionChannel();
      final serviceMonitor = RiskMonitor(
        dataSource: _EmptyRiskSource(),
        persistence: FakeRiskPersistence(),
        clock: FakeRiskClock().now,
      );
      final controller = _sessionController(
        channel: channel,
        owner: serviceMonitor,
        session: serviceSession,
      );
      final proxy = RiskServiceOwnerProxy(
        channel: channel,
        handshakeTimeout: const Duration(seconds: 1),
      );
      expect(await proxy.waitForHandshake(), isTrue);
      expect(
        (await proxy.handoffSession(_session('state-owner-a'))).accepted,
        isTrue,
      );

      serviceMonitor.publishRuntimeState(
        RiskMonitorViewState(
          isRunning: true,
          accountHash: 'queued-old-owner-state',
        ),
      );
      final nextSession = proxy.handoffSession(_session('state-owner-b'));
      final nextAck = await nextSession;
      expect(nextAck.accepted, isTrue);
      await _flushEvents();

      final newGenerationStates = channel.sent
          .where(
            (message) =>
                message.$1 == RiskMonitorWire.state &&
                message.$2['appliedSessionGeneration'] == nextAck.generation,
          )
          .map((message) => RiskMonitorWire.decodeState(message.$2));
      expect(
        newGenerationStates.any(
          (state) => state.accountHash == 'queued-old-owner-state',
        ),
        isFalse,
      );

      await proxy.dispose();
      await controller.dispose();
      serviceSession.dispose();
    },
  );

  test(
    'RED-008 a recreated proxy allocates above the service watermark',
    () async {
      final session = BackendDataSession();
      final channel = _SessionChannel();
      final controller = _sessionController(
        channel: channel,
        owner: _CountingOwner(),
        session: session,
      );
      final firstProxy = RiskServiceOwnerProxy(
        channel: channel,
        handshakeTimeout: const Duration(seconds: 1),
      );
      expect(await firstProxy.waitForHandshake(), isTrue);
      final dynamic firstApi = firstProxy;
      final firstSession = _session('first-proxy-secret');
      final firstAck = await firstApi.handoffSession(firstSession);
      expect(firstAck.accepted, isTrue);
      expect(firstApi.sessionGenerationWatermark, 1);
      await firstProxy.dispose();

      final secondProxy = RiskServiceOwnerProxy(
        channel: channel,
        handshakeTimeout: const Duration(seconds: 1),
      );
      expect(await secondProxy.waitForHandshake(), isTrue);
      final dynamic secondApi = secondProxy;
      expect(secondApi.sessionGenerationWatermark, 1);
      final nextSession = _session('second-proxy-secret');
      final nextAck = await secondApi.handoffSession(nextSession);
      expect(nextAck.accepted, isTrue);
      expect(nextAck.generation, 2);
      expect(secondApi.sessionGenerationWatermark, 2);
      expect(session.current?.bearerToken, 'second-proxy-secret');

      await secondProxy.dispose();
      await controller.dispose();
      session.dispose();
    },
  );

  test(
    'RED-008 failed session acknowledgement cannot authorize Start',
    () async {
      final session = BackendDataSession();
      final channel = _SessionChannel(throwOnSessionAck: true);
      final owner = _CountingOwner();
      final controller = _sessionController(
        channel: channel,
        owner: owner,
        session: session,
      );
      final proxy = RiskServiceOwnerProxy(
        channel: channel,
        handshakeTimeout: const Duration(milliseconds: 30),
        commandCompletionTimeout: const Duration(seconds: 1),
      );

      expect(await proxy.waitForHandshake(), isTrue);
      final dynamic proxyApi = proxy;
      final handoff = await proxyApi.handoffSession(
        _session('failed-ack-secret'),
      );
      expect(handoff.accepted, isFalse);
      final result = await proxy.dispatch(
        RiskMonitorCommand.start(id: 'start-after-failed-session-ack'),
      );
      expect(result.status, RiskMonitorCommandStatus.failed);
      expect(owner.dispatchCalls, 0);

      await proxy.dispose();
      await controller.dispose();
      session.dispose();
    },
  );

  test(
    'RED-008 expiry from a stale handoff cannot expire the new session',
    () async {
      final firstSession = _session('handoff-session-a');
      final foreground = BackendDataSession(initialSession: firstSession);
      final firstGeneration = foreground.generation;
      final secondSession = _session('handoff-session-b');
      var expiryCallbacks = 0;
      final channel = _SessionChannel();
      final proxy = RiskServiceOwnerProxy(
        channel: channel,
        backendDataSession: foreground,
        onSessionExpired: () {
          expiryCallbacks++;
          foreground.update(null);
        },
        handshakeTimeout: const Duration(seconds: 1),
      );

      final handshake = proxy.waitForHandshake();
      channel.emit(RiskMonitorWire.handshake, <String, dynamic>{
        'protocol': RiskMonitorWire.handshake,
        'backgroundAvailable': true,
        'appliedSessionGeneration': 0,
      });
      expect(await handshake, isTrue);

      final handoff = proxy.handoffSession(
        firstSession,
        foregroundGeneration: firstGeneration,
      );
      final input = channel.sent
          .where((message) => message.$1 == _sessionInputProtocol)
          .last
          .$2;
      foreground.update(secondSession);
      channel.emit(_sessionAckProtocol, <String, dynamic>{
        'protocol': _sessionAckProtocol,
        'generation': input['generation'],
        'accepted': false,
        'active': false,
        'status': 'expired',
      });

      final acknowledgement = await handoff;
      expect(acknowledgement.accepted, isFalse);
      expect(expiryCallbacks, 0);
      expect(foreground.current?.bearerToken, secondSession.bearerToken);
      expect(foreground.matches(foreground.generation, secondSession), isTrue);

      await proxy.dispose();
      foreground.dispose();
    },
  );

  test(
    'RED-008 logout fences a delayed capture before it can publish',
    () async {
      final session = BackendDataSession();
      final channel = _SessionChannel();
      final source = _DelayedRiskSource();
      final persistence = FakeRiskPersistence();
      final monitor = RiskMonitor(
        dataSource: source,
        persistence: persistence,
        clock: FakeRiskClock().now,
      );
      final controller = _sessionController(
        channel: channel,
        owner: monitor,
        session: session,
      );
      final proxy = RiskServiceOwnerProxy(
        channel: channel,
        handshakeTimeout: const Duration(seconds: 1),
        commandCompletionTimeout: const Duration(seconds: 1),
      );

      expect(await proxy.waitForHandshake(), isTrue);
      final dynamic proxyApi = proxy;
      expect(
        (await proxyApi.handoffSession(_session('active-secret'))).accepted,
        isTrue,
      );
      final starting = proxy.dispatch(
        RiskMonitorCommand.start(id: 'delayed-session-start'),
      );
      await source.requestEntered.future;

      final logout = await proxyApi.handoffSession(null);
      expect(logout.accepted, isTrue);
      expect(monitor.currentState.isRunning, isFalse);
      source.positionResult.complete(
        RiskPositionSelection(
          status: RiskEligibility.eligible,
          quality: RiskQuality.complete(
            source: 'delayed-session-test',
            observedAt: riskTestNow,
            sourceAt: riskTestNow,
          ),
          position: syntheticRiskPosition(observedAt: riskTestNow),
        ),
      );
      await starting;

      expect(source.marketCalls, 0);
      expect(persistence.saveEpisodeCalls, 0);
      expect(monitor.currentState.positions, isEmpty);
      expect(session.current, isNull);
      await proxy.dispose();
      await controller.dispose();
    },
  );

  test(
    'RED-008 active service state is cleared immediately on foreground logout',
    () async {
      final foregroundSession = BackendDataSession(
        initialSession: _session('foreground-runtime-session'),
      );
      final serviceSession = BackendDataSession();
      final channel = _SessionChannel();
      final serviceMonitor = RiskMonitor(
        dataSource: _EmptyRiskSource(),
        persistence: FakeRiskPersistence(),
        clock: FakeRiskClock().now,
      );
      final controller = _sessionController(
        channel: channel,
        owner: serviceMonitor,
        session: serviceSession,
      );
      final runtime = RiskMonitorRuntime(
        monitor: RiskMonitor(
          dataSource: _EmptyRiskSource(),
          persistence: FakeRiskPersistence(),
          clock: FakeRiskClock().now,
        ),
        platform: _SessionTestPlatform(
          channel: channel,
          session: foregroundSession,
        ),
        backendDataSession: foregroundSession,
        lifecycle: _NoopLifecycle(),
      );

      expect(
        (await runtime.dispatch(
          RiskMonitorCommand.start(id: 'runtime-private-state-start'),
        )).accepted,
        isTrue,
      );
      final proxy = (runtime.platform as _SessionTestPlatform).proxy!;
      final activeGeneration = proxy.sessionGenerationWatermark;
      final oldState = RiskMonitorWire.encodeState(
        RiskMonitorViewState(
          isRunning: true,
          accountHash: 'private-account-a-state',
          lastError: 'private old session state',
        ),
      )..['appliedSessionGeneration'] = activeGeneration;
      channel.emit(RiskMonitorWire.state, oldState);
      await _flushEvents();
      expect(runtime.currentState.accountHash, 'private-account-a-state');

      foregroundSession.update(null);
      expect(runtime.currentState.accountHash, isNull);
      channel.emit(RiskMonitorWire.state, oldState);
      await _flushEvents();
      expect(runtime.currentState.accountHash, isNull);
      expect(
        runtime.currentState.lastError,
        isNot('private old session state'),
      );
      channel.emit(RiskMonitorWire.state, oldState);
      await _flushEvents();
      expect(runtime.currentState.accountHash, isNull);

      await runtime.dispose();
      await controller.dispose();
      serviceSession.dispose();
      foregroundSession.dispose();
    },
  );
}

RiskServiceOwnerController _sessionController({
  required RiskServiceChannel channel,
  required RiskMonitorOwner owner,
  required BackendDataSession session,
}) =>
    Function.apply(
          RiskServiceOwnerController.new,
          const <Object?>[],
          <Symbol, Object?>{
            #channel: channel,
            #owner: owner,
            #backendDataSession: session,
          },
        )
        as RiskServiceOwnerController;

TradeSession _session(String token) => TradeSession(
  bearerToken: token,
  accountIdentifier: 'risk-test-account',
  expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
);

Map<String, dynamic> _sessionInput(int generation, TradeSession session) =>
    <String, dynamic>{
      'protocol': _sessionInputProtocol,
      'generation': generation,
      'active': true,
      'token': session.bearerToken,
      'accountIdentifier': session.accountIdentifier,
      'expiresAt': session.expiresAt.toIso8601String(),
    };

Map<String, dynamic> _lastSessionAck(_SessionChannel channel) =>
    channel.sent.where((message) => message.$1 == _sessionAckProtocol).last.$2;

Future<void> _flushEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _SessionChannel implements RiskServiceChannel {
  _SessionChannel({this.throwOnSessionAck = false});

  final bool throwOnSessionAck;
  final Map<String, StreamController<Map<String, dynamic>?>> _streams =
      <String, StreamController<Map<String, dynamic>?>>{};
  final List<(String, Map<String, dynamic>)> sent =
      <(String, Map<String, dynamic>)>[];

  StreamController<Map<String, dynamic>?> _stream(String method) =>
      _streams.putIfAbsent(
        method,
        () => StreamController<Map<String, dynamic>?>.broadcast(sync: true),
      );

  @override
  Stream<Map<String, dynamic>?> on(String method) => _stream(method).stream;

  @override
  void invoke(String method, [Map<String, dynamic>? arguments]) {
    if (method == 'stopService') return;
    if (throwOnSessionAck && method == _sessionAckProtocol) {
      throw StateError('session acknowledgement transport failed');
    }
    final payload = arguments ?? <String, dynamic>{};
    sent.add((method, payload));
    _stream(method).add(payload);
  }

  void emit(String method, Map<String, dynamic> payload) =>
      _stream(method).add(payload);
}

class _CountingOwner extends InMemoryRiskMonitorOwner {
  int dispatchCalls = 0;

  @override
  Future<RiskMonitorCommandResult> dispatch(RiskMonitorCommand command) {
    dispatchCalls++;
    return super.dispatch(command);
  }
}

class _BlockingRefreshOwner extends InMemoryRiskMonitorOwner {
  final Completer<void> refreshEntered = Completer<void>();
  final Completer<void> releaseRefresh = Completer<void>();
  int startDispatches = 0;

  @override
  Future<RiskMonitorCommandResult> dispatch(RiskMonitorCommand command) async {
    if (command.type == RiskMonitorCommandType.refresh) {
      if (!refreshEntered.isCompleted) refreshEntered.complete();
      await releaseRefresh.future;
    }
    if (command.type == RiskMonitorCommandType.start) startDispatches++;
    return super.dispatch(command);
  }
}

class _EmptyRiskSource implements RiskMonitorDataSource {
  @override
  Future<RiskPositionSelection> loadPosition({
    String? selectedPositionId,
    String? selectedEpisodeKey,
  }) async => const RiskPositionSelection(
    status: RiskEligibility.empty,
    quality: RiskQuality.complete(source: 'backend-session-test'),
  );

  @override
  Future<MarketRiskSnapshot> loadMarket({
    required RiskPosition position,
    DateTime? now,
  }) async => syntheticMarketSnapshot(now ?? riskTestNow);
}

class _SessionTestPlatform implements RiskRuntimePlatformAdapter {
  _SessionTestPlatform({required this.channel, required this.session});

  final RiskServiceChannel channel;
  final BackendDataSession session;
  RiskServiceOwnerProxy? proxy;
  final StreamController<void> _reconnects = StreamController<void>.broadcast();

  @override
  RiskRuntimePlatformKind get kind => RiskRuntimePlatformKind.android;

  @override
  Stream<void> get reconnects => _reconnects.stream;

  @override
  Future<RiskRuntimeOwnership> acquireOwnership() async {
    final current = session.current;
    if (current == null) {
      return const RiskRuntimeOwnership.unavailable(
        reason: 'Vui lòng đăng nhập.',
      );
    }
    final owner = RiskServiceOwnerProxy(
      channel: channel,
      handshakeTimeout: const Duration(seconds: 1),
      commandCompletionTimeout: const Duration(seconds: 1),
    );
    proxy = owner;
    if (!await owner.waitForHandshake()) {
      await owner.dispose();
      return const RiskRuntimeOwnership.unavailable();
    }
    final handoff = await owner.handoffSession(
      current,
      foregroundGeneration: session.generation,
    );
    if (!handoff.accepted ||
        !handoff.active ||
        !session.matches(session.generation, current)) {
      await owner.dispose();
      return const RiskRuntimeOwnership.unavailable(
        reason: 'Phiên giao dịch đã thay đổi.',
      );
    }
    return RiskRuntimeOwnership(
      granted: true,
      ownerLabel: 'android-service',
      backgroundAvailable: true,
      owner: owner,
    );
  }

  @override
  Future<void> releaseOwnership() async {
    await proxy?.dispose();
    proxy = null;
  }
}

class _NoopLifecycle implements RiskLifecycleAdapter {
  @override
  Stream<AppLifecycleState> get changes =>
      const Stream<AppLifecycleState>.empty();

  @override
  Future<void> dispose() async {}
}

class _DelayedRiskSource implements RiskMonitorDataSource {
  final Completer<void> requestEntered = Completer<void>();
  final Completer<RiskPositionSelection> positionResult =
      Completer<RiskPositionSelection>();
  int marketCalls = 0;

  @override
  Future<RiskPositionSelection> loadPosition({
    String? selectedPositionId,
    String? selectedEpisodeKey,
  }) {
    if (!requestEntered.isCompleted) requestEntered.complete();
    return positionResult.future;
  }

  @override
  Future<MarketRiskSnapshot> loadMarket({
    required RiskPosition position,
    DateTime? now,
  }) async {
    marketCalls++;
    return syntheticMarketSnapshot(now ?? riskTestNow);
  }
}
