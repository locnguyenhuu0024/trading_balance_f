import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import 'okx_balance_model.dart';

/// Provider cung cấp PortfolioRepository
final portfolioRepositoryProvider = Provider<PortfolioRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return PortfolioRepository(dio);
});

class PortfolioRepository {
  final Dio _dio;

  PortfolioRepository(this._dio);

  /// Gọi API lấy số dư tài khoản Trading
  Future<OkxAccountData> getAccountBalance() async {
    try {
      final response = await _dio.get(
        '/api/v5/account/balance',
        // Cờ requiresAuth rất quan trọng, nó báo cho Interceptor biết
        // cần phải tự động sinh Signature và gắn API Key vào Header.
        options: Options(extra: {'requiresAuth': true}),
      );

      final balanceResponse = OkxBalanceResponse.fromJson(response.data);

      if (balanceResponse.code == '0' && balanceResponse.data.isNotEmpty) {
        // Code '0' nghĩa là thành công. Data thường trả về 1 mảng có 1 phần tử
        return balanceResponse.data.first;
      } else {
        throw Exception('Lỗi từ OKX API: ${balanceResponse.msg}');
      }
    } on DioException catch (e) {
      // Xử lý các lỗi HTTP (401 sai key, 429 quá rate limit, lỗi mạng...)
      if (e.response?.statusCode == 401) {
        throw Exception('API Key không hợp lệ hoặc đã hết hạn.');
      } else if (e.response?.statusCode == 429) {
        throw Exception('Quá giới hạn request (Rate Limit). Thử lại sau.');
      }
      throw Exception('Lỗi kết nối mạng: ${e.message}');
    } catch (e) {
      throw Exception('Đã xảy ra lỗi không xác định: $e');
    }
  }
}