import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/backend_data_client.dart';
import '../../../core/session/connection_scope.dart';
import '../../../core/session/user_session.dart';
import '../domain/connection_models.dart';

class AuthBootstrap {
  const AuthBootstrap({
    required this.session,
    this.totpSecret,
    this.recoveryCodes = const [],
  });

  final UserSession session;
  final String? totpSecret;
  final List<String> recoveryCodes;
}

@immutable
class ScopedPage<T> {
  const ScopedPage({required this.scope, required this.page});

  final ConnectionScope scope;
  final NormalizedPage<T> page;
}

class MultiUserApiClient {
  const MultiUserApiClient({
    required this.backend,
    required this.sessions,
    required this.scopes,
    required this.isWeb,
  });

  final BackendDataClient backend;
  final UserSessionStore sessions;
  final ConnectionScopeStore scopes;
  final bool isWeb;

  /// Creates a client for bounded read-only projections using a detached
  /// per-projection scope store while sharing the authenticated transport.
  ReadOnlyBalanceScopeReader createReadOnlyScopeReader(
    ConnectionScopeStore isolatedScopes, {
    required UserSessionStore isolatedSessions,
  }) => _ReadOnlyBalanceScopeReader(
    MultiUserApiClient(
      backend: backend,
      sessions: isolatedSessions,
      scopes: isolatedScopes,
      isWeb: isWeb,
    ),
  );

  Future<AuthBootstrap> restoreSession({String? nativeBearer}) async {
    final response = await backend.requestV2(
      'GET',
      '/v2/session',
      sessionStore: sessions,
      nativeBearerToken: isWeb ? null : nativeBearer,
    );
    return _authBootstrap(response.data, fallbackBearer: nativeBearer);
  }

  Future<AuthBootstrap> activateInvite({
    required String inviteToken,
    required String username,
    required String password,
  }) async {
    final response = await backend.requestV2(
      'POST',
      '/v2/invites/activate',
      body: {
        'inviteToken': inviteToken,
        'username': username,
        'password': password,
      },
      sessionStore: sessions,
    );
    return _authBootstrap(response.data);
  }

  Future<AuthBootstrap> login({
    required String username,
    required String password,
    required String mfaProof,
    required bool recoveryCode,
  }) async {
    final response = await backend.requestV2(
      'POST',
      '/v2/login',
      body: {
        'username': username,
        'password': password,
        if (recoveryCode) 'recoveryCode': mfaProof else 'totp': mfaProof,
      },
      sessionStore: sessions,
    );
    return _authBootstrap(response.data);
  }

  Future<AuthBootstrap> startMfaEnrollment() async {
    final response = await backend.requestV2(
      'POST',
      '/v2/mfa/enrollment',
      sessionStore: sessions,
    );
    final root = _map(response.data);
    final secret = root['totpSecret'];
    final recoveryCodes = root['recoveryCodes'];
    if (secret is! String ||
        secret.isEmpty ||
        recoveryCodes is! List ||
        recoveryCodes.isEmpty ||
        recoveryCodes.any((item) => item is! String)) {
      throw _invalidResponse();
    }
    final current = sessions.current;
    if (current == null ||
        !{'enrollment', 'mfa_recovery'}.contains(current.mode)) {
      throw _invalidResponse();
    }
    return AuthBootstrap(
      session: current,
      totpSecret: secret,
      recoveryCodes: recoveryCodes.cast<String>(),
    );
  }

  Future<void> completeMfaEnrollment(String totp) async {
    await backend.requestV2(
      'POST',
      '/v2/mfa/enrollment/complete',
      body: {'totp': totp, 'recoveryCodesSaved': true},
      sessionStore: sessions,
    );
  }

  Future<DateTime> stepUp({
    required String password,
    required String totp,
  }) async {
    final response = await backend.requestV2(
      'POST',
      '/v2/step-up',
      body: {'password': password, 'totp': totp},
      sessionStore: sessions,
    );
    final until = DateTime.tryParse(
      _string(_map(response.data)['stepUpUntil']),
    )?.toUtc();
    if (until == null || !until.isAfter(DateTime.now().toUtc())) {
      throw _invalidResponse();
    }
    return until;
  }

