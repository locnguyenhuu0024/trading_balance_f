import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/settings/domain/okx_credential_bundle.dart';

void main() {
  group('OkxCredentialBundle.parse', () {
    test(
      'normalizes labeled aliases and splits values at the first delimiter',
      () {
        final credentials = OkxCredentialBundle.parse(
          'api_key =  demo:api=tail  \r\n\n'
          'SECRET-KEY:  demo:secret=tail\r\n'
          'Passphrase: demo-pass',
        );

        expect(credentials.apiKey, 'demo:api=tail');
        expect(credentials.secretKey, 'demo:secret=tail');
        expect(credentials.passphrase, 'demo-pass');
      },
    );

    test('parses a flat JSON string object with normalized aliases', () {
      final credentials = OkxCredentialBundle.parse(
        '{"API_KEY":" demo-api ",'
        '"secret":"demo:secret=tail",'
        '"PASS-PHRASE":"demo-pass"}',
      );

      expect(credentials.apiKey, 'demo-api');
      expect(credentials.secretKey, 'demo:secret=tail');
      expect(credentials.passphrase, 'demo-pass');
    });

    test('decodes JSON string escapes before returning values', () {
      final credentials = OkxCredentialBundle.parse(
        r'{"apiKey":"demo\u002dapi",'
        r'"secretKey":"demo\u003asecret",'
        r'"passphrase":"demo-pass"}',
      );

      expect(credentials.apiKey, 'demo-api');
      expect(credentials.secretKey, 'demo:secret');
      expect(credentials.passphrase, 'demo-pass');
    });

    test('rejects identical duplicate JSON keys before map conversion', () {
      const input =
          '{"apiKey":"DO_NOT_ECHO","apiKey":"second",'
          '"secretKey":"secret","passphrase":"pass"}';
      _expectGenericRejection(input);
    });

    test('rejects aliases that normalize to the same credential', () {
      const input =
          '{"api_key":"DO_NOT_ECHO","API Key":"second",'
          '"secretKey":"secret","passphrase":"pass"}';
      _expectGenericRejection(input);
    });

    test('rejects invalid, incomplete, non-flat, and ambiguous input', () {
      const invalidInputs = [
        '',
        '   ',
        'API Key: api\nSecret Key: secret',
        'unlabeled DO_NOT_ECHO',
        'Unknown Key: DO_NOT_ECHO\nSecret Key: secret\nPassphrase: pass',
        'API Key: api\nSecret Key: secret\nPassphrase: pass\nextra text',
        'API Key: DO_NOT_ECHO\napi_key=second\n'
            'Secret Key: secret\nPassphrase: pass',
        '{"apiKey":"api","secretKey":"secret",',
        '{"apiKey":"api","secretKey":"secret",'
            '"passphrase":"pass",}',
        '{"apiKey":"api","secretKey":"secret",'
            '"passphrase":"pass"} trailing',
        '{"apiKey":42,"secretKey":"secret","passphrase":"pass"}',
        '{"apiKey":null,"secretKey":"secret","passphrase":"pass"}',
        '{"apiKey":true,"secretKey":"secret","passphrase":"pass"}',
        '{"apiKey":["api"],"secretKey":"secret",'
            '"passphrase":"pass"}',
        '{"apiKey":{"nested":"api"},"secretKey":"secret",'
            '"passphrase":"pass"}',
        '["api","secret","pass"]',
        'API Key: \nSecret Key: secret\nPassphrase: pass',
        '{"apiKey":"   ","secretKey":"secret",'
            '"passphrase":"pass"}',
      ];

      for (final input in invalidInputs) {
        _expectGenericRejection(input);
      }
    });
  });
}

void _expectGenericRejection(String input) {
  Object? caught;
  try {
    OkxCredentialBundle.parse(input);
  } on FormatException catch (error) {
    caught = error;
  }

  expect(caught, isA<FormatException>());
  final error = caught! as FormatException;
  expect(error.message, OkxCredentialBundle.invalidInputMessage);
  expect(error.toString(), isNot(contains('DO_NOT_ECHO')));
}
