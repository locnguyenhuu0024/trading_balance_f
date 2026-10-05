import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/pnl_color.dart';
import '../../orders/data/trade_api_client.dart';
import '../../orders/presentation/providers/trade_session_provider.dart';
import '../domain/strategy_models.dart';
import 'providers/strategy_dashboard_provider.dart';
import 'strategy_automatic_draft_dialog.dart';
import 'strategy_number_formatter.dart';
import 'strategy_retry_dialog.dart';
import 'strategy_settings_dialog.dart';
import 'strategy_wizard_dialog.dart';

class StrategyScreen extends ConsumerStatefulWidget {
  const StrategyScreen({super.key});

  @override
  ConsumerState<StrategyScreen> createState() => _StrategyScreenState();
}

class _StrategyScreenState extends ConsumerState<StrategyScreen>
    with WidgetsBindingObserver {
  StrategyDashboardController? _boundDashboard;
  StrategyDashboardController? _scheduledDashboard;
  bool _appVisible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appVisible =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appVisible = state == AppLifecycleState.resumed;
    _boundDashboard?.setVisibility(pageVisible: true, appVisible: _appVisible);
  }

  void _scheduleDashboardBinding(StrategyDashboardController? dashboard) {
    if (identical(_scheduledDashboard, dashboard)) return;
    _scheduledDashboard = dashboard;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_scheduledDashboard, dashboard)) return;
      final previous = _boundDashboard;
      _boundDashboard = dashboard;
      if (!identical(previous, dashboard)) {
        previous?.setVisibility(pageVisible: false, appVisible: _appVisible);
      }
      dashboard?.setVisibility(pageVisible: true, appVisible: _appVisible);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _boundDashboard?.setVisibility(pageVisible: false, appVisible: _appVisible);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessionState = ref.watch(tradeSessionProvider);
    final session = sessionState.session;
    final dashboard = sessionState.isAuthenticated && session != null
        ? ref.watch(strategyDashboardProvider(session.bearerToken))
        : null;
    _scheduleDashboardBinding(dashboard);
    final width = MediaQuery.sizeOf(context).width;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chiến Thuật'),
        actions: [
          IconButton(
            key: const Key('strategy-settings-button'),
            tooltip: 'Cài đặt',
            onPressed: () => _openSettings(
              context,
              sessionState.isAuthenticated ? session?.bearerToken : null,
              dashboard,
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
          if (dashboard != null)
            IconButton(
              tooltip: 'Làm mới danh sách',
              onPressed: dashboard.isLoading ? null : dashboard.refresh,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                width < 600 ? 14 : 24,
                12,
                width < 600 ? 14 : 24,
                112,
              ),
              children: [
                if (!sessionState.isAuthenticated || session == null)
                  const _SignedOutCard()
                else ...[
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        IconButton(
                          key: const Key('strategy-create-button'),
                          tooltip: 'Dựng chiến thuật',
                          onPressed: dashboard == null
                              ? null
                              : () => _openWizard(context, session, dashboard),
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          icon: const Icon(Icons.add),
                        ),
                        IconButton(
                          key: const Key('strategy-automatic-create-button'),
                          tooltip: 'Dựng chiến thuật tự động',
                          onPressed: dashboard == null
                              ? null
                              : () => _openAutomaticWizard(
                                  context,
                                  session,
                                  dashboard,
                                ),
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          icon: const Icon(Icons.auto_awesome_outlined),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (dashboard?.loadError != null)
                    _InlineNotice(
                      message: dashboard!.loadError!,
                      onRetry: dashboard.isLoading ? null : dashboard.refresh,
                    ),
                  if (dashboard?.isLoading == true &&
                      dashboard!.strategies.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(36),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (dashboard?.strategies.isEmpty ?? true)
                    const _EmptyStrategiesCard()
                  else
                    for (final strategy in dashboard!.strategies)
                      _buildStrategyCard(context, session, dashboard, strategy),
                  if (dashboard?.actionError != null)
                    _InlineNotice(message: dashboard!.actionError!),
                  if (dashboard?.deleteError != null)
                    _InlineNotice(message: dashboard!.deleteError!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStrategyCard(
    BuildContext context,
    TradeSession session,
    StrategyDashboardController dashboard,
    Map<String, dynamic> strategy,
  ) {
    final id = _text(strategy['id']);
    _StrategyActions actionsFor(Map<String, dynamic> current) =>
        _strategyActionsFor(context, session, dashboard, current);
    final actions = actionsFor(strategy);
    final openDetails = () => showDialog<void>(
      context: context,
      builder: (dialogContext) => _StrategyDetailsDialog(
        dashboard: dashboard,
        bearerToken: session.bearerToken,
        strategyId: id,
        actionsForStrategy: actionsFor,
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _StrategyCard(
        strategy: strategy,
        actions: actions,
        metricsAreStale: dashboard.metricsAreStale,
        onOpenDetails: openDetails,
      ),
    );
  }

  _StrategyActions _strategyActionsFor(
    BuildContext context,
    TradeSession session,
    StrategyDashboardController dashboard,
    Map<String, dynamic> strategy,
  ) {
    final id = _text(strategy['id']);
    final status = _text(strategy['status']).toUpperCase();
    final candidateStage = _text(strategy['draftStage']) == 'candidates';
    final currentStrategy = () =>
        dashboard.ownsSession ? dashboard.strategyById(id) : null;
    final oversizedDraft =
        (status == 'DRAFT' ||
            (status == 'PREPARED' && strategy['canDelete'] == true)) &&
        hasOversizedNewStrategyOrderPayload(strategy);

    return _StrategyActions(
      actionBusy: dashboard.isActionInFlight(id),
      blockApply: oversizedDraft,
      onReview: candidateStage && strategy['canReview'] == true
          ? () {
              final current = currentStrategy();
              if (current != null &&
                  _text(current['draftStage']) == 'candidates' &&
                  current['canReview'] == true) {
                _openWizard(
                  context,
                  session,
                  dashboard,
                  initialCandidateDraft: current,
                );
              }
            }
          : null,
      onReplace: !candidateStage && _canReplaceStrategy(strategy)
          ? () {
              final current = currentStrategy();
              if (current != null && _canReplaceStrategy(current)) {
                _openWizard(
                  context,
                  session,
                  dashboard,
                  replacementSourceId: id,
                );
              }
            }
          : null,
      onApply: status == 'DRAFT' && !candidateStage
          ? () {
              final current = currentStrategy();
              if (!oversizedDraft &&
                  _text(current?['status']).toUpperCase() == 'DRAFT') {
                _applySaved(context, dashboard, current!);
              }
            }
          : null,
      onRetry: candidateStage || const {'DRAFT', 'PREPARED'}.contains(status)
          ? null
          : () {
              final current = currentStrategy();
              if (current != null &&
                  !const {
                    'DRAFT',
                    'PREPARED',
                  }.contains(_text(current['status']).toUpperCase())) {
                _retryLimitOrders(context, session, dashboard, current);
              }
            },
      onDelete: strategy['canDelete'] == true
          ? () {
              final current = currentStrategy();
              if (current?['canDelete'] == true) {
                _deleteStrategy(context, dashboard, current!);
              }
            }
          : null,
      onRefresh: status == 'DRAFT'
          ? null
          : () {
              final current = currentStrategy();
              if (current != null &&
                  _text(current['status']).toUpperCase() != 'DRAFT') {
                dashboard.refreshResult(id);
              }
            },
    );
  }

  void _openWizard(
    BuildContext context,
    TradeSession session,
    StrategyDashboardController dashboard, {
    String? replacementSourceId,
    Map<String, dynamic>? initialCandidateDraft,
  }) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StrategyWizardDialog(
        session: session,
        dashboard: dashboard,
        onSaved: dashboard.refresh,
        replacementSourceId: replacementSourceId,
        initialCandidateDraft: initialCandidateDraft,
      ),
    );
  }

  Future<void> _openAutomaticWizard(
    BuildContext context,
    TradeSession session,
    StrategyDashboardController dashboard,
  ) async {
    final candidateDraft = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          StrategyAutomaticDraftDialog(session: session, dashboard: dashboard),
    );
    if (!context.mounted ||
        candidateDraft == null ||
        !dashboard.ownsSession ||
        !_sessionMatches(session)) {
      return;
    }
    await dashboard.refresh();
    if (!context.mounted ||
        !dashboard.ownsSession ||
        !_sessionMatches(session)) {
      return;
    }
    final generation =
        _stringMap(candidateDraft['aiGeneration']) ??
        _stringMap(_map(candidateDraft['snapshot'])['aiGeneration']) ??
        const <String, dynamic>{};
    final recommendation = _stringMap(generation['recommendation']);
    final longIds = recommendation?['longLevelIds'];
    final shortIds = recommendation?['shortLevelIds'];
    final countText = longIds is List && shortIds is List
        ? 'Long ${longIds.length} · Short ${shortIds.length}'
        : 'số mức đề xuất chưa có';
    final emptyRecommendation =
        longIds is List &&
        shortIds is List &&
        longIds.isEmpty &&
        shortIds.isEmpty;
    final message = emptyRecommendation
        ? 'Đã lưu bản nháp tự động · Long 0 · Short 0. Chưa có mức nào đạt tiêu chí Jev; bạn có thể chọn thủ công khi xem xét.'
        : 'Đã lưu bản nháp tự động · $countText.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            key: const Key('strategy-automatic-save-notice'),
          ),
          duration: const Duration(seconds: 6),
        ),
      );
  }

  bool _sessionMatches(TradeSession session) {
    final state = ref.read(tradeSessionProvider);
    return state.isAuthenticated &&
        state.session?.bearerToken == session.bearerToken;
  }

  void _openSettings(
    BuildContext context,
    String? bearerToken,
    StrategyDashboardController? dashboard,
  ) {
    showDialog<void>(
      context: context,
      builder: (context) => StrategySettingsDialog(
        bearerToken: bearerToken,
        dashboard: dashboard,
      ),
    );
  }

  Future<void> _applySaved(
    BuildContext context,
    StrategyDashboardController dashboard,
    Map<String, dynamic> strategy,
  ) async {
    final id = _text(strategy['id']);
    if (id.isEmpty) return;
    final outcome = await dashboard.applyDraft(
      id,
      confirm: (prepared) => _confirmOrders(context, dashboard, prepared),
    );
    if (!context.mounted || !dashboard.ownsSession) return;
    if (outcome.kind == StrategyApplyOutcomeKind.cancelled) return;
    if (outcome.kind == StrategyApplyOutcomeKind.queued) {
      _showMessage(
        context,
        outcome.message ?? 'Các lệnh đã được đưa vào hàng đợi tuần tự.',
      );
      return;
    }
    if (outcome.kind == StrategyApplyOutcomeKind.unknown) {
      _showMessage(context, outcome.message ?? 'Kết quả đang được xác minh.');
    } else if (outcome.kind == StrategyApplyOutcomeKind.duplicate) {
      _showMessage(context, 'Yêu cầu này đang được xử lý.');
    } else if (outcome.kind == StrategyApplyOutcomeKind.rejected) {
      _showMessage(context, outcome.message ?? 'Máy chủ từ chối áp dụng.');
    } else {
      if (outcome.result?['replacementCleanupConflict'] == true) {
        _showMessage(
          context,
          'OKX đã chấp nhận đầy đủ lệnh thay thế, nhưng hệ thống chưa xóa được chiến thuật cũ.',
        );
      } else {
        final status = _text(outcome.result?['status']).toUpperCase();
        _showMessage(
          context,
          status == 'APPLIED'
              ? 'Máy chủ đã chấp nhận lệnh chiến thuật.'
              : 'Trạng thái chiến thuật: ${status.isEmpty ? 'đang cập nhật' : status}.',
        );
      }
    }
  }

  Future<void> _retryLimitOrders(
    BuildContext context,
    TradeSession session,
    StrategyDashboardController dashboard,
    Map<String, dynamic> strategy,
  ) async {
    final sourceId = _text(strategy['id']);
    if (sourceId.isEmpty) return;
    final random = math.Random.secure();
    final retryRequestId = base64Url
        .encode(List<int>.generate(24, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    final outcome = await dashboard.retryLimitOrders(
      sourceId,
      retryRequestId: retryRequestId,
      interact: (flow) => showDialog<StrategyRetryOutcome>(
        context: context,
        barrierDismissible: false,
        builder: (context) => StrategyRetryDialog(
          dashboard: dashboard,
          flow: flow,
          sourceStrategy: strategy,
          bearerToken: session.bearerToken,
        ),
      ),
    );
    if (!context.mounted || !dashboard.ownsSession) return;
    switch (outcome.kind) {
      case StrategyRetryOutcomeKind.cancelled:
        return;
      case StrategyRetryOutcomeKind.duplicate:
        _showMessage(context, 'Yêu cầu này đang được xử lý.');
        break;
      case StrategyRetryOutcomeKind.rejected:
      case StrategyRetryOutcomeKind.unknown:
        _showMessage(
          context,
          outcome.message ?? 'Không thể xác nhận kết quả gửi lại. Hãy làm mới.',
        );
        break;
      case StrategyRetryOutcomeKind.queued:
        _showMessage(
          context,
          'Bản gửi lại ${outcome.childId ?? ''} đã vào hàng đợi tuần tự.',
        );
        break;
      case StrategyRetryOutcomeKind.applied:
        _showMessage(
          context,
          'Đã gửi bản liên kết ${outcome.childId ?? ''}. Cập nhật lịch sử để xem trạng thái.',
        );
        break;
    }
  }

  Future<bool> _confirmOrders(
    BuildContext context,
    StrategyDashboardController dashboard,
    Map<String, dynamic> prepared,
  ) async {
    final orders = _preparedOrders(prepared);
    final mode = StrategyLimitOrderSubmissionMode.parse(
      prepared['submissionMode'],
    );
    if (orders.isEmpty || mode == null || !dashboard.ownsSession) return false;
    final sessionState = ref.read(tradeSessionProvider);
    final bearerToken = sessionState.session?.bearerToken;
    final confirmed =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Xác nhận danh sách lệnh'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Máy chủ đã kiểm tra lại giá và thông tin hợp đồng. Cơ chế dưới đây đã được cố định cho danh sách này.',
                    ),
                    const SizedBox(height: 8),
                    _SubmissionModeSummary(mode: mode),
                    const SizedBox(height: 8),
                    _PreparedFinancialSummary(prepared: prepared),
                    const SizedBox(height: 12),
                    for (var i = 0; i < orders.length; i++)
                      _OrderSummaryRow(index: i + 1, order: orders[i]),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Hủy'),
              ),
              Consumer(
                builder: (context, ref, _) {
                  final state = ref.watch(tradeSessionProvider);
                  final ownsSession =
                      state.isAuthenticated &&
                      state.session?.bearerToken == bearerToken &&
                      dashboard.ownsSession;
                  return FilledButton(
                    key: const Key('strategy-confirm-apply'),
                    onPressed: ownsSession
                        ? () => Navigator.of(context).pop(true)
                        : null,
                    child: const Text('Xác nhận gửi lệnh'),
                  );
                },
              ),
            ],
          ),
        ) ??
        false;
    return confirmed && dashboard.ownsSession;
  }

  Future<void> _deleteStrategy(
    BuildContext context,
    StrategyDashboardController dashboard,
    Map<String, dynamic> strategy,
  ) async {
    final id = _text(strategy['id']);
    if (id.isEmpty || strategy['canDelete'] != true) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa chiến thuật?'),
        content: const Text(
          'Chỉ xóa bản ghi chiến thuật trong ứng dụng; lệnh trên OKX không bị hủy hoặc thay đổi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Giữ lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xóa chiến thuật'),
          ),
        ],
      ),
    );
    if (accepted != true || !context.mounted) return;
    final deleted = await dashboard.deleteDraft(id);
    if (context.mounted) {
      _showMessage(
        context,
        deleted ? 'Đã xóa chiến thuật.' : 'Không thể xóa chiến thuật.',
      );
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _StrategyActions {
  const _StrategyActions({
    required this.actionBusy,
    required this.blockApply,
    required this.onReview,
    required this.onReplace,
    required this.onApply,
    required this.onRetry,
    required this.onDelete,
    required this.onRefresh,
  });

  final bool actionBusy;
  final bool blockApply;
  final VoidCallback? onReview;
  final VoidCallback? onReplace;
  final VoidCallback? onApply;
  final VoidCallback? onRetry;
  final VoidCallback? onDelete;
  final VoidCallback? onRefresh;
}

class _StrategyCard extends StatelessWidget {
  const _StrategyCard({
    required this.strategy,
    required this.actions,
    required this.metricsAreStale,
    required this.onOpenDetails,
  });

  final Map<String, dynamic> strategy;
  final _StrategyActions actions;
  final bool metricsAreStale;
  final VoidCallback onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final id = _text(strategy['id']);
    final instrument = _text(strategy['instrumentId']);
    final coin = instrument
        .split('-')
        .firstWhere((part) => part.isNotEmpty, orElse: () => instrument);
    final orderRows = strategy['orders'] is List
        ? strategy['orders'] as List
        : null;
    var awaiting = 0;
    var filled = 0;
    if (orderRows != null) {
      for (final value in orderRows) {
        if (value is! Map) continue;
        final status = _text(value['status']).toLowerCase();
        if (status == 'live' || status == 'partially_filled') {
          awaiting++;
        } else if (status == 'filled') {
          filled++;
        }
      }
    }
    final statusLabel = _summaryStatusLabel(strategy);
    final tooltipLines = <String>[];
    if (metricsAreStale) {
      tooltipLines.add('Dữ liệu vốn có thể đã cũ.');
    }
    if (orderRows == null) {
      tooltipLines.add('Danh sách lệnh chưa khả dụng.');
    }
    final syncState = _text(strategy['orderSyncState']).toLowerCase();
    if (syncState == 'stale') {
      tooltipLines.add('Trạng thái lệnh đã cũ.');
    } else if (syncState == 'error' || syncState == 'unavailable') {
      tooltipLines.add('Trạng thái lệnh hiện chưa khả dụng.');
    }
    tooltipLines.add(
      'Chỉ trạng thái live / khớp một phần được tính là chưa khớp; lệnh xếp hàng, chưa gửi, đã hủy, bị từ chối và chưa xác định không được tính. Hai nhóm có thể không bằng tổng lệnh.',
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: Key('strategy-summary-$id'),
            onTap: onOpenDetails,
            child: Semantics(
              button: true,
              label: 'Mở chi tiết chiến thuật $coin',
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            coin,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        Tooltip(
                          message: tooltipLines.join('\n'),
                          child: Icon(
                            Icons.info_outline,
                            size: 18,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Chip(
                      label: Text(statusLabel),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Vốn: ${_summaryTotalMargin(strategy['totalMargin'])}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 16,
                      runSpacing: 6,
                      children: [
                        _StrategySummaryCount(
                          label: 'Tổng lệnh',
                          value: orderRows?.length.toString() ?? '--',
                        ),
                        _StrategySummaryCount(
                          label: 'Chưa khớp',
                          value: orderRows == null ? '--' : '$awaiting',
                        ),
                        _StrategySummaryCount(
                          label: 'Đã khớp',
                          value: orderRows == null ? '--' : '$filled',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          _StrategyActionFooter(strategyId: id, actions: actions),
        ],
      ),
    );
  }
}

class _StrategySummaryCount extends StatelessWidget {
  const _StrategySummaryCount({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Text('$label: $value');
}

class _StrategyDetailContent extends StatelessWidget {
  const _StrategyDetailContent({
    required this.strategy,
    required this.quote,
    required this.quoteIsFresh,
    required this.metricsAreStale,
    required this.metricsStaleAt,
    required this.actions,
  });

  final Map<String, dynamic> strategy;
  final StrategyTicker? quote;
  final bool quoteIsFresh;
  final bool metricsAreStale;
  final DateTime? metricsStaleAt;
  final _StrategyActions actions;

  @override
  Widget build(BuildContext context) {
    final status = _text(strategy['status']).toUpperCase();
    final neverSent = _isNeverSentStrategy(strategy);
    final oversizedUnstartedDraft =
        (status == 'DRAFT' ||
            (status == 'PREPARED' && strategy['canDelete'] == true)) &&
        hasOversizedNewStrategyOrderPayload(strategy);
    final instrument = _text(strategy['instrumentId']);
    final positions = _mapList(strategy['positions']);
    final position = positions.isEmpty
        ? const <String, dynamic>{}
        : positions.first;
    final quoteLabel = quote == null
        ? 'Giá SWAP chưa sẵn sàng'
        : 'Giá SWAP ${StrategyNumberFormatter.amount(quote!.priceText)}${quoteIsFresh ? '' : ' · đã cũ'}';
    final quoteStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: quoteIsFresh ? null : Theme.of(context).colorScheme.error,
    );
    final usedMargin = _first(strategy, ['filledMargin', 'usedMargin']);
    final pnlPercent = strategy['pnlPercent'];
    final pnl = _first(strategy, ['unrealizedPnl', 'upl']);
    final observedAt =
        _first(position, ['observedAt']) ?? strategy['observedAt'];
    final orderSyncState = _text(strategy['orderSyncState']).toLowerCase();
    final lastOrderScanAt = _text(strategy['lastOrderScanAt']);
    final orderRows = _mapList(strategy['orders']);
    final submissionMode = StrategyLimitOrderSubmissionMode.parse(
      strategy['submissionMode'],
    );
    final showOrderOutcomes = const {
      'APPLYING',
      'APPLIED',
      'PARTIAL',
      'UNKNOWN',
      'COMPLETED',
    }.contains(status);
    final orderScanNotice = switch (orderSyncState) {
      'error' => 'Lỗi đồng bộ lệnh',
      'stale' => 'Lần quét lệnh đã cũ',
      _ => null,
    };
    final lastSuccessfulOrderScan = lastOrderScanAt.isEmpty
        ? 'chưa có lần quét thành công'
        : 'lần quét thành công gần nhất: ${_timeText(lastOrderScanAt)}';
    final orderScanNoticeText = orderScanNotice == null
        ? null
        : '$orderScanNotice · $lastSuccessfulOrderScan';
    final failureReason = _text(strategy['failureReason']);
    final resubmission = _stringMap(strategy['resubmission']);
    final sourceStrategyId = _text(resubmission?['sourceStrategyId']);
    final sourceClientOrderIds = _stringList(
      resubmission?['sourceClientOrderIds'],
    );
    final leverageErrorCode = _safeLeverageErrorCode(
      _mapList(strategy['leverageResults']),
    );
    final pnlPalette = AppPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(instrument, style: Theme.of(context).textTheme.titleMedium),
            Chip(label: Text(neverSent ? 'Chưa gửi' : _statusLabel(status))),
            if (_text(strategy['interval']).isNotEmpty)
              Chip(label: Text(_text(strategy['interval']))),
          ],
        ),
        Text(quoteLabel, style: quoteStyle),
        if (oversizedUnstartedDraft)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              status == 'PREPARED'
                  ? 'Bản nháp đã chuẩn bị vượt quá giới hạn 10 lệnh. Cập nhật trạng thái rồi tạo lại với tối đa 10 lệnh.'
                  : 'Bản nháp cũ vượt quá giới hạn 10 lệnh. Hãy tạo bản nháp mới với tối đa 10 lệnh để tiếp tục.',
            ),
          ),
        if (neverSent) ...[
          const SizedBox(height: 6),
          const Text('Không có lệnh nào được gửi lên OKX.'),
          if (failureReason == 'leverage_rejected')
            Text(
              leverageErrorCode == null
                  ? 'OKX từ chối thiết lập đòn bẩy.'
                  : 'OKX từ chối thiết lập đòn bẩy (mã: $leverageErrorCode).',
            ),
        ],
        if (strategy['replacementCleanupConflict'] == true)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'OKX đã chấp nhận đầy đủ lệnh thay thế, nhưng hệ thống chưa xóa được chiến thuật cũ.',
            ),
          ),
        if (status == 'DRAFT' && strategy['submissionMode'] == null)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Cơ chế gửi lệnh: chưa xác nhận.'),
          )
        else if (submissionMode != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Cơ chế gửi đã cố định: ${submissionMode.label}.'),
          )
        else if (strategy['submissionMode'] != null)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Cơ chế gửi lệnh chưa khả dụng.'),
          ),
        if (status == 'APPLYING' || strategy['queueStatus'] != null) ...[
          const SizedBox(height: 4),
          _QueueStatusSummary(strategy: strategy),
        ],
        if (sourceStrategyId.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Bản gửi lại ${_text(strategy['id'])} liên kết với nguồn $sourceStrategyId · ${sourceClientOrderIds.join(', ')}',
            ),
          ),
        if (quote?.observedAt != null)
          Text('Giá được ghi nhận lúc ${_time(quote!.observedAt)}'),
        if (metricsAreStale)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              metricsStaleAt == null
                  ? 'Dữ liệu PnL và vị thế chưa được cập nhật.'
                  : 'Dữ liệu PnL và vị thế đã cũ; lần cập nhật gần nhất thất bại lúc ${_time(metricsStaleAt!)}.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 20,
          runSpacing: 8,
          children: [
            _Metric(
              label: 'PnL chưa thực hiện',
              value: pnl,
              valueColor: resolvePnlColor(_finiteNumber(pnl), pnlPalette),
            ),
            _Metric(label: 'Vốn đã khớp', value: usedMargin),
            _Metric(
              label: '% trên vốn đã khớp',
              value: pnlPercent,
              isPercent: true,
              valueColor: resolvePnlColor(
                _finiteNumber(pnlPercent),
                pnlPalette,
              ),
            ),
            _Metric(
              label: 'Giá vào',
              value: _first(position, ['avgPx', 'entryPrice']),
            ),
            _Metric(
              label: 'Giá hiện tại',
              value: _first(position, ['markPx', 'latestPrice']),
            ),
            _Metric(
              label: 'Thanh lý thực tế',
              value: _first(position, ['liqPx', 'liquidationPrice']),
            ),
          ],
        ),
        if (_text(observedAt).isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Dữ liệu tài khoản: ${_text(observedAt)}'),
        ],
        if (strategy['attributionChanged'] == true)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Vị thế có hoạt động ngoài chiến thuật này; số liệu phản ánh tài khoản OKX.',
            ),
          ),
        if (showOrderOutcomes && orderRows.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Trạng thái từng lệnh',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (!neverSent && orderScanNoticeText != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                orderScanNoticeText,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            )
          else if (!neverSent && lastOrderScanAt.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Lần quét lệnh gần nhất: ${_timeText(lastOrderScanAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          for (var index = 0; index < orderRows.length; index++)
            _AppliedOrderRow(index: index + 1, order: orderRows[index]),
        ],
        const SizedBox(height: 10),
        _StrategyActionFooter(
          strategyId: _text(strategy['id']),
          actions: actions,
        ),
      ],
    );
  }
}

