// File Name: secure_storage_helper.dart
// File Path: lib/core/security/secure_storage_helper.dart

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider cung cấp instance của SecureStorageHelper
final secureStorageProvider = Provider<SecureStorageHelper>((ref) {
  const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );
  return SecureStorageHelper(storage);
});

/// Lớp hỗ trợ quản lý việc lưu trữ các dữ liệu nhạy cảm và cài đặt
class SecureStorageHelper {
  final FlutterSecureStorage _storage;

  SecureStorageHelper(this._storage);

  // Define keys
  static const String _okxApiKey = 'OKX_API_KEY';
  static const String _okxSecretKey = 'OKX_SECRET_KEY';
  static const String _okxPassphrase = 'OKX_PASSPHRASE';
  static const String _hideBalance = 'HIDE_BALANCE';
  static const String _bioAuth = 'BIO_AUTH';
  // THÊM MỚI: Keys cho Theme và Tiền tệ
  static const String _themeMode = 'THEME_MODE';
  static const String _currency = 'CURRENCY';

  /// Lưu trữ OKX Credentials
  Future<void> saveOkxCredentials({
    required String apiKey,
    required String secretKey,
    required String passphrase,
  }) async {
    await Future.wait([
      _storage.write(key: _okxApiKey, value: apiKey),
      _storage.write(key: _okxSecretKey, value: secretKey),
      _storage.write(key: _okxPassphrase, value: passphrase),
    ]);
  }

  /// Lấy cấu hình Ẩn số dư mặc định
  Future<bool> getHideBalanceDefault() async {
    final val = await _storage.read(key: _hideBalance);
    return val == 'true';
  }

  /// Lấy cấu hình Sinh trắc học
  Future<bool> getBiometricAuth() async {
    final val = await _storage.read(key: _bioAuth);
    return val == null || val == 'true';
  }

  // THÊM MỚI: Lấy cấu hình Chế độ nền
  Future<String> getThemeMode() async {
    return await _storage.read(key: _themeMode) ?? 'system';
  }

  // THÊM MỚI: Lấy cấu hình Tiền tệ
  Future<String> getCurrency() async {
    return await _storage.read(key: _currency) ?? 'USD';
  }

  /// NÂNG CẤP: Lưu trữ Tùy chọn ứng dụng bao gồm cả Theme và Currency
  Future<void> saveAppPreferences({
    required bool hideBalance,
    required bool bioAuth,
    required String themeMode,
    required String currency,
  }) async {
    await Future.wait([
      _storage.write(key: _hideBalance, value: hideBalance.toString()),
      _storage.write(key: _bioAuth, value: bioAuth.toString()),
      _storage.write(key: _themeMode, value: themeMode),
      _storage.write(key: _currency, value: currency),
    ]);
  }

  Future<String?> getOkxApiKey() => _storage.read(key: _okxApiKey);
  Future<String?> getOkxSecretKey() => _storage.read(key: _okxSecretKey);
  Future<String?> getOkxPassphrase() => _storage.read(key: _okxPassphrase);

  /// Xoá toàn bộ thông tin
  Future<void> clearOkxCredentials() async {
    await Future.wait([
      _storage.delete(key: _okxApiKey),
      _storage.delete(key: _okxSecretKey),
      _storage.delete(key: _okxPassphrase),
    ]);
  }
}