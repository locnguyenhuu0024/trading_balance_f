import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppTextScaleOption {
  const AppTextScaleOption({required this.value, required this.label});

  final double value;
  final String label;
}

/// Application-wide text scale choices and safe platform-scale composition.
abstract final class AppTextScale {
  static const defaultScale = 1.0;
  static const minScale = 0.9;
  static const maxScale = 1.3;

  static const options = <AppTextScaleOption>[
    AppTextScaleOption(value: 0.9, label: 'Nhỏ'),
    AppTextScaleOption(value: 1.0, label: 'Mặc định'),
    AppTextScaleOption(value: 1.15, label: 'Lớn'),
    AppTextScaleOption(value: 1.3, label: 'Rất lớn'),
  ];

  static double normalize(Object? value) {
    final parsed = _numberFrom(value);
    if (parsed == null ||
        !parsed.isFinite ||
        parsed < minScale ||
        parsed > maxScale ||
        !options.any((option) => option.value == parsed)) {
      return defaultScale;
    }
    return parsed;
  }

  /// Applies the app multiplier once on top of the platform baseline scale.
  static TextScaler combine(TextScaler platformScaler, double appScale) {
    final platformBaseline = platformScaler.scale(1);
    return TextScaler.linear(platformBaseline * normalize(appScale));
  }

  static double? _numberFrom(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

final appTextScaleProvider = StateProvider<double>(
  (ref) => AppTextScale.defaultScale,
);
