import 'dart:typed_data';

import 'package:dio/dio.dart';

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

class _BackendDataRoute {
  const _BackendDataRoute(this.path, {this.requiresSession = false});

  final String path;
  final bool requiresSession;
}

/// A GET-only Dio transport for the registered backend data routes.
///
/// Callers keep their legacy `/api/v5/...` paths; this client maps only those
/// exact paths onto the backend registry and retains a base URL path prefix.
class BackendDataClient {
  BackendDataClient({Dio? dio, String? baseUrl, this.onUnauthorized})
    : _baseUrl = (baseUrl ?? tradeApiBaseUrl).trim(),
      _dio = dio;

  static const String usdtVndRoute = '/v1/data/currency/usdt-vnd';
  static const String sessionExtraKey = 'backendDataSession';
  static const String errorCodeExtraKey = 'backendDataErrorCode';
  static const String _generationExtraKey = 'backendDataGeneration';
  static const String _expectedSessionExtraKey = 'backendDataExpectedSession';

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
    final expectedUri = Uri.parse(_validatedBaseUrl!).resolve(route.path);

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
      expectedAuthorization: _headerValue(options.headers, 'authorization'),
      session: _requestSession(options),
    );

    handler.next(options);
  }

  DioException? _validateFinalRequest(RequestOptions options) {
    final authorization = _authorizedRequests[options];
    if (authorization == null ||
        options.method.toUpperCase() != 'GET' ||
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

  void _handleResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final request = response.requestOptions;
    final state = _authorizedRequests[request]?.session;
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
    final state = _authorizedRequests[error.requestOptions]?.session;
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
          normalized == 'x-simulated-trading') {
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
    required this.expectedAuthorization,
    required this.session,
  });

  final Uri expectedUri;
  final String? expectedAuthorization;
  final ({BackendDataSession session, int generation, TradeSession value})?
  session;
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