class _StrategyActionFooter extends StatelessWidget {
  const _StrategyActionFooter({
    required this.strategyId,
    required this.actions,
  });

  final String strategyId;
  final _StrategyActions actions;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      if (actions.onReview != null)
        _button(
          key: Key('strategy-review-$strategyId'),
          tooltip: 'Xem lại ứng viên',
          icon: Icons.rate_review_outlined,
          onPressed: actions.onReview,
        ),
      if (actions.onReplace != null)
        _button(
          key: Key('strategy-replace-$strategyId'),
          tooltip: 'Tạo lại',
          icon: Icons.replay,
          onPressed: actions.onReplace,
        ),
      if (actions.onApply != null)
        _button(
          key: Key('strategy-apply-$strategyId'),
          tooltip: 'Áp dụng bản nháp',
          icon: Icons.play_arrow,
          onPressed: actions.onApply,
          busy: actions.actionBusy,
          disabled: actions.blockApply,
        ),
      if (actions.onRetry != null)
        _button(
          key: Key('strategy-retry-$strategyId'),
          tooltip: 'Gửi lại lệnh limit',
          icon: Icons.replay_circle_filled_outlined,
          onPressed: actions.onRetry,
        ),
      if (actions.onDelete != null)
        _button(
          key: Key('strategy-delete-$strategyId'),
          tooltip: 'Xóa chiến thuật',
          icon: Icons.delete_outline,
          onPressed: actions.onDelete,
        ),
      if (actions.onRefresh != null)
        _button(
          key: Key('strategy-refresh-$strategyId'),
          tooltip: 'Cập nhật trạng thái',
          icon: Icons.sync,
          onPressed: actions.onRefresh,
        ),
    ];
    if (children.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 4, runSpacing: 0, children: children);
  }

  Widget _button({
    required Key key,
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    bool busy = false,
    bool disabled = false,
  }) => IconButton(
    key: key,
    tooltip: tooltip,
    onPressed: actions.actionBusy || disabled ? null : onPressed,
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    icon: busy
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icon),
  );
}

