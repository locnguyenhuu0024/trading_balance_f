import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/currency/currency_display_mode.dart';
import 'package:trading_balance_f/core/typography/app_text_scale.dart';
import 'package:trading_balance_f/features/orders/data/okx_order_model.dart';
import 'package:trading_balance_f/features/orders/data/okx_position_model.dart';
import 'package:trading_balance_f/features/orders/data/trade_api_client.dart';
import 'package:trading_balance_f/features/orders/presentation/orders_screen.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/order_provider.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/trade_session_provider.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';
import 'package:trading_balance_f/main.dart';

class _LayoutTradeApi implements TradeApi {
  const _LayoutTradeApi({required this.isConfigured});

  @override
  final bool isConfigured;

  @override
  bool get supportsSessionRestoration => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LayoutTradeSessionController extends TradeSessionController {
  _LayoutTradeSessionController(super.api, {required bool authenticated}) {
    state = TradeSessionState(
      session: authenticated
          ? TradeSession(
              bearerToken: 'layout-test-token',
              accountIdentifier: 'account-42',
              expiresAt: DateTime.now().add(const Duration(hours: 1)),
            )
          : null,
    );
  }
}

OkxPosition _position({
  required String liqPx,
  String notionalUsd = '',
  String instId = 'BTC-USDT-SWAP',
}) {
  return OkxPosition(
    instId: instId,
    posSide: 'long',
    lever: '5',
    avgPx: '0.09117',
    markPx: '0.09118',
    liqPx: liqPx,
    upl: '0',
    uplRatio: '0',
    notionalUsd: notionalUsd,
  );
}

Widget _ordersApp({
  required List<OkxPosition> positions,
  String currency = CurrencyDisplayMode.usd,
  double appTextScale = AppTextScale.defaultScale,
  double? contentTextScale,
  OrderTab selectedTab = OrderTab.positions,
  List<OkxOrder> orders = const [],
  bool authenticated = false,
  bool apiConfigured = false,
}) {
  return ProviderScope(
    overrides: [
      tradeApiProvider.overrideWithValue(
        _LayoutTradeApi(isConfigured: apiConfigured),
      ),
      tradeSessionProvider.overrideWith(
        (ref) => _LayoutTradeSessionController(
          ref.read(tradeApiProvider),
          authenticated: authenticated,
        ),
      ),
      tradePositionsProvider.overrideWith(
        (ref) async => TradePositionsSnapshot(
          accountIdentifier: 'account-42',
          positions: positions,
        ),
      ),
      orderFilterProvider.overrideWith((ref) => 'SWAP'),
      orderTabProvider.overrideWith((ref) => selectedTab),
      ordersFutureProvider.overrideWith((ref) async => orders),
      positionsFutureProvider.overrideWith((ref) async => positions),
      themeModeProvider.overrideWith((ref) => ThemeMode.light),
      currencyProvider.overrideWith((ref) => currency),
      vndExchangeRateProvider.overrideWith((ref) async => 25400),
      appTextScaleProvider.overrideWith((ref) => appTextScale),
    ],
    child: TradingBalanceApp(
      requireBiometrics: false,
      home: contentTextScale == null
          ? const OrdersScreen()
          : Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(contentTextScale)),
                child: const OrdersScreen(),
              ),
            ),
    ),
  );
}

Finder _cardContainingPrice(String price) {
  return find.ancestor(of: find.text(price), matching: find.byType(Card));
}

