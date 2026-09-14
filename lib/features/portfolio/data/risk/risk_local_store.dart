import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/risk/action_plan.dart';
import '../../domain/risk/market_risk_engine.dart';
import '../../domain/risk/risk_events.dart';
import '../../domain/risk/risk_history.dart';
import '../../domain/risk/risk_models.dart';

/// The smallest asynchronous interface needed by [RiskLocalStore].  It maps
/// directly to SharedPreferences' string methods and is easy to fake in unit
/// tests without initializing a Flutter platform plugin.
abstract class RiskKeyValueStore {
  Future<String?> getString(String key);

  Future<bool> setString(String key, String value);

  Future<bool> remove(String key);

  Future<Set<String>> getKeys() async => const <String>{};
}

typedef RiskStorage = RiskKeyValueStore;

class SharedPreferencesRiskStorage implements RiskKeyValueStore {
  const SharedPreferencesRiskStorage(this.preferences);

  final SharedPreferences preferences;

  @override
  Future<String?> getString(String key) async => preferences.getString(key);

  @override
  Future<bool> setString(String key, String value) =>
      preferences.setString(key, value);

  @override
  Future<bool> remove(String key) => preferences.remove(key);

  @override
  Future<Set<String>> getKeys() async => preferences.getKeys();
}

class InMemoryRiskKeyValueStore implements RiskKeyValueStore {
  InMemoryRiskKeyValueStore({Map<String, String>? initial})
    : values = <String, String>{...?initial};

  final Map<String, String> values;
  bool failWrites = false;
  bool failRemoves = false;
  Object? writeError;
  int writeCount = 0;

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<bool> setString(String key, String value) async {
    writeCount++;
    if (writeError != null) throw writeError!;
    if (failWrites) return false;
    values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    if (failRemoves) return false;
    values.remove(key);
    return true;
  }

  @override
  Future<Set<String>> getKeys() async => values.keys.toSet();
}

enum RiskStoreStatus {
  missing,
  loaded,
  saved,
  failed,
  corrupt,
  futureSchema,
  readOnly,
  invalid,
  removed,
}

class RiskStoreResult<T> {
  const RiskStoreResult({
    required this.status,
    this.value,
    this.reason,
    this.key,
  });

  final RiskStoreStatus status;
  final T? value;
  final String? reason;
  final String? key;

  bool get isSuccess =>
      status == RiskStoreStatus.loaded || status == RiskStoreStatus.saved;

  /// T22 may deliver a newly reduced event only after its latch/event record
  /// was durably saved. Loading or failing a record never grants that gate.
  bool get notificationDeliveryAllowed => status == RiskStoreStatus.saved;

  bool get isReadOnly =>
      status == RiskStoreStatus.readOnly ||
      status == RiskStoreStatus.corrupt ||
      status == RiskStoreStatus.futureSchema;

  bool get isMissing => status == RiskStoreStatus.missing;
}

typedef RiskStoreSaveResult<T> = RiskStoreResult<T>;

class RiskAccountNamespace {
  const RiskAccountNamespace._();

  /// Account identity is intentionally derived from non-secret environment and
  /// uid strings. Callers must not pass API keys or credentials here.
  static String hash({required String environment, required String uid}) {
    final normalizedEnvironment = environment.trim();
    final normalizedUid = uid.trim();
    if (normalizedEnvironment.isEmpty || normalizedUid.isEmpty) return '';
    return sha256
        .convert(utf8.encode('$normalizedEnvironment|$normalizedUid'))
        .toString();
  }
}

class RiskRetentionLimits {
  const RiskRetentionLimits({
    this.sampleAge = const Duration(days: 30),
    this.oiAge = const Duration(hours: 25),
    this.eventAge = const Duration(days: 90),
    this.summaryAge = const Duration(days: 90),
    this.closedEpisodeAge = const Duration(days: 90),
    this.maxSamples = 2880,
    this.maxOiSamples = 1500,
    this.maxEvents = 1000,
    this.maxEpisodes = 20,
  });

  final Duration sampleAge;
  final Duration oiAge;
  final Duration eventAge;
  final Duration summaryAge;
  final Duration closedEpisodeAge;
  final int maxSamples;
  final int maxOiSamples;
  final int maxEvents;
  final int maxEpisodes;
}

class RiskEpisodeRecord {
  RiskEpisodeRecord({
    required this.accountHash,
    required this.episodeKey,
    required this.plan,
    required this.updatedAt,
    this.samples = const <RiskHistorySample>[],
    this.openInterest = const <MarketOpenInterestSample>[],
    this.events = const <RiskEvent>[],
    this.summaries = const <RiskDailySummary>[],
    RiskEventLatch? latches,
    this.lastCheckBaseline,
    this.closedAt,
  }) : latches = latches ?? RiskEventLatch(episodeKey: episodeKey);

