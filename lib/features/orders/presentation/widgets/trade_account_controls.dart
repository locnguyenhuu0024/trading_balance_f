import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/pnl_color.dart';
import '../../data/trade_api_client.dart';
import '../providers/order_cancellation_flow_provider.dart';
import '../providers/order_provider.dart';
import '../providers/position_action_flow_provider.dart';
import '../providers/trade_session_provider.dart';
import 'trade_action_confirmation_dialog.dart';

class TradeAccountControls extends ConsumerStatefulWidget {
  const TradeAccountControls({
    super.key,
    this.showCloseAll = true,
    this.filterControls,
  });

  final bool showCloseAll;
  final Widget? filterControls;

  @override
  ConsumerState<TradeAccountControls> createState() =>
      _TradeAccountControlsState();
}

class _TradeAccountControlsState extends ConsumerState<TradeAccountControls> {
  bool _busy = false;
  TradeSession? _busyOwnerSession;
  String? _statusMessage;
  TradeSession? _statusOwnerSession;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final closeAllColor = Theme.of(context).brightness == Brightness.dark
        ? PnlColors.darkNegative
        : PnlColors.lightNegative;
    final api = ref.watch(tradeApiProvider);
    final sessionState = ref.watch(tradeSessionProvider);
    final session = sessionState.session;
    final isAuthenticated = sessionState.isAuthenticated;
    final pendingOperations = sessionState.pendingOperations;
    final hasUnresolvedOperation = pendingOperations.isNotEmpty;
    ref.watch(orderCancellationFlowProvider);
    final cancellationFlows = ref.read(orderCancellationFlowProvider.notifier);
    final canShowOperationDetails =
        sessionState.isAuthenticated &&
        session != null &&
        sessionState.operationAccountIdentifier == session.accountIdentifier;
    final activePositionAction = session == null
        ? false
        : ref
              .watch(positionActionFlowsProvider)
              .values
              .any(
                (flow) =>
                    flow.isBusy &&
                    flow.accountIdentifier == session.accountIdentifier,
              );
    final canShowCloseAll =
        widget.showCloseAll && api.isConfigured && isAuthenticated;
    final closeAllButton = Tooltip(
      message: 'Đóng tất cả vị thế',
      child: IconButton(
        onPressed: _busy || hasUnresolvedOperation || activePositionAction
            ? null
            : _closeAll,
        style: IconButton.styleFrom(
          foregroundColor: closeAllColor,
          side: BorderSide(color: closeAllColor, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
          ),
          minimumSize: const Size(48, 48),
          maximumSize: const Size(48, 48),
          padding: EdgeInsets.zero,
        ),
        icon: const Icon(Icons.warning_amber_rounded, size: 20),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.space3,
        AppTokens.space2,
        AppTokens.space3,
        AppTokens.space1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.filterControls != null)
            Row(
              children: [
                Expanded(child: widget.filterControls!),
                if (canShowCloseAll) ...[
                  const SizedBox(width: AppTokens.space2),
                  closeAllButton,
                ],
              ],
            )
          else if (canShowCloseAll)
            Align(alignment: Alignment.centerLeft, child: closeAllButton),
          if (!api.isConfigured)
            Text(
              widget.showCloseAll
                  ? 'Chỉ xem vị thế. Hãy cấu hình API khi build rồi đăng nhập trong Cài đặt để bật thao tác.'
                  : 'Lệnh chờ vẫn chỉ được xem. Cấu hình API và đăng nhập trong Cài đặt để tra cứu thao tác.',
              style: const TextStyle(fontSize: 12),
            )
          else if (!isAuthenticated) ...[
            Text(
              widget.showCloseAll
                  ? 'Vị thế chỉ đọc vẫn được hiển thị. Đăng nhập trong Cài đặt để bật thao tác.'
                  : 'Lệnh chờ vẫn được hiển thị. Đăng nhập trong Cài đặt để bật thao tác và tra cứu.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (sessionState.isLoading) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(minHeight: 2),
            ],
          ],
          if (sessionState.errorMessage != null && api.isConfigured) ...[
            const SizedBox(height: AppTokens.space1),
            Text(
              sessionState.errorMessage!,
              style: TextStyle(color: palette.negative, fontSize: 12),
            ),
          ],
          if (_busy && identical(_busyOwnerSession, session))
            const LinearProgressIndicator(minHeight: 2),
          if (hasUnresolvedOperation) ...[
            const SizedBox(height: AppTokens.space3),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(AppTokens.space3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      canShowOperationDetails
                          ? 'Thao tác cần tra cứu'
                          : 'Cần đăng nhập lại để tra cứu thao tác',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: AppTokens.space1),
                    if (canShowOperationDetails)
                      for (final operation in pendingOperations)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppTokens.space1,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (cancellationFlows.operationBelongsToSession(
                                operation,
                                session,
                              ))
                                Text(
                                  '${operation.targetLabel} · ${_actionLabel(operation.action)} · ${operation.status}\n${operation.operationId}',
                                  style: const TextStyle(fontSize: 12),
                                )
                              else
                                const Text(
                                  'Có thao tác cần tra cứu.',
                                  style: TextStyle(fontSize: 12),
                                ),
                              const SizedBox(height: AppTokens.space1),
                              Align(
                                alignment: Alignment.centerRight,
                                child: OutlinedButton(
                                  onPressed: _busy || !isAuthenticated
                                      ? null
                                      : () =>
                                            _lookupPendingOperation(operation),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppTokens.space2,
                                    ),
                                  ),
                                  child: const Text(
                                    'Tra cứu trạng thái',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    if (!canShowOperationDetails)
                      Text(
                        'Thao tác và trạng thái chỉ hiện khi đăng nhập đúng tài khoản đã gửi yêu cầu.',
                        style: TextStyle(color: palette.muted, fontSize: 12),
                      )
                    else if (hasUnresolvedOperation)
                      Text(
                        isAuthenticated
                            ? 'Các thao tác mới đang tạm khóa cho đến khi tra cứu xong.'
                            : 'Đăng nhập lại cùng tài khoản để tiếp tục tra cứu.',
                        style: TextStyle(color: palette.muted, fontSize: 12),
                      ),
                  ],
                ),
              ),
            ),
          ],
          if (_statusMessage != null &&
              identical(_statusOwnerSession, session)) ...[
            const SizedBox(height: 6),
            Semantics(
              liveRegion: true,
              child: Text(
                _statusMessage!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _closeAll() async {
    if (_busy) return;
    final state = ref.read(tradeSessionProvider);
    if (state.pendingOperations.isNotEmpty) {
      _setStatus(
        'Có thao tác chưa rõ kết quả. Tra cứu trạng thái trước khi gửi thao tác mới.',
      );
      return;
    }
    final session = state.session;
    if (session == null || !session.isActive) {
      ref.read(tradeSessionProvider.notifier).expire();
      _setStatus('Phiên giao dịch không hoạt động. Hãy đăng nhập lại.');
      return;
    }
    final actionFlows = ref.read(positionActionFlowsProvider.notifier);
    if (!actionFlows.tryAcquireAccountAction(session.accountIdentifier)) {
      _setStatus('Đang có thao tác khác trên tài khoản này.');
      return;
    }
    setState(() {
      _busy = true;
      _busyOwnerSession = session;
      _statusMessage = null;
      _statusOwnerSession = session;
    });
    try {
      // The private API intentionally receives no display filter here.
      final prepared = await ref
          .read(tradeApiProvider)
          .prepare(session.bearerToken, action: 'close_all');
      if (!_isCurrentSession(session)) return;
      final targetCount = prepared.summary['targetCount'];
      if (targetCount is! int || targetCount != prepared.targets.length) {
        ref.invalidate(tradePositionsProvider);
        _setStatus(
          'Danh sách đóng tất cả không đầy đủ; không có lệnh nào được gửi.',
          sessionOwner: session,
        );
        return;
      }
      if (targetCount == 0) {
        _setStatus(
          'Máy chủ không tìm thấy vị thế đủ điều kiện để đóng.',
          sessionOwner: session,
        );
        return;
      }

      final confirmed = await showTradeActionConfirmation(
        context,
        prepared: prepared,
        title: 'Xác nhận đóng tất cả vị thế',
        confirmLabel: 'Đóng $targetCount vị thế',
        destructive: true,
        accountWide: true,
        sessionOwner: session,
      );
      if (!confirmed || !_isCurrentSession(session)) return;

      final api = ref.read(tradeApiProvider);
      final sessionController = ref.read(tradeSessionProvider.notifier);
      if (!_isCurrentSession(session) ||
          ref.read(tradeSessionProvider).pendingOperations.isNotEmpty) {
        return;
      }
      sessionController.rememberOperation(
        PendingTradeOperation(
          operationId: prepared.operationId,
          action: 'close_all',
          targetLabel: '$targetCount vị thế',
          status: 'IN_PROGRESS',
        ),
      );
      var finalResult = TradeOperationResult(
        operationId: prepared.operationId,
        action: 'close_all',
        status: 'UNKNOWN',
        targets: const [],
        updatedAt: '',
      );
      String? lookupError;
      var lookupAttempted = false;
      try {
        finalResult = await api.execute(
          session.bearerToken,
          operationId: prepared.operationId,
          confirmationToken: prepared.confirmationToken,
        );
      } on TradeApiException catch (error) {
        if (error.isUnauthorized ||
            (error.statusCode != null && error.statusCode! < 500)) {
          if (_isCurrentSession(session)) {
            if (error.isUnauthorized) sessionController.expire();
            sessionController.resolveOperation(prepared.operationId);
          }
          rethrow;
        }
        try {
          lookupAttempted = true;
          finalResult = await api.getResult(
            session.bearerToken,
            prepared.operationId,
          );
        } on TradeApiException catch (lookupFailure) {
          lookupError = lookupFailure.message;
          if (lookupFailure.isUnauthorized && _isCurrentSession(session)) {
            ref.read(tradeSessionProvider.notifier).expire();
          }
        }
      }
      if (!lookupAttempted && tradeOperationNeedsStatusLookup(finalResult)) {
        lookupAttempted = true;
        try {
          finalResult = await api.getResult(
            session.bearerToken,
            finalResult.operationId,
          );
        } on TradeApiException catch (error) {
          lookupError ??= error.message;
          if (error.isUnauthorized && _isCurrentSession(session))
            ref.read(tradeSessionProvider.notifier).expire();
        }
      }
      if (!_isCurrentSession(session)) return;
      if (tradeOperationNeedsStatusLookup(finalResult)) {
        sessionController.updateOperation(
          PendingTradeOperation(
            operationId: finalResult.operationId,
            action: 'close_all',
            targetLabel: '$targetCount vị thế',
            status: finalResult.status,
          ),
        );
      } else {
        sessionController.resolveOperation(prepared.operationId);
      }
      ref.invalidate(tradePositionsProvider);
      _setStatus(
        _headline(
          finalResult.status,
          finalResult.operationId,
          action: finalResult.action,
        ),
        sessionOwner: session,
      );
      await _showResult(
        finalResult,
        sessionOwner: session,
        lookupError: lookupError,
      );
    } on TradeApiException catch (error) {
      if (error.isUnauthorized && _isCurrentSession(session))
        ref.read(tradeSessionProvider.notifier).expire();
      if (error.isStale || error.statusCode == 409) {
        ref.invalidate(tradePositionsProvider);
      }
      _setStatus(_formatError(error), sessionOwner: session);
    } catch (_) {
      _setStatus(
        'Chưa xác nhận được kết quả. Tra cứu trạng thái trước khi thao tác lại.',
        sessionOwner: session,
      );
    } finally {
      actionFlows.releaseAccountAction(session.accountIdentifier);
      if (mounted) {
        setState(() {
          _busy = false;
          _busyOwnerSession = null;
        });
      }
    }
  }

  Future<void> _lookupPendingOperation(PendingTradeOperation operation) async {
    if (_busy) return;
    final session = ref.read(tradeSessionProvider).session;
    final sessionState = ref.read(tradeSessionProvider);
    if (session == null || !session.isActive) {
      ref.read(tradeSessionProvider.notifier).expire();
      _setStatus(
        'Phiên giao dịch không hoạt động. Hãy đăng nhập lại.',
        sessionOwner: session,
      );
      return;
    }
    if (sessionState.operationAccountIdentifier != session.accountIdentifier ||
        !sessionState.pendingOperations.any(
          (pending) => pending.operationId == operation.operationId,
        )) {
      _setStatus(
        'Hãy đăng nhập đúng tài khoản để tra cứu thao tác này.',
        sessionOwner: session,
      );
      return;
    }
    setState(() {
      _busy = true;
      _busyOwnerSession = session;
      _statusMessage = null;
      _statusOwnerSession = session;
    });
    try {
      final result = await ref
          .read(tradeApiProvider)
          .getResult(session.bearerToken, operation.operationId);
      final currentSession = ref.read(tradeSessionProvider);
      if (!identical(currentSession.session, session) ||
          currentSession.session?.bearerToken != session.bearerToken ||
          currentSession.session?.accountIdentifier !=
              session.accountIdentifier ||
          !currentSession.isAuthenticated) {
        return;
      }
      if (result.operationId != operation.operationId ||
          result.action != operation.action) {
        _setStatus(
          'Kết quả tra cứu không khớp thao tác đã lưu; thao tác vẫn chờ xác minh.',
          sessionOwner: session,
        );
        return;
      }
      ref
          .read(orderCancellationFlowProvider.notifier)
          .associateOperationWithSession(operation.operationId, session);
      final controller = ref.read(tradeSessionProvider.notifier);
      if (tradeOperationNeedsStatusLookup(result)) {
        controller.updateOperation(
          PendingTradeOperation(
            operationId: result.operationId,
            action: operation.action,
            targetLabel: operation.targetLabel,
            status: result.status,
          ),
        );
      } else {
        controller.resolveOperation(operation.operationId);
      }
      ref.invalidate(tradePositionsProvider);
      ref.invalidate(ordersFutureProvider);
      await _showResult(result, sessionOwner: session);
      _setStatus(
        _headline(result.status, result.operationId, action: result.action),
        sessionOwner: session,
      );
    } on TradeApiException catch (error) {
      if (error.isUnauthorized && _isCurrentSession(session)) {
        ref.read(tradeSessionProvider.notifier).expire();
      }
      _setStatus(
        'Chưa tra cứu được ${operation.operationId}: ${error.message}',
        sessionOwner: session,
      );
    } catch (_) {
      _setStatus(
        'Chưa tra cứu được ${operation.operationId}. Hãy thử tra cứu lại sau.',
        sessionOwner: session,
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyOwnerSession = null;
        });
      }
    }
  }

  String _actionLabel(String action) => switch (action) {
    'add_margin' => 'Thêm ký quỹ',
    'dca' => 'DCA',
    'partial_close' => 'Đóng một phần',
    'close_position' => 'Đóng 100%',
    'close_all' => 'Đóng tất cả',
    'cancel_order' => 'Hủy lệnh limit',
    _ => action,
  };

  void _setStatus(String message, {TradeSession? sessionOwner}) {
    final currentSession = ref.read(tradeSessionProvider).session;
    final owner = sessionOwner ?? currentSession;
    if (!identical(currentSession, owner)) return;
    if (mounted) {
      setState(() {
        _statusMessage = message;
        _statusOwnerSession = owner;
      });
    }
  }

  bool _isCurrentSession(TradeSession expected) {
    final current = ref.read(tradeSessionProvider);
    return current.isAuthenticated &&
        identical(current.session, expected) &&
        expected.isActive;
  }

  String _formatError(TradeApiException error) {
    if (error.code != 'close_all_ineligible_targets') return error.message;
    final rawTargets = error.details['ineligibleTargets'];
    if (rawTargets is! List) return error.message;
    final blocked = rawTargets.whereType<Map>().map((target) {
      final identity = tradeJsonMap(target['identity']);
      final instrument = identity['instrumentId']?.toString() ?? 'Vị thế';
      final reason = target['reason']?.toString() ?? 'ineligible';
      return '$instrument: ${reason.replaceAll('_', ' ')}';
    });
    return [error.message, ...blocked].join('\n');
  }

  Future<void> _showResult(
    TradeOperationResult result, {
    required TradeSession sessionOwner,
    String? lookupError,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _TradeOperationResultDialog(
        result: result,
        lookupError: lookupError,
        sessionOwner: sessionOwner,
        targetOutcome: _targetOutcome,
        headline: _headline,
      ),
    );
  }

  Widget _targetOutcome(Map<String, dynamic> target) {
    final identity = tradeJsonMap(target['identity']);
    final outcome = tradeJsonMap(target['outcome']);
    if (identity['ordId'] != null) {
      final instrument = identity['instId']?.toString() ?? 'Lệnh';
      final orderId = identity['ordId']?.toString() ?? '--';
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$instrument · ${target['status']?.toString().toUpperCase() ?? 'UNKNOWN'}',
            ),
            Text('Mã lệnh: $orderId'),
            Text(
              'Giá: ${_cancelValue(target, outcome, 'price', identity['px'])} · '
              'Tổng khối lượng: ${_cancelValue(target, outcome, 'originalSize', identity['sz'])}',
            ),
            Text(
              'Đã khớp: ${_cancelValue(target, outcome, 'filledSize')} · '
              'Còn lại: ${_cancelValue(target, outcome, 'remainingSize')}',
            ),
            if (outcome['reason'] != null)
              Text(
                'Lý do: ${outcome['reason'].toString().replaceAll('_', ' ')}',
              ),
          ],
        ),
      );
    }
    final instrument = identity['instrumentId']?.toString() ?? 'Vị thế';
    final status = target['status']?.toString().toUpperCase() ?? 'UNKNOWN';
    final reason = outcome['reason']?.toString();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        '$instrument: $status${reason == null ? '' : ' · ${reason.replaceAll('_', ' ')}'}',
      ),
    );
  }

  String _cancelValue(
    Map<String, dynamic> target,
    Map<String, dynamic> outcome,
    String key, [
    Object? fallback,
  ]) => (target[key] ?? outcome[key] ?? fallback)?.toString() ?? '--';

  String _headline(String status, String operationId, {String? action}) =>
      switch (status) {
        'SUCCEEDED' => switch (action) {
          'close_all' => 'Đã hoàn tất đóng tất cả vị thế',
          'cancel_order' => 'Đã hủy lệnh limit',
          _ => 'Đã hoàn tất thao tác',
        },
        'PARTIAL' =>
          action == 'cancel_order'
              ? 'Lệnh đã khớp một phần trước khi hủy'
              : action == 'close_all'
              ? 'Kết quả đóng một phần'
              : 'Thao tác chỉ hoàn tất một phần',
        'UNKNOWN' =>
          action == 'cancel_order'
              ? 'Chưa rõ kết quả hủy lệnh'
              : action == 'close_all'
              ? 'Chưa rõ kết quả đóng tất cả'
              : 'Chưa rõ kết quả thao tác',
        'CONFLICT' => 'Danh sách vị thế đã thay đổi',
        'FAILED' => switch (action) {
          'close_all' => 'Đóng tất cả thất bại',
          'cancel_order' => 'Hủy lệnh limit thất bại',
          _ => 'Thao tác thất bại',
        },
        'EXPIRED' => 'Xác nhận đã hết hạn',
        _ => 'Trạng thái $status · $operationId',
      };
}

