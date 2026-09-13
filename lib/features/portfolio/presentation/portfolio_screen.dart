import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/navigation_content_frame.dart';
import '../../../core/widgets/crypto_icon.dart';
import '../../settings/presentation/settings_screen.dart';
import '../application/risk_monitor_bridge.dart';
import '../domain/risk/action_plan.dart';
import '../domain/risk/risk_engine.dart';
import '../domain/risk/risk_history.dart';
import '../domain/risk/risk_models.dart';
import 'portfolio_details_screen.dart';
import 'providers/risk_dashboard_provider.dart';
import 'widgets/risk/risk_history_view.dart';
import 'widgets/risk/risk_market_card.dart';
import 'widgets/risk/risk_overview.dart';
import 'widgets/risk/risk_plan_editor.dart';
import 'widgets/risk/risk_price_map.dart';
import 'widgets/risk/risk_recovery_view.dart';
import 'widgets/risk/risk_settings_sheet.dart';
import 'widgets/risk/risk_stress_view.dart';

/// Preserved provider used by Orders, Market and the existing privacy
/// preference. Numeric values on the risk Home are already omitted; this
/// provider still controls the explicit Portfolio details surface.
final hideBalanceProvider = StateProvider<bool>((ref) => false);

final isDarkModeProvider = Provider<bool>((ref) {
  final mode = ref.watch(themeModeProvider);
  if (mode == ThemeMode.dark) return true;
  if (mode == ThemeMode.light) return false;
  return SchedulerBinding.instance.platformDispatcher.platformBrightness ==
      Brightness.dark;
});

class PortfolioScreen extends ConsumerStatefulWidget {
  const PortfolioScreen({
    super.key,
    this.bridge,
    this.plan,
    this.settings,
    this.market,
    this.samples = const <RiskHistorySample>[],
    this.summaries = const <RiskDailySummary>[],
  });

  final RiskMonitorBridge? bridge;
  final RiskPlan? plan;
  final RiskSettings? settings;
  final RiskMarketInput? market;
  final List<RiskHistorySample> samples;
  final List<RiskDailySummary> summaries;

