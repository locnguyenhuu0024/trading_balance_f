import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/navigation/navigation_content_frame.dart';

void main() {
  Widget appFor({
    double bottomInset = 0,
    double bottomViewInset = 0,
    bool inNavigationHost = true,
  }) {
    return MediaQuery(
      data: MediaQueryData(
        viewPadding: EdgeInsets.only(bottom: bottomInset),
        viewInsets: EdgeInsets.only(bottom: bottomViewInset),
      ),
      child: MaterialApp(
        home: inNavigationHost
            ? NavigationPresentationScope(
                child: const NavigationContentFrame(
                  child: SizedBox.expand(key: Key('content')),
                ),
              )
            : const NavigationContentFrame(
                child: SizedBox.expand(key: Key('content')),
              ),
      ),
    );
  }

  testWidgets('reserves the fixed bar and safe-area inset', (tester) async {
    await tester.pumpWidget(appFor(bottomInset: 24));

    expect(find.byKey(const Key('navigation-content-frame')), findsOneWidget);
    expect(
      tester
          .widget<Padding>(find.byKey(const Key('navigation-content-frame')))
          .padding,
      const EdgeInsets.only(bottom: 100),
    );
  });

  testWidgets('uses the larger keyboard inset when it exceeds safe area', (
    tester,
  ) async {
    await tester.pumpWidget(appFor(bottomInset: 12, bottomViewInset: 140));

    expect(
      tester
          .widget<Padding>(find.byKey(const Key('navigation-content-frame')))
          .padding,
      const EdgeInsets.only(bottom: 216),
    );
  });

  testWidgets('remains a no-op outside the navigation host', (tester) async {
    await tester.pumpWidget(appFor(inNavigationHost: false));

    expect(find.byKey(const Key('navigation-content-frame')), findsNothing);
    expect(find.byKey(const Key('content')), findsOneWidget);
  });
}
