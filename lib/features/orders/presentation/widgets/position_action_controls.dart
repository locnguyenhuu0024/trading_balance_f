import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/okx_position_model.dart';
import '../../data/trade_api_client.dart';
import '../providers/position_action_flow_provider.dart';
import '../providers/trade_session_provider.dart';
import 'trade_action_confirmation_dialog.dart';

class PositionActionControls extends ConsumerWidget {
  const PositionActionControls({super.key, required this.position});

  final OkxPosition position;

  static const _actions = <_PositionAction>[
    _PositionAction('add_margin', 'Thêm ký quỹ', 'addMargin', 'amount'),
    _PositionAction('dca', 'DCA', 'dca', 'size'),
    _PositionAction(
      'partial_close',
      'Đóng một phần',
      'partialClose',
      'percentage',
    ),
    _PositionAction(
      'close_position',
      'Đóng 100%',
      'closePosition',
      null,
      destructive: true,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final api = ref.watch(tradeApiProvider);
    final sessionState = ref.watch(tradeSessionProvider);
    final session = sessionState.session;
    final identityComplete = positionActionHasCompleteIdentity(position);
    final accountIdentifier =
        session?.accountIdentifier ?? sessionState.operationAccountIdentifier;
    final flowState = ref.watch(
      positionActionFlowsProvider,
    )[positionActionFlowKey(position.identity, accountIdentifier)];
    final isBusy = flowState?.isBusy ?? false;
    final hasUnresolvedOperation = sessionState.pendingOperations.isNotEmpty;
    final enabled =
        api.isConfigured && sessionState.isAuthenticated && identityComplete;
    final disabledReasons = <String>[];

    if (!api.isConfigured) {
      disabledReasons.add('Chưa cấu hình TRADE_API_BASE_URL; chỉ xem vị thế.');
    } else if (!sessionState.isAuthenticated) {
      disabledReasons.add(
        sessionState.errorMessage ?? 'Đăng nhập API giao dịch để bật thao tác.',
      );
    }
    if (session != null && sessionState.isAuthenticated && !identityComplete) {
      disabledReasons.add(
        'Thiếu định danh hoặc hướng vị thế; máy khách sẽ không gửi yêu cầu.',
      );
    }
    if (hasUnresolvedOperation) {
      disabledReasons.add(
        'Có thao tác chưa rõ kết quả. Hãy tra cứu trạng thái trước khi gửi thao tác mới.',
      );
    }

    final actionStates = _actions
        .map((action) {
          final eligibility = tradeJsonMap(
            position.eligibleActions[action.eligibilityKey],
          );
          var allowed = eligibility['eligible'] == true;
          var reason = eligibility['reason']?.toString();
          if (position.instType.toUpperCase() == 'MARGIN' &&
              (action.apiName == 'dca' || action.apiName == 'partial_close')) {
            allowed = false;
            reason ??= action.apiName == 'dca'
                ? 'margin_dca_capacity_unverified'
                : 'margin_partial_close_capacity_unverified';
          }
          if (!identityComplete && reason == null) {
            reason = 'incomplete_position_identity_or_size';
          }
          if (enabled && !allowed && reason != null) {
            disabledReasons.add('${action.label}: ${_reasonText(reason)}');
          }
          return (action: action, allowed: allowed);
        })
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 16),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: actionStates
              .map((entry) {
                final action = entry.action;
                final canRun =
                    enabled &&
                    entry.allowed &&
                    !isBusy &&
                    !hasUnresolvedOperation;
                return IconButton(
                  tooltip: action.label,
                  onPressed: canRun
                      ? () => _startAction(context, ref, action)
                      : null,
                  color: action.destructive ? palette.negative : null,
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  icon: Icon(action.icon),
                );
              })
              .toList(growable: false),
        ),
        if (isBusy) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(minHeight: 2),
        ],
        if (disabledReasons.isNotEmpty) ...[
          const SizedBox(height: 6),
          for (final reason in disabledReasons)
            Text(reason, style: TextStyle(color: palette.muted, fontSize: 12)),
        ],
        if (flowState?.statusMessage case final statusMessage?) ...[
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            child: Text(
              statusMessage,
              style: TextStyle(
                color: statusMessage.startsWith('Đã hoàn tất')
                    ? palette.positive
                    : palette.negative,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _startAction(
    BuildContext context,
    WidgetRef ref,
    _PositionAction action,
  ) {
    // Capture page-owned objects before any await. The card can be removed or
    // moved by a positions refresh while input or confirmation is open.
    final navigator = Navigator.of(context, rootNavigator: true);
    final ownerRoute = ModalRoute.of(context);
    final controller = ref.read(positionActionFlowsProvider.notifier);
    unawaited(
      controller.runAction(
        position: position,
        action: action.apiName,
        inputKind: action.inputKind,
        navigator: navigator,
        ownerRoute: ownerRoute,
        collectInput: action.inputKind == null
            ? null
            : () => showDialog<String>(
                context: navigator.context,
                builder: (dialogContext) => _TradeActionInputDialog(
                  title: action.inputTitle,
                  inputKind: action.inputKind!,
                  marginCurrency: position.marginCurrency,
                ),
              ),
        confirm: (prepared) => showTradeActionConfirmation(
          navigator.context,
          prepared: prepared,
          title: action.confirmationTitle,
          confirmLabel: action.destructive ? 'Xác nhận đóng' : 'Xác nhận',
          destructive: action.destructive,
        ),
        showResult: (TradeOperationResult result, {String? lookupError}) =>
            _showPositionActionResult(
              navigator.context,
              result,
              lookupError: lookupError,
            ),
      ),
    );
  }
}

class _PositionAction {
  const _PositionAction(
    this.apiName,
    this.label,
    this.eligibilityKey,
    this.inputKind, {
    this.destructive = false,
  });

  final String apiName;
  final String label;
  final String eligibilityKey;
  final String? inputKind;
  final bool destructive;

  IconData get icon => switch (apiName) {
    'add_margin' => Icons.add_card_outlined,
    'dca' => Icons.trending_up,
    'partial_close' => Icons.pie_chart_outline,
    _ => Icons.close_rounded,
  };

  String get inputTitle => switch (inputKind) {
    'amount' => 'Nhập số tiền ký quỹ',
    'size' => 'Nhập khối lượng DCA',
    'percentage' => 'Nhập tỷ lệ đóng',
    _ => label,
  };

  String get confirmationTitle => switch (apiName) {
    'add_margin' => 'Xác nhận thêm ký quỹ',
    'dca' => 'Xác nhận DCA',
    'partial_close' => 'Xác nhận đóng một phần',
    _ => 'Xác nhận đóng vị thế 100%',
  };
}

class _TradeActionInputDialog extends StatefulWidget {
  const _TradeActionInputDialog({
    required this.title,
    required this.inputKind,
    required this.marginCurrency,
  });

  final String title;
  final String inputKind;
  final String marginCurrency;

  @override
  State<_TradeActionInputDialog> createState() =>
      _TradeActionInputDialogState();
}

class _TradeActionInputDialogState extends State<_TradeActionInputDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hint = switch (widget.inputKind) {
      'amount' =>
        'Số tiền (${widget.marginCurrency.isEmpty ? 'đơn vị ký quỹ' : widget.marginCurrency})',
      'size' => 'Khối lượng hợp đồng',
      _ => 'Phần trăm vị thế (0–100)',
    };
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        decoration: InputDecoration(labelText: hint),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Tiếp tục'),
        ),
      ],
    );
  }
}

