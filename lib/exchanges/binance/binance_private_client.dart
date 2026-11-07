import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/exchange/exchange_models.dart';
import '../../core/network/foreground_read_gate.dart';
import '../../core/network/request_coordinator.dart';
import '../../core/security/secure_storage_helper.dart';

class BinanceKeyBundle {
  BinanceKeyBundle({required this.apiKey, required this.apiSecret}) {
    if (apiKey.trim().isEmpty || apiSecret.trim().isEmpty) {
      throw ArgumentError('Binance keys must not be empty.');
    }
  }
  final String apiKey;
  final String apiSecret;
}

class BinancePrivateException implements Exception {
  const BinancePrivateException(this.failure, {this.code});
  final ExchangeFailure failure;
  final int? code;
  @override
  String toString() => 'Binance private read failed (${failure.kind.name}).';
}

String normalizeBinanceProxyBaseUrl(String value) {
  final trimmed = value.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.userInfo.isNotEmpty) {
    return '';
  }
  return trimmed.replaceFirst(RegExp(r'/+$'), '');
}

class BinancePrivateClient {
  BinancePrivateClient({
    required this.keys,
    required this.credentialState,
    required this.coordinator,
    required this.isWeb,
    String proxyBaseUrl = '',
    Dio? dio,
    DateTime Function()? clock,
  }) : proxyBaseUrl = normalizeBinanceProxyBaseUrl(proxyBaseUrl),
       _dio = dio ?? Dio(),
       _clock = clock ?? DateTime.now;

  final BinanceKeyBundle keys;
  final ValueListenable<OkxCredentialSnapshot> credentialState;
  final RequestCoordinator coordinator;
  final bool isWeb;
  final String proxyBaseUrl;
  bool get spotMarginAvailable => !isWeb || proxyBaseUrl.isNotEmpty;
  final Dio _dio;
  final DateTime Function() _clock;
  final Map<String, int> _offsets = {};

  static const _privatePaths = {
    '/fapi/v3/account',
    '/fapi/v2/account',
    '/fapi/v3/positionRisk',
    '/fapi/v1/openOrders',
    '/fapi/v1/allOrders',
    '/api/v3/account',
    '/api/v3/myTrades',
    '/api/v3/openOrders',
    '/api/v3/allOrders',
    '/sapi/v1/margin/account',
    '/sapi/v1/margin/myTrades',
    '/sapi/v1/margin/isolated/account',
    '/sapi/v1/margin/openOrders',
    '/sapi/v1/margin/allOrders',
  };
  static const _timePaths = {'/fapi/v1/time', '/api/v3/time'};

