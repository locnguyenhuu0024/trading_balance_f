import 'package:flutter/material.dart';

import '../../../domain/risk/risk_models.dart';
import '../../risk_vietnamese_formatter.dart';
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
        const RiskQuality.unavailable(reason: 'Phục hồi chưa khả dụng');
    final effectiveQuality = riskComponentQuality(quality, assessment);
    final state = assessment?.state;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          riskVi('recoveryCosts'),
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Phục hồi dùng chi phí đã xác minh và ghi rõ các giá trị dự phóng. Khi thiếu dữ liệu bao phủ, giá trị giữ là -.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        _RecoveryCard(
          title: riskVi('recoveryRisk'),
          state: state,
          stateQuality: effectiveQuality,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Metric(
                label: riskVi('distanceToTrueExit'),
                value: riskMaskedPercent(item?.distanceToTrueExit, hideValues),
                hideValues: hideValues,
              ),
              _Metric(
                label: riskVi('holdingBurden30d'),
                value: riskMaskedPercent(item?.holdingBurden, hideValues),
                hideValues: hideValues,
              ),
              _Metric(
                label: riskVi('holdingCostDay'),
                value: riskMaskedValue(
                  metric?.holdingCostPerDay.value,
                  hideValues,
                  suffix: ' USDT',
                ),
                hideValues: hideValues,
              ),
              _Metric(
                label: riskVi('holdingCost7d'),
                value: riskMaskedValue(
                  metric?.holdingCost7d.value,
                  hideValues,
                  suffix: ' USDT',
                ),
                hideValues: hideValues,
              ),
              _Metric(
                label: riskVi('holdingCost30d'),
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
          title: riskVi('trueExitPrice'),
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
                    ? 'Mức bao phủ chi phí trọn đời đã xác minh chưa đầy đủ.'
                    : 'Mức đầy đủ chi phí đã xác minh được thiết lập cho tập này.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Đây là mô hình chi phí, không phải điểm hòa vốn được sàn bảo đảm hay giá khớp có thể thực thi.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _RecoveryCard(
          title: riskVi('interestCoverage'),
          state: null,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Metric(
                label: riskVi('actualToday'),
                value: riskMaskedValue(
                  metric?.actualInterestToday.value,
                  hideValues,
                  suffix: ' USDT',
                ),
                hideValues: hideValues,
              ),
              _Metric(
                label: riskVi('knownSubtotal'),
                value: riskMaskedValue(
                  metric?.knownInterestToday.value,
                  hideValues,
                  suffix: ' USDT',
                ),
                hideValues: hideValues,
              ),
              _Metric(
                label: riskVi('projectedTrueExit'),
                value: riskMaskedValue(
                  metric?.projectedTrueExitPrice.value,
                  hideValues,
                  suffix: ' USDT',
                ),
                hideValues: hideValues,
              ),
              _Metric(
                label: riskVi('knownCostExit'),
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
            'Thiếu dữ liệu đầu vào: ${riskRedactRiskText(item!.recoveryAssessment.missingReasons.map(riskViGenerated).join('; '), hideValues)}',
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
