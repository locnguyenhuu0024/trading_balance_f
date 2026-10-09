import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/network/foreground_read_gate.dart';
import 'package:trading_balance_f/features/orders/data/trade_api_client.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/trade_session_provider.dart';

void main() {
  test('HTTP 403 failures are terminal for automatic foreground polling', () {
    expect(
      isTerminalForegroundReadFailure(
        const TradeApiException(
          code: 'forbidden',
          message: 'Forbidden',
          statusCode: 403,
        ),
      ),
      isTrue,
    );
  });

  test(
    'TradeApiClient retains HTTP 429 and Retry-After on GET errors',
    () async {
      final adapter = _ResponseAdapter(
        429,
        {'error': 'rate_limited', 'message': 'Limited'},
        headers: {
          'retry-after': ['120'],
        },
      );
      final api = TradeApiClient(
        baseUrl: 'https://trade.example',
        dio: Dio()..httpClientAdapter = adapter,
      );

      await expectLater(
        api.getPositions('test-token'),
        throwsA(
          isA<TradeApiException>()
              .having((error) => error.statusCode, 'statusCode', 429)
              .having((error) => error.retryAfter, 'retryAfter', '120'),
        ),
      );
    },
  );

  testWidgets('operation-only session changes do not restart position reads', (
    tester,
  ) async {
    final api = _PendingPositionsApi();
    final controller = _TestSessionController(api, _session('account-a'));
    final container = _providerContainer(
      api,
      controller,
      now: tester.binding.clock.now,
    );
    final subscription = container.listen(tradePositionsProvider, (_, _) {});

    await tester.pump();
    expect(api.requests, hasLength(1));
    api.requests.single.complete(_snapshot('account-a'));
    await tester.pump();
    expect(container.read(tradePositionsProvider).hasValue, isTrue);

    container
        .read(tradeSessionProvider.notifier)
        .rememberOperation(
          const PendingTradeOperation(
            operationId: 'operation-1',
            action: 'close_position',
            targetLabel: 'BTC-USDT-SWAP',
            status: 'IN_PROGRESS',
          ),
        );
    await _flush(tester, container);

    expect(api.requests, hasLength(1));
    subscription.close();
    await _flush(tester, container);
    container.dispose();
  });

  testWidgets('cooldown survives provider disposal and screen re-entry', (
    tester,
  ) async {
    final api = _RateLimitedPositionsApi();
    final controller = _TestSessionController(api, _session('account-a'));
    final container = _providerContainer(
      api,
      controller,
      now: tester.binding.clock.now,
    );
    final first = container.listen(tradePositionsProvider, (_, _) {});

    await tester.pump();
    await tester.pump();
    expect(api.reads, 1);
    expect(container.read(tradePositionsProvider).hasError, isTrue);
    first.close();
    await _flush(tester, container);
    await tester.pump(const Duration(seconds: 30));
    expect(api.reads, 1);

    final reentered = container.listen(tradePositionsProvider, (_, _) {});
    await tester.pump();
    expect(api.reads, 1);
    await tester.pump(const Duration(seconds: 89));
    expect(api.reads, 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(api.reads, 2);

    reentered.close();
    await _flush(tester, container);
    container.dispose();
  });

  testWidgets('session replacement rejects a late old position response', (
    tester,
  ) async {
    final api = _PendingPositionsApi();
    final controller = _TestSessionController(api, _session('account-a'));
    final container = _providerContainer(
      api,
      controller,
      now: tester.binding.clock.now,
    );
    final subscription = container.listen(tradePositionsProvider, (_, _) {});

    await tester.pump();
    expect(api.requests, hasLength(1));
    controller.replace(_session('account-b'));
    await _flush(tester, container);
    await tester.pump();
    expect(api.requests, hasLength(2));

    api.requests.first.complete(_snapshot('account-a'));
    await tester.pump();
    expect(container.read(tradePositionsProvider).hasValue, isFalse);

    api.requests.last.complete(_snapshot('account-b'));
    await tester.pump();
    expect(
      container.read(tradePositionsProvider).value?.accountIdentifier,
      'account-b',
    );

    subscription.close();
    await _flush(tester, container);
    container.dispose();
  });
}

ProviderContainer _providerContainer(
  TradeApiClient api,
  TradeSessionController controller, {
  DateTime Function()? now,
}) => ProviderContainer(
  overrides: [
    tradeApiProvider.overrideWithValue(api),
    tradeSessionProvider.overrideWith((ref) => controller),
    foregroundReadGateProvider.overrideWith((ref) {
      final gate = ForegroundReadGate(now: now);
      ref.onDispose(gate.dispose);
      return gate;
    }),
  ],
);

Future<void> _flush(WidgetTester tester, ProviderContainer _) async {
  await tester.pump(const Duration(milliseconds: 1));
}

TradeSession _session(String accountIdentifier) => TradeSession(
  bearerToken: 'test-token-$accountIdentifier',
  accountIdentifier: accountIdentifier,
  expiresAt: DateTime.now().add(const Duration(hours: 1)),
);

TradePositionsSnapshot _snapshot(String accountIdentifier) =>
    TradePositionsSnapshot(
      accountIdentifier: accountIdentifier,
      positions: const [],
    );

class _TestSessionController extends TradeSessionController {
  _TestSessionController(super.api, TradeSession session) {
    state = TradeSessionState(session: session);
  }

  void replace(TradeSession session) {
    state = TradeSessionState(session: session);
  }
}

class _PendingPositionsApi extends TradeApiClient {
  _PendingPositionsApi() : super(baseUrl: 'https://trade.example');

  final List<Completer<TradePositionsSnapshot>> requests = [];

  @override
  Future<TradePositionsSnapshot> getPositions(String bearerToken) {
    final request = Completer<TradePositionsSnapshot>();
    requests.add(request);
    return request.future;
  }

  @override
  Future<TradePositionsSnapshot> getPositionsCancellable(
    String bearerToken, {
    required CancelToken cancelToken,
  }) => getPositions(bearerToken);
}

class _RateLimitedPositionsApi extends TradeApiClient {
  _RateLimitedPositionsApi() : super(baseUrl: 'https://trade.example');

  int reads = 0;

  @override
  Future<TradePositionsSnapshot> getPositions(String bearerToken) async {
    reads++;
    throw const TradeApiException(
      code: 'rate_limited',
      message: 'Limited',
      statusCode: 429,
      retryAfter: '120',
    );
  }

  @override
  Future<TradePositionsSnapshot> getPositionsCancellable(
    String bearerToken, {
    required CancelToken cancelToken,
  }) => getPositions(bearerToken);
}

class _ResponseAdapter implements HttpClientAdapter {
  _ResponseAdapter(this.statusCode, this.body, {this.headers = const {}});

  final int statusCode;
  final Object body;
  final Map<String, List<String>> headers;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
    },
  );

  @override
  void close({bool force = false}) {}
}
