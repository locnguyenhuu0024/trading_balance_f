import 'package:flutter/material.dart';

import '../../../../core/exchange/exchange_models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/pnl_color.dart';
import '../../../../core/widgets/crypto_icon.dart';
import '../../../../exchanges/binance/binance_estimated_pnl.dart';

class MarginAccountCard extends StatelessWidget {
  const MarginAccountCard({super.key, required this.row, this.estimate, this.rate = 1, this.unit = 'USDT'});
  final MarginAccountRow row;
  final EstimatedPnlRow? estimate;
  final double rate;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final key = row.key;
    final isolated = key != null;
    final palette = AppPalette.forBrightness(Theme.of(context).brightness == Brightness.dark);
    final e = estimate?.estimate;
    final percentage = estimate?.percentage;
    final pair = isolated ? (key.base != null && key.quote != null ? '${key.base}/${key.quote}' : key.nativeId) : (row.asset ?? '—');
    final base = isolated ? (key.base ?? key.nativeId) : (row.asset ?? '—');
    String value(String? text) => text == null || text.isEmpty ? '—' : text;
    String signed(double n) => '${n >= 0 ? '+' : ''}${n.toStringAsFixed(2)}';
    Widget detail(String text) => Text(text, style: TextStyle(fontSize: 12, color: palette.muted));
    return Card(
      elevation: 0,
      color: palette.raised,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
        side: BorderSide(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Row(mainAxisSize: MainAxisSize.min, children: [
                CryptoIcon(symbol: base, size: 20, backgroundColor: palette.surface, textColor: palette.ink, textSize: 10),
                const SizedBox(width: 6),
                Text(pair, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: palette.ink)),
              ]))),
              const SizedBox(width: 8),
              Flexible(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(AppTokens.radiusSmall)),
                child: Text(isolated ? 'Isolated Margin' : 'Cross Margin', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: palette.ink)),
              ))),
            ]),
            if (e != null) ...[
              const SizedBox(height: 8),
              Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 6, children: [
                Text('${signed(e.profit * rate)} $unit', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: resolvePnlColor(e.profit, palette, hidden: false))),
                if (percentage != null) Text('(${signed(percentage)}%)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: resolvePnlColor(e.profit, palette, hidden: false))),
              ]),
              detail('Lãi/lỗ ước tính'),
              detail('Giá vốn TB ${(e.average * rate).toStringAsFixed(2)}${e.ratio < 0.999999 ? ' · tính trên ${(e.ratio * 100).toStringAsFixed(0)}% lượng' : ''}${estimate!.stale ? ' · chưa cập nhật' : ''}${estimate!.message != null ? ' · ${estimate!.message}' : ''}'),
            ] else if (estimate?.message != null) ...[
              const SizedBox(height: 8),
              Text(estimate!.message!, style: TextStyle(fontSize: 13, color: palette.muted)),
            ],
            Divider(height: 16, color: palette.border),
            if (isolated) ...[
              detail(
                '${key.base ?? '—'}: Net ${value(row.baseNet)} · Vay ${value(row.baseBorrowed)} · Lãi vay ${value(row.baseInterest)}',
              ),
              detail(
                '${key.quote ?? '—'}: Net ${value(row.quoteNet)} · Vay ${value(row.quoteBorrowed)} · Lãi vay ${value(row.quoteInterest)}',
              ),
            ] else ...[
              detail('Net: ${value(row.net)}'),
              detail('Vay: ${value(row.borrowed)}'),
              detail('Lãi vay: ${value(row.interest)}'),
            ],
            detail('Mức ký quỹ: ${value(row.marginLevel)}'),
            if (isolated) ...[
              detail('Giá thanh lý: ${value(row.liquidation)}'),
              detail('Giá chỉ số: ${value(row.indexPrice)}'),
            ],
          ],
        ),
      ),
    );
  }
}
