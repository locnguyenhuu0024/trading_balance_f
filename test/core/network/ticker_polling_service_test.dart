import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/network/backend_data_client.dart';
import 'package:trading_balance_f/core/network/okx_websocket_service.dart';
import 'package:trading_balance_f/core/network/request_coordinator.dart';

void main() {
  test(
    'does not poll until subscribed and polls the ordered union once',
    () async {
      final adapter = _QuoteAdapter(
        (ids, _) => {
          'code': '0',
          'data': ids
              .map(
                (id) => {
                  'instId': id,
                  'last': '123.45',
                  'ts': DateTime.now().millisecondsSinceEpoch.toString(),
                },
              )
              .toList(),
        },
      );
      final service = _service(
        adapter,
        interval: const Duration(milliseconds: 300),
      );
      addTearDown(service.disconnect);
      final snapshots = <Map<String, String>>[];
      final listener = service.stream.listen(
        (snapshot) => snapshots.add(snapshot as Map<String, String>),
      );
      addTearDown(listener.cancel);

      service.connect();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(adapter.requests, isEmpty);

      final first = service.subscribe(['btc', 'BTC-USDT', 'eth']);
      final second = service.subscribe(['ETH', 'sol-usdt']);
      await _waitUntil(() => adapter.requests.isNotEmpty);

      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.uri.queryParametersAll.keys, ['instIds']);
      expect(
        adapter.requests.single.uri.queryParameters['instIds'],
        'BTC-USDT,ETH-USDT,SOL-USDT',
      );
      await _waitUntil(() => snapshots.any((snapshot) => snapshot.length == 3));
      expect(snapshots.last, {
        'BTC': '123.45',
        'ETH': '123.45',
        'SOL': '123.45',
      });

      await first.cancel();
      await second.cancel();
      final callsAfterCancel = adapter.requests.length;
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(adapter.requests.length, callsAfterCancel);
    },
  );

  test(
    'splits quote ids into one-key batches of at most 100 and stops on cancel',
    () async {
      final adapter = _QuoteAdapter((_, _) => {'code': '0', 'data': []});
      final service = _service(
        adapter,
        interval: const Duration(milliseconds: 200),
      );
      addTearDown(service.disconnect);
      final symbols = List<String>.generate(101, (index) => 'COIN$index');
      final subscription = service.subscribe(symbols);

      await _waitUntil(() => adapter.requests.length == 2);
      expect(adapter.requests, hasLength(2));
      final batches = adapter.requests
          .map((request) => request.uri.queryParametersAll['instIds']!)
          .toList();
      expect(batches, hasLength(2));
      expect(batches.first, hasLength(1));
      expect(batches.first.single.split(',').length, 100);
      expect(batches.last.single.split(','), ['COIN100-USDT']);

      await subscription.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(adapter.requests, hasLength(2));
    },
  );

  test(
    'upstream failure clears previously published prices and backs off',
    () async {
      var responseCount = 0;
      final adapter = _QuoteAdapter((ids, _) {
        responseCount++;
        if (responseCount == 1) {
          return {
            'code': '0',
            'data': ids
                .map(
                  (id) => {
                    'instId': id,
                    'last': '321',
                    'ts': DateTime.now().millisecondsSinceEpoch.toString(),
                  },
                )
                .toList(),
          };
        }
        return {'code': 'upstream_error', 'data': []};
      });
      final service = _service(
        adapter,
        interval: const Duration(milliseconds: 15),
      );
      addTearDown(service.disconnect);
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
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(snapshots.last, isEmpty);
      expect(adapter.requests, hasLength(2));
    },
  );

  test(
    'disconnect during a delayed failing batch prevents the next batch',
    () async {
      final adapter = _DelayedFailAdapter();
      final service = _service(adapter, interval: const Duration(seconds: 1));
      addTearDown(service.disconnect);
      service.subscribe(List<String>.generate(101, (index) => 'COIN$index'));

      await _waitUntil(() => adapter.requests.isNotEmpty);
      service.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(adapter.requests, hasLength(1));
    },
  );

  test('a quote expires while the next backend poll remains pending', () async {
    final adapter = _FirstQuoteThenPendingAdapter();
    final service = _service(
      adapter,
      interval: const Duration(milliseconds: 10),
      maximumQuoteAge: const Duration(milliseconds: 200),
    );
    addTearDown(service.disconnect);
    final snapshots = <Map<String, String>>[];
    final listener = service.stream.listen(
      (snapshot) => snapshots.add(snapshot as Map<String, String>),
    );
    addTearDown(listener.cancel);
    final subscription = service.subscribe(['BTC']);
    addTearDown(subscription.cancel);

    await _waitUntil(
      () => snapshots.any((snapshot) => snapshot['BTC'] == '456'),
      'the initial fresh quote',
    );
    final publishedIndex = snapshots.lastIndexWhere(
      (snapshot) => snapshot['BTC'] == '456',
    );
    await _waitUntil(() => adapter.requests.length == 2, 'the hanging poll');
    await _waitUntil(
      () => snapshots
          .skip(publishedIndex + 1)
          .any((snapshot) => snapshot.isEmpty),
      'fresh quote expiry after publication',
    );

    expect(adapter.requests, hasLength(2));
    expect(snapshots.last, isEmpty);
    expect(adapter.secondRequestPending, isTrue);
  });

  test(
    'a quote without a fresh upstream timestamp is never published',
    () async {
      final adapter = _QuoteAdapter(
        (ids, _) => {
          'code': '0',
          'data': ids
              .map((id) => {'instId': id, 'last': '456', 'ts': '1'})
              .toList(),
        },
      );
      final service = _service(adapter, interval: const Duration(seconds: 1));
      addTearDown(service.disconnect);
      final snapshots = <Map<String, String>>[];
      final listener = service.stream.listen(
        (snapshot) => snapshots.add(snapshot as Map<String, String>),
      );
      addTearDown(listener.cancel);
      service.subscribe(['BTC']);

      await _waitUntil(() => adapter.requests.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(
        snapshots.every((snapshot) => !snapshot.containsKey('BTC')),
        isTrue,
      );
    },
  );
}