class _TradeOperationResultDialog extends ConsumerWidget {
  const _TradeOperationResultDialog({
    required this.result,
    required this.lookupError,
    required this.sessionOwner,
    required this.targetOutcome,
    required this.headline,
  });

  final TradeOperationResult result;
  final String? lookupError;
  final TradeSession sessionOwner;
  final Widget Function(Map<String, dynamic>) targetOutcome;
  final String Function(String, String, {String? action}) headline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSession = ref.watch(tradeSessionProvider).session;
    final ownsResult = identical(currentSession, sessionOwner);
    return AlertDialog(
      title: Text(
        ownsResult
            ? headline(result.status, result.operationId, action: result.action)
            : 'Phiên giao dịch đã thay đổi',
      ),
      content: SizedBox(
        width: 420,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: ownsResult
              ? ListView(
                  shrinkWrap: true,
                  children: [
                    Text('Mã thao tác: ${result.operationId}'),
                    for (final target in result.targets) targetOutcome(target),
                    if (lookupError != null)
                      Text('Lỗi tra cứu trạng thái: $lookupError'),
                  ],
                )
              : const Text('Nội dung thao tác đã được ẩn.'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Đóng'),
        ),
      ],
    );
  }
}

class TradeSessionControls extends ConsumerStatefulWidget {
  const TradeSessionControls({super.key});

