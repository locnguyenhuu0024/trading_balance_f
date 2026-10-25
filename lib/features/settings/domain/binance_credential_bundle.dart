import 'dart:convert';

/// One atomically persisted Binance API key/secret pair.
class BinanceCredentialBundle {
  const BinanceCredentialBundle._({
    required this.apiKey,
    required this.secretKey,
  });

  static const String storageKey = 'BINANCE_CREDENTIAL_BUNDLE_V1';
  static const int version = 1;

  final String apiKey;
  final String secretKey;

  static BinanceCredentialBundle? tryCreate({
    required String apiKey,
    required String secretKey,
  }) {
    if (apiKey.trim().isEmpty || secretKey.trim().isEmpty) return null;
    return BinanceCredentialBundle._(apiKey: apiKey, secretKey: secretKey);
  }

  /// Returns null for malformed, partial, mixed-version, or extended records.
  static BinanceCredentialBundle? tryDecode(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map ||
          decoded.length != 3 ||
          decoded['version'] is! int ||
          decoded['version'] != version ||
          decoded['apiKey'] is! String ||
          decoded['secretKey'] is! String) {
        return null;
      }
      return tryCreate(
        apiKey: decoded['apiKey'] as String,
        secretKey: decoded['secretKey'] as String,
      );
    } on FormatException {
      return null;
    }
  }

  String encode() => jsonEncode(<String, Object>{
    'version': version,
    'apiKey': apiKey,
    'secretKey': secretKey,
  });
}
