import 'package:flutter/material.dart';

import '../../../domain/risk/risk_models.dart';
import 'risk_overview.dart';

class RiskStressView extends StatefulWidget {
  const RiskStressView({
    super.key,
    required this.evaluation,
    this.stateQuality,
    this.hideValues = false,
    this.onAddCustomPrice,
    this.onRemoveCustomPrice,
  });

  final RiskEvaluation? evaluation;
  final RiskQuality? stateQuality;
  final bool hideValues;
  final ValueChanged<double>? onAddCustomPrice;
  final ValueChanged<double>? onRemoveCustomPrice;

  @override
  State<RiskStressView> createState() => _RiskStressViewState();
}

class _RiskStressViewState extends State<RiskStressView> {
  final _priceController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  void _submitPrice() {
    final raw = double.tryParse(_priceController.text.trim());
    if (raw == null || !raw.isFinite || raw <= 0) {
      setState(() => _error = 'Enter a finite positive price.');
      return;
    }
    final callback = widget.onAddCustomPrice;
    if (callback == null) {
      setState(() => _error = 'Custom prices are managed by Risk settings.');
      return;
    }
    callback(raw);
    _priceController.clear();
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scenarios =
        widget.evaluation?.stressScenarios ?? const <RiskStressScenario>[];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Stress scenarios',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Frozen debt and market context. Future margin ratio is intentionally shown as -.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        if (scenarios.isEmpty)
          const _EmptyPanel(
            message:
                'Stress scenarios are unavailable until the position has complete inputs.',
          )
        else
          for (final scenario in scenarios) ...[
            _ScenarioCard(
              scenario: scenario,
              stateQuality: widget.stateQuality,
              showState: true,
              hideValues: widget.hideValues,
              onRemove:
                  scenario.percentageChange == null &&
                      widget.onRemoveCustomPrice != null
                  ? () => widget.onRemoveCustomPrice!(scenario.price)
                  : null,
            ),
            const SizedBox(height: 9),
          ],
        if (widget.onAddCustomPrice != null) ...[
          const SizedBox(height: 5),
          Card(
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
                    'Add custom price',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _priceController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Price (USDT)',
                            border: OutlineInputBorder(),
                          ),
                          obscureText: widget.hideValues,
                          onSubmitted: (_) => _submitPrice(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _submitPrice,
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ScenarioCard extends StatelessWidget {
  const _ScenarioCard({
    required this.scenario,
    required this.showState,
    this.stateQuality,
    this.onRemove,
    this.hideValues = false,
  });

  final RiskStressScenario scenario;
  final bool showState;
  final RiskQuality? stateQuality;
  final VoidCallback? onRemove;
  final bool hideValues;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final price = riskMaskedValue(scenario.price, hideValues, suffix: ' USDT');
    final effectiveQuality = stateQuality ?? const RiskQuality.complete();
    final knownState = showState
        ? scenario.overallState ?? scenario.positionState
        : null;
    final qualityIsCurrent = riskQualityIsCurrent(stateQuality);
    final color = riskQualitySeverityColor(
      context,
      effectiveQuality,
      knownState,
    );
    final change = hideValues
        ? 'Hidden change'
        : scenario.percentageChange == null
        ? 'Custom level'
        : scenario.percentageChange == 0
        ? 'Current'
        : '${(scenario.percentageChange! * 100).toStringAsFixed(0)}%';
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$change · $price',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  knownState?.label ?? '-',
                  style: TextStyle(color: color, fontWeight: FontWeight.w800),
                ),
                if (knownState != null && !qualityIsCurrent)
                  Flexible(
                    child: Text(
                      'Last known ${knownState.label} · ${riskQualityLabel(effectiveQuality)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.labelSmall?.copyWith(color: color),
                    ),
                  ),
                if (onRemove != null)
                  IconButton(
                    tooltip: 'Remove custom price',
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline, size: 19),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                _ScenarioValue(
                  label: 'Position',
                  value: scenario.positionState?.label ?? '-',
                ),
                _ScenarioValue(
                  label: 'Equity',
                  value: riskMaskedValue(
                    scenario.equity,
                    hideValues,
                    suffix: ' USDT',
                  ),
                ),
                _ScenarioValue(
                  label: 'Leverage',
                  value: riskMaskedValue(
                    scenario.effectiveLeverage,
                    hideValues,
                    suffix: 'x',
                  ),
                ),
                _ScenarioValue(
                  label: 'Buffer',
                  value: riskMaskedPercent(scenario.buffer, hideValues),
                ),
                _ScenarioValue(
                  label: 'Margin ratio',
                  value: riskMaskedPercent(scenario.marginRatio, hideValues),
                ),
              ],
            ),
            if (scenario.partial || scenario.marketFrozen) ...[
              const SizedBox(height: 8),
              Text(
                scenario.partial
                    ? 'Partial scenario · ${riskRedactRiskText(scenario.marketContextLabel, hideValues)}'
                    : riskRedactRiskText(
                        scenario.marketContextLabel,
                        hideValues,
                      ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (scenario.reasons.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                riskRedactRiskText(scenario.reasons.first.message, hideValues),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScenarioValue extends StatelessWidget {
  const _ScenarioValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 105,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(message, style: theme.textTheme.bodyMedium),
      ),
    );
  }
}
