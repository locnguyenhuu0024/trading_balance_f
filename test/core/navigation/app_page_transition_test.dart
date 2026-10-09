import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/navigation/main_navigation_shell.dart';
import 'package:trading_balance_f/core/theme/app_theme.dart';
import 'package:trading_balance_f/core/widgets/app_page_transition.dart';

class _TrackedDestination extends StatefulWidget {
  const _TrackedDestination({
    required this.index,
    required this.onDispose,
    this.onCreate,
  });

  final int index;
  final ValueChanged<int> onDispose;
  final ValueChanged<int>? onCreate;

  @override
  State<_TrackedDestination> createState() => _TrackedDestinationState();
}

class _TrackedDestinationState extends State<_TrackedDestination> {
  @override
  void initState() {
    super.initState();
    widget.onCreate?.call(widget.index);
  }

  @override
  void dispose() {
    widget.onDispose(widget.index);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('Destination ${widget.index}');
}

class _RouteDraft extends StatelessWidget {
  const _RouteDraft({required this.motionFlags});

  final ValueNotifier<(bool, bool)> motionFlags;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        const TextField(key: Key('route-draft-field')),
        TextButton(
          key: const Key('toggle-disable-animations'),
          onPressed: () =>
              motionFlags.value = (!motionFlags.value.$1, motionFlags.value.$2),
          child: const Text('Toggle disable animations'),
        ),
        TextButton(
          key: const Key('toggle-accessible-navigation'),
          onPressed: () =>
              motionFlags.value = (motionFlags.value.$1, !motionFlags.value.$2),
          child: const Text('Toggle accessible navigation'),
        ),
      ],
    ),
  );
}

List<FadeTransition> _appRouteFades(WidgetTester tester) => tester
    .widgetList<FadeTransition>(find.byType(FadeTransition))
    .where((fade) => fade.key == const Key('app-route-fade'))
    .toList(growable: false);

List<ExcludeSemantics> _appRouteSemantics(WidgetTester tester) => tester
    .widgetList<ExcludeSemantics>(find.byType(ExcludeSemantics))
    .where(
      (semantics) => semantics.key == const Key('app-route-exclude-semantics'),
    )
    .toList(growable: false);

List<IgnorePointer> _appRouteInteractions(WidgetTester tester) => tester
    .widgetList<IgnorePointer>(find.byType(IgnorePointer))
    .where((pointer) => pointer.key == const Key('app-route-ignore-pointer'))
    .toList(growable: false);

