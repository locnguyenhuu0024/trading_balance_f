import 'package:flutter/material.dart';

import '../../../application/risk_monitor_bridge.dart';
import '../../../domain/risk/action_plan.dart';
import '../../../domain/risk/risk_models.dart';
import '../../providers/risk_dashboard_provider.dart';
import 'risk_overview.dart';

class RiskPlanEditor extends StatefulWidget {
  const RiskPlanEditor({
    super.key,
    required this.episodeKey,
    required this.bridge,
    this.accountHash,
    this.plan,
    this.hideValues = false,
    this.evaluation,
    this.planEvaluation,
    this.onPlanChanged,
  });

  final String episodeKey;
  final RiskMonitorBridge bridge;
  final String? accountHash;
  final RiskPlan? plan;
  final bool hideValues;
  final RiskEvaluation? evaluation;
  final RiskPlanEvaluation? planEvaluation;
  final ValueChanged<RiskPlan>? onPlanChanged;

  @override
  State<RiskPlanEditor> createState() => _RiskPlanEditorState();
}

class _RiskPlanEditorState extends State<RiskPlanEditor> {
  late RiskPlan _plan;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _plan = widget.plan ?? RiskPlan(episodeKey: widget.episodeKey);
  }

  @override
  void didUpdateWidget(covariant RiskPlanEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final accountChanged = widget.accountHash != oldWidget.accountHash;
    final episodeChanged = widget.episodeKey != oldWidget.episodeKey;
    final authoritativePlanChanged = widget.plan != oldWidget.plan;
    if (accountChanged || episodeChanged || authoritativePlanChanged) {
      _plan = widget.plan ?? RiskPlan(episodeKey: widget.episodeKey);
      _error = null;
    }
  }

  Future<void> _commit(RiskPlan next) async {
    final errors = next.validate();
    if (errors.isNotEmpty) {
      setState(() => _error = errors.join('\n'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await widget.bridge.send(
      RiskMonitorCommand.updatePlan(id: riskCommandId('plan'), plan: next),
    );
    if (!mounted) return;
    if (!result.accepted) {
      setState(() {
        _saving = false;
        _error = result.message ?? 'Plan could not be saved.';
      });
      return;
    }
    setState(() {
      _saving = false;
      _plan = next;
    });
    widget.onPlanChanged?.call(next);
  }

  Future<void> _addRule([RiskRule? existing]) async {
    final result = await showDialog<RiskRule>(
      context: context,
      builder: (_) => _RuleDialog(
        episodeKey: widget.episodeKey,
        initial: existing,
        hideValues: widget.hideValues,
      ),
    );
    if (result == null) return;
    final rules = [..._plan.rules];
    final index = rules.indexWhere((item) => item.id == result.id);
    if (index == -1) {
      rules.add(result);
    } else {
      rules[index] = result;
    }
    await _commit(
      RiskPlan(episodeKey: _plan.episodeKey, rules: rules, zones: _plan.zones),
    );
  }

  Future<void> _deleteRule(RiskRule rule) async {
    final rules = _plan.rules
        .where((item) => item.id != rule.id)
        .toList(growable: false);
    await _commit(
      RiskPlan(episodeKey: _plan.episodeKey, rules: rules, zones: _plan.zones),
    );
  }

  Future<void> _toggleRule(RiskRule rule) async {
    final updated = rule.copyWith(
      enabled: !rule.enabled,
      updatedAt: DateTime.now().toUtc(),
    );
    final rules = _plan.rules
        .map((item) => item.id == rule.id ? updated : item)
        .toList(growable: false);
    await _commit(
      RiskPlan(episodeKey: _plan.episodeKey, rules: rules, zones: _plan.zones),
    );
  }

  Future<void> _addZone([RiskZone? existing]) async {
    final result = await showDialog<RiskZone>(
      context: context,
      builder: (_) => _ZoneDialog(
        episodeKey: widget.episodeKey,
        initial: existing,
        hideValues: widget.hideValues,
      ),
    );
    if (result == null) return;
    final zones = [..._plan.zones];
    final index = zones.indexWhere((item) => item.id == result.id);
    if (index == -1) {
      zones.add(result);
    } else {
      zones[index] = result;
    }
    await _commit(
      RiskPlan(episodeKey: _plan.episodeKey, rules: _plan.rules, zones: zones),
    );
  }

  Future<void> _deleteZone(RiskZone zone) async {
    final zones = _plan.zones
        .where((item) => item.id != zone.id)
        .toList(growable: false);
    await _commit(
      RiskPlan(episodeKey: _plan.episodeKey, rules: _plan.rules, zones: zones),
    );
  }

  Future<void> _toggleZone(RiskZone zone) async {
    final updated = RiskZone(
      id: zone.id,
      episodeKey: zone.episodeKey,
      title: zone.title,
      lowerPrice: zone.lowerPrice,
      upperPrice: zone.upperPrice,
      enabled: !zone.enabled,
      note: zone.note,
      createdAt: zone.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
    final zones = _plan.zones
        .map((item) => item.id == zone.id ? updated : item)
        .toList(growable: false);
    await _commit(
      RiskPlan(episodeKey: _plan.episodeKey, rules: _plan.rules, zones: zones),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final planEvaluation = widget.planEvaluation;
    return Card(
      key: const Key('risk-plan-editor'),
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Your plan',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (_saving)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.evaluation == null
                  ? 'Rules remain unevaluated until a complete metric is available.'
                  : 'User-authored text is displayed as text and never executed.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            if (_plan.rules.isEmpty && _plan.zones.isEmpty)
              Text(
                'No plan defined',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              )
            else ...[
              if (_plan.rules.isNotEmpty) ...[
                Text('Rules', style: theme.textTheme.labelLarge),
                for (final rule in _plan.rules) _ruleTile(rule, planEvaluation),
              ],
              if (_plan.zones.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Price zones', style: theme.textTheme.labelLarge),
                for (final zone in _plan.zones) _zoneTile(zone, planEvaluation),
              ],
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _saving ? null : () => _addRule(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Create rule'),
                ),
                OutlinedButton.icon(
                  onPressed: _saving ? null : () => _addZone(),
                  icon: const Icon(Icons.crop_free, size: 18),
                  label: const Text('Create zone'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _ruleTile(RiskRule rule, RiskPlanEvaluation? planEvaluation) {
    RiskRuleEvaluation? result;
    for (final item in planEvaluation?.rules ?? const <RiskRuleEvaluation>[]) {
      if (item.rule.id == rule.id) {
        result = item;
        break;
      }
    }
    final stateText =
        result?.state.name ?? (rule.enabled ? 'pending' : 'disabled');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(rule.enabled ? Icons.rule : Icons.rule_outlined),
      title: Text(riskRedactRiskText(rule.displayLabel, widget.hideValues)),
      subtitle: Text(
        riskRedactRiskText(
          '${riskPlanMetricName(rule.metric)} · $stateText${result?.reason == null ? '' : ' · ${result!.reason}'}',
          widget.hideValues,
        ),
      ),
      trailing: PopupMenuButton<String>(
        tooltip: 'Edit rule',
        onSelected: (value) {
          if (value == 'edit') _addRule(rule);
          if (value == 'toggle') _toggleRule(rule);
          if (value == 'delete') _deleteRule(rule);
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
          PopupMenuItem(
            value: 'toggle',
            child: Text(rule.enabled ? 'Disable' : 'Enable'),
          ),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }

  Widget _zoneTile(RiskZone zone, RiskPlanEvaluation? planEvaluation) {
    RiskZoneEvaluation? result;
    for (final item in planEvaluation?.zones ?? const <RiskZoneEvaluation>[]) {
      if (item.zone.id == zone.id) {
        result = item;
        break;
      }
    }
    final stateText =
        result?.state.name ?? (zone.enabled ? 'pending' : 'disabled');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(zone.enabled ? Icons.crop_free : Icons.crop_square),
      title: Text(riskRedactRiskText(zone.title, widget.hideValues)),
      subtitle: Text(
        '${widget.hideValues ? '******' : riskValue(zone.lowerPrice)}–${widget.hideValues ? '******' : riskValue(zone.upperPrice)} USDT · $stateText',
      ),
      trailing: PopupMenuButton<String>(
        tooltip: 'Edit zone',
        onSelected: (value) {
          if (value == 'edit') _addZone(zone);
          if (value == 'toggle') _toggleZone(zone);
          if (value == 'delete') _deleteZone(zone);
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
          PopupMenuItem(
            value: 'toggle',
            child: Text(zone.enabled ? 'Disable' : 'Enable'),
          ),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}

class _RuleDialog extends StatefulWidget {
  const _RuleDialog({
    required this.episodeKey,
    this.initial,
    this.hideValues = false,
  });

  final String episodeKey;
  final RiskRule? initial;
  final bool hideValues;

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  late final TextEditingController _title;
  late final TextEditingController _threshold;
  late final TextEditingController _upper;
  late final TextEditingController _note;
  late RiskPlanMetric _metric;
  late RiskPlanComparison _comparison;
  late bool _enabled;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _title = TextEditingController(text: initial?.displayLabel ?? '');
    _threshold = TextEditingController(
      text: initial?.threshold?.toString() ?? '',
    );
    _upper = TextEditingController(
      text: initial?.upperThreshold?.toString() ?? '',
    );
    _note = TextEditingController(text: initial?.note ?? '');
    _metric = initial?.metric ?? RiskPlanMetric.buffer;
    _comparison = initial?.comparison ?? RiskPlanComparison.lessThan;
    _enabled = initial?.enabled ?? true;
  }

  @override
  void dispose() {
    _title.dispose();
    _threshold.dispose();
    _upper.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final now = DateTime.now().toUtc();
    final rule = RiskRule(
      id: widget.initial?.id ?? 'rule-${now.microsecondsSinceEpoch}',
      episodeKey: widget.episodeKey,
      metric: _metric,
      comparison: _comparison,
      threshold: _metric == RiskPlanMetric.priceVsTrueExit
          ? null
          : double.tryParse(_threshold.text.trim()),
      upperThreshold: _comparison == RiskPlanComparison.betweenInclusive
          ? double.tryParse(_upper.text.trim())
          : null,
      enabled: _enabled,
      title: _title.text.trim(),
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      createdAt: widget.initial?.createdAt ?? now,
      updatedAt: now,
    );
    final errors = rule.validate();
    if (errors.isNotEmpty) {
      setState(() => _error = errors.join('\n'));
      return;
    }
    Navigator.of(context).pop(rule);
  }

  @override
  Widget build(BuildContext context) {
    final isDynamic = _metric == RiskPlanMetric.priceVsTrueExit;
    return AlertDialog(
      title: Text(widget.initial == null ? 'Create rule' : 'Edit rule'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<RiskPlanMetric>(
              initialValue: _metric,
              decoration: const InputDecoration(labelText: 'Metric'),
              items: [
                for (final metric in RiskPlanMetric.values.where(
                  (item) => item != RiskPlanMetric.trueExitPrice,
                ))
                  DropdownMenuItem(
                    value: metric,
                    child: Text(riskPlanMetricName(metric)),
                  ),
              ],
              onChanged: (value) => setState(() => _metric = value ?? _metric),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<RiskPlanComparison>(
              initialValue: _comparison,
              decoration: const InputDecoration(labelText: 'Comparison'),
              items: [
                for (final comparison in RiskPlanComparison.values)
                  DropdownMenuItem(
                    value: comparison,
                    child: Text(riskPlanComparisonName(comparison)),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _comparison = value ?? _comparison),
            ),
            if (!isDynamic) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _threshold,
                obscureText: widget.hideValues,
                decoration: const InputDecoration(labelText: 'Threshold'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              if (_comparison == RiskPlanComparison.betweenInclusive) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _upper,
                  obscureText: widget.hideValues,
                  decoration: const InputDecoration(
                    labelText: 'Upper threshold',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ],
            ],
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enabled'),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _save, child: const Text('Save rule')),
      ],
    );
  }
}

class _ZoneDialog extends StatefulWidget {
  const _ZoneDialog({
    required this.episodeKey,
    this.initial,
    this.hideValues = false,
  });

  final String episodeKey;
  final RiskZone? initial;
  final bool hideValues;

  @override
  State<_ZoneDialog> createState() => _ZoneDialogState();
}

class _ZoneDialogState extends State<_ZoneDialog> {
  late final TextEditingController _title;
  late final TextEditingController _lower;
  late final TextEditingController _upper;
  late final TextEditingController _note;
  late bool _enabled;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _title = TextEditingController(text: initial?.title ?? '');
    _lower = TextEditingController(text: initial?.lowerPrice.toString() ?? '');
    _upper = TextEditingController(text: initial?.upperPrice.toString() ?? '');
    _note = TextEditingController(text: initial?.note ?? '');
    _enabled = initial?.enabled ?? true;
  }

  @override
  void dispose() {
    _title.dispose();
    _lower.dispose();
    _upper.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final now = DateTime.now().toUtc();
    final zone = RiskZone(
      id: widget.initial?.id ?? 'zone-${now.microsecondsSinceEpoch}',
      episodeKey: widget.episodeKey,
      title: _title.text.trim(),
      lowerPrice: double.tryParse(_lower.text.trim()) ?? double.nan,
      upperPrice: double.tryParse(_upper.text.trim()) ?? double.nan,
      enabled: _enabled,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      createdAt: widget.initial?.createdAt ?? now,
      updatedAt: now,
    );
    final errors = zone.validate();
    if (errors.isNotEmpty) {
      setState(() => _error = errors.join('\n'));
      return;
    }
    Navigator.of(context).pop(zone);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Create zone' : 'Edit zone'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _lower,
              obscureText: widget.hideValues,
              decoration: const InputDecoration(labelText: 'Lower price'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _upper,
              obscureText: widget.hideValues,
              decoration: const InputDecoration(labelText: 'Upper price'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enabled'),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _save, child: const Text('Save zone')),
      ],
    );
  }
}
