import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../domain/risk/risk_events.dart';
import '../domain/risk/risk_models.dart';

/// Capability reported by the platform notification adapter.  A denied or
/// unavailable capability never removes an event from the in-app event list.
enum RiskNotificationCapabilityStatus { granted, denied, unavailable }

class RiskNotificationCapability {
  const RiskNotificationCapability({required this.status, this.reason});

  const RiskNotificationCapability.granted()
    : this(status: RiskNotificationCapabilityStatus.granted);

  const RiskNotificationCapability.denied([String? reason])
    : this(status: RiskNotificationCapabilityStatus.denied, reason: reason);

  const RiskNotificationCapability.unavailable([String? reason])
    : this(
        status: RiskNotificationCapabilityStatus.unavailable,
        reason: reason,
      );

  final RiskNotificationCapabilityStatus status;
  final String? reason;

  bool get canDeliver => status == RiskNotificationCapabilityStatus.granted;
}

/// The OS payload deliberately contains only generic state text.  Event
/// details, observed values, account identifiers, and PnL remain in the
/// durable/in-app event record.
class RiskNotification {
  const RiskNotification({
    required this.eventId,
    required this.episodeKey,
    required this.kind,
    required this.title,
    required this.body,
    this.severity,
  });

  factory RiskNotification.fromEvent(RiskEvent event) {
    return RiskNotification(
      eventId: event.id,
      episodeKey: event.episodeKey,
      kind: event.kind,
      severity: event.severity,
      title: 'Risk update',
      body: 'A risk condition changed. Open the app for details.',
    );
  }

  final String eventId;
  final String episodeKey;
  final RiskEventKind kind;
  final RiskSeverity? severity;
  final String title;
  final String body;

  /// This is useful for tests and protects future adapters from accidentally
  /// adding private values to OS text.
  bool get isPrivacySafe =>
      !title.contains(RegExp(r'\d')) &&
      !body.contains(RegExp(r'\d')) &&
      !title.toLowerCase().contains('pnl') &&
      !body.toLowerCase().contains('pnl');
}

enum RiskNotificationDeliveryStatus {
  delivered,
  denied,
  unavailable,
  failed,
  duplicate,
}

class RiskNotificationDelivery {
  const RiskNotificationDelivery({required this.status, this.reason});

  const RiskNotificationDelivery.delivered()
    : this(status: RiskNotificationDeliveryStatus.delivered);

  const RiskNotificationDelivery.denied([String? reason])
    : this(status: RiskNotificationDeliveryStatus.denied, reason: reason);

  const RiskNotificationDelivery.unavailable([String? reason])
    : this(status: RiskNotificationDeliveryStatus.unavailable, reason: reason);

  const RiskNotificationDelivery.failed([String? reason])
    : this(status: RiskNotificationDeliveryStatus.failed, reason: reason);

  final RiskNotificationDeliveryStatus status;
  final String? reason;

  bool get delivered => status == RiskNotificationDeliveryStatus.delivered;
}

/// Platform boundary used by [RiskMonitor].  Implementations must not mutate
/// durable latches; the monitor invokes them only after a successful save.
abstract class RiskNotificationSink {
  Future<RiskNotificationCapability> capability();

  Future<RiskNotificationDelivery> deliver(RiskNotification notification);
}

abstract interface class RiskNotificationCapabilityInvalidator {
  void invalidateCapability();
}

abstract interface class RiskNativeNotificationPlatform {
  Future<bool> initialize();

  Future<bool?> requestPermission();

  Future<void> show({
    required int id,
    required String title,
    required String body,
  });
}

/// Thin production adapter around the installed local-notifications plugin.
/// Tests inject [RiskNativeNotificationPlatform] and never touch channels.
class FlutterLocalNotificationPlatform
    implements RiskNativeNotificationPlatform {
  FlutterLocalNotificationPlatform({FlutterLocalNotificationsPlugin? plugin})
    : plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin plugin;
  bool _initialized = false;

  @override
  Future<bool> initialize() async {
    if (_initialized) return true;
    final result = await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
        macOS: DarwinInitializationSettings(),
        linux: LinuxInitializationSettings(
          defaultActionName: 'Open notification',
        ),
        windows: WindowsInitializationSettings(
          appName: 'Risk monitoring',
          appUserModelId: 'OpenAI.RiskMonitoring',
          guid: '2b6c5774-53d2-4a74-8e9e-8d1dfd3bb00f',
        ),
      ),
    );
    _initialized = result ?? false;
    return _initialized;
  }

  @override
  Future<bool?> requestPermission() async {
    if (kIsWeb) return false;
    if (!await initialize()) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      case TargetPlatform.iOS:
        return plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: false, sound: true);
      case TargetPlatform.macOS:
        return plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: false, sound: true);
      case TargetPlatform.linux:
      case TargetPlatform.windows:
      case TargetPlatform.fuchsia:
        return true;
    }
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    await plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'risk_alerts',
          'Risk alerts',
          channelDescription: 'Generic risk condition changes',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          playSound: false,
        ),
        iOS: DarwinNotificationDetails(presentSound: false),
        macOS: DarwinNotificationDetails(presentSound: false),
      ),
    );
  }
}