class _StrategyDetailsDialog extends StatelessWidget {
  const _StrategyDetailsDialog({
    required this.dashboard,
    required this.bearerToken,
    required this.strategyId,
    required this.actionsForStrategy,
  });

  final StrategyDashboardController dashboard;
  final String bearerToken;
  final String strategyId;
  final _StrategyActions Function(Map<String, dynamic> strategy)
  actionsForStrategy;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    return Consumer(
      builder: (context, ref, child) {
        final sessionState = ref.watch(tradeSessionProvider);
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: SizedBox(
            width: math.min(screenSize.width - 32, 760),
            height: math.min(screenSize.height - 32, 720),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Chi tiết chiến thuật',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Đóng chi tiết',
                        onPressed: () => Navigator.of(context).pop(),
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: AnimatedBuilder(
                    animation: dashboard,
                    builder: (context, child) {
                      final ownsCapturedSession =
                          sessionState.isAuthenticated &&
                          sessionState.session?.bearerToken == bearerToken &&
                          dashboard.ownsSession;
                      if (!ownsCapturedSession) {
                        return const _UnavailableStrategyDetail(
                          message:
                              'Phiên giao dịch đã thay đổi. Chi tiết và thao tác của phiên cũ đã được ẩn.',
                        );
                      }
                      final strategy = dashboard.strategyById(strategyId);
                      if (strategy == null) {
                        return const _UnavailableStrategyDetail(
                          message:
                              'Chiến thuật này không còn trong danh sách hiện tại.',
                        );
                      }
                      final actions = actionsForStrategy(strategy);
                      final instrument = _text(
                        strategy['instrumentId'],
                      ).toUpperCase();
                      final started = _hasStartedStatus(strategy['status']);
                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                        child: _StrategyDetailContent(
                          strategy: strategy,
                          quote: started
                              ? dashboard.quoteFor(instrument)
                              : null,
                          quoteIsFresh:
                              started && dashboard.quoteIsFresh(instrument),
                          metricsAreStale: dashboard.metricsAreStale,
                          metricsStaleAt: dashboard.metricsStaleAt,
                          actions: actions,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _UnavailableStrategyDetail extends StatelessWidget {
  const _UnavailableStrategyDetail({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Semantics(liveRegion: true, child: Text(message)),
    ),
  );
}

class _OrderSummaryRow extends StatelessWidget {
  const _OrderSummaryRow({required this.index, required this.order});

  final int index;
  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    final side = _text(order['side']).toUpperCase();
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(radius: 14, child: Text('$index')),
      title: Text(
        '$side · ${_text(order['role'])} · ${StrategyNumberFormatter.amount(order['limitPrice'], placeholder: '—')}',
      ),
      subtitle: Text(
        'Contr: ${StrategyNumberFormatter.amount(order['contracts'], placeholder: '—')} · Margin: ${StrategyNumberFormatter.amount(order['margin'], placeholder: '—')} · Fee: ${StrategyNumberFormatter.amount(order['openingFeeEstimate'], placeholder: '—')} · ${_text(order['leverage'])}x',
      ),
    );
  }
}

class _AppliedOrderRow extends StatelessWidget {
  const _AppliedOrderRow({required this.index, required this.order});

  final int index;
  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    final side = _text(order['side']).toUpperCase();
    final role = _text(order['role']).toLowerCase();
    final status = _orderStatusLabel(_text(order['status']).toLowerCase());
    final placementState = _text(order['placementState']).toLowerCase();
    final placementLabel = strategyPlacementStateLabel(placementState);
    final averageFill = StrategyNumberFormatter.amount(
      order['averageFillPrice'],
      placeholder: '',
    );
    final fillSummary =
        'Khớp: ${_display(order['filledContracts'])} / ${_display(order['contracts'])} hợp đồng';
    final subtitle = averageFill.isEmpty
        ? fillSummary
        : '$fillSummary · Giá khớp TB: $averageFill';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(radius: 14, child: Text('$index')),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$side · $role · ${StrategyNumberFormatter.amount(order['limitPrice'], placeholder: '—')}',
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 38, top: 3),
            child: Text(subtitle),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 38, top: 4),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                if (placementState.isNotEmpty)
                  Tooltip(
                    message: 'Trạng thái gửi',
                    child: Chip(
                      label: Text(placementLabel ?? 'Gửi chưa khả dụng'),
                    ),
                  ),
                Tooltip(
                  message: 'Trạng thái lệnh và khớp trên OKX',
                  child: Chip(label: Text(status)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.valueColor,
    this.isPercent = false,
  });

  final String label;
  final Object? value;
  final Color? valueColor;
  final bool isPercent;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 175,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        Text(
          isPercent
              ? StrategyNumberFormatter.percent(
                  value,
                  placeholder: 'Chưa có dữ liệu',
                )
              : _display(value),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: valueColor),
        ),
      ],
    ),
  );
}

