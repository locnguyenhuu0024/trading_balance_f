import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/features/connections/binance_connection_form.dart';
import 'package:trading_balance_f/core/exchange/exchange_models.dart';
import 'package:trading_balance_f/core/exchange/exchange_registry.dart';
import 'package:trading_balance_f/core/exchange/exchange_scope.dart';
import 'package:trading_balance_f/exchanges/binance/binance_adapter.dart';
import 'package:trading_balance_f/features/portfolio/presentation/portfolio_screen.dart';
import 'package:trading_balance_f/features/orders/presentation/orders_screen.dart';
import 'package:trading_balance_f/core/widgets/scope_bar.dart';
import 'package:trading_balance_f/exchanges/okx/okx_adapter.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/order_provider.dart';
import 'package:trading_balance_f/features/portfolio/presentation/portfolio_details_screen.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';
import '../../support/fake_exchange_adapter.dart';

class _Keys extends SecureStorageHelper {
  _Keys() : super(const FlutterSecureStorage());
  @override
  Future<String?> getBinanceApiKey() async => 'key';
  @override
  Future<String?> getBinanceApiSecret() async => 'secret';
}

class _Adapter extends FakeExchangeAdapter {
  _Adapter({this.failure, this.account});
  final ExchangeFailureKind? failure;
  final AccountSnapshot? account;
  @override
  Future<AccountSnapshot> readAccount(Ref ref, ExchangeScope scope) async {
    accountReads++;
    if (failure != null) throw Exception('secret');
    return account!;
  }

  @override
  ExchangeFailure classify(Object error) =>
      ExchangeFailure(failure ?? ExchangeFailureKind.other);
}

