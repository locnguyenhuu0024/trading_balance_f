import 'dart:async';
import 'package:trading_balance_f/exchanges/binance/binance_adapter.dart';
import 'package:trading_balance_f/exchanges/binance/binance_trade_history.dart';
import 'package:trading_balance_f/exchanges/binance/binance_cost_basis.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/exchange/exchange_models.dart';
import 'package:trading_balance_f/core/exchange/exchange_registry.dart';
import 'package:trading_balance_f/core/exchange/exchange_scope.dart';
import 'package:trading_balance_f/core/network/okx_websocket_service.dart';
import 'package:trading_balance_f/exchanges/okx/okx_adapter.dart';
import 'package:trading_balance_f/features/market/presentation/providers/market_provider.dart';
import 'package:trading_balance_f/features/portfolio/data/okx_balance_model.dart';
import 'package:trading_balance_f/features/portfolio/presentation/providers/portfolio_provider.dart';
import 'package:trading_balance_f/features/portfolio/presentation/portfolio_details_screen.dart';
import 'package:trading_balance_f/features/portfolio/presentation/portfolio_screen.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';

import '../../support/fake_exchange_adapter.dart';

class _Socket extends OkxWebsocketService {
  int subscriptions = 0;
  @override
  void subscribeToTickers(List<String> coins) => subscriptions++;
  @override
  void clearLegacySubscription() {}
}

class _Fake extends FakeExchangeAdapter {
  @override
  Future<AccountSnapshot> readAccount(Ref ref, ExchangeScope scope) async =>
      const AccountSnapshot(
        total: '42',
        balances: [
          AssetBalance(
            wallet: 'fake',
            asset: 'FAKE',
            total: '42',
            valueUsdt: '42',
          ),
        ],
      );
}

class _SnapshotAdapter extends FakeExchangeAdapter {
  _SnapshotAdapter(this.snapshot);
  final AccountSnapshot snapshot;

  @override
  Future<AccountSnapshot> readAccount(Ref ref, ExchangeScope scope) async =>
      snapshot;
}

