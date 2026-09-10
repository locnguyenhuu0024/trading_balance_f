import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/formatting/adaptive_number_format.dart';

void main() {
  group('formatAdaptiveNumber', () {
    const cases = <String, String>{
      'empty values use the placeholder': '',
      'invalid values are preserved': 'not-a-number',
      'zero keeps two decimals': '0',
      'small values keep adaptive precision': '0.09117',
      'very small values keep eight decimal places': '0.00001234',
      'small values round at eight decimals': '0.123456789',
      'one keeps two decimals': '1',
      'values below one thousand round at four decimals': '999.99999',
      'one thousand uses grouped two-decimal formatting': '1000',
      'large values use grouped two-decimal formatting': '1234567.89',
    };

    final expected = <String>[
      '--',
      'not-a-number',
      '0.00',
      '0.09117',
      '0.00001234',
      '0.12345679',
      '1.00',
      '1,000.00',
      '1,000.00',
      '1,234,567.89',
    ];

    for (final (index, entry) in cases.entries.indexed) {
      test(entry.key, () {
        expect(formatAdaptiveNumber(entry.value), expected[index]);
      });
    }

    test('preserves the sign for small values', () {
      expect(formatAdaptiveNumber('-0.09117'), '-0.09117');
    });
  });
}
