import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/currency/currency_display_mode.dart';
import 'package:trading_balance_f/features/orders/data/okx_position_model.dart';
import 'package:trading_balance_f/features/orders/data/trade_api_client.dart';
import 'package:trading_balance_f/features/orders/presentation/orders_screen.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/order_provider.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/trade_session_provider.dart';
import 'package:trading_balance_f/features/orders/presentation/widgets/position_action_controls.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';

class _ActionApi implements TradeApi {
  @override
  bool get isConfigured => true;

  @override
  bool get supportsSessionRestoration => false;

  int prepareCalls = 0;
  int executeCalls = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSessionController extends TradeSessionController {
  _TestSessionController(super.api, TradeSession session) {
    state = TradeSessionState(session: session);
  }

  void replace(TradeSession session) {
    state = TradeSessionState(session: session);
  }
}

TradeSession _session(String token, String account) => TradeSession(
  bearerToken: token,
  accountIdentifier: account,
  expiresAt: DateTime.now().add(const Duration(hours: 1)),
);

const _visiblePosition = OkxPosition(
  instId: 'BTC-USDT-SWAP',
  instType: 'SWAP',
  posSide: 'long',
  pos: '1',
  size: '1',
);

const _backendTarget = OkxPosition(
  instId: 'BTC-USDT-SWAP',
  instType: 'SWAP',
  posSide: 'short',
  pos: '7',
  size: '7',
  identity: {
    'instrumentType': 'SWAP',
    'instrumentId': 'BTC-USDT-SWAP',
    'positionId': 'backend-position-7',
    'positionSide': 'short',
    'marginMode': 'isolated',
  },
  eligibleActions: {
    'closePosition': {'eligible': true},
  },
);

void main() {
  testWidgets(
    'loads only explicit backend targets and scrolls the bounded dialog',
    (tester) async {
      tester.view.physicalSize = const Size(320, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _ActionApi();
      final sessionController = _TestSessionController(
        api,
        _session('token-A', 'backend-account-42'),
      );
      var targetLoads = 0;
      final semantics = tester.ensureSemantics();

      final app = _app(
        api: api,
        sessionController: sessionController,
        targets: () async {
          targetLoads++;
          return const TradePositionsSnapshot(
            accountIdentifier: 'backend-account-42',
            positions: [_backendTarget],
          );
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      expect(targetLoads, 0);
      expect(find.text('BTCUSDT'), findsOneWidget);
      expect(find.byType(PositionActionControls), findsNothing);
      final entry = find.byKey(const Key('backend-position-actions-entry'));
      expect(entry, findsOneWidget);
      expect(
        find.bySemanticsLabel('Chọn vị thế tài khoản backend'),
        findsOneWidget,
      );

      await tester.tap(entry);
      await tester.pumpAndSettle();

      expect(targetLoads, 1);
      expect(
        find.text('Tài khoản backend: backend-account-42'),
        findsOneWidget,
      );
      final scrollable = find
          .descendant(
            of: find.byKey(const Key('backend-action-dialog-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.textContaining('không ghép các mục này'),
        100,
        scrollable: scrollable,
      );
      expect(find.textContaining('không ghép các mục này'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('SWAP · short · 7'),
        100,
        scrollable: scrollable,
      );
      expect(find.byType(PositionActionControls), findsOneWidget);
      expect(find.byTooltip('Đóng 100%'), findsOneWidget);
      expect(find.text('SWAP · short · 7'), findsOneWidget);
      expect(scrollable, findsOneWidget);
      expect(tester.takeException(), isNull);

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('mismatched backend snapshot shows no action targets', (
    tester,
  ) async {
    final api = _ActionApi();
    final sessionController = _TestSessionController(
      api,
      _session('token-A', 'backend-account-42'),
    );

    await tester.pumpWidget(
      _app(
        api: api,
        sessionController: sessionController,
        targets: () async => const TradePositionsSnapshot(
          accountIdentifier: 'different-backend-account',
          positions: [_backendTarget],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backend-position-actions-entry')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Tài khoản hoặc phiên backend đã thay đổi'),
      findsOneWidget,
    );
    expect(find.byType(PositionActionControls), findsNothing);
    expect(find.byTooltip('Đóng 100%'), findsNothing);
    expect(api.prepareCalls, 0);
    expect(api.executeCalls, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('empty backend account explains that there are no targets', (
    tester,
  ) async {
    final api = _ActionApi();
    final sessionController = _TestSessionController(
      api,
      _session('token-A', 'backend-account-42'),
    );

    await tester.pumpWidget(
      _app(
        api: api,
        sessionController: sessionController,
        targets: () async => const TradePositionsSnapshot(
          accountIdentifier: 'backend-account-42',
          positions: [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backend-position-actions-entry')));
    await tester.pumpAndSettle();

    expect(
      find.text('Tài khoản backend chưa có vị thế đủ điều kiện.'),
      findsOneWidget,
    );
    expect(find.byType(PositionActionControls), findsNothing);
    expect(find.byTooltip('Đóng 100%'), findsNothing);
    expect(api.prepareCalls, 0);
    expect(api.executeCalls, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('backend target read errors are visible and action-free', (
    tester,
  ) async {
    final api = _ActionApi();
    final sessionController = _TestSessionController(
      api,
      _session('token-A', 'backend-account-42'),
    );

    await tester.pumpWidget(
      _app(
        api: api,
        sessionController: sessionController,
        targets: () async => throw StateError('fixture unavailable'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backend-position-actions-entry')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Không thể tải mục tiêu backend'),
      findsOneWidget,
    );
    expect(find.byType(PositionActionControls), findsNothing);
    expect(find.byTooltip('Đóng 100%'), findsNothing);
    expect(api.prepareCalls, 0);
    expect(api.executeCalls, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('session replacement hides an in-flight old target response', (
    tester,
  ) async {
    final api = _ActionApi();
    final sessionController = _TestSessionController(
      api,
      _session('token-A', 'backend-account-42'),
    );
    final pending = Completer<TradePositionsSnapshot>();

    await tester.pumpWidget(
      _app(
        api: api,
        sessionController: sessionController,
        targets: () => pending.future,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backend-position-actions-entry')));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    sessionController.replace(_session('token-B', 'backend-account-43'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Phiên backend đã thay đổi'), findsOneWidget);

    pending.complete(
      const TradePositionsSnapshot(
        accountIdentifier: 'backend-account-42',
        positions: [_backendTarget],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PositionActionControls), findsNothing);
    expect(find.text('SWAP · short · 7'), findsNothing);
    expect(api.prepareCalls, 0);
    expect(api.executeCalls, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'dialog entry keeps its generation before the route first builds',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _ActionApi();
      final entrySession = _session('token-A', 'backend-account-42');
      final sessionController = _TestSessionController(api, entrySession);
      var targetLoads = 0;

      final app = _app(
        api: api,
        sessionController: sessionController,
        targets: () async {
          targetLoads++;
          return const TradePositionsSnapshot(
            accountIdentifier: 'backend-account-42',
            positions: [_backendTarget],
          );
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(OrdersScreen)),
      );
      final backendSession = container.read(backendDataSessionProvider);
      final entryGeneration = backendSession.generation;
      await tester.tap(find.byKey(const Key('backend-position-actions-entry')));
      backendSession.update(null);
      backendSession.update(entrySession);
      expect(backendSession.generation, greaterThan(entryGeneration));
      await tester.pumpAndSettle();
      expect(find.textContaining('Phiên backend đã thay đổi'), findsOneWidget);
      expect(find.byType(PositionActionControls), findsNothing);

      expect(targetLoads, 0);
      expect(find.textContaining('Phiên backend đã thay đổi'), findsOneWidget);
      expect(find.byType(PositionActionControls), findsNothing);
      expect(find.byTooltip('Đóng 100%'), findsNothing);
      expect(api.prepareCalls, 0);
      expect(api.executeCalls, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Widget _app({
  required _ActionApi api,
  required _TestSessionController sessionController,
  required Future<TradePositionsSnapshot> Function() targets,
}) => ProviderScope(
  overrides: [
    tradeApiProvider.overrideWithValue(api),
    tradeSessionProvider.overrideWith((ref) => sessionController),
    tradePositionsProvider.overrideWith((ref) => targets()),
    positionsFutureProvider.overrideWith(
      (ref) async => const [_visiblePosition],
    ),
    orderFilterProvider.overrideWith((ref) => 'ALL'),
    orderTabProvider.overrideWith((ref) => OrderTab.positions),
    themeModeProvider.overrideWith((ref) => ThemeMode.light),
    currencyProvider.overrideWith((ref) => CurrencyDisplayMode.usd),
    vndExchangeRateProvider.overrideWith((ref) async => 25400),
  ],
  child: MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(1.5)),
      child: child!,
    ),
    home: const OrdersScreen(),
  ),
);
