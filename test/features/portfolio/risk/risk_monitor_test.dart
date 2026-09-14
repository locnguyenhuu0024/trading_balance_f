import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trading_balance_f/features/portfolio/application/risk_monitor.dart';
import 'package:trading_balance_f/features/portfolio/application/risk_monitor_bridge.dart';
import 'package:trading_balance_f/features/portfolio/application/risk_notification_sink.dart';
import 'package:trading_balance_f/features/portfolio/data/risk/risk_repository.dart';
import 'package:trading_balance_f/features/portfolio/data/risk/risk_local_store.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/market_risk_engine.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/action_plan.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_models.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_events.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_history.dart';

import 'fixtures/risk_monitor_fixtures.dart';

class FakeRiskHttpAdapter implements HttpClientAdapter {
  int? failureStatus;
  String? failurePath;
  String? retryAfterValue;
  List<Map<String, dynamic>>? interestRows;
  bool networkFailure = false;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    if (networkFailure &&
        (failurePath == null || options.uri.path == failurePath)) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'synthetic offline',
      );
    }
    final status = failureStatus;
    if (status != null &&
        (failurePath == null || options.uri.path == failurePath)) {
      final response = Response<dynamic>(
        requestOptions: options,
        statusCode: status,
        data: const <String, dynamic>{'code': '1'},
        headers: (retryAfterValue == null && status != 429)
            ? Headers()
            : Headers.fromMap(<String, List<String>>{
                'retry-after': <String>[retryAfterValue ?? '90'],
              }),
      );
      throw DioException(
        requestOptions: options,
        response: response,
        type: DioExceptionType.badResponse,
      );
    }
    final data =
        options.uri.path == RiskRepository.interestAccruedEndpoint &&
            interestRows != null
        ? <String, dynamic>{'code': '0', 'msg': '', 'data': interestRows}
        : _riskHttpPayload(options.uri.path);
    return ResponseBody.fromString(
      jsonEncode(data),
      200,
      headers: <String, List<String>>{
        'content-type': <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class PendingRiskHttpAdapter implements HttpClientAdapter {
  int calls = 0;
  final Completer<ResponseBody> firstResponse = Completer<ResponseBody>();
  final Completer<ResponseBody> secondResponse = Completer<ResponseBody>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    calls++;
    return calls == 1 ? firstResponse.future : secondResponse.future;
  }

  @override
  void close({bool force = false}) {}
}

class RepositoryBackedMonitorSource
    implements
        RiskMonitorDataSource,
        RiskMonitorSelectionFailureMetadata,
        RiskMonitorCacheInvalidator {
  RepositoryBackedMonitorSource(this.repository, this.clock);

  final RiskRepository repository;
  final FakeRiskClock clock;
  int clearCachesCalls = 0;

  @override
  RiskRepositorySelectionFailure? get lastSelectionFailure =>
      repository.lastSelectionFailure;

  @override
  void clearCaches() {
    clearCachesCalls++;
    repository.clearCaches();
  }

  @override
  Future<RiskPositionSelection> loadPosition({
    String? selectedPositionId,
    String? selectedEpisodeKey,
  }) => repository.loadPosition(
    selectedPositionId: selectedPositionId,
    selectedEpisodeKey: selectedEpisodeKey,
  );

  @override
  Future<MarketRiskSnapshot> loadMarket({
    required RiskPosition position,
    DateTime? now,
  }) async => syntheticMarketSnapshot(now ?? clock.value);
}

Map<String, dynamic> _riskHttpPayload(String path) {
  if (path == RiskRepository.configEndpoint) {
    return <String, dynamic>{
      'code': '0',
      'msg': '',
      'data': <Map<String, dynamic>>[
        <String, dynamic>{
          'uid': 'synthetic-user',
          'mgnIsoMode': 'auto_transfers_ccy',
        },
      ],
    };
  }
  if (path == RiskRepository.positionsEndpoint) {
    return <String, dynamic>{
      'code': '0',
      'msg': '',
      'data': <Map<String, dynamic>>[
        <String, dynamic>{
          'instId': 'SUI-USDT',
          'instType': 'MARGIN',
          'mgnMode': 'isolated',
          'posSide': 'net',
          'pos': '10',
          'posId': 'synthetic-position',
          'posCcy': 'SUI',
          'ccy': 'USDT',
          'liabCcy': 'USDT',
          'avgPx': '10',
          'markPx': '10',
          'liqPx': '6',
          'margin': '100',
          'upl': '0',
          'lever': '2',
          'mgnRatio': '4',
          'mmr': '10',
          'liab': '100',
          'interest': '1',
          'cTime': '1788220800000',
          'uTime': '1788998400000',
        },
      ],
    };
  }
  if (path == RiskRepository.instrumentsEndpoint) {
    return <String, dynamic>{
      'code': '0',
      'msg': '',
      'data': <Map<String, dynamic>>[
        <String, dynamic>{
          'instId': 'SUI-USDT',
          'instType': 'MARGIN',
          'groupId': '7',
        },
      ],
    };
  }
  if (path == RiskRepository.feeEndpoint) {
    return <String, dynamic>{
      'code': '0',
      'msg': '',
      'data': <Map<String, dynamic>>[
        <String, dynamic>{
          'instType': 'MARGIN',
          'instId': 'SUI-USDT',
          'feeGroup': <Map<String, dynamic>>[
            <String, dynamic>{'groupId': '7', 'taker': '-0.001'},
          ],
        },
      ],
    };
  }
  if (path == RiskRepository.interestRateEndpoint) {
    return <String, dynamic>{
      'code': '0',
      'msg': '',
      'data': <Map<String, dynamic>>[
        <String, dynamic>{'ccy': 'USDT', 'interestRate': '0.00001'},
      ],
    };
  }
  if (path == RiskRepository.interestAccruedEndpoint) {
    return <String, dynamic>{'code': '0', 'msg': '', 'data': <dynamic>[]};
  }
  throw StateError('Unexpected synthetic endpoint $path');
}

void main() {
  test(
    'RED-005 invalidates a late account response before any write',
    () async {
      final clock = FakeRiskClock();
      final source = FakeRiskSource(
        clock: clock,
        position: () => syntheticRiskPosition(observedAt: clock.value),
      );
      final pending = Completer<RiskPositionSelection>();
      source.pendingPosition = pending.future;
      final persistence = FakeRiskPersistence();
      final sink = FakeRiskNotificationSink();
      final monitor = RiskMonitor(
        dataSource: source,
        persistence: persistence,
        clock: clock.now,
        notificationSink: sink,
      );

      final start = monitor.dispatch(
        RiskMonitorCommand.start(id: 'late-start'),
      );
      await Future<void>.delayed(Duration.zero);
      monitor.invalidateCredentials(reason: 'synthetic account switch');
      pending.complete(
        RiskPositionSelection(
          status: RiskEligibility.eligible,
          quality: const RiskQuality.complete(source: 'late'),
          position: syntheticRiskPosition(observedAt: clock.value),
        ),
      );
      await start;

      expect(persistence.saveEpisodeCalls, 0);
      expect(sink.delivered, isEmpty);
      expect(monitor.currentState.evaluation, isNull);
      expect(monitor.currentState.accountHash, isNull);
      await monitor.dispose();
    },
  );

  test(
    'RED-005 denied capability retains events and failed save cannot notify',
    () async {
      final clock = FakeRiskClock();
      var mark = 10.0;
      final source = FakeRiskSource(
        clock: clock,
        position: () =>
            syntheticRiskPosition(observedAt: clock.value, markPrice: mark),
      );
      final persistence = FakeRiskPersistence();
      final sink = FakeRiskNotificationSink()
        ..capabilityState = const RiskNotificationCapability(
          status: RiskNotificationCapabilityStatus.denied,
          reason: 'synthetic permission denial',
        );
      final monitor = RiskMonitor(
        dataSource: source,
        persistence: persistence,
        clock: clock.now,
        notificationSink: sink,
      );
      await monitor.dispatch(RiskMonitorCommand.start(id: 'denied-start'));
      mark = 8;
      clock.advance(const Duration(minutes: 1));
      await monitor.dispatch(RiskMonitorCommand.refresh(id: 'denied-refresh'));
      expect(monitor.currentState.events, isNotEmpty);
      expect(sink.delivered, isEmpty);

      final failingPersistence = FakeRiskPersistence();
      final failingSink = FakeRiskNotificationSink();
      final failingMonitor = RiskMonitor(
        dataSource: source,
        persistence: failingPersistence,
        clock: clock.now,
        notificationSink: failingSink,
      );
      await failingMonitor.dispatch(
        RiskMonitorCommand.start(id: 'failed-save-start'),
      );
      expect(failingPersistence.saveEpisodeCalls, greaterThan(0));
      failingPersistence.failEpisodeSaves = true;
      mark = 7;
      clock.advance(const Duration(minutes: 1));
      await failingMonitor.dispatch(
        RiskMonitorCommand.refresh(id: 'failed-save-refresh'),
      );
      expect(failingMonitor.currentState.unsaved, isTrue);
      expect(failingSink.delivered, isEmpty);
      expect(failingSink.deliverCalls, 0);
      await monitor.dispose();
      await failingMonitor.dispose();
    },
  );

  test(
    'GREEN-005 persists before one delivery and restart reuses the latch',
    () async {
      final clock = FakeRiskClock();
      var mark = 10.0;
      final source = FakeRiskSource(
        clock: clock,
        position: () =>
            syntheticRiskPosition(observedAt: clock.value, markPrice: mark),
      );
      final persistence = FakeRiskPersistence();
      final sink = FakeRiskNotificationSink();
      final monitor = RiskMonitor(
        dataSource: source,
        persistence: persistence,
        clock: clock.now,
        notificationSink: sink,
      );
      await monitor.dispatch(RiskMonitorCommand.start(id: 'green-start'));
      mark = 8;
      clock.advance(const Duration(minutes: 1));
      await monitor.dispatch(RiskMonitorCommand.refresh(id: 'green-worsen'));
      expect(persistence.saveEpisodeCalls, greaterThanOrEqualTo(2));
      expect(sink.delivered, hasLength(1));
      expect(sink.delivered.single.body, isNot(contains(RegExp(r'\d'))));
      expect(sink.delivered.single.body.toLowerCase(), isNot(contains('pnl')));

      final duplicate = await monitor.dispatch(
        RiskMonitorCommand.refresh(id: 'green-worsen'),
      );
      expect(duplicate.replayed, isTrue);
      expect(sink.delivered, hasLength(1));
      await monitor.dispose();

      final restartSink = FakeRiskNotificationSink();
      final restarted = RiskMonitor(
        dataSource: source,
        persistence: persistence,
        clock: clock.now,
        notificationSink: restartSink,
      );
      clock.advance(const Duration(minutes: 1));
      await restarted.dispatch(RiskMonitorCommand.start(id: 'restart-start'));
      expect(restartSink.delivered, isEmpty);

      mark = 10;
      clock.advance(const Duration(seconds: 31));
      await restarted.dispatch(
        RiskMonitorCommand.refresh(id: 'green-improve-1'),
      );
      clock.advance(const Duration(seconds: 31));
      await restarted.dispatch(
        RiskMonitorCommand.refresh(id: 'green-improve-2'),
      );
      expect(restartSink.delivered, hasLength(1));
      await restarted.dispose();
    },
  );

  test(
    'GREEN-005 repository preserves 401, 429 Retry-After, network retry and recovery',
    () async {
      final clock = FakeRiskClock();
      final adapter = FakeRiskHttpAdapter()..failureStatus = 401;
      final repository = RiskRepository(
        Dio(BaseOptions(baseUrl: 'https://synthetic.invalid'))
          ..httpClientAdapter = adapter,
        environment: 'synthetic',
        clock: clock.now,
      );
      final source = RepositoryBackedMonitorSource(repository, clock);
      final monitor = RiskMonitor(
        dataSource: source,
        persistence: FakeRiskPersistence(),
        clock: clock.now,
      );
      await monitor.dispatch(RiskMonitorCommand.start(id: 'repo-auth-start'));
      final authCalls = adapter.calls;
      expect(monitor.currentState.lastError, contains('Credentials'));
      await monitor.dispatch(
        RiskMonitorCommand.refresh(id: 'repo-auth-refresh'),
      );
      expect(adapter.calls, greaterThan(authCalls));

      monitor.invalidateCredentials(reason: 'synthetic credential rotation');
      adapter.failureStatus = 429;
      await monitor.dispatch(RiskMonitorCommand.start(id: 'repo-rate-start'));
      final rateCalls = adapter.calls;
      clock.advance(const Duration(seconds: 31));
      await monitor.dispatch(
        RiskMonitorCommand.refresh(id: 'repo-rate-too-soon'),
      );
      expect(adapter.calls, rateCalls);
      clock.advance(const Duration(seconds: 60));
      await monitor.dispatch(RiskMonitorCommand.refresh(id: 'repo-rate-ready'));
      expect(adapter.calls, greaterThan(rateCalls));

      monitor.invalidateCredentials(reason: 'synthetic network recovery');
      adapter.failureStatus = null;
      adapter.networkFailure = true;
      await monitor.dispatch(
        RiskMonitorCommand.start(id: 'repo-network-start'),
      );
      final networkCalls = adapter.calls;
      clock.advance(const Duration(seconds: 31));
      adapter.networkFailure = false;
      await monitor.dispatch(
        RiskMonitorCommand.refresh(id: 'repo-network-recovered'),
      );
      expect(adapter.calls, greaterThan(networkCalls));
      expect(monitor.currentState.accountHash, isNotNull);
      await monitor.dispose();
    },
  );

  test(
    'RED-005 R22-002 enrichment failures preserve HTTP and network metadata',
    () async {
      final clock = FakeRiskClock();
      final adapter = FakeRiskHttpAdapter()
        ..failureStatus = 429
        ..failurePath = RiskRepository.instrumentsEndpoint
        ..retryAfterValue = '180';
      final repository = RiskRepository(
        Dio(BaseOptions(baseUrl: 'https://synthetic.invalid'))
          ..httpClientAdapter = adapter,
        environment: 'synthetic',
        clock: clock.now,
      );
      final selection = await repository.loadPosition();
      expect(selection.position, isNotNull);
      expect(repository.lastSelectionFailure?.statusCode, 429);
      expect(repository.lastSelectionFailure?.credentialFailure, isFalse);
      expect(
        repository.lastSelectionFailure?.retryAfter,
        const Duration(seconds: 180),
      );

      final authAdapter = FakeRiskHttpAdapter()
        ..failureStatus = 401
        ..failurePath = RiskRepository.feeEndpoint;
      final authRepository = RiskRepository(
        Dio(BaseOptions(baseUrl: 'https://synthetic.invalid'))
          ..httpClientAdapter = authAdapter,
        environment: 'synthetic',
        clock: clock.now,
      );
      final authSource = RepositoryBackedMonitorSource(authRepository, clock);
      final authMonitor = RiskMonitor(
        dataSource: authSource,
        persistence: FakeRiskPersistence(),
        clock: clock.now,
      );
      await authMonitor.dispatch(
        RiskMonitorCommand.start(id: 'enrichment-401'),
      );
      expect(authRepository.lastSelectionFailure?.statusCode, 401);
      expect(authRepository.lastSelectionFailure?.credentialFailure, isTrue);
      expect(
        authMonitor.currentState.lastError,
        contains('Credentials were rejected during risk enrichment'),
      );
      final callsBeforeRetry = authAdapter.calls;
      authAdapter.failureStatus = null;
      await authMonitor.dispatch(
        RiskMonitorCommand.refresh(id: 'enrichment-401-retry'),
      );
      expect(authAdapter.calls, greaterThan(callsBeforeRetry));
      await authMonitor.dispose();

      final networkAdapter = FakeRiskHttpAdapter()
        ..networkFailure = true
        ..failurePath = RiskRepository.feeEndpoint;
      final networkRepository = RiskRepository(
        Dio(BaseOptions(baseUrl: 'https://synthetic.invalid'))
          ..httpClientAdapter = networkAdapter,
        environment: 'synthetic',
        clock: clock.now,
      );
      final networkSelection = await networkRepository.loadPosition();
      expect(networkSelection.position, isNotNull);
      expect(networkRepository.lastSelectionFailure?.statusCode, isNull);
      expect(
        networkRepository.lastSelectionFailure?.credentialFailure,
        isFalse,
      );
    },
  );

  test(
    'GREEN-005 R22-002 ledger cache reuses data across moving episode end',
    () async {
      final clock = FakeRiskClock();
      final adapter = FakeRiskHttpAdapter()
        ..interestRows = <Map<String, dynamic>>[
          <String, dynamic>{
            'instId': 'SUI-USDT',
            'ccy': 'USDT',
            'mgnMode': 'isolated',
            'interest': '1.25',
            'type': '2',
            'ts': '1789000200000',
          },
        ];
      final repository = RiskRepository(
        Dio(BaseOptions(baseUrl: 'https://synthetic.invalid'))
          ..httpClientAdapter = adapter,
        environment: 'synthetic',
        clock: clock.now,
      );
      final start = DateTime.utc(2026, 9, 1);
      final firstEnd = DateTime.utc(2026, 9, 10);
      final secondEnd = DateTime.utc(2026, 9, 10, 1);
      final first = await repository.getInterestLedger(
        instId: 'SUI-USDT',
        ccy: 'USDT',
        episodeStart: start,
        episodeEnd: firstEnd,
      );
      final second = await repository.getInterestLedger(
        instId: 'SUI-USDT',
        ccy: 'USDT',
        episodeStart: start,
        episodeEnd: secondEnd,
      );
      expect(first.requestedTo, firstEnd);
      expect(first.entries, isEmpty);
      expect(second.requestedTo, secondEnd);
      expect(second.entries, hasLength(1));
      expect(adapter.calls, 1);
    },
  );

  test(
    'GREEN-005 R22-002 parses delta and RFC HTTP-date Retry-After values',
    () async {
      final clock = FakeRiskClock(DateTime.utc(2026, 9, 10));
      final retryAfterValues = <String>[
        '90',
        'Fri, 11 Sep 2026 00:00:00 GMT',
        'Friday, 11-Sep-26 00:00:00 GMT',
        'Fri Sep 11 00:00:00 2026',
      ];
      for (final retryAfter in retryAfterValues) {
        final adapter = FakeRiskHttpAdapter()
          ..failureStatus = 429
          ..retryAfterValue = retryAfter;
        final repository = RiskRepository(
          Dio(BaseOptions(baseUrl: 'https://synthetic.invalid'))
            ..httpClientAdapter = adapter,
          clock: clock.now,
        );
        try {
          await repository.getPositions();
          fail('Expected synthetic rate-limit failure');
        } on RiskRepositoryException catch (error) {
          expect(error.statusCode, 429);
          expect(error.retryAfter, isNotNull);
          expect(
            error.retryAfter,
            greaterThanOrEqualTo(const Duration(seconds: 90)),
          );
        }
      }
    },
  );

  test(
    'RED-005 R22-002 cache generation fences a late account response',
    () async {
      final adapter = PendingRiskHttpAdapter();
      final repository = RiskRepository(
        Dio(BaseOptions(baseUrl: 'https://synthetic.invalid'))
          ..httpClientAdapter = adapter,
        clock: () => DateTime.utc(2026, 9, 10),
      );
      final pending = repository.getAccountConfig();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(adapter.calls, 1);
      repository.clearCaches();
      adapter.firstResponse.complete(
        ResponseBody.fromString(
          jsonEncode(_riskHttpPayload(RiskRepository.configEndpoint)),
          200,
          headers: <String, List<String>>{
            'content-type': <String>['application/json'],
          },
        ),
      );
      await pending;
      final second = repository.getAccountConfig();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      adapter.secondResponse.complete(
        ResponseBody.fromString(
          jsonEncode(_riskHttpPayload(RiskRepository.configEndpoint)),
          200,
          headers: <String, List<String>>{
            'content-type': <String>['application/json'],
          },
        ),
      );
      await second;
      expect(adapter.calls, 2);
    },
  );

  test(
    'GREEN-005 R22-002 stable repository cache expires at its bounded cadence',
    () async {
      final clock = FakeRiskClock();
      final adapter = FakeRiskHttpAdapter();
      final repository = RiskRepository(
        Dio(BaseOptions(baseUrl: 'https://synthetic.invalid'))
          ..httpClientAdapter = adapter,
        clock: clock.now,
      );
      await repository.getAccountConfig();
      await repository.getAccountConfig();
      expect(adapter.calls, 1);
      clock.advance(const Duration(hours: 1, seconds: 1));
      await repository.getAccountConfig();
      expect(adapter.calls, 2);
    },
  );

  test(
    'GREEN-005 15-minute history and five-minute OI persistence cadences are bounded',
    () async {
      final clock = FakeRiskClock();
      final source = FakeRiskSource(
        clock: clock,
        position: () => syntheticRiskPosition(observedAt: clock.value),
      );
      final persistence = FakeRiskPersistence();
      final monitor = RiskMonitor(
        dataSource: source,
        persistence: persistence,
        clock: clock.now,
      );
      await monitor.dispatch(RiskMonitorCommand.start(id: 'cadence-start'));
      final initialSaves = persistence.saveEpisodeCalls;
      for (var minute = 1; minute <= 4; minute++) {
        clock.advance(const Duration(minutes: 1));
        await monitor.dispatch(
          RiskMonitorCommand.refresh(id: 'cadence-minute-$minute'),
        );
      }
      expect(persistence.saveEpisodeCalls, initialSaves);
      final samplesBeforeQuarter =
          persistence.episodes.values.single.samples.length;
      clock.advance(const Duration(minutes: 11));
      await monitor.dispatch(RiskMonitorCommand.refresh(id: 'cadence-quarter'));
      final saved = persistence.episodes.values.single;
      expect(saved.samples.length, greaterThan(samplesBeforeQuarter));
      expect(saved.openInterest, isNotEmpty);
      expect(source.marketCalls, lessThanOrEqualTo(16));
      await monitor.dispatch(RiskMonitorCommand.stop(id: 'cadence-stop'));
      await monitor.dispose();
    },
  );

  test(
    'GREEN-005 R22-002 continuous polling separates one-minute market and five-minute candles',
    () async {
      final clock = FakeRiskClock();
      final source = CadencedFakeRiskSource(
        clock: clock,
        position: () => syntheticRiskPosition(observedAt: clock.value),
      );
      final persistence = FakeRiskPersistence();
      final monitor = RiskMonitor(
        dataSource: source,
        persistence: persistence,
        clock: clock.now,
        foregroundCadence: const Duration(minutes: 1),
        marketCadence: const Duration(minutes: 1),
        candleCadence: const Duration(minutes: 5),
      );

      await monitor.dispatch(
        RiskMonitorCommand.start(id: 'cadence-split-start'),
      );
      expect(source.candleCalls, 1);
      expect(source.marketOnlyCalls, 0);
      for (var minute = 1; minute <= 4; minute++) {
        clock.advance(const Duration(minutes: 1));
        await monitor.dispatch(
          RiskMonitorCommand.refresh(id: 'cadence-split-$minute'),
        );
      }
      expect(source.cadenceCalls, 5);
      expect(source.marketOnlyCalls, 4);
      expect(source.candleCalls, 1);

      clock.advance(const Duration(minutes: 1));
      await monitor.dispatch(
        RiskMonitorCommand.refresh(id: 'cadence-split-five'),
      );
      expect(source.marketOnlyCalls, 4);
      expect(source.candleCalls, 2);
      expect(
        persistence.episodes.values.single.openInterest.length,
        greaterThan(2),
      );
      await monitor.dispatch(RiskMonitorCommand.stop(id: 'cadence-split-stop'));
      await monitor.dispose();
    },
  );

  test(
    'GREEN-005 R22-002 OI flush keeps the latest accepted sample for event comparison after restart',
    () async {
      final clock = FakeRiskClock();
      var mark = 10.0;
      final source = FakeRiskSource(
        clock: clock,
        position: () =>
            syntheticRiskPosition(observedAt: clock.value, markPrice: mark),
      );
      final persistence = FakeRiskPersistence();
      final reducer = RecordingRiskEventReducer(clock: clock.now);
      final monitor = RiskMonitor(
        dataSource: source,
        persistence: persistence,
        eventReducer: reducer,
        clock: clock.now,
        foregroundCadence: const Duration(minutes: 1),
        marketCadence: const Duration(minutes: 1),
        historySampleCadence: const Duration(minutes: 15),
        oiPersistCadence: const Duration(minutes: 5),
      );

      await monitor.dispatch(RiskMonitorCommand.start(id: 'latest-start'));
      mark = 10.5;
      for (var minute = 1; minute <= 5; minute++) {
        clock.advance(const Duration(minutes: 1));
        await monitor.dispatch(
          RiskMonitorCommand.refresh(id: 'latest-minute-$minute'),
        );
      }
      final latestBeforeTransition = monitor.currentState.samples!.last;
      final durableBeforeTransition = persistence.episodes.values.single;
      expect(
        durableBeforeTransition.samples.last.observedAt,
        isNot(latestBeforeTransition.observedAt),
      );
      expect(durableBeforeTransition.openInterest, isNotEmpty);

      await monitor.dispose();
      clock.advance(const Duration(minutes: 1));
      final restarted = RiskMonitor(
        dataSource: source,
        persistence: persistence,
        eventReducer: reducer,
        clock: clock.now,
        foregroundCadence: const Duration(minutes: 1),
        marketCadence: const Duration(minutes: 1),
        historySampleCadence: const Duration(minutes: 15),
        oiPersistCadence: const Duration(minutes: 5),
      );
      await restarted.dispatch(
        RiskMonitorCommand.start(
          id: 'latest-restart',
          accountHash: 'account-a',
          episodeKey: durableBeforeTransition.episodeKey,
        ),
      );
      expect(
        reducer.previousSamples.last?.observedAt,
        latestBeforeTransition.observedAt,
      );
      expect(restarted.currentState.events, isEmpty);

      mark = 5;
      clock.advance(const Duration(minutes: 1));
      await restarted.dispatch(
        RiskMonitorCommand.refresh(id: 'latest-transition'),
      );
      expect(
        reducer.previousSamples.last?.observedAt,
        clock.value.subtract(const Duration(minutes: 1)),
      );
      expect(restarted.currentState.events, isNotEmpty);
      await restarted.dispose();
    },
  );

  test(
    'GREEN-005 R22-002 retryable failures use the complete capped 30 60 120 300 sequence',
    () async {
      final clock = FakeRiskClock();
      final source = BackoffRiskSource(clock);
      final monitor = RiskMonitor(
        dataSource: source,
        persistence: FakeRiskPersistence(),
        clock: clock.now,
      );

      await monitor.dispatch(RiskMonitorCommand.start(id: 'backoff-start'));
      expect(source.calls, 1);
      final delays = <Duration>[
        const Duration(seconds: 30),
        const Duration(minutes: 1),
        const Duration(minutes: 2),
        const Duration(minutes: 5),
      ];
      for (var index = 0; index < delays.length; index++) {
        final delay = delays[index];
        clock.advance(delay - const Duration(seconds: 1));
        await monitor.dispatch(
          RiskMonitorCommand.refresh(id: 'backoff-early-$index'),
        );
        expect(source.calls, index + 1);
        clock.advance(const Duration(seconds: 1));
        await monitor.dispatch(
          RiskMonitorCommand.refresh(id: 'backoff-ready-$index'),
        );
        expect(source.calls, index + 2);
      }
      await monitor.dispose();
    },
  );

  test(
    'GREEN-005 R22-002 passes prior and current plans and applies reconnect gap semantics',
    () async {
      final clock = FakeRiskClock();
      var mark = 10.0;
      final source = FakeRiskSource(
        clock: clock,
        position: () =>
            syntheticRiskPosition(observedAt: clock.value, markPrice: mark),
      );
      final reducer = RecordingRiskEventReducer(clock: clock.now);
      final monitor = RiskMonitor(
        dataSource: source,
        persistence: FakeRiskPersistence(),
        eventReducer: reducer,
        clock: clock.now,
        foregroundCadence: const Duration(minutes: 1),
        marketCadence: const Duration(minutes: 1),
      );

      await monitor.dispatch(RiskMonitorCommand.start(id: 'reconnect-start'));
      expect(reducer.currentPlans.last, isNotNull);
      expect(reducer.previousPlans.last, isNull);

      clock.advance(const Duration(minutes: 1));
      await monitor.dispatch(
        RiskMonitorCommand.reconnect(id: 'reconnect-short'),
      );
      expect(reducer.reconnectFlags.last, isFalse);
      expect(reducer.previousPlans.last, isNotNull);
      expect(reducer.currentPlans.last, isNotNull);

      mark = 5;
      clock.advance(const Duration(minutes: 10));
      await monitor.dispatch(
        RiskMonitorCommand.reconnect(id: 'reconnect-long-changed'),
      );
      expect(reducer.reconnectFlags.last, isTrue);
      expect(
        monitor.currentState.events.any(
          (event) => event.kind == RiskEventKind.reconnect,
        ),
        isTrue,
      );

      final eventsAfterChanged = monitor.currentState.events.length;
      clock.advance(const Duration(minutes: 10));
      await monitor.dispatch(
        RiskMonitorCommand.reconnect(id: 'reconnect-long-unchanged'),
      );
      expect(reducer.reconnectFlags.last, isTrue);
      expect(monitor.currentState.events.length, eventsAfterChanged);

      source.position = () =>
          syntheticRiskPosition(
            observedAt: clock.value,
            markPrice: mark,
          ).copyWith(
            quality: const RiskQuality.stale(
              reason: 'Synthetic stale reconnect',
            ),
          );
      clock.advance(const Duration(minutes: 10));
      await monitor.dispatch(
        RiskMonitorCommand.reconnect(id: 'reconnect-long-stale'),
      );
      expect(reducer.reconnectFlags.last, isTrue);
      expect(monitor.currentState.events.length, eventsAfterChanged);
      await monitor.dispose();
    },
  );

  test(
    'GREEN-005 deferred writes serialize plan, settings and history mutations',
    () async {
      final clock = FakeRiskClock();
      final source = FakeRiskSource(
        clock: clock,
        position: () => syntheticRiskPosition(observedAt: clock.value),
      );
      final persistence = FakeRiskPersistence();
      final monitor = RiskMonitor(
        dataSource: source,
        persistence: persistence,
        clock: clock.now,
      );
      await monitor.dispatch(RiskMonitorCommand.start(id: 'race-start'));
      final episode = syntheticRiskPosition(observedAt: clock.value).episodeKey;
      final plan = RiskPlan(episodeKey: episode);
      const settings = RiskSettings(summaryHour: 7, summaryMinute: 30);
      final futures = <Future<RiskMonitorCommandResult>>[
        monitor.dispatch(
          RiskMonitorCommand.updatePlan(id: 'race-plan', plan: plan),
        ),
        monitor.dispatch(
          RiskMonitorCommand.updateSettings(
            id: 'race-settings',
            settings: settings,
          ),
        ),
        monitor.dispatch(RiskMonitorCommand.clearHistory(id: 'race-clear')),
      ];
      final results = await Future.wait(futures);
      expect(
        results.every(
          (result) =>
              result.accepted ||
              result.status == RiskMonitorCommandStatus.failed,
        ),
        isTrue,
      );
      expect(persistence.operationOrder, isNotEmpty);
      expect(monitor.currentState.episodeKey, episode);
      await monitor.dispose();
    },
  );

  test(
    'GREEN-005 SharedPreferences restart reloads plan, settings, history and latches',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = await SharedPreferences.getInstance();
      final store = RiskLocalStore(
        storage: SharedPreferencesRiskStorage(preferences),
      );
      final clock = FakeRiskClock();
      final source = FakeRiskSource(
        clock: clock,
        position: () => syntheticRiskPosition(observedAt: clock.value),
      );
      final monitor = RiskMonitor(
        dataSource: source,
        persistence: RiskLocalStorePersistence(store),
        clock: clock.now,
      );
      await monitor.dispatch(RiskMonitorCommand.start(id: 'prefs-start'));
      final episode = syntheticRiskPosition(observedAt: clock.value).episodeKey;
      const settings = RiskSettings(summaryHour: 6, summaryMinute: 45);
      await monitor.dispatch(
        RiskMonitorCommand.updateSettings(
          id: 'prefs-settings',
          settings: settings,
        ),
      );
      final plan = RiskPlan(episodeKey: episode);
      await monitor.dispatch(
        RiskMonitorCommand.updatePlan(id: 'prefs-plan', plan: plan),
      );
      await monitor.dispatch(RiskMonitorCommand.stop(id: 'prefs-stop'));
      await monitor.dispose();

      final restarted = RiskMonitor(
        dataSource: source,
        persistence: RiskLocalStorePersistence(store),
        clock: clock.now,
      );
      final result = await restarted.dispatch(
        RiskMonitorCommand.start(
          id: 'prefs-restart',
          accountHash: 'account-a',
          episodeKey: episode,
        ),
      );
      expect(result.state.settings?.summaryHour, 6);
      expect(result.state.plan?.episodeKey, episode);
      expect(result.state.samples, isNotNull);
      await restarted.dispose();
    },
  );

  test(
    'GREEN-005 R22-002 populated dashboard state round-trips through service wire',
    () async {
      final clock = FakeRiskClock();
      var mark = 10.0;
      final source = FakeRiskSource(
        clock: clock,
        position: () =>
            syntheticRiskPosition(observedAt: clock.value, markPrice: mark),
      );
      final persistence = FakeRiskPersistence();
      final monitor = RiskMonitor(
        dataSource: source,
        persistence: persistence,
        clock: clock.now,
      );

      await monitor.dispatch(RiskMonitorCommand.start(id: 'codec-start'));
      final episode = monitor.currentState.episodeKey!;
      final rule = RiskRule(
        id: 'codec-rule',
        episodeKey: episode,
        metric: RiskPlanMetric.markPrice,
        comparison: RiskPlanComparison.lessThan,
        threshold: 11,
        title: 'Synthetic rule',
        createdAt: clock.value,
        updatedAt: clock.value,
      );
      await monitor.dispatch(
        RiskMonitorCommand.updatePlan(
          id: 'codec-plan',
          plan: RiskPlan(episodeKey: episode, rules: <RiskRule>[rule]),
        ),
      );
      await monitor.dispatch(
        RiskMonitorCommand.updateSettings(
          id: 'codec-settings',
          settings: const RiskSettings(
            summaryHour: 6,
            summaryMinute: 45,
            customStressPrices: <double>[8, 12],
          ),
        ),
      );
      mark = 8;
      clock.advance(const Duration(minutes: 1));
      await monitor.dispatch(RiskMonitorCommand.refresh(id: 'codec-refresh'));

      final original = monitor.currentState;
      expect(original.evaluation, isNotNull);
      expect(original.planEvaluation, isNotNull);
      expect(original.plan, isNotNull);
      expect(original.settings, isNotNull);
      expect(original.market, isNotNull);
      expect(original.samples, isNotEmpty);
      expect(original.events, isNotEmpty);
      expect(original.trend, isNotNull);
      expect(original.velocity, isNotNull);
      expect(original.notificationCapability, isNotNull);

      final decoded = RiskMonitorWire.decodeState(
        RiskMonitorWire.encodeState(original),
      );
      expect(decoded.isRunning, original.isRunning);
      expect(decoded.backgroundAvailable, original.backgroundAvailable);
      expect(decoded.ownerLabel, original.ownerLabel);
      expect(decoded.accountHash, original.accountHash);
      expect(decoded.episodeKey, original.episodeKey);
      expect(decoded.evaluation?.position.instrumentId, 'SUI-USDT');
      expect(decoded.evaluation?.metrics.markPrice.value, closeTo(8, 1e-12));
      expect(
        decoded.evaluation?.quality.status,
        original.evaluation?.quality.status,
      );
      expect(decoded.plan?.toJson(), original.plan?.toJson());
      expect(decoded.settings?.toJson(), original.settings?.toJson());
      expect(decoded.market?.assetInstrument, original.market?.assetInstrument);
      expect(decoded.market?.marketPoints, original.market?.marketPoints);
      expect(decoded.samples?.length, original.samples?.length);
      expect(decoded.summaries?.length, original.summaries?.length);
      expect(
        decoded.previousCheck?.baseline.observedAt,
        original.previousCheck?.baseline.observedAt,
      );
      expect(decoded.trend?.label, original.trend?.label);
      expect(decoded.velocity?.label, original.velocity?.label);
      expect(
        decoded.events.map((event) => event.id),
        original.events.map((event) => event.id),
      );
      expect(decoded.quality.status, original.quality.status);
      expect(decoded.notificationCapability, original.notificationCapability);
      await monitor.dispose();
    },
  );

  test('RED-002 aggregate multi-position monitor', () async {
    final clock = FakeRiskClock();
    final btc = syntheticRiskPosition(
      observedAt: clock.value,
      instrumentId: 'BTC-USDT',
      baseCurrency: 'BTC',
      positionId: 'position-btc',
    );
    final eth = syntheticRiskPosition(
      observedAt: clock.value,
      instrumentId: 'ETH-USDT',
      baseCurrency: 'ETH',
      positionId: 'position-eth',
    );
    final sui = syntheticRiskPosition(
      observedAt: clock.value,
      instrumentId: 'SUI-USDT',
      baseCurrency: 'SUI',
      positionId: 'position-sui',
    );
    final source = BatchFakeRiskSource(
      clock: clock,
      positions: <RiskPosition>[btc, eth, sui],
      failedMarketEpisodes: <String>{eth.episodeKey},
    );
    final monitor = RiskMonitor(
      dataSource: source,
      persistence: FakeRiskPersistence(),
      clock: clock.now,
      foregroundCadence: const Duration(minutes: 1),
      marketCadence: const Duration(minutes: 1),
    );

    await monitor.dispatch(RiskMonitorCommand.start(id: 'red-002-start'));
    final state = monitor.currentState;
    expect(source.batchCalls, 1);
    expect(state.positions, hasLength(3));
    expect(
      state.positions.map((entry) => entry.positionId),
      containsAll(<String>['position-btc', 'position-eth', 'position-sui']),
    );
    final failed = state.positions.singleWhere(
      (entry) => entry.positionId == 'position-eth',
    );
    expect(failed.lastError, contains('Market source'));
    expect(
      state.positions
          .where((entry) => entry.positionId != 'position-eth')
          .every((entry) => entry.evaluation != null),
      isTrue,
    );

    clock.advance(const Duration(minutes: 1));
    await monitor.dispatch(RiskMonitorCommand.refresh(id: 'red-002-refresh'));
    expect(source.batchCalls, 2);
    expect(monitor.currentState.positions, hasLength(3));
    expect(
      monitor.currentState.requestStatus,
      anyOf(RiskMonitorRequestStatus.partial, RiskMonitorRequestStatus.ready),
    );
    await monitor.dispose();
  });

  test('GREEN-002 aggregate multi-position monitor', () async {
    final clock = FakeRiskClock();
    RiskPosition position(String coin, String id, DateTime createdAt) =>
        syntheticRiskPosition(
          observedAt: clock.value,
          instrumentId: '$coin-USDT',
          baseCurrency: coin,
          positionId: id,
          createdAt: createdAt,
        );
    final btc = position('BTC', 'position-btc', DateTime.utc(2026, 9, 1));
    final eth = position('ETH', 'position-eth', DateTime.utc(2026, 9, 2));
    final sui = position('SUI', 'position-sui', DateTime.utc(2026, 9, 3));
    final source = BatchFakeRiskSource(
      clock: clock,
      positions: <RiskPosition>[btc, eth, sui],
    );
    final persistence = FakeRiskPersistence();
    final sink = FakeRiskNotificationSink();
    final monitor = RiskMonitor(
      dataSource: source,
      persistence: persistence,
      notificationSink: sink,
      clock: clock.now,
      foregroundCadence: const Duration(minutes: 1),
      marketCadence: const Duration(minutes: 1),
    );

    await monitor.dispatch(RiskMonitorCommand.start(id: 'green-002-start'));
    final initial = monitor.currentState;
    expect(initial.positions, hasLength(3));
    expect(
      initial.positions.map((entry) => entry.direction),
      everyElement('long'),
    );
    final decoded = RiskMonitorWire.decodeState(
      RiskMonitorWire.encodeState(initial),
    );
    expect(decoded.positions, hasLength(3));
    expect(
      decoded.positions.map((entry) => entry.episodeKey),
      orderedEquals(initial.positions.map((entry) => entry.episodeKey)),
    );
    expect(
      decoded.positions.map((entry) => entry.positionSide),
      orderedEquals(initial.positions.map((entry) => entry.positionSide)),
    );

    final oldSuiEpisode = sui.episodeKey;
    final suiPlan = RiskPlan(episodeKey: oldSuiEpisode);
    await monitor.dispatch(
      RiskMonitorCommand.updatePlan(
        id: 'green-002-plan-sui',
        episodeKey: oldSuiEpisode,
        plan: suiPlan,
      ),
    );
    final changedSui = syntheticRiskPosition(
      observedAt: clock.value,
      instrumentId: 'SUI-USDT',
      baseCurrency: 'SUI',
      positionId: 'position-sui',
      createdAt: DateTime.utc(2026, 9, 3),
      markPrice: 8,
    );
    source.positions = <RiskPosition>[btc, eth, changedSui];
    clock.advance(const Duration(minutes: 1));
    await monitor.dispatch(RiskMonitorCommand.refresh(id: 'green-002-change'));
    expect(sink.delivered, hasLength(1));
    expect(sink.delivered.single.episodeKey, oldSuiEpisode);
    expect(
      persistence.saveHistory
          .where((record) => record.episodeKey == oldSuiEpisode)
          .expand((record) => record.events)
          .every((event) => event.episodeKey == oldSuiEpisode),
      isTrue,
    );

    source.positions = <RiskPosition>[btc, eth];
    clock.advance(const Duration(minutes: 1));
    await monitor.dispatch(RiskMonitorCommand.refresh(id: 'green-002-close'));
    expect(monitor.currentState.positions, hasLength(2));
    final closed = persistence.episodes.values.singleWhere(
      (record) => record.episodeKey == oldSuiEpisode,
    );
    expect(closed.closedAt, isNotNull);
    expect(closed.events, isNotEmpty);

    final reopened = syntheticRiskPosition(
      observedAt: clock.value,
      instrumentId: 'SUI-USDT',
      baseCurrency: 'SUI',
      positionId: 'position-sui',
      createdAt: DateTime.utc(2026, 9, 10),
    );
    source.positions = <RiskPosition>[btc, eth, reopened];
    clock.advance(const Duration(minutes: 1));
    await monitor.dispatch(RiskMonitorCommand.refresh(id: 'green-002-reopen'));
    final reopenedRow = monitor.currentState.positions.singleWhere(
      (entry) => entry.positionId == 'position-sui',
    );
    expect(reopenedRow.episodeKey, isNot(oldSuiEpisode));
    expect(reopenedRow.plan?.episodeKey, reopened.episodeKey);
    expect(reopenedRow.events, isEmpty);
    expect(reopenedRow.samples, hasLength(1));
    expect(monitor.currentState.positions, hasLength(3));
    await monitor.dispose();
  });

  test(
    'GREEN-002 retries an unsaved episode plan on the next capture',
    () async {
      final clock = FakeRiskClock();
      final source = FakeRiskSource(
        clock: clock,
        position: () => syntheticRiskPosition(observedAt: clock.value),
      );
      final persistence = FakeRiskPersistence()..failEpisodeSaves = true;
      final monitor = RiskMonitor(
        dataSource: source,
        persistence: persistence,
        clock: clock.now,
      );

      await monitor.dispatch(
        RiskMonitorCommand.start(id: 'pending-plan-start'),
      );
      final episode = monitor.currentState.episodeKey!;
      final plan = RiskPlan(episodeKey: episode);
      final update = await monitor.dispatch(
        RiskMonitorCommand.updatePlan(id: 'pending-plan-update', plan: plan),
      );
      expect(update.status, RiskMonitorCommandStatus.failed);
      expect(monitor.currentState.unsaved, isTrue);

      persistence.failEpisodeSaves = false;
      clock.advance(const Duration(minutes: 1));
      await monitor.dispatch(
        RiskMonitorCommand.refresh(id: 'pending-plan-refresh'),
      );
      expect(
        persistence.episodes['account-a::$episode']?.plan.episodeKey,
        episode,
      );
      expect(monitor.currentState.unsaved, isFalse);
      await monitor.dispose();
    },
  );

  test(
    'AUD-T25-001 retries failed sample/event/OI state before closing an episode',
    () async {
      final clock = FakeRiskClock();
      final initial = syntheticRiskPosition(observedAt: clock.value);
      final changed = syntheticRiskPosition(
        observedAt: clock.value,
        markPrice: 8,
      );
      final other = syntheticRiskPosition(
        observedAt: clock.value,
        instrumentId: 'BTC-USDT',
        baseCurrency: 'BTC',
        positionId: 'position-btc',
        createdAt: DateTime.utc(2026, 9, 2),
      );
      final source = BatchFakeRiskSource(
        clock: clock,
        positions: <RiskPosition>[initial, other],
      );
      final persistence = FakeRiskPersistence()..failEpisodeSaves = true;
      final monitor = RiskMonitor(
        dataSource: source,
        persistence: persistence,
        clock: clock.now,
        foregroundCadence: const Duration(minutes: 1),
        marketCadence: const Duration(minutes: 1),
      );

      await monitor.dispatch(RiskMonitorCommand.start(id: 'audit-001-start'));
      final episode = initial.episodeKey;
      expect(other.episodeKey, isNot(episode));
      expect(persistence.episodes, isEmpty);
      expect(persistence.saveHistory, isNotEmpty);
      expect(
        persistence.saveHistory
            .lastWhere((record) => record.episodeKey == episode)
            .samples,
        isNotEmpty,
      );
      final pendingRule = RiskRule(
        id: 'sentinel-buffer-rule',
        episodeKey: episode,
        metric: RiskPlanMetric.markPrice,
        comparison: RiskPlanComparison.greaterThan,
        threshold: 9,
        title: 'Sentinel mark rule',
        note: 'must survive a failed write',
        createdAt: clock.value,
        updatedAt: clock.value,
      );
      final pendingZone = RiskZone(
        id: 'sentinel-zone',
        episodeKey: episode,
        title: 'Sentinel zone',
        lowerPrice: 7,
        upperPrice: 9,
        note: 'must survive a failed write',
        createdAt: clock.value,
        updatedAt: clock.value,
      );
      final pendingPlan = RiskPlan(
        episodeKey: episode,
        rules: <RiskRule>[pendingRule],
        zones: <RiskZone>[pendingZone],
      );
      final failedPlan = await monitor.dispatch(
        RiskMonitorCommand.updatePlan(
          id: 'audit-001-pending-plan',
          episodeKey: episode,
          plan: pendingPlan,
        ),
      );
      expect(failedPlan.status, RiskMonitorCommandStatus.failed);

      source.positions = <RiskPosition>[changed, other];
      clock.advance(const Duration(minutes: 1));
      await monitor.dispatch(
        RiskMonitorCommand.refresh(id: 'audit-001-failed-capture'),
      );

      // The changed-price capture must generate an event while the episode
      // write is still failing. The monitor keeps that exact event in its
      // pending record for a later capture to retry.
      final failedCapture = monitor.currentState.positions.firstWhere(
        (entry) => entry.episodeKey == episode,
      );
      expect(failedCapture.unsaved, isTrue);
      final preRetryEventIds = failedCapture.events
          .map((event) => event.id)
          .toList(growable: false);
      expect(preRetryEventIds, isNotEmpty);
      expect(preRetryEventIds.toSet(), hasLength(preRetryEventIds.length));
      final failedEventRecord = persistence.saveHistory.lastWhere(
        (record) => record.episodeKey == episode && record.events.isNotEmpty,
      );
      expect(
        failedEventRecord.events.map((event) => event.id),
        orderedEquals(preRetryEventIds),
      );

      persistence.failEpisodeSaves = false;
      clock.advance(const Duration(minutes: 1));
      await monitor.dispatch(RiskMonitorCommand.refresh(id: 'audit-001-retry'));

      final retried = persistence.episodes['account-a::$episode'];
      expect(retried, isNotNull);
      expect(retried!.samples.length, greaterThanOrEqualTo(2));
      final expectedOpenInterestTimes = <DateTime>[
        DateTime.utc(2026, 9, 10, 10),
        DateTime.utc(2026, 9, 10, 10, 1),
        DateTime.utc(2026, 9, 10, 10, 2),
        DateTime.utc(2026, 9, 10, 13, 59),
        DateTime.utc(2026, 9, 10, 14),
        DateTime.utc(2026, 9, 10, 14, 1),
      ];
      expect(
        retried.openInterest.map((sample) => sample.timestamp),
        orderedEquals(expectedOpenInterestTimes),
      );
      expect(
        retried.openInterest.map((sample) => sample.oiCcy),
        orderedEquals(<double>[100, 100, 100, 101, 101, 101]),
      );
      expect(
        retried.openInterest
            .map(
              (sample) =>
                  '${sample.instrument}|${sample.timestamp.toIso8601String()}',
            )
            .toSet(),
        hasLength(retried.openInterest.length),
      );
      expect(retried.events, isNotEmpty);
      expect(retried.plan.episodeKey, pendingPlan.episodeKey);
      expect(retried.plan.rules, hasLength(1));
      expect(retried.plan.rules.single.id, pendingRule.id);
      expect(retried.plan.rules.single.threshold, pendingRule.threshold);
      expect(retried.plan.rules.single.note, pendingRule.note);
      expect(retried.plan.zones, hasLength(1));
      expect(retried.plan.zones.single.id, pendingZone.id);
      expect(retried.plan.zones.single.lowerPrice, pendingZone.lowerPrice);
      expect(retried.plan.zones.single.upperPrice, pendingZone.upperPrice);
      final retriedEventIds = retried.events
          .map((event) => event.id)
          .toList(growable: false);
      expect(retriedEventIds, orderedEquals(preRetryEventIds));
      expect(retriedEventIds.toSet(), hasLength(preRetryEventIds.length));
      expect(
        retried.events.every((event) => event.episodeKey == episode),
        isTrue,
      );
      for (final record in persistence.saveHistory.where(
        (record) => record.episodeKey == episode && record.events.isNotEmpty,
      )) {
        expect(
          record.events.map((event) => event.id),
          orderedEquals(retriedEventIds),
        );
      }

      source.positions = <RiskPosition>[other];
      clock.advance(const Duration(minutes: 1));
      await monitor.dispatch(RiskMonitorCommand.refresh(id: 'audit-001-close'));

      final closed = persistence.episodes['account-a::$episode'];
      expect(closed, isNotNull);
      expect(closed!.closedAt, isNotNull);
      expect(closed.samples.length, greaterThanOrEqualTo(2));
      expect(
        closed.openInterest.map((sample) => sample.timestamp),
        orderedEquals(expectedOpenInterestTimes),
      );
      expect(
        closed.openInterest.map((sample) => sample.oiCcy),
        orderedEquals(<double>[100, 100, 100, 101, 101, 101]),
      );
      expect(
        closed.openInterest
            .map(
              (sample) =>
                  '${sample.instrument}|${sample.timestamp.toIso8601String()}',
            )
            .toSet(),
        hasLength(closed.openInterest.length),
      );
      expect(
        closed.plan.rules.map((rule) => rule.id),
        orderedEquals(<String>[pendingRule.id]),
      );
      expect(
        closed.plan.zones.map((zone) => zone.id),
        orderedEquals(<String>[pendingZone.id]),
      );
      expect(
        closed.events.map((event) => event.id),
        orderedEquals(retriedEventIds),
      );
      expect(
        closed.events.every((event) => event.episodeKey == episode),
        isTrue,
      );
      final otherRecord =
          persistence.episodes['account-a::${other.episodeKey}'];
      expect(otherRecord, isNotNull);
      expect(otherRecord!.closedAt, isNull);
      expect(otherRecord.events, isEmpty);
      expect(otherRecord.plan.rules, isEmpty);
      expect(otherRecord.plan.zones, isEmpty);
      expect(monitor.currentState.positions, hasLength(1));
      expect(
        monitor.currentState.positions.single.episodeKey,
        other.episodeKey,
      );
      await monitor.dispose();
    },
  );

  test(
    'AUD-T25-002 discovery failure preserves last-good aggregate rows',
    () async {
      final clock = FakeRiskClock();
      final btc = syntheticRiskPosition(
        observedAt: clock.value,
        instrumentId: 'BTC-USDT',
        baseCurrency: 'BTC',
        positionId: 'position-btc',
      );
      final eth = syntheticRiskPosition(
        observedAt: clock.value,
        instrumentId: 'ETH-USDT',
        baseCurrency: 'ETH',
        positionId: 'position-eth',
      );
      final source = BatchFakeRiskSource(
        clock: clock,
        positions: <RiskPosition>[btc, eth],
      );
      final monitor = RiskMonitor(
        dataSource: source,
        persistence: FakeRiskPersistence(),
        clock: clock.now,
        foregroundCadence: const Duration(minutes: 1),
        marketCadence: const Duration(minutes: 1),
      );

      await monitor.dispatch(RiskMonitorCommand.start(id: 'audit-002-start'));
      final lastGood = monitor.currentState.positions;
      expect(lastGood, hasLength(2));
      expect(lastGood.every((row) => row.evaluation != null), isTrue);
      source.batchOverride = const RiskPositionBatch(
        status: RiskEligibility.invalid,
        quality: RiskQuality.error(reason: 'synthetic discovery failure'),
        message: 'synthetic discovery failure',
      );
      clock.advance(const Duration(minutes: 1));
      await monitor.dispatch(
        RiskMonitorCommand.refresh(id: 'audit-002-failure'),
      );

      expect(source.batchCalls, 2);
      expect(
        monitor.currentState.positions.map((row) => row.positionId),
        orderedEquals(lastGood.map((row) => row.positionId)),
      );
      expect(
        monitor.currentState.positions.every((row) => row.evaluation != null),
        isTrue,
      );
      expect(
        monitor.currentState.requestStatus,
        isNot(RiskMonitorRequestStatus.unavailable),
      );
      expect(monitor.currentState.retryAt, isNotNull);
      await monitor.dispose();
    },
  );

  test(
    'AUD-T25-002 global 429 backoff blocks later requests and exposes retry metadata',
    () async {
      final clock = FakeRiskClock();
      final source = BatchFakeRiskSource(
        clock: clock,
        positions: <RiskPosition>[
          syntheticRiskPosition(
            observedAt: clock.value,
            positionId: 'position-btc',
            instrumentId: 'BTC-USDT',
            baseCurrency: 'BTC',
          ),
          syntheticRiskPosition(
            observedAt: clock.value,
            positionId: 'position-eth',
            instrumentId: 'ETH-USDT',
            baseCurrency: 'ETH',
          ),
        ],
        marketFailure: const RiskRepositoryException(
          'synthetic rate limit',
          statusCode: 429,
          retryAfter: Duration(minutes: 3),
          endpoint: 'market',
        ),
      );
      final monitor = RiskMonitor(
        dataSource: source,
        persistence: FakeRiskPersistence(),
        clock: clock.now,
        foregroundCadence: const Duration(minutes: 1),
        marketCadence: const Duration(minutes: 1),
      );

      await monitor.dispatch(
        RiskMonitorCommand.start(id: 'audit-002-429-start'),
      );
      expect(source.batchCalls, 1);
      expect(source.batchMarketCalls, 1);
      expect(
        monitor.currentState.requestStatus,
        RiskMonitorRequestStatus.backingOff,
      );
      expect(
        monitor.currentState.retryAt,
        clock.value.add(const Duration(minutes: 3)),
      );
      expect(monitor.currentState.requestEndpointClass, 'market');

      final beforeBatch = source.batchCalls;
      final beforeMarket = source.batchMarketCalls;
      clock.advance(const Duration(minutes: 1));
      await monitor.dispatch(
        RiskMonitorCommand.refresh(id: 'audit-002-429-blocked'),
      );
      expect(source.batchCalls, beforeBatch);
      expect(source.batchMarketCalls, beforeMarket);
      expect(monitor.currentState.retryAt, isNotNull);
      expect(monitor.currentState.requestEndpointClass, 'market');
      await monitor.dispose();
    },
  );

  test(
    'AUD-T25-002 coalesces concurrent manual refresh commands into one capture',
    () async {
      final clock = FakeRiskClock();
      final source = BatchFakeRiskSource(
        clock: clock,
        positions: <RiskPosition>[
          syntheticRiskPosition(observedAt: clock.value),
        ],
      );
      final monitor = RiskMonitor(
        dataSource: source,
        persistence: FakeRiskPersistence(),
        clock: clock.now,
        foregroundCadence: const Duration(minutes: 1),
        marketCadence: const Duration(minutes: 1),
      );

      await monitor.dispatch(
        RiskMonitorCommand.start(id: 'audit-002-coalesce-start'),
      );
      clock.advance(const Duration(minutes: 1));
      final first = monitor.dispatch(
        RiskMonitorCommand.refresh(id: 'audit-002-coalesce-one'),
      );
      final second = monitor.dispatch(
        RiskMonitorCommand.refresh(id: 'audit-002-coalesce-two'),
      );
      final results = await Future.wait(<Future<RiskMonitorCommandResult>>[
        first,
        second,
      ]);

      expect(source.batchCalls, 2);
      expect(results.first.accepted, isTrue);
      expect(results.last.accepted, isTrue);
      expect(results.last.replayed, isTrue);
      await monitor.dispose();
    },
  );

  test(
    'AUD-T25-002 expired backoff recovery clears metadata and resets the retry sequence',
    () async {
      final clock = FakeRiskClock();
      final source = BatchFakeRiskSource(
        clock: clock,
        positions: <RiskPosition>[
          syntheticRiskPosition(observedAt: clock.value),
        ],
        marketFailure: const RiskRepositoryException(
          'synthetic first rate limit',
          statusCode: 429,
          retryAfter: Duration(minutes: 2),
          endpoint: 'market',
        ),
      );
      final monitor = RiskMonitor(
        dataSource: source,
        persistence: FakeRiskPersistence(),
        clock: clock.now,
        foregroundCadence: const Duration(minutes: 1),
        marketCadence: const Duration(minutes: 1),
      );

      await monitor.dispatch(
        RiskMonitorCommand.start(id: 'audit-002-recovery-start'),
      );
      expect(
        monitor.currentState.retryAt,
        clock.value.add(const Duration(minutes: 2)),
      );
      expect(monitor.currentState.requestEndpointClass, 'market');

      clock.advance(const Duration(minutes: 1, seconds: 59));
      final beforeExpiryBatch = source.batchCalls;
      await monitor.dispatch(
        RiskMonitorCommand.refresh(id: 'audit-002-recovery-blocked'),
      );
      expect(source.batchCalls, beforeExpiryBatch);
      expect(monitor.currentState.requestEndpointClass, 'market');

      source.marketFailure = null;
      clock.advance(const Duration(seconds: 1));
      await monitor.dispatch(
        RiskMonitorCommand.refresh(id: 'audit-002-recovery-success'),
      );
      expect(
        monitor.currentState.requestStatus,
        RiskMonitorRequestStatus.ready,
      );
      expect(monitor.currentState.retryAt, isNull);
      expect(monitor.currentState.requestEndpointClass, isNull);

      source.marketFailure = const RiskRepositoryException(
        'synthetic second rate limit',
        statusCode: 429,
        endpoint: 'market',
      );
      clock.advance(const Duration(minutes: 1));
      await monitor.dispatch(
        RiskMonitorCommand.refresh(id: 'audit-002-recovery-restart'),
      );
      expect(
        monitor.currentState.retryAt,
        clock.value.add(const Duration(seconds: 30)),
      );
      expect(monitor.currentState.requestEndpointClass, 'market');
      await monitor.dispose();
    },
  );

  test(
    'AUD-T25-003 aggregate codec preserves every populated per-position field',
    () async {
      final clock = FakeRiskClock();
      final source = BatchFakeRiskSource(
        clock: clock,
        positions: <RiskPosition>[
          syntheticRiskPosition(observedAt: clock.value),
        ],
      );
      final monitor = RiskMonitor(
        dataSource: source,
        persistence: FakeRiskPersistence(),
        clock: clock.now,
        foregroundCadence: const Duration(minutes: 1),
        marketCadence: const Duration(minutes: 1),
      );
      await monitor.dispatch(RiskMonitorCommand.start(id: 'audit-003-start'));
      source.positions = <RiskPosition>[
        syntheticRiskPosition(observedAt: clock.value, markPrice: 8),
      ];
      clock.advance(const Duration(minutes: 1));
      await monitor.dispatch(
        RiskMonitorCommand.refresh(id: 'audit-003-refresh'),
      );

      final original = monitor.currentState.positions.single;
      expect(original.position, isNotNull);
      expect(original.evaluation, isNotNull);
      expect(original.planEvaluation, isNotNull);
      expect(original.plan, isNotNull);
      expect(original.settings, isNotNull);
      expect(original.market, isNotNull);
      expect(original.samples.length, greaterThanOrEqualTo(2));
      expect(original.trend, isNotNull);
      expect(original.velocity, isNotNull);
      expect(original.events, isNotEmpty);

      final comparison = RiskSessionComparison(
        baseline: original.samples.first,
        current: original.samples.last,
        bufferDeltaPoints: 1.25,
        leverageDelta: 0.5,
        debtDelta: 2,
        trueExitChanged: true,
        structureChanged: true,
        fundingChanged: true,
        openInterestChanged: true,
        overallChanged: true,
        positionChanged: true,
      );
      final sample = original.samples.last;
      final rule = RiskRule(
        id: 'codec-buffer-rule',
        episodeKey: original.episodeKey,
        metric: RiskPlanMetric.buffer,
        comparison: RiskPlanComparison.lessThan,
        threshold: 0.25,
        title: 'Codec buffer rule',
        createdAt: clock.value,
        updatedAt: clock.value,
      );
      final configuredPlan = RiskPlan(
        episodeKey: original.episodeKey,
        rules: <RiskRule>[rule],
      );
      final configuredPlanEvaluation = RiskPlanEvaluation(
        rules: <RiskRuleEvaluation>[
          RiskRuleEvaluation(
            rule: rule,
            state: RiskRuleState.active,
            value: 0.1,
            referenceValue: 0.25,
            reason: 'synthetic plan evaluation',
          ),
        ],
        evaluatedAt: clock.value,
      );
      final configuredSettings = original.settings!.copyWith(
        customStressChanges: const <double>[-0.1, 0.1],
        customStressPrices: const <double>[8],
        summaryHour: 7,
        summaryMinute: 30,
      );
      final summary = RiskDailySummary(
        episodeKey: original.episodeKey,
        dateKey: '2026-09-10',
        timeZone: 'UTC',
        capturedAt: clock.value,
        quality: original.quality,
        overallState: sample.overallState,
        positionState: sample.positionState,
        marketState: sample.marketState,
        recoveryState: sample.recoveryState,
        buffer: sample.buffer,
        effectiveLeverage: sample.effectiveLeverage,
        actualInterestToday: sample.actualInterestToday,
        knownInterestToday: sample.knownInterestToday,
        actualInterestQuality: sample.actualInterestQuality,
        interestCoverageComplete: sample.interestCoverageComplete,
        majorChange: 'synthetic codec change',
        activeRuleCount: 2,
        unknownRuleCount: 1,
      );
      final populated = original.copyWith(
        plan: configuredPlan,
        planEvaluation: configuredPlanEvaluation,
        settings: configuredSettings,
        summaries: <RiskDailySummary>[summary],
        previousCheck: comparison,
        unsaved: true,
        lastError: 'synthetic per-position error',
        freshnessAt: clock.value,
      );
      final state = monitor.currentState.copyWith(
        episodeKey: populated.episodeKey,
        settings: configuredSettings,
        positions: <RiskPositionMonitorViewState>[populated],
      );
      final decoded = RiskMonitorWire.decodeState(
        RiskMonitorWire.encodeState(state),
      );
      final roundTrip = decoded.positions.single;

      expect(roundTrip.positionId, populated.positionId);
      expect(roundTrip.episodeKey, populated.episodeKey);
      expect(roundTrip.direction, populated.direction);
      expect(
        roundTrip.position?.instrumentId,
        populated.position?.instrumentId,
      );
      expect(
        roundTrip.evaluation?.metrics.markPrice.value,
        populated.evaluation?.metrics.markPrice.value,
      );
      expect(
        roundTrip.planEvaluation?.rules.length,
        populated.planEvaluation?.rules.length,
      );
      expect(roundTrip.planEvaluation?.rules.single.rule.id, rule.id);
      expect(
        roundTrip.planEvaluation?.rules.single.reason,
        'synthetic plan evaluation',
      );
      expect(roundTrip.plan?.episodeKey, populated.plan?.episodeKey);
      expect(roundTrip.plan?.rules.single.title, rule.title);
      expect(roundTrip.settings?.summaryHour, populated.settings?.summaryHour);
      expect(
        roundTrip.settings?.customStressChanges,
        configuredSettings.customStressChanges,
      );
      expect(
        roundTrip.market?.assetInstrument,
        populated.market?.assetInstrument,
      );
      expect(
        roundTrip.market?.openInterestLabel,
        populated.market?.openInterestLabel,
      );
      expect(roundTrip.samples.length, populated.samples.length);
      expect(
        roundTrip.samples.map((item) => item.observedAt),
        orderedEquals(populated.samples.map((item) => item.observedAt)),
      );
      expect(roundTrip.summaries.length, 1);
      expect(roundTrip.summaries.single.dateKey, summary.dateKey);
      expect(roundTrip.summaries.single.majorChange, summary.majorChange);
      expect(
        roundTrip.previousCheck?.baseline.observedAt,
        populated.previousCheck?.baseline.observedAt,
      );
      expect(
        roundTrip.previousCheck?.current.observedAt,
        populated.previousCheck?.current.observedAt,
      );
      expect(roundTrip.previousCheck?.bufferDeltaPoints, 1.25);
      expect(roundTrip.previousCheck?.leverageDelta, 0.5);
      expect(roundTrip.previousCheck?.debtDelta, 2);
      expect(roundTrip.previousCheck?.openInterestChanged, isTrue);
      expect(roundTrip.trend?.label, populated.trend?.label);
      expect(
        roundTrip.trend?.bufferDeltaPoints,
        populated.trend?.bufferDeltaPoints,
      );
      expect(roundTrip.velocity?.label, populated.velocity?.label);
      expect(
        roundTrip.velocity?.pointsPerHour,
        populated.velocity?.pointsPerHour,
      );
      expect(
        roundTrip.events.map((event) => event.id),
        orderedEquals(populated.events.map((event) => event.id)),
      );
      expect(roundTrip.quality.status, populated.quality.status);
      expect(roundTrip.quality.reason, populated.quality.reason);
      expect(roundTrip.unsaved, isTrue);
      expect(roundTrip.lastError, populated.lastError);
      expect(roundTrip.freshnessAt, populated.freshnessAt);
      await monitor.dispose();
    },
  );
}
