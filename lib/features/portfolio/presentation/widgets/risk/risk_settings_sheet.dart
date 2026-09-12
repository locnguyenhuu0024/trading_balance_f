import 'package:flutter/material.dart';

import '../../../application/risk_monitor_bridge.dart';
import '../../../domain/risk/action_plan.dart';
import '../../providers/risk_dashboard_provider.dart';

class RiskSettingsSheet extends StatefulWidget {
  const RiskSettingsSheet({
    super.key,
    required this.settings,
    required this.bridge,
    this.hideValues = false,
    this.onSaved,
  });

  final RiskSettings settings;
  final RiskMonitorBridge bridge;
  final bool hideValues;
  final ValueChanged<RiskSettings>? onSaved;

  static Future<void> show(
    BuildContext context, {
    required RiskSettings settings,
    required RiskMonitorBridge bridge,
    bool hideValues = false,
    ValueChanged<RiskSettings>? onSaved,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => RiskSettingsSheet(
        settings: settings,
        bridge: bridge,
        hideValues: hideValues,
        onSaved: onSaved,
      ),
    );
  }

  @override
  State<RiskSettingsSheet> createState() => _RiskSettingsSheetState();
}

class _RiskSettingsSheetState extends State<RiskSettingsSheet> {
  late final Map<String, TextEditingController> _controllers;
  late final TextEditingController _timeZone;
  late List<double> _customPrices;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final policy = widget.settings.policy;
    _timeZone = TextEditingController(text: widget.settings.timeZone);
    _controllers = <String, TextEditingController>{
      'bufferCritical': TextEditingController(
        text: policy.bufferCritical.toString(),
      ),
      'bufferHigh': TextEditingController(text: policy.bufferHigh.toString()),
      'bufferWatch': TextEditingController(text: policy.bufferWatch.toString()),
      'leverageWatch': TextEditingController(
        text: policy.leverageWatch.toString(),
      ),
      'leverageHigh': TextEditingController(
        text: policy.leverageHigh.toString(),
      ),
      'leverageCritical': TextEditingController(
        text: policy.leverageCritical.toString(),
      ),
      'marginCritical': TextEditingController(
        text: policy.marginRatioCritical.toString(),
      ),
      'marginHigh': TextEditingController(
        text: policy.marginRatioHigh.toString(),
      ),
      'marginWatch': TextEditingController(
        text: policy.marginRatioWatch.toString(),
      ),
      'summaryHour': TextEditingController(
        text: widget.settings.summaryHour.toString(),
      ),
      'summaryMinute': TextEditingController(
        text: widget.settings.summaryMinute.toString(),
      ),
      'sampleRetentionDays': TextEditingController(
        text: widget.settings.sampleRetentionDays.toString(),
      ),
      'oiRetentionHours': TextEditingController(
        text: widget.settings.oiRetentionHours.toString(),
      ),
      'eventRetentionDays': TextEditingController(
        text: widget.settings.eventRetentionDays.toString(),
      ),
      'summaryRetentionDays': TextEditingController(
        text: widget.settings.summaryRetentionDays.toString(),
      ),
      'maxSamples': TextEditingController(
        text: widget.settings.maxSamples.toString(),
      ),
      'maxOiSamples': TextEditingController(
        text: widget.settings.maxOiSamples.toString(),
      ),
      'maxEvents': TextEditingController(
        text: widget.settings.maxEvents.toString(),
      ),
      'maxEpisodes': TextEditingController(
        text: widget.settings.maxEpisodes.toString(),
      ),
    };
    _customPrices = [...widget.settings.customStressPrices];
  }

  @override
  void dispose() {
    _timeZone.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  double? _number(String key) =>
      double.tryParse(_controllers[key]!.text.trim());

  int? _integer(String key) => int.tryParse(_controllers[key]!.text.trim());

  Future<void> _save() async {
    final parsed = <String, double?>{
      for (final key in _controllers.keys) key: _number(key),
    };
    if (parsed.values.any((value) => value == null || !value.isFinite)) {
      setState(() => _error = 'Every threshold must be a finite number.');
      return;
    }
    final summaryHour = _integer('summaryHour');
    final summaryMinute = _integer('summaryMinute');
    final sampleRetentionDays = _integer('sampleRetentionDays');
    final oiRetentionHours = _integer('oiRetentionHours');
    final eventRetentionDays = _integer('eventRetentionDays');
    final summaryRetentionDays = _integer('summaryRetentionDays');
    final maxSamples = _integer('maxSamples');
    final maxOiSamples = _integer('maxOiSamples');
    final maxEvents = _integer('maxEvents');
    final maxEpisodes = _integer('maxEpisodes');
    final timingValues = <int?>[
      summaryHour,
      summaryMinute,
      sampleRetentionDays,
      oiRetentionHours,
      eventRetentionDays,
      summaryRetentionDays,
      maxSamples,
      maxOiSamples,
      maxEvents,
      maxEpisodes,
    ];
    if (_timeZone.text.trim().isEmpty ||
        timingValues.any((value) => value == null)) {
      setState(() => _error = 'Timing and retention values must be integers.');
      return;
    }
    final policy = widget.settings.policy.copyWith(
      bufferCritical: parsed['bufferCritical'],
      bufferHigh: parsed['bufferHigh'],
      bufferWatch: parsed['bufferWatch'],
      leverageWatch: parsed['leverageWatch'],
      leverageHigh: parsed['leverageHigh'],
      leverageCritical: parsed['leverageCritical'],
      marginRatioCritical: parsed['marginCritical'],
      marginRatioHigh: parsed['marginHigh'],
      marginRatioWatch: parsed['marginWatch'],
    );
    final next = widget.settings.copyWith(
      policy: policy,
      customStressPrices: _customPrices,
      timeZone: _timeZone.text.trim(),
      summaryHour: summaryHour,
      summaryMinute: summaryMinute,
      sampleRetentionDays: sampleRetentionDays,
      oiRetentionHours: oiRetentionHours,
      eventRetentionDays: eventRetentionDays,
      summaryRetentionDays: summaryRetentionDays,
      maxSamples: maxSamples,
      maxOiSamples: maxOiSamples,
      maxEvents: maxEvents,
      maxEpisodes: maxEpisodes,
    );
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
      RiskMonitorCommand.updateSettings(
        id: riskCommandId('settings'),
        settings: next,
      ),
    );
    if (!mounted) return;
    if (!result.accepted) {
      setState(() {
        _saving = false;
        _error = result.message ?? 'Settings could not be saved.';
      });
      return;
    }
    widget.onSaved?.call(next);
    Navigator.of(context).pop();
  }

  void _reset() {
    const defaults = RiskSettings();
    final policy = defaults.policy;
    for (final entry in <String, double>{
      'bufferCritical': policy.bufferCritical,
      'bufferHigh': policy.bufferHigh,
      'bufferWatch': policy.bufferWatch,
      'leverageWatch': policy.leverageWatch,
      'leverageHigh': policy.leverageHigh,
      'leverageCritical': policy.leverageCritical,
      'marginCritical': policy.marginRatioCritical,
      'marginHigh': policy.marginRatioHigh,
      'marginWatch': policy.marginRatioWatch,
    }.entries) {
      _controllers[entry.key]!.text = entry.value.toString();
    }
    _timeZone.text = defaults.timeZone;
    for (final entry in <String, int>{
      'summaryHour': defaults.summaryHour,
      'summaryMinute': defaults.summaryMinute,
      'sampleRetentionDays': defaults.sampleRetentionDays,
      'oiRetentionHours': defaults.oiRetentionHours,
      'eventRetentionDays': defaults.eventRetentionDays,
      'summaryRetentionDays': defaults.summaryRetentionDays,
      'maxSamples': defaults.maxSamples,
      'maxOiSamples': defaults.maxOiSamples,
      'maxEvents': defaults.maxEvents,
      'maxEpisodes': defaults.maxEpisodes,
    }.entries) {
      _controllers[entry.key]!.text = entry.value.toString();
    }
    setState(() {
      _customPrices = [];
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.88,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Risk settings',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _saving ? null : _reset,
                    child: const Text('Reset defaults'),
                  ),
                ],
              ),
              Text(
                'Boundaries use fractions internally; changing policy creates a configuration event.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView(
                  children: [
                    const _SectionTitle(title: 'Buffer boundaries'),
                    _field('bufferCritical', 'Critical below'),
                    _field('bufferHigh', 'High below'),
                    _field('bufferWatch', 'Watch through'),
                    const _SectionTitle(title: 'Effective leverage'),
                    _field('leverageWatch', 'Watch at'),
                    _field('leverageHigh', 'High at'),
                    _field('leverageCritical', 'Critical at'),
                    const _SectionTitle(title: 'Margin ratio (fraction)'),
                    _field('marginCritical', 'Critical at or below'),
                    _field('marginHigh', 'High at or below'),
                    _field('marginWatch', 'Watch at or below'),
                    const _SectionTitle(title: 'History timing and retention'),
                    TextField(
                      controller: _timeZone,
                      decoration: const InputDecoration(
                        labelText: 'Time zone label',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _integerField('summaryHour', 'Daily summary hour'),
                    _integerField('summaryMinute', 'Daily summary minute'),
                    _integerField(
                      'sampleRetentionDays',
                      'Sample retention days',
                    ),
                    _integerField('oiRetentionHours', 'OI retention hours'),
                    _integerField('eventRetentionDays', 'Event retention days'),
                    _integerField(
                      'summaryRetentionDays',
                      'Summary retention days',
                    ),
                    _integerField('maxSamples', 'Maximum history samples'),
                    _integerField('maxOiSamples', 'Maximum OI samples'),
                    _integerField('maxEvents', 'Maximum events'),
                    _integerField('maxEpisodes', 'Maximum episodes'),
                    const _SectionTitle(title: 'Custom scenario prices'),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final price in _customPrices)
                          InputChip(
                            label: Text(
                              widget.hideValues
                                  ? '******'
                                  : price.toStringAsFixed(4),
                            ),
                            onDeleted: () =>
                                setState(() => _customPrices.remove(price)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Add prices from the Scenarios editor; proportional stress rows remain pinned.',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Save risk settings'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String key, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: _controllers[key],
        obscureText: widget.hideValues,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _integerField(String key, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: _controllers[key],
        obscureText: widget.hideValues,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 7),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}
