import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';

import '../../../../core/network/backend_data_client.dart';
import '../../../../core/network/foreground_read_gate.dart';
import '../../../../core/security/secure_storage_helper.dart';
import '../../../../core/session/connection_scope.dart';
import '../../../../core/session/user_session.dart';
import '../../data/multi_user_api_client.dart';
import '../../domain/connection_models.dart';

final multiUserForegroundReadGateProvider = Provider<ForegroundReadGate>((ref) {
  final gate = ForegroundReadGate();
  ref.onDispose(gate.dispose);
  return gate;
});

final multiUserAppForegroundProvider =
    ChangeNotifierProvider<MultiUserAppForegroundStore>((ref) {
      return MultiUserAppForegroundStore();
    });

class MultiUserAppForegroundStore extends ChangeNotifier
    with WidgetsBindingObserver {
  MultiUserAppForegroundStore({AppLifecycleState? initialState})
    : _isForeground = initialState == null
          ? WidgetsBinding.instance.lifecycleState == null ||
                WidgetsBinding.instance.lifecycleState ==
                    AppLifecycleState.resumed
          : initialState == AppLifecycleState.resumed {
    WidgetsBinding.instance.addObserver(this);
  }

  bool _isForeground;
  bool get isForeground => _isForeground;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_isForeground == foreground) return;
    _isForeground = foreground;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

final userSessionStoreProvider = ChangeNotifierProvider<UserSessionStore>((
  ref,
) {
  final store = UserSessionStore();
  return store;
});

final connectionScopeStoreProvider =
    ChangeNotifierProvider<ConnectionScopeStore>((ref) {
      final scopes = ConnectionScopeStore();
      final sessions = ref.read(userSessionStoreProvider);
      void clearWhenSessionLeaves() {
        final current = sessions.current;
        final scope = scopes.current;
        if (current == null || (scope != null && !scope.belongsTo(current))) {
          scopes.clear();
        }
      }

      sessions.addListener(clearWhenSessionLeaves);
      ref.onDispose(() {
        sessions.removeListener(clearWhenSessionLeaves);
      });
      return scopes;
    });

final selectedConnectionProvider =
    ChangeNotifierProvider<SelectedConnectionStore>((ref) {
      final selected = SelectedConnectionStore();
      final scopes = ref.read(connectionScopeStoreProvider);
      final sessions = ref.read(userSessionStoreProvider);
      void clearIfUnowned() {
        final scope = scopes.current;
        final session = sessions.current;
        final connection = selected.current;
        if (scope == null ||
            session == null ||
            connection == null ||
            scope.connectionId != connection.connectionId ||
            !scope.belongsTo(session)) {
          selected.clear();
        }
      }

      scopes.addListener(clearIfUnowned);
      sessions.addListener(clearIfUnowned);
      ref.onDispose(() {
        scopes.removeListener(clearIfUnowned);
        sessions.removeListener(clearIfUnowned);
      });
      return selected;
    });

final pendingOperationStoreProvider =
    ChangeNotifierProvider<PendingOperationStore>((ref) {
      final store = PendingOperationStore();
      final sessions = ref.read(userSessionStoreProvider);
      String? owner = sessions.current == null
          ? null
          : '${sessions.current!.userId}:${sessions.current!.sessionId}';
      void clearForDifferentOwner() {
        final current = sessions.current;
        if (current == null) {
          owner = null;
          store.clear();
          return;
        }
        final identity = '${current.userId}:${current.sessionId}';
        if (owner != null && owner != identity) store.clear();
        owner = identity;
      }

      sessions.addListener(clearForDifferentOwner);
      ref.onDispose(() => sessions.removeListener(clearForDifferentOwner));
      return store;
    });

final multiUserApiClientProvider = Provider<MultiUserApiClient>((ref) {
  // Keep the transport stable across login, logout, and account selection.
  final sessions = ref.read(userSessionStoreProvider);
  final scopes = ref.read(connectionScopeStoreProvider);
  final storage = ref.read(secureStorageProvider);
  final backend = BackendDataClient(
    onV2Unauthorized: (owner, generation, expected) {
      if (!identical(owner, sessions) ||
          !sessions.matches(generation, expected)) {
        return;
      }
      scopes.clear();
      sessions.update(null);
      unawaited(storage.clearV2SessionBearer());
    },
  );
  ref.onDispose(() => backend.close(force: true));
  return MultiUserApiClient(
    backend: backend,
    sessions: sessions,
    scopes: scopes,
    isWeb: kIsWeb,
  );
});

