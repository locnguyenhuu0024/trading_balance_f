import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/orders/data/okx_order_model.dart';
import 'package:trading_balance_f/features/orders/data/okx_position_model.dart';
import 'package:trading_balance_f/features/orders/data/trade_api_client.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/order_provider.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/position_action_flow_provider.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/trade_session_provider.dart';
import 'package:trading_balance_f/features/orders/presentation/widgets/order_cancellation_control.dart';
import 'package:trading_balance_f/features/orders/presentation/widgets/trade_account_controls.dart';

OkxOrder _order({
  String state = 'live',
  String ordType = 'limit',
  String ordId = 'order-99',
  String px = '10.5',
  String sz = '2',
}) => OkxOrder(
  instId: 'BTC-USDT-SWAP',
  instType: 'SWAP',
  ordId: ordId,
  ordType: ordType,
  side: 'buy',
  px: px,
  sz: sz,
  state: state,
);

Map<String, dynamic> _identity(OkxOrder order) => {
  'instType': order.instType,
  'instId': order.instId,
  'ordId': order.ordId,
  'ordType': order.ordType,
  'side': order.side,
  'px': order.px,
  'sz': order.sz,
};

PreparedTradeAction _prepared(
  OkxOrder order, {
  String action = 'cancel_order',
  int? targetCount = 1,
  Map<String, dynamic>? identity,
  String price = '10.5',
  String originalSize = '2',
  String filledSize = '0',
  String remainingSize = '2',
}) {
  final target = <String, dynamic>{
    'identity': identity ?? _identity(order),
    'price': price,
    'originalSize': originalSize,
    'filledSize': filledSize,
    'remainingSize': remainingSize,
  };
  return PreparedTradeAction(
    operationId: 'operation-12345678',
    confirmationToken: 'single-use-token',
    action: action,
    expiresAt: '2099-01-01T00:00:00Z',
    summary: {
      'targetCount': targetCount,
      'targets': [target],
    },
  );
}

TradeOperationResult _result(
  OkxOrder order, {
  String operationId = 'operation-12345678',
  String action = 'cancel_order',
  String status = 'SUCCEEDED',
}) => TradeOperationResult(
  operationId: operationId,
  action: action,
  status: status,
  targets: [
    {
      'identity': _identity(order),
      'status': status,
      'price': order.px,
      'originalSize': order.sz,
      'filledSize': '1',
      'remainingSize': '1',
      'outcome': {'filledSize': '1', 'remainingSize': '1'},
    },
  ],
  updatedAt: '2099-01-01T00:00:00Z',
);

TradeSession _session(String token) => TradeSession(
  bearerToken: token,
  accountIdentifier: 'account-same',
  expiresAt: DateTime.now().add(const Duration(hours: 1)),
);

OkxPosition _position() => OkxPosition(
  instId: 'BTC-USDT-SWAP',
  instType: 'SWAP',
  posSide: 'net',
  pos: '2',
  size: '2',
  signedSize: '2',
  direction: 'long',
  mgnMode: 'isolated',
  identity: const {
    'instrumentType': 'SWAP',
    'instrumentId': 'BTC-USDT-SWAP',
    'positionId': 'position-1',
    'positionSide': 'net',
    'marginMode': 'isolated',
  },
);

class _CancellationApi implements TradeApi {
  _CancellationApi({this.configured = true});

  final bool configured;
  @override
  bool get isConfigured => configured;
  @override
  bool get supportsSessionRestoration => false;

  int prepareCalls = 0;
  int executeCalls = 0;
  int resultCalls = 0;
  String? bearerTokenSeen;
  String? actionSeen;
  Map<String, dynamic>? targetIdentitySeen;
  PreparedTradeAction? prepared;
  TradeApiException? prepareError;
  TradeApiException? executeError;
  TradeApiException? resultError;
  Completer<PreparedTradeAction>? prepareGate;
  Completer<void>? prepareStarted;
  Completer<TradeOperationResult>? executeGate;
  Completer<void>? executeStarted;
  Completer<TradeOperationResult>? resultGate;
  OkxOrder? orderForResult;

