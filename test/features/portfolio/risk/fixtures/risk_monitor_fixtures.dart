import 'package:trading_balance_f/features/portfolio/application/risk_monitor.dart';
import 'package:trading_balance_f/features/portfolio/application/risk_notification_sink.dart';
import 'package:trading_balance_f/features/portfolio/data/risk/risk_local_store.dart';
import 'package:trading_balance_f/features/portfolio/data/risk/risk_repository.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/action_plan.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/market_risk_engine.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_events.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_history.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_models.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_policy.dart';

class FakeRiskClock {
  FakeRiskClock([DateTime? initial])
    : value = initial ?? DateTime.utc(2026, 9, 10, 14);

  DateTime value;

  DateTime now() => value;

  void advance(Duration duration) {
    value = value.add(duration);
  }
}

class FakeRiskSource
    implements RiskMonitorDataSource, RiskMonitorCacheInvalidator {
  FakeRiskSource({required this.clock, required this.position, this.market});

  final FakeRiskClock clock;
  RiskPosition Function() position;
  MarketRiskSnapshot Function(DateTime now)? market;
  int positionCalls = 0;
  int marketCalls = 0;
  int clearCachesCalls = 0;
  Future<RiskPositionSelection>? pendingPosition;

  @override
  void clearCaches() {
    clearCachesCalls++;
  }

  @override
  Future<RiskPositionSelection> loadPosition({
    String? selectedPositionId,
    String? selectedEpisodeKey,
  }) {
    positionCalls++;
    final pending = pendingPosition;
    if (pending != null) {
      pendingPosition = null;
      return pending;
    }
    final value = position();
    return Future.value(
      RiskPositionSelection(
        status: RiskEligibility.eligible,
        quality: RiskQuality.complete(
          source: 'synthetic-position',
          observedAt: clock.value,
          sourceAt: clock.value,
        ),
        position: value,
      ),
    );
  }

  @override
  Future<MarketRiskSnapshot> loadMarket({
    required RiskPosition position,
    DateTime? now,
  }) async {
    marketCalls++;
    return (market ?? syntheticMarketSnapshot)(now ?? clock.value);
  }
}

/// T25 fixture for exercising the aggregate owner without touching the
/// repository's authenticated adapters. It exposes one batch per capture and
/// can fail only the selected episode's market request.
class BatchFakeRiskSource extends FakeRiskSource
    implements RiskMonitorBatchDataSource {
  BatchFakeRiskSource({
    required super.clock,
    required this.positions,
    super.market,
    this.failedMarketEpisodes = const <String>{},
    this.batchOverride,
    this.marketFailure,
  }) : super(position: () => positions.first);

  List<RiskPosition> positions;
  final Set<String> failedMarketEpisodes;
  RiskPositionBatch? batchOverride;
  RiskRepositoryException? marketFailure;
  int batchCalls = 0;
  int batchMarketCalls = 0;

  @override
  Future<RiskPositionBatch> loadPositionsBatch({
    int ledgerPageBudget = 2,
  }) async {
    batchCalls++;
    final override = batchOverride;
    if (override != null) return override;
    return RiskPositionBatch(
      status: RiskEligibility.eligible,
      quality: RiskQuality.complete(
        source: 'synthetic-position-batch',
        observedAt: clock.value,
        sourceAt: clock.value,
      ),
      positions: List<RiskPosition>.unmodifiable(positions),
    );
  }

  @override
  Future<MarketRiskSnapshot> loadMarket({
    required RiskPosition position,
    DateTime? now,
  }) async {
    batchMarketCalls++;
    final failure = marketFailure;
    if (failure != null) throw failure;
    if (failedMarketEpisodes.contains(position.episodeKey)) {
      throw StateError('synthetic market failure');
    }
    return super.loadMarket(position: position, now: now);
  }
}

