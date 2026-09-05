import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/navigation/navigation_preferences.dart';
import 'package:trading_balance_f/core/navigation/navigation_preferences_provider.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';

class _NavigationStorage extends SecureStorageHelper {
  _NavigationStorage({this.failWrites = false, this.pendingWrites = false})
    : super(const FlutterSecureStorage());

  final bool failWrites;
  final bool pendingWrites;
  final pendingWrite = Completer<void>();
  NavigationPreferences? savedPreferences;
  var writeCount = 0;

  @override
  Future<void> saveNavigationPreferences(
    NavigationPreferences preferences,
  ) async {
    writeCount++;
    if (pendingWrites) await pendingWrite.future;
    if (failWrites) throw StateError('storage unavailable');
    savedPreferences = preferences;
  }
}

void main() {
  ProviderContainer createContainer(_NavigationStorage storage) {
    final container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        navigationPreferencesInitialProvider.overrideWithValue(
          NavigationPreferences.defaults,
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('previews and persists a navigation change', () async {
    final storage = _NavigationStorage();
    final container = createContainer(storage);
    final controller = container.read(navigationPreferencesProvider.notifier);

    final future = controller.setDisplayMode(NavigationDisplayMode.floating);

    expect(
      container.read(navigationPreferencesProvider).preferences.displayMode,
      NavigationDisplayMode.floating,
    );
    expect(container.read(navigationPreferencesProvider).isSaving, isTrue);

    await future;

    expect(storage.writeCount, 1);
    expect(
      storage.savedPreferences,
      const NavigationPreferences(
        displayMode: NavigationDisplayMode.floating,
        floatingEdge: NavigationEdge.bottom,
      ),
    );
    expect(container.read(navigationPreferencesProvider).isSaving, isFalse);
  });

  test('rolls the visible choice back after a failed save', () async {
    final storage = _NavigationStorage(failWrites: true);
    final container = createContainer(storage);

    await container
        .read(navigationPreferencesProvider.notifier)
        .setDisplayMode(NavigationDisplayMode.floating);

    final state = container.read(navigationPreferencesProvider);
    expect(state.preferences, NavigationPreferences.defaults);
    expect(state.confirmedPreferences, NavigationPreferences.defaults);
    expect(state.errorMessage, isNotNull);
  });

  test('does not start a competing write while one is in flight', () async {
    final storage = _NavigationStorage(pendingWrites: true);
    final container = createContainer(storage);
    final controller = container.read(navigationPreferencesProvider.notifier);

    final first = controller.setDisplayMode(NavigationDisplayMode.floating);
    await Future<void>.delayed(Duration.zero);
    final second = controller.setFloatingEdge(NavigationEdge.left);

    expect(storage.writeCount, 1);
    expect(
      container.read(navigationPreferencesProvider).preferences,
      const NavigationPreferences(
        displayMode: NavigationDisplayMode.floating,
        floatingEdge: NavigationEdge.bottom,
      ),
    );

    storage.pendingWrite.complete();
    await Future.wait([first, second]);
  });
}
