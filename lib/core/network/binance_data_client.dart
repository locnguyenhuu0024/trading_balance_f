import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/domain/binance_credential_bundle.dart';
import '../exchange/binance_read_routes.dart';
import '../security/secure_storage_helper.dart';
import 'binance_request_coordinator.dart';

final binanceDataClientProvider = Provider<BinanceDataClient>((ref) {
  final client = BinanceDataClient(
    secureStorage: ref.watch(secureStorageProvider),
    requestCoordinator: ref.watch(binanceRequestCoordinatorProvider),
  );
  ref.onDispose(client.dispose);
  return client;
});

typedef BinanceClientClock = DateTime Function();

/// Fixed-origin, GET-only Binance transport with generation and adapter fences.
class BinanceDataClient {
  BinanceDataClient({
    SecureStorageHelper? secureStorage,
    BinanceRequestCoordinator? requestCoordinator,
    Dio? dio,
    BinanceClientClock? clock,
  }) : _secureStorage = secureStorage,
       _requestCoordinator = requestCoordinator ?? BinanceRequestCoordinator(),
       _clock = clock ?? DateTime.now,
       _ownsDio = dio == null,
       _dio = dio ?? _newDio() {
    _guardedAdapter = _BinanceGuardedHttpClientAdapter(
      delegate: _dio.httpClientAdapter,
      owner: this,
    );
    _dio.httpClientAdapter = _guardedAdapter;
    _requestInterceptor = InterceptorsWrapper(onRequest: _signRequest);
    _dio.interceptors.insert(0, _requestInterceptor);
  }

  static const String spotOrigin = 'https://api.binance.com';
  static const String futuresOrigin = 'https://fapi.binance.com';
  static const int recvWindowMilliseconds = 5000;

  final SecureStorageHelper? _secureStorage;
  final BinanceRequestCoordinator _requestCoordinator;
  final BinanceClientClock _clock;
  final bool _ownsDio;
  final Dio _dio;
  final Expando<_BinanceRequestAuthorization> _authorizations =
      Expando<_BinanceRequestAuthorization>('Binance request authorization');
  final Map<BinanceHost, Duration> _serverOffsets = <BinanceHost, Duration>{};
  final Map<BinanceHost, Future<void>> _timeSyncs =
      <BinanceHost, Future<void>>{};
  late final _BinanceGuardedHttpClientAdapter _guardedAdapter;
  late final Interceptor _requestInterceptor;
  int _activeManagedGets = 0;
  bool _disposed = false;
  bool _injectedDioRestored = false;