final multiUserControllerProvider = ChangeNotifierProvider<MultiUserController>(
  (ref) {
    final controller = MultiUserController(
      api: ref.read(multiUserApiClientProvider),
      sessions: ref.read(userSessionStoreProvider),
      scopes: ref.read(connectionScopeStoreProvider),
      selected: ref.read(selectedConnectionProvider),
      pending: ref.read(pendingOperationStoreProvider),
      storage: ref.read(secureStorageProvider),
      isWeb: kIsWeb,
    );
    return controller;
  },
);

class MultiUserController extends ChangeNotifier {
  MultiUserController({
    required this.api,
    required this.sessions,
    required this.scopes,
    required this.selected,
    required this.pending,
    required this.storage,
    required this.isWeb,
  }) {
    sessions.addListener(_handleSessionChanged);
  }

  final MultiUserApiClient api;
  final UserSessionStore sessions;
  final ConnectionScopeStore scopes;
  final SelectedConnectionStore selected;
  final PendingOperationStore pending;
  final SecureStorageHelper storage;
  final bool isWeb;

  bool _disposed = false;
  int _attemptGeneration = 0;
  final Map<int, int> _attemptSessionGenerations = {};
  bool isRestoring = false;
  bool isBusy = false;
  AuthBootstrap? enrollment;
  String? statusMessage;
  String? errorMessage;

  UserSession? get currentSession => sessions.current;
  bool get isAuthenticated => sessions.current?.canReadPrivate == true;
  bool get needsEnrollment => _activeEnrollment != null;
  AuthBootstrap? get activeEnrollment => _activeEnrollment;

  AuthBootstrap? get _activeEnrollment {
    final result = enrollment;
    final current = sessions.current;
    if (result == null ||
        current == null ||
        !current.isActive ||
        !{'enrollment', 'mfa_recovery'}.contains(current.mode) ||
        !result.session.sameIdentity(current)) {
      return null;
    }
    return result;
  }

  void _handleSessionChanged() {
    if (enrollment == null) return;
    if (_activeEnrollment == null) {
      enrollment = null;
      _notify();
    }
  }

  Future<void> restore() async {
    if (isRestoring || isBusy || sessions.current != null) return;
    isRestoring = true;
    final attempt = ++_attemptGeneration;
    final startingGeneration = sessions.generation;
    _attemptSessionGenerations[attempt] = startingGeneration;
    errorMessage = null;
    _notify();
    try {
      final nativeBearer = isWeb ? null : await storage.getV2SessionBearer();
      if (!_attemptCurrent(attempt, expectedGeneration: startingGeneration))
        return;
      if (!isWeb && (nativeBearer == null || nativeBearer.isEmpty)) return;
      final restored = await api.restoreSession(nativeBearer: nativeBearer);
      if (!_attemptCurrent(attempt, expectedGeneration: startingGeneration))
        return;
      await _accept(
        restored,
        attempt: attempt,
        expectedGeneration: startingGeneration,
      );
      if (restored.session.mode != 'ordinary') {
        await _loadEnrollment(restored.session, attempt: attempt);
      }
    } on BackendDataException catch (error) {
      if (!_attemptOwnsAuthority(attempt)) return;
      if (error.statusCode == 401 ||
          error.code == 'authentication_required' ||
          error.code == 'session_expired') {
        await _clearLocalSession(attempt: attempt);
      } else {
        errorMessage = error.message;
      }
    } catch (_) {
      if (_attemptOwnsAuthority(attempt)) {
        errorMessage = 'Không thể khôi phục phiên máy chủ. Hãy thử lại.';
      }
    } finally {
      if (_attemptCurrent(attempt)) {
        isRestoring = false;
        _notify();
      }
      _attemptSessionGenerations.remove(attempt);
    }
  }