  @override
  ConsumerState<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends ConsumerState<PortfolioScreen> {
  bool _startRequested = false;

  RiskMonitorBridge get _bridge =>
      widget.bridge ?? ref.read(riskMonitorBridgeProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _startRequested) return;
      _startRequested = true;
      final state = _bridge.currentState;
      if (!state.isRunning) {
        _bridge.start(commandId: riskCommandId('home-start'));
      }
    });
  }

  Future<void> _refresh() async {
    final state = _bridge.currentState;
    final result = state.isRunning
        ? await _bridge.send(
            RiskMonitorCommand.refresh(id: riskCommandId('home-refresh')),
          )
        : await _bridge.start(commandId: riskCommandId('home-start'));
    if (!mounted || result.accepted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      TextSnackBar(message: result.message ?? 'Refresh unavailable'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hidden = ref.watch(hideBalanceProvider);
    if (widget.bridge != null) {
      return StreamBuilder<RiskMonitorViewState>(
        stream: widget.bridge!.states,
        initialData: widget.bridge!.currentState,
        builder: (context, snapshot) => _buildScreen(
          context,
          snapshot.data ?? widget.bridge!.currentState,
          hidden,
        ),
      );
    }
    final stateAsync = ref.watch(riskMonitorViewStateProvider);
    final state = stateAsync.valueOrNull ?? _bridge.currentState;
    return _buildScreen(context, state, hidden);
  }

  Widget _buildScreen(
    BuildContext context,
    RiskMonitorViewState state,
    bool hidden,
  ) {
    final theme = Theme.of(context);
    final isDark = ref.watch(isDarkModeProvider);
    final background = isDark
        ? const Color(0xFF121212)
        : theme.colorScheme.surface;
    final foreground = isDark ? Colors.white : theme.colorScheme.onSurface;
    final useWidgetFallbacks = widget.bridge == null;
    final statePlan =
        state.plan ??
        (useWidgetFallbacks &&
                widget.plan != null &&
                (state.episodeKey == null ||
                    widget.plan!.episodeKey == state.episodeKey)
            ? widget.plan
            : null);
    final settings =
        state.settings ??
        (useWidgetFallbacks ? widget.settings : null) ??
        const RiskSettings();
    final market = state.market ?? (useWidgetFallbacks ? widget.market : null);
    final samples =
        state.samples ??
        (useWidgetFallbacks ? widget.samples : const <RiskHistorySample>[]);
    final summaries =
        state.summaries ??
        (useWidgetFallbacks ? widget.summaries : const <RiskDailySummary>[]);
    final planEvaluation = state.planEvaluation;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: foreground,
        elevation: 0,
        title: const Text('Risk Home'),
        actions: [
          IconButton(
            key: const Key('risk-privacy'),
            tooltip: hidden ? 'Show risk amounts' : 'Hide risk amounts',
            icon: Icon(hidden ? Icons.visibility_off : Icons.visibility),
            onPressed: () =>
                ref.read(hideBalanceProvider.notifier).state = !hidden,
          ),
          IconButton(
            key: const Key('risk-settings'),
            tooltip: 'Risk settings',
            icon: const Icon(Icons.tune),
            onPressed: () => RiskSettingsSheet.show(
              context,
              settings: settings,
              bridge: _bridge,
              hideValues: hidden,
              onSaved: (_) => setState(() {}),
            ),
          ),
          IconButton(
            key: const Key('portfolio-details'),
            tooltip: 'Portfolio details',
            icon: const Icon(Icons.account_balance_wallet_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PortfolioDetailsScreen(),
              ),
            ),
          ),
        ],
      ),
      body: NavigationContentFrame(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: _DashboardBody(
            state: state,
            plan: statePlan,
            planEvaluation: planEvaluation,
            settings: settings,
            market: market,
            samples: samples,
            summaries: summaries,
            previousCheck: state.previousCheck,
            bridge: _bridge,
            hideValues: hidden,
            onPlanChanged: (_) => setState(() {}),
            onSettingsChanged: (_) => setState(() {}),
            onRefresh: _refresh,
          ),
        ),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.state,
    required this.plan,
    required this.planEvaluation,
    required this.settings,
    required this.market,
    required this.samples,
    required this.summaries,
    required this.previousCheck,
    required this.bridge,
    required this.hideValues,
    required this.onPlanChanged,
    required this.onSettingsChanged,
    required this.onRefresh,
  });

  final RiskMonitorViewState state;
  final RiskPlan? plan;
  final RiskPlanEvaluation? planEvaluation;
  final RiskSettings settings;
  final RiskMarketInput? market;
  final List<RiskHistorySample> samples;
  final List<RiskDailySummary> summaries;
  final RiskSessionComparison? previousCheck;
  final RiskMonitorBridge bridge;
  final bool hideValues;
  final ValueChanged<RiskPlan> onPlanChanged;
  final ValueChanged<RiskSettings> onSettingsChanged;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final evaluation = state.evaluation;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        final maxWidth = constraints.maxWidth > 1280
            ? 1280.0
            : constraints.maxWidth;
        return ListView(
          key: const Key('risk-home-scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _MonitorStatus(
                      state: state,
                      hideValues: hideValues,
                      onRefresh: onRefresh,
                    ),
                    const SizedBox(height: 10),
                    if (evaluation == null)
                      _UnavailableDashboard(
                        state: state,
                        hideValues: hideValues,
                        onRefresh: onRefresh,
                      )
                    else ...[
                      _PositionContext(
                        evaluation: evaluation,
                        hideValues: hideValues,
                      ),
                      const SizedBox(height: 10),
                      _completeDashboard(context, evaluation, isWide),
                    ],
                    if (state.unsaved) ...[
                      const SizedBox(height: 10),
                      const _Notice(
                        message:
                            'Local risk changes are unsaved. OS delivery remains paused until storage confirms them.',
                      ),
                    ],
                    const SizedBox(height: 12),
                    const _PrivacyNote(),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _completeDashboard(
    BuildContext context,
    RiskEvaluation evaluation,
    bool isWide,
  ) {
    final overview = RiskOverview(
      state: state,
      hideValues: hideValues,
      volatilityMultiple: _volatilityMultiple(evaluation, market),
      plan: plan,
      planEvaluation: planEvaluation,
      trend: state.trend,
      velocity: state.velocity,
      onOverallTap: () => _showReasons(context, evaluation),
      onPositionTap: () => _showExposure(context, evaluation),
      onMarketTap: () => _showMarket(context, evaluation),
      onRecoveryTap: () => _showRecovery(context, evaluation),
      onBufferTap: () => _showExposure(context, evaluation),
      onLeverageTap: () => _showExposure(context, evaluation),
      onDebtTap: () => _showRecovery(context, evaluation),
      onTrueExitTap: () => _showRecovery(context, evaluation),
      onStressTap: () => _showStress(context, evaluation),
      onPlanTap: () => _showPlan(context, evaluation),
    );
    final sinceLastCheck = _SinceLastCheck(
      state: state,
      previousCheck: previousCheck,
      hideValues: hideValues,
    );
    final reasons = evaluation.reasons.isEmpty
        ? null
        : _TopReasons(
            reasons: evaluation.reasons,
            hideValues: hideValues,
            onOpen: () => _showReasons(context, evaluation),
          );
    final drilldown = _DrilldownRow(
      onExposure: () => _showExposure(context, evaluation),
      onStress: () => _showStress(context, evaluation),
      onRecovery: () => _showRecovery(context, evaluation),
      onMap: () => _showPriceMap(context, evaluation),
      onPlan: () => _showPlan(context, evaluation),
      onHistory: () => _showHistory(context),
    );
    final episodeKey = evaluation.position.episodeKey.isEmpty
        ? (state.episodeKey ?? '')
        : evaluation.position.episodeKey;
    final marketCard = RiskMarketCard(
      evaluation: evaluation,
      market: market,
      stateQuality: state.quality,
      hideValues: hideValues,
      onOpen: () => _showMarket(context, evaluation),
    );
    final planEditor = RiskPlanEditor(
      episodeKey: episodeKey,
      bridge: bridge,
      accountHash: state.accountHash,
      plan: plan,
      hideValues: hideValues,
      evaluation: evaluation,
      planEvaluation: planEvaluation,
      onPlanChanged: onPlanChanged,
    );
    final left = Column(
      key: const Key('risk-desktop-left'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        overview,
        const SizedBox(height: 10),
        sinceLastCheck,
        if (reasons != null) ...[const SizedBox(height: 10), reasons],
        const SizedBox(height: 10),
        drilldown,
      ],
    );
    final right = Column(
      key: const Key('risk-desktop-right'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [marketCard, const SizedBox(height: 10), planEditor],
    );
    if (isWide) {
      return Row(
        key: const Key('risk-desktop-columns'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: left),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: right),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        overview,
        const SizedBox(height: 10),
        sinceLastCheck,
        if (reasons != null) ...[const SizedBox(height: 10), reasons],
        const SizedBox(height: 10),
        marketCard,
        const SizedBox(height: 10),
        drilldown,
        const SizedBox(height: 10),
        planEditor,
      ],
    );
  }

  void _showMarket(BuildContext context, RiskEvaluation evaluation) {
    _showSheet(
      context,
      'Market inputs and reasons',
      _reactive(
        (current) => RiskMarketCard(
          evaluation: _evaluationFor(current, evaluation),
          market: current.market ?? (_sameSession(current) ? market : null),
          stateQuality: current.quality,
          hideValues: hideValues,
        ),
      ),
    );
  }

  void _showReasons(BuildContext context, RiskEvaluation evaluation) {
    _showSheet(
      context,
      'Why this state',
      _reactive((current) {
        final latest = _evaluationFor(current, evaluation);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              latest?.overallState?.label ?? '-',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (latest?.overallState != null &&
                !riskQualityIsCurrent(current.quality))
              Text(
                riskKnownSeverityQualifier(
                  latest!.overallState,
                  current.quality,
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 10),
            if (latest == null || latest.reasons.isEmpty)
              const Text('No complete reason is available.'),
            for (final reason in latest?.reasons ?? const <RiskReason>[])
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.info_outline),
                title: Text(riskRedactRiskText(reason.message, hideValues)),
                subtitle: Text(
                  riskRedactRiskText(
                    '${reason.factorId} · observed ${reason.observedValue == null ? '-' : riskValue(reason.observedValue)} ${reason.unit ?? ''} · ${reason.source ?? '-'}',
                    hideValues,
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }

  void _showExposure(BuildContext context, RiskEvaluation evaluation) {
    _showSheet(
      context,
      'Exposure and sensitivity',
      _reactive((current) {
        final latest = _evaluationFor(current, evaluation);
        if (latest == null) {
          return const Center(child: Text('Exposure is unavailable.'));
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _MetricSheetRow(
              label: 'Quantity',
              value: riskMaskedValue(latest.metrics.quantity.value, hideValues),
              hideValues: hideValues,
            ),
            _MetricSheetRow(
              label: 'Trade notional',
              value: riskMaskedValue(
                latest.metrics.tradeNotional.value,
                hideValues,
                suffix: ' USDT',
              ),
              hideValues: hideValues,
            ),
            _MetricSheetRow(
              label: 'Gross asset exposure',
              value: riskMaskedValue(
                latest.metrics.grossAssetExposure.value,
                hideValues,
                suffix: ' USDT',
              ),
              hideValues: hideValues,
            ),
            _MetricSheetRow(
              label: 'Equity',
              value: riskMaskedValue(
                latest.metrics.equity.value,
                hideValues,
                suffix: ' USDT',
              ),
              hideValues: hideValues,
            ),
            _MetricSheetRow(
              label: 'Trade sensitivity / 0.01',
              value: riskMaskedValue(
                latest.metrics.tradeSensitivityPerPoint.value,
                hideValues,
                suffix: ' USDT',
              ),
              hideValues: hideValues,
            ),
            _MetricSheetRow(
              label: 'Equity sensitivity / 0.01',
              value: riskMaskedValue(
                latest.metrics.equitySensitivityPerPoint.value,
                hideValues,
                suffix: ' USDT',
              ),
              hideValues: hideValues,
            ),
            _MetricSheetRow(
              label: 'Margin ratio',
              value: riskMaskedPercent(
                latest.metrics.marginRatio.value,
                hideValues,
              ),
              hideValues: hideValues,
            ),
          ],
        );
      }),
    );
  }

  void _showRecovery(BuildContext context, RiskEvaluation evaluation) {
    _showSheet(
      context,
      'Recovery and costs',
      _reactive(
        (current) => RiskRecoveryView(
          evaluation: _evaluationFor(current, evaluation),
          stateQuality: current.quality,
          hideValues: hideValues,
        ),
      ),
    );
  }

  void _showStress(BuildContext context, RiskEvaluation evaluation) {
    _showSheet(
      context,
      'Scenarios',
      _reactive(
        (current) => RiskStressView(
          evaluation: _stressEvaluation(current, evaluation),
          stateQuality: current.quality,
          hideValues: hideValues,
          onAddCustomPrice: (price) => _updateCustomPrice(context, price),
          onRemoveCustomPrice: (price) => _removeCustomPrice(context, price),
        ),
      ),
    );
  }

  void _updateCustomPrice(BuildContext context, double price) {
    final latestSettings = bridge.currentState.settings ?? settings;
    if (latestSettings.customStressPrices.any(
      (value) => (value - price).abs() < 1e-9,
    )) {
      return;
    }
    final next = latestSettings.copyWith(
      customStressPrices: [...latestSettings.customStressPrices, price],
    );
    bridge
        .send(
          RiskMonitorCommand.updateSettings(
            id: riskCommandId('custom-price-add'),
            settings: next,
          ),
        )
        .then((result) {
          if (!result.accepted || !context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Custom scenario price saved')),
          );
        });
  }

  void _removeCustomPrice(BuildContext context, double price) {
    final latestSettings = bridge.currentState.settings ?? settings;
    final next = latestSettings.copyWith(
      customStressPrices: latestSettings.customStressPrices
          .where((value) => (value - price).abs() >= 1e-9)
          .toList(growable: false),
    );
    bridge
        .send(
          RiskMonitorCommand.updateSettings(
            id: riskCommandId('custom-price-remove'),
            settings: next,
          ),
        )
        .then((result) {
          if (result.accepted && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Custom scenario price removed')),
            );
          }
        });
  }

  void _showPriceMap(BuildContext context, RiskEvaluation evaluation) {
    _showSheet(
      context,
      'Price map',
      _reactive((current) {
        final latest = _evaluationFor(current, evaluation);
        return RiskPriceMap(
          levels: latest?.priceMap ?? const <RiskPriceMapLevel>[],
          currentPrice: latest?.markPrice,
          hideValues: hideValues,
        );
      }),
    );
  }

  void _showPlan(BuildContext context, RiskEvaluation evaluation) {
    _showSheet(
      context,
      'Your plan',
      _reactive((current) {
        final latest = _evaluationFor(current, evaluation);
        final episodeKey =
            latest?.position.episodeKey ?? current.episodeKey ?? '';
        final currentPlan =
            current.plan != null &&
                (episodeKey.isEmpty || current.plan!.episodeKey == episodeKey)
            ? current.plan
            : _sameSession(current) &&
                  (plan != null &&
                      (episodeKey.isEmpty || plan!.episodeKey == episodeKey))
            ? plan
            : null;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: RiskPlanEditor(
            episodeKey: episodeKey,
            bridge: bridge,
            accountHash: current.accountHash,
            plan: currentPlan,
            hideValues: hideValues,
            evaluation: latest,
            planEvaluation: latest == null || current.planEvaluation == null
                ? null
                : current.planEvaluation,
            onPlanChanged: onPlanChanged,
          ),
        );
      }),
    );
  }

  void _showHistory(BuildContext context) {
    _showSheet(
      context,
      'History',
      _reactive(
        (current) => RiskHistoryView(
          events: current.events,
          samples:
              current.samples ??
              (_sameSession(current) ? samples : const <RiskHistorySample>[]),
          summaries:
              current.summaries ??
              (_sameSession(current) ? summaries : const <RiskDailySummary>[]),
          trend: current.trend,
          velocity: current.velocity,
          previousCheck: current.previousCheck,
          hideValues: hideValues,
          onClearHistory: () => bridge.send(
            RiskMonitorCommand.clearHistory(id: riskCommandId('history-clear')),
          ),
        ),
      ),
    );
  }

  Widget _reactive(Widget Function(RiskMonitorViewState) builder) {
    return StreamBuilder<RiskMonitorViewState>(
      stream: bridge.states,
      initialData: bridge.currentState,
      builder: (context, snapshot) => builder(snapshot.data ?? state),
    );
  }

  bool _sameSession(RiskMonitorViewState current) {
    final accountMatches =
        state.accountHash == null ||
        current.accountHash == null ||
        state.accountHash == current.accountHash;
    final episodeMatches =
        state.episodeKey == null ||
        current.episodeKey == null ||
        state.episodeKey == current.episodeKey;
    return accountMatches && episodeMatches;
  }

  RiskEvaluation? _evaluationFor(
    RiskMonitorViewState current,
    RiskEvaluation fallback,
  ) => current.evaluation ?? (_sameSession(current) ? fallback : null);

  RiskEvaluation? _stressEvaluation(
    RiskMonitorViewState current,
    RiskEvaluation fallback,
  ) {
    final latest = _evaluationFor(current, fallback);
    if (latest == null) return null;
    final latestSettings =
        current.settings ?? (_sameSession(current) ? settings : null);
    final customPrices = latestSettings?.customStressPrices ?? const <double>[];
    final evaluatedCustomPrices = latest.stressScenarios
        .where((scenario) => scenario.label == 'Custom price')
        .map((scenario) => scenario.price)
        .toList(growable: false);
    final customPricesMatch = _sameCustomPrices(
      customPrices,
      evaluatedCustomPrices,
    );
    if (customPricesMatch) return latest;
    final latestMarket =
        current.market ?? (_sameSession(current) ? market : null);
    return RiskEngine(clock: () => latest.evaluatedAt).evaluate(
      latest.position,
      policy: latestSettings?.policy,
      market: latestMarket,
      now: latest.evaluatedAt,
      customPrices: customPrices,
    );
  }

  void _showSheet(BuildContext context, String title, Widget child) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.88,
          child: Column(
            children: [
              ListTile(
                title: Text(title),
                trailing: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ),
              const Divider(height: 1),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }

  double? _volatilityMultiple(
    RiskEvaluation evaluation,
    RiskMarketInput? market,
  ) {
    final buffer = evaluation.buffer;
    final volatility = market?.dailyVolatility;
    if (buffer == null ||
        volatility == null ||
        !buffer.isFinite ||
        !volatility.isFinite ||
        volatility <= 0) {
      return null;
    }
    final multiple = buffer / volatility;
    return multiple.isFinite ? multiple : null;
  }
}

bool _sameCustomPrices(
  Iterable<double> configured,
  Iterable<double> evaluated,
) {
  final remaining = evaluated.toList(growable: true);
  for (final price in configured) {
    final index = remaining.indexWhere(
      (candidate) => (candidate - price).abs() < 1e-9,
    );
    if (index == -1) return false;
    remaining.removeAt(index);
  }
  return remaining.isEmpty;
}

class _MonitorStatus extends StatelessWidget {
  const _MonitorStatus({
    required this.state,
    required this.onRefresh,
    this.hideValues = false,
  });

  final RiskMonitorViewState state;
  final Future<void> Function() onRefresh;
  final bool hideValues;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quality = riskQualityLabel(state.quality);
    final running = state.isRunning ? 'Monitoring active' : 'Monitoring paused';
    final owner = state.ownerLabel.trim().isEmpty
        ? 'foreground'
        : riskRedactRiskText(state.ownerLabel, hideValues);
    return Card(
      key: const Key('risk-monitor-status'),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 5,
          children: [
            Icon(
              state.isRunning ? Icons.sync : Icons.pause_circle_outline,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            Text(running, style: theme.textTheme.labelLarge),
            Text('· $owner · $quality', style: theme.textTheme.bodySmall),
            if (!state.backgroundAvailable)
              Text('Background unavailable', style: theme.textTheme.bodySmall),
            if (state.lastError != null)
              Text(
                riskRedactRiskText(state.lastError!, hideValues),
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
              ),
            TextButton(onPressed: onRefresh, child: const Text('Refresh')),
          ],
        ),
      ),
    );
  }
}

class _PositionContext extends StatelessWidget {
  const _PositionContext({required this.evaluation, this.hideValues = false});

  final RiskEvaluation evaluation;
  final bool hideValues;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final position = evaluation.position;
    final instrument = position.instrumentId.trim().isEmpty
        ? '${position.baseCurrency}-${position.quoteCurrency}'
        : position.instrumentId;
    final baseSymbol = position.baseCurrency?.trim().isNotEmpty == true
        ? position.baseCurrency!.trim()
        : instrument.split('-').first.trim();
    final side = position.positionSide.trim().isEmpty
        ? '-'
        : position.positionSide.toUpperCase();
    return Card(
      key: const Key('risk-position-context'),
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 5,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CryptoIcon(
                  symbol: baseSymbol,
                  size: 20,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  textColor: theme.colorScheme.onSurface,
                  textSize: 10,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    riskRedactRiskText(instrument, hideValues),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            _ContextChip(
              label: riskRedactRiskText('ISOLATED $side', hideValues),
            ),
            _ContextChip(
              label: riskRedactRiskText(position.instrumentType, hideValues),
            ),
            Text(
              'Selected position',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContextChip extends StatelessWidget {
  const _ContextChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _SinceLastCheck extends StatelessWidget {
  const _SinceLastCheck({
    required this.state,
    required this.previousCheck,
    required this.hideValues,
  });

  final RiskMonitorViewState state;
  final RiskSessionComparison? previousCheck;
  final bool hideValues;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final observedAt = state.quality.observedAt ?? state.quality.sourceAt;
    return Card(
      key: const Key('risk-since-last-check'),
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
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  'Trend and velocity',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  hideValues
                      ? 'Last check ******'
                      : _formatRiskTimestamp(observedAt),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                _CheckValue(
                  label: 'Change',
                  value: hideValues
                      ? '- / Hidden'
                      : state.trend?.text ?? '- / Collecting history',
                ),
                _CheckValue(
                  label: 'Velocity',
                  value: hideValues
                      ? '- / Hidden'
                      : state.velocity?.text ?? '- / Collecting history',
                ),
                _CheckValue(
                  label: 'Quality',
                  value: riskQualityLabel(state.quality),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('Previous check', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            if (previousCheck == null)
              Text('No previous check', style: theme.textTheme.bodyMedium)
            else
              _PreviousCheckValues(
                comparison: previousCheck!,
                hideValues: hideValues,
              ),
          ],
        ),
      ),
    );
  }
}

class _CheckValue extends StatelessWidget {
  const _CheckValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
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

class _PreviousCheckValues extends StatelessWidget {
  const _PreviousCheckValues({
    required this.comparison,
    required this.hideValues,
  });

  final RiskSessionComparison comparison;
  final bool hideValues;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 18,
      runSpacing: 8,
      children: [
        _CheckValue(
          label: 'Overall',
          value: _stateRange(
            comparison.baseline.overallState,
            comparison.current.overallState,
          ),
        ),
        _CheckValue(
          label: 'Buffer',
          value: _numberRange(
            comparison.baseline.bufferPercentage,
            comparison.current.bufferPercentage,
            hideValues,
            decimals: 1,
            suffix: '%',
            delta: comparison.bufferDeltaPoints,
            deltaSuffix: ' pp',
          ),
        ),
        _CheckValue(
          label: 'Leverage',
          value: _numberRange(
            comparison.baseline.effectiveLeverage,
            comparison.current.effectiveLeverage,
            hideValues,
            suffix: 'x',
            delta: comparison.leverageDelta,
            deltaSuffix: 'x',
          ),
        ),
        _CheckValue(
          label: 'Debt',
          value: _numberRange(
            comparison.baseline.debt,
            comparison.current.debt,
            hideValues,
            suffix: ' USDT',
            delta: comparison.debtDelta,
            deltaSuffix: ' USDT',
          ),
        ),
        _CheckValue(
          label: 'True Exit',
          value: _numberRange(
            comparison.baseline.trueExitVerified
                ? comparison.baseline.trueExit
                : null,
            comparison.current.trueExitVerified
                ? comparison.current.trueExit
                : null,
            hideValues,
            suffix: ' USDT',
          ),
        ),
        _CheckValue(
          label: 'Structure',
          value: _textRange(
            comparison.baseline.structureLabel,
            comparison.current.structureLabel,
            hideValues,
          ),
        ),
        _CheckValue(
          label: 'Funding',
          value: _textRange(
            comparison.baseline.fundingLabel,
            comparison.current.fundingLabel,
            hideValues,
          ),
        ),
        _CheckValue(
          label: 'OI',
          value: _fractionRange(
            comparison.baseline.openInterestChange,
            comparison.current.openInterestChange,
            hideValues,
          ),
        ),
      ],
    );
  }
}

String _stateRange(RiskSeverity? before, RiskSeverity? after) =>
    '${before?.label ?? '-'} → ${after?.label ?? '-'}';

String _numberRange(
  double? before,
  double? after,
  bool hideValues, {
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

String _fractionRange(double? before, double? after, bool hideValues) {
  if ((before == null || !before.isFinite) &&
      (after == null || !after.isFinite)) {
    return '-';
  }
  if (hideValues) return '****** → ******';
  final left = riskPercent(before);
  final right = riskPercent(after);
  final delta = before != null && after != null ? after - before : null;
  final deltaText = delta == null || !delta.isFinite
      ? ''
      : ' (${delta > 0 ? '+' : ''}${(delta * 100).toStringAsFixed(1)} pp)';
  return '$left → $right$deltaText';
}

String _textRange(String? before, String? after, bool hideValues) =>
    '${riskRedactRiskText(before ?? '-', hideValues)} → ${riskRedactRiskText(after ?? '-', hideValues)}';

class _TopReasons extends StatelessWidget {
  const _TopReasons({
    required this.reasons,
    required this.hideValues,
    required this.onOpen,
  });

  final List<RiskReason> reasons;
  final bool hideValues;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('risk-top-reasons'),
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Top reasons',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(onPressed: onOpen, child: const Text('See all')),
              ],
            ),
            for (final reason in reasons.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  '• ${riskRedactRiskText(reason.message, hideValues)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _formatRiskTimestamp(DateTime? value) {
  if (value == null) return 'Last check -';
  final local = value.toLocal();
  final minute = local.minute.toString().padLeft(2, '0');
  return 'Last check ${local.month}/${local.day} ${local.hour}:$minute';
}

class _UnavailableDashboard extends StatelessWidget {
  const _UnavailableDashboard({
    required this.state,
    required this.onRefresh,
    this.hideValues = false,
  });

  final RiskMonitorViewState state;
  final Future<void> Function() onRefresh;
  final bool hideValues;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = switch (state.quality.status) {
      RiskQualityStatus.empty => 'No isolated position selected',
      RiskQualityStatus.error => 'Risk data unavailable',
      RiskQualityStatus.unsupported => 'Position is unsupported',
      RiskQualityStatus.stale => 'Last risk snapshot is stale',
      RiskQualityStatus.partial => 'Partial risk assessment',
      _ => 'Waiting for risk data',
    };
    final body =
        state.quality.reason ??
        'Risk Home needs a complete typed snapshot before it can assess the position.';
    return Card(
      key: const Key('risk-empty-state'),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: theme.colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(riskRedactRiskText(body, hideValues)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh risk data'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrilldownRow extends StatelessWidget {
  const _DrilldownRow({
    required this.onExposure,
    required this.onStress,
    required this.onRecovery,
    required this.onMap,
    required this.onPlan,
    required this.onHistory,
  });

  final VoidCallback onExposure;
  final VoidCallback onStress;
  final VoidCallback onRecovery;
  final VoidCallback onMap;
  final VoidCallback onPlan;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _DrillButton(
          label: 'Exposure & sensitivity',
          icon: Icons.analytics_outlined,
          onPressed: onExposure,
        ),
        _DrillButton(
          label: 'Recovery & costs',
          icon: Icons.flag_outlined,
          onPressed: onRecovery,
        ),
        _DrillButton(
          label: 'Scenarios',
          icon: Icons.show_chart,
          onPressed: onStress,
        ),
        _DrillButton(
          label: 'Price map',
          icon: Icons.map_outlined,
          onPressed: onMap,
        ),
        _DrillButton(
          label: 'Plan',
          icon: Icons.rule_outlined,
          onPressed: onPlan,
        ),
        _DrillButton(
          label: 'History',
          icon: Icons.history,
          onPressed: onHistory,
        ),
      ],
    );
  }
}

class _DrillButton extends StatelessWidget {
  const _DrillButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      label: Text(label),
    );
  }
}

class _MetricSheetRow extends StatelessWidget {
  const _MetricSheetRow({
    required this.label,
    required this.value,
    this.hideValues = false,
  });

  final String label;
  final String value;
  final bool hideValues;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(riskRedactRiskText(label, hideValues)),
      trailing: Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(message, style: theme.textTheme.bodySmall),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'Performance amounts stay hidden on Risk Home. Open Portfolio details to reveal them for this visit.',
      child: Text(
        'Risk Home keeps performance amounts out of the first view and notifications. Portfolio details has an explicit reveal step.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class TextSnackBar extends SnackBar {
  TextSnackBar({super.key, required String message})
    : super(content: Text(message));
}
