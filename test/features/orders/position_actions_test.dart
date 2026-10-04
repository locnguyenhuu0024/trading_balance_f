import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/theme/pnl_color.dart';
import 'package:trading_balance_f/features/orders/data/okx_position_model.dart';
import 'package:trading_balance_f/features/orders/data/trade_api_client.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/order_provider.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/trade_session_provider.dart';
import 'package:trading_balance_f/features/orders/presentation/widgets/position_action_controls.dart';
import 'package:trading_balance_f/features/orders/presentation/widgets/trade_account_controls.dart';

const _baseIdentity = <String, dynamic>{
  'instrumentType': 'SWAP',
  'instrumentId': 'BTC-USDT-SWAP',
  'positionId': 'position-1',
  'positionSide': 'net',
  'marginMode': 'isolated',
};

OkxPosition _position({
  String instrumentType = 'SWAP',
  String instrumentId = 'BTC-USDT-SWAP',
  Map<String, dynamic>? identity,
  Map<String, dynamic>? eligibility,
}) {
  final resolvedIdentity =
      identity ??
      {
        'instrumentType': instrumentType,
        'instrumentId': instrumentId,
        'positionId': 'position-1',
        'positionSide': 'net',
        'marginMode': 'isolated',
        if (instrumentType == 'MARGIN') 'marginCurrency': 'USDT',
      };
  final eligible =
      eligibility ??
      {
        'addMargin': const {'eligible': true, 'reason': null},
        'dca': const {'eligible': true, 'reason': null},
        'partialClose': const {'eligible': true, 'reason': null},
        'closePosition': const {'eligible': true, 'reason': null},
      };
  return OkxPosition(
    instId: instrumentId,
    instType: instrumentType,
    posSide: 'net',
    pos: '2',
    size: '2',
    signedSize: '2',
    direction: 'long',
    mgnMode: 'isolated',
    marginCurrency: instrumentType == 'MARGIN' ? 'USDT' : '',
    identity: resolvedIdentity,
    eligibleActions: eligible,
  );
}

class _FakeTradeApi implements TradeApi {
  _FakeTradeApi({
    this.configured = true,
    this.sessionRestorationSupported = false,
    this.restoredSession,
    this.restoreGate,
    this.logoutFailure,
  });

  final bool configured;
  @override
  bool get isConfigured => configured;
  final bool sessionRestorationSupported;
  @override
  bool get supportsSessionRestoration => sessionRestorationSupported;

  int loginCalls = 0;
  int restoreCalls = 0;
  int logoutCalls = 0;
  int prepareCalls = 0;
  int executeCalls = 0;
  int resultCalls = 0;
  int positionReads = 0;
  String? passwordSeen;
  String? totpSeen;
  String? lastAction;
  Map<String, dynamic>? lastIdentity;
  String? lastAmount;
  String? lastSize;
  String? lastPercentage;
  final TradeSession? restoredSession;
  final Completer<TradeSession>? restoreGate;
  TradeApiException? logoutFailure;
  Map<String, dynamic>? preparedIdentityOverride;
  String executeStatus = 'SUCCEEDED';
  TradeApiException? prepareError;
  TradeApiException? executeError;
  TradeApiException? resultError;
  Completer<void>? executeGate;
  List<Map<String, dynamic>> _lastTargets = const [];

  @override
  Future<TradeSession> login({
    required String password,
    required String totp,
  }) async {
    loginCalls++;
    passwordSeen = password;
    totpSeen = totp;
    return TradeSession(
      bearerToken: 'in-memory-test-token',
      accountIdentifier: '••••-42',
      expiresAt: DateTime.now().add(const Duration(minutes: 10)),
    );
  }

  @override
  Future<TradeSession> restoreSession() async {
    restoreCalls++;
    final gate = restoreGate;
    if (gate != null) return gate.future;
    final session = restoredSession;
    if (session == null) {
      throw const TradeApiException(
        code: 'authentication_required',
        message: 'No session cookie.',
        statusCode: 401,
      );
    }
    return session;
  }

