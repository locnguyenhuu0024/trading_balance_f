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
}
