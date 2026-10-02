class StrategyDecimal implements Comparable<StrategyDecimal> {
  const StrategyDecimal._(this.coefficient, this.scale);

  static final _pattern = RegExp(
    r'^([+-]?)(?:(\d+)(?:\.(\d*))?|\.(\d+))(?:[eE]([+-]?\d+))?$',
  );
  static final _ten = BigInt.from(10);

  final BigInt coefficient;
  final int scale;

  static StrategyDecimal? tryParse(String? text) {
    if (text == null || text.length > 1024) return null;
    final match = _pattern.firstMatch(text.trim());
    if (match == null) return null;
    final whole = match.group(2) ?? '0';
    final fraction = match.group(3) ?? match.group(4) ?? '';
    final exponent = int.tryParse(match.group(5) ?? '0');
    if (exponent == null || exponent.abs() > 1024) return null;
    final digits = '$whole$fraction';
    final parsedCoefficient = BigInt.tryParse(digits);
    if (parsedCoefficient == null) return null;
    var coefficient = match.group(1) == '-'
        ? -parsedCoefficient
        : parsedCoefficient;
    var scale = fraction.length - exponent;
    if (scale < 0) {
      coefficient *= _powerOfTen(-scale);
      scale = 0;
    }
    return _normalized(coefficient, scale);
  }

  static StrategyDecimal _normalized(BigInt coefficient, int scale) {
    while (scale > 0 && coefficient.remainder(_ten) == BigInt.zero) {
      coefficient ~/= _ten;
      scale--;
    }
    return StrategyDecimal._(coefficient, scale);
  }

  static BigInt _powerOfTen(int power) => _ten.pow(power);

  bool get isPositive => coefficient > BigInt.zero;

  @override
  int compareTo(StrategyDecimal other) {
    final commonScale = scale > other.scale ? scale : other.scale;
    final left = coefficient * _powerOfTen(commonScale - scale);
    final right = other.coefficient * _powerOfTen(commonScale - other.scale);
    return left.compareTo(right);
  }

  StrategyDecimal operator +(StrategyDecimal other) {
    final commonScale = scale > other.scale ? scale : other.scale;
    final left = coefficient * _powerOfTen(commonScale - scale);
    final right = other.coefficient * _powerOfTen(commonScale - other.scale);
    return _normalized(left + right, commonScale);
  }

  StrategyDecimal operator -(StrategyDecimal other) {
    final commonScale = scale > other.scale ? scale : other.scale;
    final left = coefficient * _powerOfTen(commonScale - scale);
    final right = other.coefficient * _powerOfTen(commonScale - other.scale);
    return _normalized(left - right, commonScale);
  }

  StrategyDecimal abs() =>
      coefficient.isNegative ? StrategyDecimal._(-coefficient, scale) : this;

  StrategyDecimal multipliedBy(int multiplier) =>
      _normalized(coefficient * BigInt.from(multiplier), scale);

  StrategyDecimal dividedByTwo() =>
      _normalized(coefficient * BigInt.from(5), scale + 1);

  StrategyDecimal quantizedDownTo(StrategyDecimal tick) =>
      _quantizedTo(tick, roundUp: false);

  StrategyDecimal quantizedUpTo(StrategyDecimal tick) =>
      _quantizedTo(tick, roundUp: true);

  StrategyDecimal _quantizedTo(StrategyDecimal tick, {required bool roundUp}) {
    if (!tick.isPositive) throw ArgumentError.value(tick, 'tick');
    final commonScale = scale > tick.scale ? scale : tick.scale;
    final valueUnits = coefficient * _powerOfTen(commonScale - scale);
    final tickUnits = tick.coefficient * _powerOfTen(commonScale - tick.scale);
    var ticks = valueUnits ~/ tickUnits;
    final remainder = valueUnits.remainder(tickUnits);
    if (remainder != BigInt.zero) {
      if (roundUp && !valueUnits.isNegative) ticks += BigInt.one;
      if (!roundUp && valueUnits.isNegative) ticks -= BigInt.one;
    }
    return _normalized(ticks * tickUnits, commonScale);
  }

  double toDouble() => double.parse(toString());

  @override
  String toString() {
    final sign = coefficient.isNegative ? '-' : '';
    final digits = coefficient.abs().toString();
    if (scale == 0) return '$sign$digits';
    final padded = digits.length <= scale
        ? '${List.filled(scale + 1 - digits.length, '0').join()}$digits'
        : digits;
    final point = padded.length - scale;
    return '$sign${padded.substring(0, point)}.${padded.substring(point)}';
  }
}

enum StrategyInterval {
  h6('6H', '6Hutc', Duration(hours: 6)),
  h12('12H', '12Hutc', Duration(hours: 12)),
  d1('1D', '1Dutc', Duration(days: 1)),
  w1('1W', '1Wutc', Duration(days: 7));

