import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/network/backend_data_client.dart';
import 'package:trading_balance_f/core/currency/currency_display_mode.dart';
import 'package:trading_balance_f/features/orders/data/okx_order_model.dart';
import 'package:trading_balance_f/features/orders/data/okx_position_model.dart';
import 'package:trading_balance_f/features/orders/data/trade_api_client.dart';
import 'package:trading_balance_f/features/orders/presentation/orders_screen.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/order_provider.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/trade_session_provider.dart';
import 'package:trading_balance_f/features/orders/presentation/widgets/trade_account_controls.dart';
import 'package:trading_balance_f/features/portfolio/presentation/portfolio_screen.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';

void main() {
  testWidgets('pending tab keeps its trade control in the body', (
    tester,
  ) async {
    final requests = <Completer<List<OkxOrder>>>[];
    await tester.pumpWidget(
      _ordersScreen(filter: 'ALL', requests: requests, onLoad: () {}),
    );
    await tester.pump();

    expect(find.byKey(const Key('order-tab-select')), findsOneWidget);
    expect(find.byType(TradeAccountControls), findsOneWidget);
    expect(find.byTooltip('Đóng tất cả vị thế'), findsNothing);
    expect(find.byTooltip('Làm mới dữ liệu'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('ALL polling waits five seconds and skips an active load', (
    tester,
  ) async {
    final requests = <Completer<List<OkxOrder>>>[];
    var loadCount = 0;

    await tester.pumpWidget(
      _ordersScreen(
        filter: 'ALL',
        requests: requests,
        onLoad: () => loadCount++,
      ),
    );
    await tester.pump();
    expect(loadCount, 1);
    requests.first.complete(const []);
    await tester.pump();
    await tester.pump();

    await tester.pump(const Duration(seconds: 4));
    expect(loadCount, 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(loadCount, 2);

    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(loadCount, 2);
    expect(find.text('Không có lệnh nào đang chờ khớp.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'single-type polling waits five seconds and skips an active load',
    (tester) async {
      final requests = <Completer<List<OkxOrder>>>[];
      var loadCount = 0;

      await tester.pumpWidget(
        _ordersScreen(
          filter: 'MARGIN',
          requests: requests,
          onLoad: () => loadCount++,
        ),
      );
      await tester.pump();
      expect(loadCount, 1);
      requests.first.complete(const []);
      await tester.pump();
      await tester.pump();

      await tester.pump(const Duration(seconds: 4));
      expect(loadCount, 1);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(loadCount, 2);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(loadCount, 2);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('positions filters reflow beside close-all without overflow', (
    tester,
  ) async {
    await tester.runAsync(_loadOrdersPreviewFonts);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    final scenarios = [
      (
        width: 320.0,
        textScale: 1.0,
        screenshot: 'orders-filters-mobile-320.png',
      ),
      (
        width: 390.0,
        textScale: 1.0,
        screenshot: 'orders-filters-mobile-390.png',
      ),
      (
        width: 390.0,
        textScale: 1.6,
        screenshot: 'orders-filters-mobile-390-scale-1.6.png',
      ),
      (
        width: 1280.0,
        textScale: 1.0,
        screenshot: 'orders-filters-desktop-1280.png',
      ),
    ];

    for (final scenario in scenarios) {
      final width = scenario.width;
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpWidget(
        _positionsOrdersScreen(textScale: scenario.textScale),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TradeAccountControls), findsOneWidget);
      expect(find.byTooltip('Đóng tất cả vị thế'), findsOneWidget);
      expect(find.byTooltip('Làm mới dữ liệu'), findsOneWidget);
      expect(find.text('Đóng tất cả vị thế'), findsNothing);

      final statusRect = tester.getRect(
        find.byKey(const Key('order-tab-select')),
      );
      final typeRect = tester.getRect(
        find.byKey(const Key('order-type-select')),
      );
      final closeAllRect = tester.getRect(find.byTooltip('Đóng tất cả vị thế'));
      final refreshRect = tester.getRect(
        find.byKey(const Key('orders-manual-refresh')),
      );
      final isStacked = width < 600 || scenario.textScale > 1.2;
      if (isStacked) {
        expect(typeRect.top, greaterThanOrEqualTo(statusRect.bottom));
        expect(closeAllRect.bottom, closeTo(typeRect.bottom, 2));
      } else {
        expect(statusRect.top, typeRect.top);
        expect(statusRect.right, lessThan(typeRect.left));
        expect(typeRect.right, lessThan(closeAllRect.left));
        expect(closeAllRect.bottom, closeTo(typeRect.bottom, 2));
      }
      expect(statusRect.left, greaterThanOrEqualTo(0));
      expect(typeRect.left, greaterThanOrEqualTo(0));
      expect(statusRect.right, lessThanOrEqualTo(width));
      expect(typeRect.right, lessThanOrEqualTo(width));
      expect(statusRect.height, greaterThanOrEqualTo(48));
      expect(typeRect.height, greaterThanOrEqualTo(48));
      expect(statusRect.overlaps(typeRect), isFalse);
      expect(statusRect.overlaps(closeAllRect), isFalse);
      expect(typeRect.overlaps(closeAllRect), isFalse);
      expect(closeAllRect.width, 48);
      expect(closeAllRect.height, 48);
      expect(closeAllRect.right, lessThanOrEqualTo(width));
      expect(closeAllRect.left, greaterThanOrEqualTo(0));
      expect(closeAllRect.bottom, lessThanOrEqualTo(900));
      expect(refreshRect.width, 48);
      expect(refreshRect.height, 48);
      expect(refreshRect.right, lessThanOrEqualTo(width));
      expect(refreshRect.left, greaterThanOrEqualTo(0));
      expect(tester.takeException(), isNull);
      await _writeOrdersPreview(tester, scenario.screenshot);

      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('RED-102 signed-out orders keeps refresh visible and disabled', (
    tester,
  ) async {
    final api = TradeApiClient(baseUrl: 'https://trade.example');
    var reads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderFilterProvider.overrideWith((ref) => 'ALL'),
          orderTabProvider.overrideWith((ref) => OrderTab.positions),
          tradeApiProvider.overrideWithValue(api),
          tradeSessionProvider.overrideWith(
            (ref) => TradeSessionController(api),
          ),
          positionsFutureProvider.overrideWith((ref) async {
            reads++;
            return [];
          }),
          themeModeProvider.overrideWith((ref) => ThemeMode.light),
          currencyProvider.overrideWith((ref) => CurrencyDisplayMode.usd),
          vndExchangeRateProvider.overrideWith((ref) async => 25400),
        ],
        child: const MaterialApp(home: OrdersScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final refresh = find.byTooltip('Làm mới dữ liệu');
    expect(refresh, findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('orders-manual-refresh')))
          .onPressed,
      isNull,
    );
    final readsBeforeTap = reads;
    await tester.tap(refresh);
    await tester.pump();
    expect(reads, readsBeforeTap);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('manual refresh reloads the active positions provider only', (
    tester,
  ) async {
    final api = TradeApiClient(baseUrl: 'https://trade.example');
    var positionLoads = 0;
    var orderLoads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderFilterProvider.overrideWith((ref) => 'MARGIN'),
          orderTabProvider.overrideWith((ref) => OrderTab.positions),
          tradeApiProvider.overrideWithValue(api),
          tradeSessionProvider.overrideWith(
            (ref) => _AuthenticatedTradeSessionController(api),
          ),
          tradePositionsProvider.overrideWith((ref) async {
            positionLoads++;
            return const TradePositionsSnapshot(
              accountIdentifier: 'test-account',
              positions: [],
            );
          }),
          ordersFutureProvider.overrideWith((ref) async {
            orderLoads++;
            return const [];
          }),
          themeModeProvider.overrideWith((ref) => ThemeMode.light),
          currencyProvider.overrideWith((ref) => CurrencyDisplayMode.usd),
          vndExchangeRateProvider.overrideWith((ref) async => 25400),
        ],
        child: const MaterialApp(home: OrdersScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(positionLoads, 1);

    await tester.tap(find.byKey(const Key('orders-manual-refresh')));
    await tester.pumpAndSettle();

    expect(positionLoads, 2);
    expect(orderLoads, 0);
    expect(find.text('MARGIN'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('automatic polling stops after a terminal configuration error', (
    tester,
  ) async {
    final api = TradeApiClient(baseUrl: 'https://trade.example');
    var loadCalls = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderFilterProvider.overrideWith((ref) => 'MARGIN'),
          orderTabProvider.overrideWith((ref) => OrderTab.pending),
          tradeApiProvider.overrideWithValue(api),
          tradeSessionProvider.overrideWith(
            (ref) => _AuthenticatedTradeSessionController(api),
          ),
          ordersFutureProvider.overrideWith((ref) async {
            loadCalls++;
            throw const BackendDataException(
              code: 'api_not_configured',
              message: 'Not configured.',
            );
          }),
          themeModeProvider.overrideWith((ref) => ThemeMode.light),
          currencyProvider.overrideWith((ref) => CurrencyDisplayMode.usd),
          vndExchangeRateProvider.overrideWith((ref) async => 25400),
        ],
        child: const MaterialApp(home: OrdersScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(loadCalls, 1);

    await tester.pump(const Duration(seconds: 30));
    expect(loadCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('old positions are hidden while a replacement session loads', (
    tester,
  ) async {
    final api = _PendingTradePositionsApi();
    final session = _AuthenticatedTradeSessionController(api);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderFilterProvider.overrideWith((ref) => 'ALL'),
          orderTabProvider.overrideWith((ref) => OrderTab.positions),
          tradeApiProvider.overrideWithValue(api),
          tradeSessionProvider.overrideWith((ref) => session),
          themeModeProvider.overrideWith((ref) => ThemeMode.light),
          currencyProvider.overrideWith((ref) => CurrencyDisplayMode.usd),
          vndExchangeRateProvider.overrideWith((ref) async => 25400),
        ],
        child: const MaterialApp(home: OrdersScreen()),
      ),
    );

    await tester.pump();
    expect(api.requests, hasLength(1));
    api.requests.first.complete(
      const TradePositionsSnapshot(
        accountIdentifier: 'test-account',
        positions: [],
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Không có vị thế nào đang mở.'), findsOneWidget);

    session.replace(accountIdentifier: 'replacement-account');
    await tester.pump();
    await tester.pump();
    expect(api.requests, hasLength(2));
    expect(find.text('Không có vị thế nào đang mở.'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    api.requests.last.complete(
      const TradePositionsSnapshot(
        accountIdentifier: 'replacement-account',
        positions: [],
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Không có vị thế nào đang mở.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Widget _ordersScreen({
  required String filter,
  required List<Completer<List<OkxOrder>>> requests,
  required VoidCallback onLoad,
}) {
  final api = TradeApiClient(baseUrl: 'https://trade.example');
  return ProviderScope(
    overrides: [
      orderFilterProvider.overrideWith((ref) => filter),
      orderTabProvider.overrideWith((ref) => OrderTab.pending),
      tradeApiProvider.overrideWithValue(api),
      tradeSessionProvider.overrideWith(
        (ref) => _AuthenticatedTradeSessionController(api),
      ),
      ordersFutureProvider.overrideWith((ref) {
        onLoad();
        final request = Completer<List<OkxOrder>>();
        requests.add(request);
        return request.future;
      }),
      themeModeProvider.overrideWith((ref) => ThemeMode.light),
      currencyProvider.overrideWith((ref) => CurrencyDisplayMode.usd),
      vndExchangeRateProvider.overrideWith((ref) async => 25400),
    ],
    child: const MaterialApp(home: OrdersScreen()),
  );
}

Widget _positionsOrdersScreen({double textScale = 1.0}) {
  final api = TradeApiClient(baseUrl: 'https://trade.example');
  return ProviderScope(
    overrides: [
      orderFilterProvider.overrideWith((ref) => 'MARGIN'),
      orderTabProvider.overrideWith((ref) => OrderTab.positions),
      tradeApiProvider.overrideWithValue(api),
      tradeSessionProvider.overrideWith(
        (ref) => _AuthenticatedTradeSessionController(api),
      ),
      tradePositionsProvider.overrideWith(
        (ref) async => const TradePositionsSnapshot(
          accountIdentifier: 'test-account',
          positions: [],
        ),
      ),
      themeModeProvider.overrideWith((ref) => ThemeMode.light),
      currencyProvider.overrideWith((ref) => CurrencyDisplayMode.usd),
      vndExchangeRateProvider.overrideWith((ref) async => 25400),
    ],
    child: MaterialApp(
      theme: ThemeData(
        fontFamily: 'Roboto',
        textTheme: ThemeData.light().textTheme.apply(fontFamily: 'Roboto'),
      ),
      builder: (context, child) => DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: 'Roboto'),
        child: RepaintBoundary(
          key: _ordersPreviewKey,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
      home: const OrdersScreen(),
    ),
  );
}

const _ordersPreviewKey = ValueKey('orders-screen-preview');

Future<void> _loadOrdersPreviewFonts() async {
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

Future<void> _writeOrdersPreview(WidgetTester tester, String filename) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_ordersPreviewKey),
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

class _AuthenticatedTradeSessionController extends TradeSessionController {
  _AuthenticatedTradeSessionController(super.api) {
    replace();
  }

  void replace({String accountIdentifier = 'test-account'}) {
    state = TradeSessionState(
      session: TradeSession(
        bearerToken: 'test-token-$accountIdentifier',
        accountIdentifier: accountIdentifier,
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
  }
}

class _PendingTradePositionsApi extends TradeApiClient {
  _PendingTradePositionsApi() : super(baseUrl: 'https://trade.example');

  final List<Completer<TradePositionsSnapshot>> requests = [];

  @override
  Future<TradePositionsSnapshot> getPositions(String bearerToken) {
    final request = Completer<TradePositionsSnapshot>();
    requests.add(request);
    return request.future;
  }

  @override
  Future<TradePositionsSnapshot> getPositionsCancellable(
    String bearerToken, {
    required CancelToken cancelToken,
  }) => getPositions(bearerToken);
}
