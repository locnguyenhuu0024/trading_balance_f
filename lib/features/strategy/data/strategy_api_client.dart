import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../orders/data/trade_api_client.dart';
import '../../orders/data/trade_api_browser_adapter_stub.dart'
    if (dart.library.html) '../../orders/data/trade_api_browser_adapter.dart'
    as browser;
import '../domain/strategy_models.dart';
import '../domain/strategy_settings.dart';

abstract class StrategyApi {
  Future<Map<String, dynamic>> preview(
    String bearerToken,
    Map<String, dynamic> body,
  );

  Future<Map<String, dynamic>> saveDraft(
    String bearerToken,
    Map<String, dynamic> body,
  );

  Future<StrategyRetryCandidates> getRetryCandidates(
    String bearerToken,
    String sourceStrategyId,
  );

  Future<StrategyRetryPreview> previewRetry(
    String bearerToken,
    String sourceStrategyId, {
    required String sourceRevision,
    required List<String> sourceClientOrderIds,
  });

  Future<StrategyRetryDraft> createRetryDraft(
    String bearerToken,
    String sourceStrategyId, {
    required String sourceRevision,
    required List<String> sourceClientOrderIds,
    required String previewHash,
    required String retryRequestId,
  });

  Future<List<Map<String, dynamic>>> listStrategies(String bearerToken);

  Future<Map<String, dynamic>> prepareApply(String bearerToken, String id);

  Future<Map<String, dynamic>> executeApply(
    String bearerToken,
    String id,
    String confirmationToken,
  );

  Future<Map<String, dynamic>> getResult(String bearerToken, String id);

  Future<Map<String, dynamic>> getQuote(String bearerToken, String id);

  Future<String> getLimitOrderSubmissionMode(String bearerToken);

  Future<String> saveLimitOrderSubmissionMode(String bearerToken, String mode);

  Future<void> deleteDraft(String bearerToken, String id);
}

/// Optional capability kept separate so existing StrategyApi fakes and
/// integrations do not need to implement automatic candidate generation.
abstract interface class AutomaticStrategyApi {
  Future<Map<String, dynamic>> createAutomaticDrafts(
    String bearerToken, {
    required String instrumentId,
    required String interval,
    required String requestId,
  });
}

/// Optional full-settings capability. Legacy StrategyApi implementations keep
/// their mode-only methods and do not have to implement this interface.
abstract interface class StrategySettingsApi {
  Future<StrategySettings> getStrategySettings(String bearerToken);

  Future<StrategySettings> saveStrategySettings(
    String bearerToken,
    StrategySettings settings,
  );
}