  @override
  Future<void> logout(String bearerToken) async {
    logoutCalls++;
    final failure = logoutFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<TradePositionsSnapshot> getPositions(String bearerToken) async {
    positionReads++;
    return TradePositionsSnapshot(
      accountIdentifier: '••••-42',
      positions: [_position()],
    );
  }

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
    final prepareFailure = prepareError;
    if (prepareFailure != null) throw prepareFailure;
    lastAction = action;
    lastIdentity = targetIdentity;
    lastAmount = amount;
    lastSize = size;
    lastPercentage = percentage;

    List<Map<String, dynamic>> targets;
    if (action == 'close_all') {
      targets = [
        _target(_baseIdentity, 'BTC-USDT-SWAP', action),
        _target(
          const {
            'instrumentType': 'MARGIN',
            'instrumentId': 'ETH-USDT',
            'positionId': 'position-2',
            'positionSide': 'net',
            'marginMode': 'isolated',
            'marginCurrency': 'USDT',
          },
          'ETH-USDT',
          action,
        ),
      ];
    } else {
      final identity =
          preparedIdentityOverride ?? targetIdentity ?? _baseIdentity;
      targets = [_target(identity, '${identity['instrumentId']}', action)];
    }
    _lastTargets = targets;
    return PreparedTradeAction(
      operationId: 'operation-12345678',
      confirmationToken: 'single-use-confirmation',
      action: action,
      expiresAt: '2099-01-01T00:00:00Z',
      summary: {'targetCount': targets.length, 'targets': targets},
    );
  }

  Map<String, dynamic> _target(
    Map<String, dynamic> identity,
    String instrumentId,
    String action,
  ) {
    final summary = <String, dynamic>{
      'identity': identity,
      'direction': 'long',
      'currentSize': '2',
      'action': action,
    };
    if (action == 'add_margin') {
      summary.addAll({'amount': '5.00', 'currency': 'USDT'});
    } else if (action == 'dca') {
      summary.addAll({
        'requestedSize': '1',
        'normalizedSize': '0.5',
        'sizeUnit': 'contracts',
        'lotSize': '0.5',
        'minimumSize': '0.5',
      });
    } else if (action == 'partial_close') {
      summary.addAll({
        'percentage': '50',
        'normalizedSize': '1',
        'sizeUnit': 'contracts',
        'lotSize': '0.5',
        'minimumSize': '0.5',
      });
    }
    return summary;
  }

  @override
  Future<TradeOperationResult> execute(
    String bearerToken, {
    required String operationId,
    required String confirmationToken,
  }) async {
    executeCalls++;
    final executeFailure = executeError;
    if (executeFailure != null) throw executeFailure;
    final gate = executeGate;
    if (gate != null) await gate.future;
    return _result(operationId, executeStatus);
  }

  @override
  Future<TradeOperationResult> getResult(
    String bearerToken,
    String operationId,
  ) async {
    resultCalls++;
    final resultFailure = resultError;
    if (resultFailure != null) throw resultFailure;
    return _result(operationId, executeStatus);
  }

  TradeOperationResult _result(String operationId, String status) {
    return TradeOperationResult(
      operationId: operationId,
      action: lastAction ?? 'close_position',
      status: status,
      targets: _lastTargets
          .map(
            (target) => {
              'identity': target['identity'],
              'status': status,
              'outcome': status == 'SUCCEEDED'
                  ? null
                  : {'reason': 'test_result'},
            },
          )
          .toList(growable: false),
      updatedAt: '2099-01-01T00:00:00Z',
    );
  }
}

class _FakeSessionController extends TradeSessionController {
  _FakeSessionController(super.api, {bool authenticated = true}) {
    if (authenticated) {
      state = TradeSessionState(
        session: TradeSession(
          bearerToken: 'in-memory-test-token',
          accountIdentifier: '••••-42',
          expiresAt: DateTime.now().add(const Duration(minutes: 10)),
        ),
        operationAccountIdentifier: '••••-42',
      );
    }
  }
}

Widget _tradeApp({
  required _FakeTradeApi api,
  List<OkxPosition> positions = const [],
  String filter = 'SWAP',
  bool authenticated = true,
  Brightness brightness = Brightness.light,
  bool showActions = true,
  bool showAccountControls = false,
  bool showSessionControls = false,
}) {
  return ProviderScope(
    overrides: [
      tradeApiProvider.overrideWithValue(api),
      tradeSessionProvider.overrideWith(
        (ref) => _FakeSessionController(api, authenticated: authenticated),
      ),
      tradePositionsProvider.overrideWith((ref) async {
        api.positionReads++;
        return TradePositionsSnapshot(
          accountIdentifier: '••••-42',
          positions: positions,
        );
      }),
      orderFilterProvider.overrideWith((ref) => filter),
    ],
    child: MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              Consumer(
                builder: (context, ref, child) {
                  ref.watch(tradePositionsProvider);
                  return const SizedBox.shrink();
                },
              ),
              if (showAccountControls) const TradeAccountControls(),
              if (showSessionControls) const TradeSessionControls(),
              if (showActions)
                for (final position in positions)
                  PositionActionControls(position: position),
            ],
          ),
        ),
      ),
    ),
  );
}

Finder _actionButton(String label) => find
    .ancestor(of: find.byTooltip(label), matching: find.byType(IconButton))
    .first;