  /// Sends one registered GET. Caller-selected origins, methods and auth flags
  /// are deliberately absent from the public interface.
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    BinanceRequestPriority priority = BinanceRequestPriority.interactive,
  }) async {
    if (_disposed) throw _clientClosed();
    _activeManagedGets++;
    try {
      final route = BinanceReadRoutes.forPath(path);
      if (route == null) throw _routeNotAllowed();
      final query = _canonicalQueryParameters(route, queryParameters);
      final callerHeaderError = _validateCallerHeaders(_dio.options.headers);
      if (callerHeaderError != null) throw callerHeaderError;

      _BinanceCredentials? credentials;
      if (route.signed) {
        credentials = await _loadCredentials();
        await _synchronizeServerTime(route.host);
        _assertCredentialsCurrent(credentials.snapshot);
      }

      final effectivePriority = route.bootstrap
          ? BinanceRequestPriority.bootstrap
          : priority == BinanceRequestPriority.bootstrap
          ? BinanceRequestPriority.interactive
          : priority;
      var timestampRetries = 0;
      while (true) {
        try {
          final response = await _sendRoute(
            route,
            query,
            credentials,
            priority: effectivePriority,
            cancelToken: cancelToken,
          );
          if (route.signed) {
            _assertCredentialsCurrent(credentials!.snapshot);
          }
          return response;
        } on BinanceDataException catch (error) {
          if (route.signed &&
              error.code == 'binance_timestamp_invalid' &&
              timestampRetries == 0) {
            timestampRetries++;
            await _synchronizeServerTime(route.host, force: true);
            _assertCredentialsCurrent(credentials!.snapshot);
            continue;
          }
          rethrow;
        }
      }
    } on BinanceDataException {
      rethrow;
    } on BinanceRequestPausedException catch (error) {
      throw _pausedError(error);
    } on DioException catch (error) {
      if (_disposed) throw _clientClosed();
      if (error.type == DioExceptionType.cancel) throw _cancelled();
      if (_isTimeout(error)) throw _timeoutError();
      throw _networkError();
    } on BinanceCredentialStorageException {
      if (_disposed) throw _clientClosed();
      throw _storageUnavailable();
    } catch (_) {
      if (_disposed) throw _clientClosed();
      throw _networkError();
    } finally {
      _finishManagedGet();
    }
  }

  BinanceDataException? _validateRequest(
    RequestOptions options,
    _BinanceRequestAuthorization? authorization, {
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
        options.uri.host != authorization.route.host.domain ||
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
    if (!authorization.route.signed) {
      if (_hasBinanceApiKeyHeader(options.headers)) return _requestForbidden();
      return null;
    }
    final snapshot = authorization.credentialSnapshot;
    if (snapshot == null || !_credentialsAreCurrent(snapshot)) {
      return _credentialsChanged();
    }
    if (requireSigned && !_matchesApiKey(options.headers, authorization)) {
      return _requestForbidden();
    }
    return null;
  }

  void _signRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_disposed) {
      handler.reject(_failure(_clientClosed()));
      return;
    }
    final authorization = _authorizations[options];
    final invalid = _validateRequest(
      options,
      authorization,
      requireSigned: false,
    );
    if (invalid != null) {
      handler.reject(_failure(invalid));
      return;
    }
    if (authorization!.route.signed) {
      options.headers['X-MBX-APIKEY'] = authorization.apiKey!;
    }
    authorization.signed = true;
    handler.next(options);
  }

  Future<Response<dynamic>> _sendRoute(
    BinanceReadRoute route,
    Map<String, String> query,
    _BinanceCredentials? credentials, {
    required BinanceRequestPriority priority,
    CancelToken? cancelToken,
  }) async {
    _throwIfDisposed();
    if (route.signed) {
      if (credentials == null) throw _credentialsChanged();
      _assertCredentialsCurrent(credentials.snapshot);
    }
    try {
      return await _requestCoordinator.run<Response<dynamic>>(
        host: route.host,
        weight: route.weightFor(query),
        priority: priority,
        request: () async {
          _throwIfDisposed();
          if (cancelToken?.isCancelled ?? false) throw _cancelled();
          final target = route.signed
              ? _signedUri(route, query, credentials!)
              : _unsignedUri(route, query);
          final authorization = _BinanceRequestAuthorization(
            expectedUri: target,
            route: route,
            credentialSnapshot: credentials?.snapshot,
            apiKey: credentials?.apiKey,
          );
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
            validateStatus: _acceptAnyHttpStatus,
            extra: <String, dynamic>{'withCredentials': false},
          );
          _authorizations[requestOptions] = authorization;
          if (route.signed) {
            _assertCredentialsCurrent(credentials!.snapshot);
          }
          try {
            final response = await _dio.fetch<dynamic>(requestOptions);
            _requestCoordinator.observeResponse(
              route.host,
              statusCode: response.statusCode,
              headers: _headersMap(response.headers),
            );
            if (response.statusCode != null &&
                response.statusCode! >= 200 &&
                response.statusCode! < 300) {
              _observeBootstrapData(route, response.data);
            }
            _throwIfDisposed();
            if (route.signed) {
              _assertCredentialsCurrent(credentials!.snapshot);
            }
            _validateResponse(response);
            return Response<dynamic>(
              requestOptions: _safeRequestOptions(),
              data: response.data,
              headers: _safeResponseHeaders(response.headers),
              statusCode: response.statusCode,
              statusMessage: response.statusMessage,
              isRedirect: response.isRedirect,
              redirects: const <RedirectRecord>[],
              extra: const <String, dynamic>{},
            );
          } on DioException catch (error) {
            _requestCoordinator.observeResponse(
              route.host,
              statusCode: error.response?.statusCode,
              headers: error.response == null
                  ? const <String, List<String>>{}
                  : _headersMap(error.response!.headers),
            );
            throw _safeTransportFailure(error);
          }
        },
      );
    } on BinanceRequestPausedException {
      rethrow;
    } on BinanceDataException {
      rethrow;
    } on DioException catch (error) {
      if (_disposed) throw _clientClosed();
      if (error.type == DioExceptionType.cancel) throw _cancelled();
      if (_isTimeout(error)) throw _timeoutError();
      throw _networkError();
    } catch (_) {
      if (_disposed) throw _clientClosed();
      throw _networkError();
    }
  }

  Future<_BinanceCredentials> _loadCredentials() async {
    final storage = _secureStorage;
    if (storage == null) throw _credentialsRequired();
    final snapshot = storage.binanceCredentialState.value;
    if (!snapshot.canUsePrivateReads) throw _credentialsChanged();
    final encoded = await storage.getBinanceCredentialBundle();
    final bundle = BinanceCredentialBundle.tryDecode(encoded);
    if (bundle == null) throw _credentialsRequired();
    final current = storage.binanceCredentialState.value;
    if (current != snapshot || !current.canUsePrivateReads) {
      throw _credentialsChanged();
    }
    return _BinanceCredentials(
      snapshot: snapshot,
      apiKey: bundle.apiKey,
      secretKey: bundle.secretKey,
    );
  }

  Future<void> _synchronizeServerTime(
    BinanceHost host, {
    bool force = false,
  }) async {
    if (!force && _serverOffsets.containsKey(host)) return;
    final existing = _timeSyncs[host];
    if (existing != null) {
      await existing;
      return;
    }
    final route = BinanceReadRoutes.forPath(_timePath(host));
    if (route == null) throw _routeNotAllowed();
    final sync = _performTimeSync(route);
    _timeSyncs[host] = sync;
    try {
      await sync;
    } finally {
      if (identical(_timeSyncs[host], sync)) _timeSyncs.remove(host);
    }
  }

  Future<void> _performTimeSync(BinanceReadRoute route) async {
    await _sendRoute(
      route,
      const <String, String>{},
      null,
      priority: BinanceRequestPriority.bootstrap,
    );
  }

  Uri _unsignedUri(BinanceReadRoute route, Map<String, String> query) {
    return Uri.https(
      route.host.domain,
      route.path,
      query.isEmpty ? null : query,
    );
  }

  Uri _signedUri(
    BinanceReadRoute route,
    Map<String, String> query,
    _BinanceCredentials credentials,
  ) {
    final timestamp = _clock()
        .toUtc()
        .add(_serverOffsets[route.host] ?? Duration.zero)
        .millisecondsSinceEpoch;
    final unsigned = <String, String>{
      ...query,
      'recvWindow': '$recvWindowMilliseconds',
      'timestamp': '$timestamp',
    };
    final sortedUnsigned = _sortQuery(unsigned);
    final unsignedUri = Uri.https(
      route.host.domain,
      route.path,
      sortedUnsigned,
    );
    final signature = Hmac(
      sha256,
      utf8.encode(credentials.secretKey),
    ).convert(utf8.encode(unsignedUri.query)).toString();
    final signedQuery = <String, String>{
      ...sortedUnsigned,
      'signature': signature,
    };
    return Uri.https(route.host.domain, route.path, signedQuery);
  }

  Map<String, String> _canonicalQueryParameters(
    BinanceReadRoute route,
    Map<String, dynamic>? queryParameters,
  ) {
    final query = queryParameters ?? const <String, dynamic>{};
    if (!route.acceptsQuery(query)) throw _queryInvalid();
    final canonical = <String, String>{};
    final keys = query.keys.toList(growable: false)..sort();
    for (final key in keys) {
      final value = query[key];
      if (value is String || value is num || value is bool) {
        canonical[key] = value.toString();
      } else if (key == 'symbols' &&
          value is List &&
          value.every((item) => item is String)) {
        canonical[key] = jsonEncode(value.cast<String>());
      } else {
        throw _queryInvalid();
      }
    }
    return canonical;
  }

  void _observeBootstrapData(BinanceReadRoute route, Object? body) {
    if (route.path.endsWith('/time')) {
      if (body is! Map || body['serverTime'] is! num) {
        throw _invalidResponse();
      }
      final serverTime = (body['serverTime'] as num).toInt();
      _serverOffsets[route.host] = Duration(
        milliseconds: serverTime - _clock().toUtc().millisecondsSinceEpoch,
      );
    } else if (route.path.endsWith('/exchangeInfo')) {
      _requestCoordinator.updateFromExchangeInfo(route.host, body);
    }
  }

  void _validateResponse(Response<dynamic> response) {
    final statusCode = response.statusCode;
    final retryAfter = response.headers.value('retry-after');
    if (statusCode == 418) {
      throw BinanceDataException(
        code: 'binance_ip_banned',
        message: 'Binance temporarily blocked reads for this host.',
        statusCode: statusCode,
        retryAfter: retryAfter,
      );
    }
    if (statusCode == 429) {
      throw BinanceDataException(
        code: 'binance_rate_limited',
        message: 'Binance read rate limit reached.',
        statusCode: statusCode,
        retryAfter: retryAfter,
      );
    }
    if (statusCode != null && statusCode >= 400) {
      final code = _exchangeCode(response.data);
      if (code == '-1021') {
        throw BinanceDataException(
          code: 'binance_timestamp_invalid',
          message: 'Binance rejected the request timestamp.',
          statusCode: statusCode,
        );
      }
      if (code == '-2014' || code == '-2015') {
        throw BinanceDataException(
          code: 'binance_authentication_failed',
          message: 'Binance rejected the API credentials.',
          statusCode: statusCode,
        );
      }
      throw BinanceDataException(
        code: 'binance_http_error',
        message: 'The Binance read request failed.',
        statusCode: statusCode,
        retryAfter: retryAfter,
      );
    }
    final code = _exchangeCode(response.data);
    if (code == null || code == '0') return;
    if (code == '-1021') {
      throw const BinanceDataException(
        code: 'binance_timestamp_invalid',
        message: 'Binance rejected the request timestamp.',
      );
    }
    if (code == '-2014' || code == '-2015') {
      throw const BinanceDataException(
        code: 'binance_authentication_failed',
        message: 'Binance rejected the API credentials.',
        statusCode: 401,
      );
    }
    throw const BinanceDataException(
      code: 'binance_api_error',
      message: 'Binance rejected the read request.',
    );
  }

  BinanceDataException _safeTransportFailure(DioException error) {
    if (error.type == DioExceptionType.cancel) return _cancelled();
    if (error.error is _TrustedBinanceTransportFailure) {
      return error.error as BinanceDataException;
    }
    final response = error.response;
    if (response == null) {
      return _isTimeout(error) ? _timeoutError() : _networkError();
    }
    final statusCode = response.statusCode;
    final retryAfter = response.headers.value('retry-after');
    if (statusCode == 418) {
      return BinanceDataException(
        code: 'binance_ip_banned',
        message: 'Binance temporarily blocked reads for this host.',
        statusCode: statusCode,
        retryAfter: retryAfter,
      );
    }
    if (statusCode == 429) {
      return BinanceDataException(
        code: 'binance_rate_limited',
        message: 'Binance read rate limit reached.',
        statusCode: statusCode,
        retryAfter: retryAfter,
      );
    }
    final code = _exchangeCode(response.data);
    if (code == '-1021') {
      return BinanceDataException(
        code: 'binance_timestamp_invalid',
        message: 'Binance rejected the request timestamp.',
        statusCode: statusCode,
      );
    }
    if (code == '-2014' || code == '-2015') {
      return BinanceDataException(
        code: 'binance_authentication_failed',
        message: 'Binance rejected the API credentials.',
        statusCode: statusCode,
      );
    }
    if (statusCode != null && statusCode >= 400) {
      return BinanceDataException(
        code: 'binance_http_error',
        message: 'The Binance read request failed.',
        statusCode: statusCode,
        retryAfter: retryAfter,
      );
    }
    return _networkError();
  }

  Headers _safeResponseHeaders(Headers headers) {
    final retryAfter = headers.value('retry-after');
    if (retryAfter == null) return Headers();
    return Headers.fromMap(<String, List<String>>{
      'retry-after': <String>[retryAfter],
    });
  }

  String? _exchangeCode(Object? body) {
    if (body is! Map) return null;
    final code = body['code'];
    return code == null ? null : code.toString();
  }

  BinanceDataException? _validateCallerHeaders(Map<String, dynamic> headers) {
    for (final name in headers.keys) {
      final normalized = name.toLowerCase();
      if (normalized == 'authorization' ||
          normalized == 'cookie' ||
          normalized == 'x-mbx-apikey' ||
          normalized == 'x-simulated-trading' ||
          normalized.startsWith('ok-access-')) {
        return _requestForbidden();
      }
    }
    return null;
  }

  BinanceDataException? _validateFinalTransportHeaders(
    Map<String, dynamic> headers,
  ) {
    for (final name in headers.keys) {
      final normalized = name.toLowerCase();
      if (normalized == 'authorization' ||
          normalized == 'cookie' ||
          normalized == 'x-simulated-trading' ||
          normalized.startsWith('ok-access-')) {
        return _requestForbidden();
      }
    }
    return null;
  }

  bool _matchesApiKey(
    Map<String, dynamic> headers,
    _BinanceRequestAuthorization authorization,
  ) {
    final matches = headers.entries
        .where((entry) => entry.key.toLowerCase() == 'x-mbx-apikey')
        .toList(growable: false);
    return matches.length == 1 &&
        matches.single.value?.toString() == authorization.apiKey;
  }

  bool _hasBinanceApiKeyHeader(Map<String, dynamic> headers) =>
      headers.keys.any((name) => name.toLowerCase() == 'x-mbx-apikey');

  bool _hasDuplicateHeaderNames(Map<String, dynamic> headers) {
    final names = <String>{};
    for (final name in headers.keys) {
      if (!names.add(name.toLowerCase())) return true;
    }
    return false;
  }

  BinanceDataException? _validateFinalRequest(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
  ) {
    final authorization = _authorizations[options];
    final validation = _validateRequest(
      options,
      authorization,
      requireSigned: true,
      requestStream: requestStream,
    );
    if (validation != null) return validation;
    if (_hasDuplicateHeaderNames(options.headers)) return _requestForbidden();
    return null;
  }

  BinanceDataException _pausedError(
    BinanceRequestPausedException error,
  ) => BinanceDataException(
    code: error.retryAt == null
        ? 'binance_budget_metadata_unavailable'
        : 'binance_host_paused',
    message: error.retryAt == null
        ? 'Binance reads are paused because valid rate-limit metadata is unavailable.'
        : 'Binance reads are paused until the host cooldown expires.',
    retryAt: error.retryAt,
  );

  BinanceDataException _routeNotAllowed() => const BinanceDataException(
    code: 'binance_route_not_allowed',
    message: 'The Binance read route is not registered.',
  );

  BinanceDataException _queryInvalid() => const BinanceDataException(
    code: 'binance_query_invalid',
    message: 'The Binance read query is invalid for this route.',
  );

  BinanceDataException _requestForbidden() => const BinanceDataException(
    code: 'binance_request_forbidden',
    message: 'The Binance read request failed validation.',
  );

  BinanceDataException _credentialsRequired() => const BinanceDataException(
    code: 'binance_credentials_required',
    message: 'Add a complete Binance API key and secret to read account data.',
    statusCode: 401,
  );

  BinanceDataException _credentialsChanged() => const BinanceDataException(
    code: 'credentials_changed',
    message: 'Binance credentials changed. Reload the requested data.',
    statusCode: 401,
  );

  BinanceDataException _storageUnavailable() => const BinanceDataException(
    code: 'binance_credentials_unavailable',
    message: 'Binance credentials are unavailable until storage recovers.',
    statusCode: 401,
  );

  BinanceDataException _invalidResponse() => const BinanceDataException(
    code: 'binance_invalid_response',
    message: 'Binance returned an invalid read response.',
  );

  BinanceDataException _networkError() => const BinanceDataException(
    code: 'binance_network_error',
    message: 'The Binance read request failed because of a network error.',
  );

  BinanceDataException _timeoutError() => const BinanceDataException(
    code: 'binance_timeout',
    message: 'The Binance read request timed out.',
  );

  bool _isTimeout(DioException error) =>
      error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.sendTimeout ||
      error.type == DioExceptionType.receiveTimeout;

  BinanceDataException _cancelled() => const BinanceDataException(
    code: 'request_cancelled',
    message: 'The Binance read request was cancelled.',
  );

  BinanceDataException _clientClosed() => const BinanceDataException(
    code: 'request_cancelled',
    message: 'The Binance read client was closed.',
  );

  DioException _failure(BinanceDataException error) => DioException(
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
    error: _TrustedBinanceTransportFailure(error),
  );

  RequestOptions _safeRequestOptions() => RequestOptions(
    path: '/<redacted>',
    method: 'GET',
    headers: <String, dynamic>{},
  );

  Map<String, String> _sortQuery(Map<String, String> query) {
    final keys = query.keys.toList(growable: false)..sort();
    return <String, String>{for (final key in keys) key: query[key]!};
  }

  String _timePath(BinanceHost host) =>
      host == BinanceHost.spot ? '/api/v3/time' : '/fapi/v1/time';

  Map<String, List<String>> _headersMap(Headers headers) {
    final result = <String, List<String>>{};
    headers.forEach((name, values) {
      result[name] = List<String>.unmodifiable(values);
    });
    return result;
  }

  static bool _acceptAnyHttpStatus(int? status) => status != null;

  static Dio _newDio() => Dio(
    BaseOptions(
      followRedirects: false,
      maxRedirects: 0,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  void dispose() {
    if (_disposed) return;
    _disposed = true;
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

  bool _credentialsAreCurrent(BinanceCredentialSnapshot expected) {
    final storage = _secureStorage;
    if (storage == null) return false;
    final current = storage.binanceCredentialState.value;
    return current == expected && current.canUsePrivateReads;
  }

  void _assertCredentialsCurrent(BinanceCredentialSnapshot expected) {
    if (!_credentialsAreCurrent(expected)) throw _credentialsChanged();
  }
}

class BinanceDataException implements Exception {
  const BinanceDataException({
    required this.code,
    required this.message,
    this.statusCode,
    this.retryAt,
    this.retryAfter,
  });

  final String code;
  final String message;
  final int? statusCode;
  final DateTime? retryAt;
  final String? retryAfter;

  @override
  String toString() => '$code: $message';
}

class _TrustedBinanceTransportFailure extends BinanceDataException {
  _TrustedBinanceTransportFailure(BinanceDataException error)
    : super(
        code: error.code,
        message: error.message,
        statusCode: error.statusCode,
        retryAt: error.retryAt,
        retryAfter: error.retryAfter,
      );
}

class _BinanceCredentials {
  const _BinanceCredentials({
    required this.snapshot,
    required this.apiKey,
    required this.secretKey,
  });

  final BinanceCredentialSnapshot snapshot;
  final String apiKey;
  final String secretKey;
}

class _BinanceRequestAuthorization {
  _BinanceRequestAuthorization({
    required this.expectedUri,
    required this.route,
    this.credentialSnapshot,
    this.apiKey,
  });

  final Uri expectedUri;
  final BinanceReadRoute route;
  final BinanceCredentialSnapshot? credentialSnapshot;
  final String? apiKey;
  bool signed = false;
}

class _BinanceGuardedHttpClientAdapter implements HttpClientAdapter {
  _BinanceGuardedHttpClientAdapter({
    required this.delegate,
    required this.owner,
  });

  final HttpClientAdapter delegate;
  final BinanceDataClient owner;

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
