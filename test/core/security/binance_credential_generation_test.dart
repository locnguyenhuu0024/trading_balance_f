import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/features/settings/domain/binance_credential_bundle.dart';
import 'package:trading_balance_f/main.dart' show WebStorageHelper;

void main() {
  group('RED-116', () {
    test(
      'native write exceptions fence the current generation before and after commit',
      () async {
        for (final failAfterWrite in <bool>[false, true]) {
          final records = <String, String>{
            SecureStorageHelper.binanceCredentialBundleStorageKey: _oldRecord,
          };
          final storage = _MemoryBinanceStorage(records)
            ..failBeforeWrite = !failAfterWrite
            ..failAfterWrite = failAfterWrite;

          Object? saveError;
          try {
            await storage.saveBinanceCredentials(
              apiKey: 'fixture-new-api-key',
              secretKey: 'fixture-new-secret',
            );
          } catch (error) {
            saveError = error;
          }

          expect(saveError, isA<BinanceCredentialStorageException>());
          expect(storage.writeCount, 1);
          expect(
            storage.binanceCredentialState.value.canUsePrivateReads,
            isFalse,
          );
          expect(saveError.toString(), isNot(contains('fixture-new-api-key')));
          expect(saveError.toString(), isNot(contains('fixture-new-secret')));

          final reloaded = _MemoryBinanceStorage(records);
          final bundle = BinanceCredentialBundle.tryDecode(
            await reloaded.getBinanceCredentialBundle(),
          );
          expect(bundle, isNotNull);
          expect(
            bundle!.apiKey,
            failAfterWrite ? 'fixture-new-api-key' : 'fixture-old-api-key',
          );
          expect(
            bundle.secretKey,
            failAfterWrite ? 'fixture-new-secret' : 'fixture-old-secret',
          );
          expect(
            reloaded.binanceCredentialState.value.canUsePrivateReads,
            isTrue,
          );
          storage
            ..failBeforeWrite = false
            ..failAfterWrite = false;
          await storage.saveBinanceCredentials(
            apiKey: 'fixture-recovered-key',
            secretKey: 'fixture-recovered-secret',
          );
          expect(
            storage.binanceCredentialState.value.canUsePrivateReads,
            isTrue,
          );
          reloaded.dispose();
          storage.dispose();
        }
      },
    );

    test(
      'concurrent save and clear serialize one-key writes and fence both sides',
      () async {
        final storage = _MemoryBinanceStorage(<String, String>{});
        final firstStarted = Completer<void>();
        final releaseFirst = Completer<void>();
        storage.firstWriteStarted = firstStarted;
        storage.firstWriteGate = releaseFirst.future;
        final changes = <BinanceCredentialSnapshot>[];
        storage.binanceCredentialState.addListener(
          () => changes.add(storage.binanceCredentialState.value),
        );

        final save = storage.saveBinanceCredentials(
          apiKey: 'fixture-first-key',
          secretKey: 'fixture-first-secret',
        );
        await firstStarted.future;
        final clear = storage.clearBinanceCredentials();
        expect(storage.deleteCount, 0);
        expect(
          storage.binanceCredentialState.value.canUsePrivateReads,
          isFalse,
        );

        releaseFirst.complete();
        await save;
        await clear;

        expect(storage.writeCount, 1);
        expect(storage.deleteCount, 1);
        expect(storage.records, isEmpty);
        expect(changes, const <BinanceCredentialSnapshot>[
          BinanceCredentialSnapshot(
            generation: 1,
            rotating: true,
            privateReadsEnabled: false,
          ),
          BinanceCredentialSnapshot(
            generation: 2,
            rotating: true,
            privateReadsEnabled: false,
          ),
          BinanceCredentialSnapshot(
            generation: 3,
            rotating: true,
            privateReadsEnabled: false,
          ),
          BinanceCredentialSnapshot(
            generation: 4,
            rotating: false,
            privateReadsEnabled: true,
          ),
        ]);
        storage.dispose();
      },
    );

    test(
      'native delete exceptions fence reads before and after deletion',
      () async {
        for (final failAfterDelete in <bool>[false, true]) {
          final records = <String, String>{
            BinanceCredentialBundle.storageKey: _oldRecord,
          };
          final storage = _MemoryBinanceStorage(records)
            ..failBeforeDelete = !failAfterDelete
            ..failAfterDelete = failAfterDelete;

          Object? clearError;
          try {
            await storage.clearBinanceCredentials();
          } catch (error) {
            clearError = error;
          }

          expect(clearError, isA<BinanceCredentialStorageException>());
          expect(storage.deleteCount, 1);
          expect(
            storage.binanceCredentialState.value.canUsePrivateReads,
            isFalse,
          );
          expect(clearError.toString(), isNot(contains('fixture-old-api-key')));
          expect(clearError.toString(), isNot(contains('fixture-old-secret')));
          final reloaded = _MemoryBinanceStorage(records);
          final bundle = BinanceCredentialBundle.tryDecode(
            await reloaded.getBinanceCredentialBundle(),
          );
          expect(bundle != null, !failAfterDelete);
          if (bundle != null) {
            expect(bundle.apiKey, 'fixture-old-api-key');
            expect(bundle.secretKey, 'fixture-old-secret');
          }
          storage
            ..failBeforeDelete = false
            ..failAfterDelete = false;
          await storage.saveBinanceCredentials(
            apiKey: 'fixture-recovered-delete-key',
            secretKey: 'fixture-recovered-delete-secret',
          );
          expect(
            storage.binanceCredentialState.value.canUsePrivateReads,
            isTrue,
          );
          reloaded.dispose();
          storage.dispose();
        }
      },
    );

    test(
      'web false results disable reads whether the bundle write happened or not',
      () async {
        for (final persistBeforeFalse in <bool>[false, true]) {
          SharedPreferences.setMockInitialValues(<String, Object>{});
          final preferences = await SharedPreferences.getInstance();
          final storage = _FalseWebStorage(
            preferences,
            persistBeforeFalse: persistBeforeFalse,
          );

          Object? saveError;
          try {
            await storage.saveBinanceCredentials(
              apiKey: 'fixture-web-key',
              secretKey: 'fixture-web-secret',
            );
          } catch (error) {
            saveError = error;
          }

          expect(saveError, isA<BinanceCredentialStorageException>());
          expect(saveError.toString(), isNot(contains('fixture-web-key')));
          expect(saveError.toString(), isNot(contains('fixture-web-secret')));
          expect(
            storage.binanceCredentialState.value.canUsePrivateReads,
            isFalse,
          );
          final raw = await storage.getBinanceCredentialBundle();
          final bundle = BinanceCredentialBundle.tryDecode(raw);
          expect(bundle != null, persistBeforeFalse);
          if (bundle != null) {
            expect(bundle.apiKey, 'fixture-web-key');
            expect(bundle.secretKey, 'fixture-web-secret');
          }
          expect(
            preferences
                .getKeys()
                .where((key) => key == BinanceCredentialBundle.storageKey)
                .length,
            persistBeforeFalse ? 1 : 0,
          );
          storage.returnFalse = false;
          await storage.saveBinanceCredentials(
            apiKey: 'fixture-recovered-web-key',
            secretKey: 'fixture-recovered-web-secret',
          );
          expect(
            storage.binanceCredentialState.value.canUsePrivateReads,
            isTrue,
          );
          storage.dispose();
        }
      },
    );

    test(
      'web false delete results fence reads before and after deletion',
      () async {
        for (final deleteBeforeFalse in <bool>[false, true]) {
          SharedPreferences.setMockInitialValues(<String, Object>{
            BinanceCredentialBundle.storageKey: _oldRecord,
          });
          final preferences = await SharedPreferences.getInstance();
          final storage = _FalseWebDeleteStorage(
            preferences,
            deleteBeforeFalse: deleteBeforeFalse,
          );

          Object? clearError;
          try {
            await storage.clearBinanceCredentials();
          } catch (error) {
            clearError = error;
          }

          expect(clearError, isA<BinanceCredentialStorageException>());
          expect(
            storage.binanceCredentialState.value.canUsePrivateReads,
            isFalse,
          );
          final remaining = BinanceCredentialBundle.tryDecode(
            await storage.getBinanceCredentialBundle(),
          );
          expect(remaining != null, !deleteBeforeFalse);
          if (remaining != null) {
            expect(remaining.apiKey, 'fixture-old-api-key');
            expect(remaining.secretKey, 'fixture-old-secret');
          }
          storage.returnFalse = false;
          await storage.saveBinanceCredentials(
            apiKey: 'fixture-web-recovered-delete-key',
            secretKey: 'fixture-web-recovered-delete-secret',
          );
          expect(
            storage.binanceCredentialState.value.canUsePrivateReads,
            isTrue,
          );
          storage.dispose();
        }
      },
    );
  });

  group('GREEN-116', () {
    test(
      'native save and clear each use the single versioned bundle key',
      () async {
        final storage = _MemoryBinanceStorage(<String, String>{});
        final changes = <BinanceCredentialSnapshot>[];
        storage.binanceCredentialState.addListener(
          () => changes.add(storage.binanceCredentialState.value),
        );

        await storage.saveBinanceCredentials(
          apiKey: 'fixture-native-key',
          secretKey: 'fixture-native-secret',
        );
        final saved = storage.records[BinanceCredentialBundle.storageKey];
        expect(
          BinanceCredentialBundle.tryDecode(saved)?.apiKey,
          'fixture-native-key',
        );
        expect(storage.records.keys, hasLength(1));
        expect(storage.records, contains(BinanceCredentialBundle.storageKey));
        await storage.clearBinanceCredentials();

        expect(storage.records, isEmpty);
        expect(storage.writeCount, 1);
        expect(storage.deleteCount, 1);
        expect(changes.first.rotating, isTrue);
        expect(changes[1].canUsePrivateReads, isTrue);
        expect(changes[2].rotating, isTrue);
        expect(changes.last.canUsePrivateReads, isTrue);
        storage.dispose();
      },
    );

    test('web save and clear fence the single bundle mutation', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = await SharedPreferences.getInstance();
      final storage = WebStorageHelper(preferences);
      final changes = <BinanceCredentialSnapshot>[];
      storage.binanceCredentialState.addListener(
        () => changes.add(storage.binanceCredentialState.value),
      );

      await storage.saveBinanceCredentials(
        apiKey: 'fixture-web-key',
        secretKey: 'fixture-web-secret',
      );
      expect(
        BinanceCredentialBundle.tryDecode(
          await storage.getBinanceCredentialBundle(),
        )?.secretKey,
        'fixture-web-secret',
      );
      expect(
        preferences.getKeys(),
        contains(BinanceCredentialBundle.storageKey),
      );
      await storage.clearBinanceCredentials();

      expect(await storage.getBinanceCredentialBundle(), isNull);
      expect(changes, hasLength(4));
      expect(changes[0].rotating, isTrue);
      expect(changes[1].canUsePrivateReads, isTrue);
      expect(changes[2].rotating, isTrue);
      expect(changes[3].canUsePrivateReads, isTrue);
      storage.dispose();
    });
  });
}

