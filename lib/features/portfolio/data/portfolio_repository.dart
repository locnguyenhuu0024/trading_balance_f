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
  Future<OkxAccountData> getAccountBalance({CancelToken? cancelToken}) async {
    try {
      final response = await _client.get(
        '/api/v5/account/balance',
        session: _session,
        cancelToken: cancelToken,
      );

      final balanceResponse = OkxBalanceResponse.fromJson(response.data);

      if (balanceResponse.code == '0' && balanceResponse.data.isNotEmpty) {
        // Code '0' nghĩa là thành công. Data thường trả về 1 mảng có 1 phần tử
        return balanceResponse.data.first;
      } else {
        throw Exception('Lỗi từ OKX API: ${balanceResponse.msg}');
      }
    } on BackendDataException catch (e) {
      final message = switch (e.statusCode) {
        401 => 'Phiên giao dịch đã hết hạn. Hãy đăng nhập lại.',
        429 => 'Dữ liệu tài khoản đang bị giới hạn. Hãy thử lại sau.',
        _ => e.message,
      };
      throw BackendDataException(
        code: e.code,
        message: message,
        statusCode: e.statusCode,
        retryAfter: e.retryAfter,
      );
    } on DioException catch (e) {
      final cancelled = e.type == DioExceptionType.cancel;
      // Xử lý các lỗi HTTP (401 sai key, 429 quá rate limit, lỗi mạng...)
      final statusCode = e.response?.statusCode;
      final message = switch (statusCode) {
        401 => 'Phiên giao dịch đã hết hạn. Hãy đăng nhập lại.',
        429 => 'Dữ liệu tài khoản đang bị giới hạn. Hãy thử lại sau.',
        _ => 'Không thể tải số dư từ máy chủ giao dịch.',
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
    } catch (e) {
      throw Exception('Đã xảy ra lỗi không xác định: $e');
    }
  }
}
