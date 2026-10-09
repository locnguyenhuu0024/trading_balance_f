import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/responsive_form_content.dart';
import '../data/strategy_api_client.dart';
import '../domain/strategy_models.dart';
import '../../orders/presentation/providers/trade_session_provider.dart';
import 'providers/strategy_dashboard_provider.dart';
import 'strategy_number_formatter.dart';

class StrategyRetryDialog extends ConsumerStatefulWidget {
  const StrategyRetryDialog({
    super.key,
    required this.dashboard,
    required this.flow,
    required this.sourceStrategy,
    required this.bearerToken,
  });

  final StrategyDashboardController dashboard;
  final StrategyRetryFlow flow;
  final Map<String, dynamic> sourceStrategy;
  final String bearerToken;

  @override
  ConsumerState<StrategyRetryDialog> createState() =>
      _StrategyRetryDialogState();
}

class _StrategyRetryDialogState extends ConsumerState<StrategyRetryDialog> {
  StrategyRetryCandidates? _candidates;
  StrategyRetryPreview? _preview;
  StrategyRetryDraft? _draft;
  Map<String, dynamic>? _prepared;
  final Set<String> _selectedIds = {};
  String? _error;
  bool _loading = true;
  bool _previewing = false;
  bool _creating = false;
  bool _preparing = false;
  bool _executing = false;

