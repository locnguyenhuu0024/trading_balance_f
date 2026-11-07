import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trading_balance_f/core/exchange/exchange_models.dart';
import 'package:trading_balance_f/core/network/request_coordinator.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/exchanges/binance/binance_client.dart';
import 'package:trading_balance_f/exchanges/binance/binance_cost_basis.dart';
import 'package:trading_balance_f/exchanges/binance/binance_market.dart';
import 'package:trading_balance_f/exchanges/binance/binance_private_client.dart';
import 'package:trading_balance_f/exchanges/binance/binance_trade_history.dart';

class TradeClient extends BinancePrivateClient {
  TradeClient(this.snapshot, {this.available = true})
    : super(
        keys: BinanceKeyBundle(apiKey: 'key-one', apiSecret: 'secret-one'),
        credentialState: snapshot,
        coordinator: RequestCoordinator(minimumSpacing: Duration.zero),
        isWeb: !available,
      );
  final ValueNotifier<OkxCredentialSnapshot> snapshot;
  final bool available;
  final calls = <Map<String, dynamic>>[];
  Future<List<dynamic>> Function(Map<String, dynamic>)? respond;
  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic> queryParameters = const {},
  }) async {
    final query = Map<String, dynamic>.from(queryParameters)..['path'] = path;
    calls.add(query);
    return Response(
      requestOptions: RequestOptions(path: path),
      data: await respond!(query),
    );
  }
}

class TradeMarket extends BinanceMarket {
  TradeMarket(this.list)
    : super(
        BinanceClient(
          coordinator: RequestCoordinator(minimumSpacing: Duration.zero),
        ),
      );
  final Map<String, Map<String, String>> list;
  @override
  Future<Map<String, Map<String, String>>> instruments(String product) async =>
      list;
}

Map<String, dynamic> trade(
  int id, {
  String qty = '1',
  String quote = '100',
  String commission = '0',
  String asset = 'USDT',
  bool buy = true,
}) => {
  'id': id,
  'qty': qty,
  'quoteQty': quote,
  'commission': commission,
  'commissionAsset': asset,
  'isBuyer': buy,
};