  final String accountHash;
  final String episodeKey;
  final RiskPlan plan;
  final DateTime updatedAt;
  final List<RiskHistorySample> samples;
  final List<MarketOpenInterestSample> openInterest;
  final List<RiskEvent> events;
  final List<RiskDailySummary> summaries;
  final RiskEventLatch latches;
  final RiskHistorySample? lastCheckBaseline;
  final DateTime? closedAt;

  RiskHistorySample? get currentSample => samples.isEmpty ? null : samples.last;

  bool get isClosed => closedAt != null;

  RiskEpisodeRecord copyWith({
    RiskPlan? plan,
    DateTime? updatedAt,
    List<RiskHistorySample>? samples,
    List<MarketOpenInterestSample>? openInterest,
    List<RiskEvent>? events,
    List<RiskDailySummary>? summaries,
    RiskEventLatch? latches,
    RiskHistorySample? lastCheckBaseline,
    DateTime? closedAt,
    bool clearClosedAt = false,
    bool clearLastCheckBaseline = false,
  }) {
    return RiskEpisodeRecord(
      accountHash: accountHash,
      episodeKey: episodeKey,
      plan: plan ?? this.plan,
      updatedAt: updatedAt ?? this.updatedAt,
      samples: samples ?? this.samples,
      openInterest: openInterest ?? this.openInterest,
      events: events ?? this.events,
      summaries: summaries ?? this.summaries,
      latches: latches ?? this.latches,
      lastCheckBaseline: clearLastCheckBaseline
          ? null
          : lastCheckBaseline ?? this.lastCheckBaseline,
      closedAt: clearClosedAt ? null : closedAt ?? this.closedAt,
    );
  }

  RiskEpisodeRecord prune(
    DateTime now, {
    RiskRetentionLimits limits = const RiskRetentionLimits(),
  }) {
    final sampleCutoff = now.toUtc().subtract(limits.sampleAge);
    final oiCutoff = now.toUtc().subtract(limits.oiAge);
    final eventCutoff = now.toUtc().subtract(limits.eventAge);
    final summaryCutoff = now.toUtc().subtract(limits.summaryAge);
    List<T> bounded<T>(List<T> values, int max) {
      if (values.length <= max) return List<T>.unmodifiable(values);
      return List<T>.unmodifiable(values.sublist(values.length - max));
    }

    final nextSamples = bounded(
      samples.where((item) => !item.observedAt.isBefore(sampleCutoff)).toList(),
      limits.maxSamples,
    );
    final nextOi = bounded(
      openInterest.where((item) => !item.timestamp.isBefore(oiCutoff)).toList(),
      limits.maxOiSamples,
    );
    final nextEvents = bounded(
      events.where((item) => !item.createdAt.isBefore(eventCutoff)).toList(),
      limits.maxEvents,
    );
    final nextSummaries = List<RiskDailySummary>.unmodifiable(
      summaries
          .where((item) => !item.capturedAt.isBefore(summaryCutoff))
          .toList(),
    );
    return copyWith(
      samples: nextSamples,
      openInterest: nextOi,
      events: nextEvents,
      summaries: nextSummaries,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': RiskLocalStore.schemaVersion,
    'recordType': 'episode',
    'accountHash': accountHash,
    'episodeKey': episodeKey,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'closedAt': closedAt?.toUtc().toIso8601String(),
    'plan': plan.toJson(),
    'samples': samples.map((item) => item.toJson()).toList(growable: false),
    'openInterest': openInterest
        .map(_openInterestToJson)
        .toList(growable: false),
    'events': events.map((item) => item.toJson()).toList(growable: false),
    'summaries': summaries.map((item) => item.toJson()).toList(growable: false),
    'latches': latches.toJson(),
    'lastCheckBaseline': lastCheckBaseline?.toJson(),
  };

  factory RiskEpisodeRecord.fromJson(Map<String, dynamic> json) {
    final rawSamples = _requiredList(json, 'samples');
    final rawOi = _requiredList(json, 'openInterest');
    final rawEvents = _requiredList(json, 'events');
    final rawSummaries = _requiredList(json, 'summaries');
    final accountHash = _requiredString(json, 'accountHash');
    final episodeKey = _requiredString(json, 'episodeKey');
    final plan = RiskPlan.fromJson(_requiredMap(json, 'plan'));
    if (plan.episodeKey != episodeKey) {
      throw const FormatException(
        'Plan episode identity does not match record',
      );
    }
    final samples = rawSamples
        .map((item) => RiskHistorySample.fromJson(_map(item, 'sample')))
        .toList(growable: false);
    for (final sample in samples) {
      if (sample.episodeKey != episodeKey) {
        throw const FormatException('Sample episode identity does not match');
      }
    }
    _requireAscendingHistory(samples);
    final openInterest = rawOi
        .map((item) => _openInterestFromJson(_map(item, 'openInterest')))
        .toList(growable: false);
    _requireAscendingOi(openInterest);
    final events = rawEvents
        .map((item) => RiskEvent.fromJson(_map(item, 'event')))
        .toList(growable: false);
    for (final event in events) {
      if (event.episodeKey != episodeKey) {
        throw const FormatException('Event episode identity does not match');
      }
    }
    final summaries = rawSummaries
        .map((item) => RiskDailySummary.fromJson(_map(item, 'summary')))
        .toList(growable: false);
    for (final summary in summaries) {
      if (summary.episodeKey != episodeKey) {
        throw const FormatException('Summary episode identity does not match');
      }
    }
    final latch = RiskEventLatch.fromJson(_requiredMap(json, 'latches'));
    if (latch.episodeKey != episodeKey) {
      throw const FormatException('Latch episode identity does not match');
    }
    final rawBaseline = json['lastCheckBaseline'];
    final baseline = rawBaseline == null
        ? null
        : RiskHistorySample.fromJson(_map(rawBaseline, 'lastCheckBaseline'));
    if (baseline != null && baseline.episodeKey != episodeKey) {
      throw const FormatException('Baseline episode identity does not match');
    }
    return RiskEpisodeRecord(
      accountHash: accountHash,
      episodeKey: episodeKey,
      plan: plan,
      updatedAt: _requiredDate(json, 'updatedAt'),
      closedAt: _optionalDate(json['closedAt']),
      samples: List.unmodifiable(samples),
      openInterest: List.unmodifiable(openInterest),
      events: List.unmodifiable(events),
      summaries: List.unmodifiable(summaries),
      latches: latch,
      lastCheckBaseline: baseline,
    );
  }
}

class RiskLocalStore {
  RiskLocalStore({
    required this.storage,
    RiskStoreClock? clock,
    this.retention = const RiskRetentionLimits(),
  }) : clock = clock ?? _systemClock;

