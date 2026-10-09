import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/network/okx_websocket_service.dart';
import 'package:trading_balance_f/features/market/presentation/market_screen.dart';
import 'package:trading_balance_f/features/portfolio/presentation/portfolio_screen.dart';

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
    await tester.pump(const Duration(minutes: 1));
    expect(tickerCalls, 1);

    await tester.drag(find.byType(ListView), const Offset(0, 500));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tickerCalls, 2);
    expect(websocket.connectCalls, 0);
    expect(websocket.subscribeCalls, 0);
  });

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
}
