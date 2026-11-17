import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/exchange/exchange_models.dart';
import 'package:trading_balance_f/core/exchange/exchange_registry.dart';
import 'package:trading_balance_f/core/exchange/exchange_scope.dart';
import 'package:trading_balance_f/core/exchange/scoped_read.dart';
import 'package:trading_balance_f/core/navigation/main_navigation_shell.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/order_provider.dart';
import 'package:trading_balance_f/main.dart' as app;
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/features/connections/scope_switch_gate.dart';
import '../../support/fake_exchange_adapter.dart';

class Keys extends SecureStorageHelper {
  Keys() : super(const FlutterSecureStorage());
  bool binance = true;
  String saved = 'okx-default';
  @override
  Future<String?> getOkxApiKey() async => 'key';
  @override
  Future<String?> getOkxSecretKey() async => 'secret';
  @override
  Future<String?> getOkxPassphrase() async => 'pass';
  @override
  Future<String?> getBinanceApiKey() async => binance ? 'key' : null;
  @override
  Future<String?> getBinanceApiSecret() async => binance ? 'secret' : null;
  @override
  Future<void> saveSelectedConnectionId(String id) async {
    saved = id;
  }

  @override
  Future<String> getSelectedConnectionId() async => saved;
}

class PendingAdapter extends FakeExchangeAdapter {
  final pending = Completer<AccountSnapshot>();
  @override
  Future<AccountSnapshot> readAccount(Ref ref, ExchangeScope scope) =>
      pending.future;
}

List<ExchangeRegistration> fakeRegistry({FakeExchangeAdapter? binance}) => [
  ExchangeRegistration(
    profile: const ConnectionProfile(
      connectionId: 'okx-default',
      exchange: ExchangeId.okx,
      label: 'OKX',
    ),
    adapter: FakeExchangeAdapter(),
  ),
  ExchangeRegistration(
    profile: const ConnectionProfile(
      connectionId: 'binance-default',
      exchange: ExchangeId.binance,
      label: 'Binance',
    ),
    adapter: binance ?? FakeExchangeAdapter(),
  ),
];

class RefreshAdapter extends FakeExchangeAdapter {
  final pending = Completer<AccountSnapshot>();
  int calls = 0;
  @override
  Future<AccountSnapshot> readAccount(Ref ref, ExchangeScope scope) {
    calls++;
    return calls == 1 ? Future.value(const AccountSnapshot()) : pending.future;
  }
}

