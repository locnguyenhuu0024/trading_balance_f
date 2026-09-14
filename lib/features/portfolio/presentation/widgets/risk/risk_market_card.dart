import 'package:flutter/material.dart';

import '../../../domain/risk/risk_models.dart';
import '../../risk_vietnamese_formatter.dart';
import 'risk_overview.dart';

class RiskMarketCard extends StatelessWidget {
  const RiskMarketCard({
    super.key,
    required this.evaluation,
    this.market,
    this.stateQuality,
    this.hideValues = false,
    this.onOpen,
  });

  final RiskEvaluation? evaluation;
  final RiskMarketInput? market;
  final RiskQuality? stateQuality;
  final bool hideValues;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final assessment = evaluation?.marketAssessment;
    final missing = <String>{
      ...?market?.missingReasons,
      ...?assessment?.missingReasons,
      ...?evaluation?.missingReasons,
    }.toList(growable: false);
    final reasons = <RiskReason>[...?market?.reasons, ...?assessment?.reasons];
    final quality =
        stateQuality ??
        evaluation?.quality ??
        const RiskQuality.unavailable(reason: 'Thị trường chưa khả dụng');
    final displayedState = assessment?.state;
    final effectiveQuality = riskComponentQuality(quality, assessment);
    final stateLabel = riskComponentStateLabel(
      displayedState,
      effectiveQuality,
    );
    final stateColor = riskQualitySeverityColor(
      context,
      effectiveQuality,
      displayedState,
    );
    final content = Card(
      key: const Key('risk-market-card'),
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    riskVi('marketRisk'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          stateLabel,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            color: stateColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              riskRedactRiskText(
                riskViGenerated(market?.marketContextLabel).isEmpty
                    ? 'Dữ liệu thị trường độc lập với phép tính vị thế'
                    : riskViGenerated(market?.marketContextLabel),
                hideValues,
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MarketValue(
                  label: riskVi('structure'),
                  value: riskRedactRiskText(
                    riskViGenerated(market?.assetStructureLabel).isEmpty
                        ? '-'
                        : riskViGenerated(market?.assetStructureLabel),
                    hideValues,
                  ),
                ),
                _MarketValue(
                  label: riskVi('volatility'),
                  value: riskRedactRiskText(
                    market?.volatilityLabel == null
                        ? (market?.dailyVolatility == null
                              ? '-'
                              : riskPercent(market!.dailyVolatility))
                        : riskViGenerated(market!.volatilityLabel),
                    hideValues,
                  ),
                ),
                _MarketValue(
                  label: riskVi('funding'),
                  value: riskRedactRiskText(
                    market?.fundingLabel == null
                        ? '-'
                        : riskViGenerated(market!.fundingLabel),
                    hideValues,
                  ),
                ),
                _MarketValue(
                  label: riskVi('openInterest'),
                  value: riskRedactRiskText(
                    market?.openInterestLabel == null
                        ? '-'
                        : riskViGenerated(market!.openInterestLabel),
                    hideValues,
                  ),
                ),
                _MarketValue(
                  label: riskVi('volume'),
                  value: riskRedactRiskText(
                    market?.volumePressureLabel == null
                        ? '-'
                        : riskViGenerated(market!.volumePressureLabel),
                    hideValues,
                  ),
                ),
                _MarketValue(
                  label: riskVi('dailyVolatility'),
                  value: riskMaskedPercent(market?.dailyVolatility, hideValues),
                ),
                _MarketValue(
                  label: riskVi('supportResistance'),
                  value: market?.support == null && market?.resistance == null
                      ? '-'
                      : '${riskMaskedValue(market?.support, hideValues)} / ${riskMaskedValue(market?.resistance, hideValues)}',
                ),
                _MarketValue(
                  label: riskVi('fundingInterval'),
                  value:
                      market?.normalizedFunding8h == null &&
                          market?.fundingIntervalHours == null
                      ? '-'
                      : '${riskMaskedPercent(market?.normalizedFunding8h, hideValues)} · ${riskMaskedValue(market?.fundingIntervalHours, hideValues, decimals: 1)}h',
                ),
                _MarketValue(
                  label: riskVi('oiPriceChange'),
                  value:
                      market?.openInterestChange == null &&
                          market?.marketPriceChange == null
                      ? '-'
                      : '${riskMaskedPercent(market?.openInterestChange, hideValues)} / ${riskMaskedPercent(market?.marketPriceChange, hideValues)}',
                ),
              ],
            ),
            if (missing.isNotEmpty) ...[
              const SizedBox(height: 12),
              _QualityMessage(
                icon: Icons.info_outline,
                text:
                    '${riskVi('partialMarketContext')}: ${riskRedactRiskText(missing.map(riskViGenerated).join('; '), hideValues)}',
              ),
            ],
            if (reasons.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(riskVi('whyThisState'), style: theme.textTheme.labelLarge),
              const SizedBox(height: 5),
              for (final reason in reasons.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• ${riskRedactRiskText(riskViReason(reason.message), hideValues)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
            if (market != null) ...[
              const SizedBox(height: 12),
              _MarketSourceEvidence(
                market: market!,
                reasons: reasons,
                hideValues: hideValues,
              ),
            ],
            if (onOpen != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new, size: 17),
                  label: Text(riskVi('marketInputsReasons')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
    return content;
  }
}

class _MarketValue extends StatelessWidget {
  const _MarketValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 118, maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _MarketSourceEvidence extends StatelessWidget {
  const _MarketSourceEvidence({
    required this.market,
    required this.reasons,
    required this.hideValues,
  });

  final RiskMarketInput market;
  final List<RiskReason> reasons;
  final bool hideValues;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final evidence = reasons.take(3).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(riskVi('marketEvidence'), style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(
          riskRedactRiskText(
            '${riskVi('source')} ${market.source ?? '-'} · ${riskVi('observed')} ${_marketTime(market.observedAt)} · ${riskVi('sourceTime')} ${_marketTime(market.sourceAt)}',
            hideValues,
          ),
          style: theme.textTheme.bodySmall,
        ),
        for (final reason in evidence) ...[
          const SizedBox(height: 6),
          Text(
            riskRedactRiskText(
              '${riskViReason(reason.message)} · ${riskVi('observed').toLowerCase()} ${reason.observedValue == null ? '-' : riskValue(reason.observedValue)} ${reason.unit ?? ''} · ngưỡng ${reason.threshold ?? '-'} · khoảng thời gian ${reason.window ?? '-'} · ${riskVi('source').toLowerCase()} ${reason.source ?? '-'} · thời gian ${_marketTime(reason.observedAt)}',
              hideValues,
            ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

String _marketTime(DateTime? value) {
  if (value == null) return '-';
  final local = value.toLocal();
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.month}/${local.day} ${local.hour}:$minute';
}

class _QualityMessage extends StatelessWidget {
  const _QualityMessage({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        ),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