  Future<void> activateInvite({
    required String inviteToken,
    required String username,
    required String password,
  }) async {
    await _run((attempt, startingGeneration) async {
      final activated = await api.activateInvite(
        inviteToken: inviteToken,
        username: username,
        password: password,
      );
      if (!_attemptCurrent(attempt) ||
          sessions.generation != startingGeneration)
        return;
      await _accept(
        activated,
        attempt: attempt,
        expectedGeneration: startingGeneration,
      );
      await _loadEnrollment(activated.session, attempt: attempt);
      if (!_attemptOwnsAuthority(attempt)) return;
      statusMessage =
          'Tài khoản đã được kích hoạt. Hãy bật MFA rồi đăng nhập lại.';
    });
  }

  Future<void> login({
    required String username,
    required String password,
    required String proof,
    required bool recoveryCode,
  }) async {
    await _run((attempt, startingGeneration) async {
      final authenticated = await api.login(
        username: username,
        password: password,
        mfaProof: proof,
        recoveryCode: recoveryCode,
      );
      if (!_attemptCurrent(attempt) ||
          sessions.generation != startingGeneration)
        return;
      await _accept(
        authenticated,
        attempt: attempt,
        expectedGeneration: startingGeneration,
      );
      if (!_attemptOwnsAuthority(attempt)) return;
      if (authenticated.session.mode != 'ordinary') {
        await _loadEnrollment(authenticated.session, attempt: attempt);
        if (!_attemptOwnsAuthority(attempt)) return;
        statusMessage = 'MFA cần được thiết lập lại trước khi tiếp tục.';
      } else {
        enrollment = null;
        statusMessage = null;
      }
    });
  }

  Future<void> completeEnrollment(String totp) async {
    final owner = sessions.current;
    final generation = sessions.generation;
    await _run((attempt, _) async {
      if (owner == null || !sessions.matches(generation, owner)) {
        throw _sessionChanged();
      }
      await api.completeMfaEnrollment(totp);
      if (!_attemptOwnsAuthority(attempt) ||
          !sessions.matches(generation, owner))
        return;
      await _clearLocalSession(
        attempt: attempt,
        expected: owner,
        generation: generation,
      );
      if (!_attemptOwnsAuthority(attempt)) return;
      statusMessage =
          'MFA đã bật. Hãy đăng nhập lại bằng mật khẩu và TOTP mới.';
    });
  }

  Future<void> stepUp({required String password, required String totp}) async {
    final current = sessions.current;
    final generation = sessions.generation;
    await _run((attempt, _) async {
      if (current == null ||
          !current.canReadPrivate ||
          !sessions.matches(generation, current))
        throw _sessionChanged();
      final until = await api.stepUp(password: password, totp: totp);
      if (!_attemptCurrent(attempt) || !sessions.matches(generation, current))
        return;
      sessions.update(current.withStepUp(until));
      _attemptSessionGenerations[attempt] = sessions.generation;
      statusMessage = 'Xác minh lại có hiệu lực trong thời gian ngắn.';
    });
  }

  Future<List<ConnectionRecord>> getConnections() => api.getConnections();

  Future<ConnectionRecord> createConnection({
    required String exchange,
    required String environment,
    required String region,
    required String nickname,
    required String apiKey,
    required String apiSecret,
    String? passphrase,
  }) async {
    final owner = sessions.current;
    final generation = sessions.generation;
    late ConnectionRecord record;
    await _run((attempt, _) async {
      if (owner == null ||
          !owner.canTrade ||
          !sessions.matches(generation, owner))
        throw _sessionChanged();
      record = await api.createConnection(
        exchange: exchange,
        environment: environment,
        region: region,
        nickname: nickname,
        apiKey: apiKey,
        apiSecret: apiSecret,
        passphrase: passphrase,
      );
      if (!_attemptCurrent(attempt) || !sessions.matches(generation, owner)) {
        throw _sessionChanged();
      }
      statusMessage = 'Sàn đã xác minh và kết nối an toàn.';
    });
    return record;
  }