class _MemoryBinanceStorage extends SecureStorageHelper {
  _MemoryBinanceStorage(this.records) : super(const FlutterSecureStorage());

  final Map<String, String> records;
  bool failBeforeWrite = false;
  bool failAfterWrite = false;
  bool failBeforeDelete = false;
  bool failAfterDelete = false;
  int writeCount = 0;
  int deleteCount = 0;
  Completer<void>? firstWriteStarted;
  Future<void>? firstWriteGate;

  @override
  Future<void> writeBinanceCredentialBundle(String value) async {
    writeCount++;
    if (writeCount == 1) {
      firstWriteStarted?.complete();
      if (firstWriteGate != null) await firstWriteGate;
    }
    if (failBeforeWrite) {
      throw StateError('fixture-new-api-key fixture-new-secret');
    }
    records[BinanceCredentialBundle.storageKey] = value;
    if (failAfterWrite) {
      throw StateError('fixture-new-api-key fixture-new-secret');
    }
  }

  @override
  Future<String?> readBinanceCredentialBundle() async =>
      records[BinanceCredentialBundle.storageKey];

  @override
  Future<void> deleteBinanceCredentialBundle() async {
    deleteCount++;
    if (failBeforeDelete) {
      throw StateError('fixture-old-api-key fixture-old-secret');
    }
    records.remove(BinanceCredentialBundle.storageKey);
    if (failAfterDelete) {
      throw StateError('fixture-old-api-key fixture-old-secret');
    }
  }
}

