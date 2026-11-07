import 'package:flutter/material.dart';

import '../../../../core/exchange/exchange_models.dart';

class MarginAccountCard extends StatelessWidget {
  const MarginAccountCard({super.key, required this.row});
  final MarginAccountRow row;

  @override
  Widget build(BuildContext context) {
    final key = row.key;
    final isolated = key != null;
    String value(String? text) => text == null || text.isEmpty ? '—' : text;
    return Card(
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
                '${key.base ?? '—'}: Net ${value(row.baseNet)} · Vay ${value(row.baseBorrowed)} · Lãi ${value(row.baseInterest)}',
              ),
              Text(
                '${key.quote ?? '—'}: Net ${value(row.quoteNet)} · Vay ${value(row.quoteBorrowed)} · Lãi ${value(row.quoteInterest)}',
              ),
            ] else ...[
              Text('Net: ${value(row.net)}'),
              Text('Vay: ${value(row.borrowed)}'),
              Text('Lãi: ${value(row.interest)}'),
            ],
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
