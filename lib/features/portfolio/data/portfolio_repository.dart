import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/okx_data_client.dart';
import 'okx_balance_model.dart';

/// Provider for the direct, credential-backed OKX portfolio reader.
final portfolioRepositoryProvider = Provider<PortfolioRepository>((ref) {
  return PortfolioRepository(ref.watch(okxDataClientProvider));
});

class PortfolioRepository {
  PortfolioRepository(this._client);

  final OkxDataClient _client;

  /// Loads the authenticated OKX account balance using local OKX credentials.
  Future<OkxAccountData> getAccountBalance({CancelToken? cancelToken}) async {
    final response = await _client.get(
      '/api/v5/account/balance',
      cancelToken: cancelToken,
    );
    final body = response.data;
    if (body is! Map<String, dynamic>) {
      throw const OkxDataException(
        code: 'okx_invalid_response',
        message: 'OKX returned an invalid account balance response.',
      );
    }

    final balanceResponse = OkxBalanceResponse.fromJson(body);
    if (balanceResponse.code == '0' && balanceResponse.data.isNotEmpty) {
      return balanceResponse.data.first;
    }
    throw OkxDataException(
      code: 'okx_api_error',
      message: balanceResponse.code == '0'
          ? 'OKX returned no account balance.'
          : 'OKX rejected the account balance read.',
    );
  }
}
