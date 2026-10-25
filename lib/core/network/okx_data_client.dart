import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../security/secure_storage_helper.dart';
import 'backend_data_client.dart';
import 'okx_interceptor.dart';
import 'request_coordinator.dart';

final okxDataClientProvider = Provider<OkxDataClient>((ref) {
  final client = OkxDataClient(
    secureStorage: ref.watch(secureStorageProvider),
    requestCoordinator: ref.watch(requestCoordinatorProvider),
  );
  ref.onDispose(client.dispose);
  return client;
});

/// Direct, fixed-origin, GET-only transport for approved native OKX routes.
/// Public requests do not read credential storage. Private requests are signed
/// from one immutable credential generation and fenced again at the adapter.
class OkxDataClient {
  OkxDataClient({
    SecureStorageHelper? secureStorage,
    RequestCoordinator? requestCoordinator,
    Dio? dio,
  }) : _secureStorage = secureStorage,
       _requestCoordinator = requestCoordinator ?? RequestCoordinator(),
       _ownsDio = dio == null,
       _dio = dio ?? _newDio() {
    _guardedAdapter = _OkxGuardedHttpClientAdapter(
      delegate: _dio.httpClientAdapter,
      owner: this,
    );
    _dio.httpClientAdapter = _guardedAdapter;
    _requestInterceptor = InterceptorsWrapper(onRequest: _signRequest);
    // Run the signer before any interceptor already present on an injected Dio.
    // The adapter verifies the signed request after all later interceptors.
    _dio.interceptors.insert(0, _requestInterceptor);
  }

  static const String origin = 'https://www.okx.com';

  static final Map<String, bool> _privateRoutes = <String, bool>{
    '/api/v5/public/instruments': false,
    '/api/v5/market/ticker': false,
    '/api/v5/market/tickers': false,
    '/api/v5/market/candles': false,
    '/api/v5/market/history-candles': false,
    '/api/v5/public/funding-rate': false,
    '/api/v5/public/open-interest': false,
    '/api/v5/account/balance': true,
    '/api/v5/account/positions': true,
    '/api/v5/trade/orders-pending': true,
    '/api/v5/trade/orders-history': true,
    '/api/v5/account/config': true,
    '/api/v5/account/instruments': true,
    '/api/v5/account/trade-fee': true,
    '/api/v5/account/interest-rate': true,
    '/api/v5/account/interest-accrued': true,
  };

  final SecureStorageHelper? _secureStorage;
  final RequestCoordinator _requestCoordinator;
  final bool _ownsDio;
  final Dio _dio;
  final Expando<_OkxRequestAuthorization> _authorizations =
      Expando<_OkxRequestAuthorization>('OKX request authorization');
  final Expando<int> _cancelOwners = Expando<int>('OKX cancel owner');
  int _nextCancelOwner = 0;
  ValueListenable<OkxCredentialSnapshot>? _credentialState;
  late final _OkxGuardedHttpClientAdapter _guardedAdapter;
  late final Interceptor _requestInterceptor;
  int _activeManagedGets = 0;
  bool _disposed = false;
  bool _injectedDioRestored = false;

