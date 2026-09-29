import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import 'watchlist_provider.dart';

typedef SupportResistanceLevelsLoader =
    Future<SupportResistanceMarketSnapshot> Function({
      required SupportResistanceMarketMode marketMode,
      required String instrumentId,
      required SupportResistanceTimeframe timeframe,
    });

class SupportResistanceLevelsKey {
  const SupportResistanceLevelsKey({
    required this.marketMode,
    required this.instrumentId,
    required this.timeframe,
  });

  final SupportResistanceMarketMode marketMode;
  final String instrumentId;
  final SupportResistanceTimeframe timeframe;

  @override
  bool operator ==(Object other) =>
      other is SupportResistanceLevelsKey &&
      other.marketMode == marketMode &&
      other.instrumentId == instrumentId &&
      other.timeframe == timeframe;

  @override
  int get hashCode => Object.hash(marketMode, instrumentId, timeframe);
}

enum SupportResistanceLevelsStatus { loading, available, unavailable }

class SupportResistanceLevelsState {
  const SupportResistanceLevelsState({
    required this.status,
    this.snapshot,
    this.error,
  });

  final SupportResistanceLevelsStatus status;
  final SupportResistanceMarketSnapshot? snapshot;
  final Object? error;

  bool get isStale =>
      snapshot != null && status != SupportResistanceLevelsStatus.available;
}

class SupportResistanceLevelsController extends ChangeNotifier {
  SupportResistanceLevelsController({
    required SupportResistanceLevelsLoader loadLevels,
  }) : _loadLevels = loadLevels;

  final SupportResistanceLevelsLoader _loadLevels;
  final Map<SupportResistanceLevelsKey, SupportResistanceLevelsState> _states =
      <SupportResistanceLevelsKey, SupportResistanceLevelsState>{};
  final Map<SupportResistanceLevelsKey, Future<void>> _inFlight =
      <SupportResistanceLevelsKey, Future<void>>{};
  final Map<SupportResistanceLevelsKey, int> _requestIds =
      <SupportResistanceLevelsKey, int>{};
  Set<SupportResistanceLevelsKey> _activeKeys = <SupportResistanceLevelsKey>{};
  int _nextRequestId = 0;
  bool _disposed = false;

  SupportResistanceLevelsState? stateFor(SupportResistanceLevelsKey key) =>
      _states[key];

  Set<SupportResistanceLevelsKey> get activeKeys =>
      Set.unmodifiable(_activeKeys);

  void setActiveKeys(List<SupportResistanceLevelsKey> keys) {
    final next = keys.toSet();
    if (setEquals(next, _activeKeys)) return;
    final removed = _activeKeys.difference(next);
    final added = next.difference(_activeKeys);
    _activeKeys = next;

    for (final key in removed) {
      _states.remove(key);
      _inFlight.remove(key);
      _requestIds.remove(key);
    }
    if (removed.isNotEmpty && !_disposed) notifyListeners();

    for (final key in added) {
      unawaited(_loadOne(key));
    }
  }

  Future<void> refresh() async {
    await Future.wait(_activeKeys.map(_loadOne));
  }

  Future<void> _loadOne(SupportResistanceLevelsKey key) {
    if (_disposed || !_activeKeys.contains(key)) {
      return Future<void>.value();
    }
    final existing = _inFlight[key];
    if (existing != null) return existing;

    final previous = _states[key];
    final requestId = ++_nextRequestId;
    _requestIds[key] = requestId;
    _states[key] = SupportResistanceLevelsState(
      status: SupportResistanceLevelsStatus.loading,
      snapshot: previous?.snapshot,
    );
    final future = _performLoad(key, previous, requestId);
    _inFlight[key] = future;
    if (!_disposed) notifyListeners();
    return future;
  }

  Future<void> _performLoad(
    SupportResistanceLevelsKey key,
    SupportResistanceLevelsState? previous,
    int requestId,
  ) async {
    try {
      final result = await _loadLevels(
        marketMode: key.marketMode,
        instrumentId: key.instrumentId,
        timeframe: key.timeframe,
      );
      if (result.marketMode != key.marketMode ||
          result.instrumentId != key.instrumentId ||
          result.timeframe != key.timeframe) {
        throw StateError('Market response did not match its request key.');
      }
      if (_canApply(key, requestId)) {
        _states[key] = SupportResistanceLevelsState(
          status: SupportResistanceLevelsStatus.available,
          snapshot: result,
        );
      }
    } on Object catch (error) {
      if (_canApply(key, requestId)) {
        _states[key] = SupportResistanceLevelsState(
          status: SupportResistanceLevelsStatus.unavailable,
          snapshot: previous?.snapshot,
          error: error,
        );
      }
    } finally {
      if (_requestIds[key] == requestId) {
        _inFlight.remove(key);
        _requestIds.remove(key);
        if (!_disposed) notifyListeners();
      }
    }
  }

  bool _canApply(SupportResistanceLevelsKey key, int requestId) =>
      !_disposed && _activeKeys.contains(key) && _requestIds[key] == requestId;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final supportResistanceInstrumentsProvider = FutureProvider.autoDispose
    .family<List<SupportResistanceInstrument>, SupportResistanceMarketMode>(
      (ref, marketMode) => ref
          .watch(supportResistanceMarketRepositoryProvider)
          .getInstruments(marketMode: marketMode),
    );

final supportResistanceLevelsProvider =
    ChangeNotifierProvider.autoDispose<SupportResistanceLevelsController>((
      ref,
    ) {
      final repository = ref.watch(supportResistanceMarketRepositoryProvider);
      return SupportResistanceLevelsController(
        loadLevels: repository.loadLevels,
      );
    });
