import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

typedef BackgroundServiceConfigure = Future<bool> Function({
  required IosConfiguration iosConfiguration,
  required AndroidConfiguration androidConfiguration,
});

typedef BackgroundServiceCommand = void Function(
  String method, [
  Map<String, dynamic>? arguments,
]);

Future<void> retireBackgroundService({
  BackgroundServiceConfigure? configure,
  BackgroundServiceCommand? invoke,
}) async {
  if (kIsWeb) return;

  final service = FlutterBackgroundService();
  (invoke ?? service.invoke)('stopService');
  final configured = await (configure ?? service.configure)(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      autoStartOnBoot: false,
      isForegroundMode: false,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
    ),
  );
  if (!configured) {
    throw StateError('Legacy background service retirement failed.');
  }
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await service.stopSelf();
}
