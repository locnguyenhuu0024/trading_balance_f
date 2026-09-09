import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/navigation/navigation_preferences.dart';

void main() {
  group('NavigationPreferences', () {
    test('round-trips its versioned record', () {
      const expected = NavigationPreferences(
        displayMode: NavigationDisplayMode.floating,
        floatingEdge: NavigationEdge.left,
        buttonScale: 1.1,
        buttonOpacity: 0.75,
      );

      expect(NavigationPreferences.decode(expected.encode()), expected);
    });

    test('keeps legacy mode and edge records with appearance defaults', () {
      expect(
        NavigationPreferences.decode(
          '{"version":1,"mode":"floating","edge":"right"}',
        ),
        const NavigationPreferences(
          displayMode: NavigationDisplayMode.floating,
          floatingEdge: NavigationEdge.right,
        ),
      );
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
      expect(
        NavigationPreferences.decode(
          '{"version":1,"mode":"floating","edge":"left",'
          '"buttonScale":2,"buttonOpacity":"opaque"}',
        ),
        const NavigationPreferences(
          displayMode: NavigationDisplayMode.floating,
          floatingEdge: NavigationEdge.left,
        ),
      );
    });

    test('accepts supported numeric appearance values', () {
      expect(NavigationPreferences.normalizeButtonScale('1.1'), 1.1);
      expect(NavigationPreferences.normalizeButtonOpacity(0.35), 0.35);
      expect(
        NavigationPreferences.normalizeButtonScale(0.8),
        NavigationPreferences.defaultButtonScale,
      );
      expect(
        NavigationPreferences.normalizeButtonScale(1.05),
        NavigationPreferences.defaultButtonScale,
      );
      expect(
        NavigationPreferences.normalizeButtonOpacity(1.1),
        NavigationPreferences.defaultButtonOpacity,
      );
    });
  });
}
