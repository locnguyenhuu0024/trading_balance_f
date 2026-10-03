import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Dedicated semantic PnL colors; the shared app palette remains monochrome.
class PnlColors {
  PnlColors._();

  static const lightPositive = Color(0xFF167D3C);
  static const lightNegative = Color(0xFFB42318);
  static const darkPositive = Color(0xFF4ADE80);
  static const darkNegative = Color(0xFFF87171);
}

/// Resolves PnL colors without exposing a sign for hidden or insignificant data.
Color resolvePnlColor(
  double? value,
  AppPalette palette, {
  bool hidden = false,
}) {
  if (hidden || value == null || !value.isFinite || value.abs() < 0.005) {
    return palette.muted;
  }

  final isDark = palette.background == AppPalette.dark.background;
  if (value > 0) {
    return isDark ? PnlColors.darkPositive : PnlColors.lightPositive;
  }
  return isDark ? PnlColors.darkNegative : PnlColors.lightNegative;
}
