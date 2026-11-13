import 'dart:async';
import 'package:trading_balance_f/features/orders/presentation/widgets/margin_account_card.dart';
import 'package:trading_balance_f/exchanges/binance/binance_estimated_pnl.dart';
import 'package:trading_balance_f/exchanges/binance/binance_cost_basis.dart';
import 'package:trading_balance_f/exchanges/binance/binance_trade_history.dart';
import 'package:flutter/material.dart';
import 'package:trading_balance_f/core/theme/app_theme.dart';
import 'package:trading_balance_f/core/theme/pnl_color.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/exchange/exchange_models.dart';
import 'package:trading_balance_f/core/widgets/account_state_view.dart';
import 'package:trading_balance_f/core/exchange/exchange_registry.dart';
import 'package:trading_balance_f/core/exchange/exchange_scope.dart';
import 'package:trading_balance_f/exchanges/binance/binance_adapter.dart';
import 'package:trading_balance_f/features/orders/presentation/orders_screen.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/order_provider.dart';
import 'package:trading_balance_f/features/orders/presentation/widgets/order_cancellation_control.dart';
import 'package:trading_balance_f/features/portfolio/presentation/portfolio_screen.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';
import '../../support/fake_exchange_adapter.dart';

class _Fake extends FakeExchangeAdapter {
  _Fake({
    this.accountOverride,
    this.emptyPositions = false,
    this.failureKind = ExchangeFailureKind.other,
  });
  final ExchangeFailureKind failureKind;
  @override
  ExchangeFailure classify(Object error) => ExchangeFailure(failureKind);
  final Future<AccountSnapshot> Function()? accountOverride;
  final bool emptyPositions;
  int positionReads = 0;
  @override
  ExchangeCapabilities get capabilities =>
      const ExchangeCapabilities(readableProducts: ['SWAP', 'SPOT', 'MARGIN']);
  @override
  Future<List<ExchangePosition>> readPositions(
    Ref ref,
    ExchangeScope scope,
  ) async {
    positionReads++;
    return emptyPositions || ref.watch(orderFilterProvider) == 'MARGIN'
        ? []
        : [
            const ExchangePosition(
              key: InstrumentKey(
                exchange: ExchangeId.binance,
                product: 'SWAP',
                nativeId: 'BTCUSDT',
                base: 'BTC',
                quote: 'USDT',
              ),
              productLabel: 'SWAP',
            ),
          ];
  }

