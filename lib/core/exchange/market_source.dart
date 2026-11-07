import '../../features/support_resistance/domain/models.dart';

class MarketRow {
  const MarketRow({
    required this.instrumentId,
    required this.baseCurrency,
    required this.last,
    required this.open24h,
    required this.quoteVolume,
  });
  final String instrumentId, baseCurrency;
  final double last, open24h, quoteVolume;
}

typedef RawCandle = List<dynamic>;

abstract class MarketSource {
  Future<List<MarketRow>> topTickers(String product);
  Future<List<SupportResistanceInstrument>> getInstruments({
    required SupportResistanceMarketMode marketMode,
  });
  Future<SupportResistanceTicker> getTicker({
    required SupportResistanceMarketMode marketMode,
    required String instrumentId,
  });
  Future<List<SupportResistanceCandle>> getCandles({
    required SupportResistanceMarketMode marketMode,
    required String instrumentId,
    required SupportResistanceTimeframe timeframe,
  });
  Future<SupportResistanceMarketSnapshot> loadLevels({
    required SupportResistanceMarketMode marketMode,
    required String instrumentId,
    required SupportResistanceTimeframe timeframe,
  });
  Future<List<RawCandle>> fractalCandles({
    required String coin,
    required String bar,
    required int limit,
    required int endTime,
  });
}
