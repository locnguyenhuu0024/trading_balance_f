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
final ordersFutureProvider = FutureProvider.autoDispose<List<OkxOrder>>((
  ref,
) async {
  final isSessionLoading = ref.watch(
    tradeSessionProvider.select((state) => state.isLoading),
  );
  final currentFilter = ref.watch(orderFilterProvider);
  final currentTab = ref.watch(orderTabProvider);

  if (currentTab == OrderTab.positions) return [];

  final generation = ref.watch(
    backendDataSessionProvider.select((session) => session.generation),
  );
  final backendSession = ref.read(backendDataSessionProvider);
  if (isSessionLoading) {
    throw const BackendDataException(
      code: 'session_loading',
      message: 'Đang kiểm tra phiên giao dịch. Vui lòng đợi một chút.',
    );
  }
  final session = backendSession.current;
  if (session == null) {
    throw const BackendDataException(
      code: 'authentication_required',
      message: 'Vui lòng đăng nhập để xem lệnh giao dịch.',
      statusCode: 401,
    );
  }

  final repository = ref.read(orderRepositoryProvider);
  final gate = ref.read(foregroundReadGateProvider);
  final requestType = currentTab == OrderTab.pending ? 'pending' : 'history';
  var callerActive = true;
  final lease = gate.acquire<List<OkxOrder>>(
    sessionIdentity: backendSession,
    generation: generation,
    requestKey: 'orders/$requestType/$currentFilter',
    canStart: () =>
        callerActive &&
        !ref.read(tradeSessionProvider).isLoading &&
        backendSession.matches(generation, session),
    load: (cancelToken) => currentTab == OrderTab.pending
        ? repository.getPendingOrders(
            instType: currentFilter,
            cancelToken: cancelToken,
          )
        : repository.getOrdersHistory(
            instType: currentFilter,
            cancelToken: cancelToken,
          ),
    isTransientFailure: isTransientForegroundReadFailure,
    isCancellationFailure: isForegroundReadCancellation,
    retryAfter: foregroundReadRetryAfter,
  );
  ref.onDispose(() {
    callerActive = false;
    lease.release();
  });
  return await lease.future;
});

/// Provider lấy danh sách VỊ THẾ MỞ (Chỉ áp dụng cho tab Vị thế)
final positionsFutureProvider = FutureProvider.autoDispose<List<OkxPosition>>((
  ref,
) async {
  final currentFilter = ref.watch(orderFilterProvider);
  if (currentFilter == 'SPOT') return [];

  final isSessionLoading = ref.watch(
    tradeSessionProvider.select((state) => state.isLoading),
  );
  final generation = ref.watch(
    backendDataSessionProvider.select((session) => session.generation),
  );
  final backendSession = ref.read(backendDataSessionProvider);
  if (isSessionLoading) {
    throw const BackendDataException(
      code: 'session_loading',
      message: 'Đang kiểm tra phiên giao dịch. Vui lòng đợi một chút.',
    );
  }
  final session = backendSession.current;
  if (session == null) {
    throw const BackendDataException(
      code: 'authentication_required',
      message: 'Vui lòng đăng nhập để xem vị thế giao dịch.',
      statusCode: 401,
    );
  }

  final repository = ref.read(orderRepositoryProvider);
  final gate = ref.read(foregroundReadGateProvider);
  var callerActive = true;
  final lease = gate.acquire<List<OkxPosition>>(
    sessionIdentity: backendSession,
    generation: generation,
    requestKey: 'orders/positions/raw/$currentFilter',
    canStart: () =>
        callerActive &&
        !ref.read(tradeSessionProvider).isLoading &&
        backendSession.matches(generation, session),
    load: (cancelToken) => repository.getOpenPositions(
      instType: currentFilter,
      cancelToken: cancelToken,
    ),
    isTransientFailure: isTransientForegroundReadFailure,
    isCancellationFailure: isForegroundReadCancellation,
    retryAfter: foregroundReadRetryAfter,
  );
  ref.onDispose(() {
    callerActive = false;
    lease.release();
  });
  return await lease.future;
});
