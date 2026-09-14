import 'dart:math' as math;

import 'risk_models.dart';

typedef MarketRiskClock = DateTime Function();

/// The public market source metadata is kept with each source series. It is
/// intentionally independent from authenticated position observations.
class MarketSourceInfo {
  const MarketSourceInfo({
    required this.venue,
    required this.instrument,
    required this.endpoint,
    this.observedAt,
    this.sourceAt,
    this.windowStart,
    this.windowEnd,
    this.quality = const RiskQuality.complete(),
  });

  final String venue;
  final String instrument;
  final String endpoint;
  final DateTime? observedAt;
  final DateTime? sourceAt;
  final DateTime? windowStart;
  final DateTime? windowEnd;
  final RiskQuality quality;

  String get label => '$venue $endpoint [$instrument]';
}

/// A source result keeps an unavailable/error outcome distinct from an empty
/// value so callers can disclose the exact market-data failure.
class MarketSourceResult<T> {
  const MarketSourceResult({required this.quality, this.value});

  final T? value;
  final RiskQuality quality;

  bool get hasValue => value != null && quality.isAvailable;
}

/// One confirmed OHLCV candle. [timestamp] is the exchange candle open time.
class MarketCandle {
  const MarketCandle({
    required this.timestamp,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    required this.interval,
    this.confirmed = true,
  });

  final DateTime timestamp;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;
  final String interval;
  final bool confirmed;

  bool get isValid =>
      open.isFinite &&
      high.isFinite &&
      low.isFinite &&
      close.isFinite &&
      volume.isFinite &&
      open > 0 &&
      high > 0 &&
      low > 0 &&
      close > 0 &&
      volume >= 0;
}

/// A source-tagged candle series returned by the public repository.
class MarketCandleSeries {
  const MarketCandleSeries({
    required this.instrument,
    required this.interval,
    required this.candles,
    required this.source,
    this.complete = true,
    this.missingReason,
  });

  factory MarketCandleSeries.unavailable({
    required String instrument,
    required String interval,
    required String endpoint,
    required String reason,
    DateTime? observedAt,
  }) {
    return MarketCandleSeries(
      instrument: instrument,
      interval: interval,
      candles: const <MarketCandle>[],
      source: MarketSourceInfo(
        venue: 'OKX',
        instrument: instrument,
        endpoint: endpoint,
        observedAt: observedAt,
        quality: RiskQuality.unavailable(reason: reason),
      ),
      complete: false,
      missingReason: reason,
    );
  }

  final String instrument;
  final String interval;
  final List<MarketCandle> candles;
  final MarketSourceInfo source;
  final bool complete;
  final String? missingReason;
}

/// Public funding observation for the matching USDT perpetual.
class MarketFundingObservation {
  const MarketFundingObservation({
    required this.instrument,
    required this.rate,
    required this.fundingTime,
    required this.nextFundingTime,
    required this.source,
  });

  final String instrument;
  final double? rate;
  final DateTime? fundingTime;
  final DateTime? nextFundingTime;
  final MarketSourceInfo source;

  double? get settlementIntervalHours {
    final from = fundingTime;
    final to = nextFundingTime;
    if (from == null || to == null || !to.isAfter(from)) return null;
    final hours = to.difference(from).inMilliseconds / 3600000;
    return hours.isFinite && hours > 0 ? hours : null;
  }

  double? get normalized8h {
    final value = rate;
    final hours = settlementIntervalHours;
    if (value == null || !value.isFinite || hours == null) return null;
    final normalized = value * 8 / hours;
    return normalized.isFinite ? normalized : null;
  }
}

/// One public open-interest sample. OI is kept in currency units so price
/// movement is measured separately from notional revaluation.
class MarketOpenInterestSample {
  const MarketOpenInterestSample({
    required this.instrument,
    required this.timestamp,
    required this.oiCcy,
    required this.source,
  });

  final String instrument;
  final DateTime timestamp;
  final double? oiCcy;
  final MarketSourceInfo source;
}

/// All public market observations needed for one asset. Funding and current OI
/// must use [derivativeInstrument], which is the asset-USDT-SWAP proxy;
/// historical OI samples may be injected from P03 persistence.
class MarketRiskSnapshot {
  const MarketRiskSnapshot({
    required this.asset,
    required this.assetOneHour,
    required this.assetFourHour,
    required this.btcOneHour,
    required this.btcFourHour,
    this.funding,
    this.openInterest = const <MarketOpenInterestSample>[],
    this.fundingQuality,
    this.openInterestQuality,
    this.observedAt,
  });

  final String asset;
  final MarketCandleSeries assetOneHour;
  final MarketCandleSeries assetFourHour;
  final MarketCandleSeries btcOneHour;
  final MarketCandleSeries btcFourHour;
  final MarketFundingObservation? funding;
  final List<MarketOpenInterestSample> openInterest;
  final RiskQuality? fundingQuality;
  final RiskQuality? openInterestQuality;
  final DateTime? observedAt;

  String get assetInstrument => '${asset.trim().toUpperCase()}-USDT';
  String get btcInstrument => 'BTC-USDT';
  String get derivativeInstrument => '${asset.trim().toUpperCase()}-USDT-SWAP';
}

typedef RiskMarketSnapshot = MarketRiskSnapshot;
typedef RiskMarketCandle = MarketCandle;
typedef RiskMarketCandleSeries = MarketCandleSeries;
typedef RiskMarketFunding = MarketFundingObservation;
typedef RiskMarketOpenInterestSample = MarketOpenInterestSample;

enum MarketRiskVolatility { low, normal, high }

