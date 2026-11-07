import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/exchange/exchange_models.dart';
import 'package:trading_balance_f/core/network/request_coordinator.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/exchanges/binance/binance_client.dart';
import 'package:trading_balance_f/exchanges/binance/binance_market.dart';
import 'package:trading_balance_f/exchanges/binance/binance_private_client.dart';
import 'package:trading_balance_f/exchanges/binance/binance_reader.dart';

class Transport implements HttpClientAdapter {
  Transport(this.respond, {this.spotStatus});
  final int? spotStatus;
  final Object Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final data = respond(options);
    return ResponseBody.fromString(
      jsonEncode(data),
      options.uri.path == '/api/v3/account' && spotStatus != null
          ? spotStatus!
          : data is Map && data['code'] != null
          ? 400
          : 200,
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
  });
  tearDown(() => state.dispose());
  BinanceReader make(
    Transport transport, {
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

  Object fixture(
    RequestOptions r, {
    bool crossFails = false,
    bool allFail = false,
    bool unpriced = false,
  }) {
    final path = r.uri.path;
    if (path.endsWith('/time'))
      return {'serverTime': DateTime.now().millisecondsSinceEpoch};
    if (path == '/api/v3/ticker/price')
      return [
        {'symbol': 'BTCUSDT', 'price': '76000'},
        {'symbol': 'ETHUSDT', 'price': '2000'},
      ];
    if (allFail || (crossFails && path == '/sapi/v1/margin/account'))
      return {'code': -2015};
    if (path == '/fapi/v3/account')
      return {
        'assets': [
          {'asset': 'USDT', 'marginBalance': '1000.50'},
        ],
      };
    if (path == '/api/v3/account')
      return {
        'balances': [
          {'asset': 'BTC', 'free': '0.01', 'locked': '0'},
          {'asset': 'USDT', 'free': '100', 'locked': '0'},
          if (unpriced) {'asset': 'LDUSDT', 'free': '1', 'locked': '0'},
        ],
      };
    if (path == '/sapi/v1/margin/account')
      return {
        'userAssets': [
          {'asset': 'ETH', 'netAsset': '-0.1', 'borrowed': '0.1'},
        ],
      };
    if (path == '/sapi/v1/margin/isolated/account') return {'assets': []};
    throw StateError('Unexpected $path');
  }

  test('valuation worked example and failed cross wallet', () async {
    var result = await make(Transport((r) => fixture(r))).readAccount();
    expect(result.total, '1660.50');
    expect(result.isPartial, isFalse);
    result = await make(
      Transport((r) => fixture(r, crossFails: true)),
    ).readAccount();
    expect(result.total, '1860.50');
    expect(result.isPartial, isTrue);
    expect(result.issues, contains('Cross Margin unavailable'));
  });
  test('all wallet credential failures are terminal', () async {
    await expectLater(
      make(Transport((r) => fixture(r, allFail: true))).readAccount(),
      throwsA(
        predicate(
          (e) =>
              e is BinancePrivateException &&
              e.failure.kind == ExchangeFailureKind.credential,
        ),
      ),
    );
  });
  test('web makes zero Spot or Margin requests', () async {
    final t = Transport((r) => fixture(r));
    final result = await make(t, web: true).readAccount();
    expect(result.total, '1000.50');
    expect(
      t.requests.where(
        (r) =>
            r.uri.path.startsWith('/api/') || r.uri.path.startsWith('/sapi/'),
      ),
      isEmpty,
    );
  });
  test('unpriced assets remain listed and make total partial', () async {
    final result = await make(
      Transport((r) => fixture(r, unpriced: true)),
    ).readAccount();
    expect(result.isPartial, isTrue);
    expect(
      result.balances.singleWhere((b) => b.asset == 'LDUSDT').valueUsdt,
      isNull,
    );
  });
  test('positions join account metadata and preserve missing fields', () async {
    final t = Transport((r) {
      switch (r.uri.path) {
        case '/fapi/v1/time':
          return {'serverTime': DateTime.now().millisecondsSinceEpoch};
        case '/fapi/v3/positionRisk':
          return [
            {'symbol': 'BTCUSDT', 'positionSide': 'LONG', 'positionAmt': '1'},
            {'symbol': 'ETHUSDT', 'positionSide': 'SHORT', 'positionAmt': '-1'},
          ];
        case '/fapi/v2/account':
          return {
            'positions': [
              {
                'symbol': 'BTCUSDT',
                'positionSide': 'LONG',
                'leverage': '5',
                'isolated': true,
              },
              {'symbol': 'ETHUSDT', 'positionSide': 'SHORT'},
            ],
          };
        case '/fapi/v1/exchangeInfo':
          return {
            'symbols': [
              {'symbol': 'BTCUSDT', 'baseAsset': 'BTC', 'quoteAsset': 'USDT'},
              {'symbol': 'ETHUSDT', 'baseAsset': 'ETH', 'quoteAsset': 'USDT'},
            ],
          };
        default:
          throw StateError('unexpected request');
      }
    });
    final positions = await make(t).readPositions();
    expect(positions.first.leverage, '5');
    expect(positions.first.marginMode, 'isolated');
    expect(positions.first.key.base, 'BTC');
    expect(positions.last.leverage, isNull);
    expect(positions.last.marginMode, isNull);
  });
  test('isolated margin maps pair fields and pending order query', () async {
    final t = Transport((r) {
      final path = r.uri.path;
      if (path.endsWith('/time'))
        return {'serverTime': DateTime.now().millisecondsSinceEpoch};
      if (path == '/sapi/v1/margin/isolated/account')
        return {
          'assets': [
            {
              'symbol': 'BTCUSDT',
              'baseAsset': {
                'asset': 'BTC',
                'netAsset': '1',
                'borrowed': '0',
                'interest': '0',
              },
              'quoteAsset': {
                'asset': 'USDT',
                'netAsset': '0',
                'borrowed': '0',
                'interest': '0',
              },
              'marginLevel': '2',
              'marginRatio': '0.5',
              'liquidatePrice': '100',
              'indexPrice': '200',
            },
          ],
        };
      if (path == '/sapi/v1/margin/openOrders') return [];
      return fixture(r);
    });
    final reader = make(t);
    final account = await reader.readAccount();
    final row = account.marginRows.singleWhere((r) => r.key != null);
    expect(row.liquidation, '100');
    expect(row.marginLevel, '2');
    expect(row.marginRatio, '0.5');
    expect(row.baseNet, '1');
    await reader.readOrders('MARGIN');
    final requests = t.requests
        .where((r) => r.uri.path == '/sapi/v1/margin/openOrders')
        .toList();
    expect(requests.length, 2);
    expect(requests.last.uri.queryParameters['symbol'], 'BTCUSDT');
    expect(requests.last.uri.queryParameters['isIsolated'], 'TRUE');
  });
  test(
    'web proxy worked example routes private wallets and hides secret',
    () async {
      final t = Transport((r) => fixture(r));
      final result = await make(
        t,
        web: true,
        proxy: 'https://proxy.example',
      ).readAccount();
      expect(result.total, '1660.50');
      expect(result.isPartial, isFalse);
      expect(
        result.issues,
        isNot(contains('Spot and Margin are available in the app only')),
      );
      final wallets = t.requests.where(
        (r) =>
            r.uri.path == '/api/v3/account' || r.uri.path.startsWith('/sapi/'),
      );
      expect(wallets.length, 3);
      for (final r in wallets) {
        expect(r.uri.host, 'proxy.example');
        expect(r.uri.toString(), isNot(contains('secret')));
        expect(r.headers.toString(), isNot(contains('secret')));
      }
    },
  );
  test('proxy 451 on Spot preserves futures and marks total partial', () async {
    final t = Transport((r) => fixture(r), spotStatus: 451);
    final result = await make(
      t,
      web: true,
      proxy: 'https://proxy.example',
    ).readAccount();
    expect(result.isPartial, isTrue);
    expect(result.balances.any((b) => b.wallet == 'USD-M'), isTrue);
    expect(result.issues, contains('Spot unavailable'));
  });
  test('web proxy includes Spot and Margin pending orders', () async {
    final t = Transport((r) {
      if (r.uri.path.endsWith('/time'))
        return {'serverTime': DateTime.now().millisecondsSinceEpoch};
      if (r.uri.path == '/sapi/v1/margin/isolated/account')
        return {'assets': []};
      return <Object>[];
    });
    await make(t, web: true, proxy: 'https://proxy.example').readOrders('ALL');
    final orders = t.requests
        .where((r) => r.uri.path.endsWith('/openOrders'))
        .toList();
    expect(orders.map((r) => r.uri.host), [
      'fapi.binance.com',
      'proxy.example',
      'proxy.example',
    ]);
  });
}
