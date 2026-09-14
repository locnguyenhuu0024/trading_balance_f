import 'package:trading_balance_f/features/portfolio/data/risk/risk_local_store.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/action_plan.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/market_risk_engine.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_events.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_engine.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_history.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_models.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_policy.dart';

final riskTestNow = DateTime.utc(2026, 9, 10, 14);

RiskQuality completeQuality([DateTime? at, String source = 'synthetic']) =>
    RiskQuality.complete(
      source: source,
      observedAt: at ?? riskTestNow,
      sourceAt: at ?? riskTestNow,
    );

RiskHistorySample riskSample({
  DateTime? at,
  String episode = 'episode-a',
  RiskSeverity state = RiskSeverity.normal,
  RiskQuality? quality,
  double buffer = 0.40,
  double leverage = 2,
  double debt = 100,
  double margin = 50,
  double quantity = 10,
  double? marginRatio = 4,
  double? markPrice = 10,
  double? trueExit,
  bool trueExitVerified = true,
  RiskSeverity? positionState,
  RiskSeverity? marketState,
  RiskSeverity? recoveryState,
  double? entryPrice = 10,
  double? entryFeeRate = 0.001,
  double? exitFeeRate = 0.001,
  double? actualInterestToday,
  double? knownInterestToday,
  RiskQuality? actualInterestQuality,
  bool interestCoverageComplete = false,
  String? structureLabel,
  String? fundingLabel,
  double? openInterestChange,
  String policyVersion = 'risk.v1',
  List<String> activeFactorIds = const <String>[],
  String? source = 'synthetic',
}) {
  final observedAt = at ?? riskTestNow;
  return RiskHistorySample(
    episodeKey: episode,
    observedAt: observedAt,
    quality: quality ?? completeQuality(observedAt, source ?? 'synthetic'),
    overallState: state,
    positionState: positionState,
    marketState: marketState,
    recoveryState: recoveryState,
    markPrice: markPrice,
    buffer: buffer,
    effectiveLeverage: leverage,
    debt: debt,
    marginRatio: marginRatio,
    trueExit: trueExit,
    trueExitVerified: trueExitVerified,
    entryPrice: entryPrice,
    entryFeeRate: entryFeeRate,
    exitFeeRate: exitFeeRate,
    actualInterestToday: actualInterestToday,
    knownInterestToday: knownInterestToday,
    actualInterestQuality: actualInterestQuality,
    interestCoverageComplete: interestCoverageComplete,
    quantity: quantity,
    margin: margin,
    assetStructureLabel: structureLabel,
    fundingLabel: fundingLabel,
    openInterestChange: openInterestChange,
    policyVersion: policyVersion,
    activeFactorIds: activeFactorIds,
    source: source,
  );
}

RiskRule riskRule({
  String id = 'rule-buffer',
  String episode = 'episode-a',
  RiskPlanMetric metric = RiskPlanMetric.buffer,
  RiskPlanComparison comparison = RiskPlanComparison.lessThan,
  double? threshold = 0.30,
  double? upperThreshold,
  bool enabled = true,
  String title = 'Buffer needs attention',
  DateTime? at,
}) {
  final created = at ?? riskTestNow;
  return RiskRule(
    id: id,
    episodeKey: episode,
    metric: metric,
    comparison: comparison,
    threshold: threshold,
    upperThreshold: upperThreshold,
    enabled: enabled,
    title: title,
    createdAt: created,
    updatedAt: created,
  );
}

RiskZone riskZone({
  String id = 'zone-a',
  String episode = 'episode-a',
  double lower = 9,
  double upper = 10,
  String title = 'Recovery zone',
  DateTime? at,
}) {
  final created = at ?? riskTestNow;
  return RiskZone(
    id: id,
    episodeKey: episode,
    title: title,
    lowerPrice: lower,
    upperPrice: upper,
    createdAt: created,
    updatedAt: created,
  );
}

