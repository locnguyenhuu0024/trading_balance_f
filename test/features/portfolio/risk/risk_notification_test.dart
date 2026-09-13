import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/portfolio/application/risk_monitor.dart';
import 'package:trading_balance_f/features/portfolio/application/risk_monitor_bridge.dart';
import 'package:trading_balance_f/features/portfolio/application/risk_notification_sink.dart';
import 'package:trading_balance_f/features/portfolio/data/risk/risk_local_store.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_events.dart';

import 'fixtures/risk_monitor_fixtures.dart';

class OrderedSink implements RiskNotificationSink {
  OrderedSink(this.persistence);

  final FakeRiskPersistence persistence;
  final List<RiskNotification> delivered = <RiskNotification>[];
  int savesAtFirstDelivery = 0;
  RiskEpisodeRecord? recordAtFirstDelivery;
  RiskNotificationCapability capabilityState =
      const RiskNotificationCapability.granted();

  @override
  Future<RiskNotificationCapability> capability() async => capabilityState;

  @override
  Future<RiskNotificationDelivery> deliver(
    RiskNotification notification,
  ) async {
    savesAtFirstDelivery = persistence.saveEpisodeCalls;
    recordAtFirstDelivery = persistence.episodes.values.firstWhere(
      (record) =>
          record.events.any((event) => event.id == notification.eventId),
    );
    delivered.add(notification);
    return const RiskNotificationDelivery.delivered();
  }
}

class FakeNativeNotificationPlatform implements RiskNativeNotificationPlatform {
  FakeNativeNotificationPlatform({this.granted = true});

  bool granted;
  int initializeCalls = 0;
  int permissionCalls = 0;
  int showCalls = 0;
  String? lastTitle;
  String? lastBody;

  @override
  Future<bool> initialize() async {
    initializeCalls++;
    return true;
  }

  @override
  Future<bool?> requestPermission() async {
    permissionCalls++;
    return granted;
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    showCalls++;
    lastTitle = title;
    lastBody = body;
  }
}

void main() {
  test(
    'RED-005 OS payload excludes PnL/private values and denial is retained',
    () async {
      final event = RiskEvent(
        id: 'event-1',
        episodeKey: 'episode-a',
        kind: RiskEventKind.stateChange,
        message: 'Risk worsened; pnl=123.45',
        createdAt: DateTime.utc(2026, 9, 10, 14),
        observedAt: DateTime.utc(2026, 9, 10, 14),
        currentValue: 123.45,
      );
      final notification = RiskNotification.fromEvent(event);
      expect(notification.isPrivacySafe, isTrue);
      expect(notification.body, isNot(contains('123.45')));
      expect(notification.body.toLowerCase(), isNot(contains('pnl')));

      final sink = FakeRiskNotificationSink()
        ..capabilityState = const RiskNotificationCapability.denied();
      final result = await sink.deliver(notification);
      expect(result.status, RiskNotificationDeliveryStatus.delivered);
      expect(notification.episodeKey, 'episode-a');
    },
  );

  test(
    'GREEN-005 native sink reports permission and sends generic text',
    () async {
      final platform = FakeNativeNotificationPlatform();
      final sink = FlutterLocalRiskNotificationSink(platform: platform);
      final capability = await sink.capability();
      expect(capability.status, RiskNotificationCapabilityStatus.granted);
      final result = await sink.deliver(
        RiskNotification.fromEvent(
          RiskEvent(
            id: 'event-native',
            episodeKey: 'episode-a',
            kind: RiskEventKind.stateChange,
            message: 'private pnl 123.45',
            createdAt: DateTime.utc(2026, 9, 10),
            observedAt: DateTime.utc(2026, 9, 10),
          ),
        ),
      );
      expect(result.delivered, isTrue);
      expect(platform.showCalls, 1);
      expect(platform.lastTitle, 'Risk update');
      expect(platform.lastBody, isNot(contains(RegExp(r'\d'))));
      expect(platform.lastBody!.toLowerCase(), isNot(contains('pnl')));
    },
  );

  test(
    'GREEN-005 R22-002 capability invalidation reloads changed permission state',
    () async {
      final platform = FakeNativeNotificationPlatform();
      final sink = FlutterLocalRiskNotificationSink(platform: platform);

      expect(
        (await sink.capability()).status,
        RiskNotificationCapabilityStatus.granted,
      );
      expect(platform.permissionCalls, 1);

      platform.granted = false;
      sink.invalidateCapability();
      expect(
        (await sink.capability()).status,
        RiskNotificationCapabilityStatus.denied,
      );
      expect(platform.permissionCalls, 2);
    },
  );

  test(
    'RED-005 denied native capability does not deliver through monitor',
    () async {
      final clock = FakeRiskClock();
      final source = FakeRiskSource(
        clock: clock,
        position: () => syntheticRiskPosition(observedAt: clock.value),
      );
      final platform = FakeNativeNotificationPlatform(granted: false);
      final nativeSink = FlutterLocalRiskNotificationSink(platform: platform);
      final persistence = FakeRiskPersistence();
      final monitor = RiskMonitor(
        dataSource: source,
        persistence: persistence,
        clock: clock.now,
        notificationSink: nativeSink,
      );
      await monitor.dispatch(
        RiskMonitorCommand.start(id: 'native-denied-start'),
      );
      await monitor.dispatch(
        RiskMonitorCommand.refresh(id: 'native-denied-refresh'),
      );
      expect(
        monitor.currentState.notificationCapability,
        RiskNotificationCapabilityStatus.denied,
      );
      expect(platform.showCalls, 0);
      await monitor.dispose();
    },
  );

  test('GREEN-005 durable event latch is saved before one delivery', () async {
    final clock = FakeRiskClock();
    var mark = 10.0;
    final source = FakeRiskSource(
      clock: clock,
      position: () =>
          syntheticRiskPosition(observedAt: clock.value, markPrice: mark),
    );
    final persistence = FakeRiskPersistence();
    final sink = OrderedSink(persistence);
    final monitor = RiskMonitor(
      dataSource: source,
      persistence: persistence,
      clock: clock.now,
      notificationSink: sink,
    );
    await monitor.dispatch(RiskMonitorCommand.start(id: 'notify-start'));
    mark = 8;
    clock.advance(const Duration(minutes: 1));
    await monitor.dispatch(RiskMonitorCommand.refresh(id: 'notify-worsen'));

    expect(sink.delivered, hasLength(1));
    expect(sink.savesAtFirstDelivery, greaterThan(0));
    expect(
      recordAtFirstDeliveryContains(
        sink.recordAtFirstDelivery,
        sink.delivered.single.eventId,
      ),
      isTrue,
    );
    expect(sink.delivered.single.isPrivacySafe, isTrue);
    expect(sink.delivered.single.title, isNot(contains(RegExp(r'\d'))));
    expect(sink.delivered.single.body, isNot(contains(RegExp(r'\d'))));
    await monitor.dispose();
  });
}

bool recordAtFirstDeliveryContains(RiskEpisodeRecord? record, String eventId) {
  if (record == null) return false;
  return record.events.any((event) => event.id == eventId) &&
      record.latches.emittedEventIds.contains(eventId);
}
