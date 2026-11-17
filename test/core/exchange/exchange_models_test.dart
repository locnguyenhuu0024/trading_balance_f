import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/exchange/exchange_models.dart';

void main() {
  test('scope identity includes every generation and switch epoch', () {
    const a = ExchangeScope(
      connectionId: 'okx-default',
      exchange: ExchangeId.okx,
      credentialGeneration: 1,
      switchEpoch: 2,
    );
    const same = ExchangeScope(
      connectionId: 'okx-default',
      exchange: ExchangeId.okx,
      credentialGeneration: 1,
      switchEpoch: 2,
    );
    expect(a, same);
    expect(a.hashCode, same.hashCode);
    expect(
      a,
      isNot(
        const ExchangeScope(
          connectionId: 'okx-default',
          exchange: ExchangeId.okx,
          credentialGeneration: 1,
          switchEpoch: 3,
        ),
      ),
    );
    expect(
      a,
      isNot(
        const ExchangeScope(
          connectionId: 'okx-default',
          exchange: ExchangeId.okx,
          credentialGeneration: 2,
          switchEpoch: 2,
        ),
      ),
    );
  });
  test('instrument identity is native and exchange scoped', () {
    const a = InstrumentKey(
      exchange: ExchangeId.okx,
      product: 'SPOT',
      nativeId: 'BTC-USDT',
    );
    expect(
      a,
      isNot(
        const InstrumentKey(
          exchange: ExchangeId.binance,
          product: 'SPOT',
          nativeId: 'BTC-USDT',
        ),
      ),
    );
    expect(
      a,
      isNot(
        const InstrumentKey(
          exchange: ExchangeId.okx,
          product: 'SWAP',
          nativeId: 'BTC-USDT',
        ),
      ),
    );
  });
}
