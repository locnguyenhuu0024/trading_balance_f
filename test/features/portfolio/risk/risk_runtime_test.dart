import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:trading_balance_f/core/services/background_service.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/features/portfolio/application/risk_monitor.dart';
import 'package:trading_balance_f/features/portfolio/application/risk_monitor_bridge.dart';
import 'package:trading_balance_f/features/portfolio/application/risk_notification_sink.dart';
import 'package:trading_balance_f/features/portfolio/application/risk_monitor_runtime.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/action_plan.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_events.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_history.dart';
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
    'GREEN-005 aggregate monitor state survives the service controller/proxy wire',
    () async {
      final clock = FakeRiskClock();
      var mark = 10.0;
      RiskPosition position(String coin, String id) => syntheticRiskPosition(
        observedAt: clock.value,
        instrumentId: '$coin-USDT',
        baseCurrency: coin,
        positionId: id,
        markPrice: mark,
      );
      final source = BatchFakeRiskSource(
        clock: clock,
        positions: <RiskPosition>[
          position('BTC', 'position-btc'),
          position('ETH', 'position-eth'),
          position('SUI', 'position-sui'),
        ],
      );
      final monitor = RiskMonitor(
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
      );

      expect(await proxy.waitForHandshake(), isTrue);
      final started = await proxy.dispatch(
        RiskMonitorCommand.start(id: 'aggregate-wire-start'),
      );
      expect(started.accepted, isTrue);
      expect(monitor.currentState.positions, hasLength(3));
      expect(proxy.currentState.positions, hasLength(3));
      expect(
        proxy.currentState.positions.map((entry) => entry.episodeKey),
        orderedEquals(
          monitor.currentState.positions.map((entry) => entry.episodeKey),
        ),
      );
      expect(
        proxy.currentState.positions.map((entry) => entry.direction),
        orderedEquals(
          monitor.currentState.positions.map((entry) => entry.direction),
        ),
      );
      expect(
        proxy.currentState.requestStatus,
        monitor.currentState.requestStatus,
      );

      mark = 8;
      source.positions = <RiskPosition>[
        position('BTC', 'position-btc'),
        position('ETH', 'position-eth'),
        position('SUI', 'position-sui'),
      ];
      clock.advance(const Duration(minutes: 1));
      final refreshed = await proxy.dispatch(
        RiskMonitorCommand.refresh(id: 'aggregate-wire-refresh'),
      );
      expect(refreshed.accepted, isTrue);
      final original = monitor.currentState;
      expect(original.positions, hasLength(3));
      for (final entry in original.positions) {
        expect(entry.samples, hasLength(greaterThanOrEqualTo(2)));
      }

      // Publish a populated aggregate state after the real monitor capture so
      // the controller/proxy path is tested with every nested field that a
      // position entry can carry, not only the fields produced by the basic
      // fixture.
      final hydrated = <RiskPositionMonitorViewState>[];
      for (var index = 0; index < original.positions.length; index++) {
        final expected = original.positions[index];
        final at = clock.value;
        final rule = RiskRule(
          id: 'proxy-rule-$index',
          episodeKey: expected.episodeKey,
          metric: RiskPlanMetric.markPrice,
          comparison: RiskPlanComparison.greaterThan,
          threshold: 9,
          title: 'Proxy rule $index',
          note: 'wire rule',
          createdAt: at,
          updatedAt: at,
        );
        final zone = RiskZone(
          id: 'proxy-zone-$index',
          episodeKey: expected.episodeKey,
          title: 'Proxy zone $index',
          lowerPrice: 7,
          upperPrice: 9,
          note: 'wire zone',
          createdAt: at,
          updatedAt: at,
        );
        final plan = RiskPlan(
          episodeKey: expected.episodeKey,
          rules: <RiskRule>[rule],
          zones: <RiskZone>[zone],
        );
        final planEvaluation = RiskPlanEvaluation(
          rules: <RiskRuleEvaluation>[
            RiskRuleEvaluation(
              rule: rule,
              state: RiskRuleState.active,
              value: expected.evaluation?.metrics.markPrice.value,
              referenceValue: 9,
              reason: 'proxy rule evaluation',
            ),
          ],
          zones: <RiskZoneEvaluation>[
            RiskZoneEvaluation(
              zone: zone,
              state: RiskRuleState.active,
              markPrice: expected.evaluation?.metrics.markPrice.value,
              reason: 'proxy zone evaluation',
            ),
          ],
          evaluatedAt: at,
        );
        final settings = (expected.settings ?? const RiskSettings()).copyWith(
          customStressChanges: <double>[-0.1, 0.1 + index / 100],
          customStressPrices: <double>[8.0 + index],
          summaryHour: 7 + index,
          summaryMinute: 30,
        );
        final sample = expected.samples.last;
        final summary = RiskDailySummary(
          episodeKey: expected.episodeKey,
          dateKey: '2026-09-10',
          timeZone: 'UTC',
          capturedAt: at,
          quality: expected.quality,
          overallState: sample.overallState,
          positionState: sample.positionState,
          marketState: sample.marketState,
          recoveryState: sample.recoveryState,
          buffer: sample.buffer,
          effectiveLeverage: sample.effectiveLeverage,
          actualInterestToday: sample.actualInterestToday,
          knownInterestToday: sample.knownInterestToday,
          actualInterestQuality: sample.actualInterestQuality,
          interestCoverageComplete: sample.interestCoverageComplete,
          majorChange: 'proxy summary $index',
          activeRuleCount: 1,
          unknownRuleCount: 0,
        );
        final comparison = RiskSessionComparison(
          baseline: expected.samples.first,
          current: expected.samples.last,
          bufferDeltaPoints: 1.25 + index,
          leverageDelta: 0.5 + index,
          debtDelta: 2.0 + index,
          trueExitChanged: true,
          structureChanged: true,
          fundingChanged: true,
          openInterestChanged: true,
          overallChanged: true,
          positionChanged: true,
        );
        final event = RiskEvent(
          id: 'proxy-event-$index',
          episodeKey: expected.episodeKey,
          kind: RiskEventKind.stateChange,
          message: 'proxy event $index',
          createdAt: at,
          observedAt: at,
          factorId: 'proxy-factor-$index',
          severity: RiskSeverity.watch,
          source: 'proxy-test',
          previousValue: 10,
          currentValue: 8,
          policyVersion: 'proxy.v1',
          quality: expected.quality,
        );
        hydrated.add(
          expected.copyWith(
            plan: plan,
            planEvaluation: planEvaluation,
            settings: settings,
            summaries: <RiskDailySummary>[summary],
            previousCheck: comparison,
            events: <RiskEvent>[...expected.events, event],
            unsaved: index == 0,
            lastError: index == 0 ? 'proxy row error' : null,
            clearError: index != 0,
            freshnessAt: at,
          ),
        );
      }
      final populated = original.copyWith(
        episodeKey: hydrated.first.episodeKey,
        evaluation: hydrated.first.evaluation,
        planEvaluation: hydrated.first.planEvaluation,
        plan: hydrated.first.plan,
        settings: hydrated.first.settings,
        market: hydrated.first.market,
        samples: hydrated.first.samples,
        summaries: hydrated.first.summaries,
        previousCheck: hydrated.first.previousCheck,
        trend: hydrated.first.trend,
        velocity: hydrated.first.velocity,
        events: hydrated.first.events,
        quality: hydrated.first.quality,
        unsaved: hydrated.first.unsaved,
        lastError: hydrated.first.lastError,
        positions: hydrated,
      );
      monitor.publishRuntimeState(populated);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final expectedState = monitor.currentState;
      final received = proxy.currentState;
      expect(received.positions, hasLength(expectedState.positions.length));
      expect(
        received.positions.map((entry) => entry.positionId),
        orderedEquals(expectedState.positions.map((entry) => entry.positionId)),
      );
      expect(
        received.positions.map((entry) => entry.direction),
        orderedEquals(expectedState.positions.map((entry) => entry.direction)),
      );

      void expectQuality(RiskQuality actual, RiskQuality expected) {
        expect(actual.status, expected.status);
        expect(actual.source, expected.source);
        expect(actual.reason, expected.reason);
        expect(actual.observedAt, expected.observedAt);
        expect(actual.sourceAt, expected.sourceAt);
      }

      void expectReason(RiskReason actual, RiskReason expected) {
        expect(actual.factorId, expected.factorId);
        expect(actual.message, expected.message);
        expect(actual.severity, expected.severity);
        expect(actual.observedValue, expected.observedValue);
        expect(actual.threshold, expected.threshold);
        expect(actual.unit, expected.unit);
        expect(actual.window, expected.window);
        expect(actual.observedAt, expected.observedAt);
        expect(actual.source, expected.source);
        expect(actual.evidence, expected.evidence);
      }

      void expectReasons(List<RiskReason> actual, List<RiskReason> expected) {
        expect(actual, hasLength(expected.length));
        for (var index = 0; index < expected.length; index++) {
          expectReason(actual[index], expected[index]);
        }
      }

      void expectAssessment(RiskAssessment actual, RiskAssessment expected) {
        expect(actual.state, expected.state);
        expect(actual.label, expected.label);
        expect(actual.missingReasons, orderedEquals(expected.missingReasons));
        expectQuality(actual.quality, expected.quality);
        expectReasons(actual.reasons, expected.reasons);
      }

      void expectMetric(RiskMetricValue actual, RiskMetricValue expected) {
        expect(actual.value, expected.value);
        expect(actual.unit, expected.unit);
        expect(actual.source, expected.source);
        expect(actual.observedAt, expected.observedAt);
        expect(actual.sourceAt, expected.sourceAt);
        expectQuality(actual.quality, expected.quality);
      }

      void expectPosition(RiskPosition actual, RiskPosition expected) {
        expect(actual.instrumentId, expected.instrumentId);
        expect(actual.instrumentType, expected.instrumentType);
        expect(actual.mode, expected.mode);
        expect(actual.collateralCurrency, expected.collateralCurrency);
        expect(actual.positionSide, expected.positionSide);
        expect(actual.accountNamespace, expected.accountNamespace);
        expect(actual.positionId, expected.positionId);
        expect(actual.createdAt, expected.createdAt);
        expect(actual.updatedAt, expected.updatedAt);
        expect(actual.observedAt, expected.observedAt);
        expect(actual.baseCurrency, expected.baseCurrency);
        expect(actual.quoteCurrency, expected.quoteCurrency);
        expect(actual.positionCurrency, expected.positionCurrency);
        expect(actual.accountCurrency, expected.accountCurrency);
        expect(actual.liabilityCurrency, expected.liabilityCurrency);
        expect(actual.rawQuantity, expected.rawQuantity);
        expect(actual.quantity, expected.quantity);
        expect(actual.margin, expected.margin);
        expect(actual.markPrice, expected.markPrice);
        expect(actual.entryPrice, expected.entryPrice);
        expect(actual.liquidationPrice, expected.liquidationPrice);
        expect(actual.unrealizedPnl, expected.unrealizedPnl);
        expect(actual.reportedLeverage, expected.reportedLeverage);
        expect(actual.marginRatio, expected.marginRatio);
        expect(actual.maintenanceRequirement, expected.maintenanceRequirement);
        expect(actual.reportedLiability, expected.reportedLiability);
        expect(actual.reportedInterest, expected.reportedInterest);
        expect(actual.baseBalance, expected.baseBalance);
        expect(actual.quoteBalance, expected.quoteBalance);
        expect(actual.baseBorrowed, expected.baseBorrowed);
        expect(actual.quoteBorrowed, expected.quoteBorrowed);
        expect(actual.baseInterest, expected.baseInterest);
        expect(actual.quoteInterest, expected.quoteInterest);
        expect(actual.hourlyBorrowRate, expected.hourlyBorrowRate);
        expect(actual.entryFeeRate, expected.entryFeeRate);
        expect(actual.exitFeeRate, expected.exitFeeRate);
        expectQuality(actual.quality, expected.quality);
        expect(actual.eligibility, expected.eligibility);
        expect(actual.source, expected.source);
        expect(
          actual.costAttribution.settledInterest,
          expected.costAttribution.settledInterest,
        );
        expect(
          actual.costAttribution.unbilledInterest,
          expected.costAttribution.unbilledInterest,
        );
        expect(
          actual.costAttribution.additionalActualCosts,
          expected.costAttribution.additionalActualCosts,
        );
        expect(
          actual.costAttribution.observedAt,
          expected.costAttribution.observedAt,
        );
        expect(actual.costAttribution.source, expected.costAttribution.source);
        expect(
          actual.costAttribution.coverage.complete,
          expected.costAttribution.coverage.complete,
        );
        expect(
          actual.costAttribution.coverage.reason,
          expected.costAttribution.coverage.reason,
        );
        expect(
          actual.costAttribution.coverage.ledgerComplete,
          expected.costAttribution.coverage.ledgerComplete,
        );
        expect(
          actual.costAttribution.coverage.sizeUnchanged,
          expected.costAttribution.coverage.sizeUnchanged,
        );
        expect(
          actual.costAttribution.coverage.positionOpenedAt,
          expected.costAttribution.coverage.positionOpenedAt,
        );
        expect(
          actual.costAttribution.coverage.coverageFrom,
          expected.costAttribution.coverage.coverageFrom,
        );
        expect(
          actual.costAttribution.coverage.coverageTo,
          expected.costAttribution.coverage.coverageTo,
        );
        expect(
          actual.costAttribution.coverage.nonOverlapAt,
          expected.costAttribution.coverage.nonOverlapAt,
        );
        final actualInterest = actual.costAttribution.actualInterestToday;
        final expectedInterest = expected.costAttribution.actualInterestToday;
        expect(actualInterest == null, expectedInterest == null);
        if (actualInterest != null && expectedInterest != null) {
          expect(actualInterest.amount, expectedInterest.amount);
          expect(actualInterest.knownSubtotal, expectedInterest.knownSubtotal);
          expect(actualInterest.windowStart, expectedInterest.windowStart);
          expect(actualInterest.windowEnd, expectedInterest.windowEnd);
          expect(
            actualInterest.coverageComplete,
            expectedInterest.coverageComplete,
          );
          expect(actualInterest.observedAt, expectedInterest.observedAt);
          expect(actualInterest.sourceAt, expectedInterest.sourceAt);
          expect(actualInterest.source, expectedInterest.source);
          expectQuality(actualInterest.quality, expectedInterest.quality);
        }
      }

      void expectMarket(RiskMarketInput actual, RiskMarketInput expected) {
        expect(actual.state, expected.state);
        expect(actual.complete, expected.complete);
        expect(actual.dailyVolatility, expected.dailyVolatility);
        expectReasons(actual.reasons, expected.reasons);
        expect(actual.missingReasons, orderedEquals(expected.missingReasons));
        expect(actual.support, expected.support);
        expect(actual.resistance, expected.resistance);
        expect(actual.source, expected.source);
        expect(actual.observedAt, expected.observedAt);
        expect(actual.sourceAt, expected.sourceAt);
        expect(actual.marketContextLabel, expected.marketContextLabel);
        expect(actual.assetInstrument, expected.assetInstrument);
        expect(actual.btcInstrument, expected.btcInstrument);
        expect(actual.derivativesInstrument, expected.derivativesInstrument);
        expect(actual.volatilityLabel, expected.volatilityLabel);
        expect(actual.assetStructureLabel, expected.assetStructureLabel);
        expect(actual.btcStructureLabel, expected.btcStructureLabel);
        expect(actual.volumePressureLabel, expected.volumePressureLabel);
        expect(actual.fundingLabel, expected.fundingLabel);
        expect(actual.openInterestLabel, expected.openInterestLabel);
        expect(actual.normalizedFunding8h, expected.normalizedFunding8h);
        expect(actual.fundingIntervalHours, expected.fundingIntervalHours);
        expect(actual.openInterestChange, expected.openInterestChange);
        expect(actual.marketPriceChange, expected.marketPriceChange);
        expect(actual.marketPoints, expected.marketPoints);
        expect(actual.assetPoints, expected.assetPoints);
        expect(actual.fundingPoints, expected.fundingPoints);
        expect(actual.openInterestPoints, expected.openInterestPoints);
        final actualFundingQuality = actual.fundingQuality;
        final expectedFundingQuality = expected.fundingQuality;
        expect(actualFundingQuality == null, expectedFundingQuality == null);
        if (actualFundingQuality != null && expectedFundingQuality != null) {
          expectQuality(actualFundingQuality, expectedFundingQuality);
        }
        final actualOiQuality = actual.openInterestQuality;
        final expectedOiQuality = expected.openInterestQuality;
        expect(actualOiQuality == null, expectedOiQuality == null);
        if (actualOiQuality != null && expectedOiQuality != null) {
          expectQuality(actualOiQuality, expectedOiQuality);
        }
      }

      void expectSample(RiskHistorySample actual, RiskHistorySample expected) {
        expect(actual.episodeKey, expected.episodeKey);
        expect(actual.observedAt, expected.observedAt);
        expectQuality(actual.quality, expected.quality);
        expect(actual.overallState, expected.overallState);
        expect(actual.positionState, expected.positionState);
        expect(actual.marketState, expected.marketState);
        expect(actual.recoveryState, expected.recoveryState);
        expect(actual.markPrice, expected.markPrice);
        expect(actual.buffer, expected.buffer);
        expect(actual.effectiveLeverage, expected.effectiveLeverage);
        expect(actual.debt, expected.debt);
        expect(actual.marginRatio, expected.marginRatio);
        expect(actual.trueExit, expected.trueExit);
        expect(actual.trueExitVerified, expected.trueExitVerified);
        expect(actual.entryPrice, expected.entryPrice);
        expect(actual.entryFeeRate, expected.entryFeeRate);
        expect(actual.exitFeeRate, expected.exitFeeRate);
        expect(actual.actualInterestToday, expected.actualInterestToday);
        expect(actual.knownInterestToday, expected.knownInterestToday);
        final actualInterestQuality = actual.actualInterestQuality;
        final expectedInterestQuality = expected.actualInterestQuality;
        expect(actualInterestQuality == null, expectedInterestQuality == null);
        if (actualInterestQuality != null && expectedInterestQuality != null) {
          expectQuality(actualInterestQuality, expectedInterestQuality);
        }
        expect(
          actual.interestCoverageComplete,
          expected.interestCoverageComplete,
        );
        expect(actual.quantity, expected.quantity);
        expect(actual.margin, expected.margin);
        expect(actual.assetStructureLabel, expected.assetStructureLabel);
        expect(actual.fundingLabel, expected.fundingLabel);
        expect(actual.openInterestChange, expected.openInterestChange);
        expect(actual.policyVersion, expected.policyVersion);
        expect(actual.activeFactorIds, orderedEquals(expected.activeFactorIds));
        expect(actual.source, expected.source);
      }

      void expectEvent(RiskEvent actual, RiskEvent expected) {
        expect(actual.id, expected.id);
        expect(actual.episodeKey, expected.episodeKey);
        expect(actual.kind, expected.kind);
        expect(actual.message, expected.message);
        expect(actual.createdAt, expected.createdAt);
        expect(actual.observedAt, expected.observedAt);
        expect(actual.factorId, expected.factorId);
        expect(actual.severity, expected.severity);
        expect(actual.source, expected.source);
        expect(actual.previousValue, expected.previousValue);
        expect(actual.currentValue, expected.currentValue);
        expect(actual.policyVersion, expected.policyVersion);
        final actualQuality = actual.quality;
        final expectedQuality = expected.quality;
        expect(actualQuality == null, expectedQuality == null);
        if (actualQuality != null && expectedQuality != null) {
          expectQuality(actualQuality, expectedQuality);
        }
        expect(actual.contributions, hasLength(expected.contributions.length));
        for (var index = 0; index < expected.contributions.length; index++) {
          final actualContribution = actual.contributions[index];
          final expectedContribution = expected.contributions[index];
          expect(actualContribution.id, expectedContribution.id);
          expect(actualContribution.kind, expectedContribution.kind);
          expect(actualContribution.factorId, expectedContribution.factorId);
          expect(actualContribution.message, expectedContribution.message);
          expect(actualContribution.createdAt, expectedContribution.createdAt);
          expect(
            actualContribution.observedAt,
            expectedContribution.observedAt,
          );
          expect(actualContribution.severity, expectedContribution.severity);
          expect(actualContribution.source, expectedContribution.source);
          expect(
            actualContribution.previousValue,
            expectedContribution.previousValue,
          );
          expect(
            actualContribution.currentValue,
            expectedContribution.currentValue,
          );
        }
      }

      void expectEntryParity(
        RiskPositionMonitorViewState actual,
        RiskPositionMonitorViewState expected,
      ) {
        expect(actual.positionId, expected.positionId);
        expect(actual.episodeKey, expected.episodeKey);
        expect(actual.positionSide, expected.positionSide);
        expect(actual.direction, expected.direction);
        expect(actual.position, isNotNull);
        expectPosition(actual.position!, expected.position!);

        final actualEvaluation = actual.evaluation;
        final expectedEvaluation = expected.evaluation;
        expect(actualEvaluation == null, expectedEvaluation == null);
        if (actualEvaluation != null && expectedEvaluation != null) {
          expectPosition(
            actualEvaluation.position,
            expectedEvaluation.position,
          );
          expect(
            actualEvaluation.overallState,
            expectedEvaluation.overallState,
          );
          expect(
            actualEvaluation.policyVersion,
            expectedEvaluation.policyVersion,
          );
          expect(
            actualEvaluation.exchangePnlBasis,
            expectedEvaluation.exchangePnlBasis,
          );
          expect(
            actualEvaluation.missingReasons,
            orderedEquals(expectedEvaluation.missingReasons),
          );
          expectQuality(actualEvaluation.quality, expectedEvaluation.quality);
          expectReasons(actualEvaluation.reasons, expectedEvaluation.reasons);
          expectAssessment(
            actualEvaluation.positionAssessment,
            expectedEvaluation.positionAssessment,
          );
          expectAssessment(
            actualEvaluation.marketAssessment,
            expectedEvaluation.marketAssessment,
          );
          expectAssessment(
            actualEvaluation.recoveryAssessment,
            expectedEvaluation.recoveryAssessment,
          );
          final actualMetrics = actualEvaluation.metrics;
          final expectedMetrics = expectedEvaluation.metrics;
          expectMetric(actualMetrics.quantity, expectedMetrics.quantity);
          expectMetric(actualMetrics.markPrice, expectedMetrics.markPrice);
          expectMetric(actualMetrics.entryPrice, expectedMetrics.entryPrice);
          expectMetric(
            actualMetrics.liquidationPrice,
            expectedMetrics.liquidationPrice,
          );
          expectMetric(actualMetrics.margin, expectedMetrics.margin);
          expectMetric(actualMetrics.equity, expectedMetrics.equity);
          expectMetric(actualMetrics.debt, expectedMetrics.debt);
          expectMetric(
            actualMetrics.principalDebt,
            expectedMetrics.principalDebt,
          );
          expectMetric(
            actualMetrics.tradeNotional,
            expectedMetrics.tradeNotional,
          );
          expectMetric(
            actualMetrics.grossAssetExposure,
            expectedMetrics.grossAssetExposure,
          );
          expectMetric(
            actualMetrics.effectiveLeverage,
            expectedMetrics.effectiveLeverage,
          );
          expectMetric(actualMetrics.buffer, expectedMetrics.buffer);
          expectMetric(actualMetrics.marginRatio, expectedMetrics.marginRatio);
          expectMetric(
            actualMetrics.maintenanceRequirement,
            expectedMetrics.maintenanceRequirement,
          );
          expectMetric(
            actualMetrics.tradeSensitivityPerPoint,
            expectedMetrics.tradeSensitivityPerPoint,
          );
          expectMetric(
            actualMetrics.tradeSensitivityPerPercent,
            expectedMetrics.tradeSensitivityPerPercent,
          );
          expectMetric(
            actualMetrics.equitySensitivityPerPoint,
            expectedMetrics.equitySensitivityPerPoint,
          );
          expectMetric(
            actualMetrics.equitySensitivityPerPercent,
            expectedMetrics.equitySensitivityPerPercent,
          );
          expectMetric(
            actualMetrics.distanceToEntry,
            expectedMetrics.distanceToEntry,
          );
          expectMetric(
            actualMetrics.distanceToTrueExit,
            expectedMetrics.distanceToTrueExit,
          );
          expectMetric(
            actualMetrics.actualInterestToday,
            expectedMetrics.actualInterestToday,
          );
          expectMetric(
            actualMetrics.knownInterestToday,
            expectedMetrics.knownInterestToday,
          );
          expectMetric(
            actualMetrics.trueExitPrice,
            expectedMetrics.trueExitPrice,
          );
          expectMetric(
            actualMetrics.projectedTrueExitPrice,
            expectedMetrics.projectedTrueExitPrice,
          );
          expectMetric(
            actualMetrics.knownCostExitPrice,
            expectedMetrics.knownCostExitPrice,
          );
          expectMetric(
            actualMetrics.holdingCostPerDay,
            expectedMetrics.holdingCostPerDay,
          );
          expectMetric(
            actualMetrics.holdingCost7d,
            expectedMetrics.holdingCost7d,
          );
          expectMetric(
            actualMetrics.holdingCost30d,
            expectedMetrics.holdingCost30d,
          );
          expectMetric(
            actualMetrics.recoveryDistance,
            expectedMetrics.recoveryDistance,
          );
          expectMetric(
            actualMetrics.holdingBurden,
            expectedMetrics.holdingBurden,
          );
          expectMetric(actualMetrics.tradePnl, expectedMetrics.tradePnl);
          expect(
            actualEvaluation.stressScenarios,
            hasLength(expectedEvaluation.stressScenarios.length),
          );
          for (
            var index = 0;
            index < expectedEvaluation.stressScenarios.length;
            index++
          ) {
            final actualStress = actualEvaluation.stressScenarios[index];
            final expectedStress = expectedEvaluation.stressScenarios[index];
            expect(actualStress.label, expectedStress.label);
            expect(actualStress.price, expectedStress.price);
            expect(
              actualStress.percentageChange,
              expectedStress.percentageChange,
            );
            expect(actualStress.tradePnl, expectedStress.tradePnl);
            expect(actualStress.equity, expectedStress.equity);
            expect(
              actualStress.effectiveLeverage,
              expectedStress.effectiveLeverage,
            );
            expect(actualStress.buffer, expectedStress.buffer);
            expect(actualStress.marginRatio, expectedStress.marginRatio);
            expect(
              actualStress.currentMarginRatio,
              expectedStress.currentMarginRatio,
            );
            expect(actualStress.marketFrozen, expectedStress.marketFrozen);
            expect(
              actualStress.marketContextLabel,
              expectedStress.marketContextLabel,
            );
            expect(actualStress.positionState, expectedStress.positionState);
            expect(actualStress.overallState, expectedStress.overallState);
            expect(actualStress.partial, expectedStress.partial);
            expect(actualStress.hypothetical, expectedStress.hypothetical);
            expectReasons(actualStress.reasons, expectedStress.reasons);
          }
          expect(
            actualEvaluation.priceMap,
            hasLength(expectedEvaluation.priceMap.length),
          );
          for (
            var index = 0;
            index < expectedEvaluation.priceMap.length;
            index++
          ) {
            expect(
              actualEvaluation.priceMap[index].price,
              expectedEvaluation.priceMap[index].price,
            );
            expect(
              actualEvaluation.priceMap[index].labels,
              orderedEquals(expectedEvaluation.priceMap[index].labels),
            );
          }
          expect(actualEvaluation.evaluatedAt, expectedEvaluation.evaluatedAt);
        }

        final actualPlan = actual.plan;
        final expectedPlan = expected.plan;
        expect(actualPlan == null, expectedPlan == null);
        if (actualPlan != null && expectedPlan != null) {
          expect(actualPlan.episodeKey, expectedPlan.episodeKey);
          expect(actualPlan.rules, hasLength(expectedPlan.rules.length));
          for (var index = 0; index < expectedPlan.rules.length; index++) {
            final actualRule = actualPlan.rules[index];
            final expectedRule = expectedPlan.rules[index];
            expect(actualRule.id, expectedRule.id);
            expect(actualRule.episodeKey, expectedRule.episodeKey);
            expect(actualRule.enabled, expectedRule.enabled);
            expect(actualRule.metric, expectedRule.metric);
            expect(actualRule.comparison, expectedRule.comparison);
            expect(actualRule.threshold, expectedRule.threshold);
            expect(actualRule.upperThreshold, expectedRule.upperThreshold);
            expect(actualRule.title, expectedRule.title);
            expect(actualRule.label, expectedRule.label);
            expect(actualRule.note, expectedRule.note);
            expect(actualRule.createdAt, expectedRule.createdAt);
            expect(actualRule.updatedAt, expectedRule.updatedAt);
          }
          expect(actualPlan.zones, hasLength(expectedPlan.zones.length));
          for (var index = 0; index < expectedPlan.zones.length; index++) {
            final actualZone = actualPlan.zones[index];
            final expectedZone = expectedPlan.zones[index];
            expect(actualZone.id, expectedZone.id);
            expect(actualZone.episodeKey, expectedZone.episodeKey);
            expect(actualZone.title, expectedZone.title);
            expect(actualZone.lowerPrice, expectedZone.lowerPrice);
            expect(actualZone.upperPrice, expectedZone.upperPrice);
            expect(actualZone.enabled, expectedZone.enabled);
            expect(actualZone.note, expectedZone.note);
            expect(actualZone.createdAt, expectedZone.createdAt);
            expect(actualZone.updatedAt, expectedZone.updatedAt);
          }
        }
        final actualPlanEvaluation = actual.planEvaluation;
        final expectedPlanEvaluation = expected.planEvaluation;
        expect(actualPlanEvaluation == null, expectedPlanEvaluation == null);
        if (actualPlanEvaluation != null && expectedPlanEvaluation != null) {
          expect(
            actualPlanEvaluation.evaluatedAt,
            expectedPlanEvaluation.evaluatedAt,
          );
          expect(
            actualPlanEvaluation.rules,
            hasLength(expectedPlanEvaluation.rules.length),
          );
          for (
            var index = 0;
            index < expectedPlanEvaluation.rules.length;
            index++
          ) {
            final actualRule = actualPlanEvaluation.rules[index];
            final expectedRule = expectedPlanEvaluation.rules[index];
            expect(actualRule.rule.id, expectedRule.rule.id);
            expect(actualRule.state, expectedRule.state);
            expect(actualRule.value, expectedRule.value);
            expect(actualRule.referenceValue, expectedRule.referenceValue);
            expect(actualRule.reason, expectedRule.reason);
          }
          expect(
            actualPlanEvaluation.zones,
            hasLength(expectedPlanEvaluation.zones.length),
          );
          for (
            var index = 0;
            index < expectedPlanEvaluation.zones.length;
            index++
          ) {
            final actualZone = actualPlanEvaluation.zones[index];
            final expectedZone = expectedPlanEvaluation.zones[index];
            expect(actualZone.zone.id, expectedZone.zone.id);
            expect(actualZone.state, expectedZone.state);
            expect(actualZone.markPrice, expectedZone.markPrice);
            expect(actualZone.reason, expectedZone.reason);
          }
        }

        final actualSettings = actual.settings;
        final expectedSettings = expected.settings;
        expect(actualSettings == null, expectedSettings == null);
        if (actualSettings != null && expectedSettings != null) {
          final actualPolicy = actualSettings.policy;
          final expectedPolicy = expectedSettings.policy;
          expect(actualPolicy.version, expectedPolicy.version);
          expect(actualPolicy.bufferCritical, expectedPolicy.bufferCritical);
          expect(actualPolicy.bufferHigh, expectedPolicy.bufferHigh);
          expect(actualPolicy.bufferWatch, expectedPolicy.bufferWatch);
          expect(actualPolicy.leverageWatch, expectedPolicy.leverageWatch);
          expect(actualPolicy.leverageHigh, expectedPolicy.leverageHigh);
          expect(
            actualPolicy.leverageCritical,
            expectedPolicy.leverageCritical,
          );
          expect(
            actualPolicy.marginRatioCritical,
            expectedPolicy.marginRatioCritical,
          );
          expect(actualPolicy.marginRatioHigh, expectedPolicy.marginRatioHigh);
          expect(
            actualPolicy.marginRatioWatch,
            expectedPolicy.marginRatioWatch,
          );
          expect(
            actualPolicy.bufferVolatilityHigh,
            expectedPolicy.bufferVolatilityHigh,
          );
          expect(
            actualPolicy.bufferVolatilityWatch,
            expectedPolicy.bufferVolatilityWatch,
          );
          expect(
            actualPolicy.recoveryDistanceWatch,
            expectedPolicy.recoveryDistanceWatch,
          );
          expect(
            actualPolicy.recoveryDistanceHigh,
            expectedPolicy.recoveryDistanceHigh,
          );
          expect(
            actualPolicy.holdingBurdenWatch,
            expectedPolicy.holdingBurdenWatch,
          );
          expect(
            actualPolicy.holdingBurdenHigh,
            expectedPolicy.holdingBurdenHigh,
          );
          expect(
            actualPolicy.stressChanges,
            orderedEquals(expectedPolicy.stressChanges),
          );
          expect(
            actualPolicy.priceDeduplicationTolerance,
            expectedPolicy.priceDeduplicationTolerance,
          );
          expect(
            actualSettings.customStressChanges,
            orderedEquals(expectedSettings.customStressChanges),
          );
          expect(
            actualSettings.customStressPrices,
            orderedEquals(expectedSettings.customStressPrices),
          );
          expect(actualSettings.timeZone, expectedSettings.timeZone);
          expect(actualSettings.summaryHour, expectedSettings.summaryHour);
          expect(actualSettings.summaryMinute, expectedSettings.summaryMinute);
          expect(
            actualSettings.sampleRetentionDays,
            expectedSettings.sampleRetentionDays,
          );
          expect(
            actualSettings.oiRetentionHours,
            expectedSettings.oiRetentionHours,
          );
          expect(
            actualSettings.eventRetentionDays,
            expectedSettings.eventRetentionDays,
          );
          expect(
            actualSettings.summaryRetentionDays,
            expectedSettings.summaryRetentionDays,
          );
          expect(actualSettings.maxSamples, expectedSettings.maxSamples);
          expect(actualSettings.maxOiSamples, expectedSettings.maxOiSamples);
          expect(actualSettings.maxEvents, expectedSettings.maxEvents);
          expect(actualSettings.maxEpisodes, expectedSettings.maxEpisodes);
        }

        final actualMarket = actual.market;
        final expectedMarket = expected.market;
        expect(actualMarket == null, expectedMarket == null);
        if (actualMarket != null && expectedMarket != null) {
          expectMarket(actualMarket, expectedMarket);
        }
        expect(actual.samples, hasLength(expected.samples.length));
        for (var index = 0; index < expected.samples.length; index++) {
          expectSample(actual.samples[index], expected.samples[index]);
        }
        expect(actual.summaries, hasLength(expected.summaries.length));
        for (var index = 0; index < expected.summaries.length; index++) {
          final actualSummary = actual.summaries[index];
          final expectedSummary = expected.summaries[index];
          expect(actualSummary.episodeKey, expectedSummary.episodeKey);
          expect(actualSummary.dateKey, expectedSummary.dateKey);
          expect(actualSummary.timeZone, expectedSummary.timeZone);
          expect(actualSummary.capturedAt, expectedSummary.capturedAt);
          expectQuality(actualSummary.quality, expectedSummary.quality);
          expect(actualSummary.overallState, expectedSummary.overallState);
          expect(actualSummary.positionState, expectedSummary.positionState);
          expect(actualSummary.marketState, expectedSummary.marketState);
          expect(actualSummary.recoveryState, expectedSummary.recoveryState);
          expect(actualSummary.buffer, expectedSummary.buffer);
          expect(
            actualSummary.effectiveLeverage,
            expectedSummary.effectiveLeverage,
          );
          expect(
            actualSummary.actualInterestToday,
            expectedSummary.actualInterestToday,
          );
          expect(
            actualSummary.knownInterestToday,
            expectedSummary.knownInterestToday,
          );
          final actualInterestQuality = actualSummary.actualInterestQuality;
          final expectedInterestQuality = expectedSummary.actualInterestQuality;
          expect(
            actualInterestQuality == null,
            expectedInterestQuality == null,
          );
          if (actualInterestQuality != null &&
              expectedInterestQuality != null) {
            expectQuality(actualInterestQuality, expectedInterestQuality);
          }
          expect(
            actualSummary.interestCoverageComplete,
            expectedSummary.interestCoverageComplete,
          );
          expect(actualSummary.majorChange, expectedSummary.majorChange);
          expect(
            actualSummary.activeRuleCount,
            expectedSummary.activeRuleCount,
          );
          expect(
            actualSummary.unknownRuleCount,
            expectedSummary.unknownRuleCount,
          );
        }
        final actualComparison = actual.previousCheck;
        final expectedComparison = expected.previousCheck;
        expect(actualComparison == null, expectedComparison == null);
        if (actualComparison != null && expectedComparison != null) {
          expectSample(actualComparison.baseline, expectedComparison.baseline);
          expectSample(actualComparison.current, expectedComparison.current);
          expect(
            actualComparison.bufferDeltaPoints,
            expectedComparison.bufferDeltaPoints,
          );
          expect(
            actualComparison.leverageDelta,
            expectedComparison.leverageDelta,
          );
          expect(actualComparison.debtDelta, expectedComparison.debtDelta);
          expect(
            actualComparison.trueExitChanged,
            expectedComparison.trueExitChanged,
          );
          expect(
            actualComparison.structureChanged,
            expectedComparison.structureChanged,
          );
          expect(
            actualComparison.fundingChanged,
            expectedComparison.fundingChanged,
          );
          expect(
            actualComparison.openInterestChanged,
            expectedComparison.openInterestChanged,
          );
          expect(
            actualComparison.overallChanged,
            expectedComparison.overallChanged,
          );
          expect(
            actualComparison.positionChanged,
            expectedComparison.positionChanged,
          );
        }
        final actualTrend = actual.trend;
        final expectedTrend = expected.trend;
        expect(actualTrend == null, expectedTrend == null);
        if (actualTrend != null && expectedTrend != null) {
          expect(actualTrend.label, expectedTrend.label);
          expect(
            actualTrend.bufferDeltaPoints,
            expectedTrend.bufferDeltaPoints,
          );
          expect(actualTrend.leverageDelta, expectedTrend.leverageDelta);
          expect(actualTrend.reason, expectedTrend.reason);
          if (actualTrend.baseline != null && expectedTrend.baseline != null) {
            expectSample(actualTrend.baseline!, expectedTrend.baseline!);
          }
          if (actualTrend.current != null && expectedTrend.current != null) {
            expectSample(actualTrend.current!, expectedTrend.current!);
          }
        }
        final actualVelocity = actual.velocity;
        final expectedVelocity = expected.velocity;
        expect(actualVelocity == null, expectedVelocity == null);
        if (actualVelocity != null && expectedVelocity != null) {
          expect(actualVelocity.label, expectedVelocity.label);
          expect(actualVelocity.pointsPerHour, expectedVelocity.pointsPerHour);
          expect(actualVelocity.elapsedHours, expectedVelocity.elapsedHours);
          expect(actualVelocity.reason, expectedVelocity.reason);
          if (actualVelocity.baseline != null &&
              expectedVelocity.baseline != null) {
            expectSample(actualVelocity.baseline!, expectedVelocity.baseline!);
          }
          if (actualVelocity.current != null &&
              expectedVelocity.current != null) {
            expectSample(actualVelocity.current!, expectedVelocity.current!);
          }
        }
        expect(actual.events, hasLength(expected.events.length));
        for (var index = 0; index < expected.events.length; index++) {
          expectEvent(actual.events[index], expected.events[index]);
        }
        expectQuality(actual.quality, expected.quality);
        expect(actual.unsaved, expected.unsaved);
        expect(actual.lastError, expected.lastError);
        expect(actual.freshnessAt, expected.freshnessAt);
      }

      for (var index = 0; index < expectedState.positions.length; index++) {
        expectEntryParity(
          received.positions[index],
          expectedState.positions[index],
        );
      }

      await proxy.dispose();
      await controller.dispose();
      await monitor.dispose();
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
