import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/features/orders/data/trade_api_client.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/trade_session_provider.dart';
import 'package:trading_balance_f/features/settings/domain/binance_credential_bundle.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_trade_access_page.dart';

class _Storage extends SecureStorageHelper {
  _Storage({this.binanceBundle}) : super(const FlutterSecureStorage());

  String? apiKey = 'saved-okx-key';
  String? secretKey = 'saved-okx-secret';
  String? passphrase = 'saved-okx-passphrase';
  String? binanceBundle;
  int okxSaveCalls = 0;
  int binanceSaveCalls = 0;
  int binanceClearCalls = 0;
  bool failBinanceSave = false;
  bool failBinanceClear = false;

  @override
  Future<String?> getOkxApiKey() async => apiKey;
  @override
  Future<String?> getOkxSecretKey() async => secretKey;
  @override
  Future<String?> getOkxPassphrase() async => passphrase;
  @override
  Future<String?> getBinanceCredentialBundle() async => binanceBundle;

  @override
  Future<void> saveOkxCredentials({
    required String apiKey,
    required String secretKey,
    required String passphrase,
  }) async {
    okxSaveCalls++;
    this.apiKey = apiKey;
    this.secretKey = secretKey;
    this.passphrase = passphrase;
  }

  @override
  Future<void> saveBinanceCredentials({
    required String apiKey,
    required String secretKey,
  }) async {
    binanceSaveCalls++;
    if (failBinanceSave) throw StateError('credential write failed');
    await trackBinanceCredentialMutation(() async {
      binanceBundle = BinanceCredentialBundle.tryCreate(
        apiKey: apiKey,
        secretKey: secretKey,
      )!.encode();
    });
  }

  @override
  Future<void> clearBinanceCredentials() async {
    binanceClearCalls++;
    if (failBinanceClear) throw StateError('credential delete failed');
    await trackBinanceCredentialMutation(() async => binanceBundle = null);
  }
}

class _TradeApi implements TradeApi {
  @override
  bool get isConfigured => false;
  @override
  bool get supportsSessionRestoration => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _page(_Storage storage, {Key? captureKey}) {
  final api = _TradeApi();
  return ProviderScope(
    overrides: [
      secureStorageProvider.overrideWithValue(storage),
      tradeApiProvider.overrideWithValue(api),
      tradeSessionProvider.overrideWith((ref) => TradeSessionController(api)),
    ],
    child: MaterialApp(
      home: captureKey == null
          ? const SettingsTradeAccessPage()
          : RepaintBoundary(
              key: captureKey,
              child: const SettingsTradeAccessPage(),
            ),
    ),
  );
}

Future<void> _ensureVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('GREEN-118 Binance credentials', () {
    testWidgets('Binance two-field save persists independently from OKX', (
      tester,
    ) async {
      final storage = _Storage();
      await tester.pumpWidget(_page(storage));
      await tester.pumpAndSettle();

      final modeToggle = find.byKey(
        const Key('settings-toggle-binance-entry-mode'),
      );
      await _ensureVisible(tester, modeToggle);
      await tester.tap(modeToggle);
      await tester.pumpAndSettle();
      final apiKey = find.byKey(const Key('settings-binance-api-key'));
      final secret = find.byKey(const Key('settings-binance-secret-key'));
      await _ensureVisible(tester, apiKey);
      await tester.enterText(apiKey, 'fixture-binance-key');
      await tester.enterText(secret, 'fixture-binance-secret');
      await _ensureVisible(
        tester,
        find.byKey(const Key('settings-save-binance-credentials')),
      );
      await tester.tap(
        find.byKey(const Key('settings-save-binance-credentials')),
      );
      await tester.pumpAndSettle();

      final bundle = BinanceCredentialBundle.tryDecode(storage.binanceBundle);
      expect(storage.binanceSaveCalls, 1);
      expect(storage.okxSaveCalls, 0);
      expect(bundle?.apiKey, 'fixture-binance-key');
      expect(bundle?.secretKey, 'fixture-binance-secret');
      expect(
        find.byKey(const Key('settings-binance-saved-summary')),
        findsOneWidget,
      );
      expect(find.text('fixture-binance-secret'), findsNothing);
      expect(
        find.byKey(const Key('settings-binance-passphrase')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      storage.dispose();
    });

    testWidgets('Binance credentials render at mobile and desktop widths', (
      tester,
    ) async {
      final storage = _Storage();
      for (final (name, width, height) in <(String, double, double)>[
        ('mobile', 390, 844),
        ('desktop', 1440, 900),
      ]) {
        tester.view.physicalSize = Size(width, height);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          _page(storage, captureKey: const Key('t118-credential-capture')),
        );
        await tester.pumpAndSettle();
        await _ensureVisible(
          tester,
          find.byKey(const Key('settings-binance-credential-bundle')),
        );
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('t118-credential-capture')),
        );
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.png),
        );
        if (bytes != null) {
          await tester.runAsync(
            () => File(
              '/private/tmp/t118_credentials_$name.png',
            ).writeAsBytes(bytes.buffer.asUint8List()),
          );
        }
        image.dispose();
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.pumpWidget(const SizedBox.shrink());
      storage.dispose();
    });
  });

  group('RED-118 Binance credential write failures', () {
    testWidgets(
      'failed Binance save leaves the editor active and reports an error',
      (tester) async {
        final storage = _Storage()..failBinanceSave = true;
        await tester.pumpWidget(_page(storage));
        await tester.pumpAndSettle();

        final toggle = find.byKey(
          const Key('settings-toggle-binance-entry-mode'),
        );
        await _ensureVisible(tester, toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        final apiKey = find.byKey(const Key('settings-binance-api-key'));
        final secret = find.byKey(const Key('settings-binance-secret-key'));
        await _ensureVisible(tester, apiKey);
        await tester.enterText(apiKey, 'fixture-binance-key');
        await tester.enterText(secret, 'fixture-binance-secret');
        await _ensureVisible(
          tester,
          find.byKey(const Key('settings-save-binance-credentials')),
        );
        await tester.tap(
          find.byKey(const Key('settings-save-binance-credentials')),
        );
        await tester.pumpAndSettle();

        expect(storage.binanceSaveCalls, 1);
        expect(storage.okxSaveCalls, 0);
        expect(storage.binanceBundle, isNull);
        expect(
          find.byKey(const Key('settings-binance-input-error')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('settings-binance-api-key')),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        storage.dispose();
      },
    );

    testWidgets(
      'failed Binance clear preserves the saved bundle and reports an error',
      (tester) async {
        final bundle = BinanceCredentialBundle.tryCreate(
          apiKey: 'saved-binance-key',
          secretKey: 'saved-binance-secret',
        )!.encode();
        final storage = _Storage(binanceBundle: bundle)
          ..failBinanceClear = true;
        await tester.pumpWidget(_page(storage));
        await tester.pumpAndSettle();

        final clear = find.byKey(
          const Key('settings-clear-binance-credentials'),
        );
        await _ensureVisible(tester, clear);
        await tester.tap(clear);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Xóa khóa'));
        await tester.pumpAndSettle();

        expect(storage.binanceClearCalls, 1);
        expect(storage.binanceBundle, bundle);
        expect(storage.okxSaveCalls, 0);
        expect(
          find.byKey(const Key('settings-binance-saved-summary')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('settings-binance-input-error')),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        storage.dispose();
      },
    );
  });
}
