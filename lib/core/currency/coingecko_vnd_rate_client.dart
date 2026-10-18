import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final coinGeckoVndRateClientProvider = Provider<CoinGeckoVndRateClient>((ref) {
  final client = CoinGeckoVndRateClient();
  ref.onDispose(client.dispose);
  return client;
});

/// Credential-free CoinGecko transport for the USDT to VND display rate.
class CoinGeckoVndRateClient {
  CoinGeckoVndRateClient({Dio? dio})
    : _dio = dio ?? _createDio(),
      _ownsDio = dio == null;

  static const String origin = 'https://api.coingecko.com';
  final Dio _dio;
  final bool _ownsDio;

  Future<double> fetchVndRate() async {
    final response = await _dio.get<dynamic>(
      '/api/v3/simple/price',
      queryParameters: const <String, String>{
        'ids': 'tether',
        'vs_currencies': 'vnd',
      },
      options: Options(followRedirects: false, maxRedirects: 0),
    );
    final body = response.data;
    if (body is! Map) throw const FormatException('Invalid rate response.');
    final tether = body['tether'];
    if (tether is! Map) throw const FormatException('Missing tether rate.');
    final value = tether['vnd'];
    if (value is! num || !value.isFinite || value <= 0) {
      throw const FormatException('Invalid tether VND rate.');
    }
    return value.toDouble();
  }

  void dispose() {
    if (_ownsDio) _dio.close(force: true);
  }

  static Dio _createDio() => Dio(
    BaseOptions(
      baseUrl: origin,
      followRedirects: false,
      maxRedirects: 0,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      responseType: ResponseType.json,
      headers: const <String, String>{},
    ),
  );
}
