import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../session/connection_scope.dart';
import '../session/user_session.dart';
import '../../features/orders/data/trade_api_browser_adapter_stub.dart'
    if (dart.library.html) '../../features/orders/data/trade_api_browser_adapter.dart'
    as browser;
import '../../features/orders/data/trade_api_client.dart';
import 'backend_data_session.dart';

typedef BackendDataUnauthorizedHandler =
    void Function(
      BackendDataSession session,
      int generation,
      TradeSession expectedSession,
    );

typedef BackendV2UnauthorizedHandler =
    void Function(UserSessionStore store, int generation, UserSession session);

class _BackendDataRoute {
  const _BackendDataRoute(this.path, {this.requiresSession = false});

  final String path;
  final bool requiresSession;
}

class _V2Route {
  const _V2Route({
    required this.method,
    required this.path,
    this.requiresSession = false,
    this.requiresOrdinary = false,
    this.requiresStepUp = false,
    this.sessionOptional = false,
    this.mutating = false,
    this.connectionId,
    this.allowDetachedScope = false,
    this.allowSessionInvalidation = false,
    this.allowedBodyKeys,
  });

  final String method;
  final String path;
  final bool requiresSession;
  final bool requiresOrdinary;
  final bool requiresStepUp;
  final bool sessionOptional;
  final bool mutating;
  final String? connectionId;
  final bool allowDetachedScope;
  final bool allowSessionInvalidation;
  final Set<String>? allowedBodyKeys;

  _V2Route withConnection(String id, {bool allowDetached = false}) => _V2Route(
    method: method,
    path: path,
    requiresSession: requiresSession,
    requiresOrdinary: requiresOrdinary,
    requiresStepUp: requiresStepUp,
    sessionOptional: sessionOptional,
    mutating: mutating,
    connectionId: id,
    allowDetachedScope: allowDetached,
    allowSessionInvalidation: allowSessionInvalidation,
    allowedBodyKeys: allowedBodyKeys,
  );
}

class _V2RequestDescriptor {
  const _V2RequestDescriptor({
    required this.route,
    required this.sessionStore,
    required this.sessionGeneration,
    required this.session,
    required this.scopeStore,
    required this.scopeGeneration,
    required this.scope,
    required this.allowDetachedScope,
    required this.allowSessionInvalidation,
    required this.expectedAuthorization,
    required this.expectedTransport,
    required this.expectedCsrf,
    required this.expectedBody,
    required this.expectedQuery,
  });

  final _V2Route route;
  final UserSessionStore? sessionStore;
  final int? sessionGeneration;
  final UserSession? session;
  final ConnectionScopeStore? scopeStore;
  final int? scopeGeneration;
  final ConnectionScope? scope;
  final bool allowDetachedScope;
  final bool allowSessionInvalidation;
  final String? expectedAuthorization;
  final String? expectedTransport;
  final String? expectedCsrf;
  final String? expectedBody;
  final String? expectedQuery;
}

/// A GET-only Dio transport for the registered backend data routes.
///
/// Callers keep their legacy `/api/v5/...` paths; this client maps only those
/// exact paths onto the backend registry and retains a base URL path prefix.
class BackendDataClient {
  static Future<void>? _webAuthCookieTail;

  BackendDataClient({
    Dio? dio,
    String? baseUrl,
    this.onUnauthorized,
    this.onV2Unauthorized,
    bool? isWeb,
  }) : _baseUrl = (baseUrl ?? tradeApiBaseUrl).trim(),
       _dio = dio,
       isWeb = isWeb ?? kIsWeb;

  static const String usdtVndRoute = '/v1/data/currency/usdt-vnd';
  static const String sessionExtraKey = 'backendDataSession';
  static const String errorCodeExtraKey = 'backendDataErrorCode';
  static const String _generationExtraKey = 'backendDataGeneration';
  static const String _expectedSessionExtraKey = 'backendDataExpectedSession';
  static const String _v2RequestExtraKey = 'backendV2Request';

  static const Map<String, _BackendDataRoute> _routes = {
    '/api/v5/public/instruments': _BackendDataRoute(
      'v1/data/public/instruments',
    ),
    '/api/v5/market/ticker': _BackendDataRoute('v1/data/market/ticker'),
    '/api/v5/market/tickers': _BackendDataRoute('v1/data/market/tickers'),
    '/api/v5/market/quotes': _BackendDataRoute('v1/data/market/quotes'),
    '/api/v5/market/candles': _BackendDataRoute('v1/data/market/candles'),
    '/api/v5/market/history-candles': _BackendDataRoute(
      'v1/data/market/history-candles',
    ),
    '/api/v5/public/funding-rate': _BackendDataRoute(
      'v1/data/public/funding-rate',
    ),
    '/api/v5/public/open-interest': _BackendDataRoute(
      'v1/data/public/open-interest',
    ),
    '/api/v5/account/balance': _BackendDataRoute(
      'v1/data/account/balance',
      requiresSession: true,
    ),
    '/api/v5/account/positions': _BackendDataRoute(
      'v1/data/account/positions',
      requiresSession: true,
    ),
    '/api/v5/trade/orders-pending': _BackendDataRoute(
      'v1/data/trade/orders-pending',
      requiresSession: true,
    ),
    '/api/v5/trade/orders-history': _BackendDataRoute(
      'v1/data/trade/orders-history',
      requiresSession: true,
    ),
    '/api/v5/account/config': _BackendDataRoute(
      'v1/data/account/config',
      requiresSession: true,
    ),
    '/api/v5/account/instruments': _BackendDataRoute(
      'v1/data/account/instruments',
      requiresSession: true,
    ),
    '/api/v5/account/trade-fee': _BackendDataRoute(
      'v1/data/account/trade-fee',
      requiresSession: true,
    ),
    '/api/v5/account/interest-rate': _BackendDataRoute(
      'v1/data/account/interest-rate',
      requiresSession: true,
    ),
    '/api/v5/account/interest-accrued': _BackendDataRoute(
      'v1/data/account/interest-accrued',
      requiresSession: true,
    ),
    usdtVndRoute: _BackendDataRoute('v1/data/currency/usdt-vnd'),
  };

  final String _baseUrl;
  Dio? _dio;
  final BackendDataUnauthorizedHandler? onUnauthorized;
  final BackendV2UnauthorizedHandler? onV2Unauthorized;
  final bool isWeb;
  final Expando<_AuthorizedRequest> _authorizedRequests =
      Expando<_AuthorizedRequest>('backend data authorization');
  bool _interceptorInstalled = false;

  bool get isConfigured => _validatedBaseUrl != null;