  Future<List<ConnectionRecord>> getConnections({
    CancelToken? cancelToken,
  }) async {
    final response = await backend.requestV2(
      'GET',
      '/v2/connections',
      sessionStore: sessions,
      cancelToken: cancelToken,
    );
    final root = _map(response.data);
    final values = root['connections'] ?? root['data'];
    if (values is! List) throw _invalidResponse();
    final result = <ConnectionRecord>[];
    for (final value in values) {
      final json = connectionJsonMap(value);
      final connection = ConnectionRecord.fromJson(json);
      if (connection.connectionId.isEmpty ||
          !const {'OKX', 'BINANCE'}.contains(connection.exchange) ||
          !const {'demo', 'production'}.contains(connection.environment) ||
          connection.region.isEmpty ||
          connection.credentialVersion < 0 ||
          connection.permissionVersion < 0) {
        throw _invalidResponse();
      }
      result.add(connection);
    }
    return List.unmodifiable(result);
  }

  Future<ConnectionRecord> createConnection({
    required String exchange,
    required String environment,
    required String region,
    required String nickname,
    required String apiKey,
    required String apiSecret,
    String? passphrase,
  }) async {
    final session = sessions.current;
    if (session == null || !session.canTrade) {
      throw const BackendDataException(
        code: 'step_up_required',
        message: 'Xác minh lại bằng TOTP trước khi tiếp tục.',
        statusCode: 403,
      );
    }
    final response = await backend.requestV2(
      'POST',
      '/v2/connections',
      body: {
        'exchange': exchange,
        'environment': environment,
        'region': region,
        if (nickname.trim().isNotEmpty) 'nickname': nickname.trim(),
        'apiKey': apiKey,
        'apiSecret': apiSecret,
        if (exchange == 'OKX') 'passphrase': passphrase ?? '',
      },
      sessionStore: sessions,
    );
    final root = _map(response.data);
    final record = ConnectionRecord.fromJson(root['connection'] ?? root);
    if (record.connectionId.isEmpty ||
        !{'ACTIVE', 'RECONCILING'}.contains(record.status)) {
      throw _invalidResponse();
    }
    return record;
  }

  Future<ScopedPage<NormalizedBalance>> balances(
    ConnectionScope scope, {
    String? cursor,
    int limit = 100,
    CancelToken? cancelToken,
  }) => _readPage(
    scope,
    'balances',
    NormalizedBalance.fromJson,
    cursor: cursor,
    limit: limit,
    cancelToken: cancelToken,
  );

  Future<ScopedPage<NormalizedPosition>> positions(
    ConnectionScope scope, {
    String? cursor,
    int limit = 100,
    CancelToken? cancelToken,
  }) => _readPage(
    scope,
    'positions',
    NormalizedPosition.fromJson,
    cursor: cursor,
    limit: limit,
    cancelToken: cancelToken,
  );

  Future<ScopedPage<NormalizedOrder>> orders(
    ConnectionScope scope, {
    String? cursor,
    int limit = 100,
    CancelToken? cancelToken,
  }) => _readPage(
    scope,
    'orders',
    NormalizedOrder.fromJson,
    cursor: cursor,
    limit: limit,
    cancelToken: cancelToken,
  );

  Future<ScopedPage<NormalizedBalance>> allBalances(
    ConnectionScope scope, {
    CancelToken? cancelToken,
  }) => _readAllPages(
    scope,
    (cursor) => balances(scope, cursor: cursor, cancelToken: cancelToken),
  );

  Future<ScopedPage<NormalizedPosition>> allPositions(
    ConnectionScope scope, {
    CancelToken? cancelToken,
  }) => _readAllPages(
    scope,
    (cursor) => positions(scope, cursor: cursor, cancelToken: cancelToken),
  );

  Future<ScopedPage<NormalizedOrder>> allOrders(
    ConnectionScope scope, {
    CancelToken? cancelToken,
  }) => _readAllPages(
    scope,
    (cursor) => orders(scope, cursor: cursor, cancelToken: cancelToken),
  );