  static const int schemaVersion = 1;
  static const String keyPrefix = 'risk.v1.';

  final RiskKeyValueStore storage;
  final RiskStoreClock clock;
  final RiskRetentionLimits retention;

  static DateTime _systemClock() => DateTime.now().toUtc();

  // A queue is shared by settings, episode and reset writes. Each operation
  // writes one complete JSON string under one key before the next starts.
  static Future<void> _writeQueue = Future<void>.value();
  final Set<String> _readOnlyKeys = <String>{};

  String settingsKey(String accountHash) => '$keyPrefix$accountHash.settings';

  String episodeStorageKey(String accountHash, String episodeKey) {
    final episodeHash = sha256
        .convert(utf8.encode('$accountHash|$episodeKey'))
        .toString();
    return '$keyPrefix$accountHash.episode.$episodeHash';
  }

  Future<RiskStoreResult<RiskSettings>> loadSettings(String accountHash) async {
    final validated = _validateAccount<RiskSettings>(accountHash);
    if (validated != null) return validated;
    final key = settingsKey(accountHash);
    return _readRecord<RiskSettings>(
      key,
      recordType: 'settings',
      accountHash: accountHash,
      decode: (json) => RiskSettings.fromJson(_requiredMap(json, 'settings')),
    );
  }

  Future<RiskStoreResult<RiskEpisodeRecord>> loadEpisode({
    required String accountHash,
    required String episodeKey,
  }) async {
    final validated = _validateAccount<RiskEpisodeRecord>(accountHash);
    if (validated != null) return validated;
    if (episodeKey.trim().isEmpty) {
      return const RiskStoreResult(
        status: RiskStoreStatus.invalid,
        reason: 'episodeKey is required for persistence',
      );
    }
    final key = episodeStorageKey(accountHash, episodeKey);
    return _readRecord<RiskEpisodeRecord>(
      key,
      recordType: 'episode',
      accountHash: accountHash,
      decode: RiskEpisodeRecord.fromJson,
      identity: (record) =>
          record.episodeKey == episodeKey && record.accountHash == accountHash,
    );
  }