void main() {
  testWidgets('switch shows target loading and removes former data', (
    tester,
  ) async {
    final keys = Keys();
    final adapter = PendingAdapter();
    addTearDown(keys.dispose);
    final container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(keys),
        exchangeRegistryProvider.overrideWith(
          (ref) => [
            ExchangeRegistration(
              profile: const ConnectionProfile(
                connectionId: 'okx-default',
                exchange: ExchangeId.okx,
                label: 'OKX',
              ),
              adapter: FakeExchangeAdapter(),
            ),
            ExchangeRegistration(
              profile: const ConnectionProfile(
                connectionId: 'binance-default',
                exchange: ExchangeId.binance,
                label: 'Binance',
              ),
              adapter: adapter,
            ),
          ],
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: ScopeSwitchGate(child: Text('former data'))),
        ),
      ),
    );
    await tester.pump();
    container.read(selectConnectionProvider)('binance-default');
    await tester.pump();
    expect(find.text('Đang tải Binance / Chính'), findsOneWidget);
    expect(find.text('former data'), findsNothing);
    adapter.pending.complete(const AccountSnapshot());
    await tester.pump();
    await tester.pump();
    expect(find.text('former data'), findsOneWidget);
    expect(await keys.getSelectedConnectionId(), 'binance-default');
  });
  testWidgets('removed selected Binance keys fall back to OKX', (tester) async {
    final keys = Keys()..binance = false;
    addTearDown(keys.dispose);
    final container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(keys),
        selectedConnectionIdProvider.overrideWith((ref) => 'binance-default'),
        exchangeRegistryProvider.overrideWith((ref) => fakeRegistry()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: ScopeSwitchGate(child: Text('account'))),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(container.read(exchangeScopeProvider).connectionId, 'okx-default');
  });
  testWidgets('selection survives restart through storage', (tester) async {
    final keys = Keys();
    addTearDown(keys.dispose);
    final container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(keys),
        exchangeRegistryProvider.overrideWith((ref) => fakeRegistry()),
      ],
    );
    container.read(selectConnectionProvider)('binance-default');
    await tester.pump();
    await tester.pump();
    container.dispose();
    final startup = (await tester.runAsync(
      () => app.initializeAppStartup(
        isWeb: false,
        createNativeStorage: () => keys,
        initializeTimeZone: () {},
        retireLegacyBackgroundService: () async {},
      ),
    ))!;
    expect(startup.selectedConnectionId, 'binance-default');
    await tester.pumpWidget(
      app.buildInitializedApp(startup, home: const SizedBox()),
    );
    final restored = ProviderScope.containerOf(
      tester.element(find.byType(SizedBox).first),
    );
    expect(
      restored.read(exchangeScopeProvider).connectionId,
      'binance-default',
    );
  });

  testWidgets('manual refresh keeps account visible', (tester) async {
    final keys = Keys();
    final adapter = RefreshAdapter();
    addTearDown(keys.dispose);
    final container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(keys),
        exchangeRegistryProvider.overrideWith(
          (ref) => fakeRegistry(binance: adapter),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: ScopeSwitchGate(child: Text('account'))),
        ),
      ),
    );
    await tester.pump();
    container.read(selectConnectionProvider)('binance-default');
    await tester.pump();
    await tester.pump();
    expect(find.text('account'), findsOneWidget);
    final scope = container.read(exchangeScopeProvider);
    container.invalidate(scopedAccountProvider(scope));
    await tester.pump();
    expect(find.text('account'), findsOneWidget);
    expect(find.text('Đang tải Binance / Chính'), findsNothing);
    adapter.pending.complete(const AccountSnapshot());
    await tester.pump();
  });

  testWidgets(
    'switch resets destination, filter and tab including a pushed route',
    (tester) async {
      final keys = Keys();
      addTearDown(keys.dispose);
      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(keys),
          exchangeRegistryProvider.overrideWith((ref) => fakeRegistry()),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: MainNavigationShell(
              destinationBuilder: (context, index) => Text('Screen $index'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('navigation-destination-1')));
      await tester.pumpAndSettle();
      expect(find.text('Screen 1'), findsOneWidget);
      // Keep the providers alive as the actual Orders screen does.
      final filter = container.listen(orderFilterProvider, (_, __) {});
      final tab = container.listen(orderTabProvider, (_, __) {});
      addTearDown(filter.close);
      addTearDown(tab.close);
      container.read(orderFilterProvider.notifier).state = 'SWAP';
      container.read(orderTabProvider.notifier).state = OrderTab.history;
      container.read(selectConnectionProvider)('binance-default');
      await tester.pumpAndSettle();
      expect(find.text('Screen 0'), findsOneWidget);
      expect(container.read(orderFilterProvider), 'ALL');
      expect(container.read(orderTabProvider), OrderTab.positions);
      await tester.tap(find.byKey(const Key('navigation-destination-1')));
      await tester.pumpAndSettle();
      container.read(orderFilterProvider.notifier).state = 'SWAP';
      container.read(orderTabProvider.notifier).state = OrderTab.history;
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('pushed tool')),
        ),
      );
      await tester.pumpAndSettle();
      container.read(selectConnectionProvider)('okx-default');
      await tester.pumpAndSettle();
      expect(find.text('pushed tool'), findsNothing);
      expect(find.text('Screen 0'), findsOneWidget);
      expect(container.read(orderFilterProvider), 'ALL');
      expect(container.read(orderTabProvider), OrderTab.positions);
    },
  );
}
