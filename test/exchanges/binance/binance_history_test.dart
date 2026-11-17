import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trading_balance_f/core/exchange/exchange_models.dart';
import 'package:trading_balance_f/core/network/request_coordinator.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/exchanges/binance/binance_adapter.dart';
import 'package:trading_balance_f/exchanges/binance/binance_client.dart';
import 'package:trading_balance_f/exchanges/binance/binance_market.dart';
import 'package:trading_balance_f/exchanges/binance/binance_private_client.dart';
import 'package:trading_balance_f/exchanges/binance/binance_reader.dart';
import 'package:trading_balance_f/features/support_resistance/data/watchlist_store.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/order_provider.dart';

class HistoryTransport implements HttpClientAdapter {
  HistoryTransport(this.respond);
  final Future<Object> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final data = await respond(options);
    return ResponseBody.fromString(
      jsonEncode(data),
      data is Map && data['code'] != null ? 400 : 200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late ValueNotifier<OkxCredentialSnapshot> state;
  late RequestCoordinator coordinator;
  setUp(() {
    state = ValueNotifier(
      const OkxCredentialSnapshot(generation: 0, rotating: false),
    );
    coordinator = RequestCoordinator(minimumSpacing: Duration.zero);
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => state.dispose());
  BinanceReader make(
    HistoryTransport transport, {
    bool web = false,
    String proxy = '',
  }) {
    final dio = Dio()..httpClientAdapter = transport;
    return BinanceReader(
      BinancePrivateClient(
        keys: BinanceKeyBundle(apiKey: 'key', apiSecret: 'secret'),
        credentialState: state,
        coordinator: coordinator,
        isWeb: web,
        proxyBaseUrl: proxy,
        dio: dio,
      ),
      BinanceMarket(BinanceClient(coordinator: coordinator, dio: dio)),
    );
  }

  bool history(RequestOptions r) => r.uri.path.endsWith('/allOrders');
  Object time() => {'serverTime': DateTime.now().millisecondsSinceEpoch};

  test(
    'selection follows positions, valued assets, then Binance watchlist',
    () async {
      SharedPreferences.setMockInitialValues({
        WatchlistStore.binanceStorageKey: jsonEncode({
          'version': 1,
          'spotInstrumentIds': ['WATCHUSDT', 'BTCUSDT'],
          'perpetualInstrumentIds': ['OTHERUSDT'],
        }),
      });
      final transport = HistoryTransport((r) async {
        switch (r.uri.path) {
          case '/fapi/v1/time':
          case '/api/v3/time':
            return time();
          case '/fapi/v3/positionRisk':
            return [
              {'symbol': 'BTCUSDT', 'positionSide': 'LONG', 'positionAmt': '1'},
            ];
          case '/fapi/v2/account':
            return {'positions': []};
          case '/fapi/v1/exchangeInfo':
            return {'symbols': []};
          case '/fapi/v3/account':
            return {'assets': []};
          case '/api/v3/account':
            return {
              'balances': [
                {'asset': 'ETH', 'free': '1', 'locked': '0'},
                {'asset': 'SOL', 'free': '1', 'locked': '0'},
                {'asset': 'USDT', 'free': '1', 'locked': '0'},
              ],
            };
          case '/sapi/v1/margin/account':
            return {'userAssets': []};
          case '/sapi/v1/margin/isolated/account':
            return {'assets': []};
          case '/api/v3/ticker/price':
            return [
              {'symbol': 'ETHUSDT', 'price': '2'},
              {'symbol': 'SOLUSDT', 'price': '3'},
            ];
          default:
            throw StateError('Unexpected ${r.uri.path}');
        }
      });
      final container = ProviderContainer(
        overrides: [
          binanceReaderProvider.overrideWith((ref) async => make(transport)),
        ],
      );
      addTearDown(container.dispose);
      const scope = ExchangeScope(
        connectionId: 'binance',
        exchange: ExchangeId.binance,
        credentialGeneration: 0,
        switchEpoch: 0,
      );
      final subscription = container.listen(
        binanceHistorySymbolsProvider(scope),
        (_, __) {},
      );
      addTearDown(subscription.close);
      expect(
        await container.read(binanceHistorySymbolsProvider(scope).future),
        ['BTCUSDT', 'SOLUSDT', 'ETHUSDT', 'WATCHUSDT', 'OTHERUSDT'],
      );
    },
  );

  test('adapter selects tab and forwards history symbols and filter', () async {
    final transport = HistoryTransport((r) async => history(r) ? [] : time());
    const scope = ExchangeScope(
      connectionId: 'binance',
      exchange: ExchangeId.binance,
      credentialGeneration: 0,
      switchEpoch: 0,
    );
    final container = ProviderContainer(
      overrides: [
        binanceReaderProvider.overrideWith((ref) async => make(transport)),
        binanceHistorySymbolsProvider(
          scope,
        ).overrideWith((ref) async => ['BTCUSDT']),
      ],
    );
    addTearDown(container.dispose);
    final result = FutureProvider.autoDispose<List<ExchangeOrder>>(
      (ref) => const BinanceAdapter().readOrders(ref, scope),
    );
    final subscription = container.listen(result, (_, __) {});
    addTearDown(subscription.close);
    expect(await container.read(result.future), isEmpty);
    expect(transport.requests, isEmpty);
    container.read(orderFilterProvider.notifier).state = 'SWAP';
    container.read(orderTabProvider.notifier).state = OrderTab.history;
    await container.read(result.future);
    expect(
      transport.requests.where(history).single.uri.queryParameters['symbol'],
      'BTCUSDT',
    );
  });

  test('history caps each product at ten and waits for each request', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    final transport = HistoryTransport((r) async {
      if (!history(r)) return time();
      if (!started.isCompleted) {
        started.complete();
        await gate.future;
      }
      return [];
    });
    final symbols = List.generate(12, (i) => 'ASSET${i}USDT');
    final pending = make(transport).readHistory('ALL', symbols);
    await started.future;
    await Future<void>.delayed(Duration.zero);
    expect(transport.requests.where(history).length, 1);
    gate.complete();
    final result = await pending;
    expect(result.symbols, symbols.take(10).toList());
    final requests = transport.requests.where(history).toList();
    expect(requests.length, 30);
    for (var product = 0; product < 3; product++) {
      expect(
        requests
            .skip(product * 10)
            .take(10)
            .map((r) => r.uri.queryParameters['symbol']),
        symbols.take(10),
      );
    }
    for (final request in requests) {
      expect(request.uri.queryParameters['symbol'], isNotEmpty);
      expect(request.uri.queryParameters['limit'], '100');
      expect(request.uri.queryParameters.containsKey('startTime'), isFalse);
      expect(request.uri.queryParameters.containsKey('endTime'), isFalse);
    }
  });

  test('empty history performs no requests', () async {
    final transport = HistoryTransport((r) async => time());
    expect(await make(transport).readHistory('ALL', []), isEmpty);
    expect(transport.requests, isEmpty);
  });
  test('web history only requests futures', () async {
    final transport = HistoryTransport((r) async => history(r) ? [] : time());
    await make(transport, web: true).readHistory('ALL', ['BTCUSDT']);
    expect(transport.requests.where(history).map((r) => r.uri.path), [
      '/fapi/v1/allOrders',
    ]);
  });
  test(
    'failed symbol is recorded and other results are sorted newest first',
    () async {
      final transport = HistoryTransport((r) async {
        if (!history(r)) return time();
        final symbol = r.uri.queryParameters['symbol'];
        if (symbol == 'BADUSDT') return {'code': -2015};
        return [
          {
            'symbol': symbol,
            'orderId': symbol,
            'time': symbol == 'OLDUSDT' ? 1 : 2,
          },
        ];
      });
      final result = await make(
        transport,
      ).readHistory('SWAP', ['OLDUSDT', 'BADUSDT', 'NEWUSDT']);
      expect(result.map((o) => o.key.nativeId), ['NEWUSDT', 'OLDUSDT']);
      expect(result.issues, ['SWAP BADUSDT unavailable']);
    },
  );
  test('web proxy includes Spot and Margin history', () async {
    final transport = HistoryTransport((r) async => history(r) ? [] : time());
    await make(
      transport,
      web: true,
      proxy: 'https://proxy.example',
    ).readHistory('ALL', ['BTCUSDT']);
    final requests = transport.requests.where(history).toList();
    expect(requests.map((r) => r.uri.path), [
      '/fapi/v1/allOrders',
      '/api/v3/allOrders',
      '/sapi/v1/margin/allOrders',
    ]);
    expect(requests.map((r) => r.uri.host), [
      'fapi.binance.com',
      'proxy.example',
      'proxy.example',
    ]);
  });
}