extension MarketRiskVolatilityX on MarketRiskVolatility {
  String get label {
    switch (this) {
      case MarketRiskVolatility.low:
        return 'Low';
      case MarketRiskVolatility.normal:
        return 'Normal';
      case MarketRiskVolatility.high:
        return 'High';
    }
  }
}

enum MarketRiskStructure { breakdown, recovery, weak, bearish, stable, bullish }

extension MarketRiskStructureX on MarketRiskStructure {
  String get label {
    switch (this) {
      case MarketRiskStructure.breakdown:
        return 'Breakdown';
      case MarketRiskStructure.recovery:
        return 'Recovery';
      case MarketRiskStructure.weak:
        return 'Weak';
      case MarketRiskStructure.bearish:
        return 'Bearish';
      case MarketRiskStructure.stable:
        return 'Stable/Neutral';
      case MarketRiskStructure.bullish:
        return 'Bullish';
    }
  }

  bool get adverse =>
      this == MarketRiskStructure.breakdown ||
      this == MarketRiskStructure.weak ||
      this == MarketRiskStructure.bearish;

  int get points {
    switch (this) {
      case MarketRiskStructure.breakdown:
        return 2;
      case MarketRiskStructure.weak:
      case MarketRiskStructure.bearish:
        return 1;
      case MarketRiskStructure.recovery:
      case MarketRiskStructure.stable:
      case MarketRiskStructure.bullish:
        return 0;
    }
  }
}

enum MarketRiskVolumePressure { elevatedDown, elevatedUp, balanced }

extension MarketRiskVolumePressureX on MarketRiskVolumePressure {
  String get label {
    switch (this) {
      case MarketRiskVolumePressure.elevatedDown:
        return 'Elevated down-volume';
      case MarketRiskVolumePressure.elevatedUp:
        return 'Elevated up-volume';
      case MarketRiskVolumePressure.balanced:
        return 'Balanced';
    }
  }

  int get points => this == MarketRiskVolumePressure.elevatedDown ? 1 : 0;
}

enum MarketRiskFundingClass { negative, neutral, positive, strongPositive }

extension MarketRiskFundingClassX on MarketRiskFundingClass {
  String get label {
    switch (this) {
      case MarketRiskFundingClass.negative:
        return 'Negative';
      case MarketRiskFundingClass.neutral:
        return 'Neutral';
      case MarketRiskFundingClass.positive:
        return 'Positive';
      case MarketRiskFundingClass.strongPositive:
        return 'Strong positive';
    }
  }
}

enum MarketRiskOiQuadrant {
  priceUpOiUp,
  priceUpOiDown,
  priceDownOiDown,
  priceDownOiUp,
  mixed,
}

extension MarketRiskOiQuadrantX on MarketRiskOiQuadrant {
  String get label {
    switch (this) {
      case MarketRiskOiQuadrant.priceUpOiUp:
        return 'Price up / OI up — New leverage entering';
      case MarketRiskOiQuadrant.priceUpOiDown:
        return 'Price up / OI down — Possible covering';
      case MarketRiskOiQuadrant.priceDownOiDown:
        return 'Price down / OI down — Leverage flushed';
      case MarketRiskOiQuadrant.priceDownOiUp:
        return 'Price down / OI up — New positioning during decline';
      case MarketRiskOiQuadrant.mixed:
        return 'Mixed/limited change';
    }
  }

  int get points {
    switch (this) {
      case MarketRiskOiQuadrant.priceUpOiUp:
        return 1;
      case MarketRiskOiQuadrant.priceDownOiUp:
        return 2;
      case MarketRiskOiQuadrant.priceUpOiDown:
      case MarketRiskOiQuadrant.priceDownOiDown:
      case MarketRiskOiQuadrant.mixed:
        return 0;
    }
  }

  bool get oiRising =>
      this == MarketRiskOiQuadrant.priceUpOiUp ||
      this == MarketRiskOiQuadrant.priceDownOiUp;
}

/// The complete pure market result. [input] is directly consumable by the
/// existing [RiskEngine] for max-severity overall aggregation.
class MarketRiskEvaluation {
  const MarketRiskEvaluation({
    required this.input,
    required this.quality,
    required this.reasons,
    required this.missingReasons,
    this.volatility,
    this.assetStructure,
    this.btcStructure,
    this.volumePressure,
    this.fundingClass,
    this.openInterestQuadrant,
    this.normalizedFunding8h,
    this.fundingIntervalHours,
    this.openInterestChange,
    this.priceChange,
    this.fundingQuality,
    this.openInterestQuality,
    this.points = 0,
    this.assetPoints = 0,
    this.fundingPoints = 0,
    this.openInterestPoints = 0,
    this.evaluatedAt,
  });

  final RiskMarketInput input;
  final RiskQuality quality;
  final List<RiskReason> reasons;
  final List<String> missingReasons;
  final MarketRiskVolatility? volatility;
  final MarketRiskStructure? assetStructure;
  final MarketRiskStructure? btcStructure;
  final MarketRiskVolumePressure? volumePressure;
  final MarketRiskFundingClass? fundingClass;
  final MarketRiskOiQuadrant? openInterestQuadrant;
  final double? normalizedFunding8h;
  final double? fundingIntervalHours;
  final double? openInterestChange;
  final double? priceChange;
  final RiskQuality? fundingQuality;
  final RiskQuality? openInterestQuality;
  final int points;
  final int assetPoints;
  final int fundingPoints;
  final int openInterestPoints;
  final DateTime? evaluatedAt;

  RiskMarketInput get marketInput => input;
  RiskMarketInput get market => input;
  RiskSeverity? get state => input.state;
  bool get complete => input.complete;
  bool get partial => input.complete == false;
}