RiskPlan riskPlan({
  String episode = 'episode-a',
  List<RiskRule> rules = const <RiskRule>[],
  List<RiskZone> zones = const <RiskZone>[],
}) => RiskPlan(episodeKey: episode, rules: rules, zones: zones);

RiskEvaluation riskEvaluation({
  double markPrice = 10,
  double? reportedLiability = 100,
  double? reportedInterest = 0,
  RiskQuality? quality,
  DateTime? at,
  bool verifiedCosts = true,
}) {
  final observedAt = at ?? riskTestNow;
  final position = RiskPosition(
    instrumentId: 'SUI-USDT',
    instrumentType: 'MARGIN',
    mode: RiskAccountMode.newMode,
    collateralCurrency: RiskCollateralCurrency.quote,
    positionSide: 'long',
    accountNamespace: 'fixture-account',
    positionId: 'fixture-position',
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: observedAt,
    observedAt: observedAt,
    baseCurrency: 'SUI',
    quoteCurrency: 'USDT',
    positionCurrency: 'SUI',
    accountCurrency: 'USDT',
    liabilityCurrency: 'USDT',
    rawQuantity: 10,
    quantity: 10,
    margin: 100,
    markPrice: markPrice,
    entryPrice: 10,
    liquidationPrice: 6,
    unrealizedPnl: 0,
    marginRatio: 4,
    maintenanceRequirement: 10,
    reportedLiability: reportedLiability,
    reportedInterest: reportedInterest,
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
        quality: completeQuality(observedAt, 'fixture-costs'),
        coverageComplete: true,
        observedAt: observedAt,
        sourceAt: observedAt,
        source: 'fixture-costs',
      ),
      coverage: verifiedCosts
          ? RiskCostCoverage.completeForPosition(
              positionOpenedAt: DateTime.utc(2026, 9, 1),
              coverageFrom: DateTime.utc(2026, 9, 1),
              coverageTo: observedAt,
              nonOverlapAt: observedAt,
            )
          : const RiskCostCoverage.unknown(),
      observedAt: observedAt,
      source: 'fixture-costs',
    ),
    quality: quality ?? completeQuality(observedAt),
    source: 'fixture-position',
  );
  return RiskEngine(clock: () => observedAt).evaluate(
    position,
    policy: const RiskPolicy(),
    market: const RiskMarketInput(
      state: RiskSeverity.normal,
      complete: true,
      dailyVolatility: 0.10,
    ),
    now: observedAt,
  );
}

MarketOpenInterestSample oiSample({
  required DateTime at,
  double value = 100,
  String instrument = 'SUI-USDT-SWAP',
  RiskQuality? quality,
}) {
  return MarketOpenInterestSample(
    instrument: instrument,
    timestamp: at,
    oiCcy: value,
    source: MarketSourceInfo(
      venue: 'OKX',
      instrument: instrument,
      endpoint: '/api/v5/public/open-interest',
      observedAt: at,
      sourceAt: at,
      quality: quality ?? completeQuality(at, 'OKX public OI'),
    ),
  );
}

RiskEpisodeRecord episodeRecord({
  String account = 'account-a',
  String episode = 'episode-a',
  RiskPlan? plan,
  DateTime? updatedAt,
  List<RiskHistorySample> samples = const <RiskHistorySample>[],
  List<MarketOpenInterestSample> openInterest =
      const <MarketOpenInterestSample>[],
  List<RiskEvent> events = const <RiskEvent>[],
  List<RiskDailySummary> summaries = const <RiskDailySummary>[],
  RiskEventLatch? latches,
  RiskHistorySample? baseline,
  DateTime? closedAt,
}) => RiskEpisodeRecord(
  accountHash: account,
  episodeKey: episode,
  plan: plan ?? riskPlan(episode: episode),
  updatedAt: updatedAt ?? riskTestNow,
  samples: samples,
  openInterest: openInterest,
  events: events,
  summaries: summaries,
  latches: latches ?? RiskEventLatch(episodeKey: episode),
  lastCheckBaseline: baseline,
  closedAt: closedAt,
);
