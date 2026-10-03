import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../orders/presentation/providers/trade_session_provider.dart';
import '../domain/strategy_models.dart';
import 'providers/strategy_dashboard_provider.dart';

class StrategySettingsDialog extends ConsumerStatefulWidget {
  const StrategySettingsDialog({
    super.key,
    required this.bearerToken,
    required this.dashboard,
  });

  final String? bearerToken;
  final StrategyDashboardController? dashboard;

  @override
  ConsumerState<StrategySettingsDialog> createState() =>
      _StrategySettingsDialogState();
}

class _StrategySettingsDialogState
    extends ConsumerState<StrategySettingsDialog> {
  String? _draftMode;
  bool _draftWasEdited = false;
  bool _savedAcknowledgement = false;

  @override
  void initState() {
    super.initState();
    final dashboard = widget.dashboard;
    if (dashboard != null && widget.bearerToken != null) {
      unawaited(dashboard.loadStrategySettings());
    }
  }

  bool _sessionMatches(TradeSessionState state) {
    final expectedToken = widget.bearerToken;
    if (expectedToken == null) {
      return !state.isAuthenticated && state.session == null;
    }
    return state.isAuthenticated &&
        state.session?.bearerToken == expectedToken &&
        (widget.dashboard?.ownsSession ?? false);
  }

  Future<void> _save(String? mode) async {
    final dashboard = widget.dashboard;
    if (dashboard == null ||
        mode == null ||
        !_sessionMatches(ref.read(tradeSessionProvider))) {
      return;
    }
    final saved = await dashboard.saveLimitOrderSubmissionMode(mode);
    if (!mounted || !_sessionMatches(ref.read(tradeSessionProvider))) return;
    if (saved) {
      setState(() {
        _draftWasEdited = false;
        _draftMode = mode;
        _savedAcknowledgement = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionState = ref.watch(tradeSessionProvider);
    final sessionMatches = _sessionMatches(sessionState);
    final dashboard = widget.dashboard;
    final width = MediaQuery.sizeOf(context).width;
    final height = MediaQuery.sizeOf(context).height;

    Widget content() {
      final selectedMode = _draftWasEdited
          ? _draftMode
          : dashboard?.limitOrderSubmissionMode;
      final mode = StrategyLimitOrderSubmissionMode.parse(selectedMode);
      final authenticated = widget.bearerToken != null && sessionMatches;
      final canSave =
          authenticated &&
          dashboard != null &&
          mode != null &&
          !dashboard.settingsIsLoading &&
          !dashboard.settingsIsSaving;

      return Dialog(
        key: const Key('strategy-settings-dialog'),
        insetPadding: EdgeInsets.symmetric(
          horizontal: width < 600 ? 10 : 28,
          vertical: 16,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 620, maxHeight: height * 0.9),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Cài đặt chiến thuật',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Đóng',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Column(
                    children: [
                      if (widget.bearerToken == null)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'Đăng nhập phiên giao dịch để xem và lưu cơ chế gửi lệnh limit.',
                          ),
                        )
                      else if (!sessionMatches)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'Phiên giao dịch đã thay đổi. Hãy đóng cửa sổ này và mở lại trong phiên hiện tại.',
                          ),
                        )
                      else if (dashboard == null)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('Cài đặt chưa sẵn sàng cho phiên này.'),
                        )
                      else ...[
                        if (dashboard.settingsIsLoading && mode == null)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(),
                          ),
                        if (dashboard.settingsError != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    dashboard.settingsError!,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: dashboard.settingsIsLoading
                                      ? null
                                      : () => unawaited(
                                          dashboard.loadStrategySettings(
                                            force: true,
                                          ),
                                        ),
                                  child: const Text('Thử lại'),
                                ),
                              ],
                            ),
                          ),
                        ExpansionTile(
                          key: const Key('strategy-settings-submission-mode'),
                          initiallyExpanded: true,
                          title: const Text('Cơ chế gửi lệnh limit'),
                          children: [
                            RadioGroup<String>(
                              key: const Key('strategy-settings-mode-group'),
                              groupValue: selectedMode,
                              onChanged: (value) {
                                if (!sessionMatches ||
                                    dashboard.settingsIsSaving ||
                                    value == null) {
                                  return;
                                }
                                setState(() {
                                  _draftMode = value;
                                  _draftWasEdited = true;
                                  _savedAcknowledgement = false;
                                });
                              },
                              child: Column(
                                children: [
                                  RadioListTile<String>(
                                    key: const Key(
                                      'strategy-settings-sequential',
                                    ),
                                    enabled:
                                        sessionMatches &&
                                        !dashboard.settingsIsSaving,
                                    value: 'sequential',
                                    title: const Text('Hàng đợi tuần tự'),
                                    subtitle: const Text(
                                      'Lệnh tiếp theo được gửi sau khi máy chủ xác nhận lệnh trước đã được nhận, không phải sau khi lệnh khớp.',
                                    ),
                                  ),
                                  RadioListTile<String>(
                                    key: const Key('strategy-settings-batch'),
                                    enabled:
                                        sessionMatches &&
                                        !dashboard.settingsIsSaving,
                                    value: 'batch',
                                    title: const Text('Gửi theo lô'),
                                    subtitle: const Text(
                                      'Các lệnh đã duyệt được gửi cùng nhau theo cơ chế gửi theo lô.',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (_savedAcknowledgement)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text('Máy chủ đã xác nhận lưu cài đặt.'),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      key: const Key('strategy-settings-cancel'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Hủy'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const Key('strategy-settings-save'),
                      onPressed: canSave
                          ? () => unawaited(_save(mode.wireValue))
                          : null,
                      child: dashboard?.settingsIsSaving == true
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Lưu'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (dashboard == null) return content();
    return AnimatedBuilder(
      animation: dashboard,
      builder: (context, _) => content(),
    );
  }
}
