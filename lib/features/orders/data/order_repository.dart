// File Name: order_repository.dart
// File Path: lib/features/orders/data/order_repository.dart

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import 'okx_order_model.dart';
import 'okx_position_model.dart'; // Thêm dòng import này

final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return OrderRepository(dio);
});

class OrderRepository {
  final Dio _dio;

  OrderRepository(this._dio);

  /// Lấy danh sách VỊ THẾ MỞ (Open Positions - Margin, Futures, Swap)
  Future<List<OkxPosition>> getOpenPositions({required String instType}) async {
    // SPOT không có vị thế mở, nên nếu filter là SPOT thì trả về mảng rỗng
    if (instType == 'SPOT') return [];

    try {
      final response = await _dio.get(
        '/api/v5/account/positions',
        queryParameters: {
          'instType': instType,
        },
        options: Options(extra: {'requiresAuth': true}),
      );

      final data = response.data;
      if (data['code'] == '0') {
        final List<dynamic> positionsList = data['data'];
        return positionsList.map((json) => OkxPosition.fromJson(json)).toList();
      } else {
        throw Exception('Lỗi từ OKX API: ${data['msg']}');
      }
    } on DioException catch (e) {
      _handleDioError(e);
      rethrow;
    }
  }

  /// Lấy danh sách lệnh ĐANG CHỜ (Active/Pending)
  Future<List<OkxOrder>> getPendingOrders({required String instType}) async {
    try {
      final response = await _dio.get(
        '/api/v5/trade/orders-pending',
        queryParameters: {
          'instType': instType,
        },
        options: Options(extra: {'requiresAuth': true}),
      );

      return _parseResponse(response.data);
    } on DioException catch (e) {
      _handleDioError(e);
      rethrow;
    }
  }

  /// Lấy danh sách LỊCH SỬ lệnh (7 ngày qua)
  Future<List<OkxOrder>> getOrdersHistory({required String instType}) async {
    try {
      final response = await _dio.get(
        '/api/v5/trade/orders-history',
        queryParameters: {
          'instType': instType,
        },
        options: Options(extra: {'requiresAuth': true}),
      );

      return _parseResponse(response.data);
    } on DioException catch (e) {
      _handleDioError(e);
      rethrow;
    }
  }

  // --- Hàm hỗ trợ parse JSON dùng chung cho Order ---
  List<OkxOrder> _parseResponse(Map<String, dynamic> data) {
    final orderResponse = OkxOrderResponse.fromJson(data);
    if (orderResponse.code == '0') {
      return orderResponse.data;
    } else {
      throw Exception('Lỗi từ OKX API: ${orderResponse.msg}');
    }
  }

  // --- Hàm hỗ trợ xử lý lỗi dùng chung ---
  void _handleDioError(DioException e) {
    if (e.response?.statusCode == 401) {
      throw Exception('API Key không hợp lệ hoặc thiếu quyền.');
    }
    throw Exception('Lỗi kết nối: ${e.message}');
  }
}