  const StrategyInterval(this.label, this.bar, this.duration);

  final String label;
  final String bar;
  final Duration duration;

  bool isUtcAligned(DateTime timestamp) {
    if (!timestamp.isUtc || timestamp.microsecond != 0) return false;
    if (this == StrategyInterval.w1) {
      final mondayEpoch = DateTime.utc(1969, 12, 29).millisecondsSinceEpoch;
      return (timestamp.millisecondsSinceEpoch - mondayEpoch) %
              duration.inMilliseconds ==
          0;
    }
    return timestamp.millisecondsSinceEpoch % duration.inMilliseconds == 0;
  }
}

enum StrategySide {
  long('long', 'Long'),
  short('short', 'Short');

  const StrategySide(this.wireValue, this.label);

  final String wireValue;
  final String label;
}

enum StrategyAllocation { equal, increasing, decreasing }

class StrategyInstrument {
  const StrategyInstrument({
    required this.instrumentId,
    required this.base,
    this.tickSizeText,
  });

  final String instrumentId;
  final String base;
  final String? tickSizeText;
}

class StrategyTicker {
  const StrategyTicker({
    required this.instrumentId,
    required this.lastPrice,
    required this.observedAt,
    this.exactPriceText,
  });

  final String instrumentId;
  final double lastPrice;
  final DateTime observedAt;
  final String? exactPriceText;

  String get priceText => exactPriceText ?? lastPrice.toString();

  bool isFreshAt(
    DateTime now, {
    Duration maximumAge = const Duration(seconds: 4),
  }) {
    final age = now.toUtc().difference(observedAt.toUtc());
    return lastPrice.isFinite &&
        lastPrice > 0 &&
        !age.isNegative &&
        age <= maximumAge;
  }
}

class StrategyCandle {
  const StrategyCandle({
    required this.timestamp,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.interval,
    this.exactOpenText,
    this.exactHighText,
    this.exactLowText,
    this.exactCloseText,
  });

  final DateTime timestamp;
  final double open;
  final double high;
  final double low;
  final double close;
  final StrategyInterval interval;
  final String? exactOpenText;
  final String? exactHighText;
  final String? exactLowText;
  final String? exactCloseText;

  String get openText => exactOpenText ?? open.toString();
  String get highText => exactHighText ?? high.toString();
  String get lowText => exactLowText ?? low.toString();
  String get closeText => exactCloseText ?? close.toString();

  bool get hasValidPrices {
    if (!open.isFinite || !high.isFinite || !low.isFinite || !close.isFinite) {
      return false;
    }
    final exactOpen = StrategyDecimal.tryParse(openText);
    final exactHigh = StrategyDecimal.tryParse(highText);
    final exactLow = StrategyDecimal.tryParse(lowText);
    final exactClose = StrategyDecimal.tryParse(closeText);
    if (exactOpen == null ||
        exactHigh == null ||
        exactLow == null ||
        exactClose == null ||
        !exactOpen.isPositive ||
        !exactHigh.isPositive ||
        !exactLow.isPositive ||
        !exactClose.isPositive) {
      return false;
    }
    return exactHigh.compareTo(exactLow) >= 0 &&
        exactHigh.compareTo(exactOpen) >= 0 &&
        exactHigh.compareTo(exactClose) >= 0 &&
        exactLow.compareTo(exactOpen) <= 0 &&
        exactLow.compareTo(exactClose) <= 0;
  }
}

class StrategyLevel {
  const StrategyLevel({
    required this.price,
    required this.firstTouchAt,
    required this.lastTouchAt,
    required this.touchCount,
    required this.side,
    this.exactPriceText,
    this.levelId,
  });

  final double price;
  final DateTime firstTouchAt;
  final DateTime lastTouchAt;
  final int touchCount;
  final StrategySide side;
  final String? exactPriceText;
  final String? levelId;

  String get priceText {
    final text = exactPriceText ?? price.toString();
    return StrategyDecimal.tryParse(text)?.toString() ?? text;
  }

  String get id =>
      levelId ?? '${side.wireValue}_${firstTouchAt.millisecondsSinceEpoch}';
}

class StrategyAnalysis {
  const StrategyAnalysis({
    required this.referencePrice,
    required this.supports,
    required this.resistances,
    this.exactReferencePriceText,
  });

  final double referencePrice;
  final String? exactReferencePriceText;
  final List<StrategyLevel> supports;
  final List<StrategyLevel> resistances;
}

class StrategyMarketSnapshot {
  const StrategyMarketSnapshot({
    required this.instrumentId,
    required this.interval,
    required this.ticker,
    required this.candles,
    required this.analysis,
  });

  final String instrumentId;
  final StrategyInterval interval;
  final StrategyTicker ticker;
  final List<StrategyCandle> candles;
  final StrategyAnalysis analysis;
}