  bool get _busy =>
      _loading || _previewing || _creating || _preparing || _executing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCandidates());
  }

  Future<void> _loadCandidates() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final candidates = await widget.flow.loadCandidates();
      if (!mounted) return;
      setState(() {
        _candidates = candidates;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _errorMessage(error);
      });
    }
  }

  Future<void> _previewSelection() async {
    if (_busy || _selectedIds.isEmpty || _selectedIds.length > 10) return;
    setState(() {
      _previewing = true;
      _preview = null;
      _error = null;
    });
    try {
      final preview = await widget.flow.previewSelection(
        List<String>.unmodifiable(_selectedIds),
      );
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _previewing = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _previewing = false;
        _error = _errorMessage(error);
      });
    }
  }

  Future<void> _createDraft() async {
    if (_busy || _preview == null || _draft != null) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final draft = await widget.flow.createLinkedDraft();
      if (!mounted) return;
      setState(() {
        _draft = draft;
        _preview = draft.preview;
        _creating = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = _errorMessage(error);
      });
    }
  }

  Future<void> _prepareChild() async {
    if (_busy || _draft == null || _prepared != null) return;
    setState(() {
      _preparing = true;
      _error = null;
    });
    try {
      final prepared = await widget.flow.prepareChild();
      if (!mounted) return;
      setState(() {
        _prepared = prepared;
        _preparing = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _error = _errorMessage(error);
      });
    }
  }

  Future<void> _executeOnce() async {
    if (_busy || _prepared == null || !widget.dashboard.ownsSession) return;
    setState(() {
      _executing = true;
      _error = null;
    });
    try {
      final result = await widget.flow.executeOnce();
      if (!mounted || !widget.dashboard.ownsSession) return;
      final status = _text(result['status']).toUpperCase();
      final mode = StrategyLimitOrderSubmissionMode.parse(
        _prepared?['submissionMode'],
      );
      final kind =
          status == 'APPLYING' &&
              mode == StrategyLimitOrderSubmissionMode.sequential &&
              const {'pending', 'sending'}.contains(result['queueStatus'])
          ? StrategyRetryOutcomeKind.queued
          : const {'APPLIED', 'COMPLETED'}.contains(status)
          ? StrategyRetryOutcomeKind.applied
          : StrategyRetryOutcomeKind.unknown;
      Navigator.of(context).pop(
        StrategyRetryOutcome(
          kind,
          childId: _draft!.id,
          result: result,
          message: kind == StrategyRetryOutcomeKind.unknown
              ? 'Kết quả gửi chưa rõ. Không gửi lại; hãy cập nhật trạng thái.'
              : null,
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _executing = false;
        _error = _errorMessage(error);
      });
    }
  }

  void _cancel() {
    widget.flow.cancel();
    Navigator.of(
      context,
    ).pop(const StrategyRetryOutcome(StrategyRetryOutcomeKind.cancelled));
  }

  @override
  Widget build(BuildContext context) {
    final currentSession = ref.watch(tradeSessionProvider).session;
    final ownsVisibleSession =
        currentSession?.bearerToken == widget.bearerToken &&
        widget.dashboard.ownsSession;
    final size = MediaQuery.sizeOf(context);
    final preview = _preview;
    final candidates = _candidates;

    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: size.width < 600 ? 12 : 32,
          vertical: 16,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 760,
            maxHeight: size.height * 0.9,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Gửi lại lệnh limit',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('strategy-retry-cancel'),
                      tooltip: 'Đóng',
                      onPressed: _cancel,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  child: ResponsiveFormContent(
                    maxWidth: 720,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _lineageSummary(candidates),
                        const SizedBox(height: 12),
                        if (_loading)
                          const FormPendingStatus(
                            label: 'Đang tải lệnh đủ điều kiện gửi lại…',
                          ),
                        if (_error != null) ...[
                          _Notice(message: _error!, isError: true),
                          const SizedBox(height: 10),
                        ],
                        if (candidates?.blockedReason case final String reason)
                          _Notice(
                            message: _blockMessage(reason),
                            isError: true,
                          ),
                        if (candidates != null) ...[
                          Text(
                            'Chọn 1–10 lệnh theo mã lệnh nguồn. Lệnh đủ điều kiện được chọn rõ ràng; danh sách dài hơn 10 lệnh không tự rút gọn.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 8),
                          Text('Đã chọn: ${_selectedIds.length} / 10'),
                          const SizedBox(height: 8),
                          for (final candidate in candidates.candidates)
                            _candidateTile(candidate),
                        ],
                        if (preview != null) ...[
                          const SizedBox(height: 16),
                          const Divider(),
                          Text(
                            _draft == null
                                ? 'Bản xem trước cố định'
                                : 'Bản xem trước đã liên kết với ${_draft!.id}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Giá tham chiếu hiện tại ${StrategyNumberFormatter.amount(preview.raw['currentPrice'], placeholder: '—')} · ${_text(preview.raw['quoteTimestamp'])}',
                          ),
                          _RetryCostSummary(preview: preview),
                          const SizedBox(height: 8),
                          for (
                            var index = 0;
                            index < preview.orders.length;
                            index++
                          )
                            _RetryOrderTile(
                              index: index + 1,
                              order: preview.orders[index],
                            ),
                        ],
                        if (_draft != null) ...[
                          const SizedBox(height: 12),
                          _Notice(
                            message:
                                'Đã tạo bản gửi lại ${_draft!.id}. Bản nguồn ${widget.flow.sourceStrategyId} vẫn được giữ trong lịch sử.',
                          ),
                        ],
                        if (widget.flow.createAttempted && _draft == null)
                          const _Notice(
                            message:
                                'Yêu cầu tạo bản gửi lại đã được gửi. Không gửi lại trong phiên này; hãy làm mới trạng thái để xem bản liên kết.',
                            isError: true,
                          ),
                        if (widget.flow.prepareAttempted && _prepared == null)
                          const _Notice(
                            message:
                                'Kết quả chuẩn bị chưa rõ. Bản chưa gửi vẫn còn trong lịch sử; làm mới để kiểm tra và không xin mã xác nhận mới.',
                            isError: true,
                          ),
                        if (_prepared != null) ...[
                          const Divider(height: 28),
                          Text(
                            'Xác nhận chính xác một lần',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Bản gửi lại: ${_text(_prepared!['id'])} · Nguồn: ${widget.flow.sourceStrategyId}',
                          ),
                          Text(
                            'Cơ chế gửi đã cố định: ${StrategyLimitOrderSubmissionMode.parse(_prepared!['submissionMode'])?.label ?? 'không khả dụng'}',
                          ),
                          _PreparedRetryCosts(prepared: _prepared!),
                          for (
                            var index = 0;
                            index < (_prepared!['orders'] as List).length;
                            index++
                          )
                            _RetryOrderTile(
                              index: index + 1,
                              order: Map<String, dynamic>.from(
                                (_prepared!['orders'] as List)[index] as Map,
                              ),
                            ),
                          const SizedBox(height: 8),
                          const _Notice(
                            message:
                                'Nếu hủy hoặc phiên thay đổi, bản PREPARED vẫn còn trong lịch sử và sẽ hết hạn theo quy tắc hiện hành. Không tự xóa, tạo lại hoặc xin mã xác nhận khác.',
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      key: const Key('strategy-retry-cancel-flow'),
                      onPressed: _cancel,
                      child: Text(_prepared == null ? 'Hủy' : 'Hủy xác nhận'),
                    ),
                    if (candidates != null &&
                        preview == null &&
                        !widget.flow.createAttempted &&
                        candidates.blockedReason == null)
                      AsyncFormButton(
                        key: const Key('strategy-retry-preview'),
                        onPressed:
                            ownsVisibleSession &&
                                !_busy &&
                                _selectedIds.isNotEmpty &&
                                _selectedIds.length <= 10
                            ? _previewSelection
                            : null,
                        label: 'Xem lại lệnh đã chọn',
                        busyLabel: 'Đang xem lại lệnh…',
                        isBusy: _previewing,
                      ),
                    if (preview != null && _draft == null)
                      AsyncFormButton(
                        key: const Key('strategy-retry-create'),
                        onPressed:
                            ownsVisibleSession &&
                                !_busy &&
                                !widget.flow.createAttempted
                            ? _createDraft
                            : null,
                        label: 'Tạo bản gửi lại liên kết',
                        busyLabel: 'Đang tạo bản gửi lại…',
                        isBusy: _creating,
                      ),
                    if (_draft != null && _prepared == null)
                      AsyncFormButton(
                        key: const Key('strategy-retry-prepare'),
                        onPressed:
                            ownsVisibleSession &&
                                !_busy &&
                                !widget.flow.prepareAttempted
                            ? _prepareChild
                            : null,
                        label: 'Chuẩn bị xác nhận',
                        busyLabel: 'Đang chuẩn bị xác nhận…',
                        isBusy: _preparing,
                      ),
                    if (_prepared != null)
                      AsyncFormButton(
                        key: const Key('strategy-retry-execute-once'),
                        onPressed:
                            ownsVisibleSession &&
                                !_busy &&
                                !widget.flow.executeAttempted
                            ? _executeOnce
                            : null,
                        label: 'Xác nhận và gửi một lần',
                        busyLabel: 'Đang gửi một lần…',
                        isBusy: _executing,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lineageSummary(StrategyRetryCandidates? candidates) {
    final sourceId = widget.flow.sourceStrategyId;
    final instrument = _text(widget.sourceStrategy['instrumentId']);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nguồn: $sourceId · $instrument'),
            if (candidates?.linkedChildren.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              const Text('Lịch sử các bản gửi lại liên kết:'),
              for (final child in candidates!.linkedChildren)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '$sourceId → ${child.strategyId} · ${child.status} · nguồn: ${child.sourceClientOrderIds.join(', ')}',
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _candidateTile(StrategyRetryCandidate candidate) {
    final selected = _selectedIds.contains(candidate.sourceClientOrderId);
    final reason = candidate.eligible
        ? null
        : _candidateReason(candidate.reason);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: CheckboxListTile(
        key: Key('strategy-retry-candidate-${candidate.sourceClientOrderId}'),
        value: candidate.eligible ? selected : false,
        onChanged:
            !candidate.eligible ||
                _busy ||
                _draft != null ||
                widget.flow.createAttempted
            ? null
            : (checked) {
                setState(() {
                  if (checked == true) {
                    if (_selectedIds.length >= 10) {
                      _error =
                          'Chỉ có thể chọn tối đa 10 lệnh cho một lần gửi.';
                    } else {
                      _selectedIds.add(candidate.sourceClientOrderId);
                      _error = null;
                    }
                  } else {
                    _selectedIds.remove(candidate.sourceClientOrderId);
                    _error = null;
                  }
                  _preview = null;
                });
              },
        title: Text(
          '${candidate.side.toUpperCase()} · ${candidate.role} · ${StrategyNumberFormatter.amount(candidate.limitPrice, placeholder: '—')}',
        ),
        subtitle: Text(
          'Mã nguồn ${candidate.sourceClientOrderId} · ${StrategyNumberFormatter.amount(candidate.contracts, placeholder: '—')} hợp đồng · ${candidate.leverage}x${reason == null ? ' · ${_outcomeLabel(candidate.priorOutcome)}' : ' · $reason'}',
        ),
        controlAffinity: ListTileControlAffinity.leading,
      ),
    );
  }

  String _errorMessage(Object error) => switch (error) {
    StrategyApiException(:final message) => message,
    StrategyRetryFlowException(:final message) => message,
    _ => 'Không thể hoàn thành bước gửi lại. Làm mới trạng thái rồi xem lại.',
  };

  String _candidateReason(String? code) => switch (code) {
    'accepted' => 'Lệnh đã được OKX nhận',
    'unknown' => 'Chưa rõ OKX đã nhận lệnh hay chưa',
    'filled' || 'partially_filled' => 'Lệnh đã khớp một phần hoặc toàn bộ',
    'canceled' => 'Lệnh đã hủy sau khi gửi',
    'placement_in_flight' || 'sending' => 'Lệnh đang được gửi',
    'source_changed' || 'stale' => 'Dữ liệu nguồn đã thay đổi',
    'child_overlap' || 'selection_in_use' => 'Đã có bản gửi lại liên kết',
    'missing_evidence' => 'Không đủ bằng chứng an toàn để gửi lại',
    _ => 'Không đủ điều kiện: ${code ?? 'không rõ lý do'}',
  };

  String _blockMessage(String code) => switch (code) {
    'position_exists' || 'positions_present' =>
      'Tài khoản còn vị thế. Kiểm tra vị thế và cập nhật trạng thái trước khi xem lại.',
    'pending_order' || 'pending_orders' =>
      'Tài khoản còn lệnh đang chờ. Cập nhật trạng thái trước khi xem lại.',
    'reservation_conflict' || 'reservation_exists' =>
      'Tài khoản còn khoản vốn được giữ chỗ. Cập nhật trạng thái trước khi xem lại.',
    'retry_selection_in_use' =>
      'Lệnh nguồn đã thuộc bản gửi lại khác. Mở lịch sử liên kết để kiểm tra.',
    'retry_source_stale' || 'retry_preview_stale' =>
      'Dữ liệu nguồn đã thay đổi. Làm mới danh sách và xem lại.',
    _ =>
      'Chưa thể gửi lại: $code. Cập nhật vị thế, lệnh đang chờ và khoản vốn giữ chỗ rồi xem lại.',
  };

  String _outcomeLabel(String outcome) => switch (outcome) {
    'not_submitted' => 'chưa được gửi',
    'rejected' => 'bị OKX từ chối',
    _ => 'trạng thái trước: khác',
  };
}

class _RetryCostSummary extends StatelessWidget {
  const _RetryCostSummary({required this.preview});

  final StrategyRetryPreview preview;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        Text(
          'Ký quỹ: ${StrategyNumberFormatter.amount(preview.totalMargin, placeholder: '—')}',
        ),
        Text(
          'Phí mở ước tính: ${StrategyNumberFormatter.amount(preview.estimatedOpeningFees, placeholder: '—')}',
        ),
        Text(
          'Vốn cần có: ${StrategyNumberFormatter.amount(preview.requiredBalance, placeholder: '—')}',
        ),
        Text(
          'Chưa phân bổ: ${StrategyNumberFormatter.amount(preview.unallocatedMargin, placeholder: '—')}',
        ),
      ],
    ),
  );
}

class _PreparedRetryCosts extends StatelessWidget {
  const _PreparedRetryCosts({required this.prepared});

  final Map<String, dynamic> prepared;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        Text(
          'Ký quỹ: ${StrategyNumberFormatter.amount(prepared['plannedMargin'], placeholder: '—')}',
        ),
        Text(
          'Phí mở ước tính: ${StrategyNumberFormatter.amount(prepared['estimatedOpeningFees'], placeholder: '—')}',
        ),
        Text(
          'Chưa phân bổ: ${StrategyNumberFormatter.amount(prepared['unallocatedMargin'], placeholder: '—')}',
        ),
      ],
    ),
  );
}

class _RetryOrderTile extends StatelessWidget {
  const _RetryOrderTile({required this.index, required this.order});

  final int index;
  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    leading: CircleAvatar(radius: 14, child: Text('$index')),
    title: Text(
      '${_text(order['side']).toUpperCase()} · ${_text(order['role'])} · ${StrategyNumberFormatter.amount(order['limitPrice'], placeholder: '—')}',
    ),
    subtitle: Text(
      'Nguồn ${_text(order['sourceClientOrderId'])}${order['clientOrderId'] == null ? '' : ' → ${_text(order['clientOrderId'])}'} · ${StrategyNumberFormatter.amount(order['contracts'], placeholder: '—')} hợp đồng · ${_text(order['leverage'])}x · Ký quỹ ${StrategyNumberFormatter.amount(order['margin'], placeholder: '—')} · Phí ${StrategyNumberFormatter.amount(order['openingFeeEstimate'], placeholder: '—')}',
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: isError
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(message),
  );
}

String _text(Object? value) => value == null ? '' : value.toString();
