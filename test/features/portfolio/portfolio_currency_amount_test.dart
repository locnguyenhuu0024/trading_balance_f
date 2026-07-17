import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/currency/currency_display_mode.dart';
import 'package:trading_balance_f/features/portfolio/presentation/widgets/portfolio_currency_amount.dart';

void main() {
  const rate = 25400.0;

  test('formats USD and VNĐ as single-line values', () {
    expect(
      formatPortfolioCurrencyLines(
        usdtAmount: 1234.5,
        currencyMode: CurrencyDisplayMode.usd,
        vndRate: rate,
      ),
      const PortfolioCurrencyLines(primary: r'$1,234.50'),
    );
    expect(
      formatPortfolioCurrencyLines(
        usdtAmount: 1234.5,
        currencyMode: CurrencyDisplayMode.vnd,
        vndRate: rate,
      ),
      const PortfolioCurrencyLines(primary: '31.356.300 đ'),
    );
  });

  test('formats USDT above VND in dual mode', () {
    expect(
      formatPortfolioCurrencyLines(
        usdtAmount: 1234.5,
        currencyMode: CurrencyDisplayMode.usdtVnd,
        vndRate: rate,
      ),
      const PortfolioCurrencyLines(
        primary: '1,234.50 USDT',
        secondary: '≈ 31.356.300 đ',
      ),
    );
  });

  test('preserves P&L sign on both lines and hides both lines', () {
    expect(
      formatPortfolioCurrencyLines(
        usdtAmount: -12.5,
        currencyMode: CurrencyDisplayMode.usdtVnd,
        vndRate: rate,
        showPositiveSign: true,
      ),
      const PortfolioCurrencyLines(
        primary: '-12.50 USDT',
        secondary: '≈ -317.500 đ',
      ),
    );
    expect(
      formatPortfolioCurrencyLines(
        usdtAmount: 12.5,
        currencyMode: CurrencyDisplayMode.usdtVnd,
        vndRate: rate,
        hidden: true,
      ),
      const PortfolioCurrencyLines(primary: '******', secondary: '******'),
    );
  });

  testWidgets('renders dual values as two text lines', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PortfolioCurrencyAmount(
            usdtAmount: 10,
            currencyMode: CurrencyDisplayMode.usdtVnd,
            vndRate: rate,
          ),
        ),
      ),
    );

    expect(find.text('10.00 USDT'), findsOneWidget);
    expect(find.text('≈ 254.000 đ'), findsOneWidget);
  });
}
