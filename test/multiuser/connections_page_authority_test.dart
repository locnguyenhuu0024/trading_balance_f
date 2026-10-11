import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/network/backend_data_client.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/core/session/connection_scope.dart';
import 'package:trading_balance_f/core/session/user_session.dart';
import 'package:trading_balance_f/features/connections/data/multi_user_api_client.dart';
import 'package:trading_balance_f/features/connections/domain/connection_models.dart';
import 'package:trading_balance_f/features/connections/presentation/connections_page.dart';
import 'package:trading_balance_f/features/connections/presentation/providers/multi_user_provider.dart';

void main() {
  testWidgets('captures connection form and critical saved-connection states', (
    tester,
  ) async {
    await tester.runAsync(_loadConnectionQaFonts);
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;

    final emptyKey = const ValueKey('qa-connection-empty');
    final emptyHarness = await _openPage(
      tester,
      _session(id: 'session-empty'),
      connections: const [],
      captureKey: emptyKey,
    );
    await tester.pumpAndSettle();
    expect(find.text('Chưa có kết nối sàn nào được xác minh.'), findsOneWidget);
    await _saveConnectionQaPng(tester, emptyKey, 'connection-empty-360.png');
    await _close(emptyHarness, tester);

    final loadingKey = const ValueKey('qa-connection-loading');
    final loadingGate = Completer<List<ConnectionRecord>>();
    final loadingHarness = await _openPage(
      tester,
      _session(id: 'session-loading'),
      connectionsGate: loadingGate,
      captureKey: loadingKey,
      settle: false,
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await _saveConnectionQaPng(
      tester,
      loadingKey,
      'connection-loading-360.png',
    );
    loadingGate.complete(const []);
    await tester.pumpAndSettle();
    await _close(loadingHarness, tester);

    final errorKey = const ValueKey('qa-connection-error');
    final errorGate = Completer<List<ConnectionRecord>>();
    final errorHarness = await _openPage(
      tester,
      _session(id: 'session-error'),
      connectionsGate: errorGate,
      captureKey: errorKey,
      settle: false,
    );
    await tester.pump();
    errorGate.completeError(StateError('fixture-unavailable'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Không thể tải kết nối.'), findsOneWidget);
    await _saveConnectionQaPng(tester, errorKey, 'connection-error-360.png');
    await _close(errorHarness, tester);

    final longName =
        'Binance treasury account for the long-horizon derivatives desk';
    final longNameKey = const ValueKey('qa-connection-long-name');
    final longNameHarness = await _openPage(
      tester,
      _session(id: 'session-long-name'),
      connections: [_savedConnection(nickname: longName)],
      captureKey: longNameKey,
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(find.text(longName), findsOneWidget);
    await _saveConnectionQaPng(
      tester,
      longNameKey,
      'connection-long-name-360-text-2.0x.png',
    );
    await _close(longNameHarness, tester);

    final createKey = const ValueKey('qa-connection-create-form');
    final createHarness = await _openPage(
      tester,
      _session(id: 'session-create'),
      captureKey: createKey,
    );
    await tester.tap(find.byKey(const Key('add-verified-connection')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Thêm kết nối sàn'),
      ),
      findsOneWidget,
    );
    expect(_field('API key'), findsOneWidget);
    expect(_field('API secret'), findsOneWidget);
    await _saveConnectionQaPng(
      tester,
      createKey,
      'connection-create-form-360.png',
    );
    await _close(createHarness, tester);

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets(
    'standalone root step-up clears entered credentials and closes on owner replacement',
    (tester) async {
      final owner = _session(id: 'session-a', canTrade: false);
      final sessions = UserSessionStore(initialSession: owner);
      final rootNavigator = GlobalKey<NavigatorState>();
      final nestedNavigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [userSessionStoreProvider.overrideWith((ref) => sessions)],
          child: MaterialApp(
            navigatorKey: rootNavigator,
            home: Navigator(
              key: nestedNavigator,
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (context) => Scaffold(
                  body: Center(
                    child: FilledButton(
                      key: const Key('open-standalone-step-up'),
                      onPressed: () => unawaited(
                        showConnectionStepUpDialog(
                          context,
                          owner: sessions.current!,
                        ),
                      ),
                      child: const Text('Step-up'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open-standalone-step-up')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Xác minh lại'), findsOneWidget);
      expect(rootNavigator.currentState!.canPop(), isTrue);
      expect(nestedNavigator.currentState!.canPop(), isFalse);

      final password = tester
          .widget<TextFormField>(find.byType(TextFormField).at(0))
          .controller!;
      final totp = tester
          .widget<TextFormField>(find.byType(TextFormField).at(1))
          .controller!;
      await tester.enterText(find.byType(TextFormField).at(0), 'secret-a');
      await tester.enterText(find.byType(TextFormField).at(1), '123456');
      await tester.pump();
      expect(password.text, 'secret-a');
      expect(totp.text, '123456');

      sessions.update(_session(id: 'session-b', userId: 'user-b'));
      await tester.pumpAndSettle();

      expect(password.text, isEmpty);
      expect(totp.text, isEmpty);
      expect(find.text('Xác minh lại'), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(rootNavigator.currentState!.canPop(), isFalse);
      expect(nestedNavigator.currentState!.canPop(), isFalse);
      sessions.dispose();
    },
  );

  testWidgets('pushed connection snapshot is hidden after owner logout', (
    tester,
  ) async {
    final harness = await _openPage(tester, _session(id: 'session-a'));
    await tester.pumpAndSettle();
    expect(find.text('A account label'), findsOneWidget);

    harness.sessions.update(null);
    await tester.pumpAndSettle();

    expect(find.text('A account label'), findsNothing);
    expect(find.textContaining('Phiên đã thay đổi'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('add-verified-connection')),
          )
          .onPressed,
      isNull,
    );
    await _close(harness, tester);
  });

  testWidgets('idle secret form closes and clears on session replacement', (
    tester,
  ) async {
    final harness = await _openPage(tester, _session(id: 'session-a'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-verified-connection')));
    await tester.pumpAndSettle();
    final apiKey = _field('API key');
    await tester.enterText(apiKey, 'fixture-api-key-A');
    await tester.enterText(_field('API secret'), 'fixture-api-secret-A');
    await tester.pump();

    harness.sessions.update(_session(id: 'session-b', userId: 'user-b'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(_field('API key'), findsNothing);
    expect(find.text('A account label'), findsNothing);
    expect(harness.api.createCalls, 0);
    await _close(harness, tester);
  });

  testWidgets('pending step-up cannot submit after another owner replaces A', (
    tester,
  ) async {
    final stepUp = Completer<DateTime>();
    final harness = await _openPage(
      tester,
      _session(id: 'session-a', canTrade: false),
      stepUpGate: stepUp,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-verified-connection')));
    await tester.pumpAndSettle();
    await tester.enterText(_field('API key'), 'fixture-api-key-A');
    await tester.enterText(_field('API secret'), 'fixture-api-secret-A');
    await tester.enterText(_field('Passphrase'), 'fixture-passphrase-A');
    await tester.pump();
    expect(
      tester.widget<TextField>(_field('API key')).controller!.text,
      'fixture-api-key-A',
    );
    expect(
      tester.widget<TextField>(_field('API secret')).controller!.text,
      'fixture-api-secret-A',
    );
    await _submit(tester);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('Xác minh lại'), findsOneWidget);
    await tester.enterText(_field('Mật khẩu'), 'fixture-password-A');
    await tester.enterText(_field('Mã TOTP'), '123456');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Xác minh'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(harness.api.stepUpCalls, 1);
    expect(harness.api.stepUpOwner, 'session-a');
    harness.sessions.update(_session(id: 'session-b', userId: 'user-b'));
    await tester.pumpAndSettle();
    stepUp.complete(DateTime.now().add(const Duration(minutes: 4)));
    await tester.pumpAndSettle();

    expect(harness.api.createCalls, 0);
    expect(_field('API key'), findsNothing);
    expect(find.text('A account label'), findsNothing);
    expect(harness.sessions.current?.sessionId, 'session-b');
    await _close(harness, tester);
  });

  testWidgets('legacy removal consent is fenced by its captured owner', (
    tester,
  ) async {
    final harness = await _openPage(
      tester,
      _session(id: 'session-a', canTrade: true),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-verified-connection')));
    await tester.pumpAndSettle();
    await tester.enterText(_field('API key'), 'fixture-api-key-A');
    await tester.enterText(_field('API secret'), 'fixture-api-secret-A');
    await tester.enterText(_field('Passphrase'), 'fixture-passphrase-A');
    await tester.pump();
    await tester.ensureVisible(find.textContaining('Sau khi xác minh'));
    await tester.tap(find.textContaining('Sau khi xác minh'));
    await tester.pump();
    await _submit(tester);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(harness.api.createCalls, 1);
    expect(find.text('Xóa khóa đã lưu từ phiên bản cũ?'), findsOneWidget);

    harness.sessions.update(_session(id: 'session-b', userId: 'user-b'));
    await tester.pumpAndSettle();

    expect(find.text('Xóa khóa đã lưu từ phiên bản cũ?'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(harness.storage.clearOldCalls, 0);
    expect(harness.controller.currentSession?.sessionId, 'session-b');
    await _close(harness, tester);
  });

  testWidgets('barrier dismissal during create never touches disposed fields', (
    tester,
  ) async {
    final create = Completer<ConnectionRecord>();
    final harness = await _openPage(
      tester,
      _session(id: 'session-a', canTrade: true),
      createGate: create,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-verified-connection')));
    await tester.pumpAndSettle();
    await tester.enterText(_field('API key'), 'fixture-api-key-A');
    await tester.enterText(_field('API secret'), 'fixture-api-secret-A');
    await tester.enterText(_field('Passphrase'), 'fixture-passphrase-A');
    await tester.pump();
    await _submit(tester);
    await tester.pump();
    expect(harness.api.createCalls, 1);

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    create.complete(_createdConnection());
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await _close(harness, tester);
  });
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
  description: 'TextField $label',
);

Future<void> _submit(WidgetTester tester) async {
  final submit = find.byKey(const Key('verify-connection-submit'));
  await tester.ensureVisible(submit);
  expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
  await tester.tap(submit);
  await tester.pump();
}

Future<_Harness> _openPage(
  WidgetTester tester,
  UserSession owner, {
  Completer<DateTime>? stepUpGate,
  Completer<ConnectionRecord>? createGate,
  Completer<List<ConnectionRecord>>? connectionsGate,
  List<ConnectionRecord>? connections,
  Key? captureKey,
  double textScale = 1,
  bool settle = true,
}) async {
  final sessions = UserSessionStore(initialSession: owner);
  final scopes = ConnectionScopeStore();
  final selected = SelectedConnectionStore();
  final pending = PendingOperationStore();
  final storage = _TestStorage();
  final pageApi = _PageApi(
    sessions: sessions,
    scopes: scopes,
    stepUpGate: stepUpGate,
    createGate: createGate,
    connectionsGate: connectionsGate,
    connections: connections,
  );
  final controller = MultiUserController(
    api: pageApi,
    sessions: sessions,
    scopes: scopes,
    selected: selected,
    pending: pending,
    storage: storage,
    isWeb: true,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userSessionStoreProvider.overrideWith((ref) => sessions),
        connectionScopeStoreProvider.overrideWith((ref) => scopes),
        selectedConnectionProvider.overrideWith((ref) => selected),
        pendingOperationStoreProvider.overrideWith((ref) => pending),
        multiUserControllerProvider.overrideWith((ref) => controller),
      ],
      child: MaterialApp(
        builder: (context, child) {
          final app = child ?? const SizedBox.shrink();
          return MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: captureKey == null
                ? app
                : RepaintBoundary(key: captureKey, child: app),
          );
        },
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('open-connections-route'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ConnectionsPage(),
                  ),
                ),
                child: const Text('Open connections'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-connections-route')));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
  return _Harness(
    sessions: sessions,
    scopes: scopes,
    selected: selected,
    pending: pending,
    storage: storage,
    api: pageApi,
    controller: controller,
  );
}

Future<void> _close(_Harness harness, WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  harness.controller.dispose();
  harness.sessions.dispose();
  harness.scopes.dispose();
  harness.selected.dispose();
  harness.pending.dispose();
}

class _Harness {
  const _Harness({
    required this.sessions,
    required this.scopes,
    required this.selected,
    required this.pending,
    required this.storage,
    required this.api,
    required this.controller,
  });

  final UserSessionStore sessions;
  final ConnectionScopeStore scopes;
  final SelectedConnectionStore selected;
  final PendingOperationStore pending;
  final _TestStorage storage;
  final _PageApi api;
  final MultiUserController controller;
}

class _PageApi extends MultiUserApiClient {
  _PageApi({
    required UserSessionStore sessions,
    required ConnectionScopeStore scopes,
    this.stepUpGate,
    this.createGate,
    this.connectionsGate,
    this.connections,
  }) : super(
         backend: BackendDataClient(
           dio: Dio()..httpClientAdapter = _NoNetworkAdapter(),
           baseUrl: 'https://data.example/gateway',
           isWeb: true,
         ),
         sessions: sessions,
         scopes: scopes,
         isWeb: true,
       );

  final Completer<DateTime>? stepUpGate;
  final Completer<ConnectionRecord>? createGate;
  final Completer<List<ConnectionRecord>>? connectionsGate;
  final List<ConnectionRecord>? connections;
  int stepUpCalls = 0;
  String? stepUpOwner;
  int createCalls = 0;

  @override
  Future<List<ConnectionRecord>> getConnections({
    CancelToken? cancelToken,
  }) async {
    if (connectionsGate != null) return connectionsGate!.future;
    return connections ?? [_savedConnection(nickname: 'A account label')];
  }

  @override
  Future<DateTime> stepUp({required String password, required String totp}) {
    stepUpCalls++;
    stepUpOwner = sessions.current?.sessionId;
    return stepUpGate?.future ??
        Future.value(DateTime.now().add(const Duration(minutes: 4)));
  }

  @override
  Future<ConnectionRecord> createConnection({
    required String exchange,
    required String environment,
    required String region,
    required String nickname,
    required String apiKey,
    required String apiSecret,
    String? passphrase,
  }) {
    createCalls++;
    return createGate?.future ?? Future.value(_createdConnection());
  }
}

UserSession _session({
  required String id,
  String userId = 'user-a',
  bool canTrade = false,
}) => UserSession(
  userId: userId,
  username: userId,
  sessionId: id,
  mode: 'ordinary',
  expiresAt: DateTime.now().add(const Duration(hours: 1)),
  stepUpUntil: canTrade ? DateTime.now().add(const Duration(minutes: 4)) : null,
  bearerToken: 'fixture-bearer-$id',
);

ConnectionRecord _savedConnection({required String nickname}) =>
    ConnectionRecord(
      connectionId: 'conn-a-0001',
      exchange: 'OKX',
      environment: 'demo',
      region: 'global',
      capabilities: const ['trade'],
      nickname: nickname,
      status: 'ACTIVE',
      credentialVersion: 1,
      permissionVersion: 1,
    );

ConnectionRecord _createdConnection() => const ConnectionRecord(
  connectionId: 'conn-b-0001',
  exchange: 'OKX',
  environment: 'demo',
  region: 'global',
  capabilities: ['trade'],
  nickname: 'Created connection',
  status: 'ACTIVE',
  credentialVersion: 1,
  permissionVersion: 1,
);

class _TestStorage extends SecureStorageHelper {
  _TestStorage() : super(const FlutterSecureStorage());

  int clearOldCalls = 0;

  @override
  Future<void> clearV2SessionBearer() async {}

  @override
  Future<void> clearOkxCredentials() async {
    clearOldCalls++;
  }
}

class _NoNetworkAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => throw StateError('Unexpected network access in this fixture.');

  @override
  void close({bool force = false}) {}
}

Future<void> _loadConnectionQaFonts() async {
  var directory = File(Platform.resolvedExecutable).absolute.parent;
  while (directory.path != directory.parent.path) {
    final candidate = Directory(
      '${directory.path}${Platform.pathSeparator}bin${Platform.pathSeparator}'
      'cache${Platform.pathSeparator}artifacts${Platform.pathSeparator}'
      'material_fonts',
    );
    if (await candidate.exists()) {
      for (final font in {
        'Roboto': 'roboto-regular.ttf',
        'MaterialIcons': 'materialicons-regular.otf',
      }.entries) {
        final fontFile = File(
          '${candidate.path}${Platform.pathSeparator}${font.value}',
        );
        if (!await fontFile.exists()) continue;
        final bytes = await fontFile.readAsBytes();
        final loader = FontLoader(font.key)
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
      }
      return;
    }
    directory = directory.parent;
  }
  throw StateError('Flutter SDK material fonts not found for visual QA.');
}

Future<void> _saveConnectionQaPng(
  WidgetTester tester,
  Key boundaryKey,
  String filename,
) async {
  final boundary = tester.renderObject(find.byKey(boundaryKey));
  expect(boundary, isA<RenderRepaintBoundary>());
  final image = await tester.runAsync(
    () => (boundary as RenderRepaintBoundary).toImage(pixelRatio: 1),
  );
  expect(image, isNotNull);
  final captured = image!;
  final data = await tester.runAsync(
    () => captured.toByteData(format: ui.ImageByteFormat.png),
  );
  captured.dispose();
  expect(data, isNotNull);
  final bytes = data!.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );
  await tester.runAsync(() async {
    const directory = '/private/tmp/t114-resume-qa';
    await Directory(directory).create(recursive: true);
    await File('$directory/$filename').writeAsBytes(bytes, flush: true);
  });
}
