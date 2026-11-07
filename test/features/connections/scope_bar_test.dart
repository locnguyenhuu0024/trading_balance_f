import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/core/widgets/scope_bar.dart';

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
  testWidgets(
    'bar has accessible target and picker lists configured connections',
    (tester) async {
      final keys = Keys();
      addTearDown(keys.dispose);
      final semantics = tester.ensureSemantics();
      addTearDown(semantics.dispose);
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
    },
  );
}
