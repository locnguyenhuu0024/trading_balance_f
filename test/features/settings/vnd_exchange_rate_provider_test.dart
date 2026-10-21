import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/currency/coingecko_vnd_rate_client.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
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

  test('loads the credential-free CoinGecko tether VND quote', () async {
    final adapter = _CurrencyAdapter(const {
      'tether': {'vnd': 25431.25},
    });
    final client = _client(adapter);
    final container = ProviderContainer(
      overrides: [coinGeckoVndRateClientProvider.overrideWithValue(client)],
    );
    addTearDown(() {
      container.dispose();
      client.dispose();
    });

    expect(await container.read(vndExchangeRateProvider.future), 25431.25);
    expect(adapter.requests, hasLength(1));
    final request = adapter.requests.single;
    expect(request.uri.origin, CoinGeckoVndRateClient.origin);
    expect(request.uri.path, '/api/v3/simple/price');
    expect(request.uri.queryParameters, {
      'ids': 'tether',
      'vs_currencies': 'vnd',
    });
    expect(request.headers['Authorization'], isNull);
    expect(request.headers.keys, isNot(contains('OK-ACCESS-KEY')));
    expect(request.followRedirects, isFalse);
    expect(request.maxRedirects, 0);
  });

  test('malformed or non-positive rate keeps the local fallback', () async {
    for (final rawRate in <Object?>['NaN', 0, -1, null]) {
      final adapter = _CurrencyAdapter({
        'tether': {'vnd': rawRate},
      });
      final client = _client(adapter);
      final container = ProviderContainer(
        overrides: [coinGeckoVndRateClientProvider.overrideWithValue(client)],
      );

      expect(await container.read(vndExchangeRateProvider.future), 25400.0);
      container.dispose();
      client.dispose();
    }
  });

  test('network and rate-limit failures keep the local fallback', () async {
    for (final statusCode in [429, null]) {
      final adapter = _CurrencyAdapter(const {}, failureStatusCode: statusCode);
      final client = _client(adapter);
      final container = ProviderContainer(
        overrides: [coinGeckoVndRateClientProvider.overrideWithValue(client)],
      );

      expect(await container.read(vndExchangeRateProvider.future), 25400.0);
      container.dispose();
      client.dispose();
    }
  });
}

CoinGeckoVndRateClient _client(HttpClientAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: CoinGeckoVndRateClient.origin))
    ..httpClientAdapter = adapter;
  return CoinGeckoVndRateClient(dio: dio);
}

class _CurrencyAdapter implements HttpClientAdapter {
  _CurrencyAdapter(this.body, {this.failureStatusCode});
  final Object body;
  final int? failureStatusCode;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (failureStatusCode != null) {
      return ResponseBody.fromString(
        jsonEncode(body),
        failureStatusCode!,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (failureStatusCode == null &&
        body is Map<dynamic, dynamic> &&
        (body as Map).isEmpty) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
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
