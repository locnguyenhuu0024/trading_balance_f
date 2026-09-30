import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/orders/data/order_repository.dart';

void main() {
  group('OrderRepository ALL filter', () {
    test('keeps ALL loads atomic when one pending subtype fails', () async {
      final adapter = _RecordingAdapter(failInstType: 'FUTURES');
      final repository = OrderRepository(_dioWith(adapter));

      await expectLater(
        repository.getPendingOrders(instType: 'ALL'),
        throwsA(isA<Exception>()),
      );

      expect(adapter.requestedTypes, hasLength(4));
      expect(
        adapter.requestedTypes,
        containsAll(['SPOT', 'MARGIN', 'SWAP', 'FUTURES']),
      );
      expect(adapter.requestedTypes, isNot(contains('ALL')));
    });

    test('does not request SPOT positions', () async {
      final adapter = _RecordingAdapter();
      final repository = OrderRepository(_dioWith(adapter));

      final positions = await repository.getOpenPositions(instType: 'SPOT');

      expect(positions, isEmpty);
      expect(adapter.requestedTypes, isEmpty);
    });

    test('keeps a concrete pending filter as a single request', () async {
      final adapter = _RecordingAdapter();
      final repository = OrderRepository(_dioWith(adapter));

      final orders = await repository.getPendingOrders(instType: 'SWAP');

      expect(orders, hasLength(1));
      expect(orders.single.instType, 'SWAP');
      expect(adapter.requestedTypes, ['SWAP']);
    });

    test('merges ALL positions from margin, swap, and futures', () async {
      final adapter = _RecordingAdapter();
      final repository = OrderRepository(_dioWith(adapter));

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
      expect(adapter.requestedTypes, hasLength(3));
      expect(
        adapter.requestedTypes,
        containsAll(['MARGIN', 'SWAP', 'FUTURES']),
      );
      expect(adapter.requestedTypes, isNot(contains('SPOT')));
      expect(adapter.requestedTypes, isNot(contains('ALL')));
    });

    test(
      'merges pending and history orders newest first with stable ties',
      () async {
        final adapter = _RecordingAdapter();
        final repository = OrderRepository(_dioWith(adapter));

        final pending = await repository.getPendingOrders(instType: 'ALL');
        final history = await repository.getOrdersHistory(instType: 'ALL');
        const expectedOrder = ['MARGIN', 'FUTURES', 'SPOT', 'SWAP'];

        expect(pending.map((order) => order.instType), expectedOrder);
        expect(history.map((order) => order.instType), expectedOrder);
        expect(adapter.requestedTypes, hasLength(8));
        expect(adapter.requestedTypes, isNot(contains('ALL')));
      },
    );
  });
}

Dio _dioWith(_RecordingAdapter adapter) {
  return Dio(BaseOptions(baseUrl: 'https://orders.test'))
    ..httpClientAdapter = adapter;
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({this.failInstType});

  final String? failInstType;
  final List<String> requestedTypes = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final instType = options.queryParameters['instType'] as String;
    requestedTypes.add(instType);

    if (instType == failInstType) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'Forced failure for $instType',
      );
    }

    final responseData = switch (options.path) {
      '/api/v5/account/positions' => {
        'code': '0',
        'msg': '',
        'data': [
          {'instId': '$instType-USDT-SWAP'},
        ],
      },
      '/api/v5/trade/orders-pending' || '/api/v5/trade/orders-history' => {
        'code': '0',
        'msg': '',
        'data': [
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