class CadencedFakeRiskSource extends FakeRiskSource
    implements RiskMonitorMarketCadenceSource {
  CadencedFakeRiskSource({
    required super.clock,
    required super.position,
    super.market,
  });

  int cadenceCalls = 0;
  int candleCalls = 0;
  int marketOnlyCalls = 0;

  @override
  Future<MarketRiskSnapshot> loadMarketCadence({
    required RiskPosition position,
    required DateTime now,
    required bool includeCandles,
  }) async {
    cadenceCalls++;
    if (includeCandles) {
      candleCalls++;
    } else {
      marketOnlyCalls++;
    }
    return (market ?? syntheticMarketSnapshot)(now);
  }
}

class RecordingRiskEventReducer extends RiskEventReducer {
  RecordingRiskEventReducer({super.clock});

  final List<RiskHistorySample?> previousSamples = <RiskHistorySample?>[];
  final List<RiskPlanEvaluation?> previousPlans = <RiskPlanEvaluation?>[];
  final List<RiskPlanEvaluation?> currentPlans = <RiskPlanEvaluation?>[];
  final List<bool> reconnectFlags = <bool>[];

  @override
  RiskEventReduction reduce(
    RiskHistorySample? previous,
    RiskHistorySample current,
    RiskEventLatch latches,
    RiskPolicy policy, {
    RiskPlanEvaluation? previousPlan,
    RiskPlanEvaluation? currentPlan,
    DateTime? now,
    bool reconnected = false,
  }) {
    previousSamples.add(previous);
    previousPlans.add(previousPlan);
    currentPlans.add(currentPlan);
    reconnectFlags.add(reconnected);
    return super.reduce(
      previous,
      current,
      latches,
      policy,
      previousPlan: previousPlan,
      currentPlan: currentPlan,
      now: now,
      reconnected: reconnected,
    );
  }
}

class BackoffRiskSource
    implements RiskMonitorDataSource, RiskMonitorSelectionFailureMetadata {
  BackoffRiskSource(this.clock);

  final FakeRiskClock clock;
  int calls = 0;

  @override
  RiskRepositorySelectionFailure? lastSelectionFailure;

  @override
  Future<RiskPositionSelection> loadPosition({
    String? selectedPositionId,
    String? selectedEpisodeKey,
  }) async {
    calls++;
    lastSelectionFailure = const RiskRepositorySelectionFailure(
      statusCode: 500,
    );
    return const RiskPositionSelection(
      status: RiskEligibility.invalid,
      quality: RiskQuality.error(reason: 'Synthetic retryable source failure'),
      message: 'Synthetic retryable source failure',
    );
  }

  @override
  Future<MarketRiskSnapshot> loadMarket({
    required RiskPosition position,
    DateTime? now,
  }) => Future<MarketRiskSnapshot>.error(
    StateError('Backoff source has no market data'),
  );
}

class FakeRiskPersistence implements RiskMonitorPersistence {
  final Map<String, RiskSettings> settings = <String, RiskSettings>{};
  final Map<String, RiskEpisodeRecord> episodes = <String, RiskEpisodeRecord>{};
  int saveEpisodeCalls = 0;
  int saveSettingsCalls = 0;
  bool failEpisodeSaves = false;
  bool failSettingsSaves = false;
  final List<RiskEpisodeRecord> saveHistory = <RiskEpisodeRecord>[];
  final List<String> operationOrder = <String>[];

  String _key(String account, String episode) => '$account::$episode';

  @override
  Future<RiskStoreResult<RiskSettings>> loadSettings(String accountHash) async {
    final value = settings[accountHash];
    return value == null
        ? const RiskStoreResult(status: RiskStoreStatus.missing)
        : RiskStoreResult(status: RiskStoreStatus.loaded, value: value);
  }

  @override
  Future<RiskStoreResult<RiskEpisodeRecord>> loadEpisode({
    required String accountHash,
    required String episodeKey,
  }) async {
    final value = episodes[_key(accountHash, episodeKey)];
    return value == null
        ? const RiskStoreResult(status: RiskStoreStatus.missing)
        : RiskStoreResult(status: RiskStoreStatus.loaded, value: value);
  }