  /// A compatible Dio seam for successor repositories. It retains the same
  /// route allowlist, session fencing, redirect denial, and auth callback.
  Dio get dio {
    final baseUrl = _validatedBaseUrl;
    if (baseUrl == null) {
      throw const BackendDataException(
        code: 'api_not_configured',
        message:
            'TRADE_API_BASE_URL chưa được cấu hình thành địa chỉ HTTPS hợp lệ.',
      );
    }
    return _client(baseUrl);
  }

  String? get _validatedBaseUrl {
    if (_baseUrl.isEmpty) return null;
    try {
      final uri = Uri.parse(_baseUrl);
      if (!uri.isAbsolute ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment) {
        return null;
      }
      uri.port;
      final normalized = uri.toString();
      return normalized.endsWith('/') ? normalized : '$normalized/';
    } on FormatException {
      return null;
    }
  }

  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    BackendDataSession? session,
    CancelToken? cancelToken,
  }) async {
    final baseUrl = _validatedBaseUrl;
    if (baseUrl == null) {
      throw const BackendDataException(
        code: 'api_not_configured',
        message:
            'TRADE_API_BASE_URL chưa được cấu hình thành địa chỉ HTTPS hợp lệ.',
      );
    }

    final route = _routes[path];
    if (route == null) {
      throw const BackendDataException(
        code: 'route_not_registered',
        message: 'Đường dẫn dữ liệu không được đăng ký.',
      );
    }

    if (route.requiresSession) {
      if (session == null) {
        throw _authenticationRequired();
      }
      if (session.current == null) {
        session.expireIfNeeded();
        throw _authenticationRequired();
      }
    }

    try {
      return await _client(baseUrl).get<dynamic>(
        path,
        queryParameters: queryParameters,
        cancelToken: cancelToken,
        options: Options(
          method: 'GET',
          followRedirects: false,
          maxRedirects: 0,
          extra: {if (session != null) sessionExtraKey: session},
        ),
      );
    } on DioException catch (error) {
      if (error.type == DioExceptionType.cancel) {
        throw const BackendDataException(
          code: 'request_cancelled',
          message: 'The foreground read was cancelled.',
        );
      }
      final errorCode = error.requestOptions.extra[errorCodeExtraKey];
      if (errorCode is String) {
        throw BackendDataException(
          code: errorCode,
          message: error.message ?? 'Không thể tải dữ liệu backend.',
          statusCode: error.response?.statusCode,
          retryAfter: error.response?.headers.value('retry-after'),
        );
      }
      final statusCode = error.response?.statusCode;
      if (statusCode != null) {
        throw BackendDataException(
          code: 'http_error',
          message: error.message ?? 'Không thể tải dữ liệu backend.',
          statusCode: statusCode,
          retryAfter: error.response?.headers.value('retry-after'),
        );
      }
      rethrow;
    }
  }

  /// Sends only registered v2 routes through the same final-destination guard
  /// used by legacy data reads. V2 exchange credentials never reach this API.
  Future<Response<dynamic>> requestV2(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? queryParameters,
    UserSessionStore? sessionStore,
    String? nativeBearerToken,
    ConnectionScopeStore? scopeStore,
    ConnectionScope? expectedScope,
    bool allowDetachedScope = false,
    bool allowSessionInvalidation = false,
    CancelToken? cancelToken,
  }) async {
    final baseUrl = _validatedBaseUrl;
    if (baseUrl == null) {
      throw const BackendDataException(
        code: 'api_not_configured',
        message:
            'TRADE_API_BASE_URL chưa được cấu hình thành địa chỉ HTTPS hợp lệ.',
      );
    }
    final normalizedMethod = method.toUpperCase();
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final route = _resolveV2Route(normalizedMethod, normalizedPath);
    if (route == null) {
      throw const BackendDataException(
        code: 'route_not_registered',
        message: 'Đường dẫn dữ liệu không được đăng ký.',
      );
    }
    _validateV2Query(route, queryParameters);
    _validateV2Body(route, body);

    final session = sessionStore?.current;
    if (route.requiresSession && session == null) {
      sessionStore?.expireIfNeeded();
      throw _authenticationRequired();
    }
    if (route.requiresOrdinary && !(session?.canReadPrivate ?? false)) {
      throw const BackendDataException(
        code: 'restricted_session',
        message: 'Hoàn tất xác thực nhiều lớp để tiếp tục.',
        statusCode: 403,
      );
    }
    if (route.requiresStepUp && !(session?.canTrade ?? false)) {
      throw const BackendDataException(
        code: 'step_up_required',
        message: 'Xác minh lại bằng TOTP trước khi tiếp tục.',
        statusCode: 403,
      );
    }

    if (allowDetachedScope && !route.allowDetachedScope) {
      throw const BackendDataException(
        code: 'detached_scope_forbidden',
        message: 'This request must remain bound to the selected account.',
      );
    }
    if (allowSessionInvalidation && !route.allowSessionInvalidation) {
      throw const BackendDataException(
        code: 'session_invalidation_forbidden',
        message: 'The session cannot be invalidated for this request.',
      );
    }
    final detachedScope = allowDetachedScope && route.allowDetachedScope;
    final scope = expectedScope ?? scopeStore?.current;
    final scopeGeneration = scope?.generation;
    if (route.connectionId != null) {
      if (scope == null ||
          scopeStore == null ||
          scope.connectionId != route.connectionId ||
          !scope.belongsTo(session!) ||
          (!detachedScope && !scopeStore.matches(scopeGeneration!, scope))) {
        throw const BackendDataException(
          code: 'scope_changed',
          message: 'Tài khoản giao dịch đã thay đổi. Hãy tải lại dữ liệu.',
          statusCode: 409,
        );
      }
      final product = queryParameters?['product'];
      if (product != null && product != scope.product) {
        throw const BackendDataException(
          code: 'scope_changed',
          message: 'Sản phẩm giao dịch đã thay đổi. Hãy tải lại dữ liệu.',
          statusCode: 409,
        );
      }
    }

    final bearer = session?.bearerToken ?? nativeBearerToken;
    final useBearer =
        !isWeb &&
        (route.requiresSession ||
            (route.sessionOptional && bearer != null && bearer.isNotEmpty));
    if (useBearer && (bearer == null || bearer.isEmpty)) {
      throw const BackendDataException(
        code: 'authentication_required',
        message: 'Vui lòng đăng nhập để tiếp tục.',
        statusCode: 401,
      );
    }
    final csrf = !isWeb || session == null || !route.mutating
        ? null
        : session.csrfToken;
    if (isWeb &&
        session != null &&
        route.mutating &&
        (csrf == null || csrf.isEmpty)) {
      throw const BackendDataException(
        code: 'csrf_missing',
        message: 'Phiên bảo mật đã hết hạn. Hãy đăng nhập lại.',
        statusCode: 403,
      );
    }
    final generation = sessionStore?.generation;
    final descriptor = _V2RequestDescriptor(
      route: route,
      sessionStore: sessionStore,
      sessionGeneration: generation,
      session: session,
      scopeStore: scopeStore,
      scopeGeneration: scopeGeneration,
      scope: scope,
      allowDetachedScope: detachedScope,
      allowSessionInvalidation:
          allowSessionInvalidation && route.allowSessionInvalidation,
      expectedAuthorization: useBearer ? 'Bearer $bearer' : null,
      expectedTransport: !isWeb ? 'bearer' : null,
      expectedCsrf: csrf,
      expectedBody: _fingerprint(body),
      expectedQuery: _fingerprint(queryParameters),
    );
    Future<Response<dynamic>> send() async {
      try {
        return await _client(baseUrl).request<dynamic>(
          normalizedPath.substring(1),
          data: body,
          queryParameters: queryParameters,
          cancelToken: cancelToken,
          options: Options(
            method: normalizedMethod,
            followRedirects: false,
            maxRedirects: 0,
            headers: {
              if (!isWeb) 'X-Session-Transport': 'bearer',
              if (descriptor.expectedAuthorization != null)
                'Authorization': descriptor.expectedAuthorization,
              if (csrf != null) 'X-CSRF-Token': csrf,
            },
            extra: {_v2RequestExtraKey: descriptor},
          ),
        );
      } on DioException catch (error) {
        final code = error.requestOptions.extra[errorCodeExtraKey];
        if (code is String) {
          throw BackendDataException(
            code: code,
            message: error.message ?? 'Không thể tải dữ liệu backend.',
            statusCode: error.response?.statusCode,
            retryAfter: error.response?.headers.value('retry-after'),
          );
        }
        throw BackendDataException(
          code: error.type == DioExceptionType.cancel
              ? 'request_cancelled'
              : error.response?.statusCode == null
              ? 'network_error'
              : 'http_error',
          message: error.type == DioExceptionType.cancel
              ? 'The foreground read was cancelled.'
              : error.message ?? 'Không thể tải dữ liệu backend.',
          statusCode: error.response?.statusCode,
          retryAfter: error.response?.headers.value('retry-after'),
        );
      }
    }

    if (isWeb && _changesWebSessionCookies(route)) {
      return _serializeWebSessionCookieMutation(send);
    }
    return send();
  }

  bool _changesWebSessionCookies(_V2Route route) =>
      (route.method == 'POST' &&
          const {
            '/v2/login',
            '/v2/invites/activate',
            '/v2/logout',
            '/v2/mfa/enrollment/complete',
          }.contains(route.path)) ||
      (route.method == 'GET' && route.path == '/v2/session');

  Future<T> _serializeWebSessionCookieMutation<T>(
    Future<T> Function() send,
  ) async {
    final previous = _webAuthCookieTail;
    final completion = Completer<void>();
    final tail = completion.future;
    _webAuthCookieTail = tail;
    if (previous != null) await previous;
    try {
      return await send();
    } finally {
      completion.complete();
      if (identical(_webAuthCookieTail, tail)) _webAuthCookieTail = null;
    }
  }

  _V2Route? _resolveV2Route(String method, String path) {
    _V2Route make({
      bool session = false,
      bool ordinary = false,
      bool stepUp = false,
      bool optionalSession = false,
      bool mutating = false,
      String? connection,
      bool detached = false,
      bool invalidateSession = false,
      Set<String>? body,
    }) => _V2Route(
      method: method,
      path: path,
      requiresSession: session,
      requiresOrdinary: ordinary,
      requiresStepUp: stepUp,
      sessionOptional: optionalSession,
      mutating: mutating,
      connectionId: connection,
      allowDetachedScope: detached,
      allowSessionInvalidation: invalidateSession,
      allowedBodyKeys: body,
    );

    switch ('$method $path') {
      case 'POST /v2/login':
        return make(
          mutating: true,
          body: const {'username', 'password', 'totp', 'recoveryCode'},
        );
      case 'POST /v2/invites/activate':
        return make(
          mutating: true,
          body: const {'inviteToken', 'username', 'password'},
        );
      case 'GET /v2/session':
        return make(optionalSession: true);
      case 'POST /v2/logout':
        return make(session: true, mutating: true, invalidateSession: true);
      case 'POST /v2/mfa/enrollment':
        return make(session: true, mutating: true);
      case 'POST /v2/mfa/enrollment/complete':
        return make(
          session: true,
          mutating: true,
          body: const {'totp', 'recoveryCodesSaved'},
        );
      case 'POST /v2/step-up':
        return make(
          session: true,
          ordinary: true,
          mutating: true,
          body: const {'password', 'totp'},
        );
      case 'GET /v2/connections':
        return make(session: true, ordinary: true);
      case 'POST /v2/connections':
        return make(
          session: true,
          ordinary: true,
          stepUp: true,
          mutating: true,
          body: const {
            'exchange',
            'environment',
            'region',
            'nickname',
            'apiKey',
            'apiSecret',
            'passphrase',
          },
        );
      case 'GET /v2/market/instruments':
      case 'GET /v2/market/ticker':
        return make();
    }

    final connection = RegExp(
      r'^/v2/connections/([A-Za-z0-9_-]{8,64})$',
    ).firstMatch(path);
    if (connection != null && method == 'GET') {
      return make(
        session: true,
        ordinary: true,
        connection: connection.group(1),
      );
    }
    final connectionAction = RegExp(
      r'^/v2/connections/([A-Za-z0-9_-]{8,64})/(verify|credentials|revoke)$',
    ).firstMatch(path);
    if (connectionAction != null && method == 'POST') {
      return make(
        session: true,
        ordinary: true,
        stepUp: true,
        mutating: true,
        connection: connectionAction.group(1),
        body: connectionAction.group(2) == 'credentials'
            ? const {'apiKey', 'apiSecret', 'passphrase'}
            : const <String>{},
      );
    }
    final read = RegExp(
      r'^/v2/connections/([A-Za-z0-9_-]{8,64})/(balances|positions|orders)$',
    ).firstMatch(path);
    if (read != null && method == 'GET') {
      return make(session: true, ordinary: true, connection: read.group(1));
    }
    final prepare = RegExp(
      r'^/v2/connections/([A-Za-z0-9_-]{8,64})/actions/prepare$',
    ).firstMatch(path);
    if (prepare != null && method == 'POST') {
      return make(
        session: true,
        ordinary: true,
        stepUp: true,
        mutating: true,
        connection: prepare.group(1),
        body: const {'action', 'targetIdentity'},
      );
    }
    final operation = RegExp(
      r'^/v2/connections/([A-Za-z0-9_-]{8,64})/actions/([A-Za-z0-9_-]{8,64})(?:/(execute|reconcile))?$',
    ).firstMatch(path);
    if (operation != null) {
      final suffix = operation.group(3);
      if (method == 'GET' && suffix == null) {
        return make(
          session: true,
          ordinary: true,
          connection: operation.group(1),
          detached: true,
        );
      }
      if (method == 'POST' && suffix == 'execute') {
        return make(
          session: true,
          ordinary: true,
          stepUp: true,
          mutating: true,
          connection: operation.group(1),
          body: const {'confirmationToken', 'idempotencyKey'},
        );
      }
      if (method == 'POST' && suffix == 'reconcile') {
        return make(
          session: true,
          ordinary: true,
          stepUp: true,
          mutating: true,
          connection: operation.group(1),
          detached: true,
        );
      }
    }
    final strategy = RegExp(
      r'^/v2/connections/([A-Za-z0-9_-]{8,64})/strategies(?:/(.*))?$',
    ).firstMatch(path);
    if (strategy != null) {
      final connectionId = strategy.group(1)!;
      final suffix = strategy.group(2);
      final strategyContractKeys = <String>{
        'instrumentId',
        'interval',
        'direction',
        'selectedLevels',
        'entryLevelIdBySide',
        'entryBySide',
        'totalMargin',
        'leverage',
        'sidePercent',
        'allocation',
      };
      if (method == 'GET' && suffix == null) {
        return make(session: true, ordinary: true, connection: connectionId);
      }
      if (method == 'GET' && const {'settings'}.contains(suffix) ||
          method == 'GET' &&
              suffix != null &&
              RegExp(
                r'^[A-Za-z0-9_-]{8,64}/(result|quote|retry-candidates)$',
              ).hasMatch(suffix)) {
        return make(session: true, ordinary: true, connection: connectionId);
      }
      if (method == 'POST') {
        Set<String>? body;
        var stepUp = false;
        if (suffix == 'preview') {
          body = strategyContractKeys;
        } else if (suffix == null) {
          body = {
            ...strategyContractKeys,
            'previewHash',
            'replacementSourceId',
            'candidateDraftId',
          };
        } else if (suffix == 'automatic-drafts') {
          body = const {'instrumentId', 'interval', 'requestId', 'direction'};
        } else if (suffix == 'settings') {
          body = const {'limitOrderSubmissionMode', 'jevScreeningThresholds'};
        } else if (RegExp(
          r'^[A-Za-z0-9_-]{8,64}/retry-preview$',
        ).hasMatch(suffix)) {
          body = const {'sourceRevision', 'sourceClientOrderIds'};
        } else if (RegExp(
          r'^[A-Za-z0-9_-]{8,64}/retry-drafts$',
        ).hasMatch(suffix)) {
          body = const {
            'sourceRevision',
            'sourceClientOrderIds',
            'previewHash',
            'retryRequestId',
          };
        } else if (RegExp(
          r'^[A-Za-z0-9_-]{8,64}/(prepare-apply|delete|refresh)$',
        ).hasMatch(suffix)) {
          body = const <String>{};
          stepUp = suffix.endsWith('/prepare-apply');
        } else if (RegExp(
          r'^[A-Za-z0-9_-]{8,64}/execute-apply$',
        ).hasMatch(suffix)) {
          body = const {'confirmationToken'};
          stepUp = true;
        }
        if (body != null) {
          return make(
            session: true,
            ordinary: true,
            stepUp: stepUp,
            mutating: true,
            connection: connectionId,
            body: body,
          );
        }
      }
    }
    return null;
  }

  Dio _client(String validatedBaseUrl) {
    if (_dio == null) {
      final client = Dio(
        BaseOptions(
          baseUrl: validatedBaseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 10),
          followRedirects: false,
          maxRedirects: 0,
          headers: const {'Content-Type': 'application/json'},
        ),
      );
      browser.configureTradeApiBrowserClient(client);
      _dio = client;
    }
    final client = _dio!;
    client.options.baseUrl = validatedBaseUrl;
    client.options.followRedirects = false;
    client.options.maxRedirects = 0;
    if (client.httpClientAdapter is! _GuardedHttpClientAdapter) {
      client.httpClientAdapter = _GuardedHttpClientAdapter(
        delegate: client.httpClientAdapter,
        owner: this,
      );
    }
    if (!_interceptorInstalled) {
      client.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: _handleRequest,
          onResponse: _handleResponse,
          onError: _handleError,
        ),
      );
      _interceptorInstalled = true;
    }
    return client;
  }

  void _handleRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    final v2Descriptor = options.extra[_v2RequestExtraKey];
    if (v2Descriptor is _V2RequestDescriptor) {
      _handleV2Request(options, handler, v2Descriptor);
      return;
    }
    final route = _routes[options.path];
    if (options.method.toUpperCase() != 'GET') {
      handler.reject(
        _failure(
          options,
          code: 'method_not_allowed',
          message: 'Chỉ cho phép đọc dữ liệu backend bằng GET.',
        ),
      );
      return;
    }
    if (route == null) {
      handler.reject(
        _failure(
          options,
          code: 'route_not_registered',
          message: 'Đường dẫn dữ liệu không được đăng ký.',
        ),
      );
      return;
    }

    try {
      _rejectForbiddenHeaders(options.headers);
    } on BackendDataException catch (error) {
      handler.reject(
        _failure(options, code: error.code, message: error.message),
      );
      return;
    }

    options.path = route.path;
    options.followRedirects = false;
    options.maxRedirects = 0;
    if (!_targetsConfiguredBackend(options, route.path)) {
      handler.reject(
        _failure(
          options,
          code: 'destination_forbidden',
          message: 'Đích dữ liệu backend không hợp lệ.',
        ),
      );
      return;
    }
    final expectedUri = options.uri;

    if (route.requiresSession) {
      final session = options.extra[sessionExtraKey];
      if (session is! BackendDataSession) {
        handler.reject(
          _failure(
            options,
            code: 'authentication_required',
            message: _authenticationRequired().message,
            statusCode: 401,
          ),
        );
        return;
      }
      final current = session.current;
      if (current == null) {
        session.expireIfNeeded();
        handler.reject(
          _failure(
            options,
            code: 'authentication_required',
            message: _authenticationRequired().message,
            statusCode: 401,
          ),
        );
        return;
      }
      options.extra[_generationExtraKey] = session.generation;
      options.extra[_expectedSessionExtraKey] = current;
      options.headers['Authorization'] = 'Bearer ${current.bearerToken}';
    }
    _authorizedRequests[options] = _AuthorizedRequest(
      expectedUri: expectedUri,
      expectedMethod: 'GET',
      expectedAuthorization: _headerValue(options.headers, 'authorization'),
      session: _requestSession(options),
      expectedTransport: null,
      expectedCsrf: null,
      v2: null,
      expectedBody: null,
      expectedQuery: _fingerprint(options.queryParameters),
    );

    handler.next(options);
  }

  void _handleV2Request(
    RequestOptions options,
    RequestInterceptorHandler handler,
    _V2RequestDescriptor descriptor,
  ) {
    final route = descriptor.route;
    if (options.method.toUpperCase() != route.method ||
        (options.path.startsWith('/') ? options.path : '/${options.path}') !=
            route.path) {
      handler.reject(
        _failure(
          options,
          code: 'route_not_registered',
          message: 'Đường dẫn dữ liệu không được đăng ký.',
        ),
      );
      return;
    }
    final sessionStore = descriptor.sessionStore;
    final session = descriptor.session;
    if (sessionStore != null &&
        session != null &&
        !sessionStore.matches(descriptor.sessionGeneration!, session) &&
        !(descriptor.allowSessionInvalidation &&
            sessionStore.current == null)) {
      handler.reject(
        _failure(
          options,
          code: 'session_changed',
          message: _sessionChanged().message,
          statusCode: 401,
        ),
      );
      return;
    }
    if (!_v2RequestCurrent(descriptor)) {
      handler.reject(
        _failure(
          options,
          code: _v2FailureCode(descriptor),
          message: _v2FailureMessage(descriptor),
          statusCode: _v2FailureStatus(descriptor),
        ),
      );
      return;
    }
    try {
      _rejectExchangeHeaders(options.headers);
    } on BackendDataException catch (error) {
      handler.reject(
        _failure(options, code: error.code, message: error.message),
      );
      return;
    }
    if (_headerCount(options.headers, 'authorization') !=
            (descriptor.expectedAuthorization == null ? 0 : 1) ||
        _headerValue(options.headers, 'authorization') !=
            descriptor.expectedAuthorization ||
        _headerCount(options.headers, 'x-session-transport') !=
            (descriptor.expectedTransport == null ? 0 : 1) ||
        _headerValue(options.headers, 'x-session-transport') !=
            descriptor.expectedTransport ||
        _headerCount(options.headers, 'x-csrf-token') !=
            (descriptor.expectedCsrf == null ? 0 : 1) ||
        _headerValue(options.headers, 'x-csrf-token') !=
            descriptor.expectedCsrf) {
      handler.reject(
        _failure(
          options,
          code: 'authorization_changed',
          message: 'Thông tin xác thực của yêu cầu đã thay đổi.',
        ),
      );
      return;
    }
    options.path = route.path.substring(1);
    options.followRedirects = false;
    options.maxRedirects = 0;
    if (!_targetsConfiguredBackend(options, route.path)) {
      handler.reject(
        _failure(
          options,
          code: 'destination_forbidden',
          message: 'Đích dữ liệu backend không hợp lệ.',
        ),
      );
      return;
    }
    final expectedUri = options.uri;
    _authorizedRequests[options] = _AuthorizedRequest(
      expectedUri: expectedUri,
      expectedMethod: route.method,
      expectedAuthorization: descriptor.expectedAuthorization,
      session: null,
      expectedTransport: descriptor.expectedTransport,
      expectedCsrf: descriptor.expectedCsrf,
      v2: descriptor,
      expectedBody: descriptor.expectedBody,
      expectedQuery: descriptor.expectedQuery,
    );
    handler.next(options);
  }

  bool _targetsConfiguredBackend(RequestOptions options, String routePath) {
    final configuredBase = _validatedBaseUrl;
    if (configuredBase == null) return false;
    final baseUri = Uri.parse(configuredBase);
    final actualUri = options.uri;
    final basePath = baseUri.path.replaceFirst(RegExp(r'/+$'), '');
    final relativePath = routePath.replaceFirst(RegExp(r'^/+'), '');
    final expectedPath = '${basePath.isEmpty ? '' : basePath}/$relativePath';
    return actualUri.origin == baseUri.origin &&
        actualUri.path == expectedPath &&
        actualUri.userInfo.isEmpty &&
        !actualUri.hasFragment;
  }

  bool _scopeMatches(_V2RequestDescriptor descriptor) {
    final route = descriptor.route;
    if (route.connectionId == null) return true;
    final scope = descriptor.scope;
    final session = descriptor.session;
    if (scope == null || session == null || !scope.belongsTo(session))
      return false;
    if (descriptor.allowDetachedScope) return route.allowDetachedScope;
    final store = descriptor.scopeStore;
    final generation = descriptor.scopeGeneration;
    return store != null &&
        generation != null &&
        store.matches(generation, scope);
  }

  bool _v2RequestCurrent(_V2RequestDescriptor descriptor) {
    final store = descriptor.sessionStore;
    final session = descriptor.session;
    if (store != null) {
      final generation = descriptor.sessionGeneration;
      final invalidatedForLogout =
          descriptor.allowSessionInvalidation && store.current == null;
      if (!invalidatedForLogout) {
        if (generation == null || store.generation != generation) return false;
        if (session != null && !store.matches(generation, session))
          return false;
        if (session == null && store.current != null) return false;
      }
    }
    return _v2AuthorityCurrent(descriptor) && _scopeMatches(descriptor);
  }

  bool _v2AuthorityCurrent(_V2RequestDescriptor descriptor) {
    final route = descriptor.route;
    final session = descriptor.session;
    if (route.requiresSession && (session == null || !session.isActive)) {
      return false;
    }
    if (route.requiresOrdinary && !(session?.canReadPrivate ?? false)) {
      return false;
    }
    if (route.requiresStepUp && !(session?.canTrade ?? false)) return false;
    return true;
  }

  String _v2FailureCode(_V2RequestDescriptor descriptor) {
    final session = descriptor.session;
    if (descriptor.sessionStore?.generation != descriptor.sessionGeneration) {
      return 'session_changed';
    }
    if (descriptor.route.requiresStepUp &&
        (session?.canReadPrivate ?? false) &&
        !(session?.canTrade ?? false)) {
      return 'step_up_required';
    }
    if (descriptor.route.requiresOrdinary &&
        !(session?.canReadPrivate ?? false)) {
      return session == null || !(session?.isActive ?? false)
          ? 'authentication_required'
          : 'restricted_session';
    }
    return 'scope_changed';
  }

  String _v2FailureMessage(_V2RequestDescriptor descriptor) {
    switch (_v2FailureCode(descriptor)) {
      case 'session_changed':
        return _sessionChanged().message;
      case 'step_up_required':
        return 'Xác minh lại bằng TOTP trước khi tiếp tục.';
      case 'restricted_session':
        return 'Hoàn tất xác thực nhiều lớp để tiếp tục.';
      case 'authentication_required':
        return _authenticationRequired().message;
      default:
        return 'Tài khoản giao dịch đã thay đổi. Hãy tải lại dữ liệu.';
    }
  }

  int _v2FailureStatus(_V2RequestDescriptor descriptor) {
    final code = _v2FailureCode(descriptor);
    if (code == 'step_up_required' || code == 'restricted_session') return 403;
    if (code == 'authentication_required' || code == 'session_changed') {
      return 401;
    }
    return 409;
  }

  bool _mayExpireSessionForUnauthorized(_V2RequestDescriptor descriptor) {
    if (!_v2RequestCurrent(descriptor)) return false;
    if (!descriptor.allowDetachedScope) return true;
    final scope = descriptor.scope;
    final store = descriptor.scopeStore;
    final generation = descriptor.scopeGeneration;
    return scope != null &&
        store != null &&
        generation != null &&
        store.matches(generation, scope);
  }

  void _validateV2Query(_V2Route route, Map<String, dynamic>? query) {
    final keys = query?.keys.toSet() ?? const <String>{};
    final allowed = route.path.startsWith('/v2/market/')
        ? const {
            'exchange',
            'product',
            'environment',
            'region',
            'instrument',
            'cursor',
            'limit',
          }
        : route.connectionId != null &&
              RegExp(r'/(balances|positions|orders)$').hasMatch(route.path)
        ? const {'product', 'instrument', 'cursor', 'limit'}
        : route.connectionId != null &&
              RegExp(r'/strategies$').hasMatch(route.path)
        ? const {'cursor', 'limit'}
        : const <String>{};
    if (!allowed.containsAll(keys)) {
      throw const BackendDataException(
        code: 'invalid_query',
        message: 'The backend query is invalid.',
      );
    }
    if (route.path == '/v2/market/ticker' &&
        (query?['instrument'] is! String ||
            query?['exchange'] is! String ||
            query?['product'] is! String ||
            query?['environment'] is! String ||
            query?['region'] is! String)) {
      throw const BackendDataException(
        code: 'invalid_query',
        message: 'The backend query is invalid.',
      );
    }
    if (route.path == '/v2/market/instruments' &&
        (query?['exchange'] is! String ||
            query?['product'] is! String ||
            query?['environment'] is! String ||
            query?['region'] is! String)) {
      throw const BackendDataException(
        code: 'invalid_query',
        message: 'The backend query is invalid.',
      );
    }
    if (route.connectionId != null &&
        RegExp(r'/(balances|positions|orders)$').hasMatch(route.path)) {
      if (query?['product'] is! String ||
          query!['product'].toString().isEmpty) {
        throw const BackendDataException(
          code: 'invalid_query',
          message: 'The backend query is invalid.',
        );
      }
    }
    final cursor = query?['cursor'];
    final limit = query?['limit'];
    if ((cursor != null && (cursor is! String || cursor.length > 2048)) ||
        (limit != null && (limit is! int || limit < 1 || limit > 200))) {
      throw const BackendDataException(
        code: 'invalid_query',
        message: 'The backend query is invalid.',
      );
    }
  }

  void _validateV2Body(_V2Route route, Object? body) {
    final allowed = route.allowedBodyKeys;
    if (allowed == null) {
      if (body != null) {
        throw const BackendDataException(
          code: 'invalid_request',
          message: 'The backend request is invalid.',
        );
      }
      return;
    }
    if (body is! Map ||
        body.keys.any((key) => key is! String || !allowed.contains(key))) {
      throw const BackendDataException(
        code: 'invalid_request',
        message: 'The backend request is invalid.',
      );
    }
    if (route.path == '/v2/login') {
      final hasTotp = _nonEmptyString(body['totp']);
      final hasRecovery = _nonEmptyString(body['recoveryCode']);
      if (!_nonEmptyString(body['username']) ||
          !_nonEmptyString(body['password']) ||
          hasTotp == hasRecovery) {
        throw const BackendDataException(
          code: 'invalid_request',
          message: 'The backend request is invalid.',
        );
      }
    }
    if (route.path == '/v2/invites/activate' &&
        (!_nonEmptyString(body['inviteToken']) ||
            !_nonEmptyString(body['username']) ||
            !_nonEmptyString(body['password']))) {
      throw const BackendDataException(
        code: 'invalid_request',
        message: 'The backend request is invalid.',
      );
    }
    if (route.path == '/v2/step-up' &&
        (!_nonEmptyString(body['password']) ||
            !_nonEmptyString(body['totp']))) {
      throw const BackendDataException(
        code: 'invalid_request',
        message: 'The backend request is invalid.',
      );
    }
    if (route.path == '/v2/mfa/enrollment/complete' &&
        (!_nonEmptyString(body['totp']) ||
            body['recoveryCodesSaved'] != true)) {
      throw const BackendDataException(
        code: 'invalid_request',
        message: 'The backend request is invalid.',
      );
    }
    if (route.path == '/v2/connections' &&
        (!_nonEmptyString(body['exchange']) ||
            !_nonEmptyString(body['environment']) ||
            !_nonEmptyString(body['region']) ||
            !_nonEmptyString(body['apiKey']) ||
            !_nonEmptyString(body['apiSecret']))) {
      throw const BackendDataException(
        code: 'invalid_request',
        message: 'The backend request is invalid.',
      );
    }
    if (route.path == '/v2/connections' &&
        body['exchange'] == 'OKX' &&
        !_nonEmptyString(body['passphrase'])) {
      throw const BackendDataException(
        code: 'invalid_request',
        message: 'The backend request is invalid.',
      );
    }
    if (route.path.endsWith('/actions/prepare')) {
      final action = body['action'];
      final identity = body['targetIdentity'];
      if (!_nonEmptyString(action) || identity is! Map) {
        throw const BackendDataException(
          code: 'invalid_request',
          message: 'The backend request is invalid.',
        );
      }
      final keys = identity.keys.toSet();
      if (action == 'close_position') {
        const required = {
          'instrumentType',
          'instrumentId',
          'positionSide',
          'marginMode',
        };
        const allowed = {...required, 'positionId', 'marginCurrency'};
        final product = identity['instrumentType'];
        final mode = identity['positionSide'];
        final marginMode = identity['marginMode'];
        final instrument = identity['instrumentId'];
        final marginCurrency = identity['marginCurrency'];
        final positionId = identity['positionId'];
        if (!keys.containsAll(required) ||
            !allowed.containsAll(keys) ||
            !{'MARGIN', 'SWAP', 'FUTURES'}.contains(product) ||
            !_nonEmptyString(instrument) ||
            instrument.length > 128 ||
            !{'net', 'long', 'short'}.contains(mode) ||
            !{'cross', 'isolated'}.contains(marginMode) ||
            (positionId != null &&
                (!_nonEmptyString(positionId) || positionId.length > 128)) ||
            (product == 'MARGIN'
                ? !_validMarginCurrency(marginCurrency)
                : marginCurrency != null)) {
          throw const BackendDataException(
            code: 'invalid_request',
            message: 'The backend request is invalid.',
          );
        }
      } else if (action == 'cancel_order') {
        const required = {
          'instType',
          'instId',
          'ordId',
          'ordType',
          'side',
          'px',
          'sz',
        };
        if (keys.length != required.length ||
            !keys.containsAll(required) ||
            !{
              'SPOT',
              'MARGIN',
              'SWAP',
              'FUTURES',
            }.contains(identity['instType']) ||
            !_nonEmptyString(identity['instId']) ||
            !_nonEmptyString(identity['ordId']) ||
            identity['ordId'].length > 128 ||
            identity['ordType'] != 'limit' ||
            !{'buy', 'sell'}.contains(identity['side']) ||
            !_positiveDecimal(identity['px']) ||
            !_positiveDecimal(identity['sz'])) {
          throw const BackendDataException(
            code: 'invalid_request',
            message: 'The backend request is invalid.',
          );
        }
      } else {
        throw const BackendDataException(
          code: 'invalid_request',
          message: 'The backend request is invalid.',
        );
      }
    }
    if (RegExp(r'/actions/[A-Za-z0-9_-]{8,64}/execute$').hasMatch(route.path) &&
        (!_nonEmptyString(body['confirmationToken']) ||
            !_nonEmptyString(body['idempotencyKey']))) {
      throw const BackendDataException(
        code: 'invalid_request',
        message: 'The backend request is invalid.',
      );
    }
    final exchange = body['exchange'];
    if (exchange == 'BINANCE' && body.containsKey('passphrase')) {
      throw const BackendDataException(
        code: 'invalid_request',
        message: 'The backend request is invalid.',
      );
    }
  }

  DioException? _validateFinalRequest(RequestOptions options) {
    final authorization = _authorizedRequests[options];
    if (authorization == null ||
        options.method.toUpperCase() != authorization.expectedMethod ||
        options.followRedirects ||
        options.maxRedirects != 0) {
      return _failure(
        options,
        code: 'route_not_registered',
        message: 'Đường dẫn dữ liệu không được đăng ký.',
      );
    }

    final actualUri = options.uri;
    if (actualUri.scheme != 'https' ||
        actualUri.origin != authorization.expectedUri.origin ||
        actualUri.path != authorization.expectedUri.path ||
        actualUri.query != authorization.expectedUri.query ||
        actualUri.userInfo.isNotEmpty ||
        actualUri.hasFragment) {
      return _failure(
        options,
        code: 'destination_forbidden',
        message: 'Đích dữ liệu backend không hợp lệ.',
      );
    }

    try {
      _rejectExchangeHeaders(options.headers);
    } on BackendDataException catch (error) {
      return _failure(options, code: error.code, message: error.message);
    }

    if (_headerCount(options.headers, 'authorization') !=
        (authorization.expectedAuthorization == null ? 0 : 1)) {
      return _failure(
        options,
        code: 'authorization_changed',
        message: 'Thông tin xác thực của yêu cầu đã thay đổi.',
      );
    }
    final actualAuthorization = _headerValue(options.headers, 'authorization');
    if (actualAuthorization != authorization.expectedAuthorization) {
      return _failure(
        options,
        code: 'authorization_changed',
        message: 'Thông tin xác thực của yêu cầu đã thay đổi.',
      );
    }
    if (_headerCount(options.headers, 'x-session-transport') !=
            (authorization.expectedTransport == null ? 0 : 1) ||
        _headerValue(options.headers, 'x-session-transport') !=
            authorization.expectedTransport ||
        _headerCount(options.headers, 'x-csrf-token') !=
            (authorization.expectedCsrf == null ? 0 : 1) ||
        _headerValue(options.headers, 'x-csrf-token') !=
            authorization.expectedCsrf) {
      return _failure(
        options,
        code: 'authorization_changed',
        message: 'Thông tin xác thực của yêu cầu đã thay đổi.',
      );
    }
    if (_fingerprint(options.queryParameters) != authorization.expectedQuery ||
        (authorization.expectedBody == null && options.data != null) ||
        _fingerprint(options.data) != authorization.expectedBody) {
      return _failure(
        options,
        code: 'request_changed',
        message: 'The backend request changed before transport.',
      );
    }
    final descriptor = authorization.v2;
    if (descriptor != null && !_v2RequestCurrent(descriptor)) {
      return _failure(
        options,
        code: _v2FailureCode(descriptor),
        message: _v2FailureMessage(descriptor),
        statusCode: _v2FailureStatus(descriptor),
      );
    }
    final sessionState = authorization.session;
    if (sessionState != null &&
        !sessionState.session.matches(
          sessionState.generation,
          sessionState.value,
        )) {
      return _failure(
        options,
        code: 'session_changed',
        message: _sessionChanged().message,
        statusCode: 401,
      );
    }
    return null;
  }

  String? _headerValue(Map<String, dynamic> headers, String normalizedName) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == normalizedName) {
        return entry.value?.toString();
      }
    }
    return null;
  }

  int _headerCount(Map<String, dynamic> headers, String normalizedName) =>
      headers.keys.where((name) => name.toLowerCase() == normalizedName).length;

  bool _nonEmptyString(Object? value) =>
      value is String && value.trim().isNotEmpty;

  bool _validMarginCurrency(Object? value) =>
      value is String && RegExp(r'^[A-Z0-9]{2,16}$').hasMatch(value);

  bool _positiveDecimal(Object? value) {
    if (value is! String ||
        value.length > 512 ||
        !RegExp(r'^\d+(?:\.\d+)?$').hasMatch(value)) {
      return false;
    }
    final parsed = double.tryParse(value);
    return parsed != null && parsed.isFinite && parsed > 0;
  }

  String? _fingerprint(Object? value) {
    if (value == null) return null;
    Object? canonicalize(Object? input) {
      if (input is Map) {
        if (input.isEmpty) return null;
        final keys = input.keys.map((key) => key.toString()).toList()..sort();
        return <String, Object?>{
          for (final key in keys) key: canonicalize(input[key]),
        };
      }
      if (input is List) {
        return input.map(canonicalize).toList(growable: false);
      }
      return input;
    }

    final canonical = canonicalize(value);
    if (canonical == null) return null;
    try {
      return jsonEncode(canonical);
    } on JsonUnsupportedObjectError {
      return 'unsupported:${identityHashCode(value)}';
    }
  }

  void _handleResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final request = response.requestOptions;
    final authorization = _authorizedRequests[request];
    final descriptor = authorization?.v2;
    if (descriptor != null && !_v2RequestCurrent(descriptor)) {
      handler.reject(
        _failure(
          request,
          code: _v2FailureCode(descriptor),
          message: _v2FailureMessage(descriptor),
          statusCode: _v2FailureStatus(descriptor),
        ),
      );
      return;
    }
    final state = authorization?.session;
    if (state != null &&
        !state.session.matches(state.generation, state.value)) {
      handler.reject(
        _failure(
          request,
          code: 'session_changed',
          message: _sessionChanged().message,
          statusCode: 401,
        ),
      );
      return;
    }
    handler.next(response);
  }

  void _handleError(DioException error, ErrorInterceptorHandler handler) {
    final authorization = _authorizedRequests[error.requestOptions];
    final descriptor = authorization?.v2;
    if (descriptor != null) {
      if (!_v2RequestCurrent(descriptor)) {
        handler.reject(
          _failure(
            error.requestOptions,
            code: _v2FailureCode(descriptor),
            message: _v2FailureMessage(descriptor),
            statusCode: _v2FailureStatus(descriptor),
          ),
        );
        return;
      }
      final session = descriptor.session;
      final store = descriptor.sessionStore;
      final generation = descriptor.sessionGeneration;
      if (error.response?.statusCode == 401 &&
          session != null &&
          store != null &&
          generation != null &&
          store.matches(generation, session) &&
          _mayExpireSessionForUnauthorized(descriptor)) {
        try {
          onV2Unauthorized?.call(store, generation, session);
        } catch (_) {
          // Preserve the sanitized transport error if the foreground owner has
          // already been disposed.
        }
        handler.reject(
          _failure(
            error.requestOptions,
            code: 'session_expired',
            message: 'Phiên giao dịch đã hết hạn. Hãy đăng nhập lại.',
            statusCode: 401,
          ),
        );
        return;
      }
      handler.next(error);
      return;
    }
    final state = authorization?.session;
    if (state == null) {
      handler.next(error);
      return;
    }

    if (error.response?.statusCode == 401 &&
        state.session.matches(state.generation, state.value)) {
      try {
        onUnauthorized?.call(state.session, state.generation, state.value);
      } catch (_) {
        // Preserve the sanitized transport error if the foreground owner has
        // already been disposed.
      }
      handler.reject(
        _failure(
          error.requestOptions,
          code: 'session_expired',
          message: 'Phiên giao dịch đã hết hạn. Hãy đăng nhập lại.',
          statusCode: 401,
        ),
      );
      return;
    }

    if (!state.session.matches(state.generation, state.value)) {
      handler.reject(
        _failure(
          error.requestOptions,
          code: 'session_changed',
          message: _sessionChanged().message,
          statusCode: 401,
        ),
      );
      return;
    }
    handler.next(error);
  }

  ({BackendDataSession session, int generation, TradeSession value})?
  _requestSession(RequestOptions options) {
    final session = options.extra[sessionExtraKey];
    final generation = options.extra[_generationExtraKey];
    final expected = options.extra[_expectedSessionExtraKey];
    if (session is! BackendDataSession ||
        generation is! int ||
        expected is! TradeSession) {
      return null;
    }
    return (session: session, generation: generation, value: expected);
  }

  DioException _failure(
    RequestOptions request, {
    required String code,
    required String message,
    int? statusCode,
  }) {
    request.extra[errorCodeExtraKey] = code;
    final response = statusCode == null
        ? null
        : Response<dynamic>(
            requestOptions: request,
            statusCode: statusCode,
            data: null,
            headers: Headers(),
          );
    return DioException(
      requestOptions: request,
      response: response,
      type: DioExceptionType.unknown,
      message: message,
    );
  }

  void _rejectForbiddenHeaders(Map<String, dynamic> headers) {
    _rejectExchangeHeaders(headers);
    if (_headerCount(headers, 'authorization') > 0) {
      throw const BackendDataException(
        code: 'exchange_credentials_forbidden',
        message: 'Không được gửi thông tin xác thực sàn qua dữ liệu backend.',
      );
    }
  }

  void _rejectExchangeHeaders(Map<String, dynamic> headers) {
    for (final name in headers.keys) {
      final normalized = name.toLowerCase();
      if (normalized.startsWith('ok-access-') ||
          normalized == 'x-simulated-trading' ||
          normalized.startsWith('x-mbx-') ||
          normalized.startsWith('x-binance-') ||
          normalized.startsWith('binance-')) {
        throw const BackendDataException(
          code: 'exchange_credentials_forbidden',
          message: 'Không được gửi thông tin xác thực sàn qua dữ liệu backend.',
        );
      }
    }
  }

  BackendDataException _authenticationRequired() => const BackendDataException(
    code: 'authentication_required',
    message: 'Vui lòng đăng nhập để xem dữ liệu tài khoản giao dịch.',
    statusCode: 401,
  );

  BackendDataException _sessionChanged() => const BackendDataException(
    code: 'session_changed',
    message: 'Phiên giao dịch đã thay đổi. Hãy tải lại dữ liệu.',
    statusCode: 401,
  );

  void close({bool force = false}) => _dio?.close(force: force);
}

