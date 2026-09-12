import 'package:flutter/material.dart';

import '../../../domain/risk/risk_events.dart';
import '../../../domain/risk/risk_history.dart';
import '../../../domain/risk/risk_models.dart';
import 'risk_overview.dart';

class RiskHistoryView extends StatelessWidget {
  const RiskHistoryView({
    super.key,
    this.events = const <RiskEvent>[],
    this.samples = const <RiskHistorySample>[],
    this.summaries = const <RiskDailySummary>[],
    this.trend,
    this.velocity,
    this.previousCheck,
    this.hideValues = false,
    this.onClearHistory,
  });

  final List<RiskEvent> events;
  final List<RiskHistorySample> samples;
  final List<RiskDailySummary> summaries;
  final RiskTrendResult? trend;
  final RiskVelocityResult? velocity;
  final RiskSessionComparison? previousCheck;
  final bool hideValues;
  final VoidCallback? onClearHistory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = samples.isEmpty ? null : samples.last;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'History and checks',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (onClearHistory != null)
              TextButton.icon(
                onPressed: onClearHistory,
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('Clear history'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _HistoryCard(
          title: 'Trend and velocity',
          child: Wrap(
            spacing: 16,
            runSpacing: 10,
            children: [
              _HistoryValue(
                label: 'Trend',
                value: hideValues
                    ? '- / Hidden'
                    : trend?.text ?? '- / Collecting history',
              ),
              _HistoryValue(
                label: 'Velocity',
                value: hideValues
                    ? '- / Hidden'
                    : velocity?.text ?? '- / Collecting history',
              ),
              _HistoryValue(
                label: 'Samples',
                value: hideValues ? '******' : '${samples.length}',
              ),
              _HistoryValue(
                label: 'Latest',
                value: latest == null ? '-' : _time(latest.observedAt),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _HistoryCard(
          title: 'Previous check',
          child: previousCheck == null
              ? Text('No previous check', style: theme.textTheme.bodyMedium)
              : Wrap(
                  spacing: 16,
                  runSpacing: 10,
                  children: [
                    _HistoryValue(
                      label: 'Overall',
                      value: _comparisonState(previousCheck!),
                    ),
                    _HistoryValue(
                      label: 'Buffer',
                      value: _comparisonBuffer(previousCheck!),
                    ),
                    _HistoryValue(
                      label: 'Leverage',
                      value: _comparisonLeverage(previousCheck!),
                    ),
                    _HistoryValue(
                      label: 'Debt',
                      value: _comparisonDebt(previousCheck!),
                    ),
                    _HistoryValue(
                      label: 'True Exit',
                      value: _comparisonTrueExit(previousCheck!),
                    ),
                    _HistoryValue(
                      label: 'Structure',
                      value: _comparisonText(
                        previousCheck!.baseline.structureLabel,
                        previousCheck!.current.structureLabel,
                      ),
                    ),
                    _HistoryValue(
                      label: 'Funding',
                      value: _comparisonText(
                        previousCheck!.baseline.fundingLabel,
                        previousCheck!.current.fundingLabel,
                      ),
                    ),
                    _HistoryValue(
                      label: 'OI',
                      value: _comparisonOi(previousCheck!),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        _HistoryCard(
          title: 'Daily summary',
          child: summaries.isEmpty
              ? Text(
                  'No daily summary captured yet.',
                  style: theme.textTheme.bodyMedium,
                )
              : Column(
                  children: [
                    for (final summary in summaries.reversed.take(14))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(hideValues ? '******' : summary.dateKey),
                        subtitle: Text(_summaryText(summary)),
                        trailing: Text(_time(summary.capturedAt)),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        _HistoryCard(
          title: 'Risk events',
          child: events.isEmpty
              ? Text(
                  'No risk events recorded.',
                  style: theme.textTheme.bodyMedium,
                )
              : Column(
                  children: [
                    for (final event in events.reversed.take(40))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(_eventIcon(event.kind)),
                        title: Text(
                          riskRedactRiskText(event.message, hideValues),
                        ),
                        subtitle: Text(
                          riskRedactRiskText(
                            '${event.kind.name} · ${event.factorId ?? '-'} · previous ${riskMaskedValue(event.previousValue, hideValues)} · current ${riskMaskedValue(event.currentValue, hideValues)} · source ${event.source ?? '-'}',
                            hideValues,
                          ),
                        ),
                        trailing: Text(_time(event.observedAt)),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  String _time(DateTime value) {
    if (hideValues) return '******';
    final local = value.toLocal();
    return '${local.month}/${local.day} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _summaryText(RiskDailySummary summary) {
    final actual = riskMaskedValue(summary.actualInterestToday, hideValues);
    final known = riskMaskedValue(summary.knownInterestToday, hideValues);
    final buffer = riskMaskedPercent(summary.buffer, hideValues);
    final leverage = riskMaskedValue(
      summary.effectiveLeverage,
      hideValues,
      suffix: 'x',
    );
    final quality = riskQualityLabel(summary.quality);
    final coverage = summary.interestCoverageComplete
        ? 'Complete'
        : 'Partial / unknown';
    final text = [
      'Overall ${riskStateLabelWithQuality(summary.overallState, summary.quality)} · Position ${riskStateLabelWithQuality(summary.positionState, summary.quality)} · Market ${riskStateLabelWithQuality(summary.marketState, summary.quality)} · Recovery ${riskStateLabelWithQuality(summary.recoveryState, summary.quality)}',
      'Buffer $buffer · Leverage $leverage',
      'Interest actual $actual · known $known · coverage $coverage · quality ${summary.actualInterestQuality == null ? '-' : riskQualityLabel(summary.actualInterestQuality!)}',
      'Major change ${riskRedactRiskText(summary.majorChange ?? '-', hideValues)}',
      'Plan ${hideValues ? '******' : summary.activeRuleCount} active · ${hideValues ? '******' : summary.unknownRuleCount} pending · snapshot quality $quality · ${summary.timeZone}',
    ].join('\n');
    return riskRedactRiskText(text, hideValues);
  }

  String _comparisonState(RiskSessionComparison comparison) {
    return '${_stateValue(comparison.baseline.overallState, comparison.baseline.quality)} → ${_stateValue(comparison.current.overallState, comparison.current.quality)}';
  }

  String _comparisonBuffer(RiskSessionComparison comparison) {
    return _comparisonNumber(
      comparison.baseline.bufferPercentage,
      comparison.current.bufferPercentage,
      decimals: 1,
      suffix: '%',
      delta: comparison.bufferDeltaPoints,
      deltaSuffix: ' pp',
    );
  }

  String _comparisonLeverage(RiskSessionComparison comparison) {
    return _comparisonNumber(
      comparison.baseline.effectiveLeverage,
      comparison.current.effectiveLeverage,
      suffix: 'x',
      delta: comparison.leverageDelta,
      deltaSuffix: 'x',
    );
  }

  String _comparisonDebt(RiskSessionComparison comparison) {
    return _comparisonNumber(
      comparison.baseline.debt,
      comparison.current.debt,
      suffix: ' USDT',
      delta: comparison.debtDelta,
      deltaSuffix: ' USDT',
    );
  }

  String _comparisonTrueExit(RiskSessionComparison comparison) {
    return _comparisonNumber(
      comparison.baseline.trueExitVerified
          ? comparison.baseline.trueExit
          : null,
      comparison.current.trueExitVerified ? comparison.current.trueExit : null,
      suffix: ' USDT',
    );
  }

  String _comparisonOi(RiskSessionComparison comparison) {
    final before = comparison.baseline.openInterestChange;
    final after = comparison.current.openInterestChange;
    if (before == null ||
        !before.isFinite ||
        after == null ||
        !after.isFinite) {
      return before == null && after == null
          ? '-'
          : '${riskMaskedPercent(before, hideValues)} → ${riskMaskedPercent(after, hideValues)}';
    }
    if (hideValues) return '****** → ******';
    final delta = after - before;
    final deltaText = delta == 0
        ? ''
        : ' (${delta > 0 ? '+' : ''}${(delta * 100).toStringAsFixed(1)} pp)';
    return '${riskPercent(before)} → ${riskPercent(after)}$deltaText';
  }

  String _comparisonText(String? before, String? after) {
    final left = riskRedactRiskText(before ?? '-', hideValues);
    final right = riskRedactRiskText(after ?? '-', hideValues);
    return '$left → $right';
  }

  String _stateValue(RiskSeverity? state, RiskQuality quality) {
    return state?.label ?? '-';
  }

  String _comparisonNumber(
    double? before,
    double? after, {
    int decimals = 2,
    String suffix = '',
    double? delta,
    String deltaSuffix = '',
  }) {
    final left = riskMaskedValue(
      before,
      hideValues,
      decimals: decimals,
      suffix: suffix,
    );
    final right = riskMaskedValue(
      after,
      hideValues,
      decimals: decimals,
      suffix: suffix,
    );
    if (hideValues) return '$left → $right';
    final deltaText = delta == null || !delta.isFinite
        ? ''
        : ' (${delta > 0 ? '+' : ''}${delta.toStringAsFixed(decimals)}$deltaSuffix)';
    return '$left → $right$deltaText';
  }

  IconData _eventIcon(RiskEventKind kind) {
    switch (kind) {
      case RiskEventKind.stateChange:
        return Icons.shield_outlined;
      case RiskEventKind.bufferBoundary:
        return Icons.space_bar;
      case RiskEventKind.leverageBoundary:
        return Icons.stacked_line_chart;
      case RiskEventKind.marginBoundary:
        return Icons.account_balance_outlined;
      case RiskEventKind.ruleEntry:
        return Icons.rule_outlined;
      case RiskEventKind.zoneEntry:
        return Icons.crop_free;
      case RiskEventKind.factorEntry:
        return Icons.analytics_outlined;
      case RiskEventKind.interestChange:
        return Icons.schedule;
      case RiskEventKind.configurationChange:
        return Icons.tune;
      case RiskEventKind.reconnect:
        return Icons.sync;
    }
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 9),
            child,
          ],
        ),
      ),
    );
  }
}

class _HistoryValue extends StatelessWidget {
  const _HistoryValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 145,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