/// Pure market structure, volatility, funding and open-interest evaluator.
class MarketRiskEngine {
  const MarketRiskEngine({this.clock});

  final MarketRiskClock? clock;

  MarketRiskEvaluation evaluate(
    MarketRiskSnapshot snapshot, {
    bool isBtcPosition = false,
    DateTime? now,
  }) {
    final evaluatedAt = (now ?? clock?.call() ?? DateTime.now().toUtc())
        .toUtc();
    final missing = <String>[];
    final reasons = <RiskReason>[];
    final asset = snapshot.asset.trim().toUpperCase();
    final btcPosition = isBtcPosition || asset == 'BTC';
    final expectedAsset = '$asset-USDT';
    const expectedBtc = 'BTC-USDT';
    final expectedDerivative = '$asset-USDT-SWAP';

    final assetOneHour = _prepareSeries(
      snapshot.assetOneHour,
      expectedInterval: '1H',
      expectedInstrument: expectedAsset,
      now: evaluatedAt,
      name: 'Asset 1H candles',
      missing: missing,
    );
    final assetFourHour = _prepareSeries(
      snapshot.assetFourHour,
      expectedInterval: '4H',
      expectedInstrument: expectedAsset,
      now: evaluatedAt,
      name: 'Asset 4H candles',
      missing: missing,
    );
    final btcOneHour = btcPosition
        ? assetOneHour
        : _prepareSeries(
            snapshot.btcOneHour,
            expectedInterval: '1H',
            expectedInstrument: expectedBtc,
            now: evaluatedAt,
            name: 'BTC 1H candles',
            missing: missing,
          );
    final btcFourHour = btcPosition
        ? assetFourHour
        : _prepareSeries(
            snapshot.btcFourHour,
            expectedInterval: '4H',
            expectedInstrument: expectedBtc,
            now: evaluatedAt,
            name: 'BTC 4H candles',
            missing: missing,
          );

    final volatilityResult = _dailyVolatility(
      assetOneHour,
      evaluatedAt,
      missing,
    );
    if (volatilityResult.value != null) {
      reasons.add(
        RiskReason(
          factorId: 'market-volatility',
          message:
              'Asset 1H realized volatility is ${volatilityResult.value! * 100}% (${volatilityResult.label!.label})',
          severity: volatilityResult.label == MarketRiskVolatility.high
              ? RiskSeverity.watch
              : RiskSeverity.normal,
          observedValue: volatilityResult.value,
          threshold: '<3% Low / 3%-<6% Normal / >=6% High',
          unit: 'fraction/day',
          window: 'last 24 consecutive closed 1H log returns',
          observedAt: assetOneHour.candles.last.timestamp,
          source: assetOneHour.source.label,
          evidence: '25 confirmed closes; sample standard deviation',
        ),
      );
    }

    final assetStructureResult = _structure(
      assetFourHour,
      evaluatedAt,
      missing,
      name: 'Asset',
      btc: btcPosition,
    );
    if (assetStructureResult.value != null) {
      final structure = assetStructureResult.value!;
      reasons.add(
        RiskReason(
          factorId: 'asset-structure',
          message:
              '$asset 4H structure is ${structure.label} at ${assetFourHour.candles.last.close}',
          severity: structure.points >= 2
              ? RiskSeverity.high
              : structure.adverse
              ? RiskSeverity.watch
              : RiskSeverity.normal,
          observedValue: assetFourHour.candles.last.close,
          threshold:
              'support ${assetStructureResult.support}; resistance ${assetStructureResult.resistance}',
          unit: 'USDT',
          window: 'last 100 consecutive closed 4H candles',
          observedAt: assetFourHour.candles.last.timestamp,
          source: assetFourHour.source.label,
          evidence:
              'EMA20=${assetStructureResult.ema20}; EMA50=${assetStructureResult.ema50}',
        ),
      );
    }

    final btcStructureResult = btcPosition
        ? assetStructureResult
        : _structure(btcFourHour, evaluatedAt, missing, name: 'BTC', btc: true);
    if (!btcPosition && btcStructureResult.value != null) {
      final structure = btcStructureResult.value!;
      reasons.add(
        RiskReason(
          factorId: 'btc-structure',
          message: 'BTC 4H structure is ${structure.label}',
          severity: structure.adverse
              ? RiskSeverity.watch
              : RiskSeverity.normal,
          observedValue: btcFourHour.candles.last.close,
          threshold:
              'support ${btcStructureResult.support}; resistance ${btcStructureResult.resistance}',
          unit: 'USDT',
          window: 'last 100 consecutive closed 4H candles',
          observedAt: btcFourHour.candles.last.timestamp,
          source: btcFourHour.source.label,
          evidence:
              'EMA20=${btcStructureResult.ema20}; EMA50=${btcStructureResult.ema50}',
        ),
      );
    }
    if (assetStructureResult.value == MarketRiskStructure.recovery) {
      reasons.add(
        RiskReason(
          factorId: 'asset-structure-recovery',
          message:
              '$asset confirmed support recovery clears its breakdown factor',
          severity: RiskSeverity.normal,
          observedValue: assetFourHour.candles.last.close,
          threshold: 'prior support * 1.005',
          unit: 'USDT',
          window: 'prior and latest closed 4H candles',
          observedAt: assetFourHour.candles.last.timestamp,
          source: assetFourHour.source.label,
          evidence: 'prior support=${assetStructureResult.priorSupport}',
        ),
      );
    }

    final volumeResult = _volumePressure(assetFourHour, missing);
    if (volumeResult.value != null) {
      reasons.add(
        RiskReason(
          factorId: 'market-volume',
          message:
              '$asset latest 4H volume is ${volumeResult.ratio}x its prior-20 average (${volumeResult.value!.label})',
          severity: volumeResult.value == MarketRiskVolumePressure.elevatedDown
              ? RiskSeverity.watch
              : RiskSeverity.normal,
          observedValue: volumeResult.ratio,
          threshold: '>=1.5x with candle direction',
          unit: 'ratio',
          window: 'latest closed 4H candle vs prior 20',
          observedAt: assetFourHour.candles.last.timestamp,
          source: assetFourHour.source.label,
        ),
      );
    }

    final fundingSourceQuality =
        snapshot.fundingQuality ?? snapshot.funding?.source.quality;
    final openInterestSourceQuality =
        snapshot.openInterestQuality ??
        (snapshot.openInterest.isEmpty
            ? null
            : snapshot.openInterest.last.source.quality);
    final fundingResult = _funding(
      snapshot.funding,
      expectedDerivative,
      fundingSourceQuality,
      evaluatedAt,
      missing,
    );
    if (fundingResult.value != null) {
      reasons.add(
        RiskReason(
          factorId: 'market-funding',
          message:
              '$expectedDerivative funding is ${fundingResult.value!.label} after 8H normalization',
          severity: RiskSeverity.normal,
          observedValue: fundingResult.normalized,
          threshold: '|f8|<=0.01% neutral; >0.01% positive; >=0.05% strong',
          unit: 'fraction/8h',
          window:
              '${fundingResult.intervalHours}h settlement interval; funding ${fundingResult.fundingTime}',
          observedAt: fundingResult.fundingTime,
          source: fundingResult.source!.label,
          evidence: 'raw rate=${fundingResult.rate}',
        ),
      );
    }

    final oiResult = _openInterest(
      snapshot.openInterest,
      assetOneHour,
      expectedDerivative,
      openInterestSourceQuality,
      evaluatedAt,
      missing,
    );
    final effectiveOpenInterestQuality =
        oiResult.quality ??
        openInterestSourceQuality ??
        oiResult.source?.quality;
    if (oiResult.value != null) {
      reasons.add(
        RiskReason(
          factorId: 'market-open-interest',
          message: oiResult.value!.label,
          severity: oiResult.value!.points >= 2
              ? RiskSeverity.high
              : oiResult.value!.points == 1
              ? RiskSeverity.watch
              : RiskSeverity.normal,
          observedValue: oiResult.oiChange,
          threshold: 'price neutral +/-0.5%; OI neutral +/-2%',
          unit: 'fraction',
          window: 'current vs nearest sample at/before now-4h within 15m',
          observedAt: oiResult.observedAt,
          source: oiResult.source!.label,
          evidence: 'price change=${oiResult.priceChange}',
        ),
      );
    }

    final decline24h = _priceChangeOver24h(assetOneHour);
    if (fundingResult.value == MarketRiskFundingClass.negative &&
        decline24h != null &&
        decline24h <= -0.05) {
      reasons.add(
        RiskReason(
          factorId: 'negative-funding-explanation',
          message:
              'Negative funding after a >=5% 24H decline may indicate increasing short positioning',
          severity: RiskSeverity.normal,
          observedValue: decline24h,
          threshold: '24H price change <= -5%',
          unit: 'fraction/24h',
          window: 'last 25 consecutive closed 1H closes',
          observedAt: assetOneHour.candles.last.timestamp,
          source: assetOneHour.source.label,
          evidence: 'funding=${fundingResult.normalized}',
        ),
      );
    }

    final assetStructure = assetStructureResult.value;
    final btcStructure = btcStructureResult.value;
    final volatility = volatilityResult.label;
    final volume = volumeResult.value;
    final funding = fundingResult.value;
    final oi = oiResult.value;
    final assetPoints = assetStructure?.points ?? 0;
    final volatilityPoints = volatility == MarketRiskVolatility.high ? 1 : 0;
    final volumePoints = volume?.points ?? 0;
    final openInterestPoints = oi?.points ?? 0;
    var fundingPoints = 0;
    if (funding == MarketRiskFundingClass.strongPositive) {
      fundingPoints = 1;
    }
    if (funding == MarketRiskFundingClass.positive &&
        oiResult.oiRising &&
        (oiResult.priceChange ?? 0) <= 0.005) {
      fundingPoints = 1;
    }
    fundingPoints = math.min(fundingPoints, 1);
    if (fundingPoints > 0) {
      reasons.add(
        RiskReason(
          factorId: 'market-funding-contribution',
          message: funding == MarketRiskFundingClass.strongPositive
              ? 'Strong positive funding adds one crowded-market point'
              : 'Positive funding with rising OI and neutral/down price adds one crowded-long point',
          severity: RiskSeverity.watch,
          observedValue: fundingResult.normalized,
          threshold: 'funding contribution capped at 1 point',
          unit: 'point',
          window: 'current funding and 4h OI/price relationship',
          observedAt: fundingResult.fundingTime,
          source: fundingResult.source!.label,
        ),
      );
    }

    final rawPoints =
        assetPoints +
        volatilityPoints +
        volumePoints +
        openInterestPoints +
        fundingPoints;
    var state = _stateForPoints(rawPoints);
    var marketPoints = rawPoints;
    if (!btcPosition && btcStructure?.adverse == true) {
      state = _raiseMarketState(state);
      marketPoints++;
      reasons.add(
        RiskReason(
          factorId: 'btc-market-modifier',
          message: 'Adverse BTC structure raises the market state by one level',
          severity: RiskSeverity.watch,
          observedValue: 1,
          threshold: 'one level, capped at HIGH',
          unit: 'level',
          window: 'latest closed BTC 4H structure',
          observedAt: btcFourHour.candles.last.timestamp,
          source: btcFourHour.source.label,
        ),
      );
    }

    final structureComplete =
        assetStructureResult.complete &&
        (btcPosition || btcStructureResult.complete);
    final requiredComplete =
        structureComplete &&
        volatilityResult.complete &&
        fundingResult.complete &&
        oiResult.complete;
    // A missing required factor cannot be reported as an unqualified NORMAL
    // state. Keep an observed WATCH/HIGH lower bound when points support it.
    if (!requiredComplete && state == RiskSeverity.normal) state = null;

    final uniqueMissing = _uniqueStrings(missing);
    final sourceLabels = <String>{
      assetOneHour.source.label,
      assetFourHour.source.label,
      if (!btcPosition) btcFourHour.source.label,
      if (fundingResult.source != null) fundingResult.source!.label,
      if (oiResult.source != null) oiResult.source!.label,
      if (fundingSourceQuality?.source != null) fundingSourceQuality!.source!,
      if (effectiveOpenInterestQuality?.source != null)
        effectiveOpenInterestQuality!.source!,
    };
    final source = sourceLabels.where((value) => value.isNotEmpty).join('; ');
    final sourceAt = _latestDate(<DateTime?>[
      assetOneHour.source.sourceAt,
      assetFourHour.source.sourceAt,
      btcOneHour.source.sourceAt,
      btcFourHour.source.sourceAt,
      fundingResult.source?.sourceAt,
      oiResult.source?.sourceAt,
      fundingSourceQuality?.sourceAt,
      effectiveOpenInterestQuality?.sourceAt,
    ]);
    final observedAt =
        snapshot.observedAt ??
        _latestDate(<DateTime?>[
          assetOneHour.source.observedAt,
          assetFourHour.source.observedAt,
          btcOneHour.source.observedAt,
          btcFourHour.source.observedAt,
          fundingResult.source?.observedAt,
          oiResult.source?.observedAt,
          fundingSourceQuality?.observedAt,
          effectiveOpenInterestQuality?.observedAt,
        ]) ??
        evaluatedAt;
    final anyFactor =
        assetStructure != null ||
        volatility != null ||
        volume != null ||
        funding != null ||
        oi != null;
    final quality = requiredComplete && uniqueMissing.isEmpty
        ? RiskQuality.complete(
            source: source,
            observedAt: observedAt,
            sourceAt: sourceAt,
          )
        : anyFactor
        ? RiskQuality.partial(
            source: source,
            observedAt: observedAt,
            sourceAt: sourceAt,
            reason: uniqueMissing.join('; '),
          )
        : RiskQuality.unavailable(
            source: source,
            observedAt: observedAt,
            sourceAt: sourceAt,
            reason: uniqueMissing.join('; '),
          );
    final input = RiskMarketInput(
      state: state,
      complete: requiredComplete && uniqueMissing.isEmpty,
      dailyVolatility: volatilityResult.value,
      reasons: List.unmodifiable(reasons),
      missingReasons: List.unmodifiable(uniqueMissing),
      support: assetStructureResult.support,
      resistance: assetStructureResult.resistance,
      source: source,
      observedAt: observedAt,
      sourceAt: sourceAt,
      marketContextLabel: 'OKX perpetual context',
      assetInstrument: expectedAsset,
      btcInstrument: expectedBtc,
      derivativesInstrument: expectedDerivative,
      volatilityLabel: volatility?.label,
      assetStructureLabel: assetStructure?.label,
      btcStructureLabel: btcStructure?.label,
      volumePressureLabel: volume?.label,
      fundingLabel: funding?.label,
      openInterestLabel: oi?.label,
      normalizedFunding8h: fundingResult.normalized,
      fundingIntervalHours: fundingResult.intervalHours,
      openInterestChange: oiResult.oiChange,
      marketPriceChange: oiResult.priceChange,
      fundingQuality: fundingSourceQuality,
      openInterestQuality: effectiveOpenInterestQuality,
      marketPoints: marketPoints,
      assetPoints: assetPoints,
      fundingPoints: fundingPoints,
      openInterestPoints: openInterestPoints,
    );
    return MarketRiskEvaluation(
      input: input,
      quality: quality,
      reasons: List.unmodifiable(reasons),
      missingReasons: List.unmodifiable(uniqueMissing),
      volatility: volatility,
      assetStructure: assetStructure,
      btcStructure: btcStructure,
      volumePressure: volume,
      fundingClass: funding,
      openInterestQuadrant: oi,
      normalizedFunding8h: fundingResult.normalized,
      fundingIntervalHours: fundingResult.intervalHours,
      openInterestChange: oiResult.oiChange,
      priceChange: oiResult.priceChange,
      fundingQuality: fundingSourceQuality,
      openInterestQuality: effectiveOpenInterestQuality,
      points: marketPoints,
      assetPoints: assetPoints,
      fundingPoints: fundingPoints,
      openInterestPoints: openInterestPoints,
      evaluatedAt: evaluatedAt,
    );
  }