class FlutterLocalRiskNotificationSink
    implements RiskNotificationSink, RiskNotificationCapabilityInvalidator {
  FlutterLocalRiskNotificationSink({RiskNativeNotificationPlatform? platform})
    : _platform = platform ?? FlutterLocalNotificationPlatform();

  final RiskNativeNotificationPlatform _platform;
  RiskNotificationCapability? _cachedCapability;
  Future<RiskNotificationCapability>? _capabilityFuture;
  int _capabilityGeneration = 0;

  @override
  void invalidateCapability() {
    _capabilityGeneration++;
    _cachedCapability = null;
    // A permission change can occur while initialization/requestPermission is
    // still pending. Do not let a later caller join that stale future.
    _capabilityFuture = null;
  }

  @override
  Future<RiskNotificationCapability> capability() async {
    final cached = _cachedCapability;
    if (cached != null) return cached;
    final inFlight = _capabilityFuture;
    if (inFlight != null) return inFlight;
    final generation = _capabilityGeneration;
    final future = _loadCapability();
    _capabilityFuture = future;
    final result = await future;
    if (generation == _capabilityGeneration) _cachedCapability = result;
    if (identical(_capabilityFuture, future)) _capabilityFuture = null;
    return result;
  }

  Future<RiskNotificationCapability> _loadCapability() async {
    if (kIsWeb) {
      return const RiskNotificationCapability.unavailable(
        'Web uses the in-app event center',
      );
    }
    try {
      final adapter = _platform;
      if (!await adapter.initialize()) {
        return const RiskNotificationCapability.unavailable(
          'Native notification initialization failed',
        );
      }
      final granted = await adapter.requestPermission();
      if (granted == true) return const RiskNotificationCapability.granted();
      return const RiskNotificationCapability.denied(
        'Notification permission was denied',
      );
    } catch (_) {
      return const RiskNotificationCapability.unavailable(
        'Native notification capability is unavailable',
      );
    }
  }

  @override
  Future<RiskNotificationDelivery> deliver(
    RiskNotification notification,
  ) async {
    if (!notification.isPrivacySafe) {
      return const RiskNotificationDelivery.failed(
        'Notification payload failed privacy validation',
      );
    }
    if (kIsWeb) {
      return const RiskNotificationDelivery.unavailable(
        'Web uses the in-app event center',
      );
    }
    try {
      final capability = await this.capability();
      if (!capability.canDeliver) {
        return capability.status == RiskNotificationCapabilityStatus.denied
            ? RiskNotificationDelivery.denied(capability.reason)
            : RiskNotificationDelivery.unavailable(capability.reason);
      }
      await _platform.show(
        id: notification.eventId.hashCode & 0x7fffffff,
        title: notification.title,
        body: notification.body,
      );
      return const RiskNotificationDelivery.delivered();
    } catch (_) {
      return const RiskNotificationDelivery.failed(
        'Native notification delivery failed',
      );
    }
  }
}

/// Safe default for web and for platforms where local notification setup is
/// unavailable.  The monitor still publishes and retains in-app events.
class InAppRiskNotificationSink implements RiskNotificationSink {
  const InAppRiskNotificationSink({this.web = kIsWeb});

  final bool web;

  @override
  Future<RiskNotificationCapability> capability() async =>
      RiskNotificationCapability.unavailable(
        web ? 'Web uses the in-app event center' : 'Native sink unavailable',
      );

  @override
  Future<RiskNotificationDelivery> deliver(
    RiskNotification notification,
  ) async => RiskNotificationDelivery.unavailable(
    web ? 'Web uses the in-app event center' : 'Native sink unavailable',
  );
}

/// Adapter for a native plugin or host bridge.  Keeping the callbacks small
/// lets deterministic tests use a fake without touching platform channels.
class CallbackRiskNotificationSink implements RiskNotificationSink {
  CallbackRiskNotificationSink({
    required this.capabilityCallback,
    required this.deliverCallback,
  });

  final Future<RiskNotificationCapability> Function() capabilityCallback;
  final Future<RiskNotificationDelivery> Function(RiskNotification)
  deliverCallback;

  @override
  Future<RiskNotificationCapability> capability() => capabilityCallback();

  @override
  Future<RiskNotificationDelivery> deliver(
    RiskNotification notification,
  ) async {
    if (!notification.isPrivacySafe) {
      return const RiskNotificationDelivery.failed(
        'Notification payload failed privacy validation',
      );
    }
    return deliverCallback(notification);
  }
}
