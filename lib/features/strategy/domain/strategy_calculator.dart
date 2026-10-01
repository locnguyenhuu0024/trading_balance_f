import 'strategy_models.dart';

class StrategyLevelCalculator {
  const StrategyLevelCalculator();

  static const maximumCandles = 500;
  static const maximumClusterSpan = 0.005;

  StrategyAnalysis calculate({
    required List<StrategyCandle> candles,
    required double referencePrice,
  }) {
    if (!referencePrice.isFinite || referencePrice <= 0) {
      throw ArgumentError.value(referencePrice, 'referencePrice');
    }

    final ordered = <StrategyCandle>[];
    DateTime? previousTimestamp;
    StrategyInterval? interval;
    for (final candle in candles) {
      if (!candle.timestamp.isUtc ||
          !candle.interval.isUtcAligned(candle.timestamp)) {
        throw ArgumentError.value(candle.timestamp, 'candles');
      }
      if (interval != null && interval != candle.interval) {
        throw ArgumentError.value(candles, 'candles', 'mixed intervals');
      }
      interval = candle.interval;
      if (previousTimestamp != null &&
          !candle.timestamp.isAfter(previousTimestamp)) {
        throw ArgumentError.value(candles, 'candles', 'not strictly ordered');
      }
      previousTimestamp = candle.timestamp;
      if (!candle.hasValidPrices) continue;
      ordered.add(candle);
    }

    final window = ordered.length <= maximumCandles
        ? ordered
        : ordered.sublist(ordered.length - maximumCandles);
    final candidates = <_Candidate>[];
    for (var index = 2; index < window.length - 2; index++) {
      final current = window[index];
      var isSwingHigh = true;
      var isSwingLow = true;
      for (var offset = 1; offset <= 2; offset++) {
        final left = window[index - offset];
        final right = window[index + offset];
        if (current.high <= left.high || current.high <= right.high) {
          isSwingHigh = false;
        }
        if (current.low >= left.low || current.low >= right.low) {
          isSwingLow = false;
        }
      }
      if (isSwingHigh) {
        candidates.add(
          _Candidate(current.high, current.timestamp, StrategySide.short),
        );
      }
      if (isSwingLow) {
        candidates.add(
          _Candidate(current.low, current.timestamp, StrategySide.long),
        );
      }
    }
    candidates.sort((left, right) {
      final price = left.price.compareTo(right.price);
      if (price != 0) return price;
      final timestamp = left.timestamp.compareTo(right.timestamp);
      if (timestamp != 0) return timestamp;
      return left.side.index.compareTo(right.side.index);
    });

    final clusters = <List<_Candidate>>[];
    for (final candidate in candidates) {
      if (clusters.isEmpty) {
        clusters.add([candidate]);
        continue;
      }
      final cluster = clusters.last;
      final minimum = cluster.first.price;
      if ((candidate.price - minimum) / minimum <= maximumClusterSpan) {
        cluster.add(candidate);
      } else {
        clusters.add([candidate]);
      }
    }

    final supports = <StrategyLevel>[];
    final resistances = <StrategyLevel>[];
    for (final cluster in clusters) {
      final price = _median(cluster);
      if (price == referencePrice) continue;
      final side = price < referencePrice
          ? StrategySide.long
          : StrategySide.short;
      final times = cluster.map((item) => item.timestamp).toList()..sort();
      final level = StrategyLevel(
        price: price,
        firstTouchAt: times.first,
        lastTouchAt: times.last,
        touchCount: cluster.length,
        side: side,
      );
      (side == StrategySide.long ? supports : resistances).add(level);
    }
    supports.sort((left, right) => right.price.compareTo(left.price));
    resistances.sort((left, right) => left.price.compareTo(right.price));
    return StrategyAnalysis(
      referencePrice: referencePrice,
      supports: List.unmodifiable(supports),
      resistances: List.unmodifiable(resistances),
    );
  }

  double _median(List<_Candidate> cluster) {
    final prices = cluster.map((item) => item.price).toList()..sort();
    final middle = prices.length ~/ 2;
    return prices.length.isOdd
        ? prices[middle]
        : prices[middle - 1] / 2 + prices[middle] / 2;
  }
}

class _Candidate {
  const _Candidate(this.price, this.timestamp, this.side);

  final double price;
  final DateTime timestamp;
  final StrategySide side;
}
