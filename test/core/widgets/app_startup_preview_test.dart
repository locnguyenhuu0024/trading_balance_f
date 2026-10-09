import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/widgets/app_startup.dart';

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

Future<void> _capture(WidgetTester tester, String name) async {
  debugPrint('startup-render $name: begin');
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('startup-capture-root')),
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
    final directory = Directory('build/startup-preview');
    await directory.create(recursive: true);
    final path = '${directory.path}${Platform.pathSeparator}$name.png';
    await File(path).writeAsBytes(bytes, flush: true);
  });
  debugPrint('startup-render $name: saved');
}

void main() {
  testWidgets('captures startup states at mobile and desktop sizes', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(_loadPreviewFonts);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);

    final pending = Completer<int>();
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('startup-capture-root'),
        child: AppStartup<int>(
          key: const ValueKey('pending-startup'),
          initialize: () => pending.future,
          builder: (context, value) =>
              MaterialApp(home: Scaffold(body: Text('Initialized $value'))),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Đang khởi tạo ứng dụng…'), findsOneWidget);
    await _capture(tester, 'startup-mobile-loading');

    tester.view.physicalSize = const Size(1440, 900);
    await tester.pump();
    await _capture(tester, 'startup-desktop-loading');

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('startup-capture-root'),
        child: AppStartup<int>(
          key: const ValueKey('failed-startup'),
          initialize: () => Future<int>.error(
            StateError('private exception detail stays hidden'),
          ),
          builder: (context, value) =>
              MaterialApp(home: Scaffold(body: Text('Initialized $value'))),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Chưa thể khởi tạo ứng dụng.'), findsOneWidget);
    expect(find.textContaining('private exception detail'), findsNothing);
    await _capture(tester, 'startup-mobile-error');

    tester.view.physicalSize = const Size(1440, 900);
    await tester.pump();
    await _capture(tester, 'startup-desktop-error');

    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('startup-capture-root'),
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
          home: MediaQuery(
            data: const MediaQueryData(
              disableAnimations: true,
              accessibleNavigation: true,
            ),
            child: const AppStartupStatusView(isLoading: true),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.hourglass_empty), findsOneWidget);
    await _capture(tester, 'startup-reduced-motion-static');
  });
}
