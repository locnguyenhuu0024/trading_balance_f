// File Name: order_provider.dart
// File Path: lib/features/orders/presentation/providers/order_provider.dart
// Note: Quản lý State cho Lệnh và Vị thế

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/backend_data_client.dart';
import '../../data/order_repository.dart';
import '../../data/okx_order_model.dart';
import '../../data/okx_position_model.dart'; // Import thêm Position model
import 'trade_session_provider.dart';

/// Lưu trạng thái bộ lọc loại giao dịch. Mặc định hiển thị tất cả loại giao dịch.
final orderFilterProvider = StateProvider<String>((ref) => 'ALL');

/// Thêm trạng thái 'positions' (Vị thế mở) vào Tab
enum OrderTab { positions, pending, history }
final orderTabProvider = StateProvider<OrderTab>((ref) => OrderTab.positions);

/// Provider lấy danh sách LỆNH (Áp dụng cho tab Đang chờ và Lịch sử)
final ordersFutureProvider = FutureProvider.autoDispose<List<OkxOrder>>((ref) async {
  final repository = ref.watch(orderRepositoryProvider);
  final currentFilter = ref.watch(orderFilterProvider);
  final currentTab = ref.watch(orderTabProvider);

  if (currentTab == OrderTab.positions) return [];

  final tradeState = ref.watch(tradeSessionProvider);
  final backendSession = ref.watch(backendDataSessionProvider);
  if (tradeState.isLoading) {
    throw const BackendDataException(
      code: 'session_loading',
      message: 'Đang kiểm tra phiên giao dịch. Vui lòng đợi một chút.',
    );
  }
  if (backendSession.current == null) {
    throw const BackendDataException(
      code: 'authentication_required',
      message: 'Vui lòng đăng nhập để xem lệnh giao dịch.',
      statusCode: 401,
    );
  }

  if (currentTab == OrderTab.pending) {
    return await repository.getPendingOrders(instType: currentFilter);
  } else if (currentTab == OrderTab.history) {
    return await repository.getOrdersHistory(instType: currentFilter);
  }
  return []; // Trả về rỗng nếu là tab vị thế (để an toàn)
});

/// Provider lấy danh sách VỊ THẾ MỞ (Chỉ áp dụng cho tab Vị thế)
final positionsFutureProvider = FutureProvider.autoDispose<List<OkxPosition>>((ref) async {
  final repository = ref.watch(orderRepositoryProvider);
  final currentFilter = ref.watch(orderFilterProvider);
  if (currentFilter == 'SPOT') return [];

  final tradeState = ref.watch(tradeSessionProvider);
  final backendSession = ref.watch(backendDataSessionProvider);
  if (tradeState.isLoading) {
    throw const BackendDataException(
      code: 'session_loading',
      message: 'Đang kiểm tra phiên giao dịch. Vui lòng đợi một chút.',
    );
  }
  if (backendSession.current == null) {
    throw const BackendDataException(
      code: 'authentication_required',
      message: 'Vui lòng đăng nhập để xem vị thế giao dịch.',
      statusCode: 401,
    );
  }

  return await repository.getOpenPositions(instType: currentFilter);
});