  ConnectionScope? selectConnection(
    ConnectionRecord connection,
    String product,
  ) {
    final session = sessions.current;
    if (session == null || !session.canReadPrivate || !connection.isAvailable) {
      scopes.clear();
      selected.clear();
      return null;
    }
    final scope = scopes.select(
      session: session,
      connectionId: connection.connectionId,
      exchange: connection.exchange,
      environment: connection.environment,
      region: connection.region,
      product: product,
      credentialVersion: connection.credentialVersion,
      permissionVersion: connection.permissionVersion,
    );
    selected.select(connection);
    return scope;
  }

  Future<void> logout() async {
    final attempt = ++_attemptGeneration;
    _attemptSessionGenerations[attempt] = sessions.generation;
    final owner = sessions.current;
    final request = owner == null ? null : api.logout();
    isRestoring = false;
    isBusy = false;
    errorMessage = null;
    enrollment = null;
    pending.clear();
    scopes.clear();
    sessions.update(null);
    _attemptSessionGenerations[attempt] = sessions.generation;
    unawaited(storage.clearV2SessionBearer());
    _notify();
    var serverConfirmed = false;
    try {
      if (request != null) {
        await request;
        serverConfirmed = true;
      }
    } catch (_) {
      // Local private state is cleared even when the server cannot be reached.
    }
    if (!_attemptOwnsAuthority(attempt) || sessions.current != null) return;
    statusMessage = serverConfirmed
        ? 'Đã đăng xuất khỏi phiên máy chủ.'
        : 'Đã xóa phiên trên thiết bị; máy chủ chưa xác nhận đăng xuất.';
    _notify();
  }

  Future<void> _loadEnrollment(
    UserSession session, {
    required int attempt,
  }) async {
    if (!session.mode.startsWith('enrollment') &&
        session.mode != 'mfa_recovery') {
      return;
    }
    final generation = sessions.generation;
    if (!sessions.matches(generation, session)) return;
    final bootstrap = await api.startMfaEnrollment();
    if (_attemptOwnsAuthority(attempt) &&
        sessions.matches(generation, session) &&
        bootstrap.session.sameIdentity(session)) {
      enrollment = bootstrap;
      _notify();
    }
  }

  Future<void> _accept(
    AuthBootstrap result, {
    required int attempt,
    required int expectedGeneration,
  }) async {
    if (!_attemptCurrent(attempt) ||
        sessions.generation != expectedGeneration) {
      return;
    }
    sessions.update(result.session);
    _attemptSessionGenerations[attempt] = sessions.generation;
    enrollment =
        result.totpSecret == null ||
            !{'enrollment', 'mfa_recovery'}.contains(result.session.mode)
        ? null
        : result;
    if (!isWeb) {
      final token = result.session.bearerToken;
      if (token == null || token.isEmpty) {
        await _clearLocalSession(
          attempt: attempt,
          expected: result.session,
          generation: sessions.generation,
        );
        throw const BackendDataException(
          code: 'invalid_backend_response',
          message: 'Máy chủ chưa cấp phiên bảo mật hợp lệ.',
        );
      }
      await storage.saveV2SessionBearer(token);
      if (!_attemptOwnsAuthority(attempt) ||
          sessions.current?.sameIdentity(result.session) != true)
        return;
    }
  }

  Future<void> _clearLocalSession({
    required int attempt,
    UserSession? expected,
    int? generation,
  }) async {
    if (!_attemptCurrent(attempt)) return;
    if (expected != null &&
        generation != null &&
        !sessions.matches(generation, expected))
      return;
    scopes.clear();
    sessions.update(null);
    _attemptSessionGenerations[attempt] = sessions.generation;
    enrollment = null;
    if (!isWeb) await storage.clearV2SessionBearer();
  }