  /// Makes one approved GET request. Query encoding is canonicalized and then
  /// used verbatim for signing and final-adapter verification.
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    if (_disposed) throw _clientClosed();
    _activeManagedGets++;
    try {
      final isPrivate = _privateRoutes[path];
      if (isPrivate == null) {
        throw const OkxDataException(
          code: 'okx_route_not_allowed',
          message: 'The OKX read route is not registered.',
        );
      }

      final target = _targetUri(path, queryParameters);
      final credentials = isPrivate ? await _loadCredentials() : null;
      _throwIfDisposed();
      final requestOptions = RequestOptions(
        path: target.toString(),
        baseUrl: '',
        method: 'GET',
        headers: <String, dynamic>{..._dio.options.headers},
        queryParameters: const <String, dynamic>{},
        cancelToken: cancelToken,
        followRedirects: false,
        maxRedirects: 0,
        connectTimeout: _dio.options.connectTimeout,
        sendTimeout: _dio.options.sendTimeout,
        receiveTimeout: _dio.options.receiveTimeout,
        responseType: ResponseType.json,
        validateStatus: _acceptSuccessfulStatus,
        extra: <String, dynamic>{'withCredentials': false},
      );
      final authorization = _OkxRequestAuthorization(
        expectedUri: target,
        isPrivate: isPrivate,
        credentialSnapshot: credentials?.snapshot,
        apiKey: credentials?.apiKey,
        secretKey: credentials?.secretKey,
        passphrase: credentials?.passphrase,
      );
      _authorizations[requestOptions] = authorization;

      if (!isPrivate) {
        return await _send(requestOptions, authorization);
      }

      final ownerId = cancelToken == null
          ? 'uncancelled'
          : _cancelOwnerId(cancelToken).toString();
      final key =
          '${credentials!.snapshot.generation}|${_requestTarget(target)}|$ownerId';
      return await _requestCoordinator.run<Response<dynamic>>(
        lane: RequestLane.authenticated,
        key: key,
        request: () async {
          _throwIfDisposed();
          return _send(requestOptions, authorization);
        },
      );
    } catch (_) {
      if (_disposed) throw _clientClosed();
      rethrow;
    } finally {
      _finishManagedGet();
    }
  }

  Future<Response<dynamic>> _send(
    RequestOptions options,
    _OkxRequestAuthorization authorization,
  ) async {
    try {
      _throwIfDisposed();
      _assertCurrentCredentials(authorization);
      final response = await _dio.fetch<dynamic>(options);
      _throwIfDisposed();
      _assertCurrentCredentials(authorization);
      _validateResponse(response);
      return response;
    } on DioException catch (error) {
      if (_disposed) throw _clientClosed();
      if (authorization.isPrivate && !_credentialsAreCurrent(authorization)) {
        throw _credentialsChanged();
      }
      final contained = error.error;
      if (contained is OkxDataException) throw contained;
      if (error.type == DioExceptionType.cancel) {
        throw const OkxDataException(
          code: 'request_cancelled',
          message: 'The OKX read request was cancelled.',
        );
      }
      throw _sanitizeDioError(error);
    } catch (_) {
      if (_disposed) throw _clientClosed();
      if (authorization.isPrivate && !_credentialsAreCurrent(authorization)) {
        throw _credentialsChanged();
      }
      rethrow;
    }
  }

  Future<_OkxCredentials> _loadCredentials() async {
    final storage = _secureStorage;
    if (storage == null) throw _credentialsRequired();
    _listenForCredentialChanges(storage);
    final snapshot = storage.okxCredentialState.value;
    if (snapshot.rotating) throw _credentialsChanged();

    try {
      final values = await Future.wait<String?>(<Future<String?>>[
        storage.getOkxApiKey(),
        storage.getOkxSecretKey(),
        storage.getOkxPassphrase(),
      ]);
      if (!_snapshotIsCurrent(storage, snapshot)) throw _credentialsChanged();
      final apiKey = values[0];
      final secretKey = values[1];
      final passphrase = values[2];
      if (apiKey == null ||
          apiKey.trim().isEmpty ||
          secretKey == null ||
          secretKey.trim().isEmpty ||
          passphrase == null ||
          passphrase.trim().isEmpty) {
        throw _credentialsRequired();
      }
      return _OkxCredentials(
        snapshot: snapshot,
        apiKey: apiKey,
        secretKey: secretKey,
        passphrase: passphrase,
      );
    } on OkxDataException {
      rethrow;
    } catch (_) {
      if (!_snapshotIsCurrent(storage, snapshot)) throw _credentialsChanged();
      throw const OkxDataException(
        code: 'okx_credentials_unavailable',
        message: 'Stored OKX credentials could not be loaded.',
        statusCode: 401,
      );
    }
  }

  void _listenForCredentialChanges(SecureStorageHelper storage) {
    if (_credentialState != null) return;
    _credentialState = storage.okxCredentialState;
    _credentialState!.addListener(_onCredentialStateChanged);
  }

  void _onCredentialStateChanged() {
    _requestCoordinator.clearLane(RequestLane.authenticated);
  }

  bool _snapshotIsCurrent(
    SecureStorageHelper storage,
    OkxCredentialSnapshot expected,
  ) {
    final current = storage.okxCredentialState.value;
    return !current.rotating && current.generation == expected.generation;
  }

  bool _credentialsAreCurrent(_OkxRequestAuthorization authorization) {
    if (!authorization.isPrivate) return true;
    final storage = _secureStorage;
    final expected = authorization.credentialSnapshot;
    if (storage == null || expected == null) return false;
    return _snapshotIsCurrent(storage, expected);
  }

  void _assertCurrentCredentials(_OkxRequestAuthorization authorization) {
    if (!_credentialsAreCurrent(authorization)) throw _credentialsChanged();
  }

  void _signRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_disposed) {
      handler.reject(_failure(_clientClosed()));
      return;
    }
    final authorization = _authorizations[options];
    if (authorization == null) {
      handler.reject(_failure(_requestForbidden()));
      return;
    }
    final invalid = _validateRequest(
      options,
      authorization,
      requireSigned: false,
    );
    if (invalid != null) {
      handler.reject(_failure(invalid));
      return;
    }
    if (authorization.isPrivate) {
      final snapshot = authorization.credentialSnapshot!;
      final timestamp = OkxRequestSigner.timestamp(DateTime.now().toUtc());
      final signature = OkxRequestSigner.signature(
        timestamp: timestamp,
        method: 'GET',
        requestPath: _requestTarget(authorization.expectedUri),
        body: '',
        secretKey: authorization.secretKey!,
      );
      final headers = <String, String>{
        'OK-ACCESS-KEY': authorization.apiKey!,
        'OK-ACCESS-SIGN': signature,
        'OK-ACCESS-TIMESTAMP': timestamp,
        'OK-ACCESS-PASSPHRASE': authorization.passphrase!,
      };
      options.headers.addAll(headers);
      authorization.signedHeaders = Map<String, String>.unmodifiable(headers);
      authorization.signedGeneration = snapshot.generation;
      authorization.signed = true;
    } else {
      authorization.signed = true;
    }
    handler.next(options);
  }

  OkxDataException? _validateRequest(
    RequestOptions options,
    _OkxRequestAuthorization? authorization, {
    required bool requireSigned,
    Stream<Uint8List>? requestStream,
  }) {
    if (_disposed) return _clientClosed();
    if (authorization == null ||
        options.method != 'GET' ||
        options.followRedirects ||
        options.maxRedirects != 0 ||
        options.data != null ||
        requestStream != null ||
        options.uri.toString() != authorization.expectedUri.toString() ||
        options.uri.scheme != 'https' ||
        options.uri.host != 'www.okx.com' ||
        options.uri.userInfo.isNotEmpty ||
        options.uri.hasFragment ||
        options.extra['withCredentials'] != false) {
      return _requestForbidden();
    }
    final headerFailure = requireSigned
        ? _validateFinalTransportHeaders(options.headers)
        : _validateCallerHeaders(options.headers);
    if (headerFailure != null) return headerFailure;
    if (requireSigned && !authorization.signed) return _requestForbidden();

    if (!authorization.isPrivate) {
      if (_hasOkxCredentialHeaders(options.headers)) return _requestForbidden();
      return null;
    }
    if (!_credentialsAreCurrent(authorization) ||
        (requireSigned &&
            authorization.signedGeneration !=
                authorization.credentialSnapshot?.generation)) {
      return _credentialsChanged();
    }
    if (requireSigned &&
        !_matchesSignedHeaders(options.headers, authorization)) {
      return _requestForbidden();
    }
    return null;
  }

  OkxDataException? _validateCallerHeaders(Map<String, dynamic> headers) {
    for (final name in headers.keys) {
      final normalized = name.toLowerCase();
      if (normalized == 'authorization' ||
          normalized == 'cookie' ||
          normalized == 'x-simulated-trading' ||
          normalized == 'x-mbx-apikey' ||
          normalized.startsWith('ok-access-')) {
        return _requestForbidden();
      }
    }
    return null;
  }

  OkxDataException? _validateFinalTransportHeaders(
    Map<String, dynamic> headers,
  ) {
    for (final name in headers.keys) {
      final normalized = name.toLowerCase();
      if (normalized == 'authorization' ||
          normalized == 'cookie' ||
          normalized == 'x-simulated-trading' ||
          normalized == 'x-mbx-apikey') {
        return _requestForbidden();
      }
    }
    return null;
  }

  bool _matchesSignedHeaders(
    Map<String, dynamic> headers,
    _OkxRequestAuthorization authorization,
  ) {
    final expected = authorization.signedHeaders;
    if (expected == null || _hasDuplicateHeaderNames(headers)) return false;
    for (final entry in expected.entries) {
      final matches = headers.entries
          .where(
            (candidate) =>
                candidate.key.toLowerCase() == entry.key.toLowerCase(),
          )
          .toList(growable: false);
      if (matches.length != 1 ||
          matches.single.value?.toString() != entry.value) {
        return false;
      }
    }
    return _headerCount(headers, 'ok-access-') == expected.length;
  }

  bool _hasOkxCredentialHeaders(Map<String, dynamic> headers) =>
      headers.keys.any((name) => name.toLowerCase().startsWith('ok-access-'));

  int _headerCount(Map<String, dynamic> headers, String prefix) => headers.keys
      .where((name) => name.toLowerCase().startsWith(prefix))
      .length;

  bool _hasDuplicateHeaderNames(Map<String, dynamic> headers) {
    final names = <String>{};
    for (final name in headers.keys) {
      if (!names.add(name.toLowerCase())) return true;
    }
    return false;
  }

  OkxDataException? _validateFinalRequest(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
  ) {
    final authorization = _authorizations[options];
    return _validateRequest(
      options,
      authorization,
      requireSigned: true,
      requestStream: requestStream,
    );
  }

  void _validateResponse(Response<dynamic> response) {
    final statusCode = response.statusCode;
    final retryAfter = response.headers.value('retry-after');
    if (statusCode == 401) {
      throw _authenticationFailure(retryAfter: retryAfter);
    }
    if (statusCode != null && statusCode >= 400) {
      throw _httpFailure(statusCode, retryAfter: retryAfter);
    }
    final body = response.data;
    if (body is! Map) return;
    final rawCode = body['code'];
    if (rawCode == null || rawCode.toString() == '0') return;
    final exchangeCode = rawCode.toString();
    if (exchangeCode == '50011') {
      throw OkxDataException(
        code: 'okx_rate_limited',
        message: 'OKX read rate limit reached.',
        statusCode: 429,
        retryAfter: retryAfter,
      );
    }
    if (exchangeCode == '50102') {
      throw const OkxDataException(
        code: 'okx_timestamp_invalid',
        message: 'Synchronize this device clock before retrying the OKX read.',
        statusCode: 401,
      );
    }
    if (_authenticationEnvelopeCodes.contains(exchangeCode)) {
      throw _authenticationFailure(retryAfter: retryAfter);
    }
    throw OkxDataException(
      code: 'okx_api_error',
      message: 'OKX rejected the read request.',
      statusCode: statusCode,
      retryAfter: retryAfter,
    );
  }

  static const Set<String> _authenticationEnvelopeCodes = <String>{
    '50103',
    '50104',
    '50105',
    '50106',
    '50107',
    '50111',
    '50112',
    '50113',
  };

  OkxDataException _sanitizeDioError(DioException error) {
    final statusCode = error.response?.statusCode;
    final retryAfter = error.response?.headers.value('retry-after');
    if (statusCode == 401) {
      return _authenticationFailure(retryAfter: retryAfter);
    }
    if (statusCode == 429) return _httpFailure(429, retryAfter: retryAfter);
    if (statusCode != null) {
      return _httpFailure(statusCode, retryAfter: retryAfter);
    }
    return OkxDataException(
      code: 'okx_network_error',
      message: 'The OKX read request failed because of a network error.',
      networkType: error.type,
    );
  }

  OkxDataException _httpFailure(int statusCode, {String? retryAfter}) =>
      OkxDataException(
        code: statusCode == 429 ? 'okx_rate_limited' : 'okx_http_error',
        message: statusCode == 429
            ? 'OKX read rate limit reached.'
            : 'The OKX read request failed.',
        statusCode: statusCode,
        retryAfter: retryAfter,
      );

  OkxDataException _authenticationFailure({String? retryAfter}) =>
      OkxDataException(
        code: 'okx_authentication_failed',
        message: 'OKX rejected the API credentials.',
        statusCode: 401,
        retryAfter: retryAfter,
      );

  OkxDataException _credentialsRequired() => const OkxDataException(
    code: 'okx_credentials_required',
    message: 'Add valid OKX API credentials to read account data.',
    statusCode: 401,
  );

  OkxDataException _credentialsChanged() => const OkxDataException(
    code: 'credentials_changed',
    message: 'OKX credentials changed. Reload the requested data.',
    statusCode: 401,
  );

  OkxDataException _requestForbidden() => const OkxDataException(
    code: 'okx_request_forbidden',
    message: 'The OKX read request failed validation.',
  );

  DioException _failure(OkxDataException error) => DioException(
    requestOptions: _safeRequestOptions(),
    response: error.statusCode == null
        ? null
        : Response<dynamic>(
            requestOptions: _safeRequestOptions(),
            statusCode: error.statusCode,
            headers: Headers(),
          ),
    type: DioExceptionType.unknown,
    message: error.message,
    error: error,
  );

  RequestOptions _safeRequestOptions() => RequestOptions(
    path: '/api/v5/<redacted>',
    method: 'GET',
    headers: <String, dynamic>{},
  );

  int _cancelOwnerId(CancelToken token) {
    final existing = _cancelOwners[token];
    if (existing != null) return existing;
    final next = ++_nextCancelOwner;
    _cancelOwners[token] = next;
    return next;
  }

  static Uri _targetUri(String path, Map<String, dynamic>? queryParameters) {
    if (!path.startsWith('/api/v5/') ||
        path.contains('?') ||
        path.contains('#') ||
        path.contains('://')) {
      throw const OkxDataException(
        code: 'okx_route_not_allowed',
        message: 'The OKX read route is not registered.',
      );
    }
    if (!_privateRoutes.containsKey(path)) {
      throw const OkxDataException(
        code: 'okx_route_not_allowed',
        message: 'The OKX read route is not registered.',
      );
    }
    return Uri.https(
      'www.okx.com',
      path,
      _canonicalQueryParameters(queryParameters),
    );
  }

  static Map<String, dynamic>? _canonicalQueryParameters(
    Map<String, dynamic>? queryParameters,
  ) {
    if (queryParameters == null || queryParameters.isEmpty) return null;
    final entries = queryParameters.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    final canonical = <String, dynamic>{};
    for (final entry in entries) {
      final value = entry.value;
      if (value == null) continue;
      if (value is String || value is num || value is bool) {
        canonical[entry.key] = value.toString();
        continue;
      }
      if (value is Iterable) {
        final items = <String>[];
        for (final item in value) {
          if (item is! String && item is! num && item is! bool) {
            throw const OkxDataException(
              code: 'okx_query_invalid',
              message: 'The OKX read query is invalid.',
            );
          }
          items.add(item.toString());
        }
        canonical[entry.key] = items;
        continue;
      }
      throw const OkxDataException(
        code: 'okx_query_invalid',
        message: 'The OKX read query is invalid.',
      );
    }
    return canonical.isEmpty ? null : canonical;
  }

  static String _requestTarget(Uri uri) =>
      '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}';

  static bool _acceptSuccessfulStatus(int? status) =>
      status != null && status >= 200 && status < 300;

  static Dio _newDio() => Dio(
    BaseOptions(
      baseUrl: origin,
      followRedirects: false,
      maxRedirects: 0,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _credentialState?.removeListener(_onCredentialStateChanged);
    if (_ownsDio) {
      _dio.close(force: true);
      return;
    }
    if (_activeManagedGets == 0) _restoreInjectedDio();
  }

  void _finishManagedGet() {
    _activeManagedGets--;
    if (_disposed && !_ownsDio && _activeManagedGets == 0) {
      _restoreInjectedDio();
    }
  }

  void _restoreInjectedDio() {
    if (_injectedDioRestored) return;
    _injectedDioRestored = true;
    _dio.interceptors.remove(_requestInterceptor);
    if (identical(_dio.httpClientAdapter, _guardedAdapter)) {
      _dio.httpClientAdapter = _guardedAdapter.delegate;
    }
  }

  void _throwIfDisposed() {
    if (_disposed) throw _clientClosed();
  }

  OkxDataException _clientClosed() => const OkxDataException(
    code: 'request_cancelled',
    message: 'The OKX read client was closed.',
  );
}

