import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/portfolio/data/risk/risk_local_store.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/action_plan.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_events.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_history.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/market_risk_engine.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_models.dart';

import 'fixtures/risk_test_fixtures.dart';

void main() {
  test(
    'RED-003 keeps corrupt/future records read-only and reports failed writes',
    () async {
      final corruptStorage = InMemoryRiskKeyValueStore();
      final corruptStore = RiskLocalStore(
        storage: corruptStorage,
        clock: () => riskTestNow,
      );
      const account = 'account-a';
      final key = corruptStore.settingsKey(account);
      corruptStorage.values[key] = '{not-json';
      final corruptLoad = await corruptStore.loadSettings(account);
      expect(corruptLoad.status, RiskStoreStatus.corrupt);
      final before = corruptStorage.values[key];
      final corruptSave = await corruptStore.saveSettings(
        accountHash: account,
        settings: const RiskSettings(),
      );
      expect(corruptSave.isReadOnly, isTrue);
      expect(corruptSave.notificationDeliveryAllowed, isFalse);
      expect(corruptStorage.values[key], before);

      final futureStorage = InMemoryRiskKeyValueStore();
      final futureStore = RiskLocalStore(
        storage: futureStorage,
        clock: () => riskTestNow,
      );
      final futureKey = futureStore.settingsKey(account);
      futureStorage.values[futureKey] = jsonEncode(<String, dynamic>{
        'schemaVersion': RiskLocalStore.schemaVersion + 1,
        'recordType': 'settings',
        'accountHash': account,
      });
      expect(
        (await futureStore.loadSettings(account)).status,
        RiskStoreStatus.futureSchema,
      );
      final futureBefore = futureStorage.values[futureKey];
      expect(
        (await futureStore.saveSettings(
          accountHash: account,
          settings: const RiskSettings(),
        )).isReadOnly,
        isTrue,
      );
      expect(futureStorage.values[futureKey], futureBefore);

      final failedStorage = InMemoryRiskKeyValueStore()..failWrites = true;
      final failedStore = RiskLocalStore(
        storage: failedStorage,
        clock: () => riskTestNow,
      );
      final failed = await failedStore.saveSettings(
        accountHash: account,
        settings: const RiskSettings(),
      );
      expect(failed.status, RiskStoreStatus.failed);
      expect(failed.notificationDeliveryAllowed, isFalse);
      expect(failedStorage.values, isEmpty);

      final interruptedStorage = InMemoryRiskKeyValueStore();
      final interruptedStore = RiskLocalStore(
        storage: interruptedStorage,
        clock: () => riskTestNow,
      );
      final firstSave = await interruptedStore.saveSettings(
        accountHash: account,
        settings: const RiskSettings(),
      );
      expect(firstSave.notificationDeliveryAllowed, isTrue);
      final durableBefore =
          interruptedStorage.values[interruptedStore.settingsKey(account)];
      interruptedStorage.failWrites = true;
      final interrupted = await interruptedStore.saveSettings(
        accountHash: account,
        settings: const RiskSettings(summaryHour: 9),
      );
      expect(interrupted.status, RiskStoreStatus.failed);
      expect(
        interruptedStorage.values[interruptedStore.settingsKey(account)],
        durableBefore,
      );

      final invalidRecord = episodeRecord(
        account: account,
        episode: 'episode-invalid-number',
        samples: <RiskHistorySample>[riskSample(buffer: double.nan)],
      );
      final invalidSave = await interruptedStore.saveEpisode(
        accountHash: account,
        record: invalidRecord,
      );
      expect(invalidSave.status, RiskStoreStatus.invalid);
      expect(invalidSave.notificationDeliveryAllowed, isFalse);

      expect(
        (await failedStore.saveSettings(
          accountHash: '',
          settings: const RiskSettings(),
        )).status,
        RiskStoreStatus.invalid,
      );
    },
  );

  test(
    'RED-003 isolates account namespaces and reopened position episodes',
    () async {
      final storage = InMemoryRiskKeyValueStore();
      final store = RiskLocalStore(storage: storage, clock: () => riskTestNow);
      final first = episodeRecord(
        account: 'account-a',
        episode: 'SUI:position:1',
      );
      expect(
        (await store.saveEpisode(
          accountHash: 'account-a',
          record: first,
        )).isSuccess,
        isTrue,
      );
      expect(
        (await store.loadEpisode(
          accountHash: 'account-b',
          episodeKey: first.episodeKey,
        )).status,
        RiskStoreStatus.missing,
      );
      expect(
        (await store.loadEpisode(
          accountHash: 'account-a',
          episodeKey: 'SUI:position:2',
        )).status,
        RiskStoreStatus.missing,
      );
      expect(
        (await store.loadEpisode(
          accountHash: 'account-a',
          episodeKey: first.episodeKey,
        )).value?.episodeKey,
        first.episodeKey,
      );

      final closedPair = episodeRecord(
        account: 'account-a',
        episode: 'SUI:position:closed',
        closedAt: riskTestNow.subtract(const Duration(minutes: 1)),
      );
      expect(
        (await store.saveEpisode(
          accountHash: 'account-a',
          record: closedPair,
        )).isSuccess,
        isTrue,
      );
      final reopenedPair = await store.loadEpisode(
        accountHash: 'account-a',
        episodeKey: 'SUI:position:reopened',
      );
      expect(reopenedPair.status, RiskStoreStatus.missing);
      expect(
        (await store.loadEpisode(
          accountHash: 'account-a',
          episodeKey: closedPair.episodeKey,
        )).value?.closedAt,
        isNotNull,
      );
      expect(
        store.episodeStorageKey('account-a', first.episodeKey),
        isNot(contains(first.episodeKey)),
      );
    },
  );

  test(
    'GREEN-003 saves/reloads typed settings, episode history and bounded retention',
    () async {
      final storage = InMemoryRiskKeyValueStore();
      final store = RiskLocalStore(
        storage: storage,
        clock: () => riskTestNow,
        retention: const RiskRetentionLimits(
          sampleAge: Duration(hours: 1),
          oiAge: Duration(hours: 1),
          eventAge: Duration(hours: 1),
          summaryAge: Duration(hours: 1),
          maxSamples: 2,
          maxOiSamples: 2,
          maxEvents: 2,
          maxEpisodes: 3,
        ),
      );
      const account = 'account-a';
      const settings = RiskSettings(
        customStressChanges: <double>[-0.12],
        customStressPrices: <double>[8.75],
        timeZone: 'Asia/Ho_Chi_Minh',
        summaryHour: 8,
      );
      final savedSettings = await store.saveSettings(
        accountHash: account,
        settings: settings,
      );
      expect(savedSettings.status, RiskStoreStatus.saved);
      final loadedSettings = await store.loadSettings(account);
      expect(loadedSettings.value?.timeZone, 'Asia/Ho_Chi_Minh');
      expect(loadedSettings.value?.customStressPrices.single, 8.75);

      final samples = <RiskHistorySample>[
        riskSample(at: riskTestNow.subtract(const Duration(hours: 2))),
        riskSample(at: riskTestNow.subtract(const Duration(minutes: 2))),
        riskSample(at: riskTestNow.subtract(const Duration(minutes: 1))),
        riskSample(at: riskTestNow),
      ];
      final oi = <MarketOpenInterestSample>[
        oiSample(at: riskTestNow.subtract(const Duration(hours: 2))),
        oiSample(at: riskTestNow.subtract(const Duration(minutes: 2))),
        oiSample(
          at: riskTestNow.subtract(const Duration(minutes: 1)),
          value: 101,
        ),
        oiSample(at: riskTestNow, value: 102),
      ];
      final events = List<RiskEvent>.generate(
        4,
        (index) => RiskEvent(
          id: 'event-$index',
          episodeKey: 'episode-a',
          kind: RiskEventKind.stateChange,
          message: 'Risk changed',
          createdAt: index == 0
              ? riskTestNow.subtract(const Duration(hours: 2))
              : riskTestNow.subtract(Duration(minutes: 3 - index)),
          observedAt: index == 0
              ? riskTestNow.subtract(const Duration(hours: 2))
              : riskTestNow.subtract(Duration(minutes: 3 - index)),
        ),
      );
      final summaries = <RiskDailySummary>[
        RiskDailySummary(
          episodeKey: 'episode-a',
          dateKey: '2026-09-09',
          timeZone: 'UTC',
          capturedAt: riskTestNow.subtract(const Duration(hours: 2)),
          quality: const RiskQuality.complete(),
        ),
        RiskDailySummary(
          episodeKey: 'episode-a',
          dateKey: '2026-09-10',
          timeZone: 'UTC',
          capturedAt: riskTestNow.subtract(const Duration(minutes: 2)),
          quality: const RiskQuality.complete(),
        ),
      ];
      final record = episodeRecord(
        account: account,
        episode: 'episode-a',
        samples: samples,
        openInterest: oi,
        events: events,
        summaries: summaries,
      );
      final savedEpisode = await store.saveEpisode(
        accountHash: account,
        record: record,
        activeEpisodeKey: 'episode-a',
      );
      expect(savedEpisode.status, RiskStoreStatus.saved);
      final loaded = await store.loadEpisode(
        accountHash: account,
        episodeKey: 'episode-a',
      );
      expect(loaded.status, RiskStoreStatus.loaded);
      expect(loaded.value?.samples.length, 2);
      expect(loaded.value?.openInterest.length, 2);
      expect(loaded.value?.events.length, 2);
      expect(loaded.value?.summaries.length, 1);
      expect(loaded.value?.samples.last.observedAt, riskTestNow);
      expect(loaded.value?.openInterest.last.oiCcy, 102);

      final closedOne = episodeRecord(
        account: account,
        episode: 'episode-1',
        closedAt: riskTestNow.subtract(const Duration(days: 1)),
      );
      final closedTwo = episodeRecord(
        account: account,
        episode: 'episode-2',
        closedAt: riskTestNow.subtract(const Duration(hours: 1)),
      );
      expect(
        (await store.saveEpisode(
          accountHash: account,
          record: closedOne,
        )).isSuccess,
        isTrue,
      );
      expect(
        (await store.saveEpisode(
          accountHash: account,
          record: closedTwo,
        )).isSuccess,
        isTrue,
      );
      final active = episodeRecord(account: account, episode: 'episode-3');
      expect(
        (await store.saveEpisode(
          accountHash: account,
          record: active,
          activeEpisodeKey: 'episode-3',
        )).isSuccess,
        isTrue,
      );
      expect(
        (await store.loadEpisode(
          accountHash: account,
          episodeKey: 'episode-1',
        )).status,
        RiskStoreStatus.missing,
      );
      expect(
        (await store.loadEpisode(
          accountHash: account,
          episodeKey: 'episode-2',
        )).status,
        RiskStoreStatus.loaded,
      );
      expect(
        (await store.loadEpisode(
          accountHash: account,
          episodeKey: 'episode-3',
        )).status,
        RiskStoreStatus.loaded,
      );

      expect(
        (await store.resetEpisode(
          accountHash: account,
          episodeKey: 'episode-3',
          confirmed: false,
        )).status,
        RiskStoreStatus.invalid,
      );
      expect(
        (await store.resetEpisode(
          accountHash: account,
          episodeKey: 'episode-3',
          confirmed: true,
        )).status,
        RiskStoreStatus.removed,
      );

      final historyRecord = episodeRecord(
        account: account,
        episode: 'history-only',
        samples: <RiskHistorySample>[riskSample(episode: 'history-only')],
      );
      expect(
        (await store.saveEpisode(
          accountHash: account,
          record: historyRecord,
        )).isSuccess,
        isTrue,
      );
      final cleared = await store.clearEpisodeHistory(
        accountHash: account,
        episodeKey: 'history-only',
        confirmed: true,
      );
      expect(cleared.status, RiskStoreStatus.saved);
      expect(cleared.value?.samples, isEmpty);
      expect(cleared.value?.plan.isValid, isTrue);
    },
  );

  test('GREEN-003 derives namespaced keys without raw identity text', () {
    final hash = RiskAccountNamespace.hash(
      environment: 'production',
      uid: 'uid-123',
    );
    expect(hash, hasLength(64));
    expect(hash, isNot(contains('uid-123')));
    expect(RiskAccountNamespace.hash(environment: '', uid: 'uid-123'), isEmpty);
  });

  test('GREEN-003 serializes complete per-record writes', () async {
    final storage = _SerialProbeStorage();
    final store = RiskLocalStore(storage: storage, clock: () => riskTestNow);
    final results = await Future.wait(<Future<RiskStoreResult<RiskSettings>>>[
      store.saveSettings(
        accountHash: 'account-a',
        settings: const RiskSettings(summaryHour: 8),
      ),
      store.saveSettings(
        accountHash: 'account-b',
        settings: const RiskSettings(summaryHour: 9),
      ),
    ]);
    expect(
      results.every((result) => result.status == RiskStoreStatus.saved),
      isTrue,
    );
    expect(storage.maxActiveWrites, 1);
    expect(storage.values.keys, hasLength(2));
    expect(
      storage.values.values.every((value) => value.startsWith('{')),
      isTrue,
    );
  });
}

class _SerialProbeStorage implements RiskKeyValueStore {
  final Map<String, String> values = <String, String>{};
  int activeWrites = 0;
  int maxActiveWrites = 0;

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<bool> setString(String key, String value) async {
    activeWrites++;
    if (activeWrites > maxActiveWrites) maxActiveWrites = activeWrites;
    await Future<void>.delayed(const Duration(milliseconds: 1));
    values[key] = value;
    activeWrites--;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }

  @override
  Future<Set<String>> getKeys() async => values.keys.toSet();
}
