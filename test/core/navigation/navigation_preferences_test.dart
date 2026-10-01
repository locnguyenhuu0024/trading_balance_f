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

    test('round-trips normalized destination membership', () {
      const preferences = NavigationPreferences(
        displayMode: NavigationDisplayMode.floating,
        floatingEdge: NavigationEdge.left,
        enabledDestinationIds: ['support', 'bmag', 'bmag', 'unknown'],
      );

      expect(
        NavigationPreferences.decode(
          preferences.encode(),
        ).enabledDestinationIds,
        ['bmag', 'settings', 'support'],
      );
    });

    test('round-trips destination order independently of visibility', () {
      const preferences = NavigationPreferences(
        displayMode: NavigationDisplayMode.floating,
        floatingEdge: NavigationEdge.left,
        enabledDestinationIds: ['home', 'settings'],
        destinationOrderIds: [
          'home',
          'orders',
          'market',
          'settings',
          'risk',
          'bmag',
          'support',
        ],
      );

      final decoded = NavigationPreferences.decode(preferences.encode());
      expect(decoded.destinationOrderIds, preferences.destinationOrderIds);
      expect(decoded.enabledDestinationIds, ['home', 'settings']);
    });

    test(
      'normalizes partial destination order without losing sibling values',
      () {
        final decoded = NavigationPreferences.decode(
          '{"version":1,"mode":"floating","edge":"right",'
          '"buttonScale":1.1,"buttonOpacity":0.75,'
          '"enabledDestinationIds":["orders","risk"],'
          '"destinationOrderIds":["risk","unknown","bmag","risk"]}',
        );

        expect(decoded.destinationOrderIds, [
          'risk',
          'bmag',
          'home',
          'orders',
          'market',
          'settings',
          'support',
        ]);
        expect(decoded.enabledDestinationIds, ['orders', 'settings', 'risk']);
        expect(decoded.displayMode, NavigationDisplayMode.floating);
        expect(decoded.floatingEdge, NavigationEdge.right);
        expect(decoded.buttonScale, 1.1);
        expect(decoded.buttonOpacity, 0.75);
      },
    );

    test('normalizes malformed membership without losing Settings', () {
      expect(
        NavigationPreferences.decode(
          '{"version":1,"mode":"floating","edge":"right",'
          '"enabledDestinationIds":["risk","unknown","risk"]}',
        ).enabledDestinationIds,
        ['settings', 'risk'],
      );
      expect(
        NavigationPreferences.decode(
          '{"version":1,"mode":"floating","edge":"right",'
          '"enabledDestinationIds":["unknown"]}',
        ).enabledDestinationIds,
        NavigationPreferences.defaults.enabledDestinationIds,
      );
      expect(
        NavigationPreferences.decode(
          '{"version":1,"mode":"floating","edge":"right",'
          '"enabledDestinationIds":[]}',
        ).enabledDestinationIds,
        NavigationPreferences.defaults.enabledDestinationIds,
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
