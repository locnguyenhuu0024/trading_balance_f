import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/network/okx_data_client.dart';
import 'package:trading_balance_f/core/network/okx_websocket_service.dart';
import 'package:trading_balance_f/core/network/request_coordinator.dart';

void main() {
  test(
    'polls one native SPOT ticker endpoint for the complete owner union',
    () async {
      final adapter = _ImmediateAdapter(
        (_) => {
          'code': '0',
          'data': _tickerRows([
            'BTC-USDT',
            'ETH-USDT',
            'SOL-USDT',
            'DOGE-USDT',
          ]),
        },
      );
      final coordinator = _coordinator();
      final client = _client(adapter);
      final service = _service(client, coordinator);
      addTearDown(service.disconnect);
      addTearDown(client.dispose);
      final snapshots = <Map<String, String>>[];
      final listener = service.stream.listen(
        (snapshot) => snapshots.add(snapshot as Map<String, String>),
      );
      addTearDown(listener.cancel);

      service.connect();
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(adapter.requests, isEmpty);

      final first = service.subscribe(['btc', 'BTC-USDT', 'eth']);
      final second = service.subscribe(['ETH', 'sol-usdt']);
      await _waitUntil(() => snapshots.any((snapshot) => snapshot.length == 3));

      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.uri.path, '/api/v5/market/tickers');
      expect(adapter.requests.single.uri.queryParameters, {'instType': 'SPOT'});
      expect(snapshots.last, {
        'BTC': '123.45',
        'ETH': '123.45',
        'SOL': '123.45',
      });

      await first.cancel();
      await second.cancel();
      final callsAfterCancel = adapter.requests.length;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(adapter.requests.length, callsAfterCancel);
    },
  );

  test('large active unions still use one native ticker request', () async {
    final adapter = _ImmediateAdapter((_) => {'code': '0', 'data': []});
    final client = _client(adapter);
    final service = _service(client, _coordinator());
    addTearDown(service.disconnect);
    addTearDown(client.dispose);
    final subscription = service.subscribe(
      List<String>.generate(101, (index) => 'COIN$index'),
    );

    await _waitUntil(() => adapter.requests.isNotEmpty);
    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.uri.queryParameters, {'instType': 'SPOT'});

    await subscription.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(adapter.requests, hasLength(1));
  });

  test('upstream failure clears prices and respects backoff', () async {
    final adapter = _ImmediateAdapter((requestNumber) {
      if (requestNumber == 1) {
        return {
          'code': '0',
          'data': _tickerRows(['BTC-USDT'], price: '321'),
        };
      }
      return {'code': 'upstream_error', 'data': []};
    });
    final client = _client(adapter);
    final service = _service(
      client,
      _coordinator(),
      pollInterval: const Duration(milliseconds: 15),
    );
    addTearDown(service.disconnect);
    addTearDown(client.dispose);
    final snapshots = <Map<String, String>>[];
    final listener = service.stream.listen(
      (snapshot) => snapshots.add(snapshot as Map<String, String>),
    );
    addTearDown(listener.cancel);
    final subscription = service.subscribe(['BTC']);
    addTearDown(subscription.cancel);

    await _waitUntil(
      () => snapshots.any((snapshot) => snapshot['BTC'] == '321'),
    );
    await _waitUntil(() => snapshots.any((snapshot) => snapshot.isEmpty));
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(snapshots.last, isEmpty);
    expect(adapter.requests, hasLength(2));
  });

  test('a quote expires while the next native poll remains pending', () async {
    final adapter = _FirstQuoteThenPendingAdapter();
    final client = _client(adapter);
    final service = _service(
      client,
      _coordinator(),
      pollInterval: const Duration(milliseconds: 10),
      maximumQuoteAge: const Duration(milliseconds: 200),
    );
    addTearDown(service.disconnect);
    addTearDown(client.dispose);
    final snapshots = <Map<String, String>>[];
    final listener = service.stream.listen(
      (snapshot) => snapshots.add(snapshot as Map<String, String>),
    );
    addTearDown(listener.cancel);
    final subscription = service.subscribe(['BTC']);
    addTearDown(subscription.cancel);

    await _waitUntil(
      () => snapshots.any((snapshot) => snapshot['BTC'] == '456'),
      'initial fresh quote',
    );
    final publishedIndex = snapshots.lastIndexWhere(
      (snapshot) => snapshot['BTC'] == '456',
    );
    await _waitUntil(() => adapter.requests.length == 2, 'hanging poll');
    await _waitUntil(
      () => snapshots
          .skip(publishedIndex + 1)
          .any((snapshot) => snapshot.isEmpty),
      'fresh quote expiry',
    );

    expect(adapter.requests, hasLength(2));
    expect(snapshots.last, isEmpty);
    expect(adapter.secondRequestPending, isTrue);
  });

  test(
    'subscription change cancels the old generation before publishing',
    () async {
      final adapter = _CancelThenFreshAdapter();
      final client = _client(adapter);
      final service = _service(
        client,
        _coordinator(),
        pollInterval: const Duration(milliseconds: 20),
      );
      addTearDown(service.disconnect);
      addTearDown(client.dispose);
      final snapshots = <Map<String, String>>[];
      final listener = service.stream.listen(
        (snapshot) => snapshots.add(snapshot as Map<String, String>),
      );
      addTearDown(listener.cancel);

      final first = service.subscribe(['BTC']);
      await _waitUntil(() => adapter.requests.length == 1);
      await first.cancel();
      final second = service.subscribe(['ETH']);
      addTearDown(second.cancel);
      await _waitUntil(() => adapter.requests.length == 2);
      await _waitUntil(
        () => snapshots.any((snapshot) => snapshot['ETH'] == '222'),
      );

      expect(snapshots.last, {'ETH': '222'});
      expect(adapter.requests, hasLength(2));
    },
  );

  test(
    'different poll service owners never join a cancelled shared request',
    () async {
      final adapter = _TwoPendingAdapter();
      final client = _client(adapter);
      final coordinator = _coordinator();
      final firstService = _service(client, coordinator);
      final secondService = _service(client, coordinator);
      addTearDown(firstService.disconnect);
      addTearDown(secondService.disconnect);
      addTearDown(client.dispose);
      final firstSnapshots = <Map<String, String>>[];
      final secondSnapshots = <Map<String, String>>[];
      final firstListener = firstService.stream.listen(
        (snapshot) => firstSnapshots.add(snapshot as Map<String, String>),
      );
      final secondListener = secondService.stream.listen(
        (snapshot) => secondSnapshots.add(snapshot as Map<String, String>),
      );
      addTearDown(firstListener.cancel);
      addTearDown(secondListener.cancel);

      final first = firstService.subscribe(['BTC']);
      addTearDown(first.cancel);
      await _waitUntil(() => adapter.requests.length == 1);
      await first.cancel();

      final second = secondService.subscribe(['BTC']);
      addTearDown(second.cancel);
      await _waitUntil(() => adapter.requests.length == 2);
      adapter.reply(1, {
        'code': '0',
        'data': _tickerRows(['BTC-USDT'], price: '333'),
      });
      await _waitUntil(
        () => secondSnapshots.any((snapshot) => snapshot['BTC'] == '333'),
      );

      expect(
        firstSnapshots.every((snapshot) => !snapshot.containsKey('BTC')),
        isTrue,
      );
      expect(adapter.requests, hasLength(2));
    },
  );

  test(
    'a quote without a fresh upstream timestamp is never published',
    () async {
      final adapter = _ImmediateAdapter(
        (_) => {
          'code': '0',
          'data': [
            {'instId': 'BTC-USDT', 'last': '456', 'ts': '1'},
          ],
        },
      );
      final client = _client(adapter);
      final service = _service(client, _coordinator());
      addTearDown(service.disconnect);
      addTearDown(client.dispose);
      final snapshots = <Map<String, String>>[];
      final listener = service.stream.listen(
        (snapshot) => snapshots.add(snapshot as Map<String, String>),
      );
      addTearDown(listener.cancel);
      final subscription = service.subscribe(['BTC']);
      addTearDown(subscription.cancel);

      await _waitUntil(() => adapter.requests.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(
        snapshots.every((snapshot) => !snapshot.containsKey('BTC')),
        isTrue,
      );
    },
  );
}

