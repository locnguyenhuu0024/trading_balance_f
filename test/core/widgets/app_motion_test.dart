import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/widgets/app_motion.dart';

void main() {
  testWidgets('skeleton announces loading and respects reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: AppSkeleton(itemCount: 3)),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Đang tải dữ liệu…'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith(
              'app-skeleton-placeholder-',
            ),
      ),
      findsNWidgets(3),
    );
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('entrance animates only eligible children', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppEntranceScope(
          child: Column(
            children: [
              AppEntrance(index: 0, child: Text('first')),
              AppEntrance(index: 9, child: Text('ninth')),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final firstEntrance = find.byWidgetPredicate(
      (w) => w is AppEntrance && w.index == 0,
    );
    final ninthEntrance = find.byWidgetPredicate(
      (w) => w is AppEntrance && w.index == 9,
    );
    final fade = tester.widget<FadeTransition>(
      find
          .descendant(of: firstEntrance, matching: find.byType(FadeTransition))
          .first,
    );
    expect(fade.opacity.value, lessThan(1));
    expect(
      find.descendant(of: ninthEntrance, matching: find.byType(FadeTransition)),
      findsNothing,
    );
    await tester.pumpAndSettle();
    expect(fade.opacity.value, 1);
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: AppEntranceScope(
            child: AppEntrance(index: 0, child: Text('reduced')),
          ),
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(AppEntrance),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
  });

  testWidgets('late items and items without scope render directly', (
    tester,
  ) async {
    var show = false;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: AppEntranceScope(
          child: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return show
                  ? const AppEntrance(index: 0, child: Text('late'))
                  : const SizedBox();
            },
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    update(() => show = true);
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(AppEntrance),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
    await tester.pumpWidget(
      const MaterialApp(home: AppEntrance(index: 0, child: Text('unscoped'))),
    );
    expect(
      find.descendant(
        of: find.byType(AppEntrance),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
  });
}
