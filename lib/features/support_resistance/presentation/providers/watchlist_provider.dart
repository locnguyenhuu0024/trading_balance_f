import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../portfolio/data/risk/risk_request_coordinator.dart';
import '../../data/market_repository.dart';
import '../../data/watchlist_store.dart';
import '../../domain/models.dart';

typedef WatchlistInstrumentLoader =
    Future<List<SupportResistanceInstrument>> Function(
      SupportResistanceMarketMode marketMode,
    );

enum WatchlistMutationResult {
  changed,
  unchanged,
  invalidInstrument,
  instrumentUnavailable,
  duplicate,
  limitReached,
  modeChanged,
  catalogUnavailable,
  notLoaded,
  persistenceFailed,
}

class WatchlistController extends ChangeNotifier {
  WatchlistController({
    required WatchlistStore store,
    required WatchlistInstrumentLoader loadActiveInstruments,
  }) : _store = store,
       _loadActiveInstruments = loadActiveInstruments,
       _snapshot = WatchlistSnapshot.initial(),
       _confirmedSnapshot = WatchlistSnapshot.initial();

  final WatchlistStore _store;
  final WatchlistInstrumentLoader _loadActiveInstruments;
  WatchlistSnapshot _snapshot;
  WatchlistSnapshot _confirmedSnapshot;
  Future<void> _writeQueue = Future<void>.value();
  Future<void>? _loadFuture;
  bool _isLoaded = false;
  bool _isLoading = false;
  bool _isSaving = false;
  String? _loadError;
  String? _saveError;

  WatchlistSnapshot get snapshot => _snapshot;
  bool get isLoaded => _isLoaded;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get loadError => _loadError;
  String? get saveError => _saveError;

  Future<void> load() {
    if (_isLoaded) return Future<void>.value();
    final running = _loadFuture;
    if (running != null) return running;

    final future = _loadSnapshot();
    _loadFuture = future;
    return future.whenComplete(() {
      if (identical(_loadFuture, future)) _loadFuture = null;
    });
  }

  Future<void> _loadSnapshot() async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();
    try {
      final loaded = await _store.load();
      _snapshot = loaded;
      _confirmedSnapshot = loaded;
      _isLoaded = true;
    } on Object {
      _loadError = 'Watchlist could not be loaded. Retry to continue.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<WatchlistMutationResult> setMarketMode(
    SupportResistanceMarketMode marketMode,
  ) => _enqueue((current) {
    if (current.marketMode == marketMode) {
      return const _WatchlistUpdate.unchanged();
    }
    return _WatchlistUpdate.change(current.copyWith(marketMode: marketMode));
  });

  Future<WatchlistMutationResult> setTimeframe(
    SupportResistanceTimeframe timeframe,
  ) => _enqueue((current) {
    if (current.timeframe == timeframe) {
      return const _WatchlistUpdate.unchanged();
    }
    return _WatchlistUpdate.change(current.copyWith(timeframe: timeframe));
  });

  Future<WatchlistMutationResult> addInstrument(String instrumentId) async {
    if (!_isLoaded) return WatchlistMutationResult.notLoaded;
    final marketMode = _snapshot.marketMode;
    if (!WatchlistStore.hasValidInstrumentId(marketMode, instrumentId)) {
      return WatchlistMutationResult.invalidInstrument;
    }
    final selected = _snapshot.instrumentIdsFor(marketMode);
    if (selected.contains(instrumentId)) {
      return WatchlistMutationResult.duplicate;
    }
    if (selected.length >= WatchlistSnapshot.maximumSelectionsPerMode) {
      return WatchlistMutationResult.limitReached;
    }

    late final List<SupportResistanceInstrument> activeInstruments;
    try {
      activeInstruments = await _loadActiveInstruments(marketMode);
    } on Object {
      return WatchlistMutationResult.catalogUnavailable;
    }
    if (_snapshot.marketMode != marketMode) {
      return WatchlistMutationResult.modeChanged;
    }
    final isExactActiveInstrument = activeInstruments.any(
      (instrument) =>
          instrument.marketMode == marketMode &&
          instrument.instrumentId == instrumentId,
    );
    if (!isExactActiveInstrument) {
      return WatchlistMutationResult.instrumentUnavailable;
    }

    return _enqueue((current) {
      if (current.marketMode != marketMode) {
        return const _WatchlistUpdate.unchanged(
          WatchlistMutationResult.modeChanged,
        );
      }
      final ids = current.instrumentIdsFor(marketMode);
      if (ids.contains(instrumentId)) {
        return const _WatchlistUpdate.unchanged(
          WatchlistMutationResult.duplicate,
        );
      }
      if (ids.length >= WatchlistSnapshot.maximumSelectionsPerMode) {
        return const _WatchlistUpdate.unchanged(
          WatchlistMutationResult.limitReached,
        );
      }
      final nextIds = <String>[...ids, instrumentId];
      return _WatchlistUpdate.change(
        marketMode == SupportResistanceMarketMode.spot
            ? current.copyWith(spotInstrumentIds: nextIds)
            : current.copyWith(perpetualInstrumentIds: nextIds),
      );
    });
  }

