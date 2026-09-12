import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/market_risk_engine.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_engine.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_models.dart';

void main() {
  final now = DateTime.utc(2026, 9, 10, 12);
  final marketEngine = MarketRiskEngine(clock: () => now);
  final positionEngine = RiskEngine(clock: () => now);

  test('RED-002 preserves critical position and missing-market semantics', () {
    final favorable = marketEngine.evaluate(
      _snapshot(assetFourHourMode: 'bullish', btcFourHourMode: 'bullish'),
    );
    expect(favorable.complete, isTrue);
    final critical = positionEngine.evaluate(
      _position(markPrice: 6, liquidationPrice: 6),
      market: favorable.input,
    );
    expect(critical.positionRisk, RiskSeverity.critical);
    expect(critical.marketRisk, isNot(RiskSeverity.critical));
    expect(critical.overallRisk, RiskSeverity.critical);

    final missingOi = marketEngine.evaluate(
      _snapshot(
        assetFourHourMode: 'bullish',
        btcFourHourMode: 'bullish',
        openInterest: const <MarketOpenInterestSample>[],
      ),
    );
    expect(missingOi.openInterestQuadrant, isNull);
    expect(missingOi.complete, isFalse);
    expect(missingOi.state, isNull);
    expect(missingOi.missingReasons.join(' '), contains('open-interest'));

    final zeroVolatility = marketEngine.evaluate(
      _snapshot(
        assetOneHour: _oneHourSeries(
          closeVariation: false,
          baseline: 100,
          current: 100,
        ),
        assetFourHourMode: 'stable',
        btcFourHourMode: 'stable',
      ),
    );
    expect(zeroVolatility.volatility, isNull);
    expect(zeroVolatility.state, isNull);
    expect(zeroVolatility.quality.status, RiskQualityStatus.partial);
    expect(zeroVolatility.missingReasons.join(' '), contains('volatility'));

    final incompleteCandles = marketEngine.evaluate(
      _snapshot(
        assetFourHour: _fourHourSeries('SUI-USDT', mode: 'stable', count: 99),
        btcFourHourMode: 'stable',
      ),
    );
    expect(incompleteCandles.assetStructure, isNull);
    expect(incompleteCandles.state, isNot(RiskSeverity.normal));
    expect(incompleteCandles.complete, isFalse);
    expect(incompleteCandles.missingReasons.join(' '), contains('needs 100'));

    final fundingOnly = marketEngine.evaluate(
      _snapshot(
        assetOneHour: _oneHourSeries(
          closeVariation: false,
          baseline: 100,
          current: 100,
        ),
        assetFourHour: _fourHourSeries('SUI-USDT', mode: 'stable', count: 0),
        btcFourHour: _fourHourSeries('BTC-USDT', mode: 'stable', count: 0),
        funding: _funding(rate: 0.0006),
        openInterest: const <MarketOpenInterestSample>[],
      ),
    );
    expect(fundingOnly.fundingClass, MarketRiskFundingClass.strongPositive);
    expect(fundingOnly.assetStructure, isNull);
    expect(fundingOnly.state, RiskSeverity.watch);
    expect(
      fundingOnly.reasons.any(
        (reason) =>
            reason.message.contains('Bullish') ||
            reason.message.contains('Bearish'),
      ),
      isFalse,
    );

    final baseline = positionEngine.evaluate(_position());
    final withDerivatives = positionEngine.evaluate(
      _position(),
      market: favorable.input,
    );
    expect(withDerivatives.holdingCost30d, baseline.holdingCost30d);
  });

  test('GREEN-002 evaluates market quadrants, funding, BTC and recovery', () {
    final quadrants = <MarketRiskOiQuadrant, List<double>>{
      MarketRiskOiQuadrant.priceUpOiUp: <double>[101, 103],
      MarketRiskOiQuadrant.priceUpOiDown: <double>[101, 97],
      MarketRiskOiQuadrant.priceDownOiDown: <double>[99, 97],
      MarketRiskOiQuadrant.priceDownOiUp: <double>[99, 103],
    };
    for (final entry in quadrants.entries) {
      final evaluation = marketEngine.evaluate(
        _snapshot(
          assetFourHourMode: 'stable',
          btcFourHourMode: 'stable',
          oiBaseline: 100,
          oiCurrent: entry.value[1],
          spotBaseline: 100,
          spotCurrent: entry.value[0],
        ),
      );
      expect(evaluation.openInterestQuadrant, entry.key);
      expect(evaluation.openInterestPoints, entry.key.points);
    }

    final funding = marketEngine.evaluate(
      _snapshot(funding: _funding(rate: 0.0004, intervalHours: 4)),
    );
    expect(funding.fundingClass, MarketRiskFundingClass.strongPositive);
    expect(funding.normalizedFunding8h, closeTo(0.0008, 1e-12));
    expect(funding.fundingIntervalHours, closeTo(4, 1e-12));
    expect(funding.input.derivativesInstrument, 'SUI-USDT-SWAP');
    expect(funding.input.marketContextLabel, 'OKX perpetual context');

    final adverse = marketEngine.evaluate(
      _snapshot(
        assetFourHourMode: 'breakdown',
        btcFourHourMode: 'weak',
        funding: _funding(rate: 0),
      ),
    );
    expect(adverse.assetStructure, MarketRiskStructure.breakdown);
    expect(adverse.btcStructure, MarketRiskStructure.weak);
    expect(adverse.state, RiskSeverity.high);
    expect(
      adverse.reasons.any((reason) => reason.factorId == 'btc-market-modifier'),
      isTrue,
    );

    final watchPositionHighMarket = positionEngine.evaluate(
      _position(marginRatio: 2),
      market: adverse.input,
    );
    expect(watchPositionHighMarket.positionRisk, RiskSeverity.watch);
    expect(watchPositionHighMarket.marketRisk, RiskSeverity.high);
    expect(watchPositionHighMarket.overallRisk, RiskSeverity.high);
    final marketReason = watchPositionHighMarket.reasons.firstWhere(
      (reason) => reason.factorId == 'asset-structure',
    );
    expect(marketReason.observedValue, isNotNull);
    expect(marketReason.observedAt, now);
    expect(marketReason.source, contains('OKX'));
    expect(
      adverse.reasons
          .firstWhere((reason) => reason.factorId == 'market-volatility')
          .observedAt,
      now,
    );
    expect(
      funding.reasons
          .firstWhere((reason) => reason.factorId == 'market-funding')
          .observedAt,
      now.subtract(const Duration(hours: 4)),
    );
    expect(
      funding.reasons
          .firstWhere((reason) => reason.factorId == 'market-open-interest')
          .observedAt,
      now,
    );
    expect(
      funding.reasons
          .firstWhere((reason) => reason.factorId == 'market-volume')
          .observedAt,
      now,
    );
    expect(
      funding.reasons
          .firstWhere(
            (reason) => reason.factorId == 'market-funding-contribution',
          )
          .observedAt,
      now.subtract(const Duration(hours: 4)),
    );
    expect(
      adverse.reasons
          .firstWhere((reason) => reason.factorId == 'btc-market-modifier')
          .observedAt,
      now,
    );

    final recovered = marketEngine.evaluate(
      _snapshot(
        assetFourHourMode: 'recovery',
        btcFourHourMode: 'stable',
        funding: _funding(rate: 0),
      ),
    );
    expect(recovered.assetStructure, MarketRiskStructure.recovery);
    expect(recovered.assetPoints, 0);
    expect(
      recovered.reasons.any(
        (reason) => reason.factorId == 'asset-structure-recovery',
      ),
      isTrue,
    );
    expect(
      recovered.reasons
          .firstWhere((reason) => reason.factorId == 'asset-structure-recovery')
          .observedAt,
      now,
    );
    expect(recovered.state, isNot(RiskSeverity.high));

    final neutralBand = marketEngine.evaluate(
      _snapshot(
        spotBaseline: 100,
        spotCurrent: 100.5,
        oiBaseline: 100,
        oiCurrent: 102,
      ),
    );
    expect(neutralBand.openInterestQuadrant, MarketRiskOiQuadrant.mixed);
    expect(neutralBand.openInterestPoints, 0);

    final negativeFundingAfterDecline = marketEngine.evaluate(
      _snapshot(
        assetOneHour: _oneHourSeries(
          firstClose: 110,
          baseline: 110,
          current: 100,
        ),
        funding: _funding(rate: -0.0002),
      ),
    );
    expect(negativeFundingAfterDecline.fundingPoints, 0);
    expect(
      negativeFundingAfterDecline.reasons.any(
        (reason) => reason.factorId == 'negative-funding-explanation',
      ),
      isTrue,
    );
  });

  test('GREEN-002 derives nonzero volatility at the 3% and 6% boundaries', () {
    final cases = <double, MarketRiskVolatility>{
      0.01: MarketRiskVolatility.low,
      0.03: MarketRiskVolatility.normal,
      0.06: MarketRiskVolatility.high,
    };
    for (final entry in cases.entries) {
      final evaluation = marketEngine.evaluate(
        _snapshot(
          assetOneHour: _singleLogReturnSeries(entry.key),
          assetFourHourMode: 'stable',
          btcFourHourMode: 'stable',
        ),
      );
      expect(evaluation.volatility, entry.value);
      expect(evaluation.input.dailyVolatility, closeTo(entry.key, 1e-10));
      expect(evaluation.input.dailyVolatility, greaterThan(0));
    }
  });

  test(
    'GREEN-002 respects EMA equality, support break and recovery boundaries',
    () {
      final emaEquality = marketEngine.evaluate(
        _snapshot(
          assetFourHour: _boundaryStructureSeries(latestClose: 100),
          btcFourHourMode: 'stable',
        ),
      );
      expect(emaEquality.assetStructure, MarketRiskStructure.stable);

      final supportEquality = marketEngine.evaluate(
        _snapshot(
          assetFourHour: _boundaryStructureSeries(latestClose: 99.5),
          btcFourHourMode: 'stable',
        ),
      );
      expect(
        supportEquality.assetStructure,
        isNot(MarketRiskStructure.breakdown),
      );

      final supportBreak = marketEngine.evaluate(
        _snapshot(
          assetFourHour: _boundaryStructureSeries(latestClose: 99.49),
          btcFourHourMode: 'stable',
        ),
      );
      expect(supportBreak.assetStructure, MarketRiskStructure.breakdown);

      final recoveryEquality = marketEngine.evaluate(
        _snapshot(
          assetFourHour: _boundaryStructureSeries(
            latestClose: 100.5,
            priorClose: 99,
            priorLow: 98,
          ),
          btcFourHourMode: 'stable',
        ),
      );
      expect(recoveryEquality.assetStructure, MarketRiskStructure.recovery);
    },
  );

  test('GREEN-002 requires the positive-funding and rising-OI conjunction', () {
    final conjunction = marketEngine.evaluate(
      _snapshot(
        assetOneHour: _oneHourSeries(baseline: 100, current: 100.2),
        spotBaseline: 100,
        spotCurrent: 100.2,
        oiBaseline: 100,
        oiCurrent: 103,
        funding: _funding(rate: 0.0002, intervalHours: 8),
      ),
    );
    expect(conjunction.fundingClass, MarketRiskFundingClass.positive);
    expect(conjunction.fundingPoints, 1);
    expect(
      conjunction.reasons.any(
        (reason) =>
            reason.factorId == 'market-funding-contribution' &&
            reason.message.contains('rising OI'),
      ),
      isTrue,
    );

    final withoutRisingOi = marketEngine.evaluate(
      _snapshot(
        assetOneHour: _oneHourSeries(baseline: 100, current: 100.2),
        spotBaseline: 100,
        spotCurrent: 100.2,
        oiBaseline: 100,
        oiCurrent: 97,
        funding: _funding(rate: 0.0002, intervalHours: 8),
      ),
    );
    expect(withoutRisingOi.fundingPoints, 0);
  });

  test('GREEN-002 accepts OI alignment tolerance', () {
    final target = now.subtract(const Duration(hours: 4));
    final accepted = marketEngine.evaluate(
      _snapshot(
        assetOneHour: _twoPointSpotSeries(
          baselineAt: target.subtract(const Duration(minutes: 20)),
          currentAt: now.subtract(const Duration(minutes: 5)),
        ),
        openInterest: _timestampedOpenInterest(
          baselineAt: target.subtract(const Duration(minutes: 15)),
          currentAt: now,
          baseline: 100,
          current: 103,
        ),
      ),
    );
    expect(accepted.openInterestQuadrant, MarketRiskOiQuadrant.priceUpOiUp);

    final misaligned = marketEngine.evaluate(
      _snapshot(
        assetOneHour: _twoPointSpotSeries(
          baselineAt: target.subtract(const Duration(minutes: 21)),
          currentAt: now,
        ),
        openInterest: _timestampedOpenInterest(
          baselineAt: target.subtract(const Duration(minutes: 15)),
          currentAt: now,
          baseline: 100,
          current: 103,
        ),
      ),
    );
    expect(misaligned.openInterestQuadrant, isNull);
    expect(
      misaligned.missingReasons.join(' '),
      contains('Corresponding spot closes'),
    );
  });

  test('RED-002 rejects stale OI and propagates stale quality', () {
    final staleAt = now.subtract(const Duration(minutes: 6));
    final evaluation = marketEngine.evaluate(
      _snapshot(
        assetOneHour: _twoPointSpotSeries(
          baselineAt: now.subtract(const Duration(hours: 4)),
          currentAt: staleAt,
        ),
        openInterest: _timestampedOpenInterest(
          baselineAt: now.subtract(const Duration(hours: 4)),
          currentAt: staleAt,
          baseline: 100,
          current: 103,
        ),
      ),
    );

    expect(evaluation.openInterestQuadrant, isNull);
    expect(evaluation.missingReasons.join(' '), contains('is stale'));
    expect(evaluation.openInterestQuality?.status, RiskQualityStatus.stale);
    expect(
      evaluation.input.openInterestQuality?.status,
      RiskQualityStatus.stale,
    );
    expect(evaluation.openInterestQuality?.source, 'fixture');
    expect(evaluation.input.openInterestQuality?.source, 'fixture');
    expect(evaluation.openInterestQuality?.reason, contains('is stale'));
    expect(evaluation.input.openInterestQuality?.reason, contains('is stale'));
    expect(evaluation.openInterestQuality?.observedAt, _now);
    expect(evaluation.input.openInterestQuality?.observedAt, _now);
    expect(evaluation.openInterestQuality?.sourceAt, staleAt);
    expect(evaluation.input.openInterestQuality?.sourceAt, staleAt);
  });

  test('RED-002 rejects duplicate or out-of-order injected OI history', () {
    final target = now.subtract(const Duration(hours: 4));
    final evaluation = marketEngine.evaluate(
      _snapshot(
        openInterest: <MarketOpenInterestSample>[
          _oiSample(target, 100),
          _oiSample(now, 103),
          _oiSample(now, 104),
        ],
      ),
    );
    expect(evaluation.openInterestQuadrant, isNull);
    expect(
      evaluation.missingReasons.join(' '),
      contains('duplicate or out-of-order'),
    );
    expect(evaluation.quality.status, RiskQualityStatus.partial);
  });

  test(
    'RED-002 keeps current OI unavailable until persisted history exists',
    () {
      final evaluation = marketEngine.evaluate(
        _snapshot(
          openInterest: <MarketOpenInterestSample>[_oiSample(now, 103)],
        ),
      );
      expect(evaluation.openInterestQuadrant, isNull);
      expect(
        evaluation.missingReasons.join(' '),
        contains('needs a sample at or before now-4h'),
      );
      expect(
        evaluation.openInterestQuality?.status,
        RiskQualityStatus.complete,
      );
    },
  );

  test(
    'RED-002 preserves typed funding and OI source quality in evaluation',
    () {
      final fundingQuality = RiskQuality.error(
        source: 'OKX /api/v5/public/funding-rate [SUI-USDT-SWAP]',
        reason: 'Public funding request failed (HTTP 429)',
        observedAt: now,
      );
      final oiQuality = RiskQuality(
        status: RiskQualityStatus.empty,
        source: 'OKX /api/v5/public/open-interest [SUI-USDT-SWAP]',
        reason: 'No matching SUI-USDT-SWAP current open-interest observation',
        observedAt: now,
      );
      final evaluation = marketEngine.evaluate(
        _snapshot(
          omitFunding: true,
          omitOpenInterest: true,
          fundingQuality: fundingQuality,
          openInterestQuality: oiQuality,
        ),
      );

      expect(evaluation.fundingQuality?.status, RiskQualityStatus.error);
      expect(evaluation.openInterestQuality?.status, RiskQualityStatus.empty);
      expect(evaluation.input.fundingQuality?.reason, contains('HTTP 429'));
      expect(
        evaluation.missingReasons.join(' '),
        allOf(contains('error'), contains('empty')),
      );
    },
  );
}

