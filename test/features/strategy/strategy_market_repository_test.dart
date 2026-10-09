import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/network/backend_data_client.dart';
import 'package:trading_balance_f/core/network/request_coordinator.dart';
import 'package:trading_balance_f/features/strategy/data/strategy_market_repository.dart';
import 'package:trading_balance_f/features/strategy/domain/strategy_models.dart';

void main() {
  final now = DateTime.utc(2035, 1, 1);

  test('excludes open, malformed, duplicate, and wrong-swap candles', () async {
    final base = DateTime.utc(2030, 1, 1);
    final candle = (int index, {String confirm = '1'}) => [
      (base.add(Duration(hours: index * 12))).millisecondsSinceEpoch.toString(),
      '100.000',
      '110.0100',
      '90.0000',
      '100.00',
      '0',
      '0',
      '0',
      confirm,
    ];
    final malformed = candle(3)..[2] = '80';
    final adapter = _OkxAdapter((request) {
      if (request.uri.path.endsWith('/candles')) {
        return [
          candle(8, confirm: '0'),
          {
            'instId': 'ETH-USDT-SWAP',
            'ts': candle(7).first,
            'o': '100.000',
            'h': '110.0100',
            'l': '90.0000',
            'c': '100.00',
            'confirm': '1',
          },
          candle(6),
          candle(6),
          malformed,
          candle(2),
          candle(1),
          candle(0),
        ];
      }
      return const [];
    });
    final repository = _repository(adapter, now);

    final candles = await repository.getCandles(
      instrumentId: 'BTC-USDT-SWAP',
      interval: StrategyInterval.h12,
    );

    expect(candles, hasLength(4));
    expect(
      candles.map((item) => item.timestamp),
      orderedEquals([
        base,
        base.add(const Duration(hours: 12)),
        base.add(const Duration(hours: 24)),
        base.add(const Duration(hours: 72)),
      ]),
    );
    expect(candles.first.openText, '100.000');
    expect(candles.first.highText, '110.0100');
    expect(candles.first.lowText, '90.0000');
    expect(candles.first.closeText, '100.00');
  });

  test('requests only live linear USDT swaps from the catalog', () async {
    final adapter = _OkxAdapter(
      (request) => [
        {
          'instType': 'SWAP',
          'state': 'live',
          'settleCcy': 'USDT',
          'ctType': 'linear',
          'instId': 'BTC-USDT-SWAP',
          'baseCcy': 'BTC',
          'tickSz': '0.0100',
        },
        {
          'instType': 'SWAP',
          'state': 'live',
          'settleCcy': 'USDT',
          'ctType': 'linear',
          'instId': 'ETH-USDT-SWAP',
          'baseCcy': '',
          'tickSz': '0.01',
        },
        {
          'instType': 'SWAP',
          'state': 'live',
          'settleCcy': 'USDT',
          'ctType': 'linear',
          'instId': 'SOL-USDT-SWAP',
          'tickSz': '0.0001',
        },
        {
          'instType': 'SWAP',
          'state': 'live',
          'settleCcy': 'USDT',
          'ctType': 'linear',
          'instId': 'XRP-USDT-SWAP',
          'baseCcy': 'DOGE',
        },
        {
          'instType': 'SWAP',
          'state': 'live',
          'settleCcy': 'BTC',
          'ctType': 'inverse',
          'instId': 'BTC-USD-SWAP',
          'baseCcy': 'BTC',
        },
        {
          'instType': 'SPOT',
          'state': 'live',
          'quoteCcy': 'USDT',
          'instId': 'ETH-USDT',
          'baseCcy': 'ETH',
        },
        {
          'instType': 'SWAP',
          'state': 'suspend',
          'settleCcy': 'USDT',
          'ctType': 'linear',
          'instId': 'SOL-USDT-SWAP',
          'baseCcy': 'SOL',
        },
      ],
    );
    final repository = _repository(adapter, now);

    final instruments = await repository.getInstruments();

    expect(instruments.map((item) => item.instrumentId), [
      'BTC-USDT-SWAP',
      'ETH-USDT-SWAP',
      'SOL-USDT-SWAP',
    ]);
    expect(instruments.map((item) => item.base), ['BTC', 'ETH', 'SOL']);
    expect(instruments.map((item) => item.tickSizeText), [
      '0.0100',
      '0.01',
      '0.0001',
    ]);
    expect(adapter.requests.single.uri.queryParameters['instType'], 'SWAP');
  });

  test('accepts public ticker data up to fifteen seconds old', () async {
    final exchangeTimestamp = now.subtract(const Duration(seconds: 10));
    final adapter = _OkxAdapter(
      (_) => [
        {
          'instId': 'BTC-USDT-SWAP',
          'last': '65000.00001000',
          'ts': exchangeTimestamp.millisecondsSinceEpoch.toString(),
        },
      ],
    );
    final repository = _repository(adapter, now);

    final ticker = await repository.getTicker(instrumentId: 'BTC-USDT-SWAP');

    expect(ticker.observedAt, exchangeTimestamp);
    expect(ticker.priceText, '65000.00001000');
    expect(
      ticker.isFreshAt(now, maximumAge: const Duration(seconds: 15)),
      isTrue,
    );
    expect(ticker.isFreshAt(now), isFalse);
  });

  test('rejects public ticker data older than fifteen seconds', () async {
    final exchangeTimestamp = now.subtract(const Duration(seconds: 16));
    final adapter = _OkxAdapter(
      (_) => [
        {
          'instId': 'BTC-USDT-SWAP',
          'last': '65000',
          'ts': exchangeTimestamp.millisecondsSinceEpoch.toString(),
        },
      ],
    );
    final repository = _repository(adapter, now);

    await expectLater(
      repository.getTicker(instrumentId: 'BTC-USDT-SWAP'),
      throwsA(isA<StrategyMarketException>()),
    );
  });

  test(
    'does not restamp an exchange ticker when the response completes',
    () async {
      final exchangeTimestamp = now.subtract(const Duration(milliseconds: 900));
      final adapter = _OkxAdapter(
        (_) => [
          {
            'instId': 'BTC-USDT-SWAP',
            'last': '65000',
            'ts': exchangeTimestamp.millisecondsSinceEpoch.toString(),
          },
        ],
      );
      final ticker = await _repository(
        adapter,
        now,
      ).getTicker(instrumentId: 'BTC-USDT-SWAP');

      expect(ticker.observedAt, exchangeTimestamp);
      expect(ticker.isFreshAt(now), isTrue);
    },
  );

  test('rejects an out-of-order ticker exchange timestamp', () async {
    var exchangeTimestamp = now.subtract(const Duration(seconds: 1));
    final adapter = _OkxAdapter(
      (_) => [
        {
          'instId': 'BTC-USDT-SWAP',
          'last': '65000',
          'ts': exchangeTimestamp.millisecondsSinceEpoch.toString(),
        },
      ],
    );
    final repository = _repository(adapter, now);

    final first = await repository.getTicker(instrumentId: 'BTC-USDT-SWAP');
    exchangeTimestamp = now.subtract(const Duration(seconds: 2));

    await expectLater(
      repository.getTicker(instrumentId: 'BTC-USDT-SWAP'),
      throwsA(isA<StrategyMarketException>()),
    );
    expect(first.observedAt, exchangeTimestamp.add(const Duration(seconds: 1)));
  });

  test('caps the scan at the newest 500 candles across OKX pages', () async {
    final base = DateTime.utc(2030, 1, 1);
    final all = List.generate(
      501,
      (index) => [
        base.add(Duration(hours: index * 12)).millisecondsSinceEpoch.toString(),
        '100',
        '110',
        '90',
        '100',
        '0',
        '0',
        '0',
        '1',
      ],
    );
    final adapter = _OkxAdapter((request) {
      final cursor = request.uri.queryParameters['after'];
      final page = cursor == null
          ? all.sublist(201).reversed.toList()
          : all.sublist(0, 201).reversed.toList();
      return page;
    });
    final repository = _repository(adapter, now);

    final candles = await repository.getCandles(
      instrumentId: 'BTC-USDT-SWAP',
      interval: StrategyInterval.h12,
    );

    expect(candles, hasLength(500));
    expect(candles.first.timestamp, base.add(const Duration(hours: 12)));
    expect(candles.last.timestamp, base.add(const Duration(hours: 500 * 12)));
    expect(adapter.requests, hasLength(2));
  });
}

StrategyMarketRepository _repository(_OkxAdapter adapter, DateTime now) =>
    StrategyMarketRepository(
      BackendDataClient(
        dio: Dio()..httpClientAdapter = adapter,
        baseUrl: 'https://data.example',
      ),
      requestCoordinator: RequestCoordinator(
        minimumSpacing: Duration.zero,
        delay: (_) async {},
      ),
      clock: () => now,
    );

class _OkxAdapter implements HttpClientAdapter {
  _OkxAdapter(this.respond);

  final List<Object?> Function(RequestOptions request) respond;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({'code': '0', 'data': respond(options)}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