class _PreparedFinancialSummary extends StatelessWidget {
  const _PreparedFinancialSummary({required this.prepared});

  final Map<String, dynamic> prepared;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Wrap(
        spacing: 16,
        runSpacing: 6,
        children: [
          Text(
            'Ký quỹ dự kiến: ${StrategyNumberFormatter.amount(prepared['plannedMargin'], placeholder: '—')} USDT',
          ),
          Text(
            'Phần dư: ${StrategyNumberFormatter.amount(prepared['unallocatedMargin'], placeholder: '—')} USDT',
          ),
          Text(
            'Phí mở ước tính: ${StrategyNumberFormatter.amount(prepared['estimatedOpeningFees'], placeholder: '—')} USDT · tính riêng',
          ),
        ],
      ),
    ),
  );
}

class _SubmissionModeSummary extends StatelessWidget {
  const _SubmissionModeSummary({required this.mode});

  final StrategyLimitOrderSubmissionMode mode;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cơ chế gửi đã cố định: ${mode.label}'),
          const SizedBox(height: 4),
          Text(mode.explanation),
        ],
      ),
    ),
  );
}

class _QueueStatusSummary extends StatelessWidget {
  const _QueueStatusSummary({required this.strategy});

  final Map<String, dynamic> strategy;

  @override
  Widget build(BuildContext context) {
    final rawStatus = strategy['queueStatus'];
    final statusLabel = strategyQueueStatusLabel(rawStatus);
    final progress = validatedStrategyQueueProgress(strategy['queueProgress']);
    final progressLabel = progress == null
        ? 'Tiến độ hàng đợi chưa khả dụng.'
        : 'Tiến độ hàng đợi: ${progress.attemptedCount} đã thử, ${progress.acceptedCount} đã nhận, ${progress.pendingCount} đang chờ, ${progress.notSubmittedCount} chưa gửi / ${progress.totalCount}.';
    final queueDescription = statusLabel == null
        ? 'Trạng thái hàng đợi chưa khả dụng.'
        : rawStatus == 'submitted'
        ? '$statusLabel; trạng thái này không xác nhận lệnh đã khớp.'
        : statusLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text(queueDescription), Text(progressLabel)],
    );
  }
}