MarketRiskSnapshot _snapshot({
  String asset = 'SUI',
  MarketCandleSeries? assetOneHour,
  MarketCandleSeries? assetFourHour,
  MarketCandleSeries? btcOneHour,
  MarketCandleSeries? btcFourHour,
  Object? funding,
  Object? openInterest,
  RiskQuality? fundingQuality,
  RiskQuality? openInterestQuality,
  bool omitFunding = false,
  bool omitOpenInterest = false,
  String assetFourHourMode = 'stable',
  String btcFourHourMode = 'stable',
  double spotBaseline = 100,
  double spotCurrent = 101,
  double oiBaseline = 100,
  double oiCurrent = 103,
}) {
  final assetInstrument = '${asset.toUpperCase()}-USDT';
  final actualFunding = omitFunding
      ? null
      : funding == null
      ? _funding()
      : funding as MarketFundingObservation?;
  final actualOi = omitOpenInterest
      ? const <MarketOpenInterestSample>[]
      : openInterest == null
      ? _openInterest(
          instrument: '${asset.toUpperCase()}-USDT-SWAP',
          baseline: oiBaseline,
          current: oiCurrent,
        )
      : openInterest as List<MarketOpenInterestSample>;
  return MarketRiskSnapshot(
    asset: asset,
    assetOneHour:
        assetOneHour ??
        _oneHourSeries(
          instrument: assetInstrument,
          baseline: spotBaseline,
          current: spotCurrent,
        ),
    assetFourHour:
        assetFourHour ??
        _fourHourSeries(assetInstrument, mode: assetFourHourMode),
    btcOneHour: btcOneHour ?? _oneHourSeries(instrument: 'BTC-USDT'),
    btcFourHour:
        btcFourHour ?? _fourHourSeries('BTC-USDT', mode: btcFourHourMode),
    funding: actualFunding,
    openInterest: actualOi,
    fundingQuality: fundingQuality,
    openInterestQuality: openInterestQuality,
    observedAt: _now,
  );
}

