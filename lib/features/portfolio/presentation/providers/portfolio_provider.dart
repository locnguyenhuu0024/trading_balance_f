// File Name: portfolio_provider.dart
// File Path: lib/features/portfolio/presentation/providers/portfolio_provider.dart
// Note: Riverpod Provider này chịu trách nhiệm gọi API lấy số dư và quản lý trạng thái Loading/Data/Error của màn hình Portfolio.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/backend_data_client.dart';
import '../../data/portfolio_repository.dart';
import '../../data/okx_balance_model.dart';
import '../../../orders/presentation/providers/trade_session_provider.dart';

/// Sử dụng autoDispose để giải phóng bộ nhớ khi không ai lắng nghe provider này,
/// nhưng thực tế với màn hình chính (trang chủ) ta có thể bỏ autoDispose tuỳ nhu cầu.
final portfolioFutureProvider = FutureProvider.autoDispose<OkxAccountData>((ref) async {
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
      message: 'Vui lòng đăng nhập để xem số dư giao dịch.',
      statusCode: 401,
    );
  }

  // Lấy instance của repository từ provider đã định nghĩa ở Bước 3
  final repository = ref.watch(portfolioRepositoryProvider);

  // Gọi API
  return await repository.getAccountBalance();
});