  Future<ScopedPage<T>> _readAllPages<T>(
    ConnectionScope scope,
    Future<ScopedPage<T>> Function(String? cursor) loadPage,
  ) async {
    final rows = <T>[];
    final cursors = <String>{};
    DataMeta? snapshot;
    String? cursor;
    for (var pageIndex = 0; pageIndex < 100; pageIndex++) {
      final result = await loadPage(cursor);
      if (!result.scope.sameAuthority(scope)) throw _invalidResponse();
      final pageMeta = result.page.meta;
      if (snapshot == null) {
        snapshot = pageMeta;
      } else if (snapshot.asOf != pageMeta.asOf ||
          snapshot.snapshotExpiresAt != pageMeta.snapshotExpiresAt ||
          snapshot.stale != pageMeta.stale ||
          snapshot.complete != pageMeta.complete) {
        throw _invalidResponse();
      }
      rows.addAll(result.page.rows);
      final next = result.page.nextCursor;
      if (next == null) {
        return ScopedPage(
          scope: scope,
          page: NormalizedPage<T>(
            rows: List.unmodifiable(rows),
            nextCursor: null,
            meta: snapshot,
          ),
        );
      }
      if (!cursors.add(next)) throw _invalidResponse();
      cursor = next;
    }
    throw _invalidResponse();
  }

  Future<ScopedPage<T>> _readPage<T>(
    ConnectionScope scope,
    String endpoint,
    T Function(Object?) parseRow, {
    required String? cursor,
    required int limit,
    required CancelToken? cancelToken,
  }) async {
    final response = await backend.requestV2(
      'GET',
      '/v2/connections/${scope.connectionId}/$endpoint',
      queryParameters: {
        'product': scope.product,
        if (cursor != null) 'cursor': cursor,
        'limit': limit,
      },
      sessionStore: sessions,
      scopeStore: scopes,
      expectedScope: scope,
      cancelToken: cancelToken,
    );
    final root = _map(response.data);
    final rawRows = root['data'];
    final page = connectionJsonMap(root['page']);
    if (rawRows is! List || root['page'] is! Map || root['dataMeta'] is! Map) {
      throw _invalidResponse();
    }
    final rows = <T>[];
    for (final raw in rawRows) {
      if (!_rowMatchesScope(raw, scope)) throw _invalidResponse();
      final row = parseRow(raw);
      rows.add(row);
    }
    final nextCursor = page['nextCursor'];
    if (nextCursor != null &&
        (nextCursor is! String ||
            nextCursor.isEmpty ||
            nextCursor.length > 2048)) {
      throw _invalidResponse();
    }
    late final DataMeta meta;
    try {
      meta = DataMeta.fromJson(root['dataMeta']);
    } on FormatException {
      throw _invalidResponse();
    }
    final parsedPage = NormalizedPage<T>(
      rows: List.unmodifiable(rows),
      nextCursor: nextCursor as String?,
      meta: meta,
    );
    return ScopedPage(scope: scope, page: parsedPage);
  }

  Future<Map<String, dynamic>> getStrategy(ConnectionScope scope) async {
    final response = await backend.requestV2(
      'GET',
      '/v2/connections/${scope.connectionId}/strategies',
      sessionStore: sessions,
      scopeStore: scopes,
      expectedScope: scope,
    );
    return _map(response.data);
  }

  Future<Map<String, dynamic>> strategyRequest(
    ConnectionScope scope, {
    required String method,
    String suffix = '',
    Map<String, Object?>? body,
    Map<String, Object>? queryParameters,
  }) async {
    final normalizedMethod = method.toUpperCase();
    final validSuffix =
        suffix.isEmpty ||
        const {'preview', 'automatic-drafts', 'settings'}.contains(suffix) ||
        RegExp(
          r'^[A-Za-z0-9_-]{8,64}/(prepare-apply|execute-apply|result|delete|quote|retry-candidates|retry-preview|retry-drafts|refresh)$',
        ).hasMatch(suffix);
    if (!validSuffix || !const {'GET', 'POST'}.contains(normalizedMethod)) {
      throw _invalidResponse();
    }
    final response = await backend.requestV2(
      normalizedMethod,
      '/v2/connections/${scope.connectionId}/strategies${suffix.isEmpty ? '' : '/$suffix'}',
      queryParameters: queryParameters,
      body: body,
      sessionStore: sessions,
      scopeStore: scopes,
      expectedScope: scope,
    );
    return _map(response.data);
  }

