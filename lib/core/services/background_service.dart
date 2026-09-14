// File Name: background_service.dart
// File Path: lib/core/services/background_service.dart
//
// The Android service is the exclusive RiskMonitor owner while it is running.
// It receives typed commands and publishes typed acknowledgements/state over
// flutter_background_service channels. The foreground notification contains
// only generic service status; risk values never enter OS text.

import 'dart:async';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/okx_interceptor.dart';
import '../security/secure_storage_helper.dart';
import '../../features/portfolio/application/risk_monitor.dart';
import '../../features/portfolio/application/risk_monitor_bridge.dart';
import '../../features/portfolio/application/risk_notification_sink.dart';
import '../../features/portfolio/data/risk/risk_local_store.dart';
import '../../features/portfolio/data/risk/risk_market_repository.dart';
import '../../features/portfolio/data/risk/risk_repository.dart';

const notificationChannelId = 'okx_tracker_channel';
const notificationId = 888;

abstract interface class RiskServiceChannel {
  Stream<Map<String, dynamic>?> on(String method);

  void invoke(String method, [Map<String, dynamic>? arguments]);
}

class FlutterBackgroundServiceChannel implements RiskServiceChannel {
  const FlutterBackgroundServiceChannel(this.service);

  final FlutterBackgroundService service;

  @override
  Stream<Map<String, dynamic>?> on(String method) => service.on(method);

  @override
  void invoke(String method, [Map<String, dynamic>? arguments]) =>
      service.invoke(method, arguments);
}

class ServiceInstanceChannel implements RiskServiceChannel {
  const ServiceInstanceChannel(this.service);

  final ServiceInstance service;

  @override
  Stream<Map<String, dynamic>?> on(String method) => service.on(method);

  @override
  void invoke(String method, [Map<String, dynamic>? arguments]) =>
      service.invoke(method, arguments);
}

/// Owns a real RiskMonitor in the service isolate and serializes every
/// incoming command through that owner. Tests inject this seam with a fake
/// channel and fake owner, while production uses ServiceInstance channels.
class RiskServiceOwnerController implements RiskMonitorDisposable {
  RiskServiceOwnerController({
    required this.channel,
    required this.owner,
    this.serviceStatus,
    this.heartbeatInterval = const Duration(seconds: 5),
  }) {
    _commandSubscription = channel
        .on(RiskMonitorWire.command)
        .listen(_onCommand);
    _handshakeSubscription = channel
        .on(RiskMonitorWire.handshakeRequest)
        .listen((_) => _publishHandshake());
    _stateSubscription = owner.states.listen(_publishState);
    _publishState(owner.currentState);
    _publishHandshake();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      _publishHeartbeat();
    });
  }

  final RiskServiceChannel channel;
  final RiskMonitorOwner owner;
  final void Function(String title, String content)? serviceStatus;
  final Duration heartbeatInterval;

  StreamSubscription<Map<String, dynamic>?>? _commandSubscription;
  StreamSubscription<Map<String, dynamic>?>? _handshakeSubscription;
  StreamSubscription<RiskMonitorViewState>? _stateSubscription;
  Timer? _heartbeatTimer;
  bool _disposed = false;
  Future<void> _commandTail = Future<void>.value();

  void _publishHandshake() {
    if (_disposed) return;
    channel.invoke(RiskMonitorWire.handshake, <String, dynamic>{
      'protocol': RiskMonitorWire.handshake,
      'owner': 'android-service',
      'backgroundAvailable': true,
    });
  }

  void _publishHeartbeat() {
    if (_disposed) return;
    try {
      channel.invoke(RiskMonitorWire.heartbeat, <String, dynamic>{
        'protocol': RiskMonitorWire.heartbeat,
        'owner': 'android-service',
      });
    } catch (_) {}
  }

  void _onCommand(Map<String, dynamic>? payload) {
    if (!_disposed &&
        payload != null &&
        owner is RiskMonitorCredentialInvalidator) {
      try {
        final command = RiskMonitorWire.decodeCommand(payload);
        if (command.type == RiskMonitorCommandType.invalidateCredentials) {
          (owner as RiskMonitorCredentialInvalidator)
              .fenceCredentialsForCommand(
                command.id,
                reason: command.reason ?? 'Credentials changed',
              );
        }
      } catch (_) {
        // _handleCommand sends the typed rejection acknowledgement.
      }
    }
    _commandTail = _commandTail
        .then<void>((_) => _handleCommand(payload))
        .catchError((_) {});
  }

  Future<void> _handleCommand(Map<String, dynamic>? payload) async {
    if (_disposed || payload == null) return;
    try {
      final command = RiskMonitorWire.decodeCommand(payload);
      final result = await owner.dispatch(command);
      if (_disposed) return;
      channel.invoke(RiskMonitorWire.acknowledgement, {
        ...RiskMonitorWire.encodeAck(result),
      });
      _publishState(result.state);
    } catch (error) {
      if (_disposed) return;
      channel.invoke(RiskMonitorWire.acknowledgement, <String, dynamic>{
        'protocol': RiskMonitorWire.acknowledgement,
        'ack': <String, dynamic>{
          'commandId': payload['command'] is Map
              ? (payload['command'] as Map)['id']?.toString() ?? ''
              : '',
          'status': RiskMonitorCommandStatus.failed.name,
          'message': 'Risk service command rejected',
          'replayed': false,
          'state': RiskMonitorWire.encodeState(owner.currentState),
        },
      });
      serviceStatus?.call('Risk monitoring', 'Risk service command failed');
    }
  }

  void _publishState(RiskMonitorViewState value) {
    if (_disposed) return;
    channel.invoke(RiskMonitorWire.state, RiskMonitorWire.encodeState(value));
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _commandSubscription?.cancel();
    await _handshakeSubscription?.cancel();
    await _stateSubscription?.cancel();
    await _commandTail;
    if (owner is RiskMonitorDisposable) {
      if (owner.currentState.isRunning) {
        await owner.dispatch(
          RiskMonitorCommand.stop(
            id: 'service-dispose-stop-${DateTime.now().microsecondsSinceEpoch}',
          ),
        );
      }
      await (owner as RiskMonitorDisposable).dispose();
    }
  }
}