  Future<RiskStoreSaveResult<RiskSettings>> saveSettings({
    required String accountHash,
    required RiskSettings settings,
  }) async {
    final validated = _validateAccount<RiskSettings>(accountHash);
    if (validated != null) return validated;
    final errors = settings.validate();
    if (errors.isNotEmpty) {
      return RiskStoreResult<RiskSettings>(
        status: RiskStoreStatus.invalid,
        reason: errors.join('; '),
        key: settingsKey(accountHash),
      );
    }
    final key = settingsKey(accountHash);
    final payload = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'recordType': 'settings',
      'accountHash': accountHash,
      'updatedAt': clock().toUtc().toIso8601String(),
      'settings': settings.toJson(),
    };
    return _saveJson(
      key,
      payload,
      settings,
      recordType: 'settings',
      accountHash: accountHash,
      decode: (json) => RiskSettings.fromJson(_requiredMap(json, 'settings')),
    );
  }

  Future<RiskStoreSaveResult<RiskEpisodeRecord>> saveEpisode({
    required String accountHash,
    required RiskEpisodeRecord record,
    String? activeEpisodeKey,
  }) async {
    final validated = _validateAccount<RiskEpisodeRecord>(accountHash);
    if (validated != null) return validated;
    if (record.accountHash != accountHash ||
        record.episodeKey.trim().isEmpty ||
        record.plan.episodeKey != record.episodeKey) {
      return const RiskStoreResult(
        status: RiskStoreStatus.invalid,
        reason: 'Episode/account identity does not match the save namespace',
      );
    }
    final validation = _validateEpisodeRecord(record, clock().toUtc());
    if (validation.isNotEmpty) {
      return RiskStoreResult<RiskEpisodeRecord>(
        status: RiskStoreStatus.invalid,
        reason: validation.join('; '),
      );
    }
    final key = episodeStorageKey(accountHash, record.episodeKey);
    final readOnly = _readOnlyResult<RiskEpisodeRecord>(key);
    if (readOnly != null) return readOnly;
    final prepared = record
        .copyWith(updatedAt: clock().toUtc())
        .prune(clock().toUtc(), limits: retention);
    final payload = prepared.toJson();
    final result = await _saveJson(
      key,
      payload,
      prepared,
      recordType: 'episode',
      accountHash: accountHash,
      decode: RiskEpisodeRecord.fromJson,
      identity: (value) =>
          value.episodeKey == record.episodeKey &&
          value.accountHash == accountHash,
    );
    if (!result.isSuccess) return result;
    await _pruneClosedEpisodes(
      accountHash,
      activeEpisodeKey: activeEpisodeKey ?? record.episodeKey,
    );
    return result;
  }

  Future<RiskStoreResult<void>> resetSettings({
    required String accountHash,
    required bool confirmed,
  }) async {
    final validated = _validateAccount<void>(accountHash);
    if (validated != null) return validated;
    if (!confirmed) {
      return const RiskStoreResult(
        status: RiskStoreStatus.invalid,
        reason: 'Reset requires explicit confirmation',
      );
    }
    return _remove(settingsKey(accountHash));
  }

  Future<RiskStoreResult<void>> resetEpisode({
    required String accountHash,
    required String episodeKey,
    required bool confirmed,
  }) async {
    final validated = _validateAccount<void>(accountHash);
    if (validated != null) return validated;
    if (episodeKey.trim().isEmpty) {
      return const RiskStoreResult(
        status: RiskStoreStatus.invalid,
        reason: 'episodeKey is required for reset',
      );
    }
    if (!confirmed) {
      return const RiskStoreResult(
        status: RiskStoreStatus.invalid,
        reason: 'Reset requires explicit confirmation',
      );
    }
    return _remove(episodeStorageKey(accountHash, episodeKey));
  }

  /// Clear only the episode's locally derived history and anti-spam state,
  /// preserving the user-authored plan and the episode identity.
  Future<RiskStoreResult<RiskEpisodeRecord>> clearEpisodeHistory({
    required String accountHash,
    required String episodeKey,
    required bool confirmed,
  }) async {
    final validated = _validateAccount<RiskEpisodeRecord>(accountHash);
    if (validated != null) return validated;
    if (episodeKey.trim().isEmpty) {
      return const RiskStoreResult(
        status: RiskStoreStatus.invalid,
        reason: 'episodeKey is required for history clear',
      );
    }
    if (!confirmed) {
      return const RiskStoreResult(
        status: RiskStoreStatus.invalid,
        reason: 'History clear requires explicit confirmation',
      );
    }
    final loaded = await loadEpisode(
      accountHash: accountHash,
      episodeKey: episodeKey,
    );
    final record = loaded.value;
    if (record == null || !loaded.isSuccess) return loaded;
    return saveEpisode(
      accountHash: accountHash,
      record: record.copyWith(
        samples: const <RiskHistorySample>[],
        openInterest: const <MarketOpenInterestSample>[],
        events: const <RiskEvent>[],
        summaries: const <RiskDailySummary>[],
        latches: RiskEventLatch(episodeKey: episodeKey),
        clearLastCheckBaseline: true,
      ),
      activeEpisodeKey: episodeKey,
    );
  }