class _SignedOutCard extends StatelessWidget {
  const _SignedOutCard();

  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(18),
      child: Text(
        'Đăng nhập phiên giao dịch hiện tại để xem chiến thuật đã lưu hoặc tạo chiến thuật mới.',
      ),
    ),
  );
}

class _EmptyStrategiesCard extends StatelessWidget {
  const _EmptyStrategiesCard();

  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(18),
      child: Text('Chưa có chiến thuật nào. Tạo bản nháp để bắt đầu.'),
    ),
  );
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: ListTile(
      leading: const Icon(Icons.info_outline),
      title: Text(message),
      trailing: onRetry == null
          ? null
          : IconButton(onPressed: onRetry, icon: const Icon(Icons.refresh)),
    ),
  );
}

List<Map<String, dynamic>> _preparedOrders(Map<String, dynamic> prepared) {
  return validatedNewStrategyOrders(prepared) ?? const [];
}

List<Map<String, dynamic>> _mapList(Object? value) => value is List
    ? value.whereType<Map>().map(_map).toList(growable: false)
    : const [];

Map<String, dynamic> _map(Object? value) => value is Map
    ? value.map((key, item) => MapEntry(key.toString(), item))
    : const {};

Map<String, dynamic>? _stringMap(Object? value) =>
    value is Map && value.keys.every((key) => key is String)
    ? Map<String, dynamic>.from(value)
    : null;