  static String signature(String secret, String query) =>
      Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(query)).toString();

  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic> queryParameters = const {},
  }) async {
    if (!_privatePaths.contains(path) && !_timePaths.contains(path)) {
      throw ArgumentError('Binance route is not allowed.');
    }
    if (queryParameters.keys.any(
      (key) => const {'signature', 'timestamp', 'recvWindow'}.contains(key),
    )) {
      throw ArgumentError('Reserved query parameter.');
    }
    if (!spotMarginAvailable &&
        _privatePaths.contains(path) &&
        !path.startsWith('/fapi/')) {
      throw const BinancePrivateException(
        ExchangeFailure(ExchangeFailureKind.unavailableOnPlatform),
      );
    }
    final snapshot = credentialState.value;
    _checkGeneration(snapshot);
    final host = path.startsWith('/fapi/')
        ? 'https://fapi.binance.com'
        : 'https://api.binance.com';
    final timePath = path.startsWith('/fapi/')
        ? '/fapi/v1/time'
        : '/api/v3/time';
    // No credentials or user-provided parameter values are kept in scheduler keys.
    final query = Uri(
      queryParameters: queryParameters.map(
        (key, value) => MapEntry(key, '$value'),
      ),
    ).query;
    final scheduleKey = '$path:$query:${snapshot.generation}';
    try {
      final result = await coordinator.run<Response<dynamic>>(
        lane: RequestLane.authenticated,
        key: scheduleKey,
        request: () async {
          _checkGeneration(snapshot);
          if (_timePaths.contains(path))
            return _fetchTime(host, path, snapshot);
          if (!_offsets.containsKey(host))
            await _fetchTime(host, timePath, snapshot);
          for (var attempt = 0; ; attempt++) {
            _checkGeneration(snapshot);
            final timestamp = _clock().millisecondsSinceEpoch + _offsets[host]!;
            final signedQuery = [
              if (query.isNotEmpty) query,
              'recvWindow=5000',
              'timestamp=$timestamp',
            ].join('&');
            final requestHost = isWeb && !path.startsWith('/fapi/')
                ? proxyBaseUrl
                : host;
            final uri =
                '$requestHost$path?$signedQuery&signature=${signature(keys.apiSecret, signedQuery)}';
            try {
              return await _fetch(uri, snapshot, authenticated: true);
            } on BinancePrivateException catch (error) {
              if (error.code == -1021 && attempt == 0) {
                await _fetchTime(host, timePath, snapshot);
                continue;
              }
              rethrow;
            }
          }
        },
      );
      _checkGeneration(snapshot);
      return result;
    } on RequestBackoffException catch (error) {
      _checkGeneration(snapshot);
      throw BinancePrivateException(
        ExchangeFailure(
          ExchangeFailureKind.transient,
          retryAfter: error.retryAfter,
        ),
      );
    } catch (_) {
      _checkGeneration(snapshot);
      rethrow;
    }
  }

  void _checkGeneration(OkxCredentialSnapshot snapshot) {
    if (snapshot.rotating || credentialState.value != snapshot) {
      throw const BinancePrivateException(
        ExchangeFailure(ExchangeFailureKind.cancellation),
      );
    }
  }

  Future<Response<dynamic>> _fetchTime(
    String host,
    String path,
    OkxCredentialSnapshot snapshot,
  ) async {
    final response = await _fetch('$host$path', snapshot, authenticated: false);
    final data = response.data;
    final serverTime = data is Map ? data['serverTime'] : null;
    if (serverTime is! int)
      throw const BinancePrivateException(
        ExchangeFailure(ExchangeFailureKind.other),
      );
    _checkGeneration(snapshot);
    _offsets[host] = serverTime - _clock().millisecondsSinceEpoch;
    return response;
  }

  Future<Response<dynamic>> _fetch(
    String uri,
    OkxCredentialSnapshot snapshot, {
    required bool authenticated,
  }) async {
    _checkGeneration(snapshot);
    Response<dynamic> response;
    try {
      response = await _dio.get<dynamic>(
        uri,
        options: Options(
          headers: authenticated
              ? {'X-MBX-APIKEY': keys.apiKey}
              : <String, dynamic>{},
          validateStatus: (_) => true,
        ),
      );
    } catch (_) {
      _checkGeneration(snapshot);
      throw const BinancePrivateException(
        ExchangeFailure(ExchangeFailureKind.transient),
      );
    }
    _checkGeneration(snapshot);
    final status = response.statusCode ?? 0;
    final data = response.data;
    final rawCode = data is Map ? data['code'] : null;
    final code = rawCode is int ? rawCode : int.tryParse('$rawCode');
    if (status >= 200 && status < 300 && (code == null || code >= 0))
      return response;
    final retryAfter = ForegroundReadGate.parseRetryAfter(
      response.headers.value('retry-after'),
      _clock(),
    );
    if (status != 403 &&
        status != 451 &&
        (status == 429 || status == 418 || code == -1003)) {
      final duration =
          status == 418 &&
              (retryAfter == null || retryAfter < const Duration(minutes: 2))
          ? const Duration(minutes: 2)
          : retryAfter;
      // Feed a sanitized rate-limit response to the existing lane scheduler.
      throw DioException(
        requestOptions: RequestOptions(path: 'binance-rate-limit'),
        response: Response(
          requestOptions: RequestOptions(path: 'binance-rate-limit'),
          statusCode: 429,
          headers: Headers.fromMap({
            if (duration != null) 'retry-after': ['${duration.inSeconds}'],
          }),
        ),
      );
    }
    final kind = status == 403 || status == 451
        ? ExchangeFailureKind.other
        : status == 401 || const {-2014, -2015, -2008}.contains(code)
        ? ExchangeFailureKind.credential
        : status >= 500 || status == 0
        ? ExchangeFailureKind.transient
        : ExchangeFailureKind.other;
    throw BinancePrivateException(
      ExchangeFailure(kind, retryAfter: retryAfter),
      code: code,
    );
  }
}
