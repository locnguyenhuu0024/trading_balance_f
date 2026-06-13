// File Name: order_provider.dart
// File Path: lib/features/orders/presentation/providers/order_provider.dart
// Note: Quản lý State cho Lệnh và Vị thế

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/order_repository.dart';
import '../../data/okx_order_model.dart';
import '../../data/okx_position_model.dart'; // Import thêm Position model

/// Lưu trạng thái bộ lọc loại giao dịch. Đổi mặc định thành SWAP (Hợp đồng vĩnh cửu)
final orderFilterProvider = StateProvider<String>((ref) => 'MARGIN');

/// Thêm trạng thái 'positions' (Vị thế mở) vào Tab
enum OrderTab { positions, pending, history }
final orderTabProvider = StateProvider<OrderTab>((ref) => OrderTab.positions);

/// Provider lấy danh sách LỆNH (Áp dụng cho tab Đang chờ và Lịch sử)
final ordersFutureProvider = FutureProvider.autoDispose<List<OkxOrder>>((ref) async {
  final repository = ref.watch(orderRepositoryProvider);
  final currentFilter = ref.watch(orderFilterProvider);
  final currentTab = ref.watch(orderTabProvider);

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

  return await repository.getOpenPositions(instType: currentFilter);
});