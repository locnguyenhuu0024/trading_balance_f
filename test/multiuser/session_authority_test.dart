import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
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
import 'package:trading_balance_f/features/connections/presentation/multi_user_entry_screen.dart';
import 'package:trading_balance_f/features/connections/presentation/providers/multi_user_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('restricted enrollment secrets disappear on session expiry', (
    tester,
  ) async {
    final restricted = _session(
      id: 'restricted-a',
      mode: 'enrollment',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    final sessions = UserSessionStore(initialSession: restricted);
    final scopes = ConnectionScopeStore();
    final api = _FakeApi(sessions: sessions, scopes: scopes)
      ..bootstrap = AuthBootstrap(
        session: restricted,
        totpSecret: 'fixture-totp-secret',
        recoveryCodes: const ['fixture-recovery-code'],
      );
    final controller = MultiUserController(
      api: api,
      sessions: sessions,
      scopes: scopes,
      selected: SelectedConnectionStore(),
      pending: PendingOperationStore(),
      storage: _MemoryStorage(),
      isWeb: true,
    )..enrollment = api.bootstrap;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userSessionStoreProvider.overrideWith((ref) => sessions),
          multiUserControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: MultiUserEntryScreen()),
      ),
    );
    await tester.pump();
    expect(find.textContaining('fixture-totp-secret'), findsOneWidget);
    expect(find.text('fixture-recovery-code'), findsOneWidget);

    sessions.update(
      _session(
        id: 'restricted-a',
        mode: 'enrollment',
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      ),
    );
    await tester.pump();
    expect(sessions.current, isNull);
    expect(controller.enrollment, isNull);
    expect(find.textContaining('fixture-totp-secret'), findsNothing);
    expect(find.text('fixture-recovery-code'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    sessions.dispose();
    scopes.dispose();
  });

  testWidgets('login and enrollment keyboard flow validates and gates MFA', (
    tester,
  ) async {
    final restricted = _session(
      id: 'restricted-login',
      mode: 'enrollment',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    final sessions = UserSessionStore();
    final scopes = ConnectionScopeStore();
    final api = _FakeApi(sessions: sessions, scopes: scopes)
      ..loginBootstrap = AuthBootstrap(session: restricted)
      ..enrollmentBootstrap = AuthBootstrap(
        session: restricted,
        totpSecret: 'fixture-enrollment-secret',
        recoveryCodes: const ['fixture-recovery-one'],
      );
    final controller = _controller(api, sessions, scopes);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userSessionStoreProvider.overrideWith((ref) => sessions),
          multiUserControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: MultiUserEntryScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Đăng nhập an toàn'), findsOneWidget);

    await tester.tap(find.byKey(const Key('mfa-proof')));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(api.loginCalls, 0);
    expect(
      FocusManager.instance.primaryFocus,
      same(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const Key('username')),
                matching: find.byType(EditableText),
              ),
            )
            .focusNode,
      ),
    );

    await tester.enterText(find.byKey(const Key('username')), 'alice');
    await tester.enterText(find.byKey(const Key('password')), 'secret');
    await tester.enterText(find.byKey(const Key('mfa-proof')), '123456');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(api.loginCalls, 1);
    expect(find.textContaining('fixture-enrollment-secret'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('enrollment-totp')), '123');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(api.completeEnrollmentCalls, 0);
    expect(find.text('Nhập mã TOTP gồm 6 chữ số.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('enrollment-totp')), '123456');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(api.completeEnrollmentCalls, 0);
    expect(find.text('Hãy xác nhận đã lưu mã khôi phục.'), findsOneWidget);
    final recoveryFocus = tester.widget<Focus>(
      find
          .ancestor(
            of: find.byKey(const Key('recovery-codes-saved-focus')),
            matching: find.byType(Focus),
          )
          .first,
    );
    expect(FocusManager.instance.primaryFocus, same(recoveryFocus.focusNode));

    await tester.ensureVisible(
      find.byKey(const Key('recovery-codes-saved-focus')),
    );
    await tester.tap(find.byKey(const Key('recovery-codes-saved-focus')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('enrollment-totp')));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(api.completeEnrollmentCalls, 1);
    expect(sessions.current, isNull);
    expect(find.text('Đăng nhập an toàn'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    sessions.dispose();
    scopes.dispose();
  });

  testWidgets(
    'malformed nonempty TOTP focuses the proof field and sends no login',
    (tester) async {
      final sessions = UserSessionStore();
      final scopes = ConnectionScopeStore();
      final ordinary = _session(id: 'valid-login');
      final api = _FakeApi(sessions: sessions, scopes: scopes)
        ..loginBootstrap = AuthBootstrap(session: ordinary);
      final controller = _controller(api, sessions, scopes);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userSessionStoreProvider.overrideWith((ref) => sessions),
            multiUserControllerProvider.overrideWith((ref) => controller),
          ],
          child: const MaterialApp(home: MultiUserEntryScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('username')), 'alice');
      await tester.enterText(find.byKey(const Key('password')), 'secret');
      await tester.enterText(find.byKey(const Key('mfa-proof')), '12x');
      final usernameFocus = tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const Key('username')),
              matching: find.byType(EditableText),
            ),
          )
          .focusNode;
      usernameFocus.requestFocus();
      await tester.pump();
      await tester.tap(find.byKey(const Key('server-auth-submit')));
      await tester.pump();

      final proofFocus = tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const Key('mfa-proof')),
              matching: find.byType(EditableText),
            ),
          )
          .focusNode;
      expect(api.loginCalls, 0);
      expect(FocusManager.instance.primaryFocus, same(proofFocus));
      expect(find.text('Nhập mã TOTP gồm 6 chữ số.'), findsOneWidget);
      expect(sessions.current, isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      sessions.dispose();
      scopes.dispose();
    },
  );

  testWidgets('activation Enter focuses the missing invite and sends nothing', (
    tester,
  ) async {
    final sessions = UserSessionStore();
    final scopes = ConnectionScopeStore();
    final api = _FakeApi(sessions: sessions, scopes: scopes);
    final controller = _controller(api, sessions, scopes);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userSessionStoreProvider.overrideWith((ref) => sessions),
          multiUserControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: MultiUserEntryScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Có mã mời? Kích hoạt tài khoản'));
    await tester.tap(find.text('Có mã mời? Kích hoạt tài khoản'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('username')), 'alice');
    await tester.enterText(find.byKey(const Key('password')), 'secret');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(api.activationCalls, 0);
    expect(
      FocusManager.instance.primaryFocus,
      same(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const Key('invite-token')),
                matching: find.byType(EditableText),
              ),
            )
            .focusNode,
      ),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    sessions.dispose();
    scopes.dispose();
  });

  testWidgets('renders auth loading, error, login and enrollment critical UI', (
    tester,
  ) async {
    await tester.runAsync(_loadQaFonts);
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    final restricted = _session(
      id: 'restricted-render',
      mode: 'enrollment',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    final sessions = UserSessionStore();
    final scopes = ConnectionScopeStore();
    final api = _FakeApi(sessions: sessions, scopes: scopes);
    final controller = _controller(api, sessions, scopes);
    const boundaryKey = ValueKey('qa-auth-boundary');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userSessionStoreProvider.overrideWith((ref) => sessions),
          multiUserControllerProvider.overrideWith((ref) => controller),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: RepaintBoundary(
              key: boundaryKey,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
          home: const MultiUserEntryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Đăng nhập an toàn'), findsOneWidget);
    await _saveAuthPng(
      tester,
      boundaryKey,
      'auth-login-360-light-text-2.0x.png',
    );

    final login = Completer<AuthBootstrap>();
    api.loginResult = login;
    await tester.enterText(find.byKey(const Key('username')), 'alice');
    await tester.enterText(find.byKey(const Key('password')), 'fixture-pass');
    await tester.enterText(find.byKey(const Key('mfa-proof')), '123456');
    await tester.ensureVisible(find.byKey(const Key('server-auth-submit')));
    await tester.tap(find.byKey(const Key('server-auth-submit')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.isBusy, isTrue);
    await _saveAuthPng(
      tester,
      boundaryKey,
      'auth-loading-360-light-text-2.0x.png',
    );

    login.completeError(
      const BackendDataException(
        code: 'authentication_required',
        message: 'Mã xác thực không đúng.',
        statusCode: 401,
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.errorMessage, isNotNull);
    await _saveAuthPng(
      tester,
      boundaryKey,
      'auth-error-360-light-text-2.0x.png',
    );

    api.loginResult = null;
    api.loginBootstrap = AuthBootstrap(session: restricted);
    api.enrollmentBootstrap = AuthBootstrap(
      session: restricted,
      totpSecret: 'fixture-render-secret',
      recoveryCodes: const ['fixture-render-recovery'],
    );
    await tester.enterText(find.byKey(const Key('password')), 'fixture-pass');
    await tester.enterText(find.byKey(const Key('mfa-proof')), '123456');
    await tester.ensureVisible(find.byKey(const Key('server-auth-submit')));
    await tester.tap(find.byKey(const Key('server-auth-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('fixture-render-secret'), findsOneWidget);
    await _saveAuthPng(
      tester,
      boundaryKey,
      'auth-enrollment-360-light-text-2.0x.png',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    sessions.dispose();
    scopes.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  test(
    'late login response cannot replace externally changed authority',
    () async {
      final sessions = UserSessionStore();
      final scopes = ConnectionScopeStore();
      final api = _FakeApi(sessions: sessions, scopes: scopes);
      final login = Completer<AuthBootstrap>();
      api.loginResult = login;
      final controller = MultiUserController(
        api: api,
        sessions: sessions,
        scopes: scopes,
        selected: SelectedConnectionStore(),
        pending: PendingOperationStore(),
        storage: _MemoryStorage(),
        isWeb: true,
      );

      final request = controller.login(
        username: 'alice',
        password: 'fixture-password',
        proof: 'fixture-proof',
        recoveryCode: false,
      );
      final replacement = _session(id: 'session-b', userId: 'user-b');
      sessions.update(replacement);
      login.complete(
        AuthBootstrap(
          session: _session(id: 'session-a', userId: 'user-a'),
        ),
      );
      await request;

      expect(sessions.current?.sessionId, 'session-b');
      expect(controller.enrollment, isNull);
      expect(controller.errorMessage, isNull);
      controller.dispose();
      sessions.dispose();
      scopes.dispose();
    },
  );

  test(
    'delayed restore cannot leave the login gate stuck after logout',
    () async {
      final sessions = UserSessionStore();
      final scopes = ConnectionScopeStore();
      final api = _FakeApi(sessions: sessions, scopes: scopes);
      final restore = Completer<AuthBootstrap>();
      api.restoreResult = restore;
      final controller = _controller(api, sessions, scopes);

      final pendingRestore = controller.restore();
      expect(controller.isRestoring, isTrue);
      await controller.logout();
      expect(controller.isRestoring, isFalse);

      restore.complete(AuthBootstrap(session: _session(id: 'late-a')));
      await pendingRestore;
      expect(controller.isRestoring, isFalse);
      expect(sessions.current, isNull);
      expect(controller.statusMessage, contains('đăng xuất'));
      expect(api.logoutCalls, 0);

      controller.dispose();
      sessions.dispose();
      scopes.dispose();
    },
  );

  test(
    'successful B login clears a delayed restore spinner and rejects A',
    () async {
      final sessions = UserSessionStore();
      final scopes = ConnectionScopeStore();
      final api = _FakeApi(sessions: sessions, scopes: scopes);
      final restore = Completer<AuthBootstrap>();
      final login = Completer<AuthBootstrap>();
      api.restoreResult = restore;
      api.loginResult = login;
      final controller = _controller(api, sessions, scopes);

      final pendingRestore = controller.restore();
      final pendingLogin = controller.login(
        username: 'user-b',
        password: 'fixture-password',
        proof: 'fixture-totp',
        recoveryCode: false,
      );
      login.complete(
        AuthBootstrap(
          session: _session(id: 'session-b', userId: 'user-b'),
        ),
      );
      await pendingLogin;
      expect(controller.isRestoring, isFalse);
      expect(sessions.current?.sessionId, 'session-b');

      restore.complete(AuthBootstrap(session: _session(id: 'session-a')));
      await pendingRestore;
      expect(controller.isRestoring, isFalse);
      expect(sessions.current?.sessionId, 'session-b');

      controller.dispose();
      sessions.dispose();
      scopes.dispose();
    },
  );

  test(
    'in-flight restricted enrollment is discarded after owner replacement',
    () async {
      final restricted = _session(
        id: 'restricted-a',
        mode: 'enrollment',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      final sessions = UserSessionStore();
      final scopes = ConnectionScopeStore();
      final api = _FakeApi(sessions: sessions, scopes: scopes);
      final login = Completer<AuthBootstrap>();
      final enrollment = Completer<AuthBootstrap>();
      api.loginResult = login;
      api.enrollmentResult = enrollment;
      final controller = _controller(api, sessions, scopes);
      final pendingLogin = controller.login(
        username: 'alice',
        password: 'fixture-password',
        proof: 'fixture-totp',
        recoveryCode: false,
      );
      login.complete(AuthBootstrap(session: restricted));
      await Future<void>.delayed(Duration.zero);
      expect(sessions.current?.sessionId, 'restricted-a');

      sessions.update(_session(id: 'session-b', userId: 'user-b'));
      enrollment.complete(
        AuthBootstrap(
          session: restricted,
          totpSecret: 'stale-owner-secret',
          recoveryCodes: const ['stale-owner-recovery'],
        ),
      );
      await pendingLogin;
      expect(controller.activeEnrollment, isNull);
      expect(controller.enrollment, isNull);
      expect(sessions.current?.sessionId, 'session-b');

      controller.dispose();
      sessions.dispose();
      scopes.dispose();
    },
  );

  test('Riverpod owns controller disposal exactly once', () {
    final sessions = UserSessionStore();
    final scopes = ConnectionScopeStore();
    final api = _FakeApi(sessions: sessions, scopes: scopes);
    final controller = _TrackingController(
      api: api,
      sessions: sessions,
      scopes: scopes,
      selected: SelectedConnectionStore(),
      pending: PendingOperationStore(),
      storage: _MemoryStorage(),
      isWeb: true,
    );
    final container = ProviderContainer(
      overrides: [
        multiUserControllerProvider.overrideWith((ref) => controller),
      ],
    );

    expect(container.read(multiUserControllerProvider), same(controller));
    expect(container.read(multiUserControllerProvider), same(controller));
    container.dispose();

    expect(controller.disposeCalls, 1);
    sessions.dispose();
    scopes.dispose();
  });

  test(
    'server logout sends the bearer and reports an unconfirmed failure',
    () async {
      final owner = _session(id: 'session-a');
      final sessions = UserSessionStore(initialSession: owner);
      final scopes = ConnectionScopeStore();
      final adapter = _FailingLogoutAdapter();
      final api = MultiUserApiClient(
        backend: BackendDataClient(
          dio: Dio()..httpClientAdapter = adapter,
          baseUrl: 'https://data.example/gateway',
          isWeb: false,
        ),
        sessions: sessions,
        scopes: scopes,
        isWeb: false,
      );
      final controller = MultiUserController(
        api: api,
        sessions: sessions,
        scopes: scopes,
        selected: SelectedConnectionStore(),
        pending: PendingOperationStore(),
        storage: _MemoryStorage(),
        isWeb: false,
      );

      await controller.logout();

      expect(adapter.method, 'POST');
      expect(adapter.path, endsWith('/v2/logout'));
      expect(adapter.authorization, 'Bearer fixture-session-a');
      expect(sessions.current, isNull);
      expect(
        controller.statusMessage,
        'Đã xóa phiên trên thiết bị; máy chủ chưa xác nhận đăng xuất.',
      );
      controller.dispose();
      sessions.dispose();
      scopes.dispose();
    },
  );

  test('V2 bearer clear queues before and cannot erase a later save', () async {
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    final values = <String, String>{};
    final deleteGate = Completer<void>();
    var blockDelete = false;
    var deleteStarted = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final arguments = Map<Object?, Object?>.from(call.arguments as Map);
      final key = arguments['key']! as String;
      switch (call.method) {
        case 'write':
          values[key] = arguments['value']! as String;
          return null;
        case 'read':
          return values[key];
        case 'delete':
          deleteStarted = true;
          if (blockDelete) await deleteGate.future;
          values.remove(key);
          return null;
        default:
          fail('Unexpected secure-storage call ${call.method}.');
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final storage = SecureStorageHelper(const FlutterSecureStorage());
    await storage.saveV2SessionBearer('bearer-a');
    blockDelete = true;
    final staleClear = storage.clearV2SessionBearer();
    await Future<void>.delayed(Duration.zero);
    expect(deleteStarted, isTrue);
    final saveB = storage.saveV2SessionBearer('bearer-b');
    await Future<void>.delayed(Duration.zero);
    expect(values['TRADE_V2_SESSION_BEARER'], 'bearer-a');

    deleteGate.complete();
    await staleClear;
    await saveB;
    expect(values['TRADE_V2_SESSION_BEARER'], 'bearer-b');
  });

  test(
    'web logout response completes before B login can send cookies',
    () async {
      final owner = _session(
        id: 'session-a',
        csrfToken: 'csrf-a',
      ).withStepUp(DateTime.now().add(const Duration(minutes: 5)));
      final sessions = UserSessionStore(initialSession: owner);
      final adapter = _CookieJarAdapter()..cookies['session'] = 'a';
      adapter.cookies['csrf'] = 'csrf-a';
      final backend = _webBackend(adapter);
      final logout = backend.requestV2(
        'POST',
        '/v2/logout',
        sessionStore: sessions,
        allowSessionInvalidation: true,
      );
      await adapter.firstRequestStarted.future;

      sessions.update(null);
      final loginB = _webLogin(backend, sessions, 'user-b');
      await Future<void>.delayed(Duration.zero);
      expect(adapter.paths, ['/v2/logout']);
      adapter.releaseFirstResponse();
      await logout;
      await loginB;

      expect(adapter.paths, ['/v2/logout', '/v2/login']);
      expect(adapter.requestCookies.last, isEmpty);
      expect(adapter.cookies, {'session': 'user-b', 'csrf': 'csrf-user-b'});
      sessions.dispose();
    },
  );

  test(
    'web restore response completes before B login cookie mutation',
    () async {
      final sessions = UserSessionStore();
      final adapter = _CookieJarAdapter();
      final backend = _webBackend(adapter);
      final restore = backend.requestV2(
        'GET',
        '/v2/session',
        sessionStore: sessions,
      );
      await adapter.firstRequestStarted.future;
      final loginB = _webLogin(backend, sessions, 'user-b');
      await Future<void>.delayed(Duration.zero);
      expect(adapter.paths, ['/v2/session']);
      adapter.releaseFirstResponse();
      await restore;
      await loginB;

      expect(adapter.paths, ['/v2/session', '/v2/login']);
      expect(adapter.requestCookies.last, {'csrf': 'csrf-restored-a'});
      expect(adapter.cookies, {'session': 'user-b', 'csrf': 'csrf-user-b'});
      sessions.dispose();
    },
  );

  test(
    'web late A login response cannot overwrite a later B login cookie',
    () async {
      final sessions = UserSessionStore();
      final adapter = _CookieJarAdapter();
      final backend = _webBackend(adapter);
      final loginA = _webLogin(backend, sessions, 'user-a');
      await adapter.firstRequestStarted.future;
      final loginB = _webLogin(backend, sessions, 'user-b');
      await Future<void>.delayed(Duration.zero);
      expect(adapter.paths, ['/v2/login']);
      adapter.releaseFirstResponse();
      await loginA;
      await loginB;

      expect(adapter.paths, ['/v2/login', '/v2/login']);
      expect(adapter.cookies, {'session': 'user-b', 'csrf': 'csrf-user-b'});
      sessions.dispose();
    },
  );
}

BackendDataClient _webBackend(_CookieJarAdapter adapter) => BackendDataClient(
  dio: Dio()..httpClientAdapter = adapter,
  baseUrl: 'https://data.example/gateway',
  isWeb: true,
);

Future<Response<dynamic>> _webLogin(
  BackendDataClient backend,
  UserSessionStore sessions,
  String username,
) => backend.requestV2(
  'POST',
  '/v2/login',
  body: {'username': username, 'password': 'fixture', 'totp': '123456'},
  sessionStore: sessions,
);

class _TrackingController extends MultiUserController {
  _TrackingController({
    required super.api,
    required super.sessions,
    required super.scopes,
    required super.selected,
    required super.pending,
    required super.storage,
    required super.isWeb,
  });

  int disposeCalls = 0;

  @override
  void dispose() {
    disposeCalls++;
    super.dispose();
  }
}

MultiUserController _controller(
  _FakeApi api,
  UserSessionStore sessions,
  ConnectionScopeStore scopes,
) => MultiUserController(
  api: api,
  sessions: sessions,
  scopes: scopes,
  selected: SelectedConnectionStore(),
  pending: PendingOperationStore(),
  storage: _MemoryStorage(),
  isWeb: true,
);

Future<void> _saveAuthPng(
  WidgetTester tester,
  Key boundaryKey,
  String filename,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(boundaryKey),
  );
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
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

Future<void> _loadQaFonts() async {
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

UserSession _session({
  required String id,
  String userId = 'user-a',
  String mode = 'ordinary',
  DateTime? expiresAt,
  String? csrfToken,
}) => UserSession(
  userId: userId,
  username: userId,
  sessionId: id,
  mode: mode,
  expiresAt: expiresAt ?? DateTime.now().add(const Duration(hours: 1)),
  bearerToken: 'fixture-$id',
  csrfToken: csrfToken,
);

class _MemoryStorage extends SecureStorageHelper {
  _MemoryStorage() : super(const FlutterSecureStorage());

  String? bearer;

  @override
  Future<String?> getV2SessionBearer() async => bearer;

  @override
  Future<void> saveV2SessionBearer(String token) async {
    bearer = token;
  }

  @override
  Future<void> clearV2SessionBearer() async {
    bearer = null;
  }
}

class _FakeApi extends MultiUserApiClient {
  _FakeApi({
    required UserSessionStore sessions,
    required ConnectionScopeStore scopes,
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

  AuthBootstrap? bootstrap;
  AuthBootstrap? loginBootstrap;
  AuthBootstrap? enrollmentBootstrap;
  Completer<AuthBootstrap>? loginResult;
  Completer<AuthBootstrap>? restoreResult;
  Completer<AuthBootstrap>? enrollmentResult;
  int logoutCalls = 0;
  int loginCalls = 0;
  int activationCalls = 0;
  int completeEnrollmentCalls = 0;

  @override
  Future<AuthBootstrap> restoreSession({String? nativeBearer}) {
    if (restoreResult != null) return restoreResult!.future;
    if (bootstrap != null) return Future.value(bootstrap!);
    return Future.error(
      const BackendDataException(
        code: 'authentication_required',
        message: 'Vui lòng đăng nhập để tiếp tục.',
        statusCode: 401,
      ),
    );
  }

  @override
  Future<AuthBootstrap> login({
    required String username,
    required String password,
    required String mfaProof,
    required bool recoveryCode,
  }) {
    loginCalls++;
    return loginResult?.future ?? Future.value(loginBootstrap ?? bootstrap!);
  }

  @override
  Future<AuthBootstrap> activateInvite({
    required String inviteToken,
    required String username,
    required String password,
  }) async {
    activationCalls++;
    return loginBootstrap ?? bootstrap!;
  }

  @override
  Future<AuthBootstrap> startMfaEnrollment() =>
      enrollmentResult?.future ??
      Future.value(enrollmentBootstrap ?? bootstrap!);

  @override
  Future<void> completeMfaEnrollment(String totp) async {
    completeEnrollmentCalls++;
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
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

class _FailingLogoutAdapter implements HttpClientAdapter {
  String? method;
  String? path;
  String? authorization;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    method = options.method;
    path = options.uri.path;
    authorization = options.headers['Authorization'] as String?;
    return ResponseBody.fromString(
      '{"error":"synthetic service failure"}',
      503,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _CookieJarAdapter implements HttpClientAdapter {
  _CookieJarAdapter() {
    cookies = {};
  }

  final Completer<void> firstRequestStarted = Completer<void>();
  final Completer<void> _firstResponseGate = Completer<void>();
  final List<String> paths = [];
  final List<Map<String, String>> requestCookies = [];
  late final Map<String, String> cookies;

  void releaseFirstResponse() {
    if (!_firstResponseGate.isCompleted) _firstResponseGate.complete();
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path.replaceFirst('/gateway', '');
    paths.add(path);
    requestCookies.add(Map<String, String>.from(cookies));
    options.headers['Cookie'] = cookies.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
    if (paths.length == 1) {
      firstRequestStarted.complete();
      await _firstResponseGate.future;
    }

    final List<String> setCookies;
    if (path == '/v2/logout') {
      setCookies = const [
        'session=; Max-Age=0; Path=/',
        'csrf=; Max-Age=0; Path=/',
      ];
    } else if (path == '/v2/session') {
      setCookies = const ['csrf=csrf-restored-a; Path=/'];
    } else if (path == '/v2/login') {
      final body = options.data as Map<String, dynamic>;
      final user = body['username']! as String;
      setCookies = ['session=$user; Path=/', 'csrf=csrf-$user; Path=/'];
    } else {
      setCookies = const [];
    }
    for (final cookie in setCookies) {
      final pair = cookie.split(';').first.split('=');
      final name = pair.first;
      final value = pair.skip(1).join('=');
      if (cookie.toLowerCase().contains('max-age=0')) {
        cookies.remove(name);
      } else {
        cookies[name] = value;
      }
    }
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {'set-cookie': setCookies},
    );
  }

  @override
  void close({bool force = false}) {}
}
