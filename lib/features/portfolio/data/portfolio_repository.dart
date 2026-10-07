import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/backend_data_client.dart';
import '../../../core/network/backend_data_session.dart';
import '../../orders/presentation/providers/trade_session_provider.dart';
import 'okx_balance_model.dart';

/// Provider cung cấp PortfolioRepository
final portfolioRepositoryProvider = Provider<PortfolioRepository>((ref) {
  final client = ref.watch(backendDataClientProvider);
  final session = ref.watch(backendDataSessionProvider);
  return PortfolioRepository(client, session);
});

class PortfolioRepository {
  final BackendDataClient _client;
  final BackendDataSession _session;

  PortfolioRepository(this._client, this._session);

  /// Gọi API lấy số dư tài khoản Trading
  Future<OkxAccountData> getAccountBalance() async {
    try {
      final response = await _client.get(
        '/api/v5/account/balance',
        session: _session,
      );

      final balanceResponse = OkxBalanceResponse.fromJson(response.data);

      if (balanceResponse.code == '0' && balanceResponse.data.isNotEmpty) {
        // Code '0' nghĩa là thành công. Data thường trả về 1 mảng có 1 phần tử
        return balanceResponse.data.first;
      } else {
        throw Exception('Lỗi từ OKX API: ${balanceResponse.msg}');
      }
    } on BackendDataException {
      rethrow;
    } on DioException catch (e) {
      // Xử lý các lỗi HTTP (401 sai key, 429 quá rate limit, lỗi mạng...)
      if (e.response?.statusCode == 401) {
        throw Exception('Phiên giao dịch đã hết hạn. Hãy đăng nhập lại.');
      } else if (e.response?.statusCode == 429) {
        throw Exception('Dữ liệu tài khoản đang bị giới hạn. Hãy thử lại sau.');
      }
      throw Exception('Không thể tải số dư từ máy chủ giao dịch.');
    } catch (e) {
      throw Exception('Đã xảy ra lỗi không xác định: $e');
    }
  }
}
