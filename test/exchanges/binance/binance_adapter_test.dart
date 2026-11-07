import 'package:flutter_test/flutter_test.dart';
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
}