final _now = DateTime.utc(2026, 9, 10, 12);

MarketCandleSeries _oneHourSeries({
  String instrument = 'SUI-USDT',
  double baseline = 100,
  double current = 101,
  double? firstClose,
  bool closeVariation = true,
}) {
  final candles = <MarketCandle>[];
  for (var index = 0; index < 25; index++) {
    final timestamp = _now.subtract(Duration(hours: 24 - index));
    var close = closeVariation ? 100.0 + index * 0.01 : 100.0;
    if (index == 0 && firstClose != null) close = firstClose;
    if (index == 20) close = baseline;
    if (index == 24) close = current;
    candles.add(
      _candle(
        timestamp,
        close: close,
        open: close,
        volume: 100,
        interval: '1H',
      ),
    );
  }
  return _series(instrument, '1H', candles);
}

MarketCandleSeries _singleLogReturnSeries(double finalLogReturn) {
  final candles = <MarketCandle>[];
  for (var index = 0; index < 25; index++) {
    final timestamp = _now.subtract(Duration(hours: 24 - index));
    final close = index == 24 ? 100 * math.exp(finalLogReturn) : 100.0;
    candles.add(
      _candle(
        timestamp,
        close: close,
        open: close,
        volume: 100,
        interval: '1H',
      ),
    );
  }
  return _series('SUI-USDT', '1H', candles);
}