  Future<RiskStoreResult<void>> _remove(String key) async {
    return _serialized(() async {
      try {
        final removed = await storage.remove(key);
        if (!removed) {
          return RiskStoreResult<void>(
            status: RiskStoreStatus.failed,
            reason: 'Local risk record remove failed',
            key: key,
          );
        }
        _readOnlyKeys.remove(key);
        return RiskStoreResult<void>(status: RiskStoreStatus.removed, key: key);
      } catch (error) {
        return RiskStoreResult<void>(
          status: RiskStoreStatus.failed,
          reason: 'Local risk record remove failed: $error',
          key: key,
        );
      }
    });
  }

  Future<RiskStoreResult<T>> _saveJson<T>(
    String key,
    Map<String, dynamic> payload,
    T value, {
    required String recordType,
    required String accountHash,
    required T Function(Map<String, dynamic>) decode,
    bool Function(T value)? identity,
  }) async {
    final readOnly = _readOnlyResult<T>(key);
    if (readOnly != null) return readOnly;
    return _serialized(() async {
      try {
        final encoded = jsonEncode(payload);
        final guard = await _existingWriteGuard<T>(
          key,
          recordType: recordType,
          accountHash: accountHash,
          decode: decode,
          identity: identity,
        );
        if (guard != null) return guard;
        final saved = await storage.setString(key, encoded);
        if (!saved) {
          return RiskStoreResult<T>(
            status: RiskStoreStatus.failed,
            reason: 'Local risk record save failed',
            key: key,
          );
        }
        return RiskStoreResult<T>(
          status: RiskStoreStatus.saved,
          value: value,
          key: key,
        );
      } catch (error) {
        return RiskStoreResult<T>(
          status: RiskStoreStatus.failed,
          reason: 'Local risk record save failed: $error',
          key: key,
        );
      }
    });
  }

