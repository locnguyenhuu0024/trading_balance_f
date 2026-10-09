import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/theme/app_theme.dart';
import 'package:trading_balance_f/features/fractal_tracker/data/fractal_model.dart';
import 'package:trading_balance_f/features/fractal_tracker/presentation/fractal_screen.dart';
import 'package:trading_balance_f/features/fractal_tracker/presentation/providers/fractal_provider.dart';

FractalData _fractalDataWithPrices() {
  final firstQuarter = QuarterData('Q1')
    ..startTime = DateTime(2026, 1, 1)
    ..open = 123.4567
    ..close = 234.5678
    ..high = 1234567.89
    ..low = 0.00001234;
  final secondQuarter = QuarterData('Q2')..startTime = DateTime(2026, 1, 2);
  final thirdQuarter = QuarterData('Q3')..startTime = DateTime(2026, 1, 3);
  final fourthQuarter = QuarterData('Q4')..startTime = DateTime(2026, 1, 4);

  return FractalData(
    timeframeLabel: 'D1',
    quarters: [firstQuarter, secondQuarter, thirdQuarter, fourthQuarter],
    currentPrice: 0.09117,
  );
}

FractalData _fractalDataWithoutQuarterPrices() {
  return FractalData(
    timeframeLabel: 'D1',
    quarters: [
      QuarterData('Q1'),
      QuarterData('Q2'),
      QuarterData('Q3'),
      QuarterData('Q4'),
    ],
    currentPrice: 0.09117,
  );
}

Widget _screenWithData(FractalData data) {
  return ProviderScope(
    overrides: [
      fractalDataProvider.overrideWith((ref) async => [data]),
    ],
    child: const MaterialApp(home: FractalScreen()),
  );
}

FractalData _populatedMonthlyFractal() {
  final start = DateTime(2026, 1, 1);
  final quarters = [
    QuarterData('Q1')
      ..startTime = start
      ..open = 100
      ..close = 120
      ..high = 130
      ..low = 90
      ..hasAbsoluteHigh = true,
    QuarterData('Q2')
      ..startTime = start.add(const Duration(days: 1))
      ..open = 120
      ..close = 110
      ..high = 125
      ..low = 100,
    QuarterData('Q3')
      ..startTime = start.add(const Duration(days: 2))
      ..open = 110
      ..close = 135
      ..high = 140
      ..low = 105,
    QuarterData('Q4')
      ..startTime = start.add(const Duration(days: 3))
      ..open = 135
      ..close = 130
      ..high = 150
      ..low = 125
      ..hasAbsoluteLow = true,
  ];

  return FractalData(
    timeframeLabel: 'M1',
    quarters: quarters,
    currentPrice: 132.5,
    subCandles: List.generate(
      12,
      (index) => SubCandle(
        '${index + 1}',
        100 + index.toDouble(),
        112 + index.toDouble(),
        94 + index.toDouble(),
        index.isEven ? 108 + index.toDouble() : 98 + index.toDouble(),
      ),
    ),
  );
}

