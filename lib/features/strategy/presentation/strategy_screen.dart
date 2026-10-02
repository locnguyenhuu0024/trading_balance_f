import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../orders/data/trade_api_client.dart';
import '../../orders/presentation/providers/trade_session_provider.dart';
import '../domain/strategy_models.dart';
import 'providers/strategy_dashboard_provider.dart';
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
                _introCard(context, session),
                if (!sessionState.isAuthenticated || session == null)
                  const _SignedOutCard()
                else ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Chiến thuật đã lưu',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      FilledButton.icon(
                        key: const Key('strategy-create-button'),
                        onPressed: dashboard == null
                            ? null
                            : () => _openWizard(context, session, dashboard),
                        icon: const Icon(Icons.add),
                        label: const Text('Dựng chiến thuật'),
                      ),
                    ],
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
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _StrategyCard(
                          strategy: strategy,
                          quote: _hasStartedStatus(strategy['status'])
                              ? dashboard.quoteFor(
                                  _text(strategy['instrumentId']).toUpperCase(),
                                )
                              : null,
                          quoteIsFresh:
                              _hasStartedStatus(strategy['status']) &&
                              dashboard.quoteIsFresh(
                                _text(strategy['instrumentId']).toUpperCase(),
                              ),
                          metricsAreStale: dashboard.metricsAreStale,
                          metricsStaleAt: dashboard.metricsStaleAt,
                          actionBusy: dashboard.isActionInFlight(
                            _text(strategy['id']),
                          ),
                          onReplace: strategy['canDelete'] == true
                              ? () => _openWizard(
                                  context,
                                  session,
                                  dashboard,
                                  replacementSourceId: _text(strategy['id']),
                                )
                              : null,
                          onApply:
                              _text(strategy['status']).toUpperCase() == 'DRAFT'
                              ? () => _applySaved(context, dashboard, strategy)
                              : null,
                          onDelete: strategy['canDelete'] == true
                              ? () => _deleteStrategy(
                                  context,
                                  dashboard,
                                  strategy,
                                )
                              : null,
                          onRefresh:
                              _text(strategy['status']).toUpperCase() == 'DRAFT'
                              ? null
                              : () => dashboard.refreshResult(
                                  _text(strategy['id']),
                                ),
                        ),
                      ),
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

  Widget _introCard(BuildContext context, TradeSession? session) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tạo kế hoạch lệnh từ các vùng hỗ trợ và kháng cự của hợp đồng USDT.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Lệnh chỉ được gửi sau khi bạn xem và xác nhận danh sách chính xác từ máy chủ.',
            ),
            if (session != null) ...[
              const SizedBox(height: 8),
              Text(
                'Phiên giao dịch: ${session.accountIdentifier.isEmpty ? 'đang đăng nhập' : session.accountIdentifier}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openWizard(
    BuildContext context,
    TradeSession session,
    StrategyDashboardController dashboard, {
    String? replacementSourceId,
  }) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StrategyWizardDialog(
        session: session,
        dashboard: dashboard,
        onSaved: dashboard.refresh,
        replacementSourceId: replacementSourceId,
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
      confirm: (prepared) => _confirmOrders(context, prepared),
    );
    if (!context.mounted) return;
    if (outcome.kind == StrategyApplyOutcomeKind.cancelled) return;
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

  Future<bool> _confirmOrders(
    BuildContext context,
    Map<String, dynamic> prepared,
  ) async {
    final orders = _preparedOrders(prepared);
    if (orders.isEmpty) return false;
    return await showDialog<bool>(
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
                      'Máy chủ đã kiểm tra lại giá và thông tin hợp đồng. Xác nhận sẽ gửi tối đa một lô lệnh.',
                    ),
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
              FilledButton(
                key: const Key('strategy-confirm-apply'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Xác nhận gửi lệnh'),
              ),
            ],
          ),
        ) ??
        false;
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

class _StrategyCard extends StatelessWidget {
  const _StrategyCard({
    required this.strategy,
    required this.quote,
    required this.quoteIsFresh,
    required this.metricsAreStale,
    required this.metricsStaleAt,
    required this.actionBusy,
    required this.onReplace,
    required this.onApply,
    required this.onDelete,
    required this.onRefresh,
  });

