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
    double bottomViewInset = 0,
    bool inNavigationHost = true,
    Key? childKey,
  }) {
    return ProviderScope(
      overrides: [
        navigationPreferencesInitialProvider.overrideWithValue(preferences),
      ],
      child: MediaQuery(
        data: MediaQueryData(
          viewPadding: EdgeInsets.only(bottom: bottomInset),
          viewInsets: EdgeInsets.only(bottom: bottomViewInset),
        ),
        child: MaterialApp(
          home: inNavigationHost
              ? NavigationPresentationScope(
                  child: NavigationContentFrame(
                    child: SizedBox.expand(key: childKey),
                  ),
                )
              : NavigationContentFrame(child: SizedBox.expand(key: childKey)),
        ),
      ),
    );
  }

  testWidgets(
    'reserves the fixed bar height for every navigation mode and edge',
    (tester) async {
      for (final edge in NavigationEdge.values) {
        final preferences = NavigationPreferences(
          displayMode: NavigationDisplayMode.floating,
          floatingEdge: edge,
        );
        await tester.pumpWidget(appFor(preferences, bottomInset: 24));

        expect(
          find.byKey(const Key('navigation-content-frame')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<Padding>(
                find.byKey(const Key('navigation-content-frame')),
              )
              .padding,
          const EdgeInsets.only(bottom: 100),
        );
      }

      await tester.pumpWidget(
        appFor(
          const NavigationPreferences(
            displayMode: NavigationDisplayMode.bar,
            floatingEdge: NavigationEdge.bottom,
          ),
          bottomInset: 24,
        ),
      );
      expect(
        tester
            .widget<Padding>(find.byKey(const Key('navigation-content-frame')))
            .padding,
        const EdgeInsets.only(bottom: 100),
      );
    },
  );

  testWidgets('reserves 76 pixels with no bottom inset', (tester) async {
    for (final preferences in [
      const NavigationPreferences(
        displayMode: NavigationDisplayMode.bar,
        floatingEdge: NavigationEdge.bottom,
      ),
      for (final edge in NavigationEdge.values)
        NavigationPreferences(
          displayMode: NavigationDisplayMode.floating,
          floatingEdge: edge,
        ),
    ]) {
      await tester.pumpWidget(appFor(preferences));
      expect(
        tester
            .widget<Padding>(find.byKey(const Key('navigation-content-frame')))
            .padding,
        const EdgeInsets.only(bottom: 76),
      );
    }
  });

  testWidgets('uses the larger keyboard or system bottom inset', (
    tester,
  ) async {
    await tester.pumpWidget(
      appFor(
        const NavigationPreferences(
          displayMode: NavigationDisplayMode.bar,
          floatingEdge: NavigationEdge.bottom,
        ),
        bottomInset: 16,
        bottomViewInset: 24,
      ),
    );
    expect(
      tester
          .widget<Padding>(find.byKey(const Key('navigation-content-frame')))
          .padding,
      const EdgeInsets.only(bottom: 100),
    );
  });

  testWidgets('does not reserve space outside the navigation host', (
    tester,
  ) async {
    const childKey = Key('outside-navigation-content');
    await tester.pumpWidget(
      appFor(
        const NavigationPreferences(
          displayMode: NavigationDisplayMode.bar,
          floatingEdge: NavigationEdge.bottom,
        ),
        bottomInset: 24,
        inNavigationHost: false,
        childKey: childKey,
      ),
    );

    expect(find.byKey(const Key('navigation-content-frame')), findsNothing);
    expect(tester.getSize(find.byKey(childKey)), const Size(800, 600));
  });
}