class StrategyApiClient
    implements StrategyApi, AutomaticStrategyApi, StrategySettingsApi {
  StrategyApiClient({Dio? dio, String? baseUrl})
    : _baseUrl = (baseUrl ?? tradeApiBaseUrl).trim(),
      _dio = dio;

  final String _baseUrl;
  Dio? _dio;

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
      uri.port;
      return uri.toString().endsWith('/')
          ? uri.toString()
          : '${uri.toString()}/';
    } on FormatException {
      return null;
    }
  }

  Dio get _client {
    if (_dio == null) {
      final dio = Dio(
        BaseOptions(
          baseUrl: _validatedBaseUrl!,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 10),
          headers: const {'Content-Type': 'application/json'},
        ),
      );
      browser.configureTradeApiBrowserClient(dio);
      _dio = dio;
    }
    final dio = _dio!;
    dio.options.baseUrl = _validatedBaseUrl!;
    return dio;
  }

  @override
  Future<Map<String, dynamic>> preview(
    String bearerToken,
    Map<String, dynamic> body,
  ) => _request(
    'POST',
    'v1/strategies/preview',
    bearerToken: bearerToken,
    body: body,
  );

  @override
  Future<Map<String, dynamic>> saveDraft(
    String bearerToken,
    Map<String, dynamic> body,
  ) => _request('POST', 'v1/strategies', bearerToken: bearerToken, body: body);

  @override
  Future<Map<String, dynamic>> createAutomaticDrafts(
    String bearerToken, {
    required String instrumentId,
    required String interval,
    required String requestId,
  }) {
    final normalizedInstrument = instrumentId.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]+-USDT-SWAP$').hasMatch(normalizedInstrument) ||
        !const {'6Hutc', '1Dutc', '1Wutc'}.contains(interval) ||
        !RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(requestId)) {
      throw const StrategyApiException(
        code: 'invalid_request',
        message: 'The automatic strategy request is invalid.',
      );
    }
    return _request(
      'POST',
      'v1/strategies/automatic-drafts',
      bearerToken: bearerToken,
      body: {
        'instrumentId': normalizedInstrument,
        'interval': interval,
        'requestId': requestId,
      },
    );
  }

  @override
  Future<StrategyRetryCandidates> getRetryCandidates(
    String bearerToken,
    String sourceStrategyId,
  ) async {
    final response = await _request(
      'GET',
      'v1/strategies/${Uri.encodeComponent(sourceStrategyId)}/retry-candidates',
      bearerToken: bearerToken,
    );
    final candidates = StrategyRetryCandidates.tryParse(response);
    if (candidates == null) throw _invalidRetryResponse();
    return candidates;
  }

  @override
  Future<StrategyRetryPreview> previewRetry(
    String bearerToken,
    String sourceStrategyId, {
    required String sourceRevision,
    required List<String> sourceClientOrderIds,
  }) async {
    if (!_validRetrySelection(sourceRevision, sourceClientOrderIds)) {
      throw const StrategyApiException(
        code: 'invalid_request',
        message: 'The retry selection is invalid.',
      );
    }
    final response = await _request(
      'POST',
      'v1/strategies/${Uri.encodeComponent(sourceStrategyId)}/retry-preview',
      bearerToken: bearerToken,
      body: {
        'sourceRevision': sourceRevision,
        'sourceClientOrderIds': List<String>.from(sourceClientOrderIds),
      },
    );
    final preview = StrategyRetryPreview.tryParse(response);
    if (preview == null) throw _invalidRetryResponse();
    return preview;
  }

  @override
  Future<StrategyRetryDraft> createRetryDraft(
    String bearerToken,
    String sourceStrategyId, {
    required String sourceRevision,
    required List<String> sourceClientOrderIds,
    required String previewHash,
    required String retryRequestId,
  }) async {
    if (!_validRetrySelection(sourceRevision, sourceClientOrderIds) ||
        previewHash.isEmpty ||
        previewHash.length > 512 ||
        !RegExp(r'^[A-Za-z0-9_-]{16,64}$').hasMatch(retryRequestId)) {
      throw const StrategyApiException(
        code: 'invalid_request',
        message: 'The retry draft request is invalid.',
      );
    }
    final response = await _request(
      'POST',
      'v1/strategies/${Uri.encodeComponent(sourceStrategyId)}/retry-drafts',
      bearerToken: bearerToken,
      body: {
        'sourceRevision': sourceRevision,
        'sourceClientOrderIds': List<String>.from(sourceClientOrderIds),
        'previewHash': previewHash,
        'retryRequestId': retryRequestId,
      },
    );
    final draft = StrategyRetryDraft.tryParse(response);
    if (draft == null) throw _invalidRetryResponse();
    return draft;
  }

  @override
  Future<List<Map<String, dynamic>>> listStrategies(String bearerToken) async {
    final data = await _request(
      'GET',
      'v1/strategies',
      bearerToken: bearerToken,
    );
    if (data['strategies'] is! List) {
      throw const StrategyApiException(
        code: 'invalid_response',
        message: 'The trade API returned an invalid strategy list.',
      );
    }
    return (data['strategies'] as List)
        .whereType<Map>()
        .map(tradeJsonMap)
        .toList(growable: false);
  }

  @override
  Future<Map<String, dynamic>> prepareApply(String bearerToken, String id) =>
      _request(
        'POST',
        'v1/strategies/${Uri.encodeComponent(id)}/prepare-apply',
        bearerToken: bearerToken,
        body: const {},
      );

  @override
  Future<Map<String, dynamic>> executeApply(
    String bearerToken,
    String id,
    String confirmationToken,
  ) => _request(
    'POST',
    'v1/strategies/${Uri.encodeComponent(id)}/execute-apply',
    bearerToken: bearerToken,
    body: {'confirmationToken': confirmationToken},
  );

  @override
  Future<Map<String, dynamic>> getResult(String bearerToken, String id) =>
      _request(
        'GET',
        'v1/strategies/${Uri.encodeComponent(id)}/result',
        bearerToken: bearerToken,
      );

  @override
  Future<Map<String, dynamic>> getQuote(String bearerToken, String id) =>
      _request(
        'GET',
        'v1/strategies/${Uri.encodeComponent(id)}/quote',
        bearerToken: bearerToken,
      );

  @override
  Future<String> getLimitOrderSubmissionMode(String bearerToken) async {
    final response = await _request(
      'GET',
      'v1/strategies/settings',
      bearerToken: bearerToken,
    );
    return _validatedSubmissionMode(response['limitOrderSubmissionMode']);
  }

  @override
  Future<String> saveLimitOrderSubmissionMode(
    String bearerToken,
    String mode,
  ) async {
    if (!_isSubmissionMode(mode)) {
      throw const StrategyApiException(
        code: 'invalid_request',
        message: 'The limit order submission mode is invalid.',
      );
    }
    final response = await _request(
      'POST',
      'v1/strategies/settings',
      bearerToken: bearerToken,
      body: {'limitOrderSubmissionMode': mode},
    );
    final acknowledged = _validatedSubmissionMode(
      response['limitOrderSubmissionMode'],
    );
    if (acknowledged != mode) {
      throw const StrategyApiException(
        code: 'invalid_response',
        message: 'The trade API did not acknowledge the selected setting.',
      );
    }
    return acknowledged;
  }

  @override
  Future<StrategySettings> getStrategySettings(String bearerToken) async {
    final response = await _request(
      'GET',
      'v1/strategies/settings',
      bearerToken: bearerToken,
    );
    final settings = StrategySettings.tryParse(response);
    if (settings == null) throw _invalidSettingsResponse();
    return settings;
  }

  @override
  Future<StrategySettings> saveStrategySettings(
    String bearerToken,
    StrategySettings settings,
  ) async {
    if (!settings.isValid) {
      throw const StrategyApiException(
        code: 'invalid_request',
        message: 'The strategy settings are invalid.',
      );
    }
    final response = await _request(
      'POST',
      'v1/strategies/settings',
      bearerToken: bearerToken,
      body: settings.toJson(),
    );
    final acknowledged = StrategySettings.tryParse(response);
    if (acknowledged == null || acknowledged != settings) {
      throw const StrategyApiException(
        code: 'invalid_response',
        message: 'The trade API did not acknowledge all selected settings.',
      );
    }
    return acknowledged;
  }

  @override
  Future<void> deleteDraft(String bearerToken, String id) async {
    await _request(
      'POST',
      'v1/strategies/${Uri.encodeComponent(id)}/delete',
      bearerToken: bearerToken,
      body: const {},
    );
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    required String bearerToken,
    Map<String, dynamic>? body,
  }) async {
    if (_validatedBaseUrl == null) {
      throw const StrategyApiException(
        code: 'api_not_configured',
        message: 'The authenticated trade API is not configured.',
      );
    }
    try {
      final response = await _client.request<Object?>(
        path,
        data: body,
        options: Options(
          method: method,
          followRedirects: false,
          maxRedirects: 0,
          headers: {'Authorization': 'Bearer $bearerToken'},
        ),
      );
      final payload = tradeJsonMap(response.data);
      if (payload.isEmpty && response.data is! Map) {
        throw const StrategyApiException(
          code: 'invalid_response',
          message: 'The trade API returned an invalid response.',
        );
      }
      return payload;
    } on DioException catch (error) {
      final payload = tradeJsonMap(error.response?.data);
      final message = _text(payload['message']);
      throw StrategyApiException(
        statusCode: error.response?.statusCode,
        code: _text(payload['error']).isEmpty
            ? 'network_error'
            : _text(payload['error']),
        message: message.isEmpty
            ? _failureMessage(
                error,
                automaticDrafts: path == 'v1/strategies/automatic-drafts',
              )
            : message,
        details: payload,
      );
    }
  }
}

