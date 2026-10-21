import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/network/okx_data_client.dart';
import 'package:trading_balance_f/core/network/request_coordinator.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/features/orders/data/order_repository.dart';

void main() {
  group('OrderRepository ALL native filters', () {
    test(
      'history ALL rejects the whole result when one category fails',
      () async {
        final adapter = _RecordingAdapter(failHistoryType: 'SWAP');
        final harness = _repository(adapter);
        addTearDown(harness.dispose);

        await expectLater(
          harness.repository.getOrdersHistory(instType: 'ALL'),
          throwsA(isA<OkxDataException>()),
        );

        expect(
          adapter.requests.map(
            (request) => request.uri.queryParameters['instType'],
          ),
          ['SPOT', 'MARGIN', 'SWAP'],
        );
        expect(
          adapter.requests.every(
            (request) => request.uri.path == '/api/v5/trade/orders-history',
          ),
          isTrue,
        );
      },
    );

    test('SPOT positions return empty without a private request', () async {
      final adapter = _RecordingAdapter();
      final harness = _repository(adapter);
      addTearDown(harness.dispose);

      expect(
        await harness.repository.getOpenPositions(instType: 'SPOT'),
        isEmpty,
      );
      expect(adapter.requests, isEmpty);
    });

    test('concrete pending filter stays a single native request', () async {
      final adapter = _RecordingAdapter();
      final harness = _repository(adapter);
      addTearDown(harness.dispose);

      final orders = await harness.repository.getPendingOrders(
        instType: 'SWAP',
      );

      expect(orders, hasLength(1));
      expect(orders.single.instType, 'SWAP');
      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.uri.path, '/api/v5/trade/orders-pending');
      expect(adapter.requests.single.uri.queryParameters['instType'], 'SWAP');
    });

    test('ALL positions and pending requests omit instType', () async {
      final adapter = _RecordingAdapter();
      final harness = _repository(adapter);
      addTearDown(harness.dispose);

      final positions = await harness.repository.getOpenPositions(
        instType: 'ALL',
      );
      final pending = await harness.repository.getPendingOrders(
        instType: 'ALL',
      );

      expect(positions, hasLength(3));
      expect(
        positions.map((position) => position.instId),
        containsAll([
          'MARGIN-USDT-SWAP',
          'SWAP-USDT-SWAP',
          'FUTURES-USDT-SWAP',
        ]),
      );
      expect(pending.map((order) => order.instType), [
        'MARGIN',
        'FUTURES',
        'SPOT',
        'SWAP',
      ]);
      expect(adapter.requests, hasLength(2));
      expect(adapter.requests[0].uri.path, '/api/v5/account/positions');
      expect(adapter.requests[0].uri.queryParameters, isEmpty);
      expect(adapter.requests[1].uri.path, '/api/v5/trade/orders-pending');
      expect(adapter.requests[1].uri.queryParameters, isEmpty);
    });

    test(
      'native position aliases are display-only and keep rows distinct',
      () async {
        final adapter = _RecordingAdapter(
          positionRows: const [
            {
              'instType': 'MARGIN',
              'instId': 'BTC-USDT',
              'posSide': 'net',
              'mgnMode': 'cross',
              'posId': 'native-position-1',
              'ccy': 'USDT',
              'posCcy': 'BTC',
              'identity': {'positionId': 'untrusted'},
              'eligibleActions': {
                'closePosition': {'eligible': true},
              },
            },
            {
              'instType': 'MARGIN',
              'instId': 'BTC-USDT',
              'posSide': 'net',
              'mgnMode': 'isolated',
              'posId': 'native-position-2',
              'ccy': 'USDT',
              'posCcy': 'BTC',
            },
          ],
        );
        final harness = _repository(adapter);
        addTearDown(harness.dispose);

        final positions = await harness.repository.getOpenPositions(
          instType: 'ALL',
        );

        expect(positions, hasLength(2));
        expect(positions.map((position) => position.positionId), [
          'native-position-1',
          'native-position-2',
        ]);
        expect(positions.first.marginCurrency, 'USDT');
        expect(positions.first.positionCurrency, 'BTC');
        expect(positions.first.identity, isEmpty);
        expect(positions.first.eligibleActions, isEmpty);
      },
    );

    test(
      'history ALL merges native categories newest first with stable ties',
      () async {
        final adapter = _RecordingAdapter();
        final harness = _repository(adapter);
        addTearDown(harness.dispose);

        final history = await harness.repository.getOrdersHistory(
          instType: 'ALL',
        );

        expect(history.map((order) => order.instType), [
          'MARGIN',
          'FUTURES',
          'SPOT',
          'SWAP',
        ]);
        expect(
          adapter.requests.map(
            (request) => request.uri.queryParameters['instType'],
          ),
          ['SPOT', 'MARGIN', 'SWAP', 'FUTURES'],
        );
        expect(
          adapter.requests.every(
            (request) => request.uri.path == '/api/v5/trade/orders-history',
          ),
          isTrue,
        );
      },
    );
  });
}

