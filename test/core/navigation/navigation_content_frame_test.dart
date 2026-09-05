import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/navigation/navigation_content_frame.dart';
import 'package:trading_balance_f/core/navigation/navigation_preferences.dart';
import 'package:trading_balance_f/core/navigation/navigation_preferences_provider.dart';

void main() {
  Widget appFor(NavigationPreferences preferences) {
    return ProviderScope(
      overrides: [
        navigationPreferencesInitialProvider.overrideWithValue(preferences),
      ],
      child: const MaterialApp(
        home: NavigationPresentationScope(
          child: NavigationContentFrame(child: SizedBox.expand()),
        ),
      ),
    );
  }

  testWidgets('reserves the full edge gap and floating group footprint', (
    tester,
  ) async {
    await tester.pumpWidget(
      appFor(
        const NavigationPreferences(
          displayMode: NavigationDisplayMode.floating,
          floatingEdge: NavigationEdge.bottom,
        ),
      ),
    );

    var frame = tester.widget<Padding>(
      find.byKey(const Key('navigation-content-frame')),
    );
    expect(frame.padding, const EdgeInsets.only(bottom: 80));

    await tester.pumpWidget(
      appFor(
        const NavigationPreferences(
          displayMode: NavigationDisplayMode.floating,
          floatingEdge: NavigationEdge.right,
        ),
      ),
    );
    await tester.pump();

    frame = tester.widget<Padding>(
      find.byKey(const Key('navigation-content-frame')),
    );
    expect(frame.padding, const EdgeInsets.only(right: 88));
  });
}
