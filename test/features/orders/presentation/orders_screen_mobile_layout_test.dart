import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/currency/currency_display_mode.dart';
import 'package:trading_balance_f/core/timezone/app_time_zone.dart';
import 'package:trading_balance_f/core/widgets/crypto_icon.dart';
import 'package:trading_balance_f/features/orders/data/okx_order_model.dart';
import 'package:trading_balance_f/features/orders/presentation/orders_screen.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/order_provider.dart';
import 'package:trading_balance_f/features/portfolio/presentation/portfolio_screen.dart';
import 'package:trading_balance_f/features/portfolio/presentation/widgets/portfolio_currency_amount.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';

const _timeZoneId = 'Asia/Ho_Chi_Minh';

OkxOrder _order({
  String instId = 'SUI-USDT-SWAP',
  String instType = 'SWAP',
  String lever = '10',
  String side = 'buy',
  String state = 'live',
  String px = '0.0112233',
  String sz = '123.456789',
  String notionalUsd = '12345.67',
  String fillNotionalUsd = '',
}) => OkxOrder(
  instId: instId,
  instType: instType,
  ordId: 'mobile-order-77',
  ordType: 'limit',
  side: side,
  px: px,
  sz: sz,
  notionalUsd: notionalUsd,
  fillNotionalUsd: fillNotionalUsd,
  state: state,
  lever: lever,
  cTime: '1767225600000',
);

ProviderContainer _container({
  required OkxOrder order,
  required String currency,
  required bool isDark,
}) {
  return ProviderContainer(
    overrides: [
      orderFilterProvider.overrideWith((ref) => 'SWAP'),
      orderTabProvider.overrideWith((ref) => OrderTab.pending),
      ordersFutureProvider.overrideWith((ref) async => [order]),
      currencyProvider.overrideWith((ref) => currency),
      vndExchangeRateProvider.overrideWith((ref) async => 25400),
      appTimeZoneProvider.overrideWith((ref) => _timeZoneId),
      themeModeProvider.overrideWith(
        (ref) => isDark ? ThemeMode.dark : ThemeMode.light,
      ),
    ],
  );
}

Widget _app(ProviderContainer container, double textScale) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: const OrdersScreen(),
        ),
      ),
    ),
  );
}

Future<ProviderContainer> _pumpOrder(
  WidgetTester tester, {
  required OkxOrder order,
  required double width,
  required double textScale,
  required bool isDark,
  String currency = CurrencyDisplayMode.usdtVnd,
}) async {
  tester.view.physicalSize = Size(width, 900);
  final container = _container(
    order: order,
    currency: currency,
    isDark: isDark,
  );
  await tester.pumpWidget(_app(container, textScale));
  await tester.pump();
  await tester.pump();
  return container;
}

Future<void> _clear(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
}

void _expectRowText(WidgetTester tester, String rowName, String text) {
  final row = find.byKey(Key('pending-order-row-$rowName'));
  expect(row, findsOneWidget, reason: '$rowName row should exist');
  expect(
    find.descendant(of: row, matching: find.text(text)),
    findsOneWidget,
    reason: '$rowName row should contain "$text"',
  );
}

void _expectAlignedRow(
  WidgetTester tester, {
  required String rowName,
  required String label,
  required String value,
}) {
  final row = find.byKey(Key('pending-order-row-$rowName'));
  final labelFinder = find.descendant(of: row, matching: find.text(label));
  final valueFinder = find.descendant(of: row, matching: find.text(value));
  expect(labelFinder, findsOneWidget);
  expect(valueFinder, findsOneWidget);
  expect(
    (tester.getRect(labelFinder).center.dy -
            tester.getRect(valueFinder).center.dy)
        .abs(),
    lessThan(1),
    reason: '$label and $value should share one line',
  );
}

