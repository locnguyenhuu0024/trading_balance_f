import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:trading_balance_f/core/currency/currency_display_mode.dart';

@immutable
class PortfolioCurrencyLines {
  const PortfolioCurrencyLines({required this.primary, this.secondary});

  final String primary;
  final String? secondary;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PortfolioCurrencyLines &&
            other.primary == primary &&
            other.secondary == secondary;
  }

  @override
  int get hashCode => Object.hash(primary, secondary);
}

PortfolioCurrencyLines formatPortfolioCurrencyLines({
  required double usdtAmount,
  required String currencyMode,
  required double vndRate,
  bool hidden = false,
  bool showPositiveSign = false,
}) {
  if (hidden) {
    return PortfolioCurrencyLines(
      primary: '******',
      secondary: currencyMode == CurrencyDisplayMode.usdtVnd ? '******' : null,
    );
  }

  final absoluteAmount = usdtAmount.abs();
  final sign = usdtAmount < 0
      ? '-'
      : (showPositiveSign && usdtAmount > 0 ? '+' : '');
  final usdt = NumberFormat('#,##0.00', 'en_US').format(absoluteAmount);
  final vnd = NumberFormat('#,##0', 'vi_VN').format(absoluteAmount * vndRate);

  if (currencyMode == CurrencyDisplayMode.vnd) {
    return PortfolioCurrencyLines(primary: '$sign$vnd đ');
  }
  if (currencyMode == CurrencyDisplayMode.usdtVnd) {
    return PortfolioCurrencyLines(
      primary: '$sign$usdt USDT',
      secondary: '≈ $sign$vnd đ',
    );
  }
  return PortfolioCurrencyLines(primary: '$sign\$$usdt');
}

class PortfolioCurrencyAmount extends StatelessWidget {
  const PortfolioCurrencyAmount({
    super.key,
    required this.usdtAmount,
    required this.currencyMode,
    required this.vndRate,
    this.hidden = false,
    this.showPositiveSign = false,
    this.primaryStyle,
    this.secondaryStyle,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.textAlign = TextAlign.left,
    this.primaryPrefix = '',
  });

  final double usdtAmount;
  final String currencyMode;
  final double vndRate;
  final bool hidden;
  final bool showPositiveSign;
  final TextStyle? primaryStyle;
  final TextStyle? secondaryStyle;
  final CrossAxisAlignment crossAxisAlignment;
  final TextAlign textAlign;
  final String primaryPrefix;

  @override
  Widget build(BuildContext context) {
    final lines = formatPortfolioCurrencyLines(
      usdtAmount: usdtAmount,
      currencyMode: currencyMode,
      vndRate: vndRate,
      hidden: hidden,
      showPositiveSign: showPositiveSign,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Text(
          '$primaryPrefix${lines.primary}',
          textAlign: textAlign,
          style: primaryStyle,
        ),
        if (lines.secondary != null) ...[
          const SizedBox(height: 2),
          Text(lines.secondary!, textAlign: textAlign, style: secondaryStyle),
        ],
      ],
    );
  }
}
