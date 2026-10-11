import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/network/backend_data_client.dart';
import 'package:trading_balance_f/core/network/okx_websocket_service.dart';
import 'package:trading_balance_f/features/market/presentation/market_screen.dart';
import 'package:trading_balance_f/features/portfolio/presentation/portfolio_screen.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/trade_session_provider.dart';
import 'package:trading_balance_f/features/connections/presentation/providers/multi_user_provider.dart';

class _RecordingOkxWebsocketService extends OkxWebsocketService {
  int connectCalls = 0;
  int subscribeCalls = 0;

  @override
  void connect() {
    connectCalls++;
  }

  @override
  void subscribeToTickers(List<String> coinSymbols) {
    subscribeCalls++;
  }

  @override
  void disconnect() {}
}

void main() {
  testWidgets('Market renders its fetched ticker snapshot without WebSocket', (
    tester,
  ) async {
    final websocket = _RecordingOkxWebsocketService();
    var tickerCalls = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          marketListProvider.overrideWith((ref) async {
            tickerCalls++;
            return List.generate(
              50,
              (index) => MarketTicker(
                instId: index == 0 ? 'BTC-USDT' : 'COIN$index-USDT',
                last: index == 0 ? 65000 : 1000 + index.toDouble(),
                open24h: 64000,
                vol24h: 6000000,
                asOf: DateTime.now().toUtc(),
              ),
            );
          }),
          okxWebsocketProvider.overrideWithValue(websocket),
          isDarkModeProvider.overrideWithValue(false),
        ],
        child: const MaterialApp(home: MarketScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('BTC'), findsOneWidget);
    expect(find.text('\$65,000.00'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.pump(const Duration(minutes: 1));
    expect(tickerCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, 500));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tickerCalls, 2);
    expect(websocket.connectCalls, 0);
    expect(websocket.subscribeCalls, 0);
  });

  test(
    'MarketTicker parses OKX epoch milliseconds from the native ts field',
    () {
      final timestamp = DateTime.utc(2026, 10, 11, 12).millisecondsSinceEpoch;
      final ticker = _ticker(ts: timestamp.toString());

      expect(
        ticker.asOf,
        DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true),
      );
    },
  );

  testWidgets(
    'market hides quote values without current native timestamp proof',
    (tester) async {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final cases = <({String name, Object? ts})>[
        (name: 'missing', ts: null),
        (name: 'future', ts: (now + 3000).toString()),
        (name: 'stale', ts: (now - 16000).toString()),
      ];

      for (final fixture in cases) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              marketListProvider.overrideWith(
                (ref) async => [_ticker(ts: fixture.ts)],
              ),
              okxWebsocketProvider.overrideWithValue(
                _RecordingOkxWebsocketService(),
              ),
              isDarkModeProvider.overrideWithValue(false),
            ],
            child: const MaterialApp(home: MarketScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Giá chưa khả dụng'),
          findsOneWidget,
          reason: fixture.name,
        );
        expect(
          find.textContaining('\$65,000.00'),
          findsNothing,
          reason: fixture.name,
        );
        expect(
          find.textContaining('6.00M'),
          findsNothing,
          reason: fixture.name,
        );
        expect(
          find.textContaining(
            fixture.name == 'missing'
                ? 'Thiếu thời điểm báo giá'
                : fixture.name == 'future'
                ? 'Thời điểm báo giá chưa hợp lệ'
                : 'Báo giá cũ',
          ),
          findsOneWidget,
          reason: fixture.name,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      }

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            marketListProvider.overrideWith(
              (ref) async => [_ticker(ts: now.toString())],
            ),
            okxWebsocketProvider.overrideWithValue(
              _RecordingOkxWebsocketService(),
            ),
            isDarkModeProvider.overrideWithValue(false),
          ],
          child: const MaterialApp(home: MarketScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('\$65,000.00'), findsOneWidget);
      expect(find.text('Giá chưa khả dụng'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('RED-102 manual market refresh waits and coalesces taps', (
    tester,
  ) async {
    final refreshResult = Completer<List<MarketTicker>>();
    var tickerCalls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          marketListProvider.overrideWith((ref) async {
            tickerCalls++;
            if (tickerCalls == 1) return <MarketTicker>[];
            return refreshResult.future;
          }),
          okxWebsocketProvider.overrideWithValue(
            _RecordingOkxWebsocketService(),
          ),
          isDarkModeProvider.overrideWithValue(false),
        ],
        child: const MaterialApp(home: MarketScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final refresh = find.byTooltip('Làm mới dữ liệu');
    expect(refresh, findsOneWidget);
    await tester.tap(refresh);
    await tester.pump();
    expect(tickerCalls, 2);
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    expect(tickerCalls, 2);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('market-manual-refresh')))
          .onPressed,
      isNull,
    );
    refreshResult.complete(<MarketTicker>[]);
    await tester.pumpAndSettle();
    expect(tickerCalls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'initially paused market makes no transport request until foreground',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final adapter = _PublicTickerAdapter();
      final backend = BackendDataClient(
        dio: Dio()..httpClientAdapter = adapter,
        baseUrl: 'https://fixture.example/gateway',
        isWeb: false,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backendDataClientProvider.overrideWithValue(backend),
            okxWebsocketProvider.overrideWithValue(
              _RecordingOkxWebsocketService(),
            ),
            isDarkModeProvider.overrideWithValue(false),
          ],
          child: const MaterialApp(home: MarketScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 10));
      expect(adapter.requests, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(adapter.requests, 1);
      expect(find.text('BTC'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(adapter.requests, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      backend.close(force: true);
    },
  );
}

MarketTicker _ticker({required Object? ts}) => MarketTicker.fromJson({
  'instId': 'BTC-USDT',
  'last': '65000',
  'sodUtc0': '64000',
  'volCcy24h': '6000000',
  'ts': ts,
});

class _PublicTickerAdapter implements HttpClientAdapter {
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    return ResponseBody.fromString(
      jsonEncode({
        'code': '0',
        'msg': '',
        'data': [
          {
            'instId': 'BTC-USDT',
            'last': '65000',
            'sodUtc0': '64000',
            'volCcy24h': '6000000',
            'ts': '$now',
          },
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
