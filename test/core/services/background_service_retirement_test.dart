import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/services/background_service.dart';

void main() {
  test('RED-001 legacy callback only stops a saved service handle', () async {
    final service = _FakeServiceInstance();

    onStart(service);
    await Future<void>.delayed(Duration.zero);

    expect(service.stopCalls, 1);
  });

  test(
    'GREEN-001 retirement disables autostart and stops the old service',
    () async {
      AndroidConfiguration? capturedAndroidConfiguration;
      IosConfiguration? capturedIosConfiguration;
      final events = <String>[];

      await retireBackgroundService(
        invoke: (method, [arguments]) => events.add(method),
        configure: ({
          required androidConfiguration,
          required iosConfiguration,
        }) async {
          events.add('configure');
          capturedAndroidConfiguration = androidConfiguration;
          capturedIosConfiguration = iosConfiguration;
          return true;
        },
      );

      expect(events, ['stopService', 'configure']);
      expect(capturedAndroidConfiguration?.autoStart, isFalse);
      expect(capturedAndroidConfiguration?.autoStartOnBoot, isFalse);
      expect(capturedAndroidConfiguration?.isForegroundMode, isFalse);
      expect(identical(capturedAndroidConfiguration?.onStart, onStart), isTrue);
      expect(capturedIosConfiguration?.autoStart, isFalse);
      expect(
        identical(capturedIosConfiguration?.onForeground, onStart),
        isTrue,
      );
    },
  );

  test(
    'reports failed retirement configuration after stopping the service',
    () async {
      var stopRequested = false;

      await expectLater(
        retireBackgroundService(
          invoke: (method, [arguments]) =>
              stopRequested = method == 'stopService',
          configure:
              ({required androidConfiguration, required iosConfiguration})
              async => false,
        ),
        throwsA(isA<StateError>()),
      );

      expect(stopRequested, isTrue);
    },
  );
}

class _FakeServiceInstance implements ServiceInstance {
  int stopCalls = 0;

  @override
  Future<void> stopSelf() async {
    stopCalls++;
  }

  @override
  void invoke(String method, [Map<String, dynamic>? arg]) {
    throw StateError('The legacy callback must not invoke $method.');
  }

  @override
  Stream<Map<String, dynamic>?> on(String method) {
    throw StateError('The legacy callback must not subscribe to $method.');
  }
}