  @override
  Future<TradeSession> login({
    required String password,
    required String totp,
  }) => throw UnimplementedError();
  @override
  Future<TradeSession> restoreSession() => throw UnimplementedError();
  @override
  Future<void> logout(String bearerToken) async {}
  @override
  Future<TradePositionsSnapshot> getPositions(String bearerToken) async =>
      const TradePositionsSnapshot(
        accountIdentifier: 'account-same',
        positions: [],
      );

  @override
  Future<PreparedTradeAction> prepare(
    String bearerToken, {
    required String action,
    Map<String, dynamic>? targetIdentity,
    String? amount,
    String? size,
    String? percentage,
  }) async {
    prepareCalls++;
    bearerTokenSeen = bearerToken;
    actionSeen = action;
    targetIdentitySeen = targetIdentity;
    final started = prepareStarted;
    if (started != null && !started.isCompleted) started.complete();
    final preparationFailure = prepareError;
    if (preparationFailure != null) throw preparationFailure;
    final gate = prepareGate;
    if (gate != null) return gate.future;
    return prepared ?? _prepared(_order());
  }

  @override
  Future<TradeOperationResult> execute(
    String bearerToken, {
    required String operationId,
    required String confirmationToken,
  }) async {
    executeCalls++;
    bearerTokenSeen = bearerToken;
    final started = executeStarted;
    if (started != null && !started.isCompleted) started.complete();
    final executionFailure = executeError;
    if (executionFailure != null) throw executionFailure;
    final gate = executeGate;
    if (gate != null) return gate.future;
    return _result(orderForResult ?? _order(), operationId: operationId);
  }

  @override
  Future<TradeOperationResult> getResult(
    String bearerToken,
    String operationId,
  ) async {
    resultCalls++;
    bearerTokenSeen = bearerToken;
    final lookupFailure = resultError;
    if (lookupFailure != null) throw lookupFailure;
    final gate = resultGate;
    if (gate != null) return gate.future;
    return _result(
      orderForResult ?? _order(),
      operationId: operationId,
      status: 'UNKNOWN',
    );
  }
}

class _TestSessionController extends TradeSessionController {
  _TestSessionController(super.api, TradeSessionState initialState) {
    state = initialState;
  }

  void replaceSession(TradeSession? session) {
    state = TradeSessionState(
      session: session,
      operationAccountIdentifier: session?.accountIdentifier ?? 'account-same',
    );
  }
}

class _TestHarness extends ConsumerWidget {
  const _TestHarness({required this.order});

  final OkxOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(ordersFutureProvider);
    return Scaffold(
      body: ListView(
        children: [
          OrderCancellationControl(order: order),
          const TradeAccountControls(showCloseAll: false),
        ],
      ),
    );
  }
}

Finder _cancelButton(String orderId) =>
    find.byKey(Key('order-cancel-$orderId'));

class _Fixture {
  _Fixture({
    required this.order,
    required this.api,
    bool authenticated = true,
    TradeSession? session,
  }) : sessionController = _TestSessionController(
         api,
         TradeSessionState(
           session: authenticated ? session ?? _session('token-A') : null,
           operationAccountIdentifier: 'account-same',
         ),
       ) {
    container = ProviderContainer(
      overrides: [
        tradeApiProvider.overrideWithValue(api),
        tradeSessionProvider.overrideWith((ref) => sessionController),
        ordersFutureProvider.overrideWith((ref) {
          orderReads++;
          return Future.value(<OkxOrder>[]);
        }),
      ],
    );
  }

  final OkxOrder order;
  final _CancellationApi api;
  final _TestSessionController sessionController;
  late final ProviderContainer container;
  int orderReads = 0;
  bool _disposed = false;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: _TestHarness(order: order)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    if (_disposed) return;
    _disposed = true;
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  }
}