  @override
  Future<AccountSnapshot> readAccount(Ref ref, ExchangeScope scope) async {
    accountReads++;
    return accountOverride != null
        ? accountOverride!()
        : const AccountSnapshot(
            balances: [
              AssetBalance(wallet: 'Spot', asset: 'UNKNOWN', total: '1'),
            ],
            marginRows: [
              MarginAccountRow(asset: 'BTC', net: '2', borrowed: '1'),
              MarginAccountRow(
                key: InstrumentKey(
                  exchange: ExchangeId.binance,
                  product: 'MARGIN',
                  nativeId: 'BTCUSDT',
                  base: 'BTC',
                  quote: 'USDT',
                ),
                baseNet: '3',
                indexPrice: '4',
              ),
            ],
          );
  }
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

Future<void> _pumpChip(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('USD-M refresh does not read account', (tester) async {
    final adapter = _Fake();
    final container = _errorContainer(adapter);
    container.read(orderFilterProvider.notifier).state = 'SWAP';
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: OrdersScreen()),
      ),
    );
    await _pumpChip(tester);
    final before = adapter.accountReads;
    final positionsBefore = adapter.positionReads;
    await tester.drag(
      find
          .descendant(
            of: find.byType(RefreshIndicator),
            matching: find.byType(Scrollable),
          )
          .first,
      const Offset(0, 400),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await _pumpChip(tester);
    expect(adapter.positionReads, greaterThan(positionsBefore));
    expect(adapter.accountReads, before);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  for (final isOkx in [true, false]) {
    testWidgets(
      'Orders preserves data when cost provider ${isOkx ? "is not built for OKX" : "fails"}',
      (tester) async {
        var controllerBuilds = 0;
        var stateBuilds = 0;
        final container = ProviderContainer(
          overrides: [
            selectedConnectionIdProvider.overrideWith((ref) => 'fake'),
            exchangeRegistryProvider.overrideWith(
              (ref) => [
                ExchangeRegistration(
                  profile: ConnectionProfile(
                    connectionId: 'fake',
                    exchange: isOkx ? ExchangeId.okx : ExchangeId.binance,
                    label: 'Test',
                  ),
                  adapter: _Fake(),
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
            vndExchangeRateProvider.overrideWith((ref) async => 25400),
          ],
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: OrdersScreen()),
          ),
        );
        await _pumpChip(tester);
        expect(find.text('BTC/USDT'), findsWidgets);
        if (isOkx) {
          expect(controllerBuilds, 0);
          expect(stateBuilds, 0);
        } else {
          expect(find.textContaining('Cross Margin'), findsOneWidget);
          expect(find.textContaining('Isolated Margin'), findsOneWidget);
        }
        expect(find.textContaining('Giá vốn TB'), findsNothing);
        expect(find.text('Chưa tính'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      },
    );
  }

  testWidgets(
    'margin estimates hide and account polling does not run history',
    (tester) async {
      final controller = _CostController();
      final adapter = _Fake(
        accountOverride: () async => const AccountSnapshot(
          balances: [
            AssetBalance(
              wallet: 'Cross Margin',
              asset: 'BTC',
              net: '1',
              valueUsdt: '110',
              interest: '0',
            ),
          ],
          marginRows: [MarginAccountRow(asset: 'BTC', net: '1', interest: '0')],
        ),
      );
      final container = ProviderContainer(
        overrides: [
          selectedConnectionIdProvider.overrideWith((ref) => 'fake'),
          exchangeRegistryProvider.overrideWith(
            (ref) => [
              ExchangeRegistration(
                profile: const ConnectionProfile(
                  connectionId: 'fake',
                  exchange: ExchangeId.binance,
                  label: 'Binance',
                ),
                adapter: adapter,
              ),
            ],
          ),
          binanceCostControllerProvider.overrideWith((ref) async => controller),
          binanceCostStateProvider.overrideWith(
            (ref) => Stream.value(
              const BinanceCostView(
                symbols: {
                  'Cross Margin:BTCUSDT': BinanceSymbolCost(
                    CostState(quantity: 1, cost: 100, isMargin: true),
                    completed: true,
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
          child: const MaterialApp(home: OrdersScreen()),
        ),
      );
      await _pumpChip(tester);
      expect(find.textContaining('Giá vốn TB 100.00'), findsOneWidget);
      expect(controller.runs, 1);
      await tester.pump(const Duration(seconds: 6));
      await _pumpChip(tester);
      expect(controller.runs, 1);
      container.read(hideBalanceProvider.notifier).state = true;
      await tester.pump();
      expect(find.textContaining('Giá vốn TB'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    },
  );
  testWidgets('isolated margin card shows profit on own capital', (tester) async {
    const row = MarginAccountRow(
      key: InstrumentKey(exchange: ExchangeId.binance, product: 'MARGIN',
          nativeId: 'BTCUSDT', base: 'BTC', quote: 'USDT'),
      baseNet: '1', indexPrice: '80', quoteNet: '-50.5', quoteInterest: '0.5',
    );
    const view = BinanceCostView(symbols: {
      'Isolated Margin:BTCUSDT': BinanceSymbolCost(
          CostState(quantity: 1, cost: 100, isMargin: true), completed: true),
    });
    final estimate = estimatedMargin(view, true, row, const AccountSnapshot());
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: MarginAccountCard(row: row, estimate: estimate),
    )));
    final pair = tester.widget<Text>(find.text('BTC/USDT'));
    expect(pair.style?.fontSize, 16);
    expect(pair.style?.fontWeight, FontWeight.bold);
    expect(find.text('Isolated Margin'), findsOneWidget);
    final amount = tester.widget<Text>(find.text('-20.50 USDT'));
    expect(amount.style?.fontSize, 22);
    expect(amount.style?.color, PnlColors.lightNegative);
    expect(tester.widget<Text>(find.text('(-41.00%)')).style?.color, PnlColors.lightNegative);
    expect(find.textContaining('Giá vốn TB 100.00'), findsOneWidget);
  });
  testWidgets('margin profit, missing capital, messages and sparse rows', (tester) async {
    const key = InstrumentKey(exchange: ExchangeId.binance, product: 'MARGIN', nativeId: 'BTCUSDT', base: 'BTC', quote: 'USDT');
    const view = BinanceCostView(symbols: {
      'Isolated Margin:BTCUSDT': BinanceSymbolCost(CostState(quantity: -1, cost: 100, isMargin: true), completed: true),
    });
    const short = MarginAccountRow(key: key, baseNet: '-1', indexPrice: '90', quoteNet: '150');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MarginAccountCard(row: short, estimate: estimatedMargin(view, true, short, const AccountSnapshot())))));
    expect(tester.widget<Text>(find.text('+10.00 USDT')).style?.color, PnlColors.lightPositive);
    expect(tester.widget<Text>(find.text('(+20.00%)')).style?.color, PnlColors.lightPositive);
    const loss = MarginAccountRow(key: key, baseNet: '1', indexPrice: '80', quoteNet: '-100.5', quoteInterest: '0.5');
    const longView = BinanceCostView(symbols: {
      'Isolated Margin:BTCUSDT': BinanceSymbolCost(CostState(quantity: 1, cost: 100, isMargin: true), completed: true),
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MarginAccountCard(row: loss, estimate: estimatedMargin(longView, true, loss, const AccountSnapshot())))));
    expect(find.text('-20.50 USDT'), findsOneWidget);
    expect(find.textContaining('%)'), findsNothing);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MarginAccountCard(row: loss, estimate: EstimatedPnlRow(null, 'Chưa đủ dữ liệu giá vốn')))));
    expect(tester.widget<Text>(find.text('Chưa đủ dữ liệu giá vốn')).style?.color, AppPalette.light.muted);
    expect(find.textContaining(' USDT'), findsNothing);
    const sparse = MarginAccountRow(key: InstrumentKey(exchange: ExchangeId.binance, product: 'MARGIN', nativeId: 'ETH-USDT'));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MarginAccountCard(row: sparse))));
    expect(find.text('ETH-USDT'), findsOneWidget);
    expect(find.text('Isolated Margin'), findsOneWidget);
    expect(find.textContaining('—'), findsWidgets);
    expect(find.text('Lãi/lỗ ước tính'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MarginAccountCard(row: MarginAccountRow()))));
    expect(find.text('—'), findsOneWidget);
    expect(find.text('Cross Margin'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('margin estimate wraps at 320 and large text', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const row = MarginAccountRow(
      key: InstrumentKey(
        exchange: ExchangeId.binance,
        product: 'MARGIN',
        nativeId: 'BTCUSDT',
        base: 'BTC',
        quote: 'USDT',
      ),
      baseNet: '4',
      indexPrice: '110',
    );
    const view = BinanceCostView(
      symbols: {
        'Isolated Margin:BTCUSDT': BinanceSymbolCost(
          CostState(quantity: 1, cost: 100, isMargin: true),
          completed: true,
        ),
      },
    );
    final estimate = estimatedMargin(view, true, row, const AccountSnapshot());
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 900),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: MarginAccountCard(row: row, estimate: estimate),
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('tính trên 25% lượng'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final scenario in [(false, false), (true, false), (true, true)]) {
    final (web, proxy) = scenario;
    testWidgets('Binance positions and filters web=$web proxy=$proxy', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          selectedConnectionIdProvider.overrideWith((ref) => 'fake'),
          exchangeRegistryProvider.overrideWith(
            (ref) => [
              ExchangeRegistration(
                profile: const ConnectionProfile(
                  connectionId: 'fake',
                  exchange: ExchangeId.binance,
                  label: 'Binance',
                ),
                adapter: _Fake(),
              ),
            ],
          ),
          binanceIsWebProvider.overrideWithValue(web),
          binanceProxyBaseUrlProvider.overrideWithValue(
            proxy ? 'https://proxy.example' : '',
          ),
          vndExchangeRateProvider.overrideWith((ref) async => 25400),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: OrdersScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('BTC/USDT'), findsWidgets);
      expect(find.text('BTCUSDT'), findsNothing);
      expect(find.text('Tất cả'), findsOneWidget);
      expect(find.text('USDⓈ-M'), findsWidgets);
      expect(find.text('Spot'), !web || proxy ? findsOneWidget : findsNothing);
      expect(
        find.text('Margin'),
        !web || proxy ? findsOneWidget : findsNothing,
      );
      expect(find.textContaining('Cross Margin'), findsOneWidget);
      expect(find.textContaining('Isolated Margin'), findsOneWidget);
      expect(find.textContaining('Lãi vay'), findsNWidgets(3));
      expect(find.textContaining('Lãi:'), findsNothing);
      expect(find.textContaining('—'), findsWidgets);
      expect(find.byType(OrderCancellationControl), findsNothing);
      if (!web || proxy) {
        await tester.tap(find.text('Margin'));
        await _pumpChip(tester);
        expect(find.textContaining('Cross Margin'), findsOneWidget);
        expect(find.textContaining('Isolated Margin'), findsOneWidget);
        expect(find.text('BTC/USDT'), findsOneWidget);
        await tester.tap(find.text('USDⓈ-M').first);
        await _pumpChip(tester);
        expect(find.text('BTC/USDT'), findsWidgets);
        expect(find.textContaining('Cross Margin'), findsNothing);
        expect(find.textContaining('Isolated Margin'), findsNothing);
        await tester.tap(find.text('Tất cả'));
        await _pumpChip(tester);
        expect(find.text('BTC/USDT'), findsWidgets);
        expect(find.textContaining('Cross Margin'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    });
  }
  for (final state in ['loading', 'error', 'partial', 'partialRows', 'empty']) {
    testWidgets('Margin account state: $state', (tester) async {
      final pending = Completer<AccountSnapshot>();
      final adapter = _Fake(
        emptyPositions: true,
        accountOverride: () => switch (state) {
          'loading' => pending.future,
          'error' => Future<AccountSnapshot>.error(Exception('failure')),
          'partial' => Future.value(
            const AccountSnapshot(
              walletResults: [
                WalletResult(wallet: 'Cross Margin', available: false),
              ],
            ),
          ),
          'partialRows' => Future.value(
            const AccountSnapshot(
              walletResults: [
                WalletResult(wallet: 'Cross Margin', available: false),
              ],
              marginRows: [MarginAccountRow(asset: 'BTC', net: '2')],
            ),
          ),
          _ => Future.value(const AccountSnapshot()),
        },
      );
      final container = ProviderContainer(
        overrides: [
          selectedConnectionIdProvider.overrideWith((ref) => 'fake'),
          exchangeRegistryProvider.overrideWith(
            (ref) => [
              ExchangeRegistration(
                profile: const ConnectionProfile(
                  connectionId: 'fake',
                  exchange: ExchangeId.binance,
                  label: 'Binance',
                ),
                adapter: adapter,
              ),
            ],
          ),
          binanceIsWebProvider.overrideWithValue(true),
          binanceProxyBaseUrlProvider.overrideWithValue(
            'https://proxy.example',
          ),
          vndExchangeRateProvider.overrideWith((ref) async => 25400),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: OrdersScreen()),
        ),
      );
      await _pumpChip(tester);
      await tester.tap(find.text('Margin'));
      await _pumpChip(tester);
      expect(
        find.text('Chưa có vị thế trên Binance'),
        state == 'empty' ? findsOneWidget : findsNothing,
      );
      if (state == 'loading')
        expect(find.byType(CircularProgressIndicator), findsWidgets);
      if (state == 'error')
        expect(find.byType(AccountStateView), findsOneWidget);
      if (state == 'partial' || state == 'partialRows')
        expect(find.text('Không thể tải ví Margin chéo'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    });
  }
  for (final kind in [
    ExchangeFailureKind.credential,
    ExchangeFailureKind.other,
  ]) {
    testWidgets('Margin account polling: $kind', (tester) async {
      final adapter = _Fake(
        emptyPositions: true,
        failureKind: kind,
        accountOverride: () => Future.error(Exception('failure')),
      );
      final container = _errorContainer(adapter);
      container.read(orderFilterProvider.notifier).state = 'MARGIN';
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: OrdersScreen()),
        ),
      );
      await _pumpChip(tester);
      final initial = adapter.accountReads;
      await tester.pump(const Duration(seconds: 6));
      await _pumpChip(tester);
      await tester.pump(const Duration(seconds: 6));
      await _pumpChip(tester);
      if (kind == ExchangeFailureKind.credential) {
        expect(adapter.accountReads, 1);
      } else {
        expect(adapter.accountReads, greaterThan(initial));
      }
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    });
  }
  testWidgets('ALL preserves positions when account fails', (tester) async {
    final container = _errorContainer(
      _Fake(accountOverride: () => Future.error(Exception('failure'))),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: OrdersScreen()),
      ),
    );
    await _pumpChip(tester);
    expect(find.text('BTC/USDT'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });
  testWidgets('Margin account error fits large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = _errorContainer(
      _Fake(
        emptyPositions: true,
        accountOverride: () => Future.error(Exception('failure')),
      ),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2),
            ),
            child: const OrdersScreen(),
          ),
        ),
      ),
    );
    await _pumpChip(tester);
    expect(find.byType(AccountStateView), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });
  testWidgets('missing Binance total and unpriced asset are visible', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        selectedConnectionIdProvider.overrideWith((ref) => 'fake'),
        exchangeRegistryProvider.overrideWith(
          (ref) => [
            ExchangeRegistration(
              profile: const ConnectionProfile(
                connectionId: 'fake',
                exchange: ExchangeId.binance,
                label: 'Binance',
              ),
              adapter: _Fake(),
            ),
          ],
        ),
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
    expect(find.text('—'), findsWidgets);
    expect(find.text('Chưa định giá'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });
}

ProviderContainer _errorContainer(_Fake adapter) => ProviderContainer(
  overrides: [
    selectedConnectionIdProvider.overrideWith((ref) => 'fake'),
    exchangeRegistryProvider.overrideWith(
      (ref) => [
        ExchangeRegistration(
          profile: const ConnectionProfile(
            connectionId: 'fake',
            exchange: ExchangeId.binance,
            label: 'Binance',
          ),
          adapter: adapter,
        ),
      ],
    ),
    binanceIsWebProvider.overrideWithValue(true),
    binanceProxyBaseUrlProvider.overrideWithValue('https://proxy.example'),
    vndExchangeRateProvider.overrideWith((ref) async => 25400),
  ],
);