void main() {
  const profile = ConnectionProfile(
    connectionId: 'fake',
    exchange: ExchangeId.binance,
    label: 'Binance',
  );
  testWidgets(
    'credential failure hides raw error and stops automatic refresh',
    (tester) async {
      final adapter = _Adapter(failure: ExchangeFailureKind.credential);
      final keys = _Keys();
      addTearDown(keys.dispose);
      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(keys),
          selectedConnectionIdProvider.overrideWith((ref) => 'fake'),
          exchangeRegistryProvider.overrideWith(
            (ref) => [ExchangeRegistration(profile: profile, adapter: adapter)],
          ),
          vndExchangeRateProvider.overrideWith((ref) async => 25400),
        ],
      );
      addTearDown(container.dispose);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: PortfolioScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Cần kiểm tra lại kết nối'), findsOneWidget);
      final scopeBar = find.byType(ScopeBar);
      final refresh = find.byKey(const Key('portfolio-manual-refresh'));
      expect(find.descendant(of: scopeBar, matching: find.text('Binance')), findsOneWidget);
      expect(find.descendant(of: scopeBar, matching: find.text('Binance / Ch\u00ednh')), findsNothing);
      expect(find.text('Binance / Ch\u00ednh'), findsOneWidget);
      expect(find.text('USD\u24c8-M \u00b7 Spot \u00b7 Margin'), findsNothing);
      final sharedRows = find.ancestor(of: scopeBar, matching: find.byType(Row));
      expect(sharedRows.evaluate().any((row) => find.descendant(
        of: find.byWidget(row.widget), matching: refresh,
      ).evaluate().isNotEmpty), isTrue);
      expect(tester.getCenter(scopeBar).dx, lessThan(tester.getCenter(refresh).dx));
      expect(find.text('Kiểm tra kết nối'), findsOneWidget);
      expect(find.textContaining('secret'), findsNothing);
      final reads = adapter.accountReads;
      await tester.pump(const Duration(seconds: 11));
      expect(adapter.accountReads, reads);
      await tester.tap(find.text('Kiểm tra kết nối'));
      await tester.pumpAndSettle();
      expect(find.byType(BinanceConnectionForm), findsOneWidget);
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('generic failure retries without showing raw error', (
    tester,
  ) async {
    final adapter = _Adapter(failure: ExchangeFailureKind.other);
    final container = ProviderContainer(
      overrides: [
        selectedConnectionIdProvider.overrideWith((ref) => 'fake'),
        exchangeRegistryProvider.overrideWith(
          (ref) => [ExchangeRegistration(profile: profile, adapter: adapter)],
        ),
        vndExchangeRateProvider.overrideWith((ref) async => 25400),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PortfolioScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('secret'), findsNothing);
    final reads = adapter.accountReads;
    await tester.tap(find.text('Thử lại'));
    await tester.pump();
    await tester.pump();
    expect(adapter.accountReads, greaterThan(reads));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final details in [false, true]) {
    for (final proxy in [false, true]) {
      testWidgets(
        'partial wallet results on ${details ? 'details' : 'home'} proxy=$proxy',
        (tester) async {
          final adapter = _Adapter(
            account: const AccountSnapshot(
              total: '10',
              balances: [],
              isPartial: true,
              walletResults: [
                WalletResult(wallet: 'Cross Margin', available: false),
              ],
              issues: ['secret English issue'],
            ),
          );
          final container = ProviderContainer(
            overrides: [
              selectedConnectionIdProvider.overrideWith((ref) => 'fake'),
              exchangeRegistryProvider.overrideWith(
                (ref) => [
                  ExchangeRegistration(profile: profile, adapter: adapter),
                ],
              ),
              binanceIsWebProvider.overrideWith((ref) => true),
              binanceProxyBaseUrlProvider.overrideWithValue(
                proxy ? 'https://proxy.example' : '',
              ),
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
          await tester.pump();
          expect(find.text('Chưa đầy đủ'), details ? findsOneWidget : findsNothing);
          expect(find.text('Không thể tải ví Margin chéo'), findsOneWidget);
          expect(
            find.text('Spot và Margin chỉ có trên ứng dụng'),
            proxy ? findsNothing : findsOneWidget,
          );
          expect(find.textContaining('secret'), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
  testWidgets('Binance history displays covered symbols', (tester) async {
    final adapter = _Adapter(account: const AccountSnapshot());
    final container = ProviderContainer(
      overrides: [
        selectedConnectionIdProvider.overrideWith((ref) => 'fake'),
        exchangeRegistryProvider.overrideWith(
          (ref) => [ExchangeRegistration(profile: profile, adapter: adapter)],
        ),
        orderTabProvider.overrideWith((ref) => OrderTab.history),
        binanceHistorySymbolsProvider.overrideWith(
          (ref, scope) async => ['BTCUSDT', 'ETHUSDT'],
        ),
        vndExchangeRateProvider.overrideWith((ref) async => 25400),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: OrdersScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Lịch sử của: BTCUSDT, ETHUSDT'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('expired Binance keeps OKX selectable in picker', (tester) async {
    final adapter = _Adapter(failure: ExchangeFailureKind.credential);
    final entries = [
      const ExchangeRegistration(
        profile: ConnectionProfile(
          connectionId: 'okx-default',
          exchange: ExchangeId.okx,
          label: 'OKX',
        ),
        adapter: OkxAdapter(),
      ),
      ExchangeRegistration(profile: profile, adapter: adapter),
    ];
    final container = ProviderContainer(
      overrides: [
        selectedConnectionIdProvider.overrideWith((ref) => 'fake'),
        exchangeRegistryProvider.overrideWith((ref) => entries),
        configuredConnectionsProvider.overrideWith((ref) async => entries),
        vndExchangeRateProvider.overrideWith((ref) async => 25400),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PortfolioScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Cần kiểm tra lại kết nối'), findsOneWidget);
    await tester.tap(find.byType(ScopeBar));
    await tester.pumpAndSettle();
    expect(find.text('OKX / Chính'), findsOneWidget);
    expect(find.text('Chuyển sang tài khoản này'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
