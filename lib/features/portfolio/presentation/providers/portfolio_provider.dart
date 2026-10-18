// File Name: portfolio_provider.dart
// File Path: lib/features/portfolio/presentation/providers/portfolio_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/okx_read_scope.dart';
import '../../data/portfolio_repository.dart';
import '../../data/okx_balance_model.dart';

/// Local OKX credential state, not the backend session, owns this read.
final portfolioFutureProvider = FutureProvider.autoDispose<OkxAccountData>((
  ref,
) async {
  final repository = ref.read(portfolioRepositoryProvider);
  return runOkxPrivateRead<OkxAccountData>(
    ref: ref,
    requestKey: 'portfolio/balance',
    load: (cancelToken) =>
        repository.getAccountBalance(cancelToken: cancelToken),
  );
});
