import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/trade_api_client.dart';
import '../providers/trade_session_provider.dart';

Future<bool> showTradeActionConfirmation(
  BuildContext context, {
  required PreparedTradeAction prepared,
  required String title,
  required String confirmLabel,
  bool destructive = false,
  bool accountWide = false,
  TradeSession? sessionOwner,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) => _TradeActionConfirmationDialog(
      prepared: prepared,
      title: title,
      confirmLabel: confirmLabel,
      destructive: destructive,
      accountWide: accountWide,
      sessionOwner: sessionOwner,
    ),
  );
  return confirmed == true;
}

class _TradeActionConfirmationDialog extends ConsumerStatefulWidget {
  const _TradeActionConfirmationDialog({
    required this.prepared,
    required this.title,
    required this.confirmLabel,
    required this.destructive,
    required this.accountWide,
    required this.sessionOwner,
  });

  final PreparedTradeAction prepared;
  final String title;
  final String confirmLabel;
  final bool destructive;
  final bool accountWide;
  final TradeSession? sessionOwner;

  @override
  ConsumerState<_TradeActionConfirmationDialog> createState() =>
      _TradeActionConfirmationDialogState();
}

class _TradeActionConfirmationDialogState
    extends ConsumerState<_TradeActionConfirmationDialog> {
  bool _confirming = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final currentSession = ref.watch(tradeSessionProvider).session;
    final sessionChanged =
        widget.sessionOwner != null &&
        !identical(currentSession, widget.sessionOwner);
    final targets = widget.prepared.targets;
    final targetCount =
        widget.prepared.summary['targetCount'] ?? targets.length;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 440),
          child: ListView(
            shrinkWrap: true,
            children: sessionChanged
                ? const [
                    Text('Phiên giao dịch đã thay đổi. Hãy đóng xác nhận này.'),
                  ]
                : [
                    Text(
                      widget.accountWide
                          ? 'Lệnh này bao gồm toàn bộ $targetCount vị thế được máy chủ xác nhận, không phụ thuộc bộ lọc đang chọn.'
                          : widget.prepared.action == 'cancel_order'
                          ? 'Chỉ hủy khối lượng còn lại đã được máy chủ xác nhận. Khối lượng đã khớp được giữ nguyên.'
                          : 'Xác nhận đúng vị thế và giá trị mà máy chủ đã chuẩn bị. Giá thị trường không được đảm bảo.',
                    ),
                    const SizedBox(height: AppTokens.space3),
                    if (targets.isEmpty)
                      const Text('Máy chủ không trả về danh sách mục tiêu.')
                    else
                      ...targets.map(_buildTarget),
                    const SizedBox(height: AppTokens.space2),
                    Text(
                      'Xác nhận hết hạn: ${widget.prepared.expiresAt}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _confirming
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Hủy'),
        ),
        if (!sessionChanged)
          FilledButton(
            onPressed: _confirming
                ? null
                : () {
                    setState(() => _confirming = true);
                    Navigator.of(context).pop(true);
                  },
            style: widget.destructive
                ? FilledButton.styleFrom(
                    backgroundColor: palette.negative,
                    foregroundColor: palette.onStrong,
                  )
                : null,
            child: Text(widget.confirmLabel),
          ),
      ],
    );
  }

  Widget _buildTarget(Map<String, dynamic> target) {
    final identity = _asMap(target['identity']);
    if (widget.prepared.action == 'cancel_order') {
      final instrumentId = _display(identity['instId']);
      final instrumentType = _display(identity['instType']);
      final orderId = _display(identity['ordId']);
      final orderType = _display(identity['ordType']);
      final side = _display(identity['side']);
      return Card(
        margin: const EdgeInsets.only(bottom: AppTokens.space2),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.space3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$instrumentId · $instrumentType · $orderType',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text('Mã lệnh: $orderId · Chiều: $side'),
              Text(
                'Giá giới hạn: ${_display(target['price'] ?? identity['px'])}',
              ),
              Text(
                'Khối lượng gốc: ${_display(target['originalSize'] ?? identity['sz'])}',
              ),
              Text('Đã khớp: ${_display(target['filledSize'])}'),
              Text(
                'Khối lượng còn lại để hủy: ${_display(target['remainingSize'])}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      );
    }
    final instrumentId = _display(identity['instrumentId']);
    final instrumentType = _display(identity['instrumentType']);
    final direction = _display(target['direction']);
    final currentSize = _display(target['currentSize']);
    final details = target.entries
        .where((entry) => entry.key != 'identity')
        .toList(growable: false);

    return Card(
      margin: const EdgeInsets.only(bottom: AppTokens.space2),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              instrumentId == '—'
                  ? instrumentType
                  : '$instrumentId · $instrumentType',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (direction != '—' || currentSize != '—')
              Text('Hướng: $direction · Khối lượng hiện tại: $currentSize'),
            for (final entry in details)
              if (entry.key != 'direction' && entry.key != 'currentSize')
                Text('${_label(entry.key)}: ${_display(entry.value)}'),
          ],
        ),
      ),
    );
  }
}

String _label(String key) {
  const labels = {
    'action': 'Thao tác',
    'amount': 'Số tiền chuẩn hóa',
    'currency': 'Đơn vị',
    'requestedSize': 'Khối lượng yêu cầu',
    'normalizedSize': 'Khối lượng chuẩn hóa',
    'sizeUnit': 'Đơn vị khối lượng',
    'lotSize': 'Bước khối lượng',
    'minimumSize': 'Khối lượng tối thiểu',
    'percentage': 'Tỷ lệ đóng',
  };
  return labels[key] ?? key;
}

String _display(dynamic value) => value == null ? '—' : value.toString();

Map<String, dynamic> _asMap(dynamic value) {
  if (value is! Map) return const {};
  return value.map((key, item) => MapEntry(key.toString(), item));
}