MarketCandleSeries _twoPointSpotSeries({
  required DateTime baselineAt,
  required DateTime currentAt,
}) {
  return _series('SUI-USDT', '1H', <MarketCandle>[
    _candle(baselineAt, close: 100, open: 100, interval: '1H'),
    _candle(currentAt, close: 101, open: 101, interval: '1H'),
  ]);
}

MarketCandleSeries _boundaryStructureSeries({
  required double latestClose,
  double? priorClose,
  double? priorLow,
}) {
  final candles = <MarketCandle>[];
  for (var index = 0; index < 100; index++) {
    final timestamp = _now.subtract(Duration(hours: 4 * (99 - index)));
    var close = 100.0;
    var open = 100.0;
    var low = 100.0;
    var high = 101.0;
    if (index == 98 && priorClose != null) {
      close = priorClose;
      low = priorLow ?? priorClose;
      high = 101;
    }
    if (index == 99) {
      close = latestClose;
      open = 100;
      low = math.min(latestClose, 100);
      high = math.max(latestClose, 101);
    }
    candles.add(
      _candle(
        timestamp,
        close: close,
        open: open,
        low: low,
        high: high,
        volume: 100,
        interval: '4H',
      ),
    );
  }
  return _series('SUI-USDT', '4H', candles);
}

