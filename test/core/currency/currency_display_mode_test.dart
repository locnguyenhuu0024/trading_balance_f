import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/currency/currency_display_mode.dart';

void main() {
  test('exposes backward-compatible currency values and the dual option', () {
    expect(CurrencyDisplayMode.options.map((option) => option.value), [
      'USD',
      'VNĐ',
      'USDT_VND',
    ]);
    expect(CurrencyDisplayMode.labelFor('USDT_VND'), 'USDT + VND');
  });

  test('identifies modes that require the VND exchange rate', () {
    expect(CurrencyDisplayMode.includesVnd('USD'), isFalse);
    expect(CurrencyDisplayMode.includesVnd('VNĐ'), isTrue);
    expect(CurrencyDisplayMode.includesVnd('USDT_VND'), isTrue);
  });
}