RequestCoordinator _coordinator() =>
    RequestCoordinator(minimumSpacing: Duration.zero, delay: (_) async {});

OkxDataClient _client(HttpClientAdapter adapter) =>
    OkxDataClient(dio: Dio()..httpClientAdapter = adapter);

OkxWebsocketService _service(
  OkxDataClient client,
  RequestCoordinator coordinator, {
  Duration pollInterval = const Duration(seconds: 1),
  Duration maximumQuoteAge = OkxWebsocketService.maximumQuoteAge,
}) => OkxWebsocketService(
  client: client,
  requestCoordinator: coordinator,
  pollInterval: pollInterval,
  maximumQuoteAge: maximumQuoteAge,
);

List<Map<String, String>> _tickerRows(
  List<String> ids, {
  String price = '123.45',
}) => ids
    .map(
      (id) => {
        'instId': id,
        'last': price,
        'ts': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    )
    .toList(growable: false);

Future<void> _waitUntil(
  bool Function() condition, [
  String label = 'condition',
]) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out waiting for $label.');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

ResponseBody _response(Object body, {int statusCode = 200}) =>
    ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

class _ImmediateAdapter implements HttpClientAdapter {
  _ImmediateAdapter(this.handler);

  final Map<String, dynamic> Function(int requestNumber) handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return _response(handler(requests.length));
  }

  @override
  void close({bool force = false}) {}
}

class _FirstQuoteThenPendingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  bool get secondRequestPending => requests.length >= 2;
  final Completer<ResponseBody> _pending = Completer<ResponseBody>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    if (requests.length == 1) {
      return Future.value(
        _response({
          'code': '0',
          'data': _tickerRows(['BTC-USDT'], price: '456'),
        }),
      );
    }
    cancelFuture?.then((_) {
      if (!_pending.isCompleted) {
        _pending.completeError(
          DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
          ),
        );
      }
    });
    return _pending.future;
  }

  @override
  void close({bool force = false}) {}
}

class _CancelThenFreshAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    if (requests.length == 1) {
      final cancelled = Completer<ResponseBody>();
      cancelFuture?.then((_) {
        if (!cancelled.isCompleted) {
          cancelled.completeError(
            DioException(
              requestOptions: options,
              type: DioExceptionType.cancel,
            ),
          );
        }
      });
      return cancelled.future;
    }
    return Future.value(
      _response({
        'code': '0',
        'data': [
          ..._tickerRows(['BTC-USDT'], price: '111'),
          ..._tickerRows(['ETH-USDT'], price: '222'),
        ],
      }),
    );
  }

  @override
  void close({bool force = false}) {}
}

class _TwoPendingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final List<Completer<ResponseBody>> _responses = [];

  void reply(int index, Object body) {
    if (!_responses[index].isCompleted) {
      _responses[index].complete(_response(body));
    }
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    final response = Completer<ResponseBody>();
    _responses.add(response);
    if (requests.length == 1) {
      cancelFuture?.then((_) {
        if (!response.isCompleted) {
          response.completeError(
            DioException(
              requestOptions: options,
              type: DioExceptionType.cancel,
            ),
          );
        }
      });
    }
    return response.future;
  }

  @override
  void close({bool force = false}) {}
}