void main() {
  testWidgets('shows an accessible signed-out status beside the trade title', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(_ordersApp(positions: []));
    await tester.pump();
    await tester.pump();

    expect(find.text('Quản lý Giao dịch'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Chưa đăng nhập')), findsOneWidget);
    final titleRow = find
        .ancestor(
          of: find.text('Quản lý Giao dịch'),
          matching: find.byType(Row),
        )
        .first;
    expect(
      find.descendant(of: titleRow, matching: find.byType(Tooltip)),
      findsOneWidget,
    );
    expect(find.text('Đóng tất cả vị thế'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    semantics.dispose();
  });

  testWidgets('shows a compact close-all action and signed-in title status', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);

    await tester.pumpWidget(
      _ordersApp(positions: [], authenticated: true, apiConfigured: true),
    );
    await tester.pump();
    await tester.pump();

    expect(find.bySemanticsLabel(RegExp('Đã đăng nhập')), findsOneWidget);
    final closeAll = find.widgetWithText(OutlinedButton, 'Đóng tất cả vị thế');
    expect(closeAll, findsOneWidget);
    expect(tester.getSize(closeAll).width, lessThan(390 * 0.8));
    expect(
      find.ancestor(of: closeAll, matching: find.byType(Card)),
      findsNothing,
    );
    expect(find.text('Giao dịch riêng tư'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    semantics.dispose();
  });

  testWidgets('backend positions show unavailable metrics as dashes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _ordersApp(
        positions: [
          const OkxPosition(
            instId: 'BTC-USDT-SWAP',
            posSide: 'net',
            instType: 'SWAP',
            size: '2',
            signedSize: '2',
            direction: 'long',
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    final pnlRow = find
        .ancestor(
          of: find.text('Lãi / Lỗ chưa thực hiện:'),
          matching: find.byType(Row),
        )
        .first;
    expect(
      find.descendant(of: pnlRow, matching: find.text('-- ')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: pnlRow, matching: find.text('--')),
      findsOneWidget,
    );

    final notionalLayout = find
        .ancestor(
          of: find.text('Giá trị vị thế:'),
          matching: find.byType(LayoutBuilder),
        )
        .first;
    expect(
      find.descendant(of: notionalLayout, matching: find.text('--')),
      findsOneWidget,
    );
    final pricesRow = find
        .ancestor(of: find.text('Giá vào'), matching: find.byType(Row))
        .first;
    expect(
      find.descendant(of: pricesRow, matching: find.text('--')),
      findsNWidgets(3),
    );

    final sideAndLeverageRow = find
        .ancestor(of: find.text('VỊ THẾ'), matching: find.byType(Row))
        .first;
    expect(
      find.descendant(of: sideAndLeverageRow, matching: find.text('--')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('position cards follow their content at every viewport width', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final width in [390.0, 600.0, 900.0, 1600.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpWidget(
        _ordersApp(positions: [_position(liqPx: '1234567.89')]),
      );
      await tester.pump();
      await tester.pump();

      final liquidation = find.text('1,234,567.89');
      expect(liquidation, findsOneWidget);
      final card = _cardContainingPrice('1,234,567.89');
      final cardRect = tester.getRect(card);
      final liquidationRect = tester.getRect(liquidation);

      expect(cardRect.height, lessThan(500));
      final actionReason = find.text(
        'Chưa cấu hình TRADE_API_BASE_URL; chỉ xem vị thế.',
      );
      final actionReasonRect = tester.getRect(actionReason);
      expect(cardRect.bottom - actionReasonRect.bottom, closeTo(12, 0.5));
      expect(
        cardRect.contains(tester.getRect(find.text('Đóng 100%')).center),
        isTrue,
      );
      expect(actionReasonRect.top, greaterThan(liquidationRect.bottom));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('advances a variable-height position row by its tallest card', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 900);

    await tester.pumpWidget(
      _ordersApp(
        currency: CurrencyDisplayMode.usdtVnd,
        positions: [
          _position(liqPx: '1000'),
          _position(liqPx: '2000', notionalUsd: '100'),
          _position(liqPx: '3000'),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    final firstCard = tester.getRect(_cardContainingPrice('1,000.00'));
    final secondCard = tester.getRect(_cardContainingPrice('2,000.00'));
    final thirdCard = tester.getRect(_cardContainingPrice('3,000.00'));

    expect(firstCard.top, secondCard.top);
    expect(secondCard.height, greaterThan(firstCard.height));
    expect(
      thirdCard.top,
      closeTo(
        (firstCard.bottom > secondCard.bottom
                ? firstCard.bottom
                : secondCard.bottom) +
            12,
        0.5,
      ),
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'keeps the final price inside cards for every currency mode and text scale',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 900);

      const currencies = [
        CurrencyDisplayMode.usd,
        CurrencyDisplayMode.vnd,
        CurrencyDisplayMode.usdtVnd,
      ];
      const liquidationPrice = '9,876,543.21';

      for (final currency in currencies) {
        for (final scale in AppTextScale.options.map(
          (option) => option.value,
        )) {
          await tester.pumpWidget(
            _ordersApp(
              currency: currency,
              appTextScale: scale,
              positions: [_position(liqPx: '9876543.21', notionalUsd: '100')],
            ),
          );
          await tester.pump();
          await tester.pump();

          final liquidation = find.text(liquidationPrice);
          expect(liquidation, findsOneWidget);
          final cardRect = tester.getRect(
            _cardContainingPrice(liquidationPrice),
          );
          final liquidationRect = tester.getRect(liquidation);
          final actionReason = tester.getRect(
            find.text('Chưa cấu hình TRADE_API_BASE_URL; chỉ xem vị thế.'),
          );
          // Dual-currency rows may grow with larger text; every value and action
          // must remain inside the card instead of being clipped to a fixed cap.
          expect(cardRect.contains(liquidationRect.center), isTrue);
          expect(cardRect.contains(actionReason.center), isTrue);
          expect(cardRect.bottom - actionReason.bottom, closeTo(12, 0.5));
          expect(
            cardRect.contains(tester.getRect(find.text('Đóng 100%')).center),
            isTrue,
          );
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    },
  );

  testWidgets(
    'pending and history orders follow content at narrow and wide widths',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;

      for (final tab in [OrderTab.pending, OrderTab.history]) {
        double? compactDefaultCardHeight;
        double? compactLargeTextCardHeight;
        const scenarios = [
          (width: 320.0, textScale: 1.0),
          (width: 320.0, textScale: 2.0),
          (width: 1200.0, textScale: 1.5),
        ];

        for (final scenario in scenarios) {
          tester.view.physicalSize = Size(scenario.width, 900);
          final order = OkxOrder(
            instId: 'BTC-USDT-SWAP',
            instType: 'SWAP',
            side: 'buy',
            px: '9876543.21',
            sz: '0.123456789',
            notionalUsd: '10000',
            fillNotionalUsd: tab == OrderTab.history ? '8000' : '',
            state: tab == OrderTab.pending ? 'live' : 'filled',
            cTime: '1767225600000',
          );

          await tester.pumpWidget(
            _ordersApp(
              positions: const [],
              currency: CurrencyDisplayMode.usdtVnd,
              contentTextScale: scenario.textScale,
              selectedTab: tab,
              orders: [order],
            ),
          );
          await tester.pump();
          await tester.pump();

          final card = find
              .ancestor(
                of: find.text('BTC-USDT-SWAP'),
                matching: find.byType(Card),
              )
              .first;
          final cardRect = tester.getRect(card);
          final price = find.textContaining('Giá:');
          final size = find.textContaining('KL:');
          final vndAmount = find.descendant(
            of: card,
            matching: find.textContaining(RegExp(r'\d.*đ$')),
          );

          expect(find.text('BTC-USDT-SWAP'), findsOneWidget);
          expect(price, findsOneWidget);
          expect(size, findsOneWidget);
          expect(vndAmount, findsOneWidget);
          if (scenario.width == 320 && scenario.textScale == 1.0) {
            compactDefaultCardHeight = cardRect.height;
          }
          if (scenario.width == 320 && scenario.textScale == 2.0) {
            compactLargeTextCardHeight = cardRect.height;
          }
          expect(cardRect.contains(tester.getRect(price).center), isTrue);
          expect(cardRect.contains(tester.getRect(size).center), isTrue);
          expect(cardRect.contains(tester.getRect(vndAmount).center), isTrue);
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(const SizedBox.shrink());
        }

        expect(
          compactLargeTextCardHeight,
          greaterThan(compactDefaultCardHeight!),
        );
      }
    },
  );
}
