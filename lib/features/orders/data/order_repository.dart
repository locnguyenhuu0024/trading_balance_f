// File Name: order_repository.dart
// File Path: lib/features/orders/data/order_repository.dart

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/okx_data_client.dart';
import 'okx_order_model.dart';
import 'okx_position_model.dart';

final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  return OrderRepository(ref.watch(okxDataClientProvider));
});

class OrderRepository {
  OrderRepository(this._client);

  static const supportedHistoryTypes = <String>[
    'SPOT',
    'MARGIN',
    'SWAP',
    'FUTURES',
  ];

  final OkxDataClient _client;

  /// Loads visible native positions. `ALL` uses OKX's unfiltered endpoint.
  Future<List<OkxPosition>> getOpenPositions({
    required String instType,
    CancelToken? cancelToken,
  }) async {
    if (instType == 'SPOT') return const <OkxPosition>[];
    final query = <String, dynamic>{
      if (instType != 'ALL') 'instType': instType,
    };
    final response = await _client.get(
      '/api/v5/account/positions',
      queryParameters: query,
      cancelToken: cancelToken,
    );
    return _parsePositions(response.data);
  }

  /// Loads pending orders. `ALL` omits `instType` at the native API.
  Future<List<OkxOrder>> getPendingOrders({
    required String instType,
    CancelToken? cancelToken,
  }) async {
    final response = await _client.get(
      '/api/v5/trade/orders-pending',
      queryParameters: <String, dynamic>{
        if (instType != 'ALL') 'instType': instType,
      },
      cancelToken: cancelToken,
    );
    final orders = _parseResponse(response.data);
    return instType == 'ALL' ? _sortNewestFirst(orders) : orders;
  }

  /// Loads one category, or all supported categories sequentially and
  /// atomically. The first-page history depth remains the OKX default.
  Future<List<OkxOrder>> getOrdersHistory({
    required String instType,
    CancelToken? cancelToken,
  }) async {
    if (instType != 'ALL') {
      final response = await _client.get(
        '/api/v5/trade/orders-history',
        queryParameters: <String, dynamic>{'instType': instType},
        cancelToken: cancelToken,
      );
      return _parseResponse(response.data);
    }

    final combined = <OkxOrder>[];
    for (final category in supportedHistoryTypes) {
      final response = await _client.get(
        '/api/v5/trade/orders-history',
        queryParameters: <String, dynamic>{'instType': category},
        cancelToken: cancelToken,
      );
      combined.addAll(_parseResponse(response.data));
    }
    return _sortNewestFirst(combined);
  }

  List<OkxPosition> _parsePositions(dynamic body) {
    if (body is! Map ||
        body['code']?.toString() != '0' ||
        body['data'] is! List) {
      throw const OkxDataException(
        code: 'okx_invalid_response',
        message: 'OKX returned an invalid positions response.',
      );
    }
    final rows = body['data'] as List;
    if (rows.any((row) => row is! Map)) {
      throw const OkxDataException(
        code: 'okx_invalid_response',
        message: 'OKX returned an invalid position row.',
      );
    }
    return rows
        .map((row) => OkxPosition.fromJson(_nativePositionMap(row as Map)))
        .toList(growable: false);
  }

  List<OkxOrder> _parseResponse(dynamic body) {
    if (body is! Map ||
        body['code']?.toString() != '0' ||
        body['data'] is! List) {
      throw const OkxDataException(
        code: 'okx_invalid_response',
        message: 'OKX returned an invalid order response.',
      );
    }
    final rows = body['data'] as List;
    if (rows.any((row) => row is! Map)) {
      throw const OkxDataException(
        code: 'okx_invalid_response',
        message: 'OKX returned an invalid order row.',
      );
    }
    final response = OkxOrderResponse.fromJson(_keyedMap(body));
    return response.data;
  }

  Map<String, dynamic> _keyedMap(Map raw) =>
      raw.map<String, dynamic>((key, value) => MapEntry(key.toString(), value));

  Map<String, dynamic> _nativePositionMap(Map raw) {
    final row = _keyedMap(raw);
    row
      ..remove('identity')
      ..remove('eligibleActions');
    return <String, dynamic>{
      ...row,
      'positionId': row['posId'] ?? row['positionId'],
      'marginCurrency': row['ccy'] ?? row['marginCurrency'],
      'positionCurrency': row['posCcy'] ?? row['positionCurrency'],
    };
  }

  List<OkxOrder> _sortNewestFirst(List<OkxOrder> orders) {
    final indexes = List<int>.generate(orders.length, (index) => index);
    indexes.sort((leftIndex, rightIndex) {
      final leftTime = int.tryParse(orders[leftIndex].cTime);
      final rightTime = int.tryParse(orders[rightIndex].cTime);

      if (leftTime == null && rightTime == null) {
        return leftIndex.compareTo(rightIndex);
      }
      if (leftTime == null) return 1;
      if (rightTime == null) return -1;

      final timeOrder = rightTime.compareTo(leftTime);
      return timeOrder != 0 ? timeOrder : leftIndex.compareTo(rightIndex);
    });
    return indexes.map((index) => orders[index]).toList(growable: false);
  }
}
