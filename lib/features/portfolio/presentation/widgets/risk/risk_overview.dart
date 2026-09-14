import 'package:flutter/material.dart';

import '../../../application/risk_monitor_bridge.dart';
import '../../../domain/risk/action_plan.dart';
import '../../../domain/risk/risk_history.dart';
import '../../../domain/risk/risk_models.dart';
import '../../risk_vietnamese_formatter.dart';

String riskValue(double? value, {int decimals = 2, String suffix = ''}) {
  if (value == null || !value.isFinite) return '-';
  return '${value.toStringAsFixed(decimals)}$suffix';
}

String riskRedactRiskText(String text, bool hidden) {
  if (!hidden) return text;
  return text.replaceAll(
    RegExp(r'[-+]?(?:\d+(?:\.\d+)?|\.\d+)(?:%|x)?'),
    '******',
  );
}

String riskPercent(double? fraction, {int decimals = 1}) {
  if (fraction == null || !fraction.isFinite) return '-';
  return '${(fraction * 100).toStringAsFixed(decimals)}%';
}

String riskMaskedValue(
  double? value,
  bool hidden, {
  int decimals = 2,
  String suffix = '',
}) {
  if (value == null || !value.isFinite) return '-';
  return hidden
      ? '******'
      : riskValue(value, decimals: decimals, suffix: suffix);
}

String riskMaskedPercent(double? fraction, bool hidden, {int decimals = 1}) {
  if (fraction == null || !fraction.isFinite) return '-';
  return hidden ? '******' : riskPercent(fraction, decimals: decimals);
}

String riskMetricValue(RiskMetricValue? metric, {int decimals = 2}) {
  if (metric == null || metric.value == null || !metric.value!.isFinite) {
    return '-';
  }
  return riskValue(metric.value, decimals: decimals);
}

String riskQualityLabel(RiskQuality quality) {
  return riskViQuality(quality);
}

bool riskQualityIsCurrent(RiskQuality? quality) =>
    quality == null || quality.status == RiskQualityStatus.complete;

int _riskQualityRank(RiskQualityStatus status) {
  switch (status) {
    case RiskQualityStatus.complete:
      return 0;
    case RiskQualityStatus.partial:
      return 1;
    case RiskQualityStatus.stale:
      return 2;
    case RiskQualityStatus.unavailable:
    case RiskQualityStatus.unsupported:
    case RiskQualityStatus.empty:
      return 3;
    case RiskQualityStatus.error:
      return 4;
  }
}

/// Combines the bridge quality with a component's own assessment quality.
///
/// A complete transport snapshot does not make a component complete when the
/// component itself has missing evidence. The returned quality is used for
/// both color and wording so a known component state is always qualified.
RiskQuality riskComponentQuality(
  RiskQuality transport,
  RiskAssessment? assessment,
) {
  final component = assessment?.quality;
  final missing = assessment?.missingReasons ?? const <String>[];
  final componentStatus = component == null
      ? RiskQualityStatus.complete
      : component.status == RiskQualityStatus.complete && missing.isNotEmpty
      ? RiskQualityStatus.partial
      : component.status;
  final status =
      _riskQualityRank(transport.status) >= _riskQualityRank(componentStatus)
      ? transport.status
      : componentStatus;
  final reasons = <String>{
    if (transport.reason != null && transport.reason!.isNotEmpty)
      transport.reason!,
    if (component?.reason != null && component!.reason!.isNotEmpty)
      component.reason!,
    ...missing.where((reason) => reason.isNotEmpty),
  };
  final source = component?.source ?? transport.source;
  final observedAt = component?.observedAt ?? transport.observedAt;
  final sourceAt = component?.sourceAt ?? transport.sourceAt;
  return RiskQuality(
    status: status,
    source: source,
    reason: reasons.isEmpty ? null : reasons.join('; '),
    observedAt: observedAt,
    sourceAt: sourceAt,
  );
}

String riskComponentStateLabel(RiskSeverity? severity, RiskQuality quality) {
  if (severity == null) {
    return riskQualityIsCurrent(quality)
        ? '-'
        : '- · ${riskQualityLabel(quality)}';
  }
  if (riskQualityIsCurrent(quality)) return riskViSeverity(severity);
  return '${riskVi('atLeast')} ${riskViSeverity(severity)} · ${riskQualityLabel(quality)}';
}

