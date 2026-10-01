import 'package:dio/dio.dart';

import 'okx_position_model.dart';

const tradeApiBaseUrl = String.fromEnvironment('TRADE_API_BASE_URL');

abstract class TradeApi {
  bool get isConfigured;

  Future<TradeSession> login({required String password, required String totp});

  Future<void> logout(String bearerToken);

  Future<TradePositionsSnapshot> getPositions(String bearerToken);

  Future<PreparedTradeAction> prepare(
    String bearerToken, {
    required String action,
    Map<String, dynamic>? targetIdentity,
    String? amount,
    String? size,
    String? percentage,
  });

  Future<TradeOperationResult> execute(
    String bearerToken, {
    required String operationId,
    required String confirmationToken,
  });

  Future<TradeOperationResult> getResult(
    String bearerToken,
    String operationId,
  );
}

class TradeApiClient implements TradeApi {
  TradeApiClient({Dio? dio, String? baseUrl})
    : _baseUrl = (baseUrl ?? tradeApiBaseUrl).trim(),
      _dio = dio;

  final String _baseUrl;
  Dio? _dio;

  @override
  bool get isConfigured => _validatedBaseUrl != null;

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
      // Accessing `port` also validates any explicit port in the URI.
      uri.port;
      return uri.toString().endsWith('/')
          ? uri.toString()
          : '${uri.toString()}/';
    } on FormatException {
      return null;
    }
  }

  Dio get _client {
    final client = _dio ??= Dio(
      BaseOptions(
        baseUrl: _validatedBaseUrl!,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 10),
        headers: const {'Content-Type': 'application/json'},
      ),
    );
    // A caller-supplied Dio is useful for adapters/interceptors, but it must
    // never override the validated endpoint with an insecure base URL.
    client.options.baseUrl = _validatedBaseUrl!;
    return client;
  }

  @override
  Future<TradeSession> login({
    required String password,
    required String totp,
  }) async {
    final data = await _request(
      'POST',
      'v1/login',
      body: {'password': password, 'totp': totp},
    );
    final token = _string(data['token']);
    final expiresAt = DateTime.tryParse(_string(data['expiresAt']));
    if (token.isEmpty || expiresAt == null) {
      throw const TradeApiException(
        code: 'invalid_response',
        message: 'The trade API returned an incomplete login response.',
      );
    }
    return TradeSession(
      bearerToken: token,
      accountIdentifier: _string(data['accountIdentifier']),
      expiresAt: expiresAt,
    );
  }

  @override
  Future<void> logout(String bearerToken) async {
    await _request(
      'POST',
      'v1/logout',
      bearerToken: bearerToken,
      body: const {},
    );
  }

  @override
  Future<TradePositionsSnapshot> getPositions(String bearerToken) async {
    final data = await _request(
      'GET',
      'v1/positions',
      bearerToken: bearerToken,
    );
    final rawPositions = data['positions'];
    if (rawPositions is! List) {
      throw const TradeApiException(
        code: 'invalid_response',
        message: 'The trade API returned an invalid position list.',
      );
    }
    return TradePositionsSnapshot(
      accountIdentifier: _string(data['accountIdentifier']),
      positions: rawPositions
          .whereType<Map>()
          .map((position) => tradeJsonMap(position))
          .map(positionFromTradeJson)
          .toList(growable: false),
    );
  }

  @override
  Future<PreparedTradeAction> prepare(
    String bearerToken, {
    required String action,
    Map<String, dynamic>? targetIdentity,
    String? amount,
    String? size,
    String? percentage,
  }) async {
    final body = <String, dynamic>{'action': action};
    if (targetIdentity != null) body['targetIdentity'] = targetIdentity;
    if (amount != null) body['amount'] = amount;
    if (size != null) body['size'] = size;
    if (percentage != null) body['percentage'] = percentage;
    final data = await _request(
      'POST',
      'v1/actions/prepare',
      bearerToken: bearerToken,
      body: body,
    );
    final operationId = _string(data['operationId']);
    final confirmationToken = _string(data['confirmationToken']);
    if (operationId.isEmpty || confirmationToken.isEmpty) {
      throw const TradeApiException(
        code: 'invalid_response',
        message: 'The trade API returned an incomplete confirmation.',
      );
    }
    return PreparedTradeAction(
      operationId: operationId,
      confirmationToken: confirmationToken,
      action: _string(data['action']),
      expiresAt: _string(data['expiresAt']),
      summary: tradeJsonMap(data['summary']),
    );
  }

  @override
  Future<TradeOperationResult> execute(
    String bearerToken, {
    required String operationId,
    required String confirmationToken,
  }) async {
    final data = await _request(
      'POST',
      'v1/actions/execute',
      bearerToken: bearerToken,
      body: {
        'operationId': operationId,
        'confirmationToken': confirmationToken,
      },
    );
    return TradeOperationResult.fromJson(data);
  }

  @override
  Future<TradeOperationResult> getResult(
    String bearerToken,
    String operationId,
  ) async {
    final data = await _request(
      'GET',
      'v1/actions/result/${Uri.encodeComponent(operationId)}',
      bearerToken: bearerToken,
    );
    return TradeOperationResult.fromJson(data);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    String? bearerToken,
    Map<String, dynamic>? body,
  }) async {
    if (_validatedBaseUrl == null) {
      throw const TradeApiException(
        code: 'api_not_configured',
        message:
            'Set TRADE_API_BASE_URL to a valid HTTPS address to enable private trade actions.',
      );
    }
    try {
      final response = await _client.request<Object?>(
        path,
        data: body,
        options: Options(
          method: method,
          // Passwords, TOTP codes, and bearer tokens must never be replayed
          // by the HTTP adapter to a redirect destination.
          followRedirects: false,
          maxRedirects: 0,
          headers: {
            if (bearerToken != null) 'Authorization': 'Bearer $bearerToken',
          },
        ),
      );
      final payload = tradeJsonMap(response.data);
      if (payload.isEmpty && response.data is! Map) {
        throw const TradeApiException(
          code: 'invalid_response',
          message: 'The trade API returned an invalid response.',
        );
      }
      return payload;
    } on DioException catch (error) {
      final payload = tradeJsonMap(error.response?.data);
      final message = _string(payload['message']);
      throw TradeApiException(
        statusCode: error.response?.statusCode,
        code: _string(payload['error']).isEmpty
            ? 'network_error'
            : _string(payload['error']),
        message: message.isNotEmpty
            ? message
            : 'The trade API could not be reached. Check its address and network.',
        details: payload,
      );
    }
  }
}