  Future<Map<String, dynamic>> prepareAction(
    ConnectionScope scope, {
    required String action,
    required Map<String, String> targetIdentity,
  }) async {
    final response = await backend.requestV2(
      'POST',
      '/v2/connections/${scope.connectionId}/actions/prepare',
      body: {'action': action, 'targetIdentity': targetIdentity},
      sessionStore: sessions,
      scopeStore: scopes,
      expectedScope: scope,
    );
    final operation = _map(_map(response.data)['operation']);
    _validateOperation(operation, scope, action: action, operationId: null);
    final summary = _map(operation['summary']);
    final summaryIdentity = _map(summary['identity']);
    final targetProof = connectionJsonMap(
      (operation['targets'] as List).single,
    );
    if (_string(operation['confirmationToken']).isEmpty ||
        _string(operation['status']) != 'PREPARED' ||
        _string(targetProof['status']) != 'PREPARED' ||
        !_requiredFutureTimestamp(operation['expiresAt']) ||
        summary['action'] != action ||
        !_sameStringIdentity(summaryIdentity, targetIdentity) ||
        !_validPreparedSummary(action, summary, targetIdentity)) {
      throw _invalidResponse();
    }
    return operation;
  }

  Future<Map<String, dynamic>> executeAction(
    ConnectionScope scope, {
    required String action,
    required String operationId,
    required String confirmationToken,
    required String idempotencyKey,
  }) async {
    final response = await backend.requestV2(
      'POST',
      '/v2/connections/${scope.connectionId}/actions/$operationId/execute',
      body: {
        'confirmationToken': confirmationToken,
        'idempotencyKey': idempotencyKey,
      },
      sessionStore: sessions,
      scopeStore: scopes,
      expectedScope: scope,
    );
    final operation = _map(_map(response.data)['operation']);
    _validateOperation(
      operation,
      scope,
      action: action,
      operationId: operationId,
    );
    return operation;
  }

  Future<Map<String, dynamic>> operationResult(
    ConnectionScope originalScope,
    String operationId,
    String action,
  ) async {
    final response = await backend.requestV2(
      'GET',
      '/v2/connections/${originalScope.connectionId}/actions/$operationId',
      sessionStore: sessions,
      scopeStore: scopes,
      expectedScope: originalScope,
      allowDetachedScope: true,
    );
    final result = _map(_map(response.data)['operation']);
    _validateOperation(
      result,
      originalScope,
      action: action,
      operationId: operationId,
    );
    return result;
  }

  Future<void> logout() async {
    await backend.requestV2(
      'POST',
      '/v2/logout',
      sessionStore: sessions,
      allowSessionInvalidation: true,
    );
  }

  AuthBootstrap _authBootstrap(Object? value, {String? fallbackBearer}) {
    final root = _map(value);
    final metadataValue = root['session'] ?? root['auth'] ?? root;
    final metadata = _map(metadataValue);
    final userId = _string(metadata['userId']);
    final username = _string(metadata['username']);
    final sessionId = _string(metadata['sessionId']);
    final mode = _string(metadata['mode']);
    final expiresAt = DateTime.tryParse(
      _string(metadata['expiresAt']),
    )?.toUtc();
    final stepUpUntil = DateTime.tryParse(
      _string(metadata['stepUpUntil']),
    )?.toUtc();
    final rawToken =
        metadata['bearerToken'] ??
        metadata['sessionToken'] ??
        metadata['token'];
    final token = isWeb
        ? null
        : rawToken is String && rawToken.isNotEmpty
        ? rawToken
        : fallbackBearer;
    final csrf = metadata['csrfToken'] ?? root['csrfToken'];
    if (userId.isEmpty ||
        username.isEmpty ||
        sessionId.isEmpty ||
        !{'ordinary', 'enrollment', 'mfa_recovery'}.contains(mode) ||
        expiresAt == null ||
        !expiresAt.isAfter(DateTime.now().toUtc()) ||
        (!isWeb && (token == null || token.isEmpty))) {
      throw _invalidResponse();
    }
    final session = UserSession(
      userId: userId,
      username: username,
      sessionId: sessionId,
      mode: mode,
      expiresAt: expiresAt,
      stepUpUntil: stepUpUntil,
      bearerToken: token,
      csrfToken: isWeb && csrf is String ? csrf : null,
    );
    final codes = root['recoveryCodes'];
    return AuthBootstrap(
      session: session,
      totpSecret: root['totpSecret'] is String
          ? root['totpSecret'] as String
          : null,
      recoveryCodes: codes is List
          ? codes.whereType<String>().toList()
          : const [],
    );
  }

