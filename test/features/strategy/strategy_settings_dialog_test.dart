import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/orders/data/trade_api_client.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/trade_session_provider.dart';
import 'package:trading_balance_f/features/strategy/data/strategy_api_client.dart';
import 'package:trading_balance_f/features/strategy/domain/strategy_models.dart';
import 'package:trading_balance_f/features/strategy/domain/strategy_settings.dart';
import 'package:trading_balance_f/features/strategy/presentation/providers/strategy_dashboard_provider.dart';
import 'package:trading_balance_f/features/strategy/presentation/strategy_settings_dialog.dart';

void main() {
  testWidgets('JEV percentage settings reject values above 100', (
    tester,
  ) async {
    final api = _FakeStrategyApi();
    final harness = await _pumpSettings(tester, api);

    expect(
      find.byKey(const Key('strategy-settings-entry-suitability-percent')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('strategy-settings-entry-suitability-percent')),
      '100.1',
    );
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('strategy-settings-save')))
          .onPressed,
      isNull,
    );
    expect(api.settingsSaveCalls, 0);
    harness.dashboard.dispose();
  });

  testWidgets('full JEV settings save and reload without rounding', (
    tester,
  ) async {
    final api = _FakeStrategyApi();
    final harness = await _pumpSettings(tester, api);

    await tester.tap(
      find.byKey(const Key('strategy-settings-min-structural-quality')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('3').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('strategy-settings-entry-suitability-percent')),
      '55,5',
    );
    await tester.enterText(
      find.byKey(const Key('strategy-settings-failure-risk-percent')),
      '45',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('strategy-settings-save')));
    await tester.pumpAndSettle();

    const expected = StrategySettings(
      limitOrderSubmissionMode: 'sequential',
      jevScreeningThresholds: StrategyJevScreeningThresholds(
        minStructuralQuality: 3,
        minEntrySuitabilityProbability: 0.555,
        maxFailureRiskProbability: 0.45,
      ),
    );
    expect(api.settings, expected);
    expect(harness.dashboard.strategySettings, expected);
    expect(find.text('Máy chủ đã xác nhận lưu cài đặt.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('strategy-settings-cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<DropdownButton<int>>(
            find.byKey(const Key('strategy-settings-min-structural-quality')),
          )
          .value,
      3,
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(
              const Key('strategy-settings-entry-suitability-percent'),
            ),
          )
          .controller!
          .text,
      '55.5',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('strategy-settings-failure-risk-percent')),
          )
          .controller!
          .text,
      '45',
    );
    harness.dashboard.dispose();
  });

  testWidgets('tiny valid probabilities stay editable and save exactly', (
    tester,
  ) async {
    final api = _FakeStrategyApi()
      ..settings = const StrategySettings(
        limitOrderSubmissionMode: 'sequential',
        jevScreeningThresholds: StrategyJevScreeningThresholds(
          minStructuralQuality: 0,
          minEntrySuitabilityProbability: 0.000000001,
          maxFailureRiskProbability: 1,
        ),
      );
    final harness = await _pumpSettings(tester, api);

    expect(
      tester
          .widget<TextField>(
            find.byKey(
              const Key('strategy-settings-entry-suitability-percent'),
            ),
          )
          .controller!
          .text,
      '0.0000001',
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('strategy-settings-save')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('strategy-settings-save')));
    await tester.pumpAndSettle();

    expect(api.lastSubmittedSettings, api.settings);
    harness.dashboard.dispose();
  });

  testWidgets('mismatched full settings ACK keeps the local draft', (
    tester,
  ) async {
    final api = _FakeStrategyApi()
      ..settingsSaveAcknowledgementOverride = const StrategySettings(
        limitOrderSubmissionMode: 'batch',
        jevScreeningThresholds: StrategyJevScreeningThresholds(
          minStructuralQuality: 4,
          minEntrySuitabilityProbability: 0.6,
          maxFailureRiskProbability: 0.4,
        ),
      );
    final harness = await _pumpSettings(tester, api);

    await tester.tap(find.byKey(const Key('strategy-settings-batch')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('strategy-settings-entry-suitability-percent')),
      '55',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('strategy-settings-save')));
    await tester.pumpAndSettle();

    expect(api.settingsSaveCalls, 1);
    expect(
      api
          .lastSubmittedSettings
          ?.jevScreeningThresholds
          .minEntrySuitabilityProbability,
      0.55,
    );
    expect(find.text('Máy chủ đã xác nhận lưu cài đặt.'), findsNothing);
    expect(
      find.text('Máy chủ chưa xác nhận đầy đủ các cài đặt đã lưu.'),
      findsOneWidget,
    );
    expect(_selectedMode(tester), 'batch');
    expect(
      tester
          .widget<TextField>(
            find.byKey(
              const Key('strategy-settings-entry-suitability-percent'),
            ),
          )
          .controller!
          .text,
      '55',
    );
    harness.dashboard.dispose();
  });

  testWidgets('dirty settings survive reload and save the displayed baseline', (
    tester,
  ) async {
    final api = _FakeStrategyApi();
    final harness = await _pumpSettings(tester, api);

    await tester.enterText(
      find.byKey(const Key('strategy-settings-entry-suitability-percent')),
      '55',
    );
    api.settings = const StrategySettings(
      limitOrderSubmissionMode: 'sequential',
      jevScreeningThresholds: StrategyJevScreeningThresholds(
        minStructuralQuality: 2,
        minEntrySuitabilityProbability: 0.3,
        maxFailureRiskProbability: 0.8,
      ),
    );
    await harness.dashboard.loadStrategySettings(force: true);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<DropdownButton<int>>(
            find.byKey(const Key('strategy-settings-min-structural-quality')),
          )
          .value,
      4,
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('strategy-settings-failure-risk-percent')),
          )
          .controller!
          .text,
      '40',
    );
    await tester.tap(find.byKey(const Key('strategy-settings-save')));
    await tester.pumpAndSettle();

    expect(
      api.lastSubmittedSettings?.jevScreeningThresholds,
      const StrategyJevScreeningThresholds(
        minStructuralQuality: 4,
        minEntrySuitabilityProbability: 0.55,
        maxFailureRiskProbability: 0.4,
      ),
    );
    harness.dashboard.dispose();
  });

  test(
    'controller rejects invalid full-capability settings before adoption',
    () async {
      final api = _FakeStrategyApi()
        ..settingsGetOverride = const StrategySettings(
          limitOrderSubmissionMode: 'sequential',
          jevScreeningThresholds: StrategyJevScreeningThresholds(
            minStructuralQuality: 6,
            minEntrySuitabilityProbability: 0.6,
            maxFailureRiskProbability: 0.4,
          ),
        );
      final dashboard = StrategyDashboardController(
        api: api,
        bearerToken: 'session-a',
      );

      await dashboard.loadStrategySettings();

      expect(dashboard.strategySettings, isNull);
      expect(dashboard.limitOrderSubmissionMode, isNull);
      expect(
        dashboard.settingsError,
        contains('cài đặt chiến thuật không hợp lệ'),
      );
      dashboard.dispose();
    },
  );

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
    await tester.enterText(
      find.byKey(const Key('strategy-settings-entry-suitability-percent')),
      '55',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('strategy-settings-cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();

    expect(_selectedMode(tester), 'sequential');
    expect(api.preference, 'sequential');
    expect(api.settingsSaveCalls, 0);
    expect(
      tester
          .widget<TextField>(
            find.byKey(
              const Key('strategy-settings-entry-suitability-percent'),
            ),
          )
          .controller!
          .text,
      '60',
    );
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

  testWidgets(
    'legacy mode-only API keeps JEV unavailable and saves only mode',
    (tester) async {
      final api = _LegacySettingsApi();
      final harness = await _pumpSettings(tester, api);

      expect(
        find.text('Cài đặt sàng lọc JEV chưa khả dụng trên API của phiên này.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('strategy-settings-entry-suitability-percent')),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('strategy-settings-batch')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('strategy-settings-save')));
      await tester.pumpAndSettle();

      expect(api.delegate.preference, 'batch');
      expect(api.delegate.settingsSaveCalls, 1);
      expect(find.text('Máy chủ đã xác nhận lưu cài đặt.'), findsOneWidget);
      harness.dashboard.dispose();
    },
  );

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

  test(
    'full settings controller blocks overlapping GET and duplicate writes',
    () async {
      final api = _FakeStrategyApi()
        ..settingsGetCompleter = Completer<StrategySettings>()
        ..settingsSaveCompleter = Completer<String>();
      final dashboard = StrategyDashboardController(
        api: api,
        bearerToken: 'session-a',
      );

      final loading = dashboard.loadStrategySettings();
      await Future<void>.delayed(Duration.zero);
      expect(dashboard.settingsIsLoading, isTrue);
      expect(await dashboard.saveStrategySettings(api.settings), isFalse);
      expect(api.settingsSaveCalls, 0);

      api.settingsGetCompleter!.complete(api.settings);
      await loading;
      final saving = dashboard.saveStrategySettings(api.settings);
      await Future<void>.delayed(Duration.zero);
      await dashboard.loadStrategySettings(force: true);
      expect(await dashboard.saveStrategySettings(api.settings), isFalse);
      expect(api.settingsGetCalls, 1);
      expect(api.settingsSaveCalls, 1);

      api.settingsSaveCompleter!.complete('sequential');
      expect(await saving, isTrue);
      dashboard.dispose();
    },
  );

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
      ..settingsGetCompleter = Completer<StrategySettings>()
      ..settingsSaveCompleter = Completer<String>();
    final harness = await _pumpSettings(tester, api, waitForInitialLoad: false);

    harness.session.switchTo('session-b');
    await tester.pump();
    api.settingsGetCompleter!.complete(api.settings);
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
      find.text('Đăng nhập phiên giao dịch để xem và lưu cài đặt chiến thuật.'),
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

  for (final size in const [Size(320, 800), Size(360, 800), Size(1280, 900)]) {
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
        textScale: size.width == 320 ? 2 : 1,
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
  StrategyApi api, {
  bool waitForInitialLoad = true,
  bool useLauncher = true,
  Size size = const Size(420, 900),
  double textScale = 1,
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child ?? const SizedBox.shrink(),
        ),
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

class _FakeStrategyApi implements StrategyApi, StrategySettingsApi {
  String preference = 'sequential';
  StrategySettings settings = const StrategySettings(
    limitOrderSubmissionMode: 'sequential',
    jevScreeningThresholds: StrategyJevScreeningThresholds.defaults,
  );
  StrategySettings? settingsGetOverride;
  StrategySettings? settingsSaveAcknowledgementOverride;
  StrategySettings? lastSubmittedSettings;
  StrategyApiException? settingsGetError;
  StrategyApiException? saveError;
  Completer<StrategySettings>? settingsGetCompleter;
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
    return Future.value(preference);
  }

  @override
  Future<StrategySettings> getStrategySettings(String token) {
    settingsGetCalls++;
    if (settingsGetError != null) throw settingsGetError!;
    return settingsGetCompleter?.future ??
        Future.value(settingsGetOverride ?? settings);
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
  Future<StrategySettings> saveStrategySettings(
    String token,
    StrategySettings submitted,
  ) async {
    settingsSaveCalls++;
    lastSubmittedSettings = submitted;
    if (saveError != null) throw saveError!;
    final acknowledgedMode = settingsSaveCompleter == null
        ? submitted.limitOrderSubmissionMode
        : await settingsSaveCompleter!.future;
    final acknowledged =
        settingsSaveAcknowledgementOverride ??
        StrategySettings(
          limitOrderSubmissionMode: acknowledgedMode,
          jevScreeningThresholds: submitted.jevScreeningThresholds,
        );
    if (acknowledged == submitted) {
      settings = acknowledged;
      preference = acknowledged.limitOrderSubmissionMode;
    }
    return acknowledged;
  }

  @override
  Future<StrategyRetryCandidates> getRetryCandidates(
    String token,
    String sourceStrategyId,
  ) async => throw UnimplementedError();

  @override
  Future<StrategyRetryPreview> previewRetry(
    String token,
    String sourceStrategyId, {
    required String sourceRevision,
    required List<String> sourceClientOrderIds,
  }) async => throw UnimplementedError();

  @override
  Future<StrategyRetryDraft> createRetryDraft(
    String token,
    String sourceStrategyId, {
    required String sourceRevision,
    required List<String> sourceClientOrderIds,
    required String previewHash,
    required String retryRequestId,
  }) async => throw UnimplementedError();

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

class _LegacySettingsApi implements StrategyApi {
  final delegate = _FakeStrategyApi();

  @override
  Future<String> getLimitOrderSubmissionMode(String token) =>
      delegate.getLimitOrderSubmissionMode(token);

  @override
  Future<String> saveLimitOrderSubmissionMode(String token, String mode) =>
      delegate.saveLimitOrderSubmissionMode(token, mode);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
