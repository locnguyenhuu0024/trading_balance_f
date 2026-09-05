import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/navigation/navigation_content_frame.dart';
import 'package:trading_balance_f/core/navigation/navigation_preferences.dart';
import 'package:trading_balance_f/core/navigation/navigation_preferences_provider.dart';

void main() {
  Widget appFor(
    NavigationPreferences preferences, {
    double bottomInset = 0,
    Key? childKey,
  }) {
    return ProviderScope(
      overrides: [
        navigationPreferencesInitialProvider.overrideWithValue(preferences),
      ],
      child: MediaQuery(
        data: MediaQueryData(viewPadding: EdgeInsets.only(bottom: bottomInset)),
        child: MaterialApp(
          home: NavigationPresentationScope(
            child: NavigationContentFrame(
              child: SizedBox.expand(key: childKey),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('does not reserve layout space for floating navigation', (
    tester,
  ) async {
    const childKey = Key('floating-navigation-content');

    for (final edge in NavigationEdge.values) {
      await tester.pumpWidget(
        appFor(
          NavigationPreferences(
            displayMode: NavigationDisplayMode.floating,
            floatingEdge: edge,
          ),
          bottomInset: 24,
          childKey: childKey,
        ),
      );

      expect(find.byKey(const Key('navigation-content-frame')), findsNothing);
      expect(tester.getSize(find.byKey(childKey)), const Size(800, 600));
    }
  });

  testWidgets('reserves the fixed bar and bottom safe area', (tester) async {
    await tester.pumpWidget(
      appFor(
        const NavigationPreferences(
          displayMode: NavigationDisplayMode.bar,
          floatingEdge: NavigationEdge.bottom,
        ),
        bottomInset: 24,
      ),
    );

    final frame = tester.widget<Padding>(
      find.byKey(const Key('navigation-content-frame')),
    );
    expect(frame.padding, const EdgeInsets.only(bottom: 84));
  });
}