class _FalseWebStorage extends WebStorageHelper {
  _FalseWebStorage(this.preferences, {required this.persistBeforeFalse})
    : super(preferences);

  final SharedPreferences preferences;
  final bool persistBeforeFalse;
  bool returnFalse = true;

  @override
  Future<bool> writeWebBinanceCredentialBundle(String value) async {
    if (returnFalse && persistBeforeFalse) {
      await preferences.setString(BinanceCredentialBundle.storageKey, value);
    }
    if (returnFalse) return false;
    return super.writeWebBinanceCredentialBundle(value);
  }
}

class _FalseWebDeleteStorage extends WebStorageHelper {
  _FalseWebDeleteStorage(this.preferences, {required this.deleteBeforeFalse})
    : super(preferences);

  final SharedPreferences preferences;
  final bool deleteBeforeFalse;
  bool returnFalse = true;

  @override
  Future<bool> deleteWebBinanceCredentialBundle() async {
    if (returnFalse) {
      if (deleteBeforeFalse) {
        await preferences.remove(BinanceCredentialBundle.storageKey);
      }
      return false;
    }
    return super.deleteWebBinanceCredentialBundle();
  }
}

const _oldRecord =
    '{"version":1,"apiKey":"fixture-old-api-key","secretKey":"fixture-old-secret"}';
