import 'models.dart';

class SupportResistanceCalculator {
  const SupportResistanceCalculator();

  static const int maximumCandles = 300;
  static const int maximumLevelsPerSide = 5;
  static const double maximumClusterSpan = 0.005;

  SupportResistanceAnalysis calculate({
    required List<SupportResistanceCandle> candles,
    required double referencePrice,
  }) {
    if (!referencePrice.isFinite || referencePrice <= 0) {
      throw ArgumentError.value(
        referencePrice,
        'referencePrice',
        'must be finite and positive',
      );
    }

    final confirmed = <SupportResistanceCandle>[];
    SupportResistanceTimeframe? timeframe;
    DateTime? previousTimestamp;
    for (final candle in candles) {
      if (!candle.timestamp.isUtc ||
          !candle.timeframe.isUtcAligned(candle.timestamp)) {
        throw ArgumentError.value(
          candle.timestamp,
          'candles',
          'timestamps must be UTC-aligned to one timeframe',
        );
      }
      if (timeframe != null && timeframe != candle.timeframe) {
        throw ArgumentError.value(candles, 'candles', 'must use one timeframe');
      }
      timeframe = candle.timeframe;
      if (previousTimestamp != null &&
          !candle.timestamp.isAfter(previousTimestamp)) {
        throw ArgumentError.value(
          candles,
          'candles',
          'timestamps must be unique and oldest to newest',
        );
      }
      previousTimestamp = candle.timestamp;

      // An exchange can return its current, unconfirmed candle alongside the
      // closed history. Its prices must never participate in swing detection.
      if (!candle.confirmed) continue;
      if (!candle.hasValidPrices) {
        throw ArgumentError.value(
          candle,
          'candles',
          'confirmed candle OHLC values must be finite and positive',
        );
      }
      confirmed.add(candle);
    }

    final window = confirmed.length <= maximumCandles
        ? confirmed
        : confirmed.sublist(confirmed.length - maximumCandles);
    final candidates = <_Candidate>[];
    for (var index = 2; index < window.length - 2; index++) {
      final current = window[index];
      var strictHigh = true;
      var strictLow = true;
      for (var offset = 1; offset <= 2; offset++) {
        final left = window[index - offset];
        final right = window[index + offset];
        if (current.high <= left.high || current.high <= right.high) {
          strictHigh = false;
        }
        if (current.low >= left.low || current.low >= right.low) {
          strictLow = false;
        }
      }
      if (strictHigh) {
        candidates.add(
          _Candidate(
            price: current.high,
            timestamp: current.timestamp,
            kindOrder: 0,
          ),
        );
      }
      if (strictLow) {
        candidates.add(
          _Candidate(
            price: current.low,
            timestamp: current.timestamp,
            kindOrder: 1,
          ),
        );
      }
    }

    candidates.sort((left, right) {
      final byPrice = left.price.compareTo(right.price);
      if (byPrice != 0) return byPrice;
      final byTimestamp = left.timestamp.compareTo(right.timestamp);
      if (byTimestamp != 0) return byTimestamp;
      return left.kindOrder.compareTo(right.kindOrder);
    });

    final clusters = <List<_Candidate>>[];
    for (final candidate in candidates) {
      if (clusters.isEmpty) {
        clusters.add(<_Candidate>[candidate]);
        continue;
      }
      final currentCluster = clusters.last;
      final minimum = currentCluster.first.price;
      if ((candidate.price - minimum) / minimum <= maximumClusterSpan) {
        currentCluster.add(candidate);
      } else {
        clusters.add(<_Candidate>[candidate]);
      }
    }

    final supports = <SupportResistanceLevel>[];
    final resistances = <SupportResistanceLevel>[];
    for (final cluster in clusters) {
      final representative = _median(cluster);
      if (representative == referencePrice) continue;
      final timestamps = cluster.map((item) => item.timestamp).toList()..sort();
      final side = representative < referencePrice
          ? SupportResistanceLevelSide.support
          : SupportResistanceLevelSide.resistance;
      final level = SupportResistanceLevel(
        price: representative,
        firstTouchAt: timestamps.first,
        lastTouchAt: timestamps.last,
        touchCount: cluster.length,
        side: side,
      );
      if (side == SupportResistanceLevelSide.support) {
        supports.add(level);
      } else {
        resistances.add(level);
      }
    }

    supports.sort((left, right) => right.price.compareTo(left.price));
    resistances.sort((left, right) => left.price.compareTo(right.price));
    return SupportResistanceAnalysis(
      referencePrice: referencePrice,
      supports: List<SupportResistanceLevel>.unmodifiable(
        supports.take(maximumLevelsPerSide),
      ),
      resistances: List<SupportResistanceLevel>.unmodifiable(
        resistances.take(maximumLevelsPerSide),
      ),
    );
  }

  double _median(List<_Candidate> cluster) {
    final middle = cluster.length ~/ 2;
    if (cluster.length.isOdd) return cluster[middle].price;
    return cluster[middle - 1].price / 2 + cluster[middle].price / 2;
  }
}

class _Candidate {
  const _Candidate({
    required this.price,
    required this.timestamp,
    required this.kindOrder,
  });

  final double price;
  final DateTime timestamp;
  final int kindOrder;
}
