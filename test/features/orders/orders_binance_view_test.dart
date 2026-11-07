import 'dart:async';
import 'package:flutter/material.dart';
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
  @override
  ExchangeCapabilities get capabilities =>
      const ExchangeCapabilities(readableProducts: ['SWAP', 'SPOT', 'MARGIN']);
  @override
  Future<List<ExchangePosition>> readPositions(
    Ref ref,
    ExchangeScope scope,
  ) async => emptyPositions || ref.watch(orderFilterProvider) == 'MARGIN'
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

Future<void> _pumpChip(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
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
        expect(find.text('BTC/USDT'), findsNothing);
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