  bool _rowMatchesScope(Object? row, ConnectionScope scope) {
    final json = connectionJsonMap(row);
    return json['exchange'] == scope.exchange &&
        json['product'] == scope.product &&
        json['environment'] == scope.environment &&
        json['region'] == scope.region;
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is! Map) throw _invalidResponse();
    return connectionJsonMap(value);
  }

  String _string(Object? value) => value is String ? value : '';

  bool _requiredFutureTimestamp(Object? value) {
    if (value is! String) return false;
    final parsed = DateTime.tryParse(value)?.toUtc();
    return parsed != null && parsed.isAfter(DateTime.now().toUtc());
  }

  void _validateOperation(
    Map<String, dynamic> operation,
    ConnectionScope scope, {
    required String? action,
    required String? operationId,
  }) {
    final returnedId = _string(operation['operationId']);
    final returnedAction = _string(operation['action']);
    final targets = operation['targets'];
    final status = _string(operation['status']).toUpperCase();
    const operationStatuses = {
      'PREPARED',
      'SENDING',
      'RECONCILING',
      'UNKNOWN',
      'PARTIAL',
      'SUCCEEDED',
      'FAILED',
      'EXPIRED',
      'CANCELED',
      'CONFLICT',
    };
    const targetStatuses = {
      'PREPARED',
      'SENDING',
      'ATTEMPT_STARTED',
      'RECONCILING',
      'UNKNOWN',
      'PARTIAL',
      'SUCCEEDED',
      'FAILED',
      'CANCELED',
      'CONFLICT',
    };
    if (!RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(returnedId) ||
        (operationId != null && returnedId != operationId) ||
        operation['connectionId'] != scope.connectionId ||
        operation['product'] != scope.product ||
        (action != null && returnedAction != action) ||
        !const {'close_position', 'cancel_order'}.contains(returnedAction) ||
        !operationStatuses.contains(status) ||
        targets is! List ||
        targets.length != 1 ||
        operation['result'] != null && operation['result'] is! Map) {
      throw _invalidResponse();
    }
    final proof = connectionJsonMap(targets.single);
    final targetStatus = _string(proof['status']).toUpperCase();
    if (proof['index'] != 0 ||
        !targetStatuses.contains(targetStatus) ||
        (proof['result'] != null && proof['result'] is! Map)) {
      throw _invalidResponse();
    }
  }

  bool _sameStringIdentity(
    Map<String, dynamic> returned,
    Map<String, String> expected,
  ) =>
      returned.length == expected.length &&
      expected.entries.every((entry) => returned[entry.key] == entry.value);

  bool _validPreparedSummary(
    String action,
    Map<String, dynamic> summary,
    Map<String, String> identity,
  ) {
    if (action == 'close_position') {
      final direction = summary['direction'];
      return (direction == 'long' || direction == 'short') &&
          _positiveDecimal(summary['currentSize']);
    }
    return summary['price'] == identity['px'] &&
        summary['originalSize'] == identity['sz'] &&
        _positiveDecimal(summary['originalSize']) &&
        _nonnegativeDecimal(summary['filledSize']) &&
        _positiveDecimal(summary['remainingSize']);
  }

  bool _positiveDecimal(Object? value) =>
      value is String &&
      RegExp(r'^\d+(?:\.\d+)?$').hasMatch(value) &&
      double.tryParse(value)?.isFinite == true &&
      double.parse(value) > 0;

  bool _nonnegativeDecimal(Object? value) =>
      value is String &&
      RegExp(r'^\d+(?:\.\d+)?$').hasMatch(value) &&
      double.tryParse(value)?.isFinite == true &&
      double.parse(value) >= 0;

  BackendDataException _invalidResponse() => const BackendDataException(
    code: 'invalid_backend_response',
    message: 'Máy chủ trả về dữ liệu không hợp lệ. Hãy thử lại sau.',
  );
}

/// A projection-only view of the scoped API. It deliberately exposes no
/// connection creation, step-up, or trading command methods.
abstract interface class ReadOnlyBalanceScopeReader {
  Future<ScopedPage<NormalizedBalance>> balances(
    ConnectionScope scope, {
    String? cursor,
    int limit = 100,
    CancelToken? cancelToken,
  });
}

class _ReadOnlyBalanceScopeReader implements ReadOnlyBalanceScopeReader {
  _ReadOnlyBalanceScopeReader(this._client);

  final MultiUserApiClient _client;

  @override
  Future<ScopedPage<NormalizedBalance>> balances(
    ConnectionScope scope, {
    String? cursor,
    int limit = 100,
    CancelToken? cancelToken,
  }) => _client.balances(
    scope,
    cursor: cursor,
    limit: limit,
    cancelToken: cancelToken,
  );
}