  @override
  Future<RiskStoreResult<RiskSettings>> saveSettings({
    required String accountHash,
    required RiskSettings settings,
  }) async {
    saveSettingsCalls++;
    operationOrder.add('settings');
    if (failSettingsSaves) {
      return const RiskStoreResult(status: RiskStoreStatus.failed);
    }
    this.settings[accountHash] = settings;
    return RiskStoreResult(status: RiskStoreStatus.saved, value: settings);
  }

  @override
  Future<RiskStoreResult<RiskEpisodeRecord>> saveEpisode({
    required String accountHash,
    required RiskEpisodeRecord record,
  }) async {
    saveEpisodeCalls++;
    operationOrder.add(
      'episode:${record.events.map((event) => event.id).join(',')}',
    );
    saveHistory.add(record);
    if (failEpisodeSaves) {
      return const RiskStoreResult(status: RiskStoreStatus.failed);
    }
    episodes[_key(accountHash, record.episodeKey)] = record;
    return RiskStoreResult(status: RiskStoreStatus.saved, value: record);
  }

  @override
  Future<RiskStoreResult<RiskEpisodeRecord>> clearEpisodeHistory({
    required String accountHash,
    required String episodeKey,
  }) async {
    final existing = episodes[_key(accountHash, episodeKey)];
    if (existing == null) {
      return const RiskStoreResult(status: RiskStoreStatus.missing);
    }
    final cleared = existing.copyWith(
      samples: const <RiskHistorySample>[],
      openInterest: const <MarketOpenInterestSample>[],
      events: const <RiskEvent>[],
      summaries: const <RiskDailySummary>[],
      latches: RiskEventLatch(episodeKey: episodeKey),
      clearLastCheckBaseline: true,
    );
    episodes[_key(accountHash, episodeKey)] = cleared;
    return RiskStoreResult(status: RiskStoreStatus.saved, value: cleared);
  }
}

class FakeRiskNotificationSink implements RiskNotificationSink {
  RiskNotificationCapability capabilityState =
      const RiskNotificationCapability.granted();
  final List<RiskNotification> delivered = <RiskNotification>[];
  bool failDelivery = false;
  int capabilityCalls = 0;
  int deliverCalls = 0;

  @override
  Future<RiskNotificationCapability> capability() async {
    capabilityCalls++;
    return capabilityState;
  }

  @override
  Future<RiskNotificationDelivery> deliver(
    RiskNotification notification,
  ) async {
    deliverCalls++;
    if (failDelivery) {
      return const RiskNotificationDelivery.failed(
        'synthetic delivery failure',
      );
    }
    delivered.add(notification);
    return const RiskNotificationDelivery.delivered();
  }
}

RiskPosition syntheticRiskPosition({
  required DateTime observedAt,
  double markPrice = 10,
  String account = 'account-a',
  String positionId = 'position-a',
  String instrumentId = 'SUI-USDT',
  String baseCurrency = 'SUI',
  String positionSide = 'long',
  DateTime? createdAt,
}) {
  return RiskPosition(
    instrumentId: instrumentId,
    instrumentType: 'MARGIN',
    mode: RiskAccountMode.newMode,
    collateralCurrency: RiskCollateralCurrency.quote,
    positionSide: positionSide,
    accountNamespace: account,
    positionId: positionId,
    createdAt: createdAt ?? DateTime.utc(2026, 9, 1),
    updatedAt: observedAt,
    observedAt: observedAt,
    baseCurrency: baseCurrency,
    quoteCurrency: 'USDT',
    positionCurrency: baseCurrency,
    accountCurrency: 'USDT',
    liabilityCurrency: 'USDT',
    rawQuantity: 10,
    quantity: 10,
    margin: 100,
    markPrice: markPrice,
    entryPrice: 10,
    liquidationPrice: 6,
    unrealizedPnl: 0,
    reportedLeverage: 2,
    marginRatio: 4,
    maintenanceRequirement: 10,
    reportedLiability: markPrice * 10,
    reportedInterest: 1,
    hourlyBorrowRate: 0.00001,
    entryFeeRate: 0.001,
    exitFeeRate: 0.001,
    costAttribution: RiskCostAttribution(
      settledInterest: 0,
      unbilledInterest: 0,
      additionalActualCosts: 0,
      actualInterestToday: RiskActualInterestToday(
        amount: 0,
        knownSubtotal: 0,
        windowStart: DateTime.utc(2026, 9, 10),
        windowEnd: observedAt,
        quality: RiskQuality.complete(
          source: 'synthetic-costs',
          observedAt: observedAt,
          sourceAt: observedAt,
        ),
        coverageComplete: true,
        observedAt: observedAt,
        sourceAt: observedAt,
        source: 'synthetic-costs',
      ),
      coverage: RiskCostCoverage.completeForPosition(
        positionOpenedAt: createdAt ?? DateTime.utc(2026, 9, 1),
        coverageFrom: createdAt ?? DateTime.utc(2026, 9, 1),
        coverageTo: observedAt,
        nonOverlapAt: observedAt,
      ),
      observedAt: observedAt,
      source: 'synthetic-costs',
    ),
    quality: RiskQuality.complete(
      source: 'synthetic-position',
      observedAt: observedAt,
      sourceAt: observedAt,
    ),
    source: 'synthetic-position',
  );
}

