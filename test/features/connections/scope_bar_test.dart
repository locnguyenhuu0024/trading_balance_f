import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/core/widgets/scope_bar.dart';
import 'package:trading_balance_f/core/exchange/exchange_models.dart';
import 'package:trading_balance_f/core/exchange/exchange_registry.dart';
import 'package:trading_balance_f/core/exchange/exchange_scope.dart';
import 'package:trading_balance_f/exchanges/binance/binance_adapter.dart';
import '../../support/fake_exchange_adapter.dart';

class Keys extends SecureStorageHelper {
  Keys() : super(const FlutterSecureStorage());
  @override
  Future<String?> getOkxApiKey() async => 'key';
  @override
  Future<String?> getOkxSecretKey() async => 'secret';
  @override
  Future<String?> getOkxPassphrase() async => 'pass';
  @override
  Future<String?> getBinanceApiKey() async => null;
  @override
  Future<String?> getBinanceApiSecret() async => null;
}

void main() {
  for (final proxy in [false, true]) {
    testWidgets('bar and picker follow web proxy=$proxy', (tester) async {
      final entries = [
        ExchangeRegistration(
          profile: const ConnectionProfile(
            connectionId: 'fake',
            exchange: ExchangeId.binance,
            label: 'Binance',
          ),
          adapter: FakeExchangeAdapter(),
        ),
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            selectedConnectionIdProvider.overrideWith((ref) => 'fake'),
            exchangeRegistryProvider.overrideWith((ref) => entries),
            configuredConnectionsProvider.overrideWith((ref) async => entries),
            binanceIsWebProvider.overrideWithValue(true),
            binanceProxyBaseUrlProvider.overrideWithValue(
              proxy ? 'https://proxy.example' : '',
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: ScopeBar())),
        ),
      );
      await tester.pumpAndSettle();
      final line = proxy ? 'USDⓈ-M · Spot · Margin' : 'USDⓈ-M';
      expect(find.text(line), findsOneWidget);
      await tester.tap(find.byType(ScopeBar));
      await tester.pumpAndSettle();
      expect(find.text(line), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets(
    'bar has accessible target and picker lists configured connections',
    (tester) async {
      final keys = Keys();
      addTearDown(keys.dispose);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [secureStorageProvider.overrideWithValue(keys)],
          child: const MaterialApp(home: Scaffold(body: ScopeBar())),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(ScopeBar)).height,
        greaterThanOrEqualTo(48),
      );
      expect(find.bySemanticsLabel('OKX, Chính'), findsOneWidget);
      await tester.tap(find.byType(ScopeBar));
      await tester.pumpAndSettle();
      expect(find.text('Chọn sàn & tài khoản'), findsOneWidget);
      expect(find.text('OKX / Chính'), findsWidgets);
      expect(find.text('Binance / Chính'), findsNothing);
      expect(find.text('Đang xem'), findsOneWidget);
      expect(find.text('Chỉ hiển thị một tài khoản mỗi lần.'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Quản lý kết nối'),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );

  testWidgets('bar grows without overflow at large text scale', (tester) async {
    final keys = Keys();
    addTearDown(keys.dispose);
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [secureStorageProvider.overrideWithValue(keys)],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(width: 320, child: ScopeBar()),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(ScopeBar)).height, greaterThan(54));
  });
}