String riskKnownSeverityQualifier(RiskSeverity? severity, RiskQuality quality) {
  if (severity == null) return riskQualityLabel(quality);
  if (riskQualityIsCurrent(quality)) return riskQualityLabel(quality);
  return '${riskVi('lastKnown')} ${riskViSeverity(severity)} · ${riskQualityLabel(quality)}';
}

String riskStateLabelWithQuality(RiskSeverity? severity, RiskQuality quality) {
  if (severity == null) return '-';
  if (riskQualityIsCurrent(quality)) return riskViSeverity(severity);
  return '${riskVi('lastKnown')} ${riskViSeverity(severity)} · ${riskQualityLabel(quality)}';
}

Color riskQualitySeverityColor(
  BuildContext context,
  RiskQuality quality,
  RiskSeverity? severity,
) {
  if (riskQualityIsCurrent(quality)) {
    return riskSeverityColor(context, severity);
  }
  return switch (quality.status) {
    RiskQualityStatus.partial => Colors.amber.shade800,
    RiskQualityStatus.stale => Colors.orange.shade800,
    RiskQualityStatus.error => Theme.of(context).colorScheme.error,
    _ => Theme.of(context).colorScheme.onSurfaceVariant,
  };
}

String riskAssessmentLabel(RiskAssessment? assessment) {
  if (assessment == null || assessment.state == null) return '-';
  return riskViSeverity(assessment.state);
}

Color riskSeverityColor(BuildContext context, RiskSeverity? severity) {
  switch (severity) {
    case RiskSeverity.normal:
      return Colors.green.shade700;
    case RiskSeverity.watch:
      return Colors.amber.shade800;
    case RiskSeverity.high:
      return Colors.deepOrange.shade700;
    case RiskSeverity.critical:
      return Colors.red.shade700;
    case null:
      return Theme.of(context).colorScheme.onSurfaceVariant;
  }
}

class RiskOverview extends StatelessWidget {
  const RiskOverview({
    super.key,
    required this.state,
    this.hideValues = false,
    this.volatilityMultiple,
    this.plan,
    this.planEvaluation,
    this.trend,
    this.velocity,
    this.onOverallTap,
    this.onPositionTap,
    this.onMarketTap,
    this.onRecoveryTap,
    this.onBufferTap,
    this.onLeverageTap,
    this.onDebtTap,
    this.onTrueExitTap,
    this.onStressTap,
    this.onPlanTap,
  });

  final RiskMonitorViewState state;
  final bool hideValues;
  final double? volatilityMultiple;
  final RiskPlan? plan;
  final RiskPlanEvaluation? planEvaluation;
  final RiskTrendResult? trend;
  final RiskVelocityResult? velocity;
  final VoidCallback? onOverallTap;
  final VoidCallback? onPositionTap;
  final VoidCallback? onMarketTap;
  final VoidCallback? onRecoveryTap;
  final VoidCallback? onBufferTap;
  final VoidCallback? onLeverageTap;
  final VoidCallback? onDebtTap;
  final VoidCallback? onTrueExitTap;
  final VoidCallback? onStressTap;
  final VoidCallback? onPlanTap;