Widget _responsiveScreenWithData(FractalData data, double textScale) {
  return ProviderScope(
    overrides: [
      fractalDataProvider.overrideWith((ref) async => [data]),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return RepaintBoundary(
          key: _fractalPreviewKey,
          child: MediaQuery(
            data: mediaQuery.copyWith(textScaler: TextScaler.linear(textScale)),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: const FractalScreen(),
    ),
  );
}

void main() {
  testWidgets('quick coin preset remains usable at narrow enlarged width', (
    tester,
  ) async {
    await tester.runAsync(_loadFractalPreviewFonts);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 900);
    await tester.pumpWidget(
      _responsiveScreenWithData(_fractalDataWithPrices(), 1.6),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('BMAG Tracker (BTC)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final ethText = find.text('ETH');
    expect(ethText, findsOneWidget);
    final ethPreset = find.ancestor(
      of: ethText,
      matching: find.byType(InkWell),
    );
    expect(tester.getRect(ethPreset).height, greaterThanOrEqualTo(48));
    expect(tester.widget<Text>(ethText).style?.fontSize, 14);
    expect(tester.takeException(), isNull);
    await _writeFractalPreview(
      tester,
      'fractal-coin-preset-mobile-320-scale-1.6.png',
    );

    await tester.tap(ethText);
    await tester.pumpAndSettle();
    expect(find.text('BMAG Tracker (ETH)'), findsOneWidget);
    expect(find.text('Chọn Coin'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('formats Fractal current, open, high and low prices adaptively', (
    tester,
  ) async {
    await tester.pumpWidget(_screenWithData(_fractalDataWithPrices()));
    await tester.pump();
    await tester.pump();

    expect(find.byTooltip('Làm mới dữ liệu'), findsOneWidget);
    expect(find.text(r'$0.09117'), findsOneWidget);
    expect(find.text('Mở: 123.4567'), findsOneWidget);
    expect(find.text('🔥 1,234,567.89'), findsOneWidget);
    expect(find.text('💧 0.00001234'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('keeps missing Fractal quarter prices as placeholders', (
    tester,
  ) async {
    await tester.pumpWidget(
      _screenWithData(_fractalDataWithoutQuarterPrices()),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text(r'$0.09117'), findsOneWidget);
    expect(find.text('Mở: --'), findsOneWidget);
    expect(find.text('🔥 --'), findsOneWidget);
    expect(find.text('💧 --'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('manual Fractal refresh waits for the selected data read', (
    tester,
  ) async {
    final refreshResult = Completer<List<FractalData>>();
    var loads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fractalDataProvider.overrideWith((ref) async {
            loads++;
            if (loads == 1) return [_fractalDataWithPrices()];
            return refreshResult.future;
          }),
        ],
        child: const MaterialApp(home: FractalScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Làm mới dữ liệu'), findsOneWidget);
    await tester.tap(find.byKey(const Key('fractal-manual-refresh')));
    await tester.pump();
    expect(loads, 2);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('fractal-manual-refresh')))
          .onPressed,
      isNull,
    );
    refreshResult.complete([_fractalDataWithPrices()]);
    await tester.pump();
    await tester.pump();
    expect(loads, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'keeps populated Fractal content usable at 320px with large text',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 900);
      final semantics = tester.ensureSemantics();

      try {
        for (final textScale in [1.5, 2.0]) {
          await tester.pumpWidget(
            _responsiveScreenWithData(_populatedMonthlyFractal(), textScale),
          );
          await tester.pump();
          await tester.pump();

          expect(find.text('MA TRẬN ĐỒNG PHA (CONFLUENCE)'), findsOneWidget);
          final refreshRect = tester.getRect(
            find.byKey(const Key('fractal-manual-refresh')),
          );
          expect(refreshRect.width, 48);
          expect(refreshRect.height, 48);
          expect(refreshRect.right, lessThanOrEqualTo(320));
          expect(find.text('LIVE'), findsOneWidget);
          expect(find.text('Tiến trình thời gian:'), findsOneWidget);
          await tester.ensureVisible(find.text('Q1'));
          await tester.pump();
          expect(
            find.bySemanticsLabel(RegExp('Q1:.*tăng, nến rỗng')),
            findsWidgets,
          );
          expect(
            find.bySemanticsLabel(RegExp('Q2:.*giảm, nến đặc')),
            findsWidgets,
          );

          await tester.ensureVisible(find.text('Tăng: nến rỗng'));
          await tester.pump();
          expect(find.text('Tăng: nến rỗng'), findsOneWidget);
          expect(find.text('Giảm: nến đặc'), findsOneWidget);
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(const SizedBox.shrink());
        }
      } finally {
        semantics.dispose();
      }
    },
  );
}

const _fractalPreviewKey = ValueKey('fractal-screen-preview');

Future<void> _loadFractalPreviewFonts() async {
  var directory = File(Platform.resolvedExecutable).absolute.parent;
  while (directory.path != directory.parent.path) {
    final fonts = Directory(
      '${directory.path}${Platform.pathSeparator}bin${Platform.pathSeparator}'
      'cache${Platform.pathSeparator}artifacts${Platform.pathSeparator}'
      'material_fonts',
    );
    if (await fonts.exists()) {
      for (final font in {
        'Roboto': 'roboto-regular.ttf',
        'MaterialIcons': 'materialicons-regular.otf',
      }.entries) {
        final file = File(
          '${fonts.path}${Platform.pathSeparator}${font.value}',
        );
        if (!await file.exists()) continue;
        final bytes = await file.readAsBytes();
        final loader = FontLoader(font.key)
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
      }
      return;
    }
    directory = directory.parent;
  }
}

Future<void> _writeFractalPreview(WidgetTester tester, String filename) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_fractalPreviewKey),
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
    final directory = Directory('build/forms-preview');
    await directory.create(recursive: true);
    await File('${directory.path}/$filename').writeAsBytes(bytes, flush: true);
  });
}