  RiskMarketInput evaluateInput(
    MarketRiskSnapshot snapshot, {
    bool isBtcPosition = false,
    DateTime? now,
  }) {
    return evaluate(snapshot, isBtcPosition: isBtcPosition, now: now).input;
  }

  _SeriesView _prepareSeries(
    MarketCandleSeries series, {
    required String expectedInterval,
    required String expectedInstrument,
    required DateTime now,
    required String name,
    required List<String> missing,
  }) {
    if (series.interval != expectedInterval) {
      missing.add('$name interval ${series.interval} is not $expectedInterval');
    }
    if (series.instrument.toUpperCase() != expectedInstrument.toUpperCase()) {
      missing.add(
        '$name instrument ${series.instrument} is not $expectedInstrument',
      );
    }
    if (!series.complete && series.missingReason != null) {
      missing.add(series.missingReason!);
    }
    final valid = series.candles
        .where(
          (candle) =>
              candle.confirmed &&
              candle.isValid &&
              !candle.timestamp.isAfter(now),
        )
        .toList(growable: false);
    final sorted = List<MarketCandle>.from(valid)
      ..sort((left, right) => left.timestamp.compareTo(right.timestamp));
    final unique = <MarketCandle>[];
    var duplicate = false;
    for (final candle in sorted) {
      if (unique.isNotEmpty && unique.last.timestamp == candle.timestamp) {
        duplicate = true;
        continue;
      }
      unique.add(candle);
    }
    if (duplicate) missing.add('$name has duplicate candle timestamps');
    if (valid.length != series.candles.length) {
      missing.add('$name has unconfirmed, malformed or future candles');
    }
    return _SeriesView(
      candles: List.unmodifiable(unique),
      complete:
          series.complete &&
          !duplicate &&
          valid.length == series.candles.length,
      source: series.source,
    );
  }

