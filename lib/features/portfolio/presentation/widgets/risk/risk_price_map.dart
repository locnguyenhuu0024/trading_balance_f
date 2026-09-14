import 'package:flutter/material.dart';

import '../../../domain/risk/risk_models.dart';
import '../../risk_vietnamese_formatter.dart';
import 'risk_overview.dart';

class RiskPriceMap extends StatelessWidget {
  const RiskPriceMap({
    super.key,
    required this.levels,
    this.currentPrice,
    this.hideValues = false,
  });

  final List<RiskPriceMapLevel> levels;
  final double? currentPrice;
  final bool hideValues;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ordered = [...levels]
      ..sort((left, right) => left.price.compareTo(right.price));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                riskVi('priceMapTitle'),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (currentPrice != null)
              Text(
                '${riskVi('current')} ${riskMaskedValue(currentPrice, hideValues)}',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          riskVi('priceMapDescription'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        if (ordered.isEmpty)
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                riskVi('priceMapUnavailable'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          )
        else
          Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.dividerColor),
            ),
            child: Column(
              children: [
                for (var index = 0; index < ordered.length; index++) ...[
                  _PriceLevel(
                    level: ordered[index],
                    currentPrice: currentPrice,
                    hideValues: hideValues,
                  ),
                  if (index < ordered.length - 1)
                    Divider(height: 1, color: theme.dividerColor),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _PriceLevel extends StatelessWidget {
  const _PriceLevel({
    required this.level,
    required this.currentPrice,
    required this.hideValues,
  });

  final RiskPriceMapLevel level;
  final double? currentPrice;
  final bool hideValues;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCurrent =
        currentPrice != null && (level.price - currentPrice!).abs() < 1e-9;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isCurrent
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  riskMaskedValue(level.price, hideValues, suffix: ' USDT'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                if (level.labels.isEmpty)
                  Text(
                    riskVi('observedLevel'),
                    style: theme.textTheme.bodySmall,
                  )
                else
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: [
                      for (final label in level.labels)
                        Chip(
                          label: Text(
                            riskRedactRiskText(
                              riskViPriceMapLabel(label),
                              hideValues,
                            ),
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