  @override
  Widget build(BuildContext context) {
    final evaluation = state.evaluation;
    final theme = Theme.of(context);
    final stateQuality = state.quality;
    final stateIsFresh = stateQuality.status == RiskQualityStatus.complete;
    final assessment = evaluation?.overallState;
    final qualifier = !stateIsFresh && assessment != null
        ? riskKnownSeverityQualifier(assessment, stateQuality)
        : !stateIsFresh
        ? riskQualityLabel(stateQuality)
        : evaluation == null
        ? riskQualityLabel(state.quality)
        : evaluation.partial
        ? riskVi('partialAssessment')
        : riskQualityLabel(evaluation.quality);
    final trendText = riskRedactRiskText(
      riskViGenerated(trend?.text ?? velocity?.text).isEmpty
          ? '- / ${riskVi('collectingHistory')}'
          : riskViGenerated(trend?.text ?? velocity?.text),
      hideValues,
    );
    final scenario = evaluation?.stressScenarios
        .where((item) => item.percentageChange != null)
        .fold<RiskStressScenario?>(null, (found, item) {
          if (found != null) return found;
          return (item.percentageChange! - (-0.10)).abs() < 1e-9 ? item : null;
        });
    final evaluatedPlan = planEvaluation;
    final planText = evaluatedPlan == null && plan == null
        ? riskVi('noPlan')
        : evaluatedPlan != null
        ? evaluatedPlan.hasPlan
              ? hideValues
                    ? '****** ${riskVi('active')} · ****** ${riskVi('pending')}'
                    : '${evaluatedPlan.activeCount} ${riskVi('active')} · ${evaluatedPlan.unknownCount} ${riskVi('pending')}'
              : riskVi('noPlan')
        : plan!.rules.isNotEmpty || plan!.zones.isNotEmpty
        ? hideValues
              ? '****** ${riskVi('configured')}'
              : '${plan!.rules.length + plan!.zones.length} ${riskVi('configured')}'
        : riskVi('noPlan');

    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          riskVi('riskOverview'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          riskRedactRiskText(
            evaluation?.position.instrumentId ?? riskVi('noIsolatedPosition'),
            hideValues,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    return Card(
      key: const Key('risk-overview'),
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final textScale = MediaQuery.textScalerOf(context).scale(1);
                final stackHeader =
                    constraints.maxWidth < 360 || textScale >= 1.5;
                final quality = _QualityChip(
                  label: qualifier,
                  quality: state.quality,
                );
                if (stackHeader) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      heading,
                      const SizedBox(height: 8),
                      Align(alignment: Alignment.centerLeft, child: quality),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: heading),
                    quality,
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            _StatusAnswer(
              label: riskVi('overall'),
              value: riskViSeverity(assessment),
              qualifier: qualifier,
              color: riskQualitySeverityColor(
                context,
                stateQuality,
                assessment,
              ),
              icon: Icons.shield_outlined,
              onTap: onOverallTap,
            ),
            const SizedBox(height: 9),
            _ComponentChips(
              evaluation: evaluation,
              quality: stateQuality,
              showStates: true,
              onPositionTap: onPositionTap,
              onMarketTap: onMarketTap,
              onRecoveryTap: onRecoveryTap,
            ),
            if (evaluation != null) ...[
              const SizedBox(height: 10),
              _BufferHero(
                evaluation: evaluation,
                hideValues: hideValues,
                volatilityMultiple: volatilityMultiple,
                severity: evaluation.positionAssessment.state,
                stateQuality: stateQuality,
                onTap: onBufferTap,
              ),
            ],
            const SizedBox(height: 10),
            _AnswerGrid(
              answers: [
                _Answer(
                  label: riskVi('trend'),
                  value: trendText,
                  caption: velocity == null
                      ? riskVi('sinceLastCheck')
                      : riskRedactRiskText(
                          riskViGenerated(velocity!.text),
                          hideValues,
                        ),
                  icon: Icons.trending_up,
                  onTap: onOverallTap,
                ),
                _Answer(
                  label: riskVi('effectiveLeverage'),
                  value: riskMaskedValue(
                    evaluation?.effectiveLeverage,
                    hideValues,
                    decimals: 2,
                    suffix: 'x',
                  ),
                  caption: 'Giá trị giao dịch / vốn chủ sở hữu',
                  icon: Icons.stacked_line_chart,
                  onTap: onLeverageTap,
                ),
                _Answer(
                  label: riskVi('debt'),
                  value: riskMaskedValue(
                    evaluation?.debt,
                    hideValues,
                    suffix: ' USDT',
                  ),
                  caption: riskRedactRiskText(
                    riskViGenerated(
                          evaluation?.metrics.debt.quality.reason,
                        ).isEmpty
                        ? 'Khoản nợ còn lại'
                        : riskViGenerated(
                            evaluation?.metrics.debt.quality.reason,
                          ),
                    hideValues,
                  ),
                  icon: Icons.account_balance_wallet_outlined,
                  onTap: onDebtTap,
                ),
                _Answer(
                  label: riskVi('trueExit'),
                  value: riskMaskedValue(
                    evaluation?.trueExitPrice,
                    hideValues,
                    suffix: ' USDT',
                  ),
                  caption: evaluation?.trueExitPrice == null
                      ? 'Cần xác minh mức bao phủ chi phí'
                      : 'Ước tính chi phí đã xác minh',
                  icon: Icons.flag_outlined,
                  onTap: onTrueExitTap,
                ),
                _Answer(
                  label: riskVi('scenarioTenPercent'),
                  value: riskViSeverity(scenario?.overallState),
                  caption: scenario == null
                      ? 'Kịch bản chưa khả dụng'
                      : !stateIsFresh
                      ? '${riskVi('lastKnownScenario')} · ${riskQualityLabel(stateQuality)}'
                      : hideValues
                      ? '${riskVi('engineResultAt')} ******'
                      : '${riskVi('engineResultAt')} ${riskValue(scenario.price)} USDT',
                  icon: Icons.show_chart,
                  color: riskQualitySeverityColor(
                    context,
                    stateQuality,
                    scenario?.overallState,
                  ),
                  onTap: onStressTap,
                ),
                _Answer(
                  label: riskVi('planStatus'),
                  value: planText,
                  caption: plan == null
                      ? riskVi('rulesNotLoaded')
                      : riskVi('userAuthoredRulesOnly'),
                  icon: Icons.rule_folder_outlined,
                  onTap: onPlanTap,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ComponentChips extends StatelessWidget {
  const _ComponentChips({
    required this.evaluation,
    required this.quality,
    this.showStates = true,
    this.onPositionTap,
    this.onMarketTap,
    this.onRecoveryTap,
  });

  final RiskEvaluation? evaluation;
  final RiskQuality quality;
  final bool showStates;
  final VoidCallback? onPositionTap;
  final VoidCallback? onMarketTap;
  final VoidCallback? onRecoveryTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 320 ? 2 : 1;
        const gap = 7.0;
        final width = columns == 2
            ? (constraints.maxWidth - gap) / 2
            : constraints.maxWidth;
        return Wrap(
          key: const Key('risk-component-chips'),
          spacing: gap,
          runSpacing: gap,
          children: [
            SizedBox(
              width: width,
              child: _ComponentChip(
                label: riskVi('position'),
                state: showStates ? evaluation?.positionAssessment.state : null,
                assessment: showStates ? evaluation?.positionAssessment : null,
                quality: quality,
                onTap: onPositionTap,
              ),
            ),
            SizedBox(
              width: width,
              child: _ComponentChip(
                label: riskVi('market'),
                state: showStates ? evaluation?.marketAssessment.state : null,
                assessment: showStates ? evaluation?.marketAssessment : null,
                quality: quality,
                onTap: onMarketTap,
              ),
            ),
            SizedBox(
              width: width,
              child: _ComponentChip(
                label: riskVi('recovery'),
                state: showStates ? evaluation?.recoveryAssessment.state : null,
                assessment: showStates ? evaluation?.recoveryAssessment : null,
                quality: quality,
                onTap: onRecoveryTap,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ComponentChip extends StatelessWidget {
  const _ComponentChip({
    required this.label,
    required this.state,
    required this.quality,
    this.assessment,
    this.onTap,
  });

  final String label;
  final RiskSeverity? state;
  final RiskQuality quality;
  final RiskAssessment? assessment;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final effectiveQuality = riskComponentQuality(quality, assessment);
    final color = riskQualitySeverityColor(context, effectiveQuality, state);
    final stateLabel = riskComponentStateLabel(state, effectiveQuality);
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        color: color.withValues(alpha: 0.08),
      ),
      child: Wrap(
        spacing: 5,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          Text(
            stateLabel,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
          if (onTap != null) const Icon(Icons.chevron_right, size: 16),
        ],
      ),
    );
    return onTap == null
        ? child
        : Semantics(
            button: true,
            label:
                'Mở chi tiết rủi ro ${label.toLowerCase()}; ${stateLabel == '-' ? 'chưa khả dụng' : stateLabel}',
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onTap,
              child: child,
            ),
          );
  }
}

class _BufferHero extends StatelessWidget {
  const _BufferHero({
    required this.evaluation,
    required this.hideValues,
    required this.volatilityMultiple,
    required this.stateQuality,
    this.severity,
    this.onTap,
  });

  final RiskEvaluation evaluation;
  final bool hideValues;
  final double? volatilityMultiple;
  final RiskQuality stateQuality;
  final RiskSeverity? severity;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = riskQualitySeverityColor(context, stateQuality, severity);
    final fraction = ((evaluation.buffer ?? 0).clamp(0.0, 1.0)).toDouble();
    final current = riskMaskedValue(evaluation.markPrice, hideValues);
    final liquidation = riskMaskedValue(
      evaluation.liquidationPrice,
      hideValues,
    );
    final child = Container(
      key: const Key('risk-buffer-hero'),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: color.withValues(alpha: 0.06),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxWidth < 320 ||
                  MediaQuery.textScalerOf(context).scale(1) >= 1.5;
              final value = Text(
                riskMaskedPercent(evaluation.buffer, hideValues),
                style: TextStyle(
                  color: color,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      riskVi('liquidationBuffer'),
                      style: theme.textTheme.labelLarge,
                    ),
                    Align(alignment: Alignment.centerRight, child: value),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      riskVi('liquidationBuffer'),
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  value,
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 8,
              child: Stack(
                children: [
                  Container(color: theme.colorScheme.surfaceContainerHighest),
                  FractionallySizedBox(
                    widthFactor: fraction,
                    child: Container(color: color),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 18,
            runSpacing: 4,
            children: [
              Text(
                '${riskVi('current')} $current USDT',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                '${riskVi('liquidation')} $liquidation USDT',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                '${riskVi('volatilityMultiple')} ${riskMaskedValue(volatilityMultiple, hideValues, suffix: 'x')}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
    return onTap == null
        ? child
        : Semantics(
            button: true,
            label: 'Mở chi tiết biên thanh lý',
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onTap,
              child: child,
            ),
          );
  }
}

class _QualityChip extends StatelessWidget {
  const _QualityChip({required this.label, required this.quality});

  final String label;
  final RiskQuality quality;

  @override
  Widget build(BuildContext context) {
    final color = switch (quality.status) {
      RiskQualityStatus.complete => Colors.green.shade700,
      RiskQualityStatus.partial => Colors.amber.shade800,
      RiskQualityStatus.stale => Colors.orange.shade800,
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    return Semantics(
      label: 'Chất lượng dữ liệu: $label',
      child: Container(
        constraints: const BoxConstraints(maxWidth: 170),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _StatusAnswer extends StatelessWidget {
  const _StatusAnswer({
    required this.label,
    required this.value,
    required this.qualifier,
    required this.color,
    required this.icon,
    this.onTap,
  });

  final String label;
  final String value;
  final String qualifier;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  qualifier,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null) const Icon(Icons.chevron_right),
        ],
      ),
    );
    return onTap == null
        ? child
        : Semantics(
            button: true,
            label: 'Mở chi tiết rủi ro tổng thể',
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onTap,
              child: child,
            ),
          );
  }
}

class _Answer {
  const _Answer({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;
}

class _AnswerGrid extends StatelessWidget {
  const _AnswerGrid({required this.answers});

  final List<_Answer> answers;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 320 ? 2 : 1;
        final gap = columns == 2 ? 10.0 : 8.0;
        final width = columns == 2
            ? (constraints.maxWidth - gap) / 2
            : constraints.maxWidth;
        return Wrap(
          key: const Key('risk-answer-grid'),
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final answer in answers)
              SizedBox(
                width: width,
                child: _AnswerCard(answer: answer),
              ),
          ],
        );
      },
    );
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.answer});

  final _Answer answer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = answer.color ?? theme.colorScheme.primary;
    final child = Container(
      key: ValueKey<String>('risk-answer-${_answerKey(answer.label)}'),
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor),
        color: theme.colorScheme.surface,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(answer.icon, size: 17, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(answer.label, style: theme.textTheme.labelSmall),
                const SizedBox(height: 1),
                Text(
                  answer.value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  answer.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (answer.onTap != null) const Icon(Icons.chevron_right, size: 18),
        ],
      ),
    );
    return answer.onTap == null
        ? child
        : Semantics(
            button: true,
            label: 'Mở ${answer.label}',
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: answer.onTap,
              child: child,
            ),
          );
  }
}

String _answerKey(String label) => const <String, String>{
  'Xu hướng': 'Trend',
  'Đòn bẩy hiệu quả': 'Effective leverage',
  'Nợ': 'Debt',
  'True Exit': 'True Exit',
  '-10% kịch bản': '-10% scenario',
  'Kế hoạch': 'Plan status',
}[label] ?? label;