  Future<WatchlistMutationResult> removeInstrument(
    String instrumentId, {
    SupportResistanceMarketMode? marketMode,
  }) {
    if (!_isLoaded) return Future.value(WatchlistMutationResult.notLoaded);
    final targetMode = marketMode ?? _snapshot.marketMode;
    if (!WatchlistStore.hasValidInstrumentId(targetMode, instrumentId)) {
      return Future.value(WatchlistMutationResult.invalidInstrument);
    }
    return _enqueue((current) {
      final ids = current.instrumentIdsFor(targetMode);
      if (!ids.contains(instrumentId)) {
        return const _WatchlistUpdate.unchanged();
      }
      final nextIds = ids.where((id) => id != instrumentId).toList();
      return _WatchlistUpdate.change(
        targetMode == SupportResistanceMarketMode.spot
            ? current.copyWith(spotInstrumentIds: nextIds)
            : current.copyWith(perpetualInstrumentIds: nextIds),
      );
    });
  }

  void clearSaveError() {
    if (_saveError == null) return;
    _saveError = null;
    notifyListeners();
  }

  Future<WatchlistMutationResult> _enqueue(
    _WatchlistUpdate Function(WatchlistSnapshot current) update,
  ) {
    if (!_isLoaded) return Future.value(WatchlistMutationResult.notLoaded);
    final completer = Completer<WatchlistMutationResult>();
    _writeQueue = _writeQueue.then((_) async {
      final before = _confirmedSnapshot;
      final next = update(before);
      final candidate = next.snapshot;
      if (candidate == null || candidate.hasSameValues(before)) {
        completer.complete(next.unchangedResult);
        return;
      }

      _snapshot = candidate;
      _isSaving = true;
      _saveError = null;
      notifyListeners();
      try {
        await _store.save(candidate);
        _confirmedSnapshot = candidate;
        _snapshot = candidate;
        completer.complete(WatchlistMutationResult.changed);
      } on Object {
        _snapshot = before;
        _saveError = 'Watchlist could not be saved. Try again.';
        completer.complete(WatchlistMutationResult.persistenceFailed);
      } finally {
        _isSaving = false;
        notifyListeners();
      }
    });
    return completer.future;
  }
}

class _WatchlistUpdate {
  const _WatchlistUpdate.unchanged([
    this.unchangedResult = WatchlistMutationResult.unchanged,
  ]) : snapshot = null;

  const _WatchlistUpdate.change(this.snapshot)
    : unchangedResult = WatchlistMutationResult.unchanged;

  final WatchlistSnapshot? snapshot;
  final WatchlistMutationResult unchangedResult;
}

final supportResistanceMarketRepositoryProvider =
    Provider<SupportResistanceRepository>((ref) {
      final dio = Dio(
        BaseOptions(
          baseUrl: kIsWeb ? '' : 'https://www.okx.com',
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          headers: const <String, Object>{'Content-Type': 'application/json'},
        ),
      );
      ref.onDispose(() => dio.close(force: true));
      return SupportResistanceRepository(
        dio,
        requestCoordinator: ref.watch(riskRequestCoordinatorProvider),
      );
    });

final supportResistanceWatchlistProvider =
    ChangeNotifierProvider<WatchlistController>((ref) {
      final repository = ref.watch(supportResistanceMarketRepositoryProvider);
      final controller = WatchlistController(
        store: WatchlistStore(
          storage: DeferredSharedPreferencesWatchlistStorage(),
        ),
        loadActiveInstruments: (marketMode) =>
            repository.getInstruments(marketMode: marketMode),
      );
      unawaited(controller.load());
      return controller;
    });

/// Defers platform access so constructing the controller stays synchronous.
class DeferredSharedPreferencesWatchlistStorage implements WatchlistStorage {
  DeferredSharedPreferencesWatchlistStorage()
    : _preferences = SharedPreferences.getInstance();

  final Future<SharedPreferences> _preferences;

  @override
  Future<String?> readSnapshot() async =>
      (await _preferences).getString(WatchlistStore.storageKey);

  @override
  Future<bool> writeSnapshot(String encodedSnapshot) async =>
      (await _preferences).setString(
        WatchlistStore.storageKey,
        encodedSnapshot,
      );
}
