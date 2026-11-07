import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/exchange/exchange_models.dart';
import 'package:trading_balance_f/core/exchange/exchange_registry.dart';
import 'package:trading_balance_f/core/exchange/exchange_scope.dart';
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
}
