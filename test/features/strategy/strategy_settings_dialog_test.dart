import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/orders/data/trade_api_client.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/trade_session_provider.dart';
import 'package:trading_balance_f/features/strategy/data/strategy_api_client.dart';
import 'package:trading_balance_f/features/strategy/presentation/providers/strategy_dashboard_provider.dart';
import 'package:trading_balance_f/features/strategy/presentation/strategy_settings_dialog.dart';

void main() {
  testWidgets('save failure retains selection without saved claim', (
    tester,
  ) async {
    final api = _FakeStrategyApi()
      ..saveError = const StrategyApiException(
        code: 'settings_rejected',
        statusCode: 503,
        message: 'Cài đặt chưa được lưu.',
      );
    final harness = await _pumpSettings(tester, api);

    await tester.tap(find.byKey(const Key('strategy-settings-batch')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('strategy-settings-save')));
    await tester.pumpAndSettle();

    expect(_selectedMode(tester), 'batch');
    expect(find.text('Cài đặt chưa được lưu.'), findsOneWidget);
    expect(find.text('Máy chủ đã xác nhận lưu cài đặt.'), findsNothing);
    expect(api.preference, 'sequential');
    harness.dashboard.dispose();
  });

  testWidgets('cancel discards an unsaved selection', (tester) async {
    final api = _FakeStrategyApi();
    final harness = await _pumpSettings(tester, api);

    await tester.tap(find.byKey(const Key('strategy-settings-batch')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('strategy-settings-cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();

    expect(_selectedMode(tester), 'sequential');
    expect(api.preference, 'sequential');
    harness.dashboard.dispose();
  });

  testWidgets('settings load failure never selects an assumed default', (
    tester,
  ) async {
    final api = _FakeStrategyApi()
      ..settingsGetError = const StrategyApiException(
        code: 'settings_unavailable',
        statusCode: 503,
        message: 'Không tải được cài đặt.',
      );
    final harness = await _pumpSettings(tester, api);

    expect(find.text('Không tải được cài đặt.'), findsOneWidget);
    expect(_selectedMode(tester), isNull);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('strategy-settings-save')))
          .onPressed,
      isNull,
    );
    harness.dashboard.dispose();
  });

  test('duplicate settings saves share no second write', () async {
    final api = _FakeStrategyApi()..settingsSaveCompleter = Completer<String>();
    final session = _MutableSessionController('session-a');
    final dashboard = StrategyDashboardController(
      api: api,
      bearerToken: 'session-a',
      sessionIsCurrent: () =>
          session.state.isAuthenticated &&
          session.state.session?.bearerToken == 'session-a',
    );

    final first = dashboard.saveLimitOrderSubmissionMode('batch');
    await Future<void>.delayed(Duration.zero);
    final second = await dashboard.saveLimitOrderSubmissionMode('batch');
    expect(second, isFalse);
    expect(api.settingsSaveCalls, 1);

    api.settingsSaveCompleter!.complete('batch');
    expect(await first, isTrue);
    expect(dashboard.limitOrderSubmissionMode, 'batch');
    dashboard.dispose();
  });

  testWidgets('settings mode persists and queue confirmation stays frozen', (
    tester,
  ) async {
    final api = _FakeStrategyApi();
    final harness = await _pumpSettings(tester, api);

    await tester.tap(find.byKey(const Key('strategy-settings-batch')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('strategy-settings-save')));
    await tester.pumpAndSettle();

    expect(find.text('Máy chủ đã xác nhận lưu cài đặt.'), findsOneWidget);
    expect(api.preference, 'batch');
    await harness.dashboard.loadStrategySettings(force: true);
    expect(harness.dashboard.limitOrderSubmissionMode, 'batch');
    expect(api.settingsGetCalls, 2);

    String? frozenMode;
    final outcome = await harness.dashboard.applyDraft(
      'draft-1',
      confirm: (prepared) async {
        frozenMode = prepared['submissionMode'] as String?;
        return true;
      },
    );

    expect(frozenMode, 'sequential');
    expect(outcome.kind, StrategyApplyOutcomeKind.queued);
    expect(outcome.result?['submissionMode'], 'sequential');
    expect(outcome.result?['queueStatus'], 'pending');
    expect(api.executeCalls, 1);
    harness.dashboard.dispose();
  });

  testWidgets('late account A settings GET is ignored after account switch', (
    tester,
  ) async {
    final api = _FakeStrategyApi()
      ..settingsGetCompleter = Completer<String>()
      ..settingsSaveCompleter = Completer<String>();
    final harness = await _pumpSettings(tester, api, waitForInitialLoad: false);

    harness.session.switchTo('session-b');
    await tester.pump();
    api.settingsGetCompleter!.complete('sequential');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(harness.dashboard.limitOrderSubmissionMode, isNull);
    expect(find.textContaining('Phiên giao dịch đã thay đổi.'), findsOneWidget);

    harness.dashboard.dispose();
  });

  testWidgets('late account A save ACK after account switch is ignored', (
    tester,
  ) async {
    final api = _FakeStrategyApi()..settingsSaveCompleter = Completer<String>();
    final harness = await _pumpSettings(tester, api);

    await tester.tap(find.byKey(const Key('strategy-settings-batch')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('strategy-settings-save')));
    await tester.pump();
    expect(api.settingsSaveCalls, 1);

    harness.session.switchTo('session-b');
    await tester.pump();
    api.settingsSaveCompleter!.complete('batch');
    await tester.pump();

    expect(find.textContaining('Phiên giao dịch đã thay đổi.'), findsOneWidget);
    expect(find.text('Máy chủ đã xác nhận lưu cài đặt.'), findsNothing);
    expect(harness.dashboard.limitOrderSubmissionMode, 'sequential');
    harness.dashboard.dispose();
  });

  testWidgets('signed-out settings explain login and keep saving disabled', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StrategySettingsDialog(bearerToken: null, dashboard: null),
          ),
        ),
      ),
    );

    expect(
      find.text(
        'Đăng nhập phiên giao dịch để xem và lưu cơ chế gửi lệnh limit.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('strategy-settings-save')))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(360, 800), Size(1280, 900)]) {
    testWidgets('settings modal lays out at ${size.width.toInt()} px', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _FakeStrategyApi();
      final harness = await _pumpSettings(
        tester,
        api,
        useLauncher: false,
        size: size,
      );

      expect(find.text('Cài đặt chiến thuật'), findsOneWidget);
      expect(find.text('Hàng đợi tuần tự'), findsOneWidget);
      expect(tester.takeException(), isNull);
      harness.dashboard.dispose();
    });
  }
}