List<String> _stringList(Object? value) => value is List
    ? value.whereType<String>().toList(growable: false)
    : const [];

Object? _first(Map<String, dynamic> values, List<String> keys) {
  for (final key in keys) {
    final value = values[key];
    if (value != null && value.toString().isNotEmpty) return value;
  }
  return null;
}

String _text(Object? value) => value == null ? '' : value.toString();

double? _finiteNumber(Object? value) {
  final number = value is num
      ? value.toDouble()
      : double.tryParse(_text(value));
  return number?.isFinite == true ? number : null;
}

String _summaryStatusLabel(Map<String, dynamic> strategy) {
  if (_text(strategy['draftStage']) == 'candidates') {
    return 'Chờ xem xét';
  }
  if (_isAllCanceledStrategy(strategy)) return 'Đã hủy';
  if (_isNeverSentStrategy(strategy)) return 'Chưa gửi';
  return _statusLabel(_text(strategy['status']).toUpperCase());
}

bool _isAllCanceledStrategy(Map<String, dynamic> strategy) {
  if (const {
    'DRAFT',
    'PREPARED',
    'APPLYING',
  }.contains(_text(strategy['status']).toUpperCase())) {
    return false;
  }
  final orders = strategy['orders'];
  if (orders is! List || orders.isEmpty) return false;
  for (final row in orders) {
    if (row is! Map) return false;
    final status = _text(row['status']).toLowerCase();
    if (status != 'canceled' && status != 'mmp_canceled') return false;
  }

  final queueStatus = _text(strategy['queueStatus']).toLowerCase();
  if (queueStatus.isNotEmpty &&
      !const {'stopped', 'submitted'}.contains(queueStatus)) {
    return false;
  }
  final orderSyncState = _text(strategy['orderSyncState']).toLowerCase();
  if (const {'stale', 'error', 'unavailable'}.contains(orderSyncState)) {
    return false;
  }
  final hasQueueEvidence =
      queueStatus.isNotEmpty ||
      _text(strategy['submissionMode']).toLowerCase() == 'sequential';
  if (hasQueueEvidence || strategy['queueProgress'] != null) {
    final progress = validatedStrategyQueueProgress(strategy['queueProgress']);
    if (progress == null ||
        progress.pendingCount != 0 ||
        progress.notSubmittedCount != 0 ||
        progress.totalCount != orders.length) {
      return false;
    }
  }
  if (_text(strategy['executionId']).isNotEmpty) {
    return false;
  }
  return true;
}