Future<void> _pumpActiveDialog(WidgetTester tester) async {
  // Position and account actions deliberately keep an indeterminate progress
  // indicator active while their server-prepared confirmation is open.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  group('RED-002 position action safety', () {
    testWidgets('RED-001 long press on an action icon never prepares it', (
      tester,
    ) async {
      final api = _FakeTradeApi();
      await tester.pumpWidget(_tradeApp(api: api, positions: [_position()]));
      await tester.pumpAndSettle();

      await tester.longPress(_actionButton('Đóng 100%'));
      await tester.pumpAndSettle();

      expect(find.text('Đóng 100%'), findsOneWidget);
      expect(api.prepareCalls, 0);
      expect(api.executeCalls, 0);
      expect(find.text('Xác nhận đóng vị thế 100%'), findsNothing);
    });

    testWidgets('RED-INPUT-CANCEL before prepare sends no request', (
      tester,
    ) async {
      final api = _FakeTradeApi();
      await tester.pumpWidget(_tradeApp(api: api, positions: [_position()]));
      await tester.pumpAndSettle();

      await tester.tap(_actionButton('Thêm ký quỹ'));
      await _pumpActiveDialog(tester);
      expect(find.text('Nhập số tiền ký quỹ'), findsOneWidget);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(api.prepareCalls, 0);
      expect(api.executeCalls, 0);
    });

    testWidgets('cancel after server prepare sends no execute request', (
      tester,
    ) async {
      final api = _FakeTradeApi();
      await tester.pumpWidget(_tradeApp(api: api, positions: [_position()]));
      await tester.pumpAndSettle();

      await tester.tap(_actionButton('Đóng 100%'));
      await _pumpActiveDialog(tester);
      expect(api.prepareCalls, 1);
      expect(find.text('Xác nhận đóng vị thế 100%'), findsOneWidget);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(api.executeCalls, 0);
    });

    testWidgets('dismissing prepared confirmation sends no execute request', (
      tester,
    ) async {
      final api = _FakeTradeApi();
      await tester.pumpWidget(_tradeApp(api: api, positions: [_position()]));
      await tester.pumpAndSettle();

      await tester.tap(_actionButton('Đóng 100%'));
      await _pumpActiveDialog(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(api.prepareCalls, 1);
      expect(api.executeCalls, 0);
    });

    testWidgets('incomplete position identity cannot prepare an action', (
      tester,
    ) async {
      final api = _FakeTradeApi();
      final incomplete = _position(identity: const {});
      await tester.pumpWidget(_tradeApp(api: api, positions: [incomplete]));
      await tester.pumpAndSettle();

      final button = tester.widget<IconButton>(_actionButton('DCA'));
      expect(button.onPressed, isNull);
      expect(api.prepareCalls, 0);
      expect(api.executeCalls, 0);
    });

    testWidgets('prepared target drift is rejected before confirmation', (
      tester,
    ) async {
      final api = _FakeTradeApi()
        ..preparedIdentityOverride = {
          ..._baseIdentity,
          'instrumentId': 'ETH-USDT-SWAP',
        };
      await tester.pumpWidget(_tradeApp(api: api, positions: [_position()]));
      await tester.pumpAndSettle();

      await tester.tap(_actionButton('Đóng 100%'));
      await tester.pumpAndSettle();
      expect(api.prepareCalls, 1);
      expect(find.text('Xác nhận đóng vị thế 100%'), findsNothing);
      expect(api.executeCalls, 0);
      expect(
        find.text(
          'Máy chủ trả về mục tiêu khác hoặc nhiều mục tiêu. Hãy kiểm tra lại vị thế.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('input submission keeps the position selected before refresh', (
      tester,
    ) async {
      final api = _FakeTradeApi();
      final selected = _position(
        instrumentType: 'MARGIN',
        instrumentId: 'BTC-USDT',
      );
      await tester.pumpWidget(_tradeApp(api: api, positions: [selected]));
      await tester.pumpAndSettle();

      await tester.tap(_actionButton('Thêm ký quỹ'));
      await _pumpActiveDialog(tester);
      expect(find.text('Số tiền (USDT)'), findsOneWidget);

      final refreshed = _position(
        instrumentType: 'MARGIN',
        instrumentId: 'ETH-USDC',
        identity: const {
          'instrumentType': 'MARGIN',
          'instrumentId': 'ETH-USDC',
          'positionId': 'position-2',
          'positionSide': 'net',
          'marginMode': 'isolated',
          'marginCurrency': 'USDC',
        },
      );
      await tester.pumpWidget(_tradeApp(api: api, positions: [refreshed]));
      await tester.enterText(find.byType(TextField), '5');
      await tester.tap(find.text('Tiếp tục'));
      await _pumpActiveDialog(tester);

      expect(api.lastIdentity, selected.identity);
      expect(find.textContaining('BTC-USDT'), findsOneWidget);
      expect(find.textContaining('ETH-USDC'), findsNothing);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(api.executeCalls, 0);
    });

    testWidgets(
      'reordering and removing a card while dialogs are open keeps the action bound to its position',
      (tester) async {
        final api = _FakeTradeApi()..executeGate = Completer<void>();
        final selected = _position(
          instrumentType: 'MARGIN',
          instrumentId: 'BTC-USDT',
        );
        final other = _position(
          instrumentId: 'ETH-USDT-SWAP',
          identity: const {
            'instrumentType': 'SWAP',
            'instrumentId': 'ETH-USDT-SWAP',
            'positionId': 'position-2',
            'positionSide': 'net',
            'marginMode': 'isolated',
          },
        );

        await tester.pumpWidget(
          _tradeApp(api: api, positions: [selected, other]),
        );
        await tester.pumpAndSettle();

        await tester.tap(_actionButton('Thêm ký quỹ').first);
        await _pumpActiveDialog(tester);
        expect(find.text('Nhập số tiền ký quỹ'), findsOneWidget);

        // ResponsiveOrderGrid may reuse the old first card element for the
        // next position when a refresh changes the position ordering.
        await tester.pumpWidget(
          _tradeApp(api: api, positions: [other, selected]),
        );
        await tester.pump();
        expect(find.text('Nhập số tiền ký quỹ'), findsOneWidget);
        await tester.enterText(find.byType(TextField), '5');
        await tester.tap(find.text('Tiếp tục'));
        await _pumpActiveDialog(tester);

        expect(api.prepareCalls, 1);
        expect(api.lastIdentity, selected.identity);
        expect(find.text('Xác nhận thêm ký quỹ'), findsOneWidget);

        // The selected card can disappear while its server-prepared
        // confirmation is open. The dialog remains owned by the page
        // navigator and cannot transfer the action to the remaining card.
        await tester.pumpWidget(_tradeApp(api: api, positions: [other]));
        await tester.pump();
        expect(find.text('Xác nhận thêm ký quỹ'), findsOneWidget);
        await tester.tap(find.text('Xác nhận'));
        await _pumpActiveDialog(tester);

        expect(api.executeCalls, 1);
        expect(find.text('Đã hoàn tất thao tác'), findsNothing);
        api.executeGate!.complete();
        await _pumpActiveDialog(tester);
        expect(find.text('Đã hoàn tất thao tác'), findsOneWidget);
        await tester.tap(find.text('Đóng'));
        await tester.pumpAndSettle();

        expect(api.executeCalls, 1);
        expect(find.text('Đã hoàn tất thao tác'), findsNothing);
      },
    );

    testWidgets(
      'session expiry while prepared confirmation is open cannot execute',
      (tester) async {
        final api = _FakeTradeApi();
        await tester.pumpWidget(_tradeApp(api: api, positions: [_position()]));
        await tester.pumpAndSettle();

        await tester.tap(_actionButton('Đóng 100%'));
        await _pumpActiveDialog(tester);
        expect(find.text('Xác nhận đóng vị thế 100%'), findsOneWidget);

        final container = ProviderScope.containerOf(
          tester.element(find.byType(PositionActionControls).first),
        );
        container.read(tradeSessionProvider.notifier).expire();
        await tester.pump();
        await tester.tap(find.text('Xác nhận đóng'));
        await tester.pumpAndSettle();

        expect(api.prepareCalls, 1);
        expect(api.executeCalls, 0);
        expect(
          find.text(
            'Phiên giao dịch đã thay đổi hoặc hết hạn. Hãy đăng nhập lại.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'new unresolved operation while confirmation is open blocks execute',
      (tester) async {
        final api = _FakeTradeApi();
        await tester.pumpWidget(_tradeApp(api: api, positions: [_position()]));
        await tester.pumpAndSettle();

        await tester.tap(_actionButton('Đóng 100%'));
        await _pumpActiveDialog(tester);
        expect(find.text('Xác nhận đóng vị thế 100%'), findsOneWidget);

        final container = ProviderScope.containerOf(
          tester.element(find.byType(PositionActionControls).first),
        );
        container
            .read(tradeSessionProvider.notifier)
            .rememberOperation(
              const PendingTradeOperation(
                operationId: 'previous-operation',
                action: 'close_position',
                targetLabel: 'BTC-USDT-SWAP',
                status: 'UNKNOWN',
              ),
            );
        await tester.pump();
        await tester.tap(find.text('Xác nhận đóng'));
        await tester.pumpAndSettle();

        expect(api.prepareCalls, 1);
        expect(api.executeCalls, 0);
        expect(
          find.text(
            'Có thao tác chưa rõ kết quả. Tra cứu trạng thái trước khi gửi thao tác mới.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('a repeated tap while execute is pending sends once', (
      tester,
    ) async {
      final api = _FakeTradeApi()..executeGate = Completer<void>();
      await tester.pumpWidget(_tradeApp(api: api, positions: [_position()]));
      await tester.pumpAndSettle();

      await tester.tap(_actionButton('Đóng 100%'));
      await _pumpActiveDialog(tester);
      await tester.tap(find.text('Xác nhận đóng'));
      await _pumpActiveDialog(tester);
      expect(api.executeCalls, 1);

      await tester.tap(_actionButton('Đóng 100%'), warnIfMissed: false);
      await tester.pump();
      expect(api.executeCalls, 1);
      api.executeGate!.complete();
      await _pumpActiveDialog(tester);
    });

    testWidgets('selected full close prepares exactly its single target', (
      tester,
    ) async {
      final api = _FakeTradeApi();
      await tester.pumpWidget(_tradeApp(api: api, positions: [_position()]));
      await tester.pumpAndSettle();

      await tester.tap(_actionButton('Đóng 100%'));
      await _pumpActiveDialog(tester);
      expect(api.lastAction, 'close_position');
      expect(api.lastIdentity, _baseIdentity);
      expect(api.prepareCalls, 1);
      expect(find.textContaining('BTC-USDT-SWAP'), findsOneWidget);
      expect(find.textContaining('ETH-USDT'), findsNothing);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(api.executeCalls, 0);
    });

    testWidgets('close all ignores the selected SWAP display filter', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _FakeTradeApi();
      await tester.pumpWidget(
        _tradeApp(
          api: api,
          positions: [_position()],
          filter: 'SWAP',
          showActions: false,
          showAccountControls: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Đóng tất cả vị thế'), findsOneWidget);
      final closeAllTooltip = find.byTooltip('Đóng tất cả vị thế');
      final closeAllButton = find.descendant(
        of: closeAllTooltip,
        matching: find.byType(TextButton),
      );
      expect(tester.getSize(closeAllButton).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(closeAllButton).height, greaterThanOrEqualTo(48));
      expect(
        find.descendant(
          of: closeAllTooltip,
          matching: find.byIcon(Icons.warning_amber_rounded),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Đóng tất cả vị thế'));
      await _pumpActiveDialog(tester);
      expect(api.lastAction, 'close_all');
      expect(api.lastIdentity, isNull);
      expect(find.textContaining('BTC-USDT-SWAP'), findsOneWidget);
      expect(find.textContaining('ETH-USDT'), findsOneWidget);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(api.executeCalls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('close-all button uses red foreground and outline by theme', (
      tester,
    ) async {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final api = _FakeTradeApi();
        await tester.pumpWidget(
          _tradeApp(
            api: api,
            showActions: false,
            showAccountControls: true,
            brightness: brightness,
          ),
        );
        await tester.pumpAndSettle();

        final tooltip = find.byTooltip('Đóng tất cả vị thế');
        final button = tester.widget<TextButton>(
          find.descendant(of: tooltip, matching: find.byType(TextButton)),
        );
        final expectedColor = brightness == Brightness.dark
            ? PnlColors.darkNegative
            : PnlColors.lightNegative;
        expect(button.style?.foregroundColor?.resolve({}), expectedColor);
        expect(
          button.style?.side?.resolve({}),
          BorderSide(color: expectedColor, width: 1),
        );
      }
    });

    testWidgets('ineligible close-all prepare surfaces server reason', (
      tester,
    ) async {
      final api = _FakeTradeApi()
        ..prepareError = const TradeApiException(
          code: 'close_all_ineligible_targets',
          message: 'The complete target set cannot be closed.',
          details: {
            'ineligibleTargets': [
              {
                'identity': {'instrumentId': 'ETH-USDT-SWAP'},
                'reason': 'unknown_margin_mode',
              },
            ],
          },
        );
      await tester.pumpWidget(
        _tradeApp(
          api: api,
          positions: [_position()],
          showActions: false,
          showAccountControls: true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Đóng tất cả vị thế'));
      await tester.pumpAndSettle();

      expect(api.lastAction, isNull);
      expect(api.executeCalls, 0);
      expect(
        find.textContaining('ETH-USDT-SWAP: unknown margin mode'),
        findsOneWidget,
      );
    });

    testWidgets('server-disabled MARGIN DCA and partial close show reasons', (
      tester,
    ) async {
      final api = _FakeTradeApi();
      final margin = _position(
        instrumentType: 'MARGIN',
        instrumentId: 'BTC-USDT',
        eligibility: const {
          'addMargin': {'eligible': true},
          'dca': {
            'eligible': false,
            'reason': 'margin_dca_capacity_unverified',
          },
          'partialClose': {
            'eligible': false,
            'reason': 'margin_partial_close_capacity_unverified',
          },
          'closePosition': {'eligible': true},
        },
      );
      await tester.pumpWidget(_tradeApp(api: api, positions: [margin]));
      await tester.pumpAndSettle();

      expect(tester.widget<IconButton>(_actionButton('DCA')).onPressed, isNull);
      expect(
        tester.widget<IconButton>(_actionButton('Đóng một phần')).onPressed,
        isNull,
      );
      expect(
        find.textContaining(
          'MARGIN DCA is disabled because trade capacity is not verified.',
        ),
        findsOneWidget,
      );
      expect(api.prepareCalls, 0);
    });
  });

  group('GREEN-002 prepared actions', () {
    testWidgets(
      'GREEN-ADD add margin confirms the server-prepared amount and refreshes',
      (tester) async {
        final api = _FakeTradeApi();
        await tester.pumpWidget(_tradeApp(api: api, positions: [_position()]));
        await tester.pumpAndSettle();
        final initialReads = api.positionReads;

        await tester.tap(_actionButton('Thêm ký quỹ'));
        await _pumpActiveDialog(tester);
        await tester.enterText(find.byType(TextField), '5');
        await tester.tap(find.text('Tiếp tục'));
        await _pumpActiveDialog(tester);
        expect(api.lastAction, 'add_margin');
        expect(api.lastAmount, '5');
        expect(find.textContaining('Số tiền chuẩn hóa: 5.00'), findsOneWidget);
        await tester.tap(find.text('Xác nhận'));
        await _pumpActiveDialog(tester);

        expect(api.executeCalls, 1);
        expect(api.resultCalls, 0);
        expect(api.positionReads, greaterThan(initialReads));
        expect(find.text('Đã hoàn tất thao tác'), findsWidgets);
      },
    );

    testWidgets('DCA confirms the server-normalized contract size', (
      tester,
    ) async {
      final api = _FakeTradeApi();
      await tester.pumpWidget(_tradeApp(api: api, positions: [_position()]));
      await tester.pumpAndSettle();

      await tester.tap(_actionButton('DCA'));
      await _pumpActiveDialog(tester);
      await tester.enterText(find.byType(TextField), '1');
      await tester.tap(find.text('Tiếp tục'));
      await _pumpActiveDialog(tester);
      expect(api.lastSize, '1');
      expect(find.textContaining('Khối lượng chuẩn hóa: 0.5'), findsOneWidget);
      await tester.tap(find.text('Xác nhận'));
      await _pumpActiveDialog(tester);
      expect(api.executeCalls, 1);
      expect(find.text('Đã hoàn tất thao tác'), findsWidgets);
    });

    testWidgets('partial close confirms the server-normalized percentage', (
      tester,
    ) async {
      final api = _FakeTradeApi();
      await tester.pumpWidget(_tradeApp(api: api, positions: [_position()]));
      await tester.pumpAndSettle();

      await tester.tap(_actionButton('Đóng một phần'));
      await _pumpActiveDialog(tester);
      await tester.enterText(find.byType(TextField), '50');
      await tester.tap(find.text('Tiếp tục'));
      await _pumpActiveDialog(tester);
      expect(api.lastPercentage, '50');
      expect(find.textContaining('Khối lượng chuẩn hóa: 1'), findsOneWidget);
      await tester.tap(find.text('Xác nhận'));
      await _pumpActiveDialog(tester);
      expect(api.executeCalls, 1);
      expect(find.text('Đã hoàn tất thao tác'), findsWidgets);
    });

    testWidgets('full close executes once for the selected target', (
      tester,
    ) async {
      final api = _FakeTradeApi();
      await tester.pumpWidget(_tradeApp(api: api, positions: [_position()]));
      await tester.pumpAndSettle();

      await tester.tap(_actionButton('Đóng 100%'));
      await _pumpActiveDialog(tester);
      await tester.tap(find.text('Xác nhận đóng'));
      await _pumpActiveDialog(tester);
      expect(api.lastAction, 'close_position');
      expect(api.lastIdentity, _baseIdentity);
      expect(api.executeCalls, 1);
      expect(find.text('Đã hoàn tất thao tác'), findsWidgets);
    });

    testWidgets('close all confirms all prepared targets and refreshes', (
      tester,
    ) async {
      final api = _FakeTradeApi();
      await tester.pumpWidget(
        _tradeApp(
          api: api,
          positions: [_position()],
          filter: 'SPOT',
          showActions: false,
          showAccountControls: true,
        ),
      );
      await tester.pumpAndSettle();
      final initialReads = api.positionReads;

      await tester.tap(find.byTooltip('Đóng tất cả vị thế'));
      await _pumpActiveDialog(tester);
      expect(find.text('Đóng 2 vị thế'), findsOneWidget);
      expect(find.textContaining('ETH-USDT'), findsOneWidget);
      await tester.tap(find.text('Đóng 2 vị thế'));
      await _pumpActiveDialog(tester);

      expect(api.lastAction, 'close_all');
      expect(api.lastIdentity, isNull);
      expect(api.executeCalls, 1);
      expect(api.positionReads, greaterThan(initialReads));
      expect(find.text('Đã hoàn tất đóng tất cả vị thế'), findsWidgets);
    });

    testWidgets(
      'login sends password and TOTP then shows only masked account',
      (tester) async {
        final api = _FakeTradeApi();
        await tester.pumpWidget(
          _tradeApp(
            api: api,
            authenticated: false,
            showActions: false,
            showSessionControls: true,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Đăng nhập'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField).at(0),
          'long-test-password',
        );
        await tester.enterText(find.byType(TextField).at(1), '123456');
        await tester.tap(find.text('Đăng nhập').last);
        await tester.pumpAndSettle();

        expect(api.loginCalls, 1);
        expect(api.passwordSeen, 'long-test-password');
        expect(api.totpSeen, '123456');
        expect(find.textContaining('••••-42'), findsOneWidget);
        expect(find.text('in-memory-test-token'), findsNothing);
      },
    );

    testWidgets('Positions directs signed-out users to Settings', (
      tester,
    ) async {
      final api = _FakeTradeApi();
      await tester.pumpWidget(
        _tradeApp(
          api: api,
          authenticated: false,
          showActions: false,
          showAccountControls: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Đăng nhập'), findsNothing);
      expect(find.text('Đăng xuất'), findsNothing);
      expect(find.textContaining('Cài đặt'), findsOneWidget);
    });

    test('restores an active cookie session before enabling actions', () async {
      final session = TradeSession(
        bearerToken: 'restored-in-memory-token',
        accountIdentifier: 'account-42',
        expiresAt: DateTime.now().add(const Duration(hours: 8)),
      );
      final api = _FakeTradeApi(
        sessionRestorationSupported: true,
        restoredSession: session,
      );
      final controller = TradeSessionController(api);

      final restore = controller.restore();

      expect(controller.state.isLoading, isTrue);
      expect(controller.state.isAuthenticated, isFalse);
      expect(await restore, isTrue);
      expect(api.restoreCalls, 1);
      expect(controller.state.isAuthenticated, isTrue);
      expect(controller.state.session?.bearerToken, 'restored-in-memory-token');
    });

    test('a missing or expired cookie leaves the session signed out', () async {
      final api = _FakeTradeApi(sessionRestorationSupported: true);
      final controller = TradeSessionController(api);

      expect(await controller.restore(), isFalse);
      expect(controller.state.isAuthenticated, isFalse);
      expect(controller.state.session, isNull);
      expect(controller.state.errorMessage, isNull);

      final expiredController = TradeSessionController(
        _FakeTradeApi(
          sessionRestorationSupported: true,
          restoredSession: TradeSession(
            bearerToken: 'expired-token',
            accountIdentifier: 'account-42',
            expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
          ),
        ),
      );
      expect(await expiredController.restore(), isFalse);
      expect(expiredController.state.isAuthenticated, isFalse);
      expect(expiredController.state.session, isNull);
      expect(expiredController.state.errorMessage, contains('expired'));
    });

    test(
      'stale restoration cannot overwrite a later login or logout',
      () async {
        final restoredSession = TradeSession(
          bearerToken: 'stale-cookie-token',
          accountIdentifier: 'account-42',
          expiresAt: DateTime.now().add(const Duration(hours: 8)),
        );
        final loginGate = Completer<TradeSession>();
        final loginApi = _FakeTradeApi(
          sessionRestorationSupported: true,
          restoreGate: loginGate,
        );
        final loginController = TradeSessionController(loginApi);
        final pendingLoginRestore = loginController.restore();
        expect(
          await loginController.login(password: 'password', totp: '123456'),
          isTrue,
        );
        loginGate.complete(restoredSession);
        expect(await pendingLoginRestore, isFalse);
        expect(
          loginController.state.session?.bearerToken,
          'in-memory-test-token',
        );

        final logoutGate = Completer<TradeSession>();
        final logoutApi = _FakeTradeApi(
          sessionRestorationSupported: true,
          restoreGate: logoutGate,
        );
        final logoutController = TradeSessionController(logoutApi);
        final pendingLogoutRestore = logoutController.restore();
        expect(await logoutController.logout(), isTrue);
        logoutGate.complete(restoredSession);
        expect(await pendingLogoutRestore, isFalse);
        expect(logoutController.state.session, isNull);
        expect(logoutController.state.isAuthenticated, isFalse);
      },
    );

    test(
      'failed logout keeps the session and exposes a retryable error',
      () async {
        final api = _FakeTradeApi(
          logoutFailure: const TradeApiException(
            code: 'network_error',
            message: 'temporary connection failure',
          ),
        );
        final controller = TradeSessionController(api);
        expect(
          await controller.login(password: 'password', totp: '123456'),
          isTrue,
        );

        expect(await controller.logout(), isFalse);
        expect(controller.state.session?.bearerToken, 'in-memory-test-token');
        expect(controller.state.isAuthenticated, isTrue);
        expect(controller.state.errorMessage, contains('temporary connection'));

        api.logoutFailure = null;
        expect(await controller.logout(), isTrue);
        expect(controller.state.session, isNull);
        expect(api.logoutCalls, 2);
      },
    );

    testWidgets('unknown result remains visible and is looked up', (
      tester,
    ) async {
      final api = _FakeTradeApi()..executeStatus = 'UNKNOWN';
      await tester.pumpWidget(
        _tradeApp(
          api: api,
          positions: [_position()],
          showAccountControls: true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_actionButton('Đóng 100%'));
      await _pumpActiveDialog(tester);
      await tester.tap(find.text('Xác nhận đóng'));
      await _pumpActiveDialog(tester);

      expect(api.executeCalls, 1);
      expect(api.resultCalls, 1);
      expect(find.text('Chưa rõ kết quả thao tác'), findsWidgets);
      expect(find.textContaining('operation-12345678'), findsWidgets);
      await tester.tap(find.text('Đóng').last);
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _tradeApp(
          api: api,
          positions: [_position(instrumentId: 'ETH-USDT-SWAP')],
          showAccountControls: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('operation-12345678'), findsOneWidget);
      expect(
        tester.widget<IconButton>(_actionButton('Đóng 100%')).onPressed,
        isNull,
      );
      expect(api.executeCalls, 1);

      api.executeStatus = 'SUCCEEDED';
      await tester.tap(find.text('Tra cứu trạng thái'));
      await _pumpActiveDialog(tester);

      expect(api.resultCalls, 2);
      expect(api.executeCalls, 1);
      expect(find.text('Đã hoàn tất thao tác'), findsWidgets);
      await tester.tap(find.text('Đóng').last);
      await tester.pumpAndSettle();
      expect(find.text('operation-12345678'), findsNothing);
      expect(
        tester.widget<IconButton>(_actionButton('Đóng 100%')).onPressed,
        isNotNull,
      );
    });

    testWidgets('execute transport failure reconciles once and stays unknown', (
      tester,
    ) async {
      final api = _FakeTradeApi()
        ..executeError = const TradeApiException(
          code: 'network_error',
          message: 'Temporary API failure.',
          statusCode: 503,
        )
        ..executeStatus = 'UNKNOWN';
      await tester.pumpWidget(_tradeApp(api: api, positions: [_position()]));
      await tester.pumpAndSettle();

      await tester.tap(_actionButton('Đóng 100%'));
      await _pumpActiveDialog(tester);
      await tester.tap(find.text('Xác nhận đóng'));
      await _pumpActiveDialog(tester);

      expect(api.executeCalls, 1);
      expect(api.resultCalls, 1);
      expect(find.text('Chưa rõ kết quả thao tác'), findsWidgets);
      expect(find.textContaining('Temporary API failure.'), findsNothing);
    });

    testWidgets('close-all unknown transport outcome gets one status lookup', (
      tester,
    ) async {
      final api = _FakeTradeApi()
        ..executeError = const TradeApiException(
          code: 'network_error',
          message: 'Temporary API failure.',
          statusCode: 503,
        )
        ..executeStatus = 'UNKNOWN';
      await tester.pumpWidget(
        _tradeApp(
          api: api,
          positions: [_position()],
          showActions: false,
          showAccountControls: true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Đóng tất cả vị thế'));
      await _pumpActiveDialog(tester);
      await tester.tap(find.text('Đóng 2 vị thế'));
      await _pumpActiveDialog(tester);

      expect(api.executeCalls, 1);
      expect(api.resultCalls, 1);
      expect(find.text('Chưa rõ kết quả đóng tất cả'), findsWidgets);
      expect(find.textContaining('operation-12345678'), findsWidgets);
      await tester.tap(find.text('Đóng').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('operation-12345678'), findsOneWidget);

      api.executeStatus = 'SUCCEEDED';
      await tester.tap(find.text('Tra cứu trạng thái'));
      await _pumpActiveDialog(tester);
      expect(api.executeCalls, 1);
      expect(api.resultCalls, 2);
      expect(find.text('Đã hoàn tất đóng tất cả vị thế'), findsWidgets);
      await tester.tap(find.text('Đóng').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('operation-12345678'), findsNothing);
      expect(
        tester
            .widget<TextButton>(
              find.descendant(
                of: find.byTooltip('Đóng tất cả vị thế'),
                matching: find.byType(TextButton),
              ),
            )
            .onPressed,
        isNotNull,
      );
    });
  });
}
