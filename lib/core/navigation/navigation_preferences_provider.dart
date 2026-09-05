import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../security/secure_storage_helper.dart';
import 'navigation_preferences.dart';

/// Startup supplies a hydrated value while tests and standalone screens safely
/// fall back to [NavigationPreferences.defaults].
final navigationPreferencesInitialProvider = Provider<NavigationPreferences>(
  (ref) => NavigationPreferences.defaults,
);

final navigationPreferencesProvider =
    StateNotifierProvider<
      NavigationPreferencesController,
      NavigationPreferencesState
    >((ref) {
      return NavigationPreferencesController(
        storage: ref.watch(secureStorageProvider),
        initialPreferences: ref.watch(navigationPreferencesInitialProvider),
      );
    });

class NavigationPreferencesState {
  const NavigationPreferencesState({
    required this.preferences,
    required this.confirmedPreferences,
    this.isSaving = false,
    this.errorMessage,
  });

  factory NavigationPreferencesState.initial(NavigationPreferences value) {
    return NavigationPreferencesState(
      preferences: value,
      confirmedPreferences: value,
    );
  }

  final NavigationPreferences preferences;
  final NavigationPreferences confirmedPreferences;
  final bool isSaving;
  final String? errorMessage;

  NavigationPreferencesState copyWith({
    NavigationPreferences? preferences,
    NavigationPreferences? confirmedPreferences,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
  }) {
    return NavigationPreferencesState(
      preferences: preferences ?? this.preferences,
      confirmedPreferences: confirmedPreferences ?? this.confirmedPreferences,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

/// Applies presentation changes immediately while serialising persistence.
class NavigationPreferencesController
    extends StateNotifier<NavigationPreferencesState> {
  NavigationPreferencesController({
    required SecureStorageHelper storage,
    required NavigationPreferences initialPreferences,
  }) : _storage = storage,
       super(NavigationPreferencesState.initial(initialPreferences));

  final SecureStorageHelper _storage;

  Future<void> setDisplayMode(NavigationDisplayMode displayMode) {
    return update(state.preferences.copyWith(displayMode: displayMode));
  }

  Future<void> setFloatingEdge(NavigationEdge edge) {
    return update(state.preferences.copyWith(floatingEdge: edge));
  }

  Future<void> update(NavigationPreferences nextPreferences) async {
    if (state.isSaving || nextPreferences == state.preferences) return;

    final confirmedPreferences = state.confirmedPreferences;
    state = NavigationPreferencesState(
      preferences: nextPreferences,
      confirmedPreferences: confirmedPreferences,
      isSaving: true,
    );

    try {
      await _storage.saveNavigationPreferences(nextPreferences);
      if (!mounted) return;

      state = NavigationPreferencesState(
        preferences: nextPreferences,
        confirmedPreferences: nextPreferences,
      );
    } catch (_) {
      if (!mounted) return;

      state = NavigationPreferencesState(
        preferences: confirmedPreferences,
        confirmedPreferences: confirmedPreferences,
        errorMessage: 'Không lưu được tùy chọn điều hướng. Vui lòng thử lại.',
      );
    }
  }
}