  _VolatilityResult _dailyVolatility(
    _SeriesView series,
    DateTime at,
    List<String> missing,
  ) {
    final window = _window(
      series,
      count: 25,
      interval: const Duration(hours: 1),
      name: 'Asset 1H volatility',
      missing: missing,
    );
    if (window == null) return const _VolatilityResult();
    final returns = <double>[];
    for (var index = 1; index < window.length; index++) {
      final previous = window[index - 1].close;
      final current = window[index].close;
      final value = math.log(current / previous);
      if (!value.isFinite) {
        missing.add('Asset 1H volatility has a nonpositive close');
        return const _VolatilityResult();
      }
      returns.add(value);
    }
    final mean = returns.reduce((left, right) => left + right) / returns.length;
    final variance =
        returns
            .map((value) => math.pow(value - mean, 2).toDouble())
            .reduce((left, right) => left + right) /
        (returns.length - 1);
    final daily = math.sqrt(variance) * math.sqrt(24);
    if (!daily.isFinite || daily <= 0) {
      missing.add('Asset 1H daily volatility is zero or unavailable');
      return const _VolatilityResult();
    }
    final label = daily < 0.03
        ? MarketRiskVolatility.low
        : daily < 0.06
        ? MarketRiskVolatility.normal
        : MarketRiskVolatility.high;
    return _VolatilityResult(
      value: daily,
      label: label,
      complete: series.complete,
    );
  }

