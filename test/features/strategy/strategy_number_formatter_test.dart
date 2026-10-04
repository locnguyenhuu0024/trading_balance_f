import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/strategy/presentation/strategy_number_formatter.dart';

void main() {
  test('formats amounts by magnitude and restores negative signs', () {
    expect(StrategyNumberFormatter.amount('1234.56789'), '1,234.57');
    expect(StrategyNumberFormatter.amount('-1.23456789'), '-1.2346');
    expect(StrategyNumberFormatter.amount('-0.123456789'), '-0.12345679');
  });

  test('keeps tiny nonzero values visible in compact notation', () {
    expect(StrategyNumberFormatter.amount('0.000000004'), '4e-9');
    expect(StrategyNumberFormatter.amount('-4e-9'), '-4e-9');
  });

  test('formats percentages to two decimals without negative zero', () {
    expect(StrategyNumberFormatter.percent('-0.006'), '-0.01');
    expect(StrategyNumberFormatter.percent('-0.004'), '0.00');
  });

  test('uses the caller placeholder for missing and invalid values', () {
    expect(StrategyNumberFormatter.amount(null), '--');
    expect(StrategyNumberFormatter.amount('NaN'), '--');
    expect(StrategyNumberFormatter.amount('Infinity'), '--');
    expect(StrategyNumberFormatter.percent('invalid', placeholder: '—'), '—');
    expect(StrategyNumberFormatter.amount(-0.0), '0.00');
  });
}