class TradeSession {
  const TradeSession({
    required this.bearerToken,
    required this.accountIdentifier,
    required this.expiresAt,
  });

  final String bearerToken;
  final String accountIdentifier;
  final DateTime expiresAt;

  bool get isActive => DateTime.now().isBefore(expiresAt);
}

class TradePositionsSnapshot {
  const TradePositionsSnapshot({
    required this.accountIdentifier,
    required this.positions,
  });

  final String accountIdentifier;
  final List<OkxPosition> positions;
}

class PreparedTradeAction {
  const PreparedTradeAction({
    required this.operationId,
    required this.confirmationToken,
    required this.action,
    required this.expiresAt,
    required this.summary,
  });

  final String operationId;
  final String confirmationToken;
  final String action;
  final String expiresAt;
  final Map<String, dynamic> summary;

  List<Map<String, dynamic>> get targets {
    final raw = summary['targets'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map(tradeJsonMap).toList(growable: false);
  }
}

class TradeOperationResult {
  const TradeOperationResult({
    required this.operationId,
    required this.action,
    required this.status,
    required this.targets,
    required this.updatedAt,
  });

  factory TradeOperationResult.fromJson(Map<String, dynamic> json) {
    final rawTargets = json['targets'];
    return TradeOperationResult(
      operationId: _string(json['operationId']),
      action: _string(json['action']),
      status: _string(json['status']).toUpperCase(),
      targets: rawTargets is List
          ? rawTargets
                .whereType<Map>()
                .map(tradeJsonMap)
                .toList(growable: false)
          : const [],
      updatedAt: _string(json['updatedAt']),
    );
  }

  final String operationId;
  final String action;
  final String status;
  final List<Map<String, dynamic>> targets;
  final String updatedAt;
}

class TradeApiException implements Exception {
  const TradeApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.details = const {},
  });

  final int? statusCode;
  final String code;
  final String message;
  final Map<String, dynamic> details;

  bool get isUnauthorized => statusCode == 401;

  bool get isStale => code == 'stale_target' || code == 'position_changed';

  @override
  String toString() => message;
}

Map<String, dynamic> tradeJsonMap(dynamic value) {
  if (value is! Map) return const <String, dynamic>{};
  return value.map((key, item) => MapEntry(key.toString(), item));
}

String _string(dynamic value) => value == null ? '' : value.toString();
