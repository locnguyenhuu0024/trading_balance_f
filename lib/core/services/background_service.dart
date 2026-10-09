// File Name: background_service.dart
// File Path: lib/core/services/background_service.dart
//
// The Android service is the exclusive RiskMonitor owner while it is running.
// It receives typed commands and publishes typed acknowledgements/state over
// flutter_background_service channels. The foreground notification contains
// only generic service status; risk values never enter OS text.

import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/backend_data_client.dart';
import '../network/backend_data_session.dart';
import '../../features/portfolio/application/risk_monitor.dart';
import '../../features/portfolio/application/risk_monitor_bridge.dart';
import '../../features/portfolio/application/risk_notification_sink.dart';
import '../../features/portfolio/data/risk/risk_local_store.dart';
import '../../features/portfolio/data/risk/risk_market_repository.dart';
import '../../features/portfolio/data/risk/risk_repository.dart';
import '../../features/orders/data/trade_api_client.dart';

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
    this.backendDataSession,
    this.onDispose,
    this.serviceStatus,
    this.heartbeatInterval = const Duration(seconds: 5),
  }) {
    _commandSubscription = channel
        .on(RiskMonitorWire.command)
        .listen(_onCommand);
    _sessionInputSubscription = channel
        .on(RiskMonitorWire.sessionInput)
        .listen(_onSessionInput);
    _handshakeSubscription = channel
        .on(RiskMonitorWire.handshakeRequest)
        .listen((_) => _publishHandshake());
    if (backendDataSession != null) {
      _backendSessionSubscription = backendDataSession!.changes.listen((_) {
        _acknowledgedSessionGeneration = null;
        if (!_applyingSessionInput) {
          _fenceOwnerForSessionChange();
          if (_appliedSession != null && backendDataSession!.current == null) {
            _publishExpiredSessionStatus();
          }
        }
      });
    }
    _stateSubscription = owner.states.listen(_publishState);
    _publishState(owner.currentState);
    _publishHandshake();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      _publishHeartbeat();
    });
  }

  final RiskServiceChannel channel;
  final RiskMonitorOwner owner;
  final BackendDataSession? backendDataSession;
  final Future<void> Function()? onDispose;
  final void Function(String title, String content)? serviceStatus;
  final Duration heartbeatInterval;

  StreamSubscription<Map<String, dynamic>?>? _commandSubscription;
  StreamSubscription<Map<String, dynamic>?>? _sessionInputSubscription;
  StreamSubscription<Map<String, dynamic>?>? _handshakeSubscription;
  StreamSubscription<RiskMonitorViewState>? _stateSubscription;
  StreamSubscription<void>? _backendSessionSubscription;
  Timer? _heartbeatTimer;
  bool _disposed = false;
  bool _applyingSessionInput = false;
  Future<void> _commandTail = Future<void>.value();
  Future<void> _sessionTail = Future<void>.value();
  int _appliedSessionGeneration = 0;
  int? _acknowledgedSessionGeneration;
  int _appliedLocalSessionGeneration = 0;
  TradeSession? _appliedSession;

  void _publishHandshake() {
    if (_disposed) return;
    backendDataSession?.expireIfNeeded();
    channel.invoke(RiskMonitorWire.handshake, <String, dynamic>{
      'protocol': RiskMonitorWire.handshake,
      'owner': 'android-service',
      'backgroundAvailable': true,
      'appliedSessionGeneration': _appliedSessionGeneration,
      'sessionActive': _hasActiveBackendSession(),
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
    final decoded = payload == null ? null : _tryDecodeCommand(payload);
    final requiresSession = decoded != null && _requiresSession(decoded.type);
    final sessionGenerationAtArrival = backendDataSession?.generation;
    final acknowledgedGenerationAtArrival = _acknowledgedSessionGeneration;
    final startAuthorizedAtArrival =
        !requiresSession || _hasActiveBackendSession();
    _commandTail = _commandTail
        .then<void>(
          (_) => _handleCommand(
            payload,
            commandAtArrival: decoded,
            requiresSession: requiresSession,
            startAuthorizedAtArrival: startAuthorizedAtArrival,
            sessionGenerationAtArrival: sessionGenerationAtArrival,
            acknowledgedGenerationAtArrival: acknowledgedGenerationAtArrival,
          ),
        )
        .catchError((_) {});
  }

  Future<void> _handleCommand(
    Map<String, dynamic>? payload, {
    required RiskMonitorCommand? commandAtArrival,
    required bool requiresSession,
    required bool startAuthorizedAtArrival,
    required int? sessionGenerationAtArrival,
    required int? acknowledgedGenerationAtArrival,
  }) async {
    if (_disposed || payload == null) return;
    try {
      final command = RiskMonitorWire.decodeCommand(payload);
      late final RiskMonitorCommandResult result;
      if (requiresSession &&
          (commandAtArrival == null ||
              commandAtArrival.id != command.id ||
              !startAuthorizedAtArrival ||
              !_sessionContextMatches(
                sessionGenerationAtArrival,
                acknowledgedGenerationAtArrival,
              ))) {
        result = _rejected(command, 'An active backend session is required');
      } else {
        final dispatched = await owner.dispatch(command);
        if (requiresSession &&
            !_sessionContextMatches(
              sessionGenerationAtArrival,
              acknowledgedGenerationAtArrival,
            )) {
          result = _rejected(command, 'Backend session changed during command');
        } else {
          result = dispatched;
        }
      }
      if (_disposed) return;
      channel.invoke(RiskMonitorWire.acknowledgement, {
        ...RiskMonitorWire.encodeAck(result),
        'appliedSessionGeneration': _appliedSessionGeneration,
      });
      _publishState(result.state);
    } catch (error) {
      if (_disposed) return;
      channel.invoke(RiskMonitorWire.acknowledgement, <String, dynamic>{
        'protocol': RiskMonitorWire.acknowledgement,
        'appliedSessionGeneration': _appliedSessionGeneration,
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

  void _onSessionInput(Map<String, dynamic>? payload) {
    if (_disposed) return;
    final parsed = _decodeSessionInput(payload);
    final generation = parsed.generation;
    final session = parsed.session;
    if (!parsed.valid || generation == null || backendDataSession == null) {
      _queueSessionAck(
        generation ?? 0,
        accepted: false,
        active: false,
        localGeneration: null,
      );
      return;
    }

    if (generation < _appliedSessionGeneration) {
      _queueSessionAck(
        generation,
        accepted: false,
        active: false,
        localGeneration: null,
      );
      return;
    }

    if (generation == _appliedSessionGeneration) {
      final identicalState = _sameSession(_appliedSession, session);
      final localGeneration = backendDataSession!.generation;
      final sessionStillApplied = _sessionMatches(session, localGeneration);
      _queueSessionAck(
        generation,
        accepted: identicalState && sessionStillApplied,
        active: session != null && identicalState && sessionStillApplied,
        localGeneration: localGeneration,
      );
      return;
    }

    // Revoke the previous ack before the session notification can reach any
    // command listener. The request/session generation changes fence in-flight
    // Dio work before this update can wait on the command tail.
    _acknowledgedSessionGeneration = null;
    _appliedSessionGeneration = generation;
    _appliedSession = session;
    _fenceOwnerForSessionChange();
    _applyingSessionInput = true;
    backendDataSession!.update(session);
    _applyingSessionInput = false;
    backendDataSession!.expireIfNeeded();
    final localGeneration = backendDataSession!.generation;
    _appliedLocalSessionGeneration = localGeneration;
    final stillApplied = _sessionMatches(session, localGeneration);
    _queueSessionAck(
      generation,
      accepted: stillApplied,
      active: session != null && stillApplied,
      localGeneration: localGeneration,
    );
  }

  void _queueSessionAck(
    int generation, {
    required bool accepted,
    required bool active,
    required int? localGeneration,
  }) {
    _sessionTail = _sessionTail
        .then<void>((_) async {
          if (_disposed) return;
          final session = backendDataSession;
          session?.expireIfNeeded();
          final current =
              _appliedSessionGeneration == generation &&
              (localGeneration == null ||
                  session?.generation == localGeneration);
          final acceptedNow = accepted && current;
          final activeNow =
              acceptedNow &&
              active &&
              session != null &&
              _sessionMatches(_appliedSession, localGeneration);
          try {
            channel.invoke(RiskMonitorWire.sessionAck, <String, dynamic>{
              'protocol': RiskMonitorWire.sessionAck,
              'generation': generation,
              'accepted': acceptedNow,
              'active': activeNow,
              'status': acceptedNow ? 'applied' : 'rejected',
            });
            if (activeNow &&
                _appliedSessionGeneration == generation &&
                session.generation == localGeneration &&
                _sessionMatches(_appliedSession, localGeneration)) {
              _acknowledgedSessionGeneration = generation;
            }
            _publishState(owner.currentState);
          } catch (_) {
            _acknowledgedSessionGeneration = null;
          }
        })
        .catchError((_) {});
  }

  ({bool valid, int? generation, TradeSession? session}) _decodeSessionInput(
    Map<String, dynamic>? payload,
  ) {
    final generation = payload?['generation'];
    if (payload == null ||
        payload['protocol'] != RiskMonitorWire.sessionInput ||
        generation is! int ||
        generation < 0 ||
        payload['active'] is! bool) {
      return (
        valid: false,
        generation: generation is int ? generation : null,
        session: null,
      );
    }
    final active = payload['active'] as bool;
    final requiredKeys = <String>{'protocol', 'generation', 'active'};
    if (active) {
      requiredKeys.addAll(<String>{'token', 'accountIdentifier', 'expiresAt'});
    }
    if (payload.keys.length != requiredKeys.length ||
        !payload.keys.toSet().containsAll(requiredKeys)) {
      return (valid: false, generation: generation, session: null);
    }
    if (!active) return (valid: true, generation: generation, session: null);

    final token = payload['token'];
    final account = payload['accountIdentifier'];
    final rawExpiry = payload['expiresAt'];
    final expiry = rawExpiry is String ? DateTime.tryParse(rawExpiry) : null;
    if (token is! String ||
        token.trim().isEmpty ||
        account is! String ||
        account.trim().isEmpty ||
        expiry == null ||
        !DateTime.now().toUtc().isBefore(expiry.toUtc())) {
      return (valid: false, generation: generation, session: null);
    }
    return (
      valid: true,
      generation: generation,
      session: TradeSession(
        bearerToken: token,
        accountIdentifier: account,
        expiresAt: expiry.toUtc(),
      ),
    );
  }

  RiskMonitorCommand? _tryDecodeCommand(Map<String, dynamic> payload) {
    try {
      return RiskMonitorWire.decodeCommand(payload);
    } on Object {
      return null;
    }
  }

  bool _requiresSession(RiskMonitorCommandType type) =>
      backendDataSession != null &&
      const <RiskMonitorCommandType>{
        RiskMonitorCommandType.start,
        RiskMonitorCommandType.refresh,
        RiskMonitorCommandType.reconnect,
        RiskMonitorCommandType.uiResume,
      }.contains(type);

  bool _hasActiveBackendSession() {
    final session = backendDataSession;
    if (session == null) return true;
    session.expireIfNeeded();
    final active = session.current;
    return active != null &&
        _acknowledgedSessionGeneration == _appliedSessionGeneration &&
        _appliedSession != null &&
        _sessionMatches(_appliedSession, _appliedLocalSessionGeneration);
  }

  bool _sessionContextMatches(int? localGeneration, int? ackGeneration) {
    final session = backendDataSession;
    if (session == null) return true;
    session.expireIfNeeded();
    return localGeneration != null &&
        ackGeneration != null &&
        localGeneration == session.generation &&
        ackGeneration == _acknowledgedSessionGeneration &&
        ackGeneration == _appliedSessionGeneration &&
        _hasActiveBackendSession();
  }

  bool _sessionMatches(TradeSession? expected, int? generation) {
    final session = backendDataSession;
    if (session == null) return false;
    if (expected == null) return session.current == null;
    return generation != null && session.matches(generation, expected);
  }

  bool _sameSession(TradeSession? left, TradeSession? right) => left == null
      ? right == null
      : right != null &&
            left.bearerToken == right.bearerToken &&
            left.accountIdentifier == right.accountIdentifier &&
            left.expiresAt == right.expiresAt;

  void _fenceOwnerForSessionChange() {
    final monitor = owner;
    if (monitor is RiskMonitor) {
      final reason = backendDataSession?.current == null
          ? 'Phiên giao dịch đã hết hạn. Hãy đăng nhập lại.'
          : 'Phiên giao dịch đã thay đổi. Hãy bắt đầu theo dõi lại.';
      monitor.invalidateCredentials(reason: reason);
    }
  }

  void _publishExpiredSessionStatus() {
    if (_disposed) return;
    try {
      channel.invoke(RiskMonitorWire.sessionAck, <String, dynamic>{
        'protocol': RiskMonitorWire.sessionAck,
        'generation': _appliedSessionGeneration,
        'accepted': false,
        'active': false,
        'status': 'expired',
      });
      _publishState(owner.currentState);
    } catch (_) {}
  }

  RiskMonitorCommandResult _rejected(
    RiskMonitorCommand command,
    String message,
  ) => RiskMonitorCommandResult(
    commandId: command.id,
    status: RiskMonitorCommandStatus.rejected,
    state: owner.currentState,
    message: message,
  );

  void _publishState(RiskMonitorViewState value) {
    if (_disposed) return;
    final currentValue = backendDataSession == null
        ? value
        : owner.currentState;
    channel.invoke(RiskMonitorWire.state, <String, dynamic>{
      ...RiskMonitorWire.encodeState(currentValue),
      'appliedSessionGeneration': _appliedSessionGeneration,
    });
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _commandSubscription?.cancel();
    await _sessionInputSubscription?.cancel();
    await _handshakeSubscription?.cancel();
    await _stateSubscription?.cancel();
    await _backendSessionSubscription?.cancel();
    await _commandTail;
    await _sessionTail;
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
    await onDispose?.call();
  }
}

class ProductionRiskServiceMonitor {
  const ProductionRiskServiceMonitor({
    required this.monitor,
    required this.client,
    required this.repository,
    required this.marketRepository,
  });

  final RiskMonitor monitor;
  final BackendDataClient client;
  final RiskRepository repository;
  final RiskMarketRepository marketRepository;

  Future<void> dispose() async {
    await repository.dispose();
    await marketRepository.dispose();
    client.close(force: true);
  }
}

Future<ProductionRiskServiceMonitor> createProductionRiskServiceMonitor({
  required BackendDataSession backendSession,
}) async {
  final client = BackendDataClient(
    onUnauthorized: (session, generation, expectedSession) {
      if (identical(session, backendSession) &&
          session.matches(generation, expectedSession)) {
        session.update(null);
      }
    },
  );
  final repository = RiskRepository(client.dio, backendSession: backendSession);
  final marketRepository = RiskMarketRepository(
    client.dio,
    backendSession: backendSession,
    requestCoordinator: repository.requestCoordinator,
  );
  final preferences = await SharedPreferences.getInstance();
  final monitor = RiskMonitor.fromRepositories(
    repository: repository,
    marketRepository: marketRepository,
    store: RiskLocalStore(storage: SharedPreferencesRiskStorage(preferences)),
    notificationSink: FlutterLocalRiskNotificationSink(),
  );
  monitor.setRuntimeStatus(
    ownerLabel: 'android-service',
    backgroundAvailable: true,
  );
  monitor.setBackgroundMode(true);
  return ProductionRiskServiceMonitor(
    monitor: monitor,
    client: client,
    repository: repository,
    marketRepository: marketRepository,
  );
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
    final backendSession = BackendDataSession();
    final resources = await createProductionRiskServiceMonitor(
      backendSession: backendSession,
    );
    controller = RiskServiceOwnerController(
      channel: channel,
      owner: resources.monitor,
      backendDataSession: backendSession,
      onDispose: () async {
        await resources.dispose();
        backendSession.dispose();
      },
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
