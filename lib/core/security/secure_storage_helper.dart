// File Name: secure_storage_helper.dart
// File Path: lib/core/security/secure_storage_helper.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../navigation/navigation_preferences.dart';
import '../timezone/app_time_zone.dart';
import '../typography/app_text_scale.dart';

/// Provider cung cấp instance của SecureStorageHelper
final secureStorageProvider = Provider<SecureStorageHelper>((ref) {
  const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
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
  static const String _navigationPreferences = 'NAVIGATION_PREFERENCES';
  static const String _timeZoneId = 'TIME_ZONE_ID';
  static const String _appTextScale = 'APP_TEXT_SCALE';
  static const String _rememberedTradePasswordPrefix =
      'REMEMBERED_TRADE_PASSWORD_V1_';
  final Map<String, Future<void>> _rememberedTradePasswordTails = {};
  int _rememberedTradePasswordVersion = 0;

  /// Reads a remembered trade password from platform secure storage.
  Future<String?> getRememberedTradePassword(String endpoint) {
    final key = _rememberedTradePasswordKey(endpoint);
    return _withRememberedTradePasswordLock(key, () async {
      final record = await _storage.read(key: key);
      if (record == null) return null;
      final decoded = _decodeRememberedTradePassword(record);
      if (decoded == null || decoded.password.isEmpty) return null;
      return decoded.password;
    });
  }

  /// Saves a remembered trade password in platform secure storage.
  Future<String> saveRememberedTradePassword(String endpoint, String password) {
    if (password.isEmpty) {
      throw ArgumentError.value(password, 'password', 'Must not be empty.');
    }
    final key = _rememberedTradePasswordKey(endpoint);
    return _withRememberedTradePasswordLock(key, () async {
      final version =
          '${DateTime.now().microsecondsSinceEpoch}-${++_rememberedTradePasswordVersion}';
      await _storage.write(
        key: key,
        value: jsonEncode({'version': version, 'password': password}),
      );
      return version;
    });
  }

  /// Deletes a remembered password without affecting other endpoint scopes.
  Future<void> deleteRememberedTradePassword(String endpoint) {
    final key = _rememberedTradePasswordKey(endpoint);
    return _withRememberedTradePasswordLock(
      key,
      () => _storage.delete(key: key),
    );
  }

  /// Deletes a completed write only if no newer write replaced it.
  Future<bool> deleteRememberedTradePasswordIfVersion(
    String endpoint,
    String version,
  ) {
    final key = _rememberedTradePasswordKey(endpoint);
    return _withRememberedTradePasswordLock(key, () async {
      final record = _decodeRememberedTradePassword(
        await _storage.read(key: key) ?? '',
      );
      if (record?.version != version) return false;
      await _storage.delete(key: key);
      return true;
    });
  }

  Future<T> _withRememberedTradePasswordLock<T>(
    String key,
    Future<T> Function() action,
  ) async {
    final previous = _rememberedTradePasswordTails[key];
    final completion = Completer<void>();
    final tail = completion.future;
    _rememberedTradePasswordTails[key] = tail;
    if (previous != null) await previous;
    try {
      return await action();
    } finally {
      completion.complete();
      if (identical(_rememberedTradePasswordTails[key], tail)) {
        _rememberedTradePasswordTails.remove(key);
      }
    }
  }

  ({String version, String password})? _decodeRememberedTradePassword(
    String value,
  ) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map &&
          decoded['version'] is String &&
          decoded['password'] is String) {
        return (
          version: decoded['version'] as String,
          password: decoded['password'] as String,
        );
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  String _rememberedTradePasswordKey(String endpoint) {
    final normalizedEndpoint = endpoint.trim();
    if (normalizedEndpoint.isEmpty) {
      throw ArgumentError.value(endpoint, 'endpoint', 'Must not be empty.');
    }
    final encodedEndpoint = base64Url
        .encode(utf8.encode(normalizedEndpoint))
        .replaceAll('=', '');
    return '$_rememberedTradePasswordPrefix$encodedEndpoint';
  }

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
    return val == 'true';
  }

  // THÊM MỚI: Lấy cấu hình Chế độ nền
  Future<String> getThemeMode() async {
    return await _storage.read(key: _themeMode) ?? 'system';
  }

  // THÊM MỚI: Lấy cấu hình Tiền tệ
  Future<String> getCurrency() async {
    return await _storage.read(key: _currency) ?? 'USD';
  }

  /// Returns a supported IANA ID, defaulting safely to UTC.
  Future<String> getTimeZoneId() async {
    return AppTimeZone.normalizeId(await _storage.read(key: _timeZoneId));
  }

  /// Persists the selected IANA time-zone ID.
  Future<void> saveTimeZoneId(String timeZoneId) {
    return _storage.write(
      key: _timeZoneId,
      value: AppTimeZone.normalizeId(timeZoneId),
    );
  }

  /// Returns a safe application text scale for missing or invalid data.
  Future<double> getAppTextScale() async {
    return AppTextScale.normalize(await _storage.read(key: _appTextScale));
  }

  /// Persists the normalized application text scale.
  Future<void> saveAppTextScale(double scale) {
    return _storage.write(
      key: _appTextScale,
      value: AppTextScale.normalize(scale).toString(),
    );
  }

  /// Returns a safe default for missing, corrupt, or future records.
  Future<NavigationPreferences> getNavigationPreferences() async {
    final value = await _storage.read(key: _navigationPreferences);
    return NavigationPreferences.decode(value);
  }

  /// Persists navigation independently from the pre-existing app settings.
  Future<void> saveNavigationPreferences(NavigationPreferences preferences) {
    return _storage.write(
      key: _navigationPreferences,
      value: preferences.encode(),
    );
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
