import 'strategy_models.dart';

class StrategyLevelCalculator {
  const StrategyLevelCalculator();

  static const maximumCandles = 500;

  StrategyAnalysis calculate({
    required List<StrategyCandle> candles,
    required double referencePrice,
    String? referencePriceText,
    String tickSizeText = '1',
  }) {
    if (!referencePrice.isFinite || referencePrice <= 0) {
      throw ArgumentError.value(referencePrice, 'referencePrice');
    }
    final reference = StrategyDecimal.tryParse(
      referencePriceText ?? referencePrice.toString(),
    );
    final tick = StrategyDecimal.tryParse(tickSizeText);
    if (reference == null || !reference.isPositive) {
      throw ArgumentError.value(referencePriceText, 'referencePriceText');
    }
    if (tick == null || !tick.isPositive) {
      throw ArgumentError.value(tickSizeText, 'tickSizeText');
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
      final currentHigh = StrategyDecimal.tryParse(current.highText)!;
      final currentLow = StrategyDecimal.tryParse(current.lowText)!;
      var isSwingHigh = true;
      var isSwingLow = true;
      for (var offset = 1; offset <= 2; offset++) {
        final left = window[index - offset];
        final right = window[index + offset];
        final leftHigh = StrategyDecimal.tryParse(left.highText)!;
        final rightHigh = StrategyDecimal.tryParse(right.highText)!;
        final leftLow = StrategyDecimal.tryParse(left.lowText)!;
        final rightLow = StrategyDecimal.tryParse(right.lowText)!;
        if (currentHigh.compareTo(leftHigh) <= 0 ||
            currentHigh.compareTo(rightHigh) <= 0) {
          isSwingHigh = false;
        }
        if (currentLow.compareTo(leftLow) >= 0 ||
            currentLow.compareTo(rightLow) >= 0) {
          isSwingLow = false;
        }
      }
      if (isSwingHigh) {
        candidates.add(
          _Candidate(
            currentHigh,
            current.timestamp,
            _sourceLevelId('high', current.timestamp),
          ),
        );
      }
      if (isSwingLow) {
        candidates.add(
          _Candidate(
            currentLow,
            current.timestamp,
            _sourceLevelId('low', current.timestamp),
          ),
        );
      }
    }
    candidates.sort((left, right) {
      final price = left.price.compareTo(right.price);
      if (price != 0) return price;
      final timestamp = left.timestamp.compareTo(right.timestamp);
      if (timestamp != 0) return timestamp;
      return left.sourceLevelId.compareTo(right.sourceLevelId);
    });

    final clusters = <List<_Candidate>>[];
    for (final candidate in candidates) {
      if (clusters.isEmpty) {
        clusters.add([candidate]);
        continue;
      }
      final cluster = clusters.last;
      final minimum = cluster.first.price;
      final distance = candidate.price - minimum;
      if (distance.multipliedBy(200).compareTo(minimum) <= 0) {
        cluster.add(candidate);
      } else {
        clusters.add([candidate]);
      }
    }

    final supports = <StrategyLevel>[];
    final resistances = <StrategyLevel>[];
    for (final cluster in clusters) {
      final median = _median(cluster);
      final comparison = median.compareTo(reference);
      if (comparison == 0) continue;
      final side = comparison < 0 ? StrategySide.long : StrategySide.short;
      final quantized = side == StrategySide.long
          ? median.quantizedDownTo(tick)
          : median.quantizedUpTo(tick);
      if ((side == StrategySide.long && quantized.compareTo(reference) >= 0) ||
          (side == StrategySide.short && quantized.compareTo(reference) <= 0)) {
        continue;
      }
      final orderedCluster = cluster.toList()
        ..sort((left, right) {
          final timestamp = left.timestamp.compareTo(right.timestamp);
          return timestamp != 0
              ? timestamp
              : left.sourceLevelId.compareTo(right.sourceLevelId);
        });
      final times = cluster.map((item) => item.timestamp).toList()..sort();
      final level = StrategyLevel(
        price: quantized.toDouble(),
        exactPriceText: quantized.toString(),
        levelId: orderedCluster.first.sourceLevelId,
        firstTouchAt: times.first,
        lastTouchAt: times.last,
        touchCount: cluster.length,
        side: side,
      );
      (side == StrategySide.long ? supports : resistances).add(level);
    }
    int compareLevels(StrategyLevel left, StrategyLevel right) {
      final price = StrategyDecimal.tryParse(
        left.priceText,
      )!.compareTo(StrategyDecimal.tryParse(right.priceText)!);
      if (price != 0) {
        return left.side == StrategySide.long ? -price : price;
      }
      return left.id.compareTo(right.id);
    }

    supports.sort(compareLevels);
    resistances.sort(compareLevels);
    return StrategyAnalysis(
      referencePrice: referencePrice,
      exactReferencePriceText: reference.toString(),
      supports: List.unmodifiable(supports),
      resistances: List.unmodifiable(resistances),
    );
  }

  StrategyDecimal _median(List<_Candidate> cluster) {
    final prices = cluster.map((item) => item.price).toList()
      ..sort((left, right) => left.compareTo(right));
    final middle = prices.length ~/ 2;
    return prices.length.isOdd
        ? prices[middle]
        : (prices[middle - 1] + prices[middle]).dividedByTwo();
  }

  String _sourceLevelId(String type, DateTime timestamp) =>
      '${type}_${timestamp.millisecondsSinceEpoch}';
}

class _Candidate {
  const _Candidate(this.price, this.timestamp, this.sourceLevelId);

  final StrategyDecimal price;
  final DateTime timestamp;
  final String sourceLevelId;
}