_RepositoryHarness _repository(_RecordingAdapter adapter) {
  final storage = _CredentialStorage();
  final client = OkxDataClient(
    dio: Dio()..httpClientAdapter = adapter,
    secureStorage: storage,
    requestCoordinator: RequestCoordinator(
      minimumSpacing: Duration.zero,
      delay: (_) async {},
    ),
  );
  return _RepositoryHarness(OrderRepository(client), client, storage);
}

class _RepositoryHarness {
  const _RepositoryHarness(this.repository, this.client, this.storage);

  final OrderRepository repository;
  final OkxDataClient client;
  final _CredentialStorage storage;

  void dispose() {
    client.dispose();
    storage.dispose();
  }
}

class _CredentialStorage extends SecureStorageHelper {
  _CredentialStorage() : super(const FlutterSecureStorage());

  @override
  Future<String?> getOkxApiKey() async => 'fixture-key';

  @override
  Future<String?> getOkxSecretKey() async => 'fixture-secret';

  @override
  Future<String?> getOkxPassphrase() async => 'fixture-passphrase';
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({this.failHistoryType, this.positionRows});

  final String? failHistoryType;
  final List<Map<String, dynamic>>? positionRows;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final path = options.uri.path;
    final instType = options.uri.queryParameters['instType'];

    if (path == '/api/v5/trade/orders-history' && instType == failHistoryType) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }

    final responseData = switch (path) {
      '/api/v5/account/positions' => {
        'code': '0',
        'msg': '',
        'data':
            positionRows ??
            [
              {'instType': 'MARGIN', 'instId': 'MARGIN-USDT-SWAP', 'pos': '1'},
              {'instType': 'SWAP', 'instId': 'SWAP-USDT-SWAP', 'pos': '1'},
              {
                'instType': 'FUTURES',
                'instId': 'FUTURES-USDT-SWAP',
                'pos': '1',
              },
            ],
      },
      '/api/v5/trade/orders-pending' => {
        'code': '0',
        'msg': '',
        'data': _ordersFor(instType),
      },
      '/api/v5/trade/orders-history' => {
        'code': '0',
        'msg': '',
        'data': _ordersFor(instType),
      },
      _ => throw StateError('Unexpected orders endpoint: $path'),
    };

    return ResponseBody.fromString(
      jsonEncode(responseData),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  List<Map<String, String>> _ordersFor(String? type) {
    final types = type == null
        ? const ['SPOT', 'MARGIN', 'SWAP', 'FUTURES']
        : [type];
    return types
        .map(
          (item) => {
            'instType': item,
            'instId': '$item-USDT',
            'cTime': _timestampFor(item),
          },
        )
        .toList();
  }

  String _timestampFor(String instType) => switch (instType) {
    'SPOT' => '10',
    'MARGIN' => '50',
    'SWAP' => 'invalid',
    'FUTURES' => '50',
    _ => '0',
  };

  @override
  void close({bool force = false}) {}
}
