import '../../core/exchange/market_source.dart';
import '../../features/support_resistance/domain/level_calculator.dart';
import '../../features/support_resistance/domain/models.dart';
import 'binance_client.dart';

class BinanceMarket implements MarketSource {
  BinanceMarket(
    this.client, {
    DateTime Function()? clock,
    this.calculator = const SupportResistanceCalculator(),
  }) : clock = clock ?? DateTime.now;
  final BinanceClient client;
  final DateTime Function() clock;
  final SupportResistanceCalculator calculator;
  String _prefix(SupportResistanceMarketMode mode) =>
      mode == SupportResistanceMarketMode.spot ? '/api/v3' : '/fapi/v1';
  double _number(Object? value) => double.parse(value.toString());
  String _symbol(String id) {
    final value = id.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]+USDT$').hasMatch(value))
      throw ArgumentError.value(id, 'instrumentId');
    return value;
  }

  Future<Map<String, double>> valuationPrices() async {
    final response = await client.get('/api/v3/ticker/price');
    return {
      for (final row in response.data as List)
        if (row is Map && double.tryParse('${row['price']}') != null)
          '${row['symbol']}': double.parse('${row['price']}'),
    };
  }

  Future<Map<String, Map<String, String>>> instruments(String product) async {
    final prefix = product == 'SWAP' ? '/fapi/v1' : '/api/v3';
    final response = await client.get('$prefix/exchangeInfo');
    return {
      for (final row in response.data['symbols'] as List)
        '${row['symbol']}': {
          'base': '${row['baseAsset']}',
          'quote': '${row['quoteAsset']}',
        },
    };
  }

  @override
  Future<List<MarketRow>> topTickers(String product) async {
    final prefix = product == 'SPOT' ? '/api/v3' : '/fapi/v1';
    final response = await client.get('$prefix/ticker/24hr');
    final rows = <MarketRow>[];
    for (final item in response.data as List) {
      final id = item['symbol'] as String;
      if (!RegExp(r'^[A-Z0-9]+USDT$').hasMatch(id)) continue;
      final volume = double.tryParse(item['quoteVolume'].toString()) ?? 0;
      if (volume <= 5000000) continue;
      rows.add(
        MarketRow(
          instrumentId: id,
          baseCurrency: id.substring(0, id.length - 4),
          last: _number(item['lastPrice']),
          open24h: _number(item['openPrice']),
          quoteVolume: volume,
        ),
      );
    }
    rows.sort((a, b) => b.quoteVolume.compareTo(a.quoteVolume));
    return rows.take(50).toList();
  }

  @override
  Future<List<SupportResistanceInstrument>> getInstruments({
    required SupportResistanceMarketMode marketMode,
  }) async {
    final response = await client.get('${_prefix(marketMode)}/exchangeInfo');
    final result = <SupportResistanceInstrument>[];
    for (final row in response.data['symbols'] as List) {
      if (row['status'] != 'TRADING' ||
          row['quoteAsset'] != 'USDT' ||
          (marketMode == SupportResistanceMarketMode.perpetual &&
              row['contractType'] != 'PERPETUAL'))
        continue;
      final id = row['symbol'] as String;
      if (!RegExp(r'^[A-Z0-9]+USDT$').hasMatch(id)) continue;
      result.add(
        SupportResistanceInstrument(
          marketMode: marketMode,
          instrumentId: id,
          baseCurrency: row['baseAsset'] as String,
        ),
      );
    }
    result.sort((a, b) => a.instrumentId.compareTo(b.instrumentId));
    return result;
  }

  @override
  Future<SupportResistanceTicker> getTicker({
    required SupportResistanceMarketMode marketMode,
    required String instrumentId,
  }) async {
    final id = _symbol(instrumentId);
    final response = await client.get(
      '${_prefix(marketMode)}/ticker/24hr',
      queryParameters: {'symbol': id},
    );
    return SupportResistanceTicker(
      instrumentId: id,
      lastPrice: _number(response.data['lastPrice']),
      observedAt: clock().toUtc(),
    );
  }

  @override
  Future<List<SupportResistanceCandle>> getCandles({
    required SupportResistanceMarketMode marketMode,
    required String instrumentId,
    required SupportResistanceTimeframe timeframe,
  }) async {
    final id = _symbol(instrumentId);
    final interval = switch (timeframe) {
      SupportResistanceTimeframe.h1 => '1h',
      SupportResistanceTimeframe.h4 => '4h',
      SupportResistanceTimeframe.h6 => '6h',
      SupportResistanceTimeframe.d1 => '1d',
      SupportResistanceTimeframe.w1 => '1w',
    };
    final response = await client.get(
      '${_prefix(marketMode)}/klines',
      queryParameters: {'symbol': id, 'interval': interval, 'limit': 301},
    );
    final now = clock().toUtc();
    final result = <SupportResistanceCandle>[];
    for (final row in response.data as List) {
      final time = DateTime.fromMillisecondsSinceEpoch(
        int.parse(row[0].toString()),
        isUtc: true,
      );
      if (time.add(timeframe.duration).isAfter(now)) continue;
      final candle = SupportResistanceCandle(
        timestamp: time,
        open: _number(row[1]),
        high: _number(row[2]),
        low: _number(row[3]),
        close: _number(row[4]),
        timeframe: timeframe,
        confirmed: true,
      );
      if (!timeframe.isUtcAligned(time) || !candle.hasValidPrices)
        throw FormatException('Invalid candle');
      result.add(candle);
    }
    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result.length > 300 ? result.sublist(result.length - 300) : result;
  }

  @override
  Future<SupportResistanceMarketSnapshot> loadLevels({
    required SupportResistanceMarketMode marketMode,
    required String instrumentId,
    required SupportResistanceTimeframe timeframe,
  }) async {
    final ticker = await getTicker(
      marketMode: marketMode,
      instrumentId: instrumentId,
    );
    final candles = await getCandles(
      marketMode: marketMode,
      instrumentId: instrumentId,
      timeframe: timeframe,
    );
    return SupportResistanceMarketSnapshot(
      marketMode: marketMode,
      instrumentId: ticker.instrumentId,
      timeframe: timeframe,
      referencePrice: ticker.lastPrice,
      fetchedAt: clock().toUtc(),
      candles: candles,
      analysis: calculator.calculate(
        candles: candles,
        referencePrice: ticker.lastPrice,
      ),
    );
  }

  @override
  Future<List<RawCandle>> fractalCandles({
    required String coin,
    required String bar,
    required int limit,
    required int endTime,
  }) async {
    final interval = switch (bar) {
      '1H' => '1h',
      '4H' => '4h',
      '1Dutc' => '1d',
      '1Wutc' => '1w',
      '1Mutc' => '1M',
      _ => throw ArgumentError.value(bar, 'bar'),
    };
    final response = await client.get(
      '/api/v3/klines',
      queryParameters: {
        'symbol': _symbol('${coin.toUpperCase()}USDT'),
        'interval': interval,
        'limit': limit,
        'endTime': endTime - 1,
      },
    );
    return (response.data as List).reversed
        .map((row) => (row as List).map((value) => value.toString()).toList())
        .toList();
  }
}