void main() {
  group('T69 RED-003 cancellation safety boundaries', () {
    testWidgets('hold shows the tooltip and never prepares an action', (
      tester,
    ) async {
      final fixture = _Fixture(order: _order(), api: _CancellationApi());
      addTearDown(() => fixture.dispose(tester));
      await fixture.pump(tester);

      await tester.longPress(find.byTooltip('Hủy lệnh limit'));
      await tester.pumpAndSettle();

      expect(find.text('Hủy lệnh limit'), findsOneWidget);
      expect(fixture.api.prepareCalls, 0);
      expect(fixture.api.executeCalls, 0);
    });

    testWidgets('unauthenticated or missing identity cannot prepare', (
      tester,
    ) async {
      final unauthenticated = _Fixture(
        order: _order(),
        api: _CancellationApi(),
        authenticated: false,
      );
      addTearDown(() => unauthenticated.dispose(tester));
      await unauthenticated.pump(tester);
      expect(
        tester.widget<IconButton>(_cancelButton('order-99')).onPressed,
        isNull,
      );
      expect(unauthenticated.api.prepareCalls, 0);
      await unauthenticated.dispose(tester);

      final missingIdentity = _Fixture(
        order: _order(ordId: ''),
        api: _CancellationApi(),
      );
      await missingIdentity.pump(tester);
      expect(tester.widget<IconButton>(_cancelButton('')).onPressed, isNull);
      expect(missingIdentity.api.prepareCalls, 0);
      await missingIdentity.dispose(tester);
    });

    testWidgets('non-limit and history orders do not expose cancellation', (
      tester,
    ) async {
      final api = _CancellationApi();
      final market = _Fixture(
        order: _order(ordType: 'market'),
        api: api,
      );
      addTearDown(() => market.dispose(tester));
      await market.pump(tester);
      expect(find.byTooltip('Hủy lệnh limit'), findsNothing);
      await market.dispose(tester);

      final history = _Fixture(
        order: _order(state: 'filled'),
        api: api,
      );
      await history.pump(tester);
      expect(find.byTooltip('Hủy lệnh limit'), findsNothing);
      expect(api.prepareCalls, 0);
      await history.dispose(tester);
    });

    testWidgets('prepared action or identity mismatch never opens confirm', (
      tester,
    ) async {
      final order = _order();
      final api = _CancellationApi()
        ..prepared = _prepared(order, action: 'close_position');
      final fixture = _Fixture(order: order, api: api);
      addTearDown(() => fixture.dispose(tester));
      await fixture.pump(tester);
      await tester.tap(find.byTooltip('Hủy lệnh limit'));
      await tester.pumpAndSettle();
      expect(find.text('Xác nhận hủy lệnh limit'), findsNothing);
      expect(api.executeCalls, 0);

      final wrongIdentity = Map<String, dynamic>.from(_identity(order))
        ..['ordId'] = 'other-order';
      api.prepared = _prepared(order, identity: wrongIdentity);
      await tester.tap(find.byTooltip('Hủy lệnh limit'));
      await tester.pumpAndSettle();
      expect(find.text('Xác nhận hủy lệnh limit'), findsNothing);
      expect(api.executeCalls, 0);

      api.prepared = _prepared(order, targetCount: 2);
      await tester.tap(find.byTooltip('Hủy lệnh limit'));
      await tester.pumpAndSettle();
      expect(find.text('Xác nhận hủy lệnh limit'), findsNothing);
      expect(api.executeCalls, 0);
      expect(api.prepareCalls, 3);
    });

    testWidgets('contradictory fractional summary is rejected exactly', (
      tester,
    ) async {
      final order = _order(sz: '0.3');
      final api = _CancellationApi()
        ..prepared = _prepared(
          order,
          originalSize: '0.3',
          filledSize: '0.1',
          remainingSize: '0.3',
        );
      final fixture = _Fixture(order: order, api: api);
      addTearDown(() => fixture.dispose(tester));
      await fixture.pump(tester);
      await tester.tap(find.byTooltip('Hủy lệnh limit'));
      await tester.pumpAndSettle();
      expect(find.text('Xác nhận hủy lệnh limit'), findsNothing);
      expect(api.executeCalls, 0);
    });

    testWidgets('dismiss and repeated taps never execute twice', (
      tester,
    ) async {
      final order = _order();
      final api = _CancellationApi()..prepared = _prepared(order);
      final fixture = _Fixture(order: order, api: api);
      addTearDown(() => fixture.dispose(tester));
      await fixture.pump(tester);
      await tester.tap(find.byTooltip('Hủy lệnh limit'));
      await tester.pumpAndSettle();
      expect(find.text('Khối lượng còn lại để hủy: 2'), findsOneWidget);
      expect(find.textContaining('Mã lệnh: order-99'), findsOneWidget);
      expect(find.text('Hủy phần còn lại 2'), findsOneWidget);
      expect(
        tester.widget<IconButton>(_cancelButton('order-99')).onPressed,
        isNull,
      );
      expect(api.prepareCalls, 1);
      await tester.tap(find.widgetWithText(TextButton, 'Hủy'));
      await tester.pumpAndSettle();
      expect(api.executeCalls, 0);
      expect(
        fixture.container.read(tradeSessionProvider).pendingOperations,
        isEmpty,
      );
    });

    testWidgets(
      'same-account session switch hides confirmation and blocks write',
      (tester) async {
        final order = _order();
        final api = _CancellationApi()..prepared = _prepared(order);
        final fixture = _Fixture(order: order, api: api);
        addTearDown(() => fixture.dispose(tester));
        await fixture.pump(tester);
        await tester.tap(find.byTooltip('Hủy lệnh limit'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Mã lệnh: order-99'), findsOneWidget);

        fixture.sessionController.replaceSession(_session('token-B'));
        await tester.pumpAndSettle();
        expect(
          find.text('Phiên giao dịch đã thay đổi. Hãy đóng xác nhận này.'),
          findsOneWidget,
        );
        expect(find.textContaining('Mã lệnh: order-99'), findsNothing);
        expect(find.text('Hủy phần còn lại 2'), findsNothing);
        await tester.tap(find.widgetWithText(TextButton, 'Hủy'));
        await tester.pumpAndSettle();
        expect(api.executeCalls, 0);
        expect(
          fixture.container.read(tradeSessionProvider).session?.bearerToken,
          'token-B',
        );
      },
    );

    testWidgets(
      'old-session unauthorized prepare cannot expire replacement session',
      (tester) async {
        final order = _order();
        final api = _CancellationApi()
          ..prepareGate = Completer<PreparedTradeAction>()
          ..prepareStarted = Completer<void>();
        final fixture = _Fixture(order: order, api: api);
        addTearDown(() => fixture.dispose(tester));
        await fixture.pump(tester);
        await tester.tap(find.byTooltip('Hủy lệnh limit'));
        await api.prepareStarted!.future;
        fixture.sessionController.replaceSession(_session('token-B'));
        api.prepareGate!.completeError(
          const TradeApiException(
            code: 'unauthorized',
            message: 'expired old token',
            statusCode: 401,
          ),
        );
        await tester.pumpAndSettle();
        final sessionState = fixture.container.read(tradeSessionProvider);
        expect(sessionState.isAuthenticated, isTrue);
        expect(sessionState.session?.bearerToken, 'token-B');
        expect(sessionState.errorMessage, isNull);
        expect(api.executeCalls, 0);
      },
    );

    testWidgets('session switch hides an already-open result dialog', (
      tester,
    ) async {
      final order = _order();
      final api = _CancellationApi()..prepared = _prepared(order);
      final fixture = _Fixture(order: order, api: api);
      addTearDown(() => fixture.dispose(tester));
      await fixture.pump(tester);
      await tester.tap(find.byTooltip('Hủy lệnh limit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hủy phần còn lại 2'));
      await tester.pumpAndSettle();
      expect(find.text('Mã thao tác: operation-12345678'), findsOneWidget);
      expect(find.textContaining('Mã lệnh: order-99'), findsOneWidget);

      fixture.sessionController.replaceSession(_session('token-B'));
      await tester.pumpAndSettle();
      expect(find.text('Nội dung thao tác đã được ẩn.'), findsOneWidget);
      expect(find.text('operation-12345678'), findsNothing);
      expect(find.textContaining('Mã lệnh: order-99'), findsNothing);
    });

    testWidgets('unknown execute is looked up once and stays pending', (
      tester,
    ) async {
      final order = _order();
      final api = _CancellationApi()
        ..prepared = _prepared(order)
        ..executeError = const TradeApiException(
          code: 'network_error',
          message: 'temporary network failure',
          statusCode: 503,
        )
        ..resultError = const TradeApiException(
          code: 'network_error',
          message: 'result unavailable',
          statusCode: 503,
        );
      final fixture = _Fixture(order: order, api: api);
      addTearDown(() => fixture.dispose(tester));
      await fixture.pump(tester);
      await tester.tap(find.byTooltip('Hủy lệnh limit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hủy phần còn lại 2'));
      await tester.pumpAndSettle();

      final pending = fixture.container
          .read(tradeSessionProvider)
          .pendingOperations;
      expect(api.executeCalls, 1);
      expect(api.resultCalls, 1);
      expect(pending, hasLength(1));
      expect(pending.single.operationId, 'operation-12345678');
      expect(pending.single.action, 'cancel_order');
      expect(fixture.orderReads, greaterThanOrEqualTo(2));
      expect(find.textContaining('operation-12345678'), findsOneWidget);
      expect(
        tester.widget<IconButton>(_cancelButton('order-99')).onPressed,
        isNull,
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture.container,
          child: const MaterialApp(
            home: Scaffold(body: TradeAccountControls(showCloseAll: false)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('operation-12345678'), findsOneWidget);
      expect(find.text('Tra cứu trạng thái'), findsOneWidget);
    });
  });

  group('T69 GREEN-003 cancellation success', () {
    testWidgets('matching fractional cancellation confirms and executes once', (
      tester,
    ) async {
      final order = _order(sz: '0.3');
      final api = _CancellationApi()
        ..prepared = _prepared(
          order,
          originalSize: '0.3',
          filledSize: '0.1',
          remainingSize: '0.2',
        );
      final fixture = _Fixture(order: order, api: api);
      addTearDown(() => fixture.dispose(tester));
      await fixture.pump(tester);

      await tester.tap(find.byTooltip('Hủy lệnh limit'));
      await tester.pumpAndSettle();
      expect(find.text('Khối lượng gốc: 0.3'), findsOneWidget);
      expect(find.text('Đã khớp: 0.1'), findsOneWidget);
      expect(find.text('Khối lượng còn lại để hủy: 0.2'), findsOneWidget);
      expect(find.text('Hủy phần còn lại 0.2'), findsOneWidget);
      expect(api.executeCalls, 0);

      await tester.tap(find.text('Hủy phần còn lại 0.2'));
      await tester.pumpAndSettle();
      expect(api.actionSeen, 'cancel_order');
      expect(api.targetIdentitySeen, {
        'instType': 'SWAP',
        'instId': 'BTC-USDT-SWAP',
        'ordId': 'order-99',
        'ordType': 'limit',
        'side': 'buy',
        'px': '10.5',
        'sz': '0.3',
      });
      expect(api.executeCalls, 1);
      expect(api.resultCalls, 0);
      expect(fixture.orderReads, greaterThanOrEqualTo(2));
      expect(
        fixture.container.read(tradeSessionProvider).pendingOperations,
        isEmpty,
      );
    });

    testWidgets('shared account action lock disables cancellation', (
      tester,
    ) async {
      final api = _CancellationApi()
        ..prepareGate = Completer<PreparedTradeAction>()
        ..prepareStarted = Completer<void>();
      final fixture = _Fixture(order: _order(), api: api);
      addTearDown(() => fixture.dispose(tester));
      await fixture.pump(tester);
      final position = _position();
      final positionAction = fixture.container
          .read(positionActionFlowsProvider.notifier)
          .runAction(
            position: position,
            action: 'close_position',
            inputKind: null,
            navigator: tester.state<NavigatorState>(find.byType(Navigator)),
            ownerRoute: null,
            confirm: (_) async => false,
            showResult: (result, {String? lookupError}) async {},
          );
      await api.prepareStarted!.future;
      await tester.pumpAndSettle();
      expect(
        tester.widget<IconButton>(_cancelButton('order-99')).onPressed,
        isNull,
      );
      api.prepareGate!.complete(
        PreparedTradeAction(
          operationId: 'position-operation',
          confirmationToken: 'position-token',
          action: 'close_position',
          expiresAt: '2099-01-01T00:00:00Z',
          summary: {
            'targetCount': 1,
            'targets': [
              {
                'identity': position.identity,
                'direction': 'long',
                'currentSize': '2',
              },
            ],
          },
        ),
      );
      await tester.pumpAndSettle();
      await positionAction;
      expect(fixture.api.prepareCalls, 1);
    });
  });
}
