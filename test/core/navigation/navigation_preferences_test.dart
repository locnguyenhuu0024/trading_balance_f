import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/navigation/navigation_preferences.dart';

void main() {
  group('NavigationPreferences', () {
    test('round-trips its versioned record', () {
      const expected = NavigationPreferences(
        displayMode: NavigationDisplayMode.floating,
        floatingEdge: NavigationEdge.left,
      );

      expect(NavigationPreferences.decode(expected.encode()), expected);
    });

    test(
      'uses fixed-bottom defaults for missing, malformed, and future data',
      () {
        expect(
          NavigationPreferences.decode(null),
          NavigationPreferences.defaults,
        );
        expect(
          NavigationPreferences.decode('{not-json'),
          NavigationPreferences.defaults,
        );
        expect(
          NavigationPreferences.decode(
            '{"version":2,"mode":"floating","edge":"right"}',
          ),
          NavigationPreferences.defaults,
        );
      },
    );

    test('normalizes invalid fields without discarding a valid sibling', () {
      expect(
        NavigationPreferences.decode(
          '{"version":1,"mode":"floating","edge":"diagonal"}',
        ),
        const NavigationPreferences(
          displayMode: NavigationDisplayMode.floating,
          floatingEdge: NavigationEdge.bottom,
        ),
      );
      expect(
        NavigationPreferences.decode(
          '{"version":1,"mode":"strip","edge":"right"}',
        ),
        const NavigationPreferences(
          displayMode: NavigationDisplayMode.bar,
          floatingEdge: NavigationEdge.right,
        ),
      );
    });
  });
}