void _expectTopAlignedNotional(
  WidgetTester tester, {
  required String label,
  required String primaryValue,
}) {
  final row = find.byKey(const Key('pending-order-row-notional'));
  final labelFinder = find.descendant(of: row, matching: find.text(label));
  final valueCandidates = find.descendant(
    of: row,
    matching: find.text(primaryValue),
  );
  expect(labelFinder, findsOneWidget);
  expect(valueCandidates, findsWidgets);
  final valueFinder = valueCandidates.first;
  final labelRect = tester.getRect(labelFinder);
  final valueRect = tester.getRect(valueFinder);
  expect(
    (labelRect.top - valueRect.top).abs(),
    lessThan(1),
    reason: '$label should align with the primary notional line',
  );
  expect(labelRect.right, lessThanOrEqualTo(valueRect.left));
}

void main() {
  testWidgets(
    'pending order header and detail rows stay readable across phone sizes, scales, and themes',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;

      for (final width in [320.0, 375.0, 390.0, 430.0]) {
        for (final textScale in [1.0, 1.3, 2.0]) {
          for (final isDark in [false, true]) {
            final container = await _pumpOrder(
              tester,
              order: _order(),
              width: width,
              textScale: textScale,
              isDark: isDark,
            );

            final header = find.byKey(const Key('pending-order-header'));
            final instrumentType = find.descendant(
              of: header,
              matching: find.text('SWAP'),
            );
            expect(header, findsOneWidget);
            expect(find.text('MUA'), findsOneWidget);
            expect(find.text('10x'), findsOneWidget);
            expect(find.byType(CryptoIcon), findsOneWidget);
            expect(find.text('SUIUSDT'), findsOneWidget);
            expect(instrumentType, findsOneWidget);
            final headerRect = tester.getRect(header);
            final headerLeft = find.byKey(
              const Key('pending-order-header-left'),
            );
            final headerRight = find.byKey(
              const Key('pending-order-header-right'),
            );
            expect(headerLeft, findsOneWidget);
            expect(headerRight, findsOneWidget);
            if (width == 430) {
              expect(
                tester.getRect(headerLeft).left,
                closeTo(headerRect.left, 1),
              );
              expect(
                tester.getRect(headerRight).right,
                closeTo(headerRect.right, 1),
              );
              expect(
                tester.getRect(find.text('MUA')).left,
                closeTo(headerRect.left, 1),
              );
              expect(
                tester
                    .getRect(
                      find.byKey(const Key('pending-order-instrument-type')),
                    )
                    .right,
                closeTo(headerRect.right, 1),
              );
            }
            for (final finder in [
              find.text('MUA'),
              find.text('10x'),
              find.byType(CryptoIcon),
              find.text('SUIUSDT'),
              instrumentType,
            ]) {
              expect(
                headerRect.contains(tester.getRect(finder).center),
                isTrue,
                reason:
                    'header content should fit at $width/$textScale/$isDark',
              );
            }
            expect(
              tester.getRect(find.text('MUA')).center.dy,
              closeTo(tester.getRect(find.text('SUIUSDT')).center.dy, 1),
            );
            expect(
              tester.getRect(find.byType(CryptoIcon)).center.dx,
              lessThan(tester.getRect(find.text('SUIUSDT')).center.dx),
            );
            expect(
              tester.getRect(find.text('SUIUSDT')).center.dx,
              lessThan(tester.getRect(instrumentType).center.dx),
            );

            _expectAlignedRow(
              tester,
              rowName: 'timestamp',
              label: 'Thời gian:',
              value: formatOrderTimestamp('1767225600000', _timeZoneId),
            );
            _expectAlignedRow(
              tester,
              rowName: 'state',
              label: 'Trạng thái:',
              value: 'LIVE',
            );
            _expectAlignedRow(
              tester,
              rowName: 'price',
              label: 'Giá:',
              value: '0.0112233',
            );
            _expectAlignedRow(
              tester,
              rowName: 'quantity',
              label: 'KL:',
              value: '123.4568',
            );
            _expectRowText(tester, 'notional', 'Giá trị lệnh:');
            _expectRowText(tester, 'notional', '12,345.67 USDT');
            _expectTopAlignedNotional(
              tester,
              label: 'Giá trị lệnh:',
              primaryValue: '12,345.67 USDT',
            );
            expect(
              find.byKey(const Key('order-cancel-mobile-order-77')),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);

            await _clear(tester);
            container.dispose();
          }
        }
      }

      final container = await _pumpOrder(
        tester,
        order: _order(),
        width: 1200,
        textScale: 1,
        isDark: false,
      );
      expect(find.text('SUIUSDT'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('pending-order-header')),
          matching: find.text('SWAP'),
        ),
        findsOneWidget,
      );
      final desktopHeader = find.byKey(const Key('pending-order-header'));
      expect(
        tester.getRect(find.byKey(const Key('pending-order-header-left'))).left,
        closeTo(tester.getRect(desktopHeader).left, 1),
      );
      expect(
        tester
            .getRect(find.byKey(const Key('pending-order-header-right')))
            .right,
        closeTo(tester.getRect(desktopHeader).right, 1),
      );
      expect(
        tester.getRect(find.text('MUA')).left,
        closeTo(tester.getRect(desktopHeader).left, 1),
      );
      expect(
        tester
            .getRect(find.byKey(const Key('pending-order-instrument-type')))
            .right,
        closeTo(tester.getRect(desktopHeader).right, 1),
      );
      expect(tester.takeException(), isNull);
      await _clear(tester);
      container.dispose();
    },
  );

  testWidgets(
    'pending order keeps complete large dual-currency values in one-line detail rows',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;

      const amount = 987654321.12;
      final largeValueContainer = await _pumpOrder(
        tester,
        order: _order(
          side: 'sell',
          px: '987654321.123456',
          sz: '987654321.123456',
          notionalUsd: '$amount',
        ),
        width: 320,
        textScale: 2,
        isDark: true,
      );

      _expectAlignedRow(
        tester,
        rowName: 'price',
        label: 'Giá:',
        value: '987,654,321.12',
      );
      _expectAlignedRow(
        tester,
        rowName: 'quantity',
        label: 'KL:',
        value: '987,654,321.12',
      );
      final amountLines = formatPortfolioCurrencyLines(
        usdtAmount: amount,
        currencyMode: CurrencyDisplayMode.usdtVnd,
        vndRate: 25400,
      );
      _expectRowText(tester, 'notional', 'Giá trị lệnh:');
      _expectRowText(tester, 'notional', amountLines.primary);
      _expectRowText(tester, 'notional', amountLines.secondary!);
      _expectTopAlignedNotional(
        tester,
        label: 'Giá trị lệnh:',
        primaryValue: amountLines.primary,
      );
      expect(find.text('BÁN'), findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);
      expect(find.textContaining('…'), findsNothing);
      expect(tester.takeException(), isNull);

      await _clear(tester);
      largeValueContainer.dispose();
    },
  );

  testWidgets(
    'pending order supports absent type, leverage, and notional plus hidden balances',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;

      final missingDataContainer = await _pumpOrder(
        tester,
        order: _order(instType: '', lever: '', notionalUsd: ''),
        width: 320,
        textScale: 2,
        isDark: false,
      );
      expect(find.text('SUIUSDT'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(Card), matching: find.text('SWAP')),
        findsNothing,
      );
      expect(find.text('10x'), findsNothing);
      _expectAlignedRow(
        tester,
        rowName: 'price',
        label: 'Giá:',
        value: '0.0112233',
      );
      _expectTopAlignedNotional(
        tester,
        label: 'Giá trị lệnh:',
        primaryValue: '--',
      );
      expect(tester.takeException(), isNull);
      await _clear(tester);
      missingDataContainer.dispose();

      final container = _container(
        order: _order(),
        currency: CurrencyDisplayMode.usdtVnd,
        isDark: true,
      );
      container.read(hideBalanceProvider.notifier).state = true;
      tester.view.physicalSize = const Size(375, 900);
      await tester.pumpWidget(_app(container, 1.3));
      await tester.pump();
      await tester.pump();

      final notionalRow = find.byKey(const Key('pending-order-row-notional'));
      _expectRowText(tester, 'notional', 'Giá trị lệnh:');
      expect(
        find.descendant(of: notionalRow, matching: find.text('******')),
        findsNWidgets(2),
      );
      _expectTopAlignedNotional(
        tester,
        label: 'Giá trị lệnh:',
        primaryValue: '******',
      );
      expect(tester.takeException(), isNull);

      await _clear(tester);
      container.dispose();
    },
  );
}