  Future<RiskStoreResult<T>?> _existingWriteGuard<T>(
    String key, {
    required String recordType,
    required String accountHash,
    required T Function(Map<String, dynamic>) decode,
    bool Function(T value)? identity,
  }) async {
    final raw = await storage.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('Record is not an object');
      }
      final json = decoded.map<String, dynamic>(
        (entryKey, entryValue) => MapEntry(entryKey.toString(), entryValue),
      );
      final version = json['schemaVersion'];
      if (version is! num || version % 1 != 0) {
        throw const FormatException('schemaVersion is missing or invalid');
      }
      if (version.toInt() > schemaVersion) {
        _readOnlyKeys.add(key);
        return RiskStoreResult<T>(
          status: RiskStoreStatus.futureSchema,
          reason: 'Future local risk schema is read-only',
          key: key,
        );
      }
      if (version.toInt() != schemaVersion ||
          json['recordType'] != recordType ||
          json['accountHash'] != accountHash) {
        throw const FormatException('Unsupported local risk record schema');
      }
      final existing = decode(json);
      if (identity != null && !identity(existing)) {
        throw const FormatException('Record identity does not match key');
      }
      return null;
    } on FormatException catch (error) {
      _readOnlyKeys.add(key);
      return RiskStoreResult<T>(
        status: RiskStoreStatus.corrupt,
        reason: 'Local risk record is corrupt: $error',
        key: key,
      );
    } on Object catch (error) {
      _readOnlyKeys.add(key);
      return RiskStoreResult<T>(
        status: RiskStoreStatus.corrupt,
        reason: 'Local risk record is corrupt: $error',
        key: key,
      );
    }
  }

  Future<RiskStoreResult<T>> _readRecord<T>(
    String key, {
    required String recordType,
    required String accountHash,
    required T Function(Map<String, dynamic>) decode,
    bool Function(T value)? identity,
  }) async {
    final readOnly = _readOnlyResult<T>(key);
    if (readOnly != null) return readOnly;
    final raw = await storage.getString(key);
    if (raw == null) {
      return RiskStoreResult<T>(status: RiskStoreStatus.missing, key: key);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('Record is not an object');
      }
      final json = decoded.map<String, dynamic>(
        (entryKey, value) => MapEntry(entryKey.toString(), value),
      );
      final version = json['schemaVersion'];
      if (version is! num || version % 1 != 0) {
        throw const FormatException('schemaVersion is missing or invalid');
      }
      if (version.toInt() > schemaVersion) {
        _readOnlyKeys.add(key);
        return RiskStoreResult<T>(
          status: RiskStoreStatus.futureSchema,
          reason: 'Future local risk schema is read-only',
          key: key,
        );
      }
      if (version.toInt() != schemaVersion ||
          json['recordType'] != recordType) {
        throw const FormatException('Unsupported local risk record schema');
      }
      if (json['accountHash'] != accountHash) {
        throw const FormatException('Account namespace does not match record');
      }
      final value = decode(json);
      if (identity != null && !identity(value)) {
        throw const FormatException('Record identity does not match key');
      }
      return RiskStoreResult<T>(
        status: RiskStoreStatus.loaded,
        value: value,
        key: key,
      );
    } catch (error) {
      _readOnlyKeys.add(key);
      return RiskStoreResult<T>(
        status: RiskStoreStatus.corrupt,
        reason: 'Local risk record is corrupt: $error',
        key: key,
      );
    }
  }

  Future<void> _pruneClosedEpisodes(
    String accountHash, {
    required String activeEpisodeKey,
  }) => _serialized(
    () => _pruneClosedEpisodesUnlocked(
      accountHash,
      activeEpisodeKey: activeEpisodeKey,
    ),
  );

  Future<void> _pruneClosedEpisodesUnlocked(
    String accountHash, {
    required String activeEpisodeKey,
  }) async {
    final keys = await storage.getKeys();
    final prefix = '$keyPrefix$accountHash.episode.';
    final episodeKeys = keys.where((key) => key.startsWith(prefix)).toList();
    final records = <_StoredEpisode>[];
    for (final key in episodeKeys) {
      if (_readOnlyKeys.contains(key)) continue;
      final raw = await storage.getString(key);
      if (raw == null) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final json = decoded.map<String, dynamic>(
          (entryKey, value) => MapEntry(entryKey.toString(), value),
        );
        final version = json['schemaVersion'];
        if (version is! num ||
            version % 1 != 0 ||
            version.toInt() != schemaVersion ||
            json['recordType'] != 'episode' ||
            json['accountHash'] != accountHash) {
          _readOnlyKeys.add(key);
          continue;
        }
        final record = RiskEpisodeRecord.fromJson(json);
        records.add(_StoredEpisode(key: key, record: record));
      } on Object {
        // A corrupt record is never silently deleted by retention pruning.
      }
    }
    final cutoff = clock().toUtc().subtract(retention.closedEpisodeAge);
    final expired = records
        .where(
          (item) =>
              item.record.episodeKey != activeEpisodeKey &&
              item.record.closedAt != null &&
              item.record.closedAt!.isBefore(cutoff),
        )
        .toList(growable: false);
    for (final candidate in expired) {
      try {
        if (await storage.remove(candidate.key)) {
          records.remove(candidate);
        }
      } on Object {
        // Preserve the record when pruning cannot be completed.
      }
    }
    if (records.length <= retention.maxEpisodes) return;
    final candidates =
        records
            .where(
              (item) =>
                  item.record.closedAt != null &&
                  item.record.episodeKey != activeEpisodeKey,
            )
            .toList()
          ..sort((left, right) {
            final leftAt = left.record.closedAt ?? left.record.updatedAt;
            final rightAt = right.record.closedAt ?? right.record.updatedAt;
            return leftAt.compareTo(rightAt);
          });
    var remaining = records.length - retention.maxEpisodes;
    for (final candidate in candidates) {
      if (remaining <= 0) break;
      try {
        if (await storage.remove(candidate.key)) remaining--;
      } on Object {
        break;
      }
    }
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _writeQueue = _writeQueue.then<void>((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  RiskStoreResult<T>? _readOnlyResult<T>(String key) {
    if (!_readOnlyKeys.contains(key)) return null;
    return RiskStoreResult<T>(
      status: RiskStoreStatus.readOnly,
      reason: 'Local risk record is read-only until explicitly reset',
      key: key,
    );
  }

  RiskStoreResult<T>? _validateAccount<T>(String accountHash) {
    if (accountHash.trim().isNotEmpty) return null;
    return RiskStoreResult<T>(
      status: RiskStoreStatus.invalid,
      reason: 'Unresolved account namespace is ephemeral and cannot persist',
    );
  }
}

List<String> _validateEpisodeRecord(RiskEpisodeRecord record, DateTime now) {
  final errors = <String>[];
  void finite(String name, double? value) {
    if (value != null && !value.isFinite) {
      errors.add('$name must be finite');
    }
  }

  void sampleNumbers(RiskHistorySample sample, String prefix) {
    finite('$prefix.markPrice', sample.markPrice);
    finite('$prefix.buffer', sample.buffer);
    finite('$prefix.effectiveLeverage', sample.effectiveLeverage);
    finite('$prefix.debt', sample.debt);
    finite('$prefix.marginRatio', sample.marginRatio);
    finite('$prefix.trueExit', sample.trueExit);
    finite('$prefix.entryPrice', sample.entryPrice);
    finite('$prefix.entryFeeRate', sample.entryFeeRate);
    finite('$prefix.exitFeeRate', sample.exitFeeRate);
    finite('$prefix.actualInterestToday', sample.actualInterestToday);
    finite('$prefix.knownInterestToday', sample.knownInterestToday);
    finite('$prefix.quantity', sample.quantity);
    finite('$prefix.margin', sample.margin);
    finite('$prefix.openInterestChange', sample.openInterestChange);
  }

  void eventNumbers(RiskEvent event, String prefix) {
    finite('$prefix.previousValue', event.previousValue);
    finite('$prefix.currentValue', event.currentValue);
    for (var index = 0; index < event.contributions.length; index++) {
      final contribution = event.contributions[index];
      finite(
        '$prefix.contributions[$index].previousValue',
        contribution.previousValue,
      );
      finite(
        '$prefix.contributions[$index].currentValue',
        contribution.currentValue,
      );
    }
  }

  void summaryNumbers(RiskDailySummary summary, String prefix) {
    finite('$prefix.buffer', summary.buffer);
    finite('$prefix.effectiveLeverage', summary.effectiveLeverage);
    finite('$prefix.actualInterestToday', summary.actualInterestToday);
    finite('$prefix.knownInterestToday', summary.knownInterestToday);
  }

  errors.addAll(record.plan.validate());
  finite('latches.lastNotifiedTrueExit', record.latches.lastNotifiedTrueExit);
  if (record.latches.lastSample != null) {
    sampleNumbers(record.latches.lastSample!, 'latches.lastSample');
  }
  if (record.latches.episodeKey != record.episodeKey) {
    errors.add('Latch episode identity does not match record');
  }
  if (record.lastCheckBaseline != null &&
      record.lastCheckBaseline!.episodeKey != record.episodeKey) {
    errors.add('Baseline episode identity does not match record');
  }
  for (var index = 0; index < record.samples.length; index++) {
    final sample = record.samples[index];
    sampleNumbers(sample, 'samples[$index]');
    if (sample.episodeKey != record.episodeKey) {
      errors.add('Sample episode identity does not match record');
    }
    if (sample.observedAt.isAfter(now)) errors.add('Future history sample');
    if (index > 0 &&
        !sample.observedAt.isAfter(record.samples[index - 1].observedAt)) {
      errors.add('History observations must be strictly ascending');
    }
  }
  for (var index = 0; index < record.openInterest.length; index++) {
    final sample = record.openInterest[index];
    finite('openInterest[$index].oiCcy', sample.oiCcy);
    if (sample.timestamp.isAfter(now)) errors.add('Future OI sample');
    if (index > 0 &&
        !sample.timestamp.isAfter(record.openInterest[index - 1].timestamp)) {
      errors.add('OI timestamps must be strictly ascending');
    }
  }
  for (var index = 0; index < record.events.length; index++) {
    final event = record.events[index];
    eventNumbers(event, 'events[$index]');
    if (event.episodeKey != record.episodeKey) {
      errors.add('Event episode identity does not match record');
    }
    if (event.createdAt.isAfter(now) || event.observedAt.isAfter(now)) {
      errors.add('Future risk event');
    }
  }
  for (var index = 0; index < record.summaries.length; index++) {
    final summary = record.summaries[index];
    summaryNumbers(summary, 'summaries[$index]');
    if (summary.episodeKey != record.episodeKey) {
      errors.add('Summary episode identity does not match record');
    }
    if (summary.capturedAt.isAfter(now)) errors.add('Future daily summary');
  }
  if (record.lastCheckBaseline != null) {
    sampleNumbers(record.lastCheckBaseline!, 'lastCheckBaseline');
  }
  return errors.toSet().toList(growable: false);
}

typedef RiskStoreClock = DateTime Function();

class _StoredEpisode {
  const _StoredEpisode({required this.key, required this.record});

  final String key;
  final RiskEpisodeRecord record;
}

Map<String, dynamic> _openInterestToJson(MarketOpenInterestSample sample) =>
    <String, dynamic>{
      'instrument': sample.instrument,
      'timestamp': sample.timestamp.toUtc().toIso8601String(),
      'oiCcy': sample.oiCcy,
      'source': _sourceToJson(sample.source),
    };

MarketOpenInterestSample _openInterestFromJson(Map<String, dynamic> json) {
  final oi = _optionalDouble(json['oiCcy']);
  if (oi == null || oi <= 0) throw const FormatException('Invalid oiCcy');
  return MarketOpenInterestSample(
    instrument: _requiredString(json, 'instrument'),
    timestamp: _requiredDate(json, 'timestamp'),
    oiCcy: oi,
    source: _sourceFromJson(_requiredMap(json, 'source')),
  );
}

void _requireAscendingOi(List<MarketOpenInterestSample> samples) {
  for (var index = 1; index < samples.length; index++) {
    if (!samples[index].timestamp.isAfter(samples[index - 1].timestamp)) {
      throw const FormatException('OI timestamps must be strictly ascending');
    }
  }
}

void _requireAscendingHistory(List<RiskHistorySample> samples) {
  for (var index = 1; index < samples.length; index++) {
    if (!samples[index].observedAt.isAfter(samples[index - 1].observedAt)) {
      throw const FormatException(
        'History observations must be strictly ascending',
      );
    }
  }
}

Map<String, dynamic> _sourceToJson(MarketSourceInfo source) =>
    <String, dynamic>{
      'venue': source.venue,
      'instrument': source.instrument,
      'endpoint': source.endpoint,
      'observedAt': source.observedAt?.toUtc().toIso8601String(),
      'sourceAt': source.sourceAt?.toUtc().toIso8601String(),
      'windowStart': source.windowStart?.toUtc().toIso8601String(),
      'windowEnd': source.windowEnd?.toUtc().toIso8601String(),
      'quality': _qualityToJson(source.quality),
    };

MarketSourceInfo _sourceFromJson(Map<String, dynamic> json) => MarketSourceInfo(
  venue: _requiredString(json, 'venue'),
  instrument: _requiredString(json, 'instrument'),
  endpoint: _requiredString(json, 'endpoint'),
  observedAt: _optionalDate(json['observedAt']),
  sourceAt: _optionalDate(json['sourceAt']),
  windowStart: _optionalDate(json['windowStart']),
  windowEnd: _optionalDate(json['windowEnd']),
  quality: _qualityFromJson(_requiredMap(json, 'quality')),
);

Map<String, dynamic> _qualityToJson(RiskQuality quality) => <String, dynamic>{
  'status': quality.status.name,
  'source': quality.source,
  'reason': quality.reason,
  'observedAt': quality.observedAt?.toUtc().toIso8601String(),
  'sourceAt': quality.sourceAt?.toUtc().toIso8601String(),
};

RiskQuality _qualityFromJson(Map<String, dynamic> json) {
  final statusText = _requiredString(json, 'status');
  final status = RiskQualityStatus.values.firstWhere(
    (value) => value.name == statusText,
    orElse: () => throw FormatException('Unknown quality status: $statusText'),
  );
  return RiskQuality(
    status: status,
    source: _optionalString(json['source']),
    reason: _optionalString(json['reason']),
    observedAt: _optionalDate(json['observedAt']),
    sourceAt: _optionalDate(json['sourceAt']),
  );
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string');
  }
  return value;
}

String? _optionalString(Object? value) => value is String ? value : null;

DateTime _requiredDate(Map<String, dynamic> json, String key) {
  final value = _optionalDate(json[key]);
  if (value == null) throw FormatException('$key must be an ISO timestamp');
  return value;
}

DateTime? _optionalDate(Object? value) {
  if (value == null) return null;
  if (value is! String) throw const FormatException('Invalid timestamp');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw const FormatException('Invalid timestamp');
  return parsed.toUtc();
}

double? _optionalDouble(Object? value) {
  if (value == null) return null;
  if (value is! num || !value.toDouble().isFinite) {
    throw const FormatException('Expected finite number');
  }
  return value.toDouble();
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! Map) throw FormatException('$key must be an object');
  return value.map<String, dynamic>(
    (itemKey, itemValue) => MapEntry(itemKey.toString(), itemValue),
  );
}

Map<String, dynamic> _map(Object? value, String key) {
  if (value is! Map) throw FormatException('$key must be an object');
  return value.map<String, dynamic>(
    (itemKey, itemValue) => MapEntry(itemKey.toString(), itemValue),
  );
}

List<Object?> _requiredList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List) throw FormatException('$key must be an array');
  return value.cast<Object?>();
}
