import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trading_balance_f/core/exchange/exchange_models.dart';
import 'package:trading_balance_f/core/exchange/exchange_scope.dart';
import 'package:trading_balance_f/core/exchange/scoped_read.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/core/widgets/scope_bar.dart';
import 'package:trading_balance_f/exchanges/binance/binance_private_client.dart';
import 'package:trading_balance_f/features/connections/binance_connection_form.dart';
import 'package:trading_balance_f/features/connections/scope_switch_gate.dart';
import 'package:trading_balance_f/main.dart' show WebStorageHelper;

void main() {
  testWidgets('failed test retains input and shows safe failure class', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = WebStorageHelper(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          binanceConnectionTestProvider.overrideWithValue((key, secret) async {
            throw const BinancePrivateException(
              ExchangeFailure(ExchangeFailureKind.credential),
            );
          }),
        ],
        child: const MaterialApp(home: BinanceConnectionForm()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'my-key');
    await tester.enterText(find.byType(TextField).at(1), 'my-secret');
    await tester.tap(find.text('Kiểm tra kết nối'));
    await tester.pumpAndSettle();
    expect(find.text('Khóa không hợp lệ'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
      'my-key',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      'my-secret',
    );
    final message = tester.widget<Text>(find.text('Khóa không hợp lệ'));
    expect(message.data, isNot(contains('my-key')));
    expect(message.data, isNot(contains('my-secret')));
    await tester.pumpWidget(const SizedBox());
    storage.dispose();
  });

  testWidgets('save adds Binance to picker and deletion falls back to OKX', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'OKX_API_KEY': 'ok',
      'OKX_SECRET_KEY': 'secret',
      'OKX_PASSPHRASE': 'pass',
    });
    final storage = WebStorageHelper(await SharedPreferences.getInstance());
    final container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        scopedAccountProvider.overrideWith(
          (ref, scope) async => const AccountSnapshot(),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ScopeSwitchGate(
            child: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    const ScopeBar(),
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const BinanceConnectionForm(),
                        ),
                      ),
                      child: const Text('Open'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'key');
    await tester.enterText(find.byType(TextField).at(1), 'secret');
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ScopeBar));
    await tester.pumpAndSettle();
    expect(find.text('Binance / Chính'), findsOneWidget);
    await tester.tap(find.text('Binance / Chính'));
    await tester.pumpAndSettle();
    expect(
      container.read(exchangeScopeProvider).connectionId,
      'binance-default',
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xóa kết nối'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xóa kết nối').last);
    await tester.pumpAndSettle();
    expect(container.read(exchangeScopeProvider).connectionId, 'okx-default');
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    storage.dispose();
  });
}
