import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

import '../../features/connections/connections_screen.dart';
import '../exchange/exchange_models.dart';
import '../exchange/exchange_registry.dart';
import '../network/okx_read_scope.dart';

bool isTerminalAccountFailure(
  ExchangeRegistration registration,
  Object? error,
) {
  if (error == null) return false;
  return registration.profile.exchange == ExchangeId.okx
      ? isTerminalOkxReadFailure(error)
      : registration.adapter.classify(error).kind ==
            ExchangeFailureKind.credential;
}

class AccountStateView extends StatelessWidget {
  AccountStateView.fromError({
    super.key,
    required Object error,
    required this.registration,
    required this.onRetry,
  }) : credentialFailure =
           registration.adapter.classify(error).kind ==
           ExchangeFailureKind.credential;

  final ExchangeRegistration registration;
  final VoidCallback onRetry;
  final bool credentialFailure;

  @override
  Widget build(BuildContext context) => Center(
    child: Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: AppPalette.forBrightness(
            Theme.of(context).brightness == Brightness.dark,
          ).border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              credentialFailure
                  ? 'Cần kiểm tra lại kết nối'
                  : 'Không thể tải dữ liệu',
            ),
            if (credentialFailure)
              Text('${registration.profile.label} / Chính'),
            TextButton(
              onPressed: credentialFailure
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            connectionForm(registration.profile.exchange),
                      ),
                    )
                  : onRetry,
              child: Text(credentialFailure ? 'Kiểm tra kết nối' : 'Thử lại'),
            ),
          ],
        ),
      ),
    ),
  );
}

class PartialAccountNotice extends StatelessWidget {
  const PartialAccountNotice({
    super.key,
    required this.account,
    required this.spotMarginAvailable,
  });
  final AccountSnapshot account;
  final bool spotMarginAvailable;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (account.isPartial) const Text('Chưa đầy đủ'),
      for (final result in account.walletResults.where(
        (result) => !result.available,
      ))
        Text(
          'Không thể tải ví ${switch (result.wallet) {
            'USD-M' => 'USDⓈ-M',
            'Spot' => 'Spot',
            'Cross Margin' => 'Margin chéo',
            'Isolated Margin' => 'Margin riêng biệt',
            _ => result.wallet,
          }}',
        ),
      if (!spotMarginAvailable)
        const Text('Spot và Margin chỉ có trên ứng dụng'),
    ],
  );
}