MarketCandleSeries _fourHourSeries(
  String instrument, {
  String mode = 'stable',
  int count = 100,
}) {
  final candles = <MarketCandle>[];
  for (var index = 0; index < count; index++) {
    final timestamp = _now.subtract(Duration(hours: 4 * (99 - index)));
    var close = 100.0;
    var open = close;
    var low = close - 1;
    var high = close + 1;
    switch (mode) {
      case 'bullish':
        close = 100.0 + index;
        open = close;
        low = close - 1;
        high = close + 1;
      case 'weak':
        close = 200.0 - index;
        open = close;
        low = 50;
        high = close + 1;
      case 'breakdown':
        close = index == 99 ? 170.0 : 100.0 + index;
        open = index == 99 ? 180.0 : close;
        low = index == 99 ? 169.0 : close - 1;
        high = index == 99 ? 181.0 : close + 1;
      case 'recovery':
        if (index < 78) {
          close = 100;
          open = close;
          low = 100;
          high = 101;
        } else if (index < 98) {
          close = 100;
          open = close;
          low = 100;
          high = 101;
        } else if (index == 98) {
          close = 99;
          open = 100;
          low = 98;
          high = 101;
        } else {
          close = 101;
          open = 100;
          low = 100;
          high = 102;
        }
      default:
        break;
    }
    candles.add(
      _candle(
        timestamp,
        close: close,
        open: open,
        low: low,
        high: high,
        volume: index == 99 ? 200 : 100,
        interval: '4H',
      ),
    );
  }
  return _series(instrument, '4H', candles, complete: count >= 100);
}

