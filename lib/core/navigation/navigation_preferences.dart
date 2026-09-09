import 'dart:convert';

enum NavigationDisplayMode { bar, floating }

enum NavigationEdge { top, bottom, left, right }

class NavigationAppearanceOption {
  const NavigationAppearanceOption({required this.value, required this.label});

  final double value;
  final String label;
}

/// Local presentation choices for the application's primary navigation.
///
/// The record is intentionally small and versioned so invalid future values do
/// not prevent the application from rendering its safe fixed-bar default.
class NavigationPreferences {
  const NavigationPreferences({
    required this.displayMode,
    required this.floatingEdge,
    this.buttonScale = _defaultButtonScale,
    this.buttonOpacity = _defaultButtonOpacity,
  });

  static const currentVersion = 1;
  static const defaultButtonScale = _defaultButtonScale;
  static const defaultButtonOpacity = _defaultButtonOpacity;
  static const minButtonScale = 0.9;
  static const maxButtonScale = 1.1;
  static const minButtonOpacity = 0.35;
  static const maxButtonOpacity = 1.0;

  static const buttonScaleOptions = <NavigationAppearanceOption>[
    NavigationAppearanceOption(value: 0.9, label: 'Nhỏ'),
    NavigationAppearanceOption(value: 1.0, label: 'Chuẩn'),
    NavigationAppearanceOption(value: 1.1, label: 'Lớn'),
  ];

  static const buttonOpacityOptions = <NavigationAppearanceOption>[
    NavigationAppearanceOption(value: 0.35, label: 'Mờ'),
    NavigationAppearanceOption(value: 0.5, label: 'Mặc định (50%)'),
    NavigationAppearanceOption(value: 0.75, label: 'Rõ (75%)'),
    NavigationAppearanceOption(value: 1.0, label: 'Đục (100%)'),
  ];

  static const defaults = NavigationPreferences(
    displayMode: NavigationDisplayMode.bar,
    floatingEdge: NavigationEdge.bottom,
  );

  final NavigationDisplayMode displayMode;
  final NavigationEdge floatingEdge;
  final double buttonScale;
  final double buttonOpacity;

  NavigationPreferences copyWith({
    NavigationDisplayMode? displayMode,
    NavigationEdge? floatingEdge,
    double? buttonScale,
    double? buttonOpacity,
  }) {
    return NavigationPreferences(
      displayMode: displayMode ?? this.displayMode,
      floatingEdge: floatingEdge ?? this.floatingEdge,
      buttonScale: buttonScale ?? this.buttonScale,
      buttonOpacity: buttonOpacity ?? this.buttonOpacity,
    );
  }

  String encode() {
    return jsonEncode({
      'version': currentVersion,
      'mode': displayMode.name,
      'edge': floatingEdge.name,
      'buttonScale': buttonScale,
      'buttonOpacity': buttonOpacity,
    });
  }

  static NavigationPreferences decode(String? rawValue) {
    if (rawValue == null || rawValue.isEmpty) return defaults;

    try {
      final decoded = jsonDecode(rawValue);
      if (decoded is! Map || decoded['version'] != currentVersion) {
        return defaults;
      }

      return NavigationPreferences(
        displayMode: _displayModeFrom(decoded['mode']),
        floatingEdge: _edgeFrom(decoded['edge']),
        buttonScale: normalizeButtonScale(decoded['buttonScale']),
        buttonOpacity: normalizeButtonOpacity(decoded['buttonOpacity']),
      );
    } on FormatException {
      return defaults;
    } on TypeError {
      return defaults;
    }
  }

  static NavigationDisplayMode _displayModeFrom(Object? value) {
    for (final mode in NavigationDisplayMode.values) {
      if (mode.name == value) return mode;
    }
    return defaults.displayMode;
  }

  static NavigationEdge _edgeFrom(Object? value) {
    for (final edge in NavigationEdge.values) {
      if (edge.name == value) return edge;
    }
    return defaults.floatingEdge;
  }

  static double normalizeButtonScale(Object? value) {
    final parsed = _numberFrom(value);
    if (parsed == null ||
        !parsed.isFinite ||
        parsed < minButtonScale ||
        parsed > maxButtonScale ||
        !buttonScaleOptions.any((option) => option.value == parsed)) {
      return defaultButtonScale;
    }
    return parsed;
  }

  static double normalizeButtonOpacity(Object? value) {
    final parsed = _numberFrom(value);
    if (parsed == null ||
        !parsed.isFinite ||
        parsed < minButtonOpacity ||
        parsed > maxButtonOpacity ||
        !buttonOpacityOptions.any((option) => option.value == parsed)) {
      return defaultButtonOpacity;
    }
    return parsed;
  }

  static double? _numberFrom(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  @override
  bool operator ==(Object other) {
    return other is NavigationPreferences &&
        other.displayMode == displayMode &&
        other.floatingEdge == floatingEdge &&
        other.buttonScale == buttonScale &&
        other.buttonOpacity == buttonOpacity;
  }

  @override
  int get hashCode =>
      Object.hash(displayMode, floatingEdge, buttonScale, buttonOpacity);

  @override
  String toString() {
    return 'NavigationPreferences('
        'displayMode: $displayMode, floatingEdge: $floatingEdge, '
        'buttonScale: $buttonScale, buttonOpacity: $buttonOpacity)';
  }
}

const _defaultButtonScale = 1.0;
const _defaultButtonOpacity = 0.5;
