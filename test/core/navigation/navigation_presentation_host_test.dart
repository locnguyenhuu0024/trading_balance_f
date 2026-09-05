import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/navigation/main_navigation_shell.dart';
import 'package:trading_balance_f/core/navigation/navigation_preferences.dart';
import 'package:trading_balance_f/core/navigation/navigation_preferences_provider.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';

class _MemoryNavigationStorage extends SecureStorageHelper {
  _MemoryNavigationStorage() : super(const FlutterSecureStorage());

  @override
  Future<void> saveNavigationPreferences(
    NavigationPreferences preferences,
  ) async {}
}

class _PersistentDestination extends StatefulWidget {
  const _PersistentDestination({required this.onPageTap});

  final VoidCallback onPageTap;

  @override
  State<_PersistentDestination> createState() => _PersistentDestinationState();
}

class _PersistentDestinationState extends State<_PersistentDestination> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onPageTap,
      child: ColoredBox(
        color: Colors.amber,
        child: Center(
          child: TextField(
            key: const Key('persistent-navigation-input'),
            controller: _controller,
          ),
        ),
      ),
    );
  }
}

void main() {
  ProviderContainer createContainer() {
    final container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(_MemoryNavigationStorage()),
        navigationPreferencesInitialProvider.overrideWithValue(
          NavigationPreferences.defaults,
        ),
        themeModeProvider.overrideWith((ref) => ThemeMode.light),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  testWidgets('keeps the active page state when its presentation changes', (
    tester,
  ) async {
    final container = createContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: MainNavigationShell(
            destinationBuilder: (context, index) =>
                _PersistentDestination(onPageTap: () {}),
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('persistent-navigation-input')),
      'draft API value',
    );
    await tester.pump();

    await container
        .read(navigationPreferencesProvider.notifier)
        .setDisplayMode(NavigationDisplayMode.floating);
    await tester.pumpAndSettle();

    expect(find.text('draft API value'), findsOneWidget);
    expect(
      find.byKey(const Key('floating-navigation-destination-4')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('navigation-bar-surface')), findsNothing);
  });

  testWidgets('keeps raised button hits separate from transparent page space', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);

    final container = createContainer();
    var pageTapCount = 0;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: MainNavigationShell(
            destinationBuilder: (context, index) =>
                _PersistentDestination(onPageTap: () => pageTapCount++),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final selectedButton = tester.getRect(
      find.byKey(const Key('navigation-destination-0')),
    );
    final surface = tester.getRect(
      find.byKey(const Key('navigation-bar-surface')),
    );

    await tester.tapAt(selectedButton.center);
    await tester.pump();
    expect(pageTapCount, 0);

    await tester.tapAt(Offset(surface.left + 82, surface.top - 8));
    await tester.pump();
    expect(pageTapCount, 1);
  });
}
