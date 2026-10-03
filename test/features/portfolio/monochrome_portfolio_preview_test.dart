import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/currency/currency_display_mode.dart';
import 'package:trading_balance_f/core/navigation/main_navigation_shell.dart';
import 'package:trading_balance_f/core/network/okx_websocket_service.dart';
import 'package:trading_balance_f/core/typography/app_text_scale.dart';
import 'package:trading_balance_f/features/market/presentation/providers/market_provider.dart';
import 'package:trading_balance_f/features/portfolio/data/okx_balance_model.dart';
import 'package:trading_balance_f/features/portfolio/presentation/providers/portfolio_provider.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';
import 'package:trading_balance_f/main.dart';

class _PreviewWebsocketService extends OkxWebsocketService {
  @override
  Stream<dynamic> get stream => const Stream.empty();

  @override
  void connect() {}

  @override
  void subscribeToTickers(List<String> coinSymbols) {}

  @override
  void disconnect() {}
}

const _portfolioPreviewKey = ValueKey('monochrome-portfolio-preview');

Future<Directory?> _findMaterialFontsDirectory() async {
  var directory = File(Platform.resolvedExecutable).absolute.parent;
  while (directory.path != directory.parent.path) {
    final candidate = Directory(
      '${directory.path}${Platform.pathSeparator}bin${Platform.pathSeparator}'
      'cache${Platform.pathSeparator}artifacts${Platform.pathSeparator}'
      'material_fonts',
    );
    if (await candidate.exists()) return candidate;
    directory = directory.parent;
  }
  return null;
}

Future<void> _loadPreviewFonts() async {
  final fontsDirectory = await _findMaterialFontsDirectory();
  if (fontsDirectory == null) return;

  for (final font in {
    'Roboto': 'roboto-regular.ttf',
    'MaterialIcons': 'materialicons-regular.otf',
  }.entries) {
    final fontFile = File(
      '${fontsDirectory.path}${Platform.pathSeparator}${font.value}',
    );
    if (!await fontFile.exists()) continue;
    final fontBytes = await fontFile.readAsBytes();
    final loader = FontLoader(font.key)
      ..addFont(Future.value(ByteData.sublistView(fontBytes)));
    await loader.load();
  }
}

Widget _previewApp(ThemeMode mode, {double appTextScale = 1.0}) {
  const account = OkxAccountData(
    details: [
      OkxCoinDetail(ccy: 'BTC', eq: '0.125', eqUsd: '12500', upl: '0.00025'),
      OkxCoinDetail(
        ccy: 'ETH',
        eq: '2.5',
        eqUsd: '7000',
        upl: '-0.017857142857',
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      portfolioFutureProvider.overrideWith((ref) async => account),
      livePriceProvider.overrideWith((ref) => LivePriceNotifier()),
      okxWebsocketProvider.overrideWithValue(_PreviewWebsocketService()),
      currencyProvider.overrideWith((ref) => CurrencyDisplayMode.usdtVnd),
      vndExchangeRateProvider.overrideWith((ref) async => 25400),
      themeModeProvider.overrideWith((ref) => mode),
      appTextScaleProvider.overrideWith((ref) => appTextScale),
    ],
    child: RepaintBoundary(
      key: _portfolioPreviewKey,
      child: const TradingBalanceApp(requireBiometrics: false),
    ),
  );
}

Future<void> _writePreview(WidgetTester tester, String filename) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_portfolioPreviewKey),
  );
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
  expect(image, isNotNull);
  final capturedImage = image!;
  final png = await tester.runAsync(
    () => capturedImage.toByteData(format: ui.ImageByteFormat.png),
  );
  capturedImage.dispose();
  expect(png, isNotNull);

  final bytes = png!.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
  await tester.runAsync(() async {
    final directory = Directory('build/monochrome-preview');
    await directory.create(recursive: true);
    await File('${directory.path}/$filename').writeAsBytes(bytes, flush: true);
  });
}

void main() {
  testWidgets('captures the real portfolio shell in both monochrome themes', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    await tester.runAsync(_loadPreviewFonts);

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      await tester.pumpWidget(_previewApp(mode));
      await tester.pump();
      await tester.pump();

      expect(find.byType(MainNavigationShell), findsOneWidget);
      expect(find.text('Tài sản chi tiết'), findsOneWidget);
      expect(find.text('BTC'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _writePreview(
        tester,
        mode == ThemeMode.light ? 'portfolio-light.png' : 'portfolio-dark.png',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }

    tester.view.physicalSize = const Size(320, 900);
    await tester.pumpWidget(
      _previewApp(ThemeMode.light, appTextScale: AppTextScale.maxScale),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(MainNavigationShell), findsOneWidget);
    expect(find.text('Tài sản chi tiết'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