  @override
  ConsumerState<TradeSessionControls> createState() =>
      _TradeSessionControlsState();
}

class _TradeSessionControlsState extends ConsumerState<TradeSessionControls> {
  bool _busy = false;
  bool _logoutPending = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final api = ref.watch(tradeApiProvider);
    final sessionState = ref.watch(tradeSessionProvider);
    final session = sessionState.session;
    final isAuthenticated = sessionState.isAuthenticated;
    final hasActiveSession = (session?.isActive ?? false) || _logoutPending;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Giao dịch riêng tư',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (hasActiveSession)
                  TextButton(
                    onPressed: _busy || sessionState.isLoading ? null : _logout,
                    child: const Text('Đăng xuất'),
                  )
                else if (api.isConfigured)
                  FilledButton.tonal(
                    onPressed: _busy || sessionState.isLoading ? null : _login,
                    child: const Text('Đăng nhập'),
                  ),
              ],
            ),
            if (!api.isConfigured)
              const Text(
                'Chưa cấu hình API giao dịch. Vị thế vẫn chỉ đọc; thao tác riêng tư đang tắt.',
                style: TextStyle(fontSize: 12),
              )
            else if (session?.isActive ?? false) ...[
              Text(
                'Đã đăng nhập: ${session!.accountIdentifier.isNotEmpty ? session.accountIdentifier : '••••'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Phiên hết hạn: ${session.expiresAt.toLocal()}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else ...[
              Text(
                _logoutPending
                    ? 'Đang kết thúc phiên giao dịch…'
                    : sessionState.isLoading
                    ? 'Đang khôi phục phiên giao dịch…'
                    : 'Đăng nhập bằng mật khẩu và mã TOTP để bật thao tác.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (sessionState.isLoading) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(minHeight: 2),
              ],
            ],
            if (sessionState.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                sessionState.errorMessage!,
                style: TextStyle(color: palette.negative, fontSize: 12),
              ),
            ],
            if (api.supportsSessionRestoration &&
                !isAuthenticated &&
                !sessionState.isLoading &&
                sessionState.errorMessage != null) ...[
              const SizedBox(height: AppTokens.space2),
              OutlinedButton(
                onPressed: _busy ? null : _restore,
                child: const Text('Thử khôi phục phiên'),
              ),
            ],
            if (_busy) const LinearProgressIndicator(minHeight: 2),
          ],
        ),
      ),
    );
  }

  Future<void> _login() async {
    final credentials = await showDialog<_TradeCredentials>(
      context: context,
      builder: (context) => const _TradeLoginDialog(),
    );
    if (credentials == null || !mounted) return;
    setState(() => _busy = true);
    final loggedIn = await ref
        .read(tradeSessionProvider.notifier)
        .login(password: credentials.password, totp: credentials.totp);
    if (!mounted) return;
    if (loggedIn) ref.invalidate(tradePositionsProvider);
    setState(() => _busy = false);
  }

  Future<void> _logout() async {
    setState(() {
      _busy = true;
      _logoutPending = true;
    });
    final loggedOut = await ref.read(tradeSessionProvider.notifier).logout();
    if (!mounted) return;
    if (loggedOut) ref.invalidate(tradePositionsProvider);
    setState(() {
      _busy = false;
      _logoutPending = false;
    });
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    final restored = await ref.read(tradeSessionProvider.notifier).restore();
    if (!mounted) return;
    if (restored) ref.invalidate(tradePositionsProvider);
    setState(() => _busy = false);
  }
}

class _TradeCredentials {
  const _TradeCredentials(this.password, this.totp);

  final String password;
  final String totp;
}

class _TradeLoginDialog extends StatefulWidget {
  const _TradeLoginDialog();

  @override
  State<_TradeLoginDialog> createState() => _TradeLoginDialogState();
}

class _TradeLoginDialogState extends State<_TradeLoginDialog> {
  final _passwordController = TextEditingController();
  final _totpController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _totpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Đăng nhập API giao dịch'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _passwordController,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(labelText: 'Mật khẩu'),
          ),
          TextField(
            controller: _totpController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Mã TOTP gồm 6 chữ số',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: AppPalette.of(context).negative),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Đăng nhập')),
      ],
    );
  }

  void _submit() {
    final password = _passwordController.text;
    final totp = _totpController.text.trim();
    if (password.isEmpty || !RegExp(r'^\d{6}$').hasMatch(totp)) {
      setState(() => _error = 'Nhập mật khẩu và mã TOTP gồm đúng 6 chữ số.');
      return;
    }
    _passwordController.clear();
    _totpController.clear();
    Navigator.of(context).pop(_TradeCredentials(password, totp));
  }
}