  _StructureResult _structure(
    _SeriesView series,
    DateTime at,
    List<String> missing, {
    required String name,
    required bool btc,
  }) {
    final window = _window(
      series,
      count: 100,
      interval: const Duration(hours: 4),
      name: '$name 4H structure',
      missing: missing,
    );
    if (window == null) return const _StructureResult();
    final closes = window.map((candle) => candle.close).toList(growable: false);
    final ema20 = _ema(closes, 20);
    final ema50 = _ema(closes, 50);
    final latest = window.last;
    final prior = window.sublist(window.length - 21, window.length - 1);
    final support = _min(prior.map((candle) => candle.low));
    final resistance = _max(prior.map((candle) => candle.high));
    final priorCandle = window[window.length - 2];
    final priorWindow = window.sublist(window.length - 22, window.length - 2);
    final priorSupport = _min(priorWindow.map((candle) => candle.low));
    final recovery =
        priorCandle.close < priorSupport &&
        latest.close >= priorSupport * 1.005;
    final breakdown = latest.close < support * 0.995;
    final value = recovery
        ? MarketRiskStructure.recovery
        : breakdown
        ? MarketRiskStructure.breakdown
        : latest.close < ema20 && ema20 < ema50
        ? (btc ? MarketRiskStructure.weak : MarketRiskStructure.bearish)
        : latest.close > ema20 && ema20 > ema50
        ? MarketRiskStructure.bullish
        : MarketRiskStructure.stable;
    return _StructureResult(
      value: value,
      support: support,
      resistance: resistance,
      priorSupport: priorSupport,
      ema20: ema20,
      ema50: ema50,
      complete: series.complete,
    );
  }

  _VolumeResult _volumePressure(_SeriesView series, List<String> missing) {
    final window = _window(
      series,
      count: 21,
      interval: const Duration(hours: 4),
      name: 'Asset 4H volume',
      missing: missing,
    );
    if (window == null) return const _VolumeResult();
    final latest = window.last;
    final prior = window.sublist(0, window.length - 1);
    final mean =
        prior
            .map((candle) => candle.volume)
            .reduce((left, right) => left + right) /
        prior.length;
    if (!mean.isFinite || mean <= 0) {
      missing.add('Asset 4H volume mean is zero or unavailable');
      return const _VolumeResult();
    }
    final ratio = latest.volume / mean;
    if (!ratio.isFinite) {
      missing.add('Asset 4H volume ratio is unavailable');
      return const _VolumeResult();
    }
    final pressure = ratio >= 1.5 && latest.close < latest.open
        ? MarketRiskVolumePressure.elevatedDown
        : ratio >= 1.5 && latest.close > latest.open
        ? MarketRiskVolumePressure.elevatedUp
        : MarketRiskVolumePressure.balanced;
    return _VolumeResult(
      value: pressure,
      ratio: ratio,
      complete: series.complete,
    );
  }

