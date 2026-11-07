import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/exchange/exchange_models.dart';
import '../../core/exchange/exchange_scope.dart';
import '../../core/network/request_coordinator.dart';

final binanceClientProvider = Provider<BinanceClient>(
  (ref) => BinanceClient(
    coordinator: ref.watch(
      exchangeRequestCoordinatorProvider(ExchangeId.binance),
    ),
  ),
);

class BinanceClient {
  BinanceClient({required this.coordinator, Dio? dio}) : _dio = dio ?? Dio();
  final RequestCoordinator coordinator;
  final Dio _dio;
  static const _paths = {
    '/fapi/v1/exchangeInfo',
    '/api/v3/exchangeInfo',
    '/fapi/v1/ticker/24hr',
    '/api/v3/ticker/24hr',
    '/api/v3/ticker/price',
    '/fapi/v1/klines',
    '/api/v3/klines',
  };

  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic> queryParameters = const {},
  }) {
    if (!_paths.contains(path)) throw ArgumentError.value(path, 'path');
    final entries = queryParameters.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final key = '$path?${entries.map((e) => '${e.key}=${e.value}').join('&')}';
    final host = path.startsWith('/fapi/')
        ? 'https://fapi.binance.com'
        : 'https://api.binance.com';
    return coordinator.run(
      lane: RequestLane.public,
      key: key,
      request: () {
        _dio.options.headers.removeWhere(
          (key, value) => key.toLowerCase() == 'x-mbx-apikey',
        );
        return _dio.get<dynamic>(
          '$host$path',
          queryParameters: queryParameters,
        );
      },
    );
  }
}