class _AuthorizedRequest {
  const _AuthorizedRequest({
    required this.expectedUri,
    required this.expectedMethod,
    required this.expectedAuthorization,
    required this.session,
    required this.expectedTransport,
    required this.expectedCsrf,
    required this.v2,
    required this.expectedBody,
    required this.expectedQuery,
  });

  final Uri expectedUri;
  final String expectedMethod;
  final String? expectedAuthorization;
  final ({BackendDataSession session, int generation, TradeSession value})?
  session;
  final String? expectedTransport;
  final String? expectedCsrf;
  final _V2RequestDescriptor? v2;
  final String? expectedBody;
  final String? expectedQuery;
}

class _GuardedHttpClientAdapter implements HttpClientAdapter {
  _GuardedHttpClientAdapter({required this.delegate, required this.owner});

  final HttpClientAdapter delegate;
  final BackendDataClient owner;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final failure = owner._validateFinalRequest(options);
    if (failure != null) return Future<ResponseBody>.error(failure);
    return delegate.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) => delegate.close(force: force);
}

class BackendDataException implements Exception {
  const BackendDataException({
    required this.code,
    required this.message,
    this.statusCode,
    this.retryAfter,
  });

  final String code;
  final String message;
  final int? statusCode;
  final String? retryAfter;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}
