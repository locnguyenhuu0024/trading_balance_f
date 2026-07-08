import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('crypto icon URLs', () {
    final screenFiles = [
      File('lib/features/market/presentation/market_screen.dart'),
      File('lib/features/orders/presentation/orders_screen.dart'),
      File('lib/features/portfolio/presentation/portfolio_screen.dart'),
    ];

    test('use GitHub raw icon host instead of CoinCap', () {
      for (final file in screenFiles) {
        final source = file.readAsStringSync();

        expect(
          source,
          isNot(contains('https://assets.coincap.io/assets/icons/')),
          reason: '${file.path} should avoid the CoinCap icon host',
        );
        expect(
          source,
          contains(
            'https://raw.githubusercontent.com/spothq/cryptocurrency-icons/master/128/color/',
          ),
          reason: '${file.path} should use the CORS-friendly icon host',
        );
      }
    });

    test('lowercase coin symbols before building icon URLs', () {
      final expressions = {
        'lib/features/market/presentation/market_screen.dart':
            r'${t.coinSymbol.toLowerCase()}.png',
        'lib/features/orders/presentation/orders_screen.dart':
            r'${baseCoin.toLowerCase()}.png',
        'lib/features/portfolio/presentation/portfolio_screen.dart':
            r'${coin.ccy.toLowerCase()}.png',
      };

      for (final entry in expressions.entries) {
        final source = File(entry.key).readAsStringSync();

        expect(source, contains(entry.value));
      }
    });
  });
}
