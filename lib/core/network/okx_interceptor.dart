import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../security/secure_storage_helper.dart';

/// Provider cung cấp OkxInterceptor
final okxInterceptorProvider = Provider<OkxInterceptor>((ref) {
  final secureStorage = ref.watch(secureStorageProvider);
  return OkxInterceptor(secureStorage);
});

/// Interceptor này sẽ tự động chặn các request có gán cờ `requiresAuth`
/// và thêm các thông tin xác thực cần thiết của OKX vào Header.
class OkxInterceptor extends Interceptor {
  final SecureStorageHelper _secureStorage;

  OkxInterceptor(this._secureStorage);

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    // Kiểm tra xem request này có cần xác thực không (public API thì không cần)
    final requiresAuth = options.extra['requiresAuth'] ?? false;

    if (requiresAuth) {
      final apiKey = await _secureStorage.getOkxApiKey();
      final secretKey = await _secureStorage.getOkxSecretKey();
      final passphrase = await _secureStorage.getOkxPassphrase();

      if (apiKey == null || secretKey == null || passphrase == null) {
        return handler.reject(DioException(
          requestOptions: options,
          error: 'Thiếu thông tin OKX API Credentials. Vui lòng cập nhật API Key.',
        ));
      }

      // 1. Tạo Timestamp chuẩn OKX (Bắt buộc phải có 3 chữ số phần nghìn giây - millisecond)
      final timestamp = _getOkxTimestamp(DateTime.now().toUtc());

      // 2. Định dạng request path (bao gồm cả query parameters nếu có)
      final method = options.method.toUpperCase();
      final requestPath = options.uri.path + (options.uri.hasQuery ? '?${options.uri.query}' : '');

      // 3. Chuẩn bị Body (nếu là GET thì body rỗng)
      String bodyStr = '';
      if (options.data != null) {
        bodyStr = jsonEncode(options.data);
      }

      // 4. Tạo Signature
      final sign = _generateSignature(timestamp, method, requestPath, bodyStr, secretKey);

      // 5. Gắn vào Headers
      options.headers.addAll({
        'OK-ACCESS-KEY': apiKey,
        'OK-ACCESS-SIGN': sign,
        'OK-ACCESS-TIMESTAMP': timestamp,
        'OK-ACCESS-PASSPHRASE': passphrase,
      });
    }

    super.onRequest(options, handler);
  }

  /// Hàm format thời gian theo đúng chuẩn OKX yêu cầu: YYYY-MM-DDTHH:mm:ss.SSSZ
  String _getOkxTimestamp(DateTime dateTime) {
    String isoStr = dateTime.toIso8601String();
    if (isoStr.contains('.')) {
      List<String> parts = isoStr.split('.');
      String ms = parts[1].replaceAll('Z', '');
      // Đảm bảo luôn có 3 chữ số thập phân
      ms = ms.padRight(3, '0').substring(0, 3);
      return '${parts[0]}.$ms\Z';
    } else {
      return '${isoStr.replaceAll('Z', '')}.000Z';
    }
  }

  /// Hàm mã hoá HMAC-SHA256 theo tài liệu của OKX
  /// message = timestamp + method + requestPath + body
  String _generateSignature(
      String timestamp,
      String method,
      String requestPath,
      String body,
      String secretKey
      ) {
    final message = '$timestamp$method$requestPath$body';
    final keyBytes = utf8.encode(secretKey);
    final messageBytes = utf8.encode(message);

    final hmac = Hmac(sha256, keyBytes);
    final digest = hmac.convert(messageBytes);

    return base64Encode(digest.bytes);
  }
}