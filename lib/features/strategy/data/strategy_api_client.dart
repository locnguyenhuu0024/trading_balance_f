import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../orders/data/trade_api_client.dart';
import '../../orders/data/trade_api_browser_adapter_stub.dart'
    if (dart.library.html) '../../orders/data/trade_api_browser_adapter.dart'
    as browser;

abstract class StrategyApi {
  Future<Map<String, dynamic>> preview(
    String bearerToken,
    Map<String, dynamic> body,
  );

  Future<Map<String, dynamic>> saveDraft(
    String bearerToken,
    Map<String, dynamic> body,
  );

  Future<List<Map<String, dynamic>>> listStrategies(String bearerToken);

  Future<Map<String, dynamic>> prepareApply(String bearerToken, String id);

  Future<Map<String, dynamic>> executeApply(
    String bearerToken,
    String id,
    String confirmationToken,
  );

  Future<Map<String, dynamic>> getResult(String bearerToken, String id);

  Future<Map<String, dynamic>> getQuote(String bearerToken, String id);

  Future<void> deleteDraft(String bearerToken, String id);
}

class StrategyApiClient implements StrategyApi {
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
        message: message.isEmpty ? _failureMessage(error) : message,
        details: payload,
      );
    }
  }
}

String _failureMessage(DioException error) {
  final statusCode = error.response?.statusCode;
  if (statusCode != null) {
    final guidance = switch (statusCode) {
      401 => 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
      404 =>
        'Không tìm thấy đường dẫn xem trước chiến lược. Vui lòng kiểm tra API rồi thử lại.',
      429 =>
        'Yêu cầu xem trước quá thường xuyên. Vui lòng chờ một chút rồi thử lại.',
      >= 500 => 'Máy chủ xem trước đang gặp sự cố. Vui lòng thử lại sau.',
      >= 400 =>
        'Máy chủ từ chối yêu cầu xem trước. Vui lòng kiểm tra thông tin rồi thử lại.',
      _ => 'Máy chủ trả về phản hồi không thể xử lý. Vui lòng thử lại sau.',
    };
    return '$guidance (HTTP $statusCode)';
  }

  return switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.transformTimeout =>
      'Yêu cầu xem trước đã quá thời gian chờ. Vui lòng thử lại. (TIMEOUT)',
    DioExceptionType.cancel =>
      'Yêu cầu xem trước đã bị hủy. Bạn có thể nhấn “Xem lại lệnh” để thử lại. (CANCELLED)',
    DioExceptionType.connectionError ||
    DioExceptionType.badCertificate ||
    DioExceptionType.unknown =>
      'Không thể kết nối để xem trước lệnh. Kiểm tra mạng hoặc trình duyệt rồi thử lại. (CONNECTION)',
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

final strategyApiProvider = Provider<StrategyApi>((ref) => StrategyApiClient());