MarketCandle _candle(
  DateTime timestamp, {
  required double close,
  required double open,
  required String interval,
  double? high,
  double? low,
  double volume = 100,
}) {
  return MarketCandle(
    timestamp: timestamp,
    open: open,
    high: high ?? close + 1,
    low: low ?? close - 1,
    close: close,
    volume: volume,
    interval: interval,
  );
}

MarketCandleSeries _series(
  String instrument,
  String interval,
  List<MarketCandle> candles, {
  bool complete = true,
}) {
  final sourceAt = candles.isEmpty ? null : candles.last.timestamp;
  return MarketCandleSeries(
    instrument: instrument,
    interval: interval,
    candles: List.unmodifiable(candles),
    complete: complete,
    source: MarketSourceInfo(
      venue: 'OKX',
      instrument: instrument,
      endpoint: '/api/v5/market/candles',
      observedAt: _now,
      sourceAt: sourceAt,
      quality: complete
          ? RiskQuality.complete(source: 'fixture', observedAt: _now)
          : const RiskQuality.partial(source: 'fixture', reason: 'incomplete'),
    ),
  );
}

MarketFundingObservation _funding({
  String instrument = 'SUI-USDT-SWAP',
  double rate = 0,
  int intervalHours = 8,
}) {
  final fundingTime = _now.subtract(Duration(hours: intervalHours));
  return MarketFundingObservation(
    instrument: instrument,
    rate: rate,
    fundingTime: fundingTime,
    nextFundingTime: _now,
    source: MarketSourceInfo(
      venue: 'OKX',
      instrument: instrument,
      endpoint: '/api/v5/public/funding-rate',
      observedAt: _now,
      sourceAt: fundingTime,
      quality: RiskQuality.complete(source: 'fixture', observedAt: _now),
    ),
  );
}

