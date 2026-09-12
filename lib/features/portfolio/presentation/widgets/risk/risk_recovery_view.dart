import 'package:flutter/material.dart';

import '../../../domain/risk/risk_models.dart';
import 'risk_overview.dart';

class RiskRecoveryView extends StatelessWidget {
  const RiskRecoveryView({
    super.key,
    required this.evaluation,
    this.stateQuality,
    this.hideValues = false,
  });

  final RiskEvaluation? evaluation;
  final RiskQuality? stateQuality;
  final bool hideValues;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = evaluation;
    final assessment = item?.recoveryAssessment;
    final metric = item?.metrics;
    final quality =
        stateQuality ??
        item?.quality ??
        const RiskQuality.unavailable(reason: 'Recovery unavailable');
    final effectiveQuality = riskComponentQuality(quality, assessment);
    final state = assessment?.state;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Recovery and costs',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Recovery uses verified costs and clearly labels projections. Missing coverage stays -.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        _RecoveryCard(
          title: 'Recovery risk',
          state: state,
          stateQuality: effectiveQuality,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Metric(
                label: 'Distance to True Exit',
                value: riskMaskedPercent(item?.distanceToTrueExit, hideValues),
                hideValues: hideValues,
              ),
              _Metric(
                label: '30-day holding burden',
                value: riskMaskedPercent(item?.holdingBurden, hideValues),
                hideValues: hideValues,
              ),
              _Metric(
                label: 'Holding cost / day',
                value: riskMaskedValue(
                  metric?.holdingCostPerDay.value,
                  hideValues,
                  suffix: ' USDT',
                ),
                hideValues: hideValues,
              ),
              _Metric(
                label: 'Holding cost / 7d',
                value: riskMaskedValue(
                  metric?.holdingCost7d.value,
                  hideValues,
                  suffix: ' USDT',
                ),
                hideValues: hideValues,
              ),
              _Metric(
                label: 'Holding cost / 30d',
                value: riskMaskedValue(
                  metric?.holdingCost30d.value,
                  hideValues,
                  suffix: ' USDT',
                ),
                hideValues: hideValues,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _RecoveryCard(
          title: 'True Exit price',
          state: null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                riskMaskedValue(
                  item?.trueExitPrice,
                  hideValues,
                  suffix: ' USDT',
                ),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item?.trueExitPrice == null
                    ? 'Verified lifetime cost coverage is incomplete.'
                    : 'Verified cost completeness is established for this episode.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'This is a cost model, not a guaranteed exchange breakeven or executable fill price.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _RecoveryCard(
          title: 'Interest coverage',
          state: null,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Metric(
                label: 'Actual today',
                value: riskMaskedValue(
                  metric?.actualInterestToday.value,
                  hideValues,
                  suffix: ' USDT',
                ),
                hideValues: hideValues,
              ),
              _Metric(
                label: 'Known subtotal',
                value: riskMaskedValue(
                  metric?.knownInterestToday.value,
                  hideValues,
                  suffix: ' USDT',
                ),
                hideValues: hideValues,
              ),
              _Metric(
                label: 'Projected True Exit',
                value: riskMaskedValue(
                  metric?.projectedTrueExitPrice.value,
                  hideValues,
                  suffix: ' USDT',
                ),
                hideValues: hideValues,
              ),
              _Metric(
                label: 'Known-cost exit',
                value: riskMaskedValue(
                  metric?.knownCostExitPrice.value,
                  hideValues,
                  suffix: ' USDT',
                ),
                hideValues: hideValues,
              ),
            ],
          ),
        ),
        if (item?.recoveryAssessment.missingReasons.isNotEmpty ?? false) ...[
          const SizedBox(height: 12),
          Text(
            'Missing inputs: ${riskRedactRiskText(item!.recoveryAssessment.missingReasons.join('; '), hideValues)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _RecoveryCard extends StatelessWidget {
  const _RecoveryCard({
    required this.title,
    required this.child,
    this.state,
    this.stateQuality,
  });

  final String title;
  final Widget child;
  final RiskSeverity? state;
  final RiskQuality? stateQuality;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quality = stateQuality ?? const RiskQuality.complete();
    final color = riskQualitySeverityColor(context, quality, state);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (state != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        riskComponentStateLabel(state, quality),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.hideValues = false,
  });

  final String label;
  final String value;
  final bool hideValues;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 155,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            riskRedactRiskText(label, hideValues),
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