bool _canReplaceStrategy(Map<String, dynamic> strategy) {
  final serverValue = strategy['canReplace'];
  if (serverValue is bool) return serverValue;
  // Older servers only exposed the original never-sent deletion predicate.
  if (_text(strategy['status']).toUpperCase() == 'DRAFT') {
    return strategy['canDelete'] == true &&
        strategy['batchAttempted'] != true &&
        strategy['orderPlacementAttempted'] != true;
  }
  return _isNeverSentStrategy(strategy);
}

bool _isNeverSentStrategy(Map<String, dynamic> strategy) =>
    _text(strategy['status']).toUpperCase() != 'DRAFT' &&
    strategy['canDelete'] == true &&
    strategy['batchAttempted'] == false &&
    strategy['orderPlacementAttempted'] != true &&
    strategy['canReplace'] != false;

String? _safeLeverageErrorCode(List<Map<String, dynamic>> results) {
  for (final result in results) {
    final code = _text(result['errorCode']).trim().toUpperCase();
    if (RegExp(r'^[A-Z0-9_-]{1,32}$').hasMatch(code)) return code;
  }
  return null;
}

bool _hasStartedStatus(Object? status) => const {
  'APPLIED',
  'PARTIAL',
  'UNKNOWN',
}.contains(_text(status).toUpperCase());