void main() {
  late SharedPreferences prefs;
  late ValueNotifier<OkxCredentialSnapshot> generation;
  late TradeClient client;
  late DateTime now;
  late BinanceCostStore store;
  late TradeMarket market;
  late BinanceCostController controller;
  const btc = AccountSnapshot(
    balances: [AssetBalance(wallet: 'Spot', asset: 'BTC', valueUsdt: '100')],
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    generation = ValueNotifier(
      const OkxCredentialSnapshot(generation: 0, rotating: false),
    );
    client = TradeClient(generation);
    store = BinanceCostStore(prefs, 'key-one');
    market = TradeMarket({
      'BTCUSDT': {'base': 'BTC', 'quote': 'USDT'},
      'ETHUSDT': {'base': 'ETH', 'quote': 'USDT'},
    });
    now = DateTime.utc(2026);
    controller = BinanceCostController(client, market, store, clock: () => now);
  });
  tearDown(() {
    controller.dispose();
    generation.dispose();
  });

  test('second run resumes after stored id and folds worked example', () async {
    client.respond = (q) async => q['fromId'] == 0
        ? [
            trade(0, qty: '1', quote: '100', commission: '0.001', asset: 'BTC'),
            trade(1, quote: '200', commission: '0.2'),
          ]
        : [trade(2, qty: '0.5', quote: '150', buy: false)];
    await controller.run(btc);
    await controller.run(btc);
    expect(client.calls.length, 1);
    now = now.add(const Duration(seconds: 60));
    await controller.run(btc);
    expect(client.calls.map((e) => e['fromId']), [0, 2]);
    final cost = store
        .read(const BinanceCostSymbol('Spot', 'BTCUSDT', 'BTC', 100))!
        .cost;
    expect(cost.quantity, closeTo(1.499, 0.000001));
    expect(cost.cost, closeTo(225.1125, 0.0001));
  });

  test('30 page budget persists unfinished state and resumes', () async {
    client.respond = (q) async =>
        List.generate(1000, (i) => trade((q['fromId'] as int) + i));
    await controller.run(btc);
    expect(client.calls.length, 30);
    expect(controller.state.symbols['Spot:BTCUSDT']!.completed, isFalse);
    now = now.add(const Duration(seconds: 60));
    client.respond = (_) async => [];
    await controller.run(btc);
    expect(client.calls.last['fromId'], 30000);
  });

  test('top 20 eligible holdings and isolated route', () async {
    for (var i = 0; i < 22; i++) {
      market.list['A${i}USDT'] = {'base': 'A$i', 'quote': 'USDT'};
    }
    final account = AccountSnapshot(
      balances: [
        for (var i = 0; i < 22; i++)
          AssetBalance(wallet: 'Spot', asset: 'A$i', valueUsdt: '$i'),
        const AssetBalance(wallet: 'Spot', asset: 'USDT', valueUsdt: '10000'),
        const AssetBalance(
          wallet: 'Spot',
          asset: 'MISSING',
          valueUsdt: '10000',
        ),
      ],
    );
    client.respond = (_) async => [];
    await controller.run(account);
    expect(client.calls.length, 20);
    expect(client.calls.any((q) => q['symbol'] == 'A0USDT'), isFalse);
    now = now.add(const Duration(seconds: 60));
    await controller.run(
      const AccountSnapshot(
        marginRows: [
          MarginAccountRow(
            key: InstrumentKey(
              exchange: ExchangeId.binance,
              product: 'MARGIN',
              nativeId: 'BTCUSDT',
              base: 'BTC',
              quote: 'USDT',
            ),
            baseNet: '1',
            indexPrice: '100',
          ),
        ],
      ),
    );
    expect(client.calls.last['isIsolated'], 'TRUE');
    expect(client.calls.last['path'], '/sapi/v1/margin/myTrades');
  });

  test('failure isolates symbol; credential failure stops run', () async {
    const account = AccountSnapshot(
      balances: [
        AssetBalance(wallet: 'Spot', asset: 'BTC', valueUsdt: '200'),
        AssetBalance(wallet: 'Spot', asset: 'ETH', valueUsdt: '100'),
      ],
    );
    await store.write(
      const BinanceCostSymbol('Spot', 'BTCUSDT', 'BTC', 0),
      const BinanceSymbolCost(
        CostState(quantity: 2, cost: 100, lastTradeId: 4),
        completed: true,
      ),
    );
    client.respond = (q) async {
      if (q['symbol'] == 'BTCUSDT') return [trade(5, qty: '0')];
      return [trade(0)];
    };
    await controller.run(account);
    expect(controller.state.symbols['Spot:BTCUSDT']!.stale, isTrue);
    expect(controller.state.symbols['Spot:BTCUSDT']!.cost.lastTradeId, 4);
    expect(controller.state.symbols['Spot:ETHUSDT']!.cost.lastTradeId, 0);
    now = now.add(const Duration(seconds: 60));
    client.calls.clear();
    client.respond = (_) async => throw const BinancePrivateException(
      ExchangeFailure(ExchangeFailureKind.credential),
    );
    await controller.run(account);
    expect(client.calls.length, 1);
  });

  test('rotation discards page and unavailable client does no work', () async {
    final pending = Completer<List<dynamic>>();
    client.respond = (_) => pending.future;
    final run = controller.run(btc);
    await Future<void>.delayed(Duration.zero);
    generation.value = const OkxCredentialSnapshot(
      generation: 1,
      rotating: true,
    );
    pending.complete([trade(0)]);
    await run;
    expect(prefs.getKeys(), isEmpty);
    final unavailable = BinanceCostController(
      TradeClient(generation, available: false),
      market,
      store,
    );
    expect(unavailable.state.available, isFalse);
    await unavailable.run(btc);
    unavailable.dispose();
  });

  test('store separates keys, contains no secrets, and clears all', () async {
    final symbol = const BinanceCostSymbol('Spot', 'BTCUSDT', 'BTC', 1);
    await store.write(
      symbol,
      const BinanceSymbolCost(
        CostState(quantity: 1, cost: 100, lastTradeId: 1),
      ),
    );
    expect(BinanceCostStore(prefs, 'key-two').read(symbol), isNull);
    expect(prefs.getKeys().join(), isNot(contains('key-one')));
    expect(
      prefs.getString(prefs.getKeys().single),
      isNot(contains('secret-one')),
    );
    await BinanceCostStore.clearAll();
    expect(prefs.getKeys(), isEmpty);
  });
}
