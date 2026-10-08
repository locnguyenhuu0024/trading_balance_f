// File Name: order_repository.dart
// File Path: lib/features/orders/data/order_repository.dart

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/backend_data_client.dart';
import '../../../core/network/backend_data_session.dart';
import '../presentation/providers/trade_session_provider.dart';
import 'okx_order_model.dart';
import 'okx_position_model.dart'; // Thêm dòng import này

final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  final client = ref.watch(backendDataClientProvider);
  final session = ref.watch(backendDataSessionProvider);
  return OrderRepository(client, session);
});

class OrderRepository {
  OrderRepository(this._client, this._session);

  final BackendDataClient _client;
  final BackendDataSession _session;

  /// Lấy danh sách VỊ THẾ MỞ (Open Positions - Margin, Futures, Swap)
  Future<List<OkxPosition>> getOpenPositions({
    required String instType,
    CancelToken? cancelToken,
  }) async {
    // SPOT không có vị thế mở, nên nếu filter là SPOT thì trả về mảng rỗng
    if (instType == 'SPOT') return [];

    try {
      final response = await _client.get(
        '/api/v5/account/positions',
        queryParameters: {'instType': instType},
        session: _session,
        cancelToken: cancelToken,
      );

      final data = response.data;
      if (data['code'] == '0') {
        final List<dynamic> positionsList = data['data'];
        return positionsList.map((json) => OkxPosition.fromJson(json)).toList();
      } else {
        throw Exception('Lỗi từ OKX API: ${data['msg']}');
      }
    } on BackendDataException catch (e) {
      _mapBackendError(e);
    } on DioException catch (e) {
      _handleDioError(e);
      rethrow;
    }
  }

  /// Lấy danh sách lệnh ĐANG CHỜ (Active/Pending)
  Future<List<OkxOrder>> getPendingOrders({
    required String instType,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _client.get(
        '/api/v5/trade/orders-pending',
        queryParameters: {'instType': instType},
        session: _session,
        cancelToken: cancelToken,
      );

      final orders = _parseResponse(response.data);
      return instType == 'ALL' ? _sortNewestFirst(orders) : orders;
    } on BackendDataException catch (e) {
      _mapBackendError(e);
    } on DioException catch (e) {
      _handleDioError(e);
      rethrow;
    }
  }

  /// Lấy danh sách LỊCH SỬ lệnh (7 ngày qua)
  Future<List<OkxOrder>> getOrdersHistory({
    required String instType,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _client.get(
        '/api/v5/trade/orders-history',
        queryParameters: {'instType': instType},
        session: _session,
        cancelToken: cancelToken,
      );

      final orders = _parseResponse(response.data);
      return instType == 'ALL' ? _sortNewestFirst(orders) : orders;
    } on BackendDataException catch (e) {
      _mapBackendError(e);
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

    return indexes.map((index) => orders[index]).toList();
  }

  // --- Hàm hỗ trợ xử lý lỗi dùng chung ---
  void _handleDioError(DioException e) {
    final cancelled = e.type == DioExceptionType.cancel;
    final statusCode = e.response?.statusCode;
    final message = switch (statusCode) {
      401 => 'Phiên giao dịch đã hết hạn. Hãy đăng nhập lại.',
      429 => 'Dữ liệu giao dịch đang bị giới hạn. Hãy thử lại sau.',
      _ => 'Không thể tải dữ liệu giao dịch từ máy chủ.',
    };
    throw BackendDataException(
      code: cancelled
          ? 'request_cancelled'
          : statusCode == null
          ? 'network_error'
          : 'http_error',
      message: cancelled ? 'The foreground read was cancelled.' : message,
      statusCode: statusCode,
      retryAfter: e.response?.headers.value('retry-after'),
    );
  }

  Never _mapBackendError(BackendDataException error) {
    final message = switch (error.statusCode) {
      401 => 'Phiên giao dịch đã hết hạn. Hãy đăng nhập lại.',
      429 => 'Dữ liệu giao dịch đang bị giới hạn. Hãy thử lại sau.',
      _ => error.message,
    };
    throw BackendDataException(
      code: error.code,
      message: message,
      statusCode: error.statusCode,
      retryAfter: error.retryAfter,
    );
  }
}
