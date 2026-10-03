import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/theme/app_theme.dart';
import 'package:trading_balance_f/core/theme/pnl_color.dart';

void main() {
  test('PnL colors use a signed threshold in both themes', () {
    expect(resolvePnlColor(0.005, AppPalette.light), PnlColors.lightPositive);
    expect(resolvePnlColor(-0.005, AppPalette.light), PnlColors.lightNegative);
    expect(resolvePnlColor(0.005, AppPalette.dark), PnlColors.darkPositive);
    expect(resolvePnlColor(-0.005, AppPalette.dark), PnlColors.darkNegative);
  });

  test(
    'hidden, invalid, negative zero, and sub-threshold values are muted',
    () {
      for (final value in <double?>[
        null,
        double.nan,
        double.infinity,
        double.negativeInfinity,
        -0.0,
        0.004999,
        -0.004999,
      ]) {
        expect(
          resolvePnlColor(value, AppPalette.light),
          AppPalette.light.muted,
        );
        expect(resolvePnlColor(value, AppPalette.dark), AppPalette.dark.muted);
      }
      expect(
        resolvePnlColor(12.0, AppPalette.light, hidden: true),
        AppPalette.light.muted,
      );
      expect(
        resolvePnlColor(-12.0, AppPalette.dark, hidden: true),
        AppPalette.dark.muted,
      );
    },
  );

  test('general palette sign roles remain grayscale', () {
    expect(AppPalette.light.positive, const Color(0xFF303030));
    expect(AppPalette.light.negative, const Color(0xFF646464));
    expect(AppPalette.dark.positive, const Color(0xFFF0F0F0));
    expect(AppPalette.dark.negative, const Color(0xFFBEBEBE));
  });
}
