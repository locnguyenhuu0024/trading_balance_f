import 'dart:convert';

import '../domain/models.dart';

/// Storage boundary for the single watchlist snapshot.
abstract interface class WatchlistStorage {
  Future<String?> readSnapshot();

  Future<bool> writeSnapshot(String encodedSnapshot);
}

class WatchlistSnapshot {
  WatchlistSnapshot({
    required this.marketMode,
    required this.timeframe,
    required List<String> spotInstrumentIds,
    required List<String> perpetualInstrumentIds,
  }) : spotInstrumentIds = List<String>.unmodifiable(spotInstrumentIds),
       perpetualInstrumentIds = List<String>.unmodifiable(
         perpetualInstrumentIds,
       );

  factory WatchlistSnapshot.initial() => WatchlistSnapshot(
    marketMode: SupportResistanceMarketMode.spot,
    timeframe: SupportResistanceTimeframe.h6,
    spotInstrumentIds: const <String>[],
    perpetualInstrumentIds: const <String>[],
  );

  final SupportResistanceMarketMode marketMode;
  final SupportResistanceTimeframe timeframe;
  final List<String> spotInstrumentIds;
  final List<String> perpetualInstrumentIds;

  static const int maximumSelectionsPerMode = 10;

  List<String> instrumentIdsFor(SupportResistanceMarketMode mode) =>
      mode == SupportResistanceMarketMode.spot
      ? spotInstrumentIds
      : perpetualInstrumentIds;

  WatchlistSnapshot copyWith({
    SupportResistanceMarketMode? marketMode,
    SupportResistanceTimeframe? timeframe,
    List<String>? spotInstrumentIds,
    List<String>? perpetualInstrumentIds,
  }) => WatchlistSnapshot(
    marketMode: marketMode ?? this.marketMode,
    timeframe: timeframe ?? this.timeframe,
    spotInstrumentIds: spotInstrumentIds ?? this.spotInstrumentIds,
    perpetualInstrumentIds:
        perpetualInstrumentIds ?? this.perpetualInstrumentIds,
  );

  bool hasSameValues(WatchlistSnapshot other) =>
      marketMode == other.marketMode &&
      timeframe == other.timeframe &&
      _sameIds(spotInstrumentIds, other.spotInstrumentIds) &&
      _sameIds(perpetualInstrumentIds, other.perpetualInstrumentIds);

  static bool _sameIds(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}

class WatchlistStore {
  WatchlistStore({required WatchlistStorage storage}) : _storage = storage;

  static const String storageKey = 'support_resistance_watchlist_snapshot';
  static const int schemaVersion = 1;

  final WatchlistStorage _storage;

  Future<WatchlistSnapshot> load() async {
    final raw = await _storage.readSnapshot();
    if (raw == null || raw.trim().isEmpty) return WatchlistSnapshot.initial();

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return WatchlistSnapshot.initial();
      final values = <String, dynamic>{
        for (final entry in decoded.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
      if (values['version'] != schemaVersion) {
        return WatchlistSnapshot.initial();
      }

      return WatchlistSnapshot(
        marketMode: _parseMode(values['marketMode']),
        timeframe: _parseTimeframe(values['timeframe']),
        spotInstrumentIds: _sanitizeInstrumentIds(
          values['spotInstrumentIds'],
          SupportResistanceMarketMode.spot,
        ),
        perpetualInstrumentIds: _sanitizeInstrumentIds(
          values['perpetualInstrumentIds'],
          SupportResistanceMarketMode.perpetual,
        ),
      );
    } on Object {
      return WatchlistSnapshot.initial();
    }
  }

  Future<void> save(WatchlistSnapshot snapshot) async {
    final encoded = jsonEncode(<String, Object>{
      'version': schemaVersion,
      'marketMode': snapshot.marketMode.name,
      'timeframe': snapshot.timeframe.name,
      'spotInstrumentIds': snapshot.spotInstrumentIds,
      'perpetualInstrumentIds': snapshot.perpetualInstrumentIds,
    });
    if (!await _storage.writeSnapshot(encoded)) {
      throw const WatchlistPersistenceException();
    }
  }

  static bool hasValidInstrumentId(
    SupportResistanceMarketMode mode,
    String instrumentId,
  ) {
    final pattern = mode == SupportResistanceMarketMode.spot
        ? RegExp(r'^[A-Z0-9]+-USDT$')
        : RegExp(r'^[A-Z0-9]+-USDT-SWAP$');
    return pattern.hasMatch(instrumentId);
  }

  static SupportResistanceMarketMode _parseMode(Object? value) {
    for (final mode in SupportResistanceMarketMode.values) {
      if (mode.name == value) return mode;
    }
    return SupportResistanceMarketMode.spot;
  }

  static SupportResistanceTimeframe _parseTimeframe(Object? value) {
    for (final timeframe in SupportResistanceTimeframe.values) {
      if (timeframe.name == value) return timeframe;
    }
    return SupportResistanceTimeframe.h6;
  }

  static List<String> _sanitizeInstrumentIds(
    Object? raw,
    SupportResistanceMarketMode mode,
  ) {
    if (raw is! List) return const <String>[];
    final result = <String>[];
    final seen = <String>{};
    for (final value in raw) {
      if (value is! String) continue;
      final instrumentId = value.trim().toUpperCase();
      if (!hasValidInstrumentId(mode, instrumentId) ||
          !seen.add(instrumentId)) {
        continue;
      }
      result.add(instrumentId);
      if (result.length == WatchlistSnapshot.maximumSelectionsPerMode) break;
    }
    return result;
  }
}

class WatchlistPersistenceException implements Exception {
  const WatchlistPersistenceException();
}
