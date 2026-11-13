import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/exchange/exchange_models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/pnl_color.dart';
import '../../../../core/widgets/crypto_icon.dart';
import '../../../../exchanges/binance/binance_estimated_pnl.dart';

String _num(String? text) {
  if (text == null || text.isEmpty) return '—';
  final number = double.tryParse(text);
  if (number == null || !number.isFinite) return text;
  if (number == 0) return '0.00';
  final magnitude = number.abs();
  if (magnitude >= 0.01) return number.toStringAsFixed(2);
  final digits = (1 - (math.log(magnitude) / math.ln10).floor()).clamp(2, 8);
  return number.toStringAsFixed(digits);
}

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
            Table(
              columnWidths: const {
                0: IntrinsicColumnWidth(),
                1: FlexColumnWidth(),
                2: FlexColumnWidth(),
                3: FlexColumnWidth(),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(children: [
                  const SizedBox.shrink(),
                  for (final label in ['Net', 'Vay', 'Lãi vay'])
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(label, textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: palette.muted)),
                    ),
                ]),
                for (final values in isolated
                    ? [
                        [key.base ?? '—', row.baseNet, row.baseBorrowed, row.baseInterest],
                        [key.quote ?? '—', row.quoteNet, row.quoteBorrowed, row.quoteInterest],
                      ]
                    : [[row.asset ?? '—', row.net, row.borrowed, row.interest]])
                  TableRow(children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 2, right: 8),
                      child: Text(values[0]!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: palette.ink)),
                    ),
                    for (final value in values.skip(1))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(_num(value), textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: palette.ink, fontFeatures: const [FontFeature.tabularFigures()])),
                      ),
                  ]),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 4, runSpacing: 2, children: [
              detail('Mức ký quỹ ${_num(row.marginLevel)}'),
              if (isolated) ...[
                detail('·'),
                detail('Giá thanh lý ${_num(row.liquidation)}'),
                detail('·'),
                detail('Giá chỉ số ${_num(row.indexPrice)}'),
              ],
            ]),
          ],
        ),
      ),
    );
  }
}
