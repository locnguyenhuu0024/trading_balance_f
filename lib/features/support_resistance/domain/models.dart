enum SupportResistanceMarketMode {
  spot('SPOT'),
  perpetual('SWAP');

  const SupportResistanceMarketMode(this.instrumentType);

  final String instrumentType;

  String instrumentIdFor(String baseCurrency) {
    final base = baseCurrency.trim().toUpperCase();
    return this == SupportResistanceMarketMode.spot
        ? '$base-USDT'
        : '$base-USDT-SWAP';
  }
}

enum SupportResistanceTimeframe {
  h1('H1', '1H', Duration(hours: 1)),
  h4('H4', '4H', Duration(hours: 4)),
  h6('H6', '6Hutc', Duration(hours: 6)),
  d1('D1', '1Dutc', Duration(days: 1)),
  w1('W1', '1Wutc', Duration(days: 7));

  const SupportResistanceTimeframe(this.label, this.bar, this.duration);

  final String label;
  final String bar;
  final Duration duration;

  bool isUtcAligned(DateTime timestamp) {
    if (!timestamp.isUtc || timestamp.microsecond != 0) return false;
    final millis = timestamp.millisecondsSinceEpoch;
    if (this == SupportResistanceTimeframe.w1) {
      final mondayEpoch = DateTime.utc(1969, 12, 29).millisecondsSinceEpoch;
      return (millis - mondayEpoch) % duration.inMilliseconds == 0;
    }
    return millis % duration.inMilliseconds == 0;
  }
}

enum SupportResistanceLevelSide { support, resistance }

class SupportResistanceInstrument {
  const SupportResistanceInstrument({
    required this.marketMode,
    required this.instrumentId,
    required this.baseCurrency,
  });

  final SupportResistanceMarketMode marketMode;
  final String instrumentId;
  final String baseCurrency;
}

class SupportResistanceTicker {
  const SupportResistanceTicker({
    required this.instrumentId,
    required this.lastPrice,
    required this.observedAt,
  });

  final String instrumentId;
  final double lastPrice;
  final DateTime observedAt;
}

class SupportResistanceCandle {
  const SupportResistanceCandle({
    required this.timestamp,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.timeframe,
    required this.confirmed,
  });

  final DateTime timestamp;
  final double open;
  final double high;
  final double low;
  final double close;
  final SupportResistanceTimeframe timeframe;
  final bool confirmed;

  bool get hasValidPrices =>
      open.isFinite &&
      high.isFinite &&
      low.isFinite &&
      close.isFinite &&
      open > 0 &&
      high > 0 &&
      low > 0 &&
      close > 0 &&
      high >= low &&
      high >= open &&
      high >= close &&
      low <= open &&
      low <= close;
}

class SupportResistanceLevel {
  const SupportResistanceLevel({
    required this.price,
    required this.firstTouchAt,
    required this.lastTouchAt,
    required this.touchCount,
    required this.side,
  });

  final double price;
  final DateTime firstTouchAt;
  final DateTime lastTouchAt;
  final int touchCount;
  final SupportResistanceLevelSide side;
}

class SupportResistanceAnalysis {
  const SupportResistanceAnalysis({
    required this.referencePrice,
    required this.supports,
    required this.resistances,
  });

  final double referencePrice;
  final List<SupportResistanceLevel> supports;
  final List<SupportResistanceLevel> resistances;
}

class SupportResistanceMarketSnapshot {
  const SupportResistanceMarketSnapshot({
    required this.marketMode,
    required this.instrumentId,
    required this.timeframe,
    required this.referencePrice,
    required this.fetchedAt,
    required this.candles,
    required this.analysis,
  });

  final SupportResistanceMarketMode marketMode;
  final String instrumentId;
  final SupportResistanceTimeframe timeframe;
  final double referencePrice;
  final DateTime fetchedAt;
  final List<SupportResistanceCandle> candles;
  final SupportResistanceAnalysis analysis;
}

enum SupportResistanceRepositoryFailure {
  invalidRequest,
  transport,
  rateLimited,
  invalidResponse,
  unavailableTicker,
}

class SupportResistanceRepositoryException implements Exception {
  const SupportResistanceRepositoryException({
    required this.failure,
    required this.message,
    required this.endpoint,
    this.statusCode,
    this.retryAfter,
    this.retryAt,
    this.cause,
  });

  final SupportResistanceRepositoryFailure failure;
  final String message;
  final String endpoint;
  final int? statusCode;
  final Duration? retryAfter;
  final DateTime? retryAt;
  final Object? cause;

  @override
  String toString() {
    final status = statusCode == null ? '' : ' (HTTP $statusCode)';
    return 'SupportResistanceRepositoryException$status: $message';
  }
}