Future<RiskMonitor> createProductionRiskServiceMonitor() async {
  const secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  final credentials = SecureStorageHelper(secureStorage);
  final authenticatedDio = Dio(
    BaseOptions(
      baseUrl: 'https://www.okx.com',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: const <String, Object>{'Content-Type': 'application/json'},
    ),
  )..interceptors.add(OkxInterceptor(credentials));
  final marketDio = Dio(
    BaseOptions(
      baseUrl: 'https://www.okx.com',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: const <String, Object>{'Content-Type': 'application/json'},
    ),
  );
  final preferences = await SharedPreferences.getInstance();
  final monitor = RiskMonitor.fromRepositories(
    repository: RiskRepository(authenticatedDio),
    marketRepository: RiskMarketRepository(marketDio),
    store: RiskLocalStore(storage: SharedPreferencesRiskStorage(preferences)),
    notificationSink: FlutterLocalRiskNotificationSink(),
  );
  monitor.setRuntimeStatus(
    ownerLabel: 'android-service',
    backgroundAvailable: true,
  );
  monitor.setBackgroundMode(true);
  return monitor;
}

Future<void> initializeBackgroundService() async {
  if (kIsWeb) return;
  final service = FlutterBackgroundService();

  const channel = AndroidNotificationChannel(
    notificationChannelId,
    'Risk monitoring service',
    description: 'Generic status for the risk monitoring owner',
    importance: Importance.low,
  );
  final localNotifications = FlutterLocalNotificationsPlugin();
  await localNotifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.requestNotificationsPermission();
  await localNotifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      foregroundServiceTypes: [AndroidForegroundType.dataSync],
      notificationChannelId: notificationChannelId,
      initialNotificationTitle: 'Risk monitoring',
      initialNotificationContent: 'Risk monitoring service is starting',
      foregroundServiceNotificationId: notificationId,
    ),
    iosConfiguration: IosConfiguration(autoStart: false, onForeground: onStart),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  final channel = ServiceInstanceChannel(service);
  RiskServiceOwnerController? controller;
  Timer? statusTimer;

  void publishStatus() {
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'Risk monitoring',
        content: 'Risk monitoring service is active',
      );
    }
  }

  publishStatus();
  statusTimer = Timer.periodic(const Duration(minutes: 1), (_) {
    publishStatus();
  });
  try {
    final monitor = await createProductionRiskServiceMonitor();
    controller = RiskServiceOwnerController(
      channel: channel,
      owner: monitor,
      serviceStatus: (_, content) {
        if (service is AndroidServiceInstance) {
          service.setForegroundNotificationInfo(
            title: 'Risk monitoring',
            content: content,
          );
        }
      },
    );
  } catch (_) {
    channel.invoke(RiskMonitorWire.handshake, <String, dynamic>{
      'protocol': RiskMonitorWire.handshake,
      'owner': 'android-service',
      'backgroundAvailable': false,
      'error': 'Risk service owner unavailable',
    });
  }
  service.on('stopService').listen((_) async {
    await controller?.dispose();
    statusTimer?.cancel();
    service.stopSelf();
  });
}
