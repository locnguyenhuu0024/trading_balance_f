import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/currency/currency_display_mode.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';

class _PendingStorageHelper extends SecureStorageHelper {
  _PendingStorageHelper() : super(const FlutterSecureStorage());

  String? savedCurrency;

  @override
  Future<String?> getOkxApiKey() => Completer<String?>().future;

  @override
  Future<void> saveAppPreferences({
    required bool hideBalance,
    required bool bioAuth,
    required String themeMode,
    required String currency,
  }) async {
    savedCurrency = currency;
  }
}

void main() {
  testWidgets('offers USDT + VND as a display currency option', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStorageProvider.overrideWithValue(_PendingStorageHelper()),
          vndExchangeRateProvider.overrideWith((ref) async => 25400),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );

    final currencyDropdown = find.byWidgetPredicate(
      (widget) => widget is DropdownButton<String>,
    );
    expect(currencyDropdown, findsOneWidget);

    await tester.tap(currencyDropdown);
    await tester.pumpAndSettle();

    expect(find.text('USDT + VND'), findsOneWidget);
  });

  testWidgets('shows the exchange rate in USDT + VND mode', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStorageProvider.overrideWithValue(_PendingStorageHelper()),
          currencyProvider.overrideWith((ref) => CurrencyDisplayMode.usdtVnd),
          vndExchangeRateProvider.overrideWith((ref) async => 25400),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('1 USDT ≈ 25,400 đ'), findsOneWidget);
  });

  testWidgets('persists USDT_VND when the dual option is selected', (
    tester,
  ) async {
    final storage = _PendingStorageHelper();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          vndExchangeRateProvider.overrideWith((ref) async => 25400),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );

    final currencyDropdown = find.byWidgetPredicate(
      (widget) => widget is DropdownButton<String>,
    );
    await tester.tap(currencyDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('USDT + VND').last);
    await tester.pump();

    expect(storage.savedCurrency, CurrencyDisplayMode.usdtVnd);
  });
}
