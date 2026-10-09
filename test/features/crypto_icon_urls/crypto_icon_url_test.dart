import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/widgets/crypto_icon.dart';

void main() {
  group('crypto icon URLs', () {
    final screenFiles = [
      File('lib/features/market/presentation/market_screen.dart'),
      File('lib/features/orders/presentation/orders_screen.dart'),
      File('lib/features/portfolio/presentation/portfolio_screen.dart'),
    ];

    test('screens use the shared CryptoIcon widget', () {
      for (final file in screenFiles) {
        final source = file.readAsStringSync();

        expect(
          source,
          contains('CryptoIcon('),
          reason: '${file.path} should use the shared icon widget',
        );
        expect(
          source,
          isNot(contains('Image.network(')),
          reason: '${file.path} should not build icon images directly',
        );
        expect(
          source,
          isNot(contains('https://assets.coincap.io/assets/icons/')),
          reason: '${file.path} should avoid the CoinCap icon host',
        );
      }
    });

    test('lowercases symbols and keeps GitHub raw as first source', () {
      final urls = CryptoIconUrls.forSymbol(' BTC ');

      expect(urls.first, CryptoIconUrls.githubRawUrl('btc'));
    });

    test('adds broader fallback sources for commonly missing icons', () {
      final urls = CryptoIconUrls.forSymbol('SUI');

      expect(urls, contains(CryptoIconUrls.githubRawUrl('sui')));
      expect(
        urls,
        contains(
          'https://coin-images.coingecko.com/coins/images/26375/large/sui-ocean-square.png',
        ),
      );
    });

    test('falls back to text when there is no symbol', () {
      expect(CryptoIconUrls.forSymbol(''), isEmpty);
      expect(CryptoIconFallback.letter(''), '?');
      expect(CryptoIconFallback.letter('eth'), 'E');
    });
  });
}
