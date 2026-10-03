import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/trade_api_client.dart';

Future<bool> showTradeActionConfirmation(
  BuildContext context, {
  required PreparedTradeAction prepared,
  required String title,
  required String confirmLabel,
  bool destructive = false,
  bool accountWide = false,
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
    ),
  );
  return confirmed == true;
}

class _TradeActionConfirmationDialog extends StatefulWidget {
  const _TradeActionConfirmationDialog({
    required this.prepared,
    required this.title,
    required this.confirmLabel,
    required this.destructive,
    required this.accountWide,
  });

  final PreparedTradeAction prepared;
  final String title;
  final String confirmLabel;
  final bool destructive;
  final bool accountWide;

  @override
  State<_TradeActionConfirmationDialog> createState() =>
      _TradeActionConfirmationDialogState();
}

class _TradeActionConfirmationDialogState
    extends State<_TradeActionConfirmationDialog> {
  bool _confirming = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final targets = widget.prepared.targets;
    final targetCount =
        widget.prepared.summary['targetCount'] ?? targets.length;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 440,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 440),
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                widget.accountWide
                    ? 'Lệnh này bao gồm toàn bộ $targetCount vị thế được máy chủ xác nhận, không phụ thuộc bộ lọc đang chọn.'
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
