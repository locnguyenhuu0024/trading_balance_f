import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  test(
    'GREEN-002 secure writes serialize and stale cleanup preserves newer password',
    () async {
      final values = <String, String>{};
      final writes = <Map<String, Object?>>[];
      final reads = <String>[];
      final firstWriteGate = Completer<void>();
      var blockFirstWrite = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final arguments = Map<Object?, Object?>.from(call.arguments as Map);
            final key = arguments['key']! as String;
            switch (call.method) {
              case 'read':
                reads.add(key);
                return values[key];
              case 'write':
                writes.add(Map<String, Object?>.from(arguments));
                if (blockFirstWrite) {
                  blockFirstWrite = false;
                  await firstWriteGate.future;
                }
                values[key] = arguments['value']! as String;
                return null;
              case 'delete':
                values.remove(key);
                return null;
              default:
                fail('Unexpected secure-storage method: ${call.method}');
            }
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final storage = SecureStorageHelper(const FlutterSecureStorage());
      const endpoint = 'https://trade.example/';
      final olderWrite = storage.saveRememberedTradePassword(
        endpoint,
        'older-password',
      );
      await Future<void>.delayed(Duration.zero);
      expect(writes, hasLength(1));

      final newerWrite = storage.saveRememberedTradePassword(
        endpoint,
        'newer-password',
      );
      await Future<void>.delayed(Duration.zero);
      expect(writes, hasLength(1));

      firstWriteGate.complete();
      final olderVersion = await olderWrite;
      final newerVersion = await newerWrite;
      expect(writes, hasLength(2));
      expect(
        await storage.getRememberedTradePassword(endpoint),
        'newer-password',
      );
      expect(
        await storage.deleteRememberedTradePasswordIfVersion(
          endpoint,
          olderVersion,
        ),
        isFalse,
      );
      expect(
        await storage.getRememberedTradePassword(endpoint),
        'newer-password',
      );
      expect(newerVersion, isNot(olderVersion));
      expect(reads, isNotEmpty);

      final records = writes.map((write) => write['value'] as String).toList();
      expect(records.every((record) => record.contains('password')), isTrue);
      expect(records.any((record) => record.contains('totp')), isFalse);
      expect(
        writes.every(
          (write) => (write['key'] as String).startsWith(
            'REMEMBERED_TRADE_PASSWORD_V1_',
          ),
        ),
        isTrue,
      );
    },
  );

  test(
    'corrupt secure record is ignored and endpoint scopes stay separate',
    () async {
      final values = <String, String>{};
      final reads = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final arguments = Map<Object?, Object?>.from(call.arguments as Map);
            final key = arguments['key']! as String;
            if (call.method == 'read') {
              reads.add(key);
              return values[key];
            }
            if (call.method == 'write') {
              values[key] = arguments['value']! as String;
              return null;
            }
            if (call.method == 'delete') {
              values.remove(key);
              return null;
            }
            fail('Unexpected secure-storage method: ${call.method}');
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final storage = SecureStorageHelper(const FlutterSecureStorage());
      const endpoint = 'https://trade.example/';
      expect(await storage.getRememberedTradePassword(endpoint), isNull);
      values[reads.single] = 'corrupt record with no password';
      expect(await storage.getRememberedTradePassword(endpoint), isNull);
      expect(
        await storage.getRememberedTradePassword('https://other.example/'),
        isNull,
      );
      expect(reads[0], reads[1]);
      expect(reads[0], isNot(reads[2]));
    },
  );
}