class StrategyMarketException implements Exception {
  const StrategyMarketException(this.message);

  final String message;

  @override
  String toString() => message;
}

String strategyNumber(Object? value) => value == null ? '' : value.toString();

List<Map<String, dynamic>>? validatedStrategyOrders(
  Map<String, dynamic> prepared,
) {
  if (_nonNegativeOrderNumber(prepared['estimatedOpeningFees']) == null) {
    return null;
  }
  final rawOrders = prepared['orders'];
  if (rawOrders is! List || rawOrders.isEmpty || rawOrders.length > 20) {
    return null;
  }
  final orders = <Map<String, dynamic>>[];
  for (final rawOrder in rawOrders) {
    if (rawOrder is! Map || rawOrder.keys.any((key) => key is! String)) {
      return null;
    }
    final order = Map<String, dynamic>.from(rawOrder);
    final side = order['side'];
    final role = order['role'];
    if (side is! String ||
        !const {'long', 'short'}.contains(side) ||
        role is! String ||
        !const {'entry', 'dca'}.contains(role)) {
      return null;
    }
    if (_positiveOrderNumber(order['limitPrice']) == null ||
        _positiveOrderNumber(order['contracts']) == null ||
        _positiveOrderNumber(order['margin']) == null) {
      return null;
    }
    final leverage = _positiveOrderNumber(order['leverage']);
    if (leverage == null ||
        leverage < 1 ||
        leverage > 10 ||
        leverage != leverage.roundToDouble() ||
        _nonNegativeOrderNumber(order['openingFeeEstimate']) == null) {
      return null;
    }
    orders.add(Map.unmodifiable(order));
  }
  if (!_openingFeesMatch(prepared['estimatedOpeningFees'], orders)) {
    return null;
  }
  return List.unmodifiable(orders);
}

bool _openingFeesMatch(
  Object? aggregateValue,
  List<Map<String, dynamic>> orders,
) {
  final aggregate = _ExactDecimal.parse(aggregateValue);
  if (aggregate == null) return false;
  final fees = <_ExactDecimal>[];
  var commonScale = aggregate.scale;
  for (final order in orders) {
    final fee = _ExactDecimal.parse(order['openingFeeEstimate']);
    if (fee == null) return false;
    fees.add(fee);
    if (fee.scale > commonScale) commonScale = fee.scale;
  }
  final scaledAggregate =
      aggregate.coefficient *
      BigInt.from(10).pow(commonScale - aggregate.scale);
  final scaledFeeSum = fees.fold<BigInt>(
    BigInt.zero,
    (sum, fee) =>
        sum + fee.coefficient * BigInt.from(10).pow(commonScale - fee.scale),
  );
  return scaledAggregate == scaledFeeSum;
}

class _ExactDecimal {
  const _ExactDecimal(this.coefficient, this.scale);

  static final _pattern = RegExp(
    r'^([+-]?)(?:(\d+)(?:\.(\d*))?|\.(\d+))(?:[eE]([+-]?\d+))?$',
  );

  final BigInt coefficient;
  final int scale;

  static _ExactDecimal? parse(Object? value) {
    final text = switch (value) {
      num number => number.toString(),
      String string => string.trim(),
      _ => null,
    };
    if (text == null || text.length > 1024) return null;
    final match = _pattern.firstMatch(text);
    if (match == null) return null;
    final whole = match.group(2) ?? '0';
    final fraction = match.group(3) ?? match.group(4) ?? '';
    final exponent = int.tryParse(match.group(5) ?? '0');
    if (exponent == null || exponent.abs() > 1024) return null;
    final digits = '$whole$fraction';
    final parsedCoefficient = BigInt.tryParse(digits);
    if (parsedCoefficient == null) return null;
    var coefficient = match.group(1) == '-'
        ? -parsedCoefficient
        : parsedCoefficient;
    var scale = fraction.length - exponent;
    if (scale < 0) {
      coefficient *= BigInt.from(10).pow(-scale);
      scale = 0;
    }
    while (scale > 0 && coefficient.remainder(BigInt.from(10)) == BigInt.zero) {
      coefficient ~/= BigInt.from(10);
      scale--;
    }
    return _ExactDecimal(coefficient, scale);
  }
}

double? _positiveOrderNumber(Object? value) {
  final number = switch (value) {
    num number => number.toDouble(),
    String text => double.tryParse(text.trim()),
    _ => null,
  };
  return number != null && number.isFinite && number > 0 ? number : null;
}

double? _nonNegativeOrderNumber(Object? value) {
  final number = switch (value) {
    num number => number.toDouble(),
    String text => double.tryParse(text.trim()),
    _ => null,
  };
  return number != null && number.isFinite && number >= 0 ? number : null;
}