void main() {
  Widget shellApp({
    required ValueChanged<int> onDispose,
    ValueChanged<int>? onCreate,
    bool disableAnimations = false,
    bool accessibleNavigation = false,
  }) {
    return MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: disableAnimations,
          accessibleNavigation: accessibleNavigation,
        ),
        child: child!,
      ),
      home: ProviderScope(
        child: MainNavigationShell(
          destinationBuilder: (context, index) => _TrackedDestination(
            index: index,
            onDispose: onDispose,
            onCreate: onCreate,
          ),
        ),
      ),
    );
  }

  String draftText(WidgetTester tester, Key key) => tester
      .widget<EditableText>(
        find.descendant(
          of: find.byKey(key),
          matching: find.byType(EditableText),
        ),
      )
      .controller
      .text;

  testWidgets(
    'rapid destination changes dispose old pages before the fade finishes',
    (tester) async {
      final disposed = <int>[];
      final created = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ProviderScope(
            child: MainNavigationShell(
              destinationBuilder: (context, index) => _TrackedDestination(
                index: index,
                onDispose: disposed.add,
                onCreate: created.add,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(created, [0]);

      await tester.tap(find.byKey(const Key('navigation-destination-1')));
      await tester.pump();
      expect(disposed, contains(0));
      expect(find.text('Destination 0'), findsNothing);
      expect(find.text('Destination 1'), findsOneWidget);

      await tester.tap(find.byKey(const Key('navigation-destination-2')));
      await tester.pump();
      expect(disposed, containsAll([0, 1]));
      expect(created, [0, 1, 2]);
      expect(find.text('Destination 1'), findsNothing);
      expect(find.text('Destination 2'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byKey(const Key('app-destination-fade')), findsOneWidget);
    },
  );

  testWidgets(
    'destination fade honors both reduced-motion accessibility flags',
    (tester) async {
      for (final flags in [
        (disableAnimations: true, accessibleNavigation: false),
        (disableAnimations: false, accessibleNavigation: true),
      ]) {
        final disposed = <int>[];
        final created = <int>[];
        await tester.pumpWidget(
          shellApp(
            onDispose: disposed.add,
            onCreate: created.add,
            disableAnimations: flags.disableAnimations,
            accessibleNavigation: flags.accessibleNavigation,
          ),
        );
        await tester.pumpAndSettle();
        expect(created, [0]);
        await tester.tap(find.byKey(const Key('navigation-destination-1')));
        await tester.pump();

        expect(created, [0, 1]);
        expect(disposed, contains(0));
        expect(find.text('Destination 1'), findsOneWidget);
        expect(find.byType(AnimatedSize), findsNothing);
        expect(find.byKey(const Key('app-destination-fade')), findsOneWidget);
        expect(
          tester
              .widget<FadeTransition>(
                find.byKey(const Key('app-destination-fade')),
              )
              .opacity
              .value,
          1,
        );
        expect(disposed, [0]);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );

  testWidgets(
    'route opacity reaches the standard token and disables access during entry',
    (tester) async {
      var didPush = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            platform: TargetPlatform.android,
            pageTransitionsTheme: AppPageTransitions.theme,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: false, accessibleNavigation: false),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  didPush = true;
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        body: Column(
                          children: [
                            const Text('Next route'),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Pop route'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Open route'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        _appRouteInteractions(tester).any((pointer) => !pointer.ignoring),
        isTrue,
      );

      await tester.tap(find.text('Open route'));
      expect(didPush, isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(_appRouteFades(tester), isNotEmpty);
      expect(_appRouteSemantics(tester).any((item) => item.excluding), isTrue);
      expect(find.text('Next route'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 109));
      final halfwayFades = _appRouteFades(tester);
      expect(
        halfwayFades.any(
          (fade) => fade.opacity.value > 0 && fade.opacity.value < 1,
        ),
        isTrue,
      );

      await tester.pump(const Duration(milliseconds: 110));
      expect(
        _appRouteFades(tester).every((fade) => fade.opacity.value > 0.999),
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(_appRouteSemantics(tester).any((item) => !item.excluding), isTrue);

      await tester.tap(find.text('Pop route'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 109));
      expect(
        _appRouteFades(
          tester,
        ).any((fade) => fade.opacity.value > 0 && fade.opacity.value < 1),
        isTrue,
      );
      await tester.pump(const Duration(milliseconds: 110));
      await tester.pumpAndSettle();
      expect(find.text('Open route'), findsOneWidget);
      expect(find.text('Next route'), findsNothing);
    },
  );

  testWidgets(
    'route transition is immediate for disableAnimations and accessibleNavigation',
    (tester) async {
      for (final flags in [
        (disableAnimations: true, accessibleNavigation: false),
        (disableAnimations: false, accessibleNavigation: true),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              platform: TargetPlatform.android,
              pageTransitionsTheme: AppPageTransitions.theme,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: flags.disableAnimations,
                accessibleNavigation: flags.accessibleNavigation,
              ),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => Builder(
                        builder: (context) => Scaffold(
                          body: Column(
                            children: [
                              const Text('Immediate route'),
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Pop immediate route'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Open immediate route'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open immediate route'));
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.text('Immediate route'), findsOneWidget);
        expect(_appRouteFades(tester), isNotEmpty);
        expect(
          _appRouteFades(tester).every((fade) => fade.opacity.value == 1),
          isTrue,
        );
        expect(
          _appRouteSemantics(tester).any((item) => !item.excluding),
          isTrue,
        );
        await tester.tap(find.text('Pop immediate route'));
        await tester.pumpAndSettle();
        expect(find.text('Open immediate route'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );

  testWidgets('destination keeps its draft when reduced-motion flags change', (
    tester,
  ) async {
    final flags = ValueNotifier<(bool, bool)>((false, false));
    addTearDown(flags.dispose);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => ValueListenableBuilder<(bool, bool)>(
          valueListenable: flags,
          child: child,
          builder: (context, value, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: value.$1,
              accessibleNavigation: value.$2,
            ),
            child: child!,
          ),
        ),
        home: Scaffold(
          body: Column(
            children: [
              TextButton(
                key: const Key('toggle-destination-disable'),
                onPressed: () => flags.value = (true, flags.value.$2),
                child: const Text('Disable destination motion'),
              ),
              TextButton(
                key: const Key('toggle-destination-accessible'),
                onPressed: () => flags.value = (flags.value.$1, true),
                child: const Text('Enable accessible navigation'),
              ),
              const Expanded(
                child: AppDestinationTransition(
                  destinationId: 0,
                  child: TextField(key: Key('destination-draft-field')),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('destination-draft-field')),
      'draft survives',
    );
    await tester.tap(find.byKey(const Key('toggle-destination-disable')));
    await tester.pumpAndSettle();
    expect(
      draftText(tester, const Key('destination-draft-field')),
      'draft survives',
    );

    await tester.tap(find.byKey(const Key('toggle-destination-accessible')));
    await tester.pumpAndSettle();
    expect(
      draftText(tester, const Key('destination-draft-field')),
      'draft survives',
    );
  });

  testWidgets('route keeps draft state when reduced-motion flags change', (
    tester,
  ) async {
    final flags = ValueNotifier<(bool, bool)>((false, false));
    addTearDown(flags.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          platform: TargetPlatform.android,
          pageTransitionsTheme: AppPageTransitions.theme,
        ),
        builder: (context, child) => ValueListenableBuilder<(bool, bool)>(
          valueListenable: flags,
          child: child,
          builder: (context, value, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: value.$1,
              accessibleNavigation: value.$2,
            ),
            child: child!,
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => _RouteDraft(motionFlags: flags),
                ),
              ),
              child: const Text('Open draft route'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Open draft route'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('route-draft-field')),
      'draft survives',
    );
    await tester.tap(find.byKey(const Key('toggle-disable-animations')));
    await tester.pumpAndSettle();
    expect(draftText(tester, const Key('route-draft-field')), 'draft survives');

    await tester.tap(find.byKey(const Key('toggle-accessible-navigation')));
    await tester.pumpAndSettle();
    expect(draftText(tester, const Key('route-draft-field')), 'draft survives');
  });

  testWidgets('Cupertino route keeps native back swipe and draft state', (
    tester,
  ) async {
    final flags = ValueNotifier<(bool, bool)>((false, false));
    addTearDown(flags.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          platform: TargetPlatform.iOS,
          pageTransitionsTheme: AppPageTransitions.theme,
        ),
        builder: (context, child) => ValueListenableBuilder<(bool, bool)>(
          valueListenable: flags,
          child: child,
          builder: (context, value, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: value.$1,
              accessibleNavigation: value.$2,
            ),
            child: child!,
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => _RouteDraft(motionFlags: flags),
                ),
              ),
              child: const Text('Open Apple route'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Apple route'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('route-draft-field')),
      'native draft',
    );
    await tester.tap(find.byKey(const Key('toggle-disable-animations')));
    await tester.pumpAndSettle();
    expect(draftText(tester, const Key('route-draft-field')), 'native draft');
    await tester.tap(find.byKey(const Key('toggle-accessible-navigation')));
    await tester.pumpAndSettle();
    expect(draftText(tester, const Key('route-draft-field')), 'native draft');

    final backSwipe = await tester.startGesture(const Offset(1, 300));
    await backSwipe.moveBy(const Offset(400, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await backSwipe.up();
    await tester.pumpAndSettle();
    expect(find.text('Open Apple route'), findsOneWidget);
    expect(find.byKey(const Key('route-draft-field')), findsNothing);
  });
}