String _display(Object? value) =>
    StrategyNumberFormatter.amount(value, placeholder: 'Chưa có dữ liệu');

String _summaryTotalMargin(Object? value) {
  final parsed = double.tryParse(value?.toString().trim() ?? '');
  if (parsed == null || !parsed.isFinite || parsed < 0) return '--';
  final amount = StrategyNumberFormatter.amount(value);
  return amount == '--' ? amount : '$amount USDT';
}

String _time(DateTime timestamp) {
  final local = timestamp.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

String _timeText(String value) {
  final parsed = DateTime.tryParse(value);
  return parsed == null ? value : _time(parsed);
}

String _statusLabel(String status) => switch (status) {
  'DRAFT' => 'Bản nháp',
  'PREPARED' => 'Đang chờ xác nhận',
  'APPLYING' => 'Đang gửi',
  'APPLIED' => 'Đã gửi',
  'PARTIAL' => 'Một phần / cần kiểm tra',
  'UNKNOWN' => 'Chưa rõ kết quả',
  'COMPLETED' => 'Hoàn tất',
  _ => status.isEmpty ? 'Không rõ trạng thái' : status,
};

String _orderStatusLabel(String status) => switch (status) {
  'queued' => 'Đang xếp hàng',
  'sending' => 'Đang gửi',
  'accepted' => 'Đã nhận',
  'live' => 'Đang chờ',
  'partially_filled' => 'Khớp một phần',
  'filled' => 'Đã khớp',
  'canceled' => 'Đã hủy',
  'mmp_canceled' => 'Đã hủy MMP',
  'rejected' => 'Bị từ chối',
  'unknown' => 'Chưa xác định',
  'not_submitted' => 'Chưa gửi',
  _ => 'Chưa xác định',
};
