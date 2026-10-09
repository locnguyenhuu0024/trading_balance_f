import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/network/backend_data_client.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/trade_session_provider.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';

class _SettingsPreferencesStorage extends SecureStorageHelper {
  _SettingsPreferencesStorage() : super(const FlutterSecureStorage());

  int currencyReads = 0;

  @override
  Future<bool> getHideBalanceDefault() async => false;

  @override
  Future<bool> getBiometricAuth() async => true;

  @override
  Future<String> getThemeMode() async => 'system';

  @override
  Future<String> getCurrency() async {
    currencyReads++;
    return 'USD';
  }

  @override
  Future<String> getTimeZoneId() async => 'UTC';

  @override
  Future<double> getAppTextScale() async => 1.0;
}

void main() {
  testWidgets('RED-102 settings refresh reads only the exchange rate', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final storage = _SettingsPreferencesStorage();
    var rateReads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          vndExchangeRateProvider.overrideWith((ref) async {
            rateReads++;
            return 25400 + rateReads.toDouble();
          }),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(rateReads, 1);
    expect(storage.currencyReads, 1);

    final refresh = find.byTooltip('Làm mới dữ liệu');
    expect(refresh, findsOneWidget);
    final refreshRect = tester.getRect(refresh);
    expect(refreshRect.width, 48);
    expect(refreshRect.height, 48);
    expect(refreshRect.right, lessThanOrEqualTo(320));
    await tester.tap(refresh);
    await tester.pumpAndSettle();

    expect(rateReads, 2);
    expect(storage.currencyReads, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'loads the public USDT-VND rate without login or auth headers',
    () async {
      final adapter = _CurrencyAdapter({
        'code': '0',
        'data': [
          {'instId': 'USDT-VND', 'rate': '25431.25', 'source': 'CoinGecko'},
        ],
      });
      final container = ProviderContainer(
        overrides: [
          backendDataClientProvider.overrideWithValue(_client(adapter)),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(vndExchangeRateProvider.future), 25431.25);
      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.uri.path, '/v1/data/currency/usdt-vnd');
      expect(adapter.requests.single.headers['Authorization'], isNull);
    },
  );

  test('malformed or non-positive rate keeps the local fallback', () async {
    for (final rawRate in ['NaN', '0', '-1', 12345]) {
      final adapter = _CurrencyAdapter({
        'code': '0',
        'data': [
          {'instId': 'USDT-VND', 'rate': rawRate, 'source': 'CoinGecko'},
        ],
      });
      final container = ProviderContainer(
        overrides: [
          backendDataClientProvider.overrideWithValue(_client(adapter)),
        ],
      );

      expect(await container.read(vndExchangeRateProvider.future), 25400.0);
      container.dispose();
    }
  });
}

BackendDataClient _client(HttpClientAdapter adapter) => BackendDataClient(
  dio: Dio()..httpClientAdapter = adapter,
  baseUrl: 'https://data.example',
);

class _CurrencyAdapter implements HttpClientAdapter {
  _CurrencyAdapter(this.body);
  final Object body;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