MarketRiskSnapshot syntheticMarketSnapshot(DateTime now) {
  MarketSourceInfo source(
    String instrument,
    String endpoint,
    DateTime sourceAt,
  ) => MarketSourceInfo(
    venue: 'synthetic',
    instrument: instrument,
    endpoint: endpoint,
    observedAt: now,
    sourceAt: sourceAt,
    quality: RiskQuality.complete(
      source: 'synthetic-market',
      observedAt: now,
      sourceAt: sourceAt,
    ),
  );

  MarketCandleSeries candles(String instrument, String interval, int count) {
    final step = interval == '1H' ? 1 : 4;
    final last = interval == '1H'
        ? now.subtract(const Duration(minutes: 1))
        : now.subtract(Duration(hours: step));
    final values = List<MarketCandle>.generate(count, (index) {
      final timestamp = last.subtract(
        Duration(hours: step * (count - 1 - index)),
      );
      final close = 10 + index * 0.01;
      return MarketCandle(
        timestamp: timestamp,
        open: close - 0.02,
        high: close + 0.05,
        low: close - 0.05,
        close: close,
        volume: 100 + index.toDouble(),
        interval: interval,
      );
    });
    return MarketCandleSeries(
      instrument: instrument,
      interval: interval,
      candles: values,
      source: source(instrument, '/synthetic/candles', values.last.timestamp),
      complete: true,
    );
  }

  const asset = 'SUI-USDT';
  const btc = 'BTC-USDT';
  const swap = 'SUI-USDT-SWAP';
  final fundingAt = now.subtract(const Duration(hours: 8));
  final openInterest = <MarketOpenInterestSample>[
    MarketOpenInterestSample(
      instrument: swap,
      timestamp: now.subtract(const Duration(hours: 4)),
      oiCcy: 100,
      source: source(swap, '/synthetic/open-interest', fundingAt),
    ),
    MarketOpenInterestSample(
      instrument: swap,
      timestamp: now.subtract(const Duration(minutes: 1)),
      oiCcy: 101,
      source: source(swap, '/synthetic/open-interest', now),
    ),
  ];
  return MarketRiskSnapshot(
    asset: 'SUI',
    assetOneHour: candles(asset, '1H', 32),
    assetFourHour: candles(asset, '4H', 101),
    btcOneHour: candles(btc, '1H', 32),
    btcFourHour: candles(btc, '4H', 101),
    funding: MarketFundingObservation(
      instrument: swap,
      rate: 0,
      fundingTime: fundingAt,
      nextFundingTime: now,
      source: source(swap, '/synthetic/funding', fundingAt),
    ),
    openInterest: openInterest,
    fundingQuality: RiskQuality.complete(
      source: 'synthetic-funding',
      observedAt: now,
      sourceAt: fundingAt,
    ),
    openInterestQuality: RiskQuality.complete(
      source: 'synthetic-open-interest',
      observedAt: now,
      sourceAt: now,
    ),
    observedAt: now,
  );
}