OkxWebsocketService _service(
  HttpClientAdapter adapter, {
  required Duration interval,
  Duration maximumQuoteAge = OkxWebsocketService.maximumQuoteAge,
}) => OkxWebsocketService(
  client: BackendDataClient(
    dio: Dio()..httpClientAdapter = adapter,
    baseUrl: 'https://data.example',
  ),
  requestCoordinator: RequestCoordinator(
    minimumSpacing: Duration.zero,
    delay: (_) async {},
  ),
  pollInterval: interval,
  maximumQuoteAge: maximumQuoteAge,
);

Future<void> _waitUntil(
  bool Function() condition, [
  String label = 'condition',
]) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for $label.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _QuoteAdapter implements HttpClientAdapter {
  _QuoteAdapter(this.handler);

  final Map<String, dynamic> Function(List<String> ids, int requestNumber)
  handler;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final ids = (options.uri.queryParameters['instIds'] ?? '').split(',');
    final body = handler(ids, requests.length);
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _DelayedFailAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    final response = Completer<ResponseBody>();
    cancelFuture?.then((_) {
      if (!response.isCompleted) {
        response.completeError(
          DioException(requestOptions: options, type: DioExceptionType.cancel),
        );
      }
    });
    Timer(const Duration(milliseconds: 20), () {
      if (!response.isCompleted) {
        response.complete(
          ResponseBody.fromString(
            jsonEncode({'code': 'upstream_error', 'data': []}),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          ),
        );
      }
    });
    return response.future;
  }

  @override
  void close({bool force = false}) {}
}

class _FirstQuoteThenPendingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];
  bool get secondRequestPending => requests.length >= 2;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    if (requests.length == 1) {
      return Future<ResponseBody>.value(
        ResponseBody.fromString(
          jsonEncode({
            'code': '0',
            'data': [
              {
                'instId': 'BTC-USDT',
                'last': '456',
                'ts': DateTime.now().millisecondsSinceEpoch.toString(),
              },
            ],
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      );
    }
    final pending = Completer<ResponseBody>();
    cancelFuture?.then((_) {
      if (!pending.isCompleted) {
        pending.completeError(
          DioException(requestOptions: options, type: DioExceptionType.cancel),
        );
      }
    });
    return pending.future;
  }

  @override
  void close({bool force = false}) {}
}
