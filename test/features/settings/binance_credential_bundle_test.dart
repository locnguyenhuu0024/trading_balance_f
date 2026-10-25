import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/settings/domain/binance_credential_bundle.dart';

void main() {
  group('RED-116', () {
    test(
      'rejects missing, partial, malformed, and future credential bundles',
      () {
        const invalidRecords = <String?>[
          null,
          '',
          '{',
          '{"version":1,"apiKey":"fixture-key"}',
          '{"version":2,"apiKey":"fixture-key","secretKey":"fixture-secret"}',
          '{"version":1.0,"apiKey":"fixture-key","secretKey":"fixture-secret"}',
          '{"version":1,"apiKey":" ","secretKey":"fixture-secret"}',
          '{"version":1,"apiKey":"fixture-key","secretKey":4}',
          '{"version":1,"apiKey":"fixture-key","secretKey":"fixture-secret","oldKey":"stale"}',
        ];

        for (final record in invalidRecords) {
          expect(BinanceCredentialBundle.tryDecode(record), isNull);
        }
        expect(
          BinanceCredentialBundle.tryCreate(apiKey: '', secretKey: 'secret'),
          isNull,
        );
        expect(
          BinanceCredentialBundle.tryCreate(apiKey: 'key', secretKey: '  '),
          isNull,
        );
      },
    );
  });

  group('GREEN-116', () {
    test('round-trips one complete versioned key and secret pair', () {
      final bundle = BinanceCredentialBundle.tryCreate(
        apiKey: 'fixture-api-key',
        secretKey: 'fixture-secret',
      );

      expect(bundle, isNotNull);
      final encoded = bundle!.encode();
      expect(encoded, contains('"version":1'));
      expect(
        BinanceCredentialBundle.tryDecode(encoded)?.apiKey,
        'fixture-api-key',
      );
      expect(
        BinanceCredentialBundle.tryDecode(encoded)?.secretKey,
        'fixture-secret',
      );
      expect(
        BinanceCredentialBundle.storageKey,
        'BINANCE_CREDENTIAL_BUNDLE_V1',
      );
    });
  });
}