  _FundingResult _funding(
    MarketFundingObservation? observation,
    String expectedInstrument,
    RiskQuality? sourceQuality,
    DateTime at,
    List<String> missing,
  ) {
    if (observation == null) {
      missing.add(
        _qualityMissingReason(
          'Matching $expectedInstrument funding is unavailable',
          sourceQuality,
        ),
      );
      return const _FundingResult();
    }
    final quality = sourceQuality ?? observation.source.quality;
    if (!quality.isAvailable) {
      missing.add(
        _qualityMissingReason(
          'Matching $expectedInstrument funding is unavailable',
          quality,
        ),
      );
      return const _FundingResult();
    }
    if (observation.instrument.toUpperCase() != expectedInstrument) {
      missing.add(
        'Funding instrument ${observation.instrument} is not $expectedInstrument',
      );
      return const _FundingResult();
    }
    final normalized = observation.normalized8h;
    final interval = observation.settlementIntervalHours;
    if (normalized == null || interval == null) {
      missing.add(
        _qualityMissingReason(
          'Funding rate or settlement interval is unavailable',
          quality,
        ),
      );
      return const _FundingResult();
    }
    final value = normalized < -0.0001
        ? MarketRiskFundingClass.negative
        : normalized <= 0.0001
        ? MarketRiskFundingClass.neutral
        : normalized < 0.0005
        ? MarketRiskFundingClass.positive
        : MarketRiskFundingClass.strongPositive;
    return _FundingResult(
      value: value,
      normalized: normalized,
      intervalHours: interval,
      fundingTime: observation.fundingTime,
      rate: observation.rate,
      source: observation.source,
      complete: quality.status == RiskQualityStatus.complete,
    );
  }

  _OiResult _openInterest(
    List<MarketOpenInterestSample> samples,
    _SeriesView spotSeries,
    String expectedInstrument,
    RiskQuality? sourceQuality,
    DateTime now,
    List<String> missing,
  ) {
    if (sourceQuality != null && !sourceQuality.isAvailable) {
      missing.add(
        _qualityMissingReason(
          'Matching $expectedInstrument open-interest is unavailable',
          sourceQuality,
        ),
      );
      return const _OiResult();
    }
    final matching = samples
        .where(
          (sample) =>
              sample.instrument.toUpperCase() == expectedInstrument &&
              sample.timestamp.isBefore(
                now.add(const Duration(microseconds: 1)),
              ) &&
              sample.oiCcy != null &&
              sample.oiCcy!.isFinite &&
              sample.oiCcy! > 0,
        )
        .toList(growable: false);
    if (matching.isEmpty) {
      missing.add(
        _qualityMissingReason(
          'Matching $expectedInstrument open-interest history is unavailable',
          sourceQuality,
        ),
      );
      return const _OiResult();
    }
    for (var index = 1; index < matching.length; index++) {
      if (!matching[index].timestamp.isAfter(matching[index - 1].timestamp)) {
        missing.add(
          'Matching $expectedInstrument open-interest samples contain duplicate or out-of-order timestamps',
        );
        return const _OiResult();
      }
    }
    final current = matching.last;
    if (now.difference(current.timestamp) > const Duration(minutes: 5)) {
      final quality = sourceQuality ?? current.source.quality;
      final staleReason =
          'Current $expectedInstrument open-interest observation is stale';
      missing.add(staleReason);
      return _OiResult(
        observedAt: current.timestamp,
        source: current.source,
        quality: quality.withStatus(
          RiskQualityStatus.stale,
          nextReason: quality.reason == null || quality.reason!.isEmpty
              ? staleReason
              : '${quality.reason}; $staleReason',
        ),
      );
    }
    final target = now.subtract(const Duration(hours: 4));
    final historical = matching
        .where(
          (sample) =>
              !sample.timestamp.isAfter(target) &&
              target.difference(sample.timestamp) <=
                  const Duration(minutes: 15),
        )
        .toList(growable: false);
    if (historical.isEmpty) {
      missing.add(
        'Open-interest history needs a sample at or before now-4h within 15 minutes',
      );
      return const _OiResult();
    }
    final baseline = historical.last;
    final currentSpot = _nearestClose(spotSeries.candles, current.timestamp);
    final baselineSpot = _nearestClose(spotSeries.candles, baseline.timestamp);
    if (currentSpot == null || baselineSpot == null) {
      missing.add('Corresponding spot closes within 5 minutes are unavailable');
      return const _OiResult();
    }
    final oiChange = baseline.oiCcy == null || baseline.oiCcy! <= 0
        ? null
        : current.oiCcy! / baseline.oiCcy! - 1;
    final priceChange = baselineSpot <= 0
        ? null
        : currentSpot / baselineSpot - 1;
    if (oiChange == null ||
        priceChange == null ||
        !oiChange.isFinite ||
        !priceChange.isFinite) {
      missing.add('Open-interest or corresponding price change is unavailable');
      return const _OiResult();
    }
    final priceNeutral = priceChange >= -0.005 && priceChange <= 0.005;
    final oiNeutral = oiChange >= -0.02 && oiChange <= 0.02;
    final quadrant = priceNeutral || oiNeutral
        ? MarketRiskOiQuadrant.mixed
        : priceChange > 0 && oiChange > 0
        ? MarketRiskOiQuadrant.priceUpOiUp
        : priceChange > 0 && oiChange < 0
        ? MarketRiskOiQuadrant.priceUpOiDown
        : priceChange < 0 && oiChange < 0
        ? MarketRiskOiQuadrant.priceDownOiDown
        : MarketRiskOiQuadrant.priceDownOiUp;
    return _OiResult(
      value: quadrant,
      oiChange: oiChange,
      priceChange: priceChange,
      oiRising: oiChange > 0,
      observedAt: current.timestamp,
      source: current.source,
      complete:
          (sourceQuality ?? current.source.quality).status ==
              RiskQualityStatus.complete &&
          baseline.source.quality.status == RiskQualityStatus.complete,
    );
  }

