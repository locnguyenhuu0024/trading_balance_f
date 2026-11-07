import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

import '../../../../core/exchange/exchange_models.dart';

class MarginAccountCard extends StatelessWidget {
  const MarginAccountCard({super.key, required this.row, this.estimateText});
  final MarginAccountRow row;
  final String? estimateText;

  @override
  Widget build(BuildContext context) {
    final key = row.key;
    final isolated = key != null;
    String value(String? text) => text == null || text.isEmpty ? '—' : text;
    return Card(
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isolated
                  ? 'Isolated Margin · ${key.base != null && key.quote != null ? '${key.base}/${key.quote}' : key.nativeId}'
                  : 'Cross Margin · ${row.asset ?? '—'}',
            ),
            if (isolated) ...[
              Text(
                '${key.base ?? '—'}: Net ${value(row.baseNet)} · Vay ${value(row.baseBorrowed)} · Lãi vay ${value(row.baseInterest)}',
              ),
              Text(
                '${key.quote ?? '—'}: Net ${value(row.quoteNet)} · Vay ${value(row.quoteBorrowed)} · Lãi vay ${value(row.quoteInterest)}',
              ),
            ] else ...[
              Text('Net: ${value(row.net)}'),
              Text('Vay: ${value(row.borrowed)}'),
              Text('Lãi vay: ${value(row.interest)}'),
            ],
            if (estimateText != null) Text(estimateText!),
            Text('Mức ký quỹ: ${value(row.marginLevel)}'),
            if (isolated) ...[
              Text('Giá thanh lý: ${value(row.liquidation)}'),
              Text('Giá chỉ số: ${value(row.indexPrice)}'),
            ],
          ],
        ),
      ),
    );
  }
}
