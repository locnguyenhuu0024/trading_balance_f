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
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Kiểm tra xem request này có cần xác thực không (public API thì không cần)
    final requiresAuth = options.extra['requiresAuth'] ?? false;

    if (requiresAuth) {
      final apiKey = await _secureStorage.getOkxApiKey();
      final secretKey = await _secureStorage.getOkxSecretKey();
      final passphrase = await _secureStorage.getOkxPassphrase();

      if (apiKey == null || secretKey == null || passphrase == null) {
        return handler.reject(
          DioException(
            requestOptions: options,
            error:
                'Thiếu thông tin OKX API Credentials. Vui lòng cập nhật API Key.',
          ),
        );
      }

      // 1. Tạo Timestamp chuẩn OKX (Bắt buộc phải có 3 chữ số phần nghìn giây - millisecond)
      final timestamp = OkxRequestSigner.timestamp(DateTime.now().toUtc());

      // 2. Định dạng request path (bao gồm cả query parameters nếu có)
      final method = options.method.toUpperCase();
      final requestPath =
          options.uri.path +
          (options.uri.hasQuery ? '?${options.uri.query}' : '');

      // 3. Chuẩn bị Body (nếu là GET thì body rỗng)
      String bodyStr = '';
      if (options.data != null) {
        bodyStr = jsonEncode(options.data);
      }

      // 4. Tạo Signature
      final sign = OkxRequestSigner.signature(
        timestamp: timestamp,
        method: method,
        requestPath: requestPath,
        body: bodyStr,
        secretKey: secretKey,
      );

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
}

/// Shared OKX signing primitives for the legacy interceptor and the native
/// GET transport. Callers pass the exact encoded request target they send.
class OkxRequestSigner {
  const OkxRequestSigner._();

  /// Formats the UTC timestamp required by OKX: yyyy-MM-ddTHH:mm:ss.SSSZ.
  static String timestamp(DateTime dateTime) {
    final utc = dateTime.toUtc();
    final base = utc.toIso8601String().split('.').first;
    final milliseconds = utc.millisecond.toString().padLeft(3, '0');
    return '$base.${milliseconds}Z';
  }

  /// Signs timestamp + uppercase method + exact encoded path/query + body.
  static String signature({
    required String timestamp,
    required String method,
    required String requestPath,
    required String body,
    required String secretKey,
  }) {
    final message = '$timestamp${method.toUpperCase()}$requestPath$body';
    final digest = Hmac(
      sha256,
      utf8.encode(secretKey),
    ).convert(utf8.encode(message));
    return base64Encode(digest.bytes);
  }
}