Future<void> _showPositionActionResult(
  BuildContext context,
  TradeOperationResult result, {
  String? lookupError,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(_resultHeadline(result.status, result.operationId)),
      content: SizedBox(
        width: 420,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: ListView(
            shrinkWrap: true,
            children: [
              Text('Mã thao tác: ${result.operationId}'),
              for (final target in result.targets) _resultTarget(target),
              if (lookupError != null) ...[
                const SizedBox(height: 8),
                Text('Chưa tra cứu được trạng thái mới: $lookupError'),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Đóng'),
        ),
      ],
    ),
  );
}

Widget _resultTarget(Map<String, dynamic> target) {
  final identity = tradeJsonMap(target['identity']);
  final outcome = tradeJsonMap(target['outcome']);
  final instrument = identity['instrumentId']?.toString() ?? 'Vị thế';
  final status = target['status']?.toString().toUpperCase() ?? 'UNKNOWN';
  final reason = outcome['reason']?.toString();
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      '$instrument: $status${reason == null ? '' : ' · ${_reasonText(reason)}'}',
    ),
  );
}

String _resultHeadline(String status, String operationId) {
  return switch (status) {
    'SUCCEEDED' => 'Đã hoàn tất thao tác',
    'PARTIAL' => 'Thao tác chỉ hoàn tất một phần',
    'UNKNOWN' => 'Chưa rõ kết quả thao tác',
    'CONFLICT' => 'Vị thế đã thay đổi trước khi xác nhận',
    'FAILED' => 'Thao tác thất bại',
    'EXPIRED' => 'Xác nhận đã hết hạn',
    _ => 'Trạng thái $status · $operationId',
  };
}

String _reasonText(String reason) {
  const messages = {
    'margin_dca_capacity_unverified':
        'MARGIN DCA is disabled because trade capacity is not verified.',
    'margin_partial_close_capacity_unverified':
        'MARGIN partial close is disabled because capacity and debt limits are not verified.',
    'isolated_margin_required': 'Only isolated margin positions are supported.',
    'margin_currency_metadata_missing': 'The margin currency is unavailable.',
    'unknown_margin_mode': 'The margin mode is unknown.',
    'unknown_position_mode': 'The account position mode is unknown.',
    'ambiguous_position_direction':
        'The position direction cannot be verified.',
    'ambiguous_position_identity': 'The position identity is ambiguous.',
    'incomplete_position_identity_or_size':
        'Position identity or size is incomplete.',
    'zero_size_position': 'A zero-size position cannot be changed.',
    'instrument_size_rules_missing': 'Instrument size rules are unavailable.',
    'unsupported_instrument_type': 'This instrument type is not supported.',
  };
  return messages[reason] ?? reason.replaceAll('_', ' ');
}