  List<MarketCandle>? _window(
    _SeriesView series, {
    required int count,
    required Duration interval,
    required String name,
    required List<String> missing,
  }) {
    if (series.candles.length < count) {
      missing.add('$name needs $count confirmed candles');
      return null;
    }
    final window = series.candles.sublist(series.candles.length - count);
    for (var index = 1; index < window.length; index++) {
      if (window[index].timestamp.difference(window[index - 1].timestamp) !=
          interval) {
        missing.add('$name has a gap in its consecutive candle window');
        return null;
      }
    }
    return window;
  }

  double _ema(List<double> closes, int period) {
    final initial =
        closes.take(period).reduce((left, right) => left + right) / period;
    var value = initial;
    final alpha = 2 / (period + 1);
    for (var index = period; index < closes.length; index++) {
      value = alpha * closes[index] + (1 - alpha) * value;
    }
    return value;
  }

  double? _nearestClose(List<MarketCandle> candles, DateTime timestamp) {
    MarketCandle? nearest;
    var distance = const Duration(days: 36500);
    for (final candle in candles) {
      final candidateDistance = candle.timestamp.difference(timestamp).abs();
      if (candidateDistance < distance) {
        distance = candidateDistance;
        nearest = candle;
      }
    }
    return nearest != null && distance <= const Duration(minutes: 5)
        ? nearest.close
        : null;
  }

  double? _priceChangeOver24h(_SeriesView series) {
    if (series.candles.length < 25) return null;
    final window = series.candles.sublist(series.candles.length - 25);
    for (var index = 1; index < window.length; index++) {
      if (window[index].timestamp.difference(window[index - 1].timestamp) !=
          const Duration(hours: 1)) {
        return null;
      }
    }
    final first = window.first.close;
    final last = window.last.close;
    if (first <= 0 || !first.isFinite || !last.isFinite) return null;
    final change = last / first - 1;
    return change.isFinite ? change : null;
  }

  double _min(Iterable<double> values) => values.reduce(math.min);

  double _max(Iterable<double> values) => values.reduce(math.max);

  RiskSeverity? _stateForPoints(int points) {
    if (points <= 0) return RiskSeverity.normal;
    if (points == 1) return RiskSeverity.watch;
    return RiskSeverity.high;
  }

  RiskSeverity? _raiseMarketState(RiskSeverity? state) {
    switch (state) {
      case null:
        return RiskSeverity.watch;
      case RiskSeverity.normal:
        return RiskSeverity.watch;
      case RiskSeverity.watch:
        return RiskSeverity.high;
      case RiskSeverity.high:
      case RiskSeverity.critical:
        return RiskSeverity.high;
    }
  }

  DateTime? _latestDate(Iterable<DateTime?> values) {
    DateTime? latest;
    for (final value in values) {
      if (value == null || (latest != null && !value.isAfter(latest))) continue;
      latest = value;
    }
    return latest;
  }

  List<String> _uniqueStrings(Iterable<String> values) {
    final result = <String>[];
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty && !result.contains(trimmed)) result.add(trimmed);
    }
    return result;
  }

  String _qualityMissingReason(String base, RiskQuality? quality) {
    if (quality == null) return base;
    final status = quality.status.name;
    final reason = quality.reason;
    return reason == null || reason.trim().isEmpty
        ? '$base ($status)'
        : '$base ($status: ${reason.trim()})';
  }
}

class _SeriesView {
  const _SeriesView({
    required this.candles,
    required this.complete,
    required this.source,
  });

  final List<MarketCandle> candles;
  final bool complete;
  final MarketSourceInfo source;
}

class _VolatilityResult {
  const _VolatilityResult({this.value, this.label, this.complete = false});

  final double? value;
  final MarketRiskVolatility? label;
  final bool complete;
}

class _StructureResult {
  const _StructureResult({
    this.value,
    this.support,
    this.resistance,
    this.priorSupport,
    this.ema20,
    this.ema50,
    this.complete = false,
  });

  final MarketRiskStructure? value;
  final double? support;
  final double? resistance;
  final double? priorSupport;
  final double? ema20;
  final double? ema50;
  final bool complete;
}

class _VolumeResult {
  const _VolumeResult({this.value, this.ratio = 0, this.complete = false});

  final MarketRiskVolumePressure? value;
  final double ratio;
  final bool complete;
}

class _FundingResult {
  const _FundingResult({
    this.value,
    this.normalized,
    this.intervalHours,
    this.fundingTime,
    this.rate,
    this.source,
    this.complete = false,
  });

  final MarketRiskFundingClass? value;
  final double? normalized;
  final double? intervalHours;
  final DateTime? fundingTime;
  final double? rate;
  final MarketSourceInfo? source;
  final bool complete;
}

class _OiResult {
  const _OiResult({
    this.value,
    this.oiChange,
    this.priceChange,
    this.oiRising = false,
    this.observedAt,
    this.source,
    this.quality,
    this.complete = false,
  });

  final MarketRiskOiQuadrant? value;
  final double? oiChange;
  final double? priceChange;
  final bool oiRising;
  final DateTime? observedAt;
  final MarketSourceInfo? source;
  final RiskQuality? quality;
  final bool complete;
}