String? _selectedMode(WidgetTester tester) => tester
    .widget<RadioGroup<String>>(
      find.byKey(const Key('strategy-settings-mode-group')),
    )
    .groupValue;

Future<_SettingsHarness> _pumpSettings(
  WidgetTester tester,
  _FakeStrategyApi api, {
  bool waitForInitialLoad = true,
  bool useLauncher = true,
  Size size = const Size(420, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final session = _MutableSessionController('session-a');
  final dashboard = StrategyDashboardController(
    api: api,
    bearerToken: 'session-a',
    sessionIsCurrent: () =>
        session.state.isAuthenticated &&
        session.state.session?.bearerToken == 'session-a',
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tradeSessionProvider.overrideWith((ref) => session),
        strategyApiProvider.overrideWithValue(api),
      ],
      child: MaterialApp(
        home: useLauncher
            ? Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    key: const Key('open-settings'),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (context) => StrategySettingsDialog(
                        bearerToken: 'session-a',
                        dashboard: dashboard,
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              )
            : Scaffold(
                body: StrategySettingsDialog(
                  bearerToken: 'session-a',
                  dashboard: dashboard,
                ),
              ),
      ),
    ),
  );
  if (useLauncher) await tester.tap(find.byKey(const Key('open-settings')));
  await tester.pump();
  if (waitForInitialLoad) await tester.pumpAndSettle();
  return _SettingsHarness(dashboard: dashboard, session: session);
}

class _SettingsHarness {
  const _SettingsHarness({required this.dashboard, required this.session});

  final StrategyDashboardController dashboard;
  final _MutableSessionController session;
}

class _MutableSessionController extends TradeSessionController {
  _MutableSessionController(String bearerToken)
    : super(TradeApiClient(baseUrl: 'https://trade.example')) {
    switchTo(bearerToken);
  }

  void switchTo(String bearerToken) {
    state = TradeSessionState(
      session: TradeSession(
        bearerToken: bearerToken,
        accountIdentifier: bearerToken,
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
  }
}

class _FakeStrategyApi implements StrategyApi {
  String preference = 'sequential';
  StrategyApiException? settingsGetError;
  StrategyApiException? saveError;
  Completer<String>? settingsGetCompleter;
  Completer<String>? settingsSaveCompleter;
  int settingsGetCalls = 0;
  int settingsSaveCalls = 0;
  int executeCalls = 0;

  final prepared = <String, dynamic>{
    'confirmationToken': 'one-use-token',
    'submissionMode': 'sequential',
    'estimatedOpeningFees': '0.03',
    'orders': [
      {
        'side': 'long',
        'role': 'entry',
        'limitPrice': '65000',
        'contracts': '1',
        'margin': '13',
        'leverage': 5,
        'openingFeeEstimate': '0.03',
      },
    ],
  };

  @override
  Future<String> getLimitOrderSubmissionMode(String token) {
    settingsGetCalls++;
    if (settingsGetError != null) throw settingsGetError!;
    return settingsGetCompleter?.future ?? Future.value(preference);
  }

  @override
  Future<String> saveLimitOrderSubmissionMode(String token, String mode) async {
    settingsSaveCalls++;
    if (saveError != null) throw saveError!;
    final acknowledged = settingsSaveCompleter == null
        ? mode
        : await settingsSaveCompleter!.future;
    preference = acknowledged;
    return acknowledged;
  }

  @override
  Future<Map<String, dynamic>> preview(
    String token,
    Map<String, dynamic> body,
  ) async => {};

  @override
  Future<Map<String, dynamic>> saveDraft(
    String token,
    Map<String, dynamic> body,
  ) async => {'id': 'draft-1'};

  @override
  Future<List<Map<String, dynamic>>> listStrategies(String token) async => [];

  @override
  Future<Map<String, dynamic>> prepareApply(String token, String id) async =>
      prepared;

  @override
  Future<Map<String, dynamic>> executeApply(
    String token,
    String id,
    String confirmationToken,
  ) async {
    executeCalls++;
    return {
      'status': 'APPLYING',
      'submissionMode': 'sequential',
      'queueStatus': 'pending',
      'queueProgress': {
        'totalCount': 1,
        'attemptedCount': 0,
        'acceptedCount': 0,
        'pendingCount': 1,
        'notSubmittedCount': 0,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getResult(String token, String id) async => {};

  @override
  Future<Map<String, dynamic>> getQuote(String token, String id) async => {};

  @override
  Future<void> deleteDraft(String token, String id) async {}
}
