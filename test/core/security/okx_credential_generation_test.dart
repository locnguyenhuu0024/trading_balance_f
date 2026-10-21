import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/main.dart' show WebStorageHelper;

void main() {
  group('RED-001', () {
    test(
      'concurrent save and clear fence immediately and finish after all writes',
      () async {
        final storage = _ControlledStorage();
        final changes = <OkxCredentialSnapshot>[];
        storage.okxCredentialState.addListener(
          () => changes.add(storage.okxCredentialState.value),
        );

        final first = storage.saveOkxCredentials(
          apiKey: 'fixture-first',
          secretKey: 'fixture-secret-first',
          passphrase: 'fixture-pass-first',
        );
        final second = storage.clearOkxCredentials();
        expect(
          storage.okxCredentialState.value,
          const OkxCredentialSnapshot(generation: 2, rotating: true),
        );

        storage.writes[0].complete();
        await first;
        expect(
          storage.okxCredentialState.value,
          const OkxCredentialSnapshot(generation: 3, rotating: true),
        );

        storage.writes[1].completeError(StateError('fixture storage failure'));
        await expectLater(second, throwsStateError);
        expect(
          storage.okxCredentialState.value,
          const OkxCredentialSnapshot(generation: 4, rotating: false),
        );
        expect(changes, const <OkxCredentialSnapshot>[
          OkxCredentialSnapshot(generation: 1, rotating: true),
          OkxCredentialSnapshot(generation: 2, rotating: true),
          OkxCredentialSnapshot(generation: 3, rotating: true),
          OkxCredentialSnapshot(generation: 4, rotating: false),
        ]);

        storage.dispose();
      },
    );
  });

  group('GREEN-001', () {
    test(
      'WebStorageHelper save and clear publish safe generation changes',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final preferences = await SharedPreferences.getInstance();
        final storage = WebStorageHelper(preferences);
        final changes = <OkxCredentialSnapshot>[];
        storage.okxCredentialState.addListener(
          () => changes.add(storage.okxCredentialState.value),
        );

        await storage.saveOkxCredentials(
          apiKey: 'fixture-web-key',
          secretKey: 'fixture-web-secret',
          passphrase: 'fixture-web-passphrase',
        );
        await storage.clearOkxCredentials();

        expect(changes, const <OkxCredentialSnapshot>[
          OkxCredentialSnapshot(generation: 1, rotating: true),
          OkxCredentialSnapshot(generation: 2, rotating: false),
          OkxCredentialSnapshot(generation: 3, rotating: true),
          OkxCredentialSnapshot(generation: 4, rotating: false),
        ]);
        expect(
          changes.every((state) => state.runtimeType == OkxCredentialSnapshot),
          isTrue,
        );
        storage.dispose();
      },
    );
  });
}

class _ControlledStorage extends SecureStorageHelper {
  _ControlledStorage() : super(const FlutterSecureStorage());

  final List<Completer<void>> writes = <Completer<void>>[];

  @override
  Future<void> saveOkxCredentials({
    required String apiKey,
    required String secretKey,
    required String passphrase,
  }) {
    final write = Completer<void>();
    writes.add(write);
    return trackOkxCredentialMutation(() => write.future);
  }

  @override
  Future<void> clearOkxCredentials() {
    final write = Completer<void>();
    writes.add(write);
    return trackOkxCredentialMutation(() => write.future);
  }
}
