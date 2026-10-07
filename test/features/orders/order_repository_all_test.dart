import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/network/backend_data_client.dart';
import 'package:trading_balance_f/core/network/backend_data_session.dart';
import 'package:trading_balance_f/features/orders/data/trade_api_client.dart';
import 'package:trading_balance_f/features/orders/data/order_repository.dart';

void main() {
  group('OrderRepository ALL filter', () {
    test('keeps an ALL load atomic when its backend aggregate fails', () async {
      final adapter = _RecordingAdapter(failAll: true);
      final repository = _repository(adapter);

      await expectLater(
        repository.getPendingOrders(instType: 'ALL'),
        throwsA(isA<Exception>()),
      );

      expect(adapter.requestedTypes, ['ALL']);
    });

    test('does not request SPOT positions', () async {
      final adapter = _RecordingAdapter();
      final repository = _repository(adapter);

      final positions = await repository.getOpenPositions(instType: 'SPOT');

      expect(positions, isEmpty);
      expect(adapter.requestedTypes, isEmpty);
    });

    test('keeps a concrete pending filter as a single request', () async {
      final adapter = _RecordingAdapter();
      final repository = _repository(adapter);

      final orders = await repository.getPendingOrders(instType: 'SWAP');

      expect(orders, hasLength(1));
      expect(orders.single.instType, 'SWAP');
      expect(adapter.requestedTypes, ['SWAP']);
    });

    test('loads ALL positions through one backend aggregate request', () async {
      final adapter = _RecordingAdapter();
      final repository = _repository(adapter);

      final positions = await repository.getOpenPositions(instType: 'ALL');

      expect(
        positions.map((position) => position.instId),
        containsAll([
          'MARGIN-USDT-SWAP',
          'SWAP-USDT-SWAP',
          'FUTURES-USDT-SWAP',
        ]),
      );
      expect(positions, hasLength(3));
      expect(adapter.requestedTypes, ['ALL']);
    });

    test(
      'merges pending and history orders newest first with stable ties',
      () async {
        final adapter = _RecordingAdapter();
        final repository = _repository(adapter);

        final pending = await repository.getPendingOrders(instType: 'ALL');
        final history = await repository.getOrdersHistory(instType: 'ALL');
        const expectedOrder = ['MARGIN', 'FUTURES', 'SPOT', 'SWAP'];

        expect(pending.map((order) => order.instType), expectedOrder);
        expect(history.map((order) => order.instType), expectedOrder);
        expect(adapter.requestedTypes, ['ALL', 'ALL']);
      },
    );
  });
}

OrderRepository _repository(_RecordingAdapter adapter) {
  final client = BackendDataClient(
    dio: Dio()..httpClientAdapter = adapter,
    baseUrl: 'https://orders.test',
  );
  final session = BackendDataSession(
    initialSession: TradeSession(
      bearerToken: 'test-token',
      accountIdentifier: 'test-account',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    ),
  );
  return OrderRepository(client, session);
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({this.failAll = false});

  final bool failAll;
  final List<String> requestedTypes = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final instType = options.queryParameters['instType'] as String;
    requestedTypes.add(instType);

    if (failAll && instType == 'ALL') {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'Forced aggregate failure',
      );
    }

    final responseData = switch (options.path) {
      'v1/data/account/positions' => {
        'code': '0',
        'msg': '',
        'data': instType == 'ALL'
            ? [
                {'instId': 'MARGIN-USDT-SWAP'},
                {'instId': 'SWAP-USDT-SWAP'},
                {'instId': 'FUTURES-USDT-SWAP'},
              ]
            : [
                {'instId': '$instType-USDT-SWAP'},
              ],
      },
      'v1/data/trade/orders-pending' || 'v1/data/trade/orders-history' => {
        'code': '0',
        'msg': '',
        'data': instType == 'ALL'
            ? ['SPOT', 'MARGIN', 'SWAP', 'FUTURES']
                  .map(
                    (type) => {
                      'instType': type,
                      'instId': '$type-USDT',
                      'cTime': _timestampFor(type),
                    },
                  )
                  .toList()
            : [
                {
                  'instType': instType,
                  'instId': '$instType-USDT',
                  'cTime': _timestampFor(instType),
                },
              ],
      },
      _ => throw StateError('Unexpected orders endpoint: ${options.path}'),
    };

    return ResponseBody.fromString(
      jsonEncode(responseData),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}

  String _timestampFor(String instType) => switch (instType) {
    'SPOT' => '10',
    'MARGIN' => '50',
    'SWAP' => 'invalid',
    'FUTURES' => '50',
    _ => '0',
  };
}