class _CostController implements BinanceCostController {
  int runs = 0;
  @override
  Future<void> run(AccountSnapshot account) async {
    runs++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'active history run hides missing row and summary until finished',
    (tester) async {
      final views = StreamController<BinanceCostView>();
      final container = ProviderContainer(
        overrides: [
          selectedConnectionIdProvider.overrideWith((ref) => 'test'),
          exchangeRegistryProvider.overrideWith(
            (ref) => [
              ExchangeRegistration(
                profile: const ConnectionProfile(
                  connectionId: 'test',
                  exchange: ExchangeId.binance,
                  label: 'Binance',
                ),
                adapter: _SnapshotAdapter(
                  const AccountSnapshot(
                    total: '100',
                    balances: [
                      AssetBalance(
                        wallet: 'Spot',
                        asset: 'BTC',
                        total: '1',
                        valueUsdt: '100',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          binanceCostControllerProvider.overrideWith(
            (ref) async => _CostController(),
          ),
          binanceCostStateProvider.overrideWith((ref) => views.stream),
          vndExchangeRateProvider.overrideWith((ref) async => 25400),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: PortfolioScreen()),
        ),
      );
      await tester.pump();
      views.add(const BinanceCostView(loading: true));
      await tester.pump();
      await tester.pump();
      expect(find.text('Chưa tính'), findsNothing);
      expect(find.textContaining('Ước tính Spot · Margin'), findsNothing);
      views.add(const BinanceCostView());
      await tester.pump();
      expect(find.text('Chưa tính'), findsOneWidget);
      expect(
        find.textContaining('Ước tính Spot · Margin: Chưa đủ dữ liệu giá vốn'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      addTearDown(views.close);
    },
  );

  for (final withSpot in [false, true]) {
    testWidgets('Assets own capital and summary withSpot=$withSpot', (tester) async {
      const key = InstrumentKey(exchange: ExchangeId.binance, product: 'MARGIN',
          nativeId: 'ETHUSDT', base: 'ETH', quote: 'USDT');
      final snapshot = AccountSnapshot(
        total: withSpot ? '139.5' : '29.5',
        balances: [if (withSpot) const AssetBalance(
          wallet: 'Spot', asset: 'BTC', total: '1', valueUsdt: '110')],
        marginRows: const [MarginAccountRow(key: key, baseNet: '1', indexPrice: '80',
            quoteNet: '-50.5', quoteInterest: '0.5')],
      );
      const symbols = <String, BinanceSymbolCost>{
        'Spot:BTCUSDT': BinanceSymbolCost(CostState(quantity: 1, cost: 100), completed: true),
        'Isolated Margin:ETHUSDT': BinanceSymbolCost(
            CostState(quantity: 1, cost: 100, isMargin: true), completed: true),
      };
      final views = StreamController<BinanceCostView>();
      final container = ProviderContainer(overrides: [
        selectedConnectionIdProvider.overrideWith((ref) => 'test'),
        exchangeRegistryProvider.overrideWith((ref) => [ExchangeRegistration(
          profile: const ConnectionProfile(connectionId: 'test', exchange: ExchangeId.binance, label: 'Binance'),
          adapter: _SnapshotAdapter(snapshot),
        )]),
        binanceCostControllerProvider.overrideWith((ref) async => _CostController()),
        binanceCostStateProvider.overrideWith((ref) => views.stream),
        vndExchangeRateProvider.overrideWith((ref) async => 25400),
      ]);
      await tester.pumpWidget(UncontrolledProviderScope(container: container,
          child: const MaterialApp(home: PortfolioScreen())));
      await tester.pump();
      views.add(const BinanceCostView(loading: true, symbols: symbols));
      await tester.pump();
      await tester.pump();
      if (!withSpot) expect(find.text(r'$29.50'), findsWidgets);
      views.add(const BinanceCostView(symbols: symbols));
      await tester.pump();
      await tester.pump();
      if (withSpot) {
        expect(find.text(r'Ước tính Spot · Margin: -$10.50 (-7.00%)'), findsOneWidget);
        expect(find.text('Tính trên 2/2 tài sản'), findsOneWidget);
      } else {
        expect(find.text(r'$50.00'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });
  }

  for (final isOkx in [true, false]) {
    testWidgets(
      'Assets preserves account when cost provider ${isOkx ? "is not built for OKX" : "fails"}',
      (tester) async {
        var stateBuilds = 0;
        var controllerBuilds = 0;
        final container = ProviderContainer(
          overrides: [
            selectedConnectionIdProvider.overrideWith((ref) => 'test'),
            exchangeRegistryProvider.overrideWith(
              (ref) => [
                ExchangeRegistration(
                  profile: ConnectionProfile(
                    connectionId: 'test',
                    exchange: isOkx ? ExchangeId.okx : ExchangeId.binance,
                    label: 'Test',
                  ),
                  adapter: _SnapshotAdapter(
                    const AccountSnapshot(
                      total: '1200',
                      balances: [
                        AssetBalance(
                          wallet: 'USD-M',
                          asset: 'USDT',
                          total: '1100',
                          valueUsdt: '1100',
                          unrealizedPnl: '100',
                        ),
                        AssetBalance(
                          wallet: 'Spot',
                          asset: 'BTC',
                          total: '1',
                          valueUsdt: '100',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            binanceCostControllerProvider.overrideWith((ref) async {
              controllerBuilds++;
              if (isOkx) fail('OKX built the cost controller');
              throw StateError('history failed');
            }),
            binanceCostStateProvider.overrideWith((ref) {
              stateBuilds++;
              if (isOkx) fail('OKX built the cost state');
              return Stream<BinanceCostView>.error(
                StateError('history failed'),
              );
            }),
            livePriceProvider.overrideWith((ref) => LivePriceNotifier()),
            okxWebsocketProvider.overrideWithValue(_Socket()),
            vndExchangeRateProvider.overrideWith((ref) async => 25400),
          ],
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: PortfolioScreen()),
          ),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump();
        expect(find.text('BTC'), findsOneWidget);
        expect(find.textContaining('Giá vốn TB'), findsNothing);
        expect(find.textContaining('Ước tính Spot · Margin'), findsNothing);
        if (isOkx) {
          expect(stateBuilds, 0);
          expect(controllerBuilds, 0);
        }
        if (!isOkx) expect(find.text('(+10.00%)'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      },
    );
  }

  testWidgets('Assets partial stale estimate fits at large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        selectedConnectionIdProvider.overrideWith((ref) => 'test'),
        exchangeRegistryProvider.overrideWith(
          (ref) => [
            ExchangeRegistration(
              profile: const ConnectionProfile(
                connectionId: 'test',
                exchange: ExchangeId.binance,
                label: 'Binance',
              ),
              adapter: _SnapshotAdapter(
                const AccountSnapshot(
                  total: '400',
                  balances: [
                    AssetBalance(
                      wallet: 'Spot',
                      asset: 'BTC',
                      total: '4',
                      valueUsdt: '400',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        binanceCostControllerProvider.overrideWith(
          (ref) async => _CostController(),
        ),
        binanceCostStateProvider.overrideWith(
          (ref) => Stream.value(
            const BinanceCostView(
              symbols: {
                'Spot:BTCUSDT': BinanceSymbolCost(
                  CostState(quantity: 1, cost: 80),
                  completed: true,
                  stale: true,
                ),
              },
            ),
          ),
        ),
        vndExchangeRateProvider.overrideWith((ref) async => 25400),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(320, 3000),
              textScaler: TextScaler.linear(2),
            ),
            child: PortfolioScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(
      find.textContaining('tính trên 25% lượng · chưa cập nhật'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets(
    'estimates stay separate from USD-M and polling does not run history',
    (tester) async {
      final controller = _CostController();
      const snapshot = AccountSnapshot(
        total: '1200',
        balances: [
          AssetBalance(
            wallet: 'USD-M',
            asset: 'USDT',
            total: '1100',
            valueUsdt: '1100',
            unrealizedPnl: '100',
          ),
          AssetBalance(
            wallet: 'Spot',
            asset: 'BTC',
            total: '1',
            valueUsdt: '100',
          ),
        ],
      );
      const view = BinanceCostView(
        symbols: {
          'Spot:BTCUSDT': BinanceSymbolCost(
            CostState(quantity: 1, cost: 80),
            completed: true,
          ),
        },
      );
      final container = ProviderContainer(
        overrides: [
          selectedConnectionIdProvider.overrideWith((ref) => 'test'),
          exchangeRegistryProvider.overrideWith(
            (ref) => [
              ExchangeRegistration(
                profile: const ConnectionProfile(
                  connectionId: 'test',
                  exchange: ExchangeId.binance,
                  label: 'Binance',
                ),
                adapter: _SnapshotAdapter(snapshot),
              ),
            ],
          ),
          binanceCostControllerProvider.overrideWith((ref) async => controller),
          binanceCostStateProvider.overrideWith((ref) => Stream.value(view)),
          vndExchangeRateProvider.overrideWith((ref) async => 25400),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: PortfolioScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('(+10.00%)'), findsOneWidget);
      expect(find.textContaining('Ước tính Spot · Margin:'), findsOneWidget);
      expect(find.text('Tính trên 1/1 tài sản'), findsOneWidget);
      expect(find.textContaining('Giá vốn TB 80.00'), findsOneWidget);
      expect(controller.runs, 1);
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      await tester.pump();
      expect(controller.runs, 1);
      container.read(hideBalanceProvider.notifier).state = true;
      await tester.pump();
      expect(find.textContaining('Giá vốn TB'), findsNothing);
      expect(find.textContaining('Ước tính Spot · Margin'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    },
  );
  for (final details in [false, true]) {
    for (final scenario in ['binance', 'no-usdm', 'okx']) {
      testWidgets('PnL scope $scenario ${details ? "details" : "home"}', (
        tester,
      ) async {
        final isOkx = scenario == 'okx';
        var costReads = 0;
        final noUsdm = scenario == 'no-usdm';
        final snapshot = AccountSnapshot(
          total: '2000',
          balances: [
            if (!noUsdm)
              const AssetBalance(
                wallet: 'USD-M',
                asset: 'USDT',
                total: '1100',
                valueUsdt: '1100',
                unrealizedPnl: '100',
              ),
            AssetBalance(
              wallet: 'Spot',
              asset: 'OTHER',
              total: noUsdm ? '2000' : '900',
              valueUsdt: noUsdm ? '2000' : '900',
            ),
          ],
        );
        final container = ProviderContainer(
          overrides: [
            if (isOkx)
              binanceCostStateProvider.overrideWith((ref) {
                costReads++;
                return Stream.value(const BinanceCostView());
              }),
            selectedConnectionIdProvider.overrideWith((ref) => 'test'),
            exchangeRegistryProvider.overrideWith(
              (ref) => [
                ExchangeRegistration(
                  profile: ConnectionProfile(
                    connectionId: 'test',
                    exchange: isOkx ? ExchangeId.okx : ExchangeId.binance,
                    label: isOkx ? 'OKX' : 'Binance',
                  ),
                  adapter: _SnapshotAdapter(snapshot),
                ),
              ],
            ),
            livePriceProvider.overrideWith((ref) => LivePriceNotifier()),
            okxWebsocketProvider.overrideWithValue(_Socket()),
            vndExchangeRateProvider.overrideWith((ref) async => 25400),
          ],
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: details
                  ? const PortfolioDetailsScreen()
                  : const PortfolioScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        if (details) {
          await tester.tap(find.byKey(const Key('portfolio-reveal-pnl')));
          await tester.pump();
        }
        expect(
          find.text(
            details
                ? (isOkx ? 'Unrealized PnL' : 'Unrealized PnL · USDⓈ-M')
                : (isOkx
                      ? 'Lãi / lỗ chưa thực hiện'
                      : 'Lãi / lỗ chưa thực hiện · USDⓈ-M'),
          ),
          findsOneWidget,
        );
        if (noUsdm && details) {
          expect(find.text('******'), findsOneWidget);
        } else {
          expect(
            find.text(
              noUsdm
                  ? '(+0.00%)'
                  : isOkx
                  ? '(+5.26%)'
                  : '(+10.00%)',
            ),
            findsOneWidget,
          );
        }
        if (!noUsdm) expect(find.text(r'$1,900.00'), findsOneWidget);
        if (isOkx) expect(costReads, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      });
    }
  }
  testWidgets('fake exchange renders balances without starting OKX prices', (
    tester,
  ) async {
    var priceStarts = 0;
    final socket = _Socket();
    final container = ProviderContainer(
      overrides: [
        selectedConnectionIdProvider.overrideWith((ref) => 'fake'),
        exchangeRegistryProvider.overrideWith(
          (ref) => [
            ExchangeRegistration(
              profile: const ConnectionProfile(
                connectionId: 'fake',
                exchange: ExchangeId.binance,
                label: 'Fake',
              ),
              adapter: _Fake(),
            ),
          ],
        ),
        livePriceProvider.overrideWith((ref) {
          priceStarts++;
          return LivePriceNotifier();
        }),
        okxWebsocketProvider.overrideWithValue(socket),
        vndExchangeRateProvider.overrideWith((ref) async => 25400),
      ],
    );
    addTearDown(container.dispose);
    for (final screen in [
      const PortfolioScreen(),
      const PortfolioDetailsScreen(),
    ]) {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: screen),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('FAKE'), findsOneWidget);
      expect(find.textContaining('42.00'), findsWidgets);
      expect(priceStarts, 0);
      expect(socket.subscriptions, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
  for (final details in [false, true]) {
    testWidgets(
      'late OKX response never renders under fake exchange ${details ? "details" : "home"}',
      (tester) async {
        final pending = Completer<OkxAccountData>();
        var priceStarts = 0;
        final socket = _Socket();
        final container = ProviderContainer(
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
                    connectionId: 'fake',
                    exchange: ExchangeId.binance,
                    label: 'Fake',
                  ),
                  adapter: _Fake(),
                ),
              ],
            ),
            portfolioFutureProvider.overrideWith((ref) => pending.future),
            livePriceProvider.overrideWith((ref) {
              priceStarts++;
              return LivePriceNotifier();
            }),
            okxWebsocketProvider.overrideWithValue(socket),
            vndExchangeRateProvider.overrideWith((ref) async => 25400),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: details
                  ? const PortfolioDetailsScreen()
                  : const PortfolioScreen(),
            ),
          ),
        );
        await tester.pump();
        final beforeSwitchPriceStarts = priceStarts;
        container.read(selectedConnectionIdProvider.notifier).state = 'fake';
        await tester.pump();
        await tester.pump();
        pending.complete(
          const OkxAccountData(
            details: [OkxCoinDetail(ccy: 'LATE', eq: '999', eqUsd: '999')],
          ),
        );
        await tester.pump();
        expect(find.text('FAKE'), findsOneWidget);
        expect(find.textContaining('42.00'), findsWidgets);
        expect(find.text('LATE'), findsNothing);
        expect(find.textContaining('999'), findsNothing);
        expect(socket.subscriptions, 0);
        expect(priceStarts, beforeSwitchPriceStarts);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