List<MarketOpenInterestSample> _openInterest({
  required String instrument,
  required double baseline,
  required double current,
}) {
  MarketSourceInfo source(DateTime at) => MarketSourceInfo(
    venue: 'OKX',
    instrument: instrument,
    endpoint: '/api/v5/public/open-interest',
    observedAt: _now,
    sourceAt: at,
    quality: RiskQuality.complete(source: 'fixture', observedAt: _now),
  );
  return <MarketOpenInterestSample>[
    MarketOpenInterestSample(
      instrument: instrument,
      timestamp: _now.subtract(const Duration(hours: 4)),
      oiCcy: baseline,
      source: source(_now.subtract(const Duration(hours: 4))),
    ),
    MarketOpenInterestSample(
      instrument: instrument,
      timestamp: _now,
      oiCcy: current,
      source: source(_now),
    ),
  ];
}

List<MarketOpenInterestSample> _timestampedOpenInterest({
  required DateTime baselineAt,
  required DateTime currentAt,
  required double baseline,
  required double current,
}) {
  return <MarketOpenInterestSample>[
    _oiSample(baselineAt, baseline),
    _oiSample(currentAt, current),
  ];
}

MarketOpenInterestSample _oiSample(DateTime timestamp, double value) {
  return MarketOpenInterestSample(
    instrument: 'SUI-USDT-SWAP',
    timestamp: timestamp,
    oiCcy: value,
    source: MarketSourceInfo(
      venue: 'OKX',
      instrument: 'SUI-USDT-SWAP',
      endpoint: '/api/v5/public/open-interest',
      observedAt: _now,
      sourceAt: timestamp,
      quality: RiskQuality.complete(
        source: 'fixture',
        observedAt: _now,
        sourceAt: timestamp,
      ),
    ),
  );
}

RiskPosition _position({
  double markPrice = 10,
  double liquidationPrice = 6,
  double marginRatio = 2,
}) {
  return RiskPosition(
    instrumentId: 'SUI-USDT',
    mode: RiskAccountMode.newMode,
    collateralCurrency: RiskCollateralCurrency.quote,
    positionSide: 'net',
    positionId: 'market-test',
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: _now,
    baseCurrency: 'SUI',
    quoteCurrency: 'USDT',
    positionCurrency: 'SUI',
    liabilityCurrency: 'USDT',
    rawQuantity: 100,
    quantity: 100,
    margin: 700,
    markPrice: markPrice,
    entryPrice: 11,
    liquidationPrice: liquidationPrice,
    unrealizedPnl: -200,
    marginRatio: marginRatio,
    maintenanceRequirement: 100,
    reportedLiability: 1198,
    reportedInterest: 2,
    hourlyBorrowRate: 0.00001,
    entryFeeRate: 0.001,
    exitFeeRate: 0.001,
    quality: const RiskQuality.complete(source: 'fixture'),
    source: 'fixture',
  );
}