  final Map<String, dynamic> strategy;
  final StrategyTicker? quote;
  final bool quoteIsFresh;
  final bool metricsAreStale;
  final DateTime? metricsStaleAt;
  final bool actionBusy;
  final VoidCallback? onReplace;
  final VoidCallback? onApply;
  final VoidCallback? onDelete;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final status = _text(strategy['status']).toUpperCase();
    final neverSent = _isNeverSentStrategy(strategy);
    final instrument = _text(strategy['instrumentId']);
    final positions = _mapList(strategy['positions']);
    final position = positions.isEmpty
        ? const <String, dynamic>{}
        : positions.first;
    final quoteLabel = quote == null
        ? 'Giá SWAP chưa sẵn sàng'
        : 'Giá SWAP ${quote!.priceText}${quoteIsFresh ? '' : ' · đã cũ'}';
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
    final showOrderOutcomes = const {
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
    final leverageErrorCode = _safeLeverageErrorCode(
      _mapList(strategy['leverageResults']),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  instrument,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Chip(
                  label: Text(neverSent ? 'Chưa gửi' : _statusLabel(status)),
                ),
                if (_text(strategy['interval']).isNotEmpty)
                  Chip(label: Text(_text(strategy['interval']))),
              ],
            ),
            Text(quoteLabel, style: quoteStyle),
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
                _Metric(label: 'PnL chưa thực hiện', value: pnl),
                _Metric(label: 'Vốn đã khớp', value: usedMargin),
                _Metric(label: '% trên vốn đã khớp', value: pnlPercent),
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onReplace != null)
                  FilledButton.tonalIcon(
                    onPressed: actionBusy ? null : onReplace,
                    icon: const Icon(Icons.replay),
                    label: const Text('Tạo lại'),
                  ),
                if (onApply != null)
                  FilledButton.tonalIcon(
                    onPressed: actionBusy ? null : onApply,
                    icon: actionBusy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow),
                    label: const Text('Áp dụng bản nháp'),
                  ),
                if (onDelete != null)
                  OutlinedButton.icon(
                    onPressed: actionBusy ? null : onDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Xóa chiến thuật'),
                  ),
                if (onRefresh != null)
                  OutlinedButton.icon(
                    onPressed: actionBusy ? null : onRefresh,
                    icon: const Icon(Icons.sync),
                    label: const Text('Cập nhật trạng thái'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
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
        '$side · ${_text(order['role'])} · ${_text(order['limitPrice'])}',
      ),
      subtitle: Text(
        'Contr: ${_text(order['contracts'])} · Margin: ${_text(order['margin'])} · Fee: ${_text(order['openingFeeEstimate'])} · ${_text(order['leverage'])}x',
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
    final averageFill = _text(order['averageFillPrice']);
    final fillSummary =
        'Khớp: ${_display(order['filledContracts'])} / ${_display(order['contracts'])} hợp đồng';
    final subtitle = averageFill.isEmpty
        ? fillSummary
        : '$fillSummary · Giá khớp TB: $averageFill';
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(radius: 14, child: Text('$index')),
      title: Text('$side · $role · ${_text(order['limitPrice'])}'),
      subtitle: Text(subtitle),
      trailing: Chip(label: Text(status)),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 175,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        Text(_display(value), style: Theme.of(context).textTheme.bodyMedium),
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
          Text('Ký quỹ dự kiến: ${_text(prepared['plannedMargin'])} USDT'),
          Text('Phần dư: ${_text(prepared['unallocatedMargin'])} USDT'),
          Text(
            'Phí mở ước tính: ${_text(prepared['estimatedOpeningFees'])} USDT · tính riêng',
          ),
        ],
      ),
    ),
  );
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
  return validatedStrategyOrders(prepared) ?? const [];
}

List<Map<String, dynamic>> _mapList(Object? value) => value is List
    ? value.whereType<Map>().map(_map).toList(growable: false)
    : const [];

Map<String, dynamic> _map(Object? value) => value is Map
    ? value.map((key, item) => MapEntry(key.toString(), item))
    : const {};

Object? _first(Map<String, dynamic> values, List<String> keys) {
  for (final key in keys) {
    final value = values[key];
    if (value != null && value.toString().isNotEmpty) return value;
  }
  return null;
}

String _text(Object? value) => value == null ? '' : value.toString();

bool _isNeverSentStrategy(Map<String, dynamic> strategy) =>
    _text(strategy['status']).toUpperCase() != 'DRAFT' &&
    strategy['canDelete'] == true &&
    strategy['batchAttempted'] == false;

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

String _display(Object? value) => value == null || value.toString().isEmpty
    ? 'Chưa có dữ liệu'
    : value.toString();

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
  'accepted' => 'Đã nhận',
  'live' => 'Đang chờ',
  'partially_filled' => 'Khớp một phần',
  'filled' => 'Đã khớp',
  'canceled' => 'Đã hủy',
  'mmp_canceled' => 'Đã hủy MMP',
  'rejected' => 'Bị từ chối',
  'not_submitted' => 'Chưa gửi',
  _ => 'Chưa xác định',
};
