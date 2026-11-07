import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:trading_balance_f/core/exchange/exchange_models.dart';
import 'package:trading_balance_f/core/exchange/exchange_registry.dart';
import 'package:trading_balance_f/core/exchange/exchange_scope.dart';
import 'package:trading_balance_f/core/exchange/market_source.dart';
import 'package:trading_balance_f/core/network/request_coordinator.dart';
import 'package:trading_balance_f/exchanges/binance/binance_client.dart';
import 'package:trading_balance_f/exchanges/binance/binance_market.dart';
import 'package:trading_balance_f/exchanges/okx/okx_adapter.dart';
import '../../support/fake_exchange_adapter.dart';
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
  testWidgets(
    'Binance market displays fixture rows, source and product selection',
    (tester) async {
      final client = _MarketFixtureClient();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            exchangeRegistryProvider.overrideWith(
              (ref) => [
                const ExchangeRegistration(
                  profile: ConnectionProfile(
                    connectionId: 'okx-default',
                    exchange: ExchangeId.okx,
                    label: 'OKX',
                  ),
                  adapter: OkxAdapter(),
                ),
                ExchangeRegistration(
                  profile: const ConnectionProfile(
                    connectionId: 'binance',
                    exchange: ExchangeId.binance,
                    label: 'Binance',
                  ),
                  adapter: _BinanceAdapter(client),
                ),
              ],
            ),
            selectedConnectionIdProvider.overrideWith((ref) => 'binance'),
            isDarkModeProvider.overrideWithValue(false),
          ],
          child: const MaterialApp(home: MarketScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nguồn giá: Binance'), findsOneWidget);
      expect(find.text('BTC'), findsOneWidget);
      expect(find.text('\$12.00'), findsOneWidget);
      expect(client.paths, ['/fapi/v1/ticker/24hr']);
      await tester.tap(find.text('SPOT'));
      await tester.pumpAndSettle();
      expect(client.paths.last, '/api/v3/ticker/24hr');
    },
  );

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

class _BinanceAdapter extends FakeExchangeAdapter {
  _BinanceAdapter(this.client);
  final BinanceClient client;
  @override
  List<String> get marketProducts => const ['USD-M', 'SPOT'];
  @override
  MarketSource market(Ref ref) => BinanceMarket(client);
}

class _MarketFixtureClient extends BinanceClient {
  _MarketFixtureClient() : super(coordinator: RequestCoordinator());
  final paths = <String>[];
  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic> queryParameters = const {},
  }) async {
    paths.add(path);
    return Response(
      requestOptions: RequestOptions(path: path),
      data: [
        {
          'symbol': 'BTCUSDT',
          'lastPrice': '12',
          'openPrice': '10',
          'quoteVolume': '6000000',
        },
      ],
    );
  }
}
