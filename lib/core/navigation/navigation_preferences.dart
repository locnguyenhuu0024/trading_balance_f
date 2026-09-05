import 'dart:convert';

enum NavigationDisplayMode { bar, floating }

enum NavigationEdge { top, bottom, left, right }

/// Local presentation choices for the application's primary navigation.
///
/// The record is intentionally small and versioned so invalid future values do
/// not prevent the application from rendering its safe fixed-bar default.
class NavigationPreferences {
  const NavigationPreferences({
    required this.displayMode,
    required this.floatingEdge,
  });

  static const currentVersion = 1;
  static const defaults = NavigationPreferences(
    displayMode: NavigationDisplayMode.bar,
    floatingEdge: NavigationEdge.bottom,
  );

  final NavigationDisplayMode displayMode;
  final NavigationEdge floatingEdge;

  NavigationPreferences copyWith({
    NavigationDisplayMode? displayMode,
    NavigationEdge? floatingEdge,
  }) {
    return NavigationPreferences(
      displayMode: displayMode ?? this.displayMode,
      floatingEdge: floatingEdge ?? this.floatingEdge,
    );
  }

  String encode() {
    return jsonEncode({
      'version': currentVersion,
      'mode': displayMode.name,
      'edge': floatingEdge.name,
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

  @override
  bool operator ==(Object other) {
    return other is NavigationPreferences &&
        other.displayMode == displayMode &&
        other.floatingEdge == floatingEdge;
  }

  @override
  int get hashCode => Object.hash(displayMode, floatingEdge);

  @override
  String toString() {
    return 'NavigationPreferences('
        'displayMode: $displayMode, floatingEdge: $floatingEdge)';
  }
}