bool _validRetrySelection(String revision, List<String> ids) =>
    revision.isNotEmpty &&
    revision.length <= 512 &&
    ids.isNotEmpty &&
    ids.length <= strategyNewSubmissionOrderLimit &&
    ids.every((id) => id.isNotEmpty && id.length <= 200) &&
    ids.toSet().length == ids.length;

StrategyApiException _invalidRetryResponse() => const StrategyApiException(
  code: 'invalid_response',
  message: 'The trade API returned an invalid retry review.',
);

StrategyApiException _invalidSettingsResponse() => const StrategyApiException(
  code: 'invalid_response',
  message: 'The trade API returned invalid strategy settings.',
);

String _failureMessage(
  DioException error, {
  bool automaticDrafts = false,
}) {
  final operation = automaticDrafts ? 'dựng chiến thuật tự động' : 'xem trước';
  final statusCode = error.response?.statusCode;
  if (statusCode != null) {
    final guidance = switch (statusCode) {
      401 => 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
      404 => automaticDrafts
          ? 'Không tìm thấy đường dẫn dựng chiến thuật tự động. Vui lòng kiểm tra API rồi thử lại.'
          : 'Không tìm thấy đường dẫn xem trước chiến lược. Vui lòng kiểm tra API rồi thử lại.',
      429 => automaticDrafts
          ? 'Yêu cầu dựng chiến thuật tự động quá thường xuyên. Vui lòng chờ một chút rồi thử lại.'
          : 'Yêu cầu xem trước quá thường xuyên. Vui lòng chờ một chút rồi thử lại.',
      >= 500 => automaticDrafts
          ? 'Máy chủ dựng chiến thuật tự động đang gặp sự cố. Vui lòng thử lại sau.'
          : 'Máy chủ xem trước đang gặp sự cố. Vui lòng thử lại sau.',
      >= 400 =>
        'Máy chủ từ chối yêu cầu $operation. Vui lòng kiểm tra thông tin rồi thử lại.',
      _ => 'Máy chủ trả về phản hồi không thể xử lý. Vui lòng thử lại sau.',
    };
    return '$guidance (HTTP $statusCode)';
  }

  return switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.transformTimeout =>
      'Yêu cầu $operation đã quá thời gian chờ. Vui lòng thử lại. (TIMEOUT)',
    DioExceptionType.cancel => automaticDrafts
        ? 'Yêu cầu dựng chiến thuật tự động đã bị hủy. Vui lòng thử lại nếu cần. (CANCELLED)'
        : 'Yêu cầu xem trước đã bị hủy. Bạn có thể nhấn “Xem lại lệnh” để thử lại. (CANCELLED)',
    DioExceptionType.connectionError ||
    DioExceptionType.badCertificate ||
    DioExceptionType.unknown => automaticDrafts
        ? 'Không thể kết nối để dựng chiến thuật tự động. Kiểm tra mạng hoặc trình duyệt rồi thử lại. (CONNECTION)'
        : 'Không thể kết nối để xem trước lệnh. Kiểm tra mạng hoặc trình duyệt rồi thử lại. (CONNECTION)',
    DioExceptionType.badResponse =>
      'Máy chủ trả về phản hồi không hợp lệ. Vui lòng thử lại sau. (SERVER_RESPONSE)',
  };
}

class StrategyApiException implements Exception {
  const StrategyApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.details = const {},
  });

  final String code;
  final String message;
  final int? statusCode;
  final Map<String, dynamic> details;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

String _text(Object? value) => value == null ? '' : value.toString();

bool _isSubmissionMode(String value) =>
    value == 'sequential' || value == 'batch';

String _validatedSubmissionMode(Object? value) {
  if (value is String && _isSubmissionMode(value)) return value;
  throw const StrategyApiException(
    code: 'invalid_response',
    message: 'The trade API returned an invalid strategy setting.',
  );
}

final strategyApiProvider = Provider<StrategyApi>((ref) => StrategyApiClient());
