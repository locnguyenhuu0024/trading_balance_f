import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/network/request_coordinator.dart';
import 'package:trading_balance_f/exchanges/binance/binance_client.dart';
import 'package:trading_balance_f/exchanges/binance/binance_market.dart';
import 'package:trading_balance_f/features/support_resistance/domain/models.dart';

class FixtureAdapter implements HttpClientAdapter {
  final paths = <String>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? stream,
    Future<void>? cancel,
  ) async {
    paths.add(options.path);
    final Object data;
    if (options.path.endsWith('exchangeInfo')) {
      data = {
        'symbols': [
          {
            'symbol': 'BTCUSDT',
            'baseAsset': 'BTC',
            'quoteAsset': 'USDT',
            'status': 'TRADING',
            'contractType': 'PERPETUAL',
          },
          {
            'symbol': 'ETHUSDT',
            'baseAsset': 'ETH',
            'quoteAsset': 'USDT',
            'status': 'TRADING',
            'contractType': 'CURRENT_QUARTER',
          },
          {
            'symbol': 'OLDUSDT',
            'baseAsset': 'OLD',
            'quoteAsset': 'USDT',
            'status': 'BREAK',
            'contractType': 'PERPETUAL',
          },
        ],
      };
    } else if (options.path.endsWith('klines')) {
      data = [
        [1704067200000, '10', '13', '9', '12', '99'],
        [1704153600000, '10', '14', '8', '12', '99'],
        [1704240000000, '10', '20', '5', '12', '99'],
        [1704326400000, '10', '14', '8', '12', '99'],
        [1704412800000, '10', '13', '9', '12', '99'],
      ];
    } else if (options.queryParameters.containsKey('symbol')) {
      data = {'symbol': 'BTCUSDT', 'lastPrice': '12'};
    } else {
      data = [
        for (var i = 0; i < 55; i++)
          {
            'symbol': 'COIN${i}USDT',
            'lastPrice': '1',
            'openPrice': '1',
            'quoteVolume': '${10000000 + i}',
          },
        {
          'symbol': 'BTCUSDT',
          'lastPrice': '12',
          'openPrice': '10',
          'quoteVolume': '6000000',
        },
        {
          'symbol': 'ETHUSDT',
          'lastPrice': '4',
          'openPrice': '3',
          'quoteVolume': '9000000',
        },
        {
          'symbol': 'LOWUSDT',
          'lastPrice': '1',
          'openPrice': '1',
          'quoteVolume': '5000000',
        },
        {
          'symbol': 'BAD-USDT',
          'lastPrice': '1',
          'openPrice': '1',
          'quoteVolume': '90000000',
        },
      ];
    }
    return ResponseBody.fromString(
      jsonEncode(data),
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'spot and USD-M instruments, sorted tickers and kline indexes',
    () async {
      final fixture = FixtureAdapter();
      final market = BinanceMarket(
        BinanceClient(
          coordinator: RequestCoordinator(minimumSpacing: Duration.zero),
          dio: Dio()..httpClientAdapter = fixture,
        ),
        clock: () => DateTime.utc(2024, 1, 10),
      );
      expect(
        (await market.getInstruments(
          marketMode: SupportResistanceMarketMode.spot,
        )).map((e) => e.instrumentId),
        ['BTCUSDT', 'ETHUSDT'],
      );
      expect(
        (await market.getInstruments(
          marketMode: SupportResistanceMarketMode.perpetual,
        )).map((e) => e.instrumentId),
        ['BTCUSDT'],
      );
      final top = await market.topTickers('USD-M');
      expect(top.length, 50);
      expect(top.first.baseCurrency, 'COIN54');
      expect(top.last.baseCurrency, 'COIN5');
      expect(top.every((row) => row.quoteVolume > 5000000), isTrue);
      final candle = (await market.getCandles(
        marketMode: SupportResistanceMarketMode.spot,
        instrumentId: 'BTCUSDT',
        timeframe: SupportResistanceTimeframe.d1,
      ))[2];
      expect(
        [candle.open, candle.high, candle.low, candle.close],
        [10, 20, 5, 12],
      );
      final levels = await market.loadLevels(
        marketMode: SupportResistanceMarketMode.spot,
        instrumentId: 'BTCUSDT',
        timeframe: SupportResistanceTimeframe.d1,
      );
      expect(levels.analysis.supports.map((e) => e.price), [5]);
      expect(levels.analysis.resistances.map((e) => e.price), [20]);
      final raw = (await market.fractalCandles(
        coin: 'BTC',
        bar: '1Dutc',
        limit: 1,
        endTime: 1704153600000,
      )).last;
      expect(raw.sublist(0, 6), ['1704067200000', '10', '13', '9', '12', '99']);
      expect(fixture.paths.any((p) => p.contains('/fapi/v1/')), isTrue);
      expect(fixture.paths.any((p) => p.contains('/api/v3/')), isTrue);
    },
  );
}