/// Compatible with RequestCoordinator while keeping transport messages safe.
class OkxDataException extends BackendDataException {
  const OkxDataException({
    required super.code,
    required super.message,
    super.statusCode,
    super.retryAfter,
    this.networkType,
  });

  final DioExceptionType? networkType;
}

class _OkxCredentials {
  const _OkxCredentials({
    required this.snapshot,
    required this.apiKey,
    required this.secretKey,
    required this.passphrase,
  });

  final OkxCredentialSnapshot snapshot;
  final String apiKey;
  final String secretKey;
  final String passphrase;
}

class _OkxRequestAuthorization {
  _OkxRequestAuthorization({
    required this.expectedUri,
    required this.isPrivate,
    required this.credentialSnapshot,
    required this.apiKey,
    required this.secretKey,
    required this.passphrase,
  });

  final Uri expectedUri;
  final bool isPrivate;
  final OkxCredentialSnapshot? credentialSnapshot;
  final String? apiKey;
  final String? secretKey;
  final String? passphrase;
  Map<String, String>? signedHeaders;
  int? signedGeneration;
  bool signed = false;
}

class _OkxGuardedHttpClientAdapter implements HttpClientAdapter {
  _OkxGuardedHttpClientAdapter({required this.delegate, required this.owner});

  final HttpClientAdapter delegate;
  final OkxDataClient owner;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final failure = owner._validateFinalRequest(options, requestStream);
    if (failure != null) {
      return Future<ResponseBody>.error(owner._failure(failure));
    }
    return delegate.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) => delegate.close(force: force);
}