  Future<void> _run(
    Future<void> Function(int attempt, int startingGeneration) action,
  ) async {
    if (isBusy) return;
    final attempt = ++_attemptGeneration;
    isRestoring = false;
    final owner = sessions.current;
    final ownerGeneration = sessions.generation;
    _attemptSessionGenerations[attempt] = ownerGeneration;
    isBusy = true;
    errorMessage = null;
    statusMessage = null;
    _notify();
    try {
      await action(attempt, ownerGeneration);
    } on BackendDataException catch (error) {
      if (!_attemptOwnsAuthority(attempt)) return;
      if (owner != null && !sessions.matches(ownerGeneration, owner)) return;
      errorMessage = error.message;
      if (error.statusCode == 401 || error.code == 'session_expired') {
        if (owner != null) {
          await _clearLocalSession(
            attempt: attempt,
            expected: owner,
            generation: ownerGeneration,
          );
        }
      }
      rethrow;
    } finally {
      if (_attemptCurrent(attempt)) {
        isBusy = false;
        _notify();
      }
      _attemptSessionGenerations.remove(attempt);
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _attemptCurrent(int attempt, {int? expectedGeneration}) =>
      !_disposed &&
      attempt == _attemptGeneration &&
      (expectedGeneration == null || sessions.generation == expectedGeneration);

  bool _attemptOwnsAuthority(int attempt) =>
      _attemptCurrent(attempt) &&
      sessions.generation == _attemptSessionGenerations[attempt];

  BackendDataException _sessionChanged() => const BackendDataException(
    code: 'session_changed',
    message: 'Phiên giao dịch đã thay đổi. Hãy thử lại.',
    statusCode: 401,
  );

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    sessions.removeListener(_handleSessionChanged);
    enrollment = null;
    _attemptSessionGenerations.clear();
    super.dispose();
  }
}

class SelectedConnectionStore extends ChangeNotifier {
  ConnectionRecord? _current;
  ConnectionRecord? get current => _current;

  void select(ConnectionRecord connection) {
    if (_current == connection) return;
    _current = connection;
    notifyListeners();
  }

  void clear() {
    if (_current == null) return;
    _current = null;
    notifyListeners();
  }
}

@immutable
class PendingOperation {
  const PendingOperation({
    required this.scope,
    required this.operationId,
    required this.action,
    required this.createdAt,
    required this.connectionLabel,
    this.status = 'UNKNOWN',
    this.targets = const [],
  });

  final ConnectionScope scope;
  final String operationId;
  final String action;
  final DateTime createdAt;
  final String connectionLabel;
  final String status;
  final List<Map<String, dynamic>> targets;
}

class PendingOperationStore extends ChangeNotifier {
  final List<PendingOperation> _operations = [];
  List<PendingOperation> get operations => List.unmodifiable(_operations);

  void add(PendingOperation operation) {
    if (_operations.any(
      (item) =>
          item.scope == operation.scope &&
          item.operationId == operation.operationId,
    )) {
      return;
    }
    _operations.add(operation);
    notifyListeners();
  }

  void remove(PendingOperation operation) {
    _operations.removeWhere(
      (item) =>
          item.scope == operation.scope &&
          item.operationId == operation.operationId,
    );
    notifyListeners();
  }

  void update(PendingOperation operation, String status) {
    final index = _operations.indexWhere(
      (item) =>
          item.scope == operation.scope &&
          item.operationId == operation.operationId,
    );
    if (index < 0) return;
    final previous = _operations[index];
    _operations[index] = PendingOperation(
      scope: previous.scope,
      operationId: previous.operationId,
      action: previous.action,
      createdAt: previous.createdAt,
      connectionLabel: previous.connectionLabel,
      status: status,
      targets: previous.targets,
    );
    notifyListeners();
  }

  void updateProof(
    PendingOperation operation,
    String status,
    List<Map<String, dynamic>> targets,
  ) {
    final index = _operations.indexWhere(
      (item) =>
          item.scope == operation.scope &&
          item.operationId == operation.operationId,
    );
    if (index < 0) return;
    final previous = _operations[index];
    _operations[index] = PendingOperation(
      scope: previous.scope,
      operationId: previous.operationId,
      action: previous.action,
      createdAt: previous.createdAt,
      connectionLabel: previous.connectionLabel,
      status: status,
      targets: List.unmodifiable(targets),
    );
    notifyListeners();
  }

  void clear() {
    if (_operations.isEmpty) return;
    _operations.clear();
    notifyListeners();
  }
}
