import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trading_balance_f/core/exchange/exchange_models.dart';
import 'package:trading_balance_f/exchanges/binance/binance_adapter.dart';
import 'package:trading_balance_f/exchanges/binance/binance_private_client.dart';

void main() {
  test('adapter identifies Binance and classifies private failures', () {
    const adapter = BinanceAdapter();
    expect(adapter.id, ExchangeId.binance);
    expect(
      adapter
          .classify(
            const BinancePrivateException(
              ExchangeFailure(ExchangeFailureKind.credential),
            ),
          )
          .kind,
      ExchangeFailureKind.credential,
    );
  });
  test('Spot and Margin availability follows web and proxy providers', () {
    final web = ProviderContainer(
      overrides: [
        binanceIsWebProvider.overrideWithValue(true),
        binanceProxyBaseUrlProvider.overrideWithValue(''),
      ],
    );
    addTearDown(web.dispose);
    expect(web.read(binanceSpotMarginAvailableProvider), isFalse);
    final proxied = ProviderContainer(
      overrides: [
        binanceIsWebProvider.overrideWithValue(true),
        binanceProxyBaseUrlProvider.overrideWithValue('https://proxy.example'),
      ],
    );
    addTearDown(proxied.dispose);
    expect(proxied.read(binanceSpotMarginAvailableProvider), isTrue);
    expect(
      normalizeBinanceProxyBaseUrl('https://proxy.example/'),
      'https://proxy.example',
    );
  });
}
