import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/responsive_form_content.dart';
import '../../orders/presentation/providers/trade_session_provider.dart';
import '../domain/strategy_models.dart';
import '../domain/strategy_settings.dart';
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
  final _entrySuitabilityController = TextEditingController();
  final _failureRiskController = TextEditingController();
  String? _draftMode;
  int? _draftQuality;
  StrategySettings? _draftSettingsBaseline;
  bool _draftWasEdited = false;
  bool _qualityWasEdited = false;
  bool _entrySuitabilityWasEdited = false;
  bool _failureRiskWasEdited = false;
  bool _savedAcknowledgement = false;

  @override
  void initState() {
    super.initState();
    final dashboard = widget.dashboard;
    _syncFromDashboard(notify: false);
    dashboard?.addListener(_syncFromDashboard);
    if (dashboard != null && widget.bearerToken != null) {
      unawaited(dashboard.loadStrategySettings());
    }
  }

  @override
  void didUpdateWidget(covariant StrategySettingsDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dashboard != widget.dashboard) {
      oldWidget.dashboard?.removeListener(_syncFromDashboard);
      widget.dashboard?.addListener(_syncFromDashboard);
      _draftWasEdited = false;
      _syncFromDashboard(notify: false);
      if (widget.dashboard != null && widget.bearerToken != null) {
        unawaited(widget.dashboard!.loadStrategySettings());
      }
    }
  }

  @override
  void dispose() {
    widget.dashboard?.removeListener(_syncFromDashboard);
    _entrySuitabilityController.dispose();
    _failureRiskController.dispose();
    super.dispose();
  }

  void _syncFromDashboard({bool notify = true}) {
    final dashboard = widget.dashboard;
    if ((notify && !mounted) ||
        dashboard == null ||
        _draftWasEdited ||
        !dashboard.settingsLoaded) {
      return;
    }
    final settings = dashboard.strategySettings;
    void synchronize() {
      _draftSettingsBaseline = settings;
      _draftMode = dashboard.limitOrderSubmissionMode;
      _draftQuality = settings?.jevScreeningThresholds.minStructuralQuality;
      _qualityWasEdited = false;
      _entrySuitabilityWasEdited = false;
      _failureRiskWasEdited = false;
      _entrySuitabilityController.text = settings == null
          ? ''
          : _probabilityAsPercentText(
              settings.jevScreeningThresholds.minEntrySuitabilityProbability,
            );
      _failureRiskController.text = settings == null
          ? ''
          : _probabilityAsPercentText(
              settings.jevScreeningThresholds.maxFailureRiskProbability,
            );
    }

    if (notify) {
      setState(synchronize);
    } else {
      synchronize();
    }
  }

  String _probabilityAsPercentText(double probability) {
    final text = probability.toString();
    final exponentAt = text.indexOf(RegExp('[eE]'));
    if (exponentAt >= 0) {
      return _expandScientific(text, decimalShift: 2);
    }
    final parts = text.split('.');
    if (parts.first == '1') return '100';
    final fractional = (parts.length == 1 ? '' : parts.last).padRight(2, '0');
    final whole = fractional.substring(0, 2);
    final remainder = fractional.substring(2);
    final percent = remainder.isEmpty ? whole : '$whole.$remainder';
    final normalized = percent.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (!normalized.contains('.')) return normalized;
    return normalized
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  String _expandScientific(String value, {int decimalShift = 0}) {
    final parts = value.toLowerCase().split('e');
    if (parts.length != 2) return value;
    final parsedExponent = int.tryParse(parts[1]);
    if (parsedExponent == null) return value;
    final exponent = parsedExponent + decimalShift;
    final mantissaParts = parts[0].split('.');
    final digits = mantissaParts.join();
    final decimalPosition = mantissaParts.first.length + exponent;
    if (decimalPosition <= 0) {
      return '0.${List.filled(-decimalPosition, '0').join()}$digits';
    }
    if (decimalPosition >= digits.length) {
      return '$digits${List.filled(decimalPosition - digits.length, '0').join()}';
    }
    return '${digits.substring(0, decimalPosition)}.${digits.substring(decimalPosition)}';
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

  void _markDraftEdited() {
    setState(() {
      _draftWasEdited = true;
      _savedAcknowledgement = false;
    });
  }

  void _resetJevDefaults() {
    setState(() {
      _draftWasEdited = true;
      _qualityWasEdited = true;
      _entrySuitabilityWasEdited = true;
      _failureRiskWasEdited = true;
      _draftQuality =
          StrategyJevScreeningThresholds.defaults.minStructuralQuality;
      _entrySuitabilityController.text = '60';
      _failureRiskController.text = '40';
      _savedAcknowledgement = false;
    });
  }

  StrategyJevScreeningThresholds? _editedThresholds() {
    final saved = _draftSettingsBaseline?.jevScreeningThresholds;
    final quality = _qualityWasEdited
        ? _draftQuality
        : saved?.minStructuralQuality;
    final suitabilityPercent = _entrySuitabilityWasEdited
        ? StrategyJevScreeningThresholds.parsePercentage(
            _entrySuitabilityController.text,
          )
        : null;
    final failureRiskPercent = _failureRiskWasEdited
        ? StrategyJevScreeningThresholds.parsePercentage(
            _failureRiskController.text,
          )
        : null;
    if (quality == null ||
        (_entrySuitabilityWasEdited && suitabilityPercent == null) ||
        (_failureRiskWasEdited && failureRiskPercent == null)) {
      return null;
    }
    final savedSuitability = saved?.minEntrySuitabilityProbability;
    final savedFailureRisk = saved?.maxFailureRiskProbability;
    if ((!_entrySuitabilityWasEdited && savedSuitability == null) ||
        (!_failureRiskWasEdited && savedFailureRisk == null)) {
      return null;
    }
    final thresholds = StrategyJevScreeningThresholds(
      minStructuralQuality: quality,
      minEntrySuitabilityProbability: _entrySuitabilityWasEdited
          ? suitabilityPercent! / 100
          : savedSuitability!,
      maxFailureRiskProbability: _failureRiskWasEdited
          ? failureRiskPercent! / 100
          : savedFailureRisk!,
    );
    return thresholds.isValid ? thresholds : null;
  }

  Future<void> _save({
    required String? mode,
    required StrategyJevScreeningThresholds? thresholds,
  }) async {
    final dashboard = widget.dashboard;
    if (dashboard == null ||
        mode == null ||
        !_sessionMatches(ref.read(tradeSessionProvider))) {
      return;
    }
    final fullSettings = dashboard.supportsFullStrategySettings;
    final saved = fullSettings
        ? thresholds != null &&
              await dashboard.saveStrategySettings(
                StrategySettings(
                  limitOrderSubmissionMode: mode,
                  jevScreeningThresholds: thresholds,
                ),
              )
        : await dashboard.saveLimitOrderSubmissionMode(mode);
    if (!mounted || !_sessionMatches(ref.read(tradeSessionProvider))) return;
    if (saved) {
      setState(() {
        _draftWasEdited = false;
        _draftMode = mode;
        if (thresholds != null) {
          _draftSettingsBaseline = StrategySettings(
            limitOrderSubmissionMode: mode,
            jevScreeningThresholds: thresholds,
          );
          _draftQuality = thresholds.minStructuralQuality;
          _qualityWasEdited = false;
          _entrySuitabilityWasEdited = false;
          _failureRiskWasEdited = false;
          _entrySuitabilityController.text = _probabilityAsPercentText(
            thresholds.minEntrySuitabilityProbability,
          );
          _failureRiskController.text = _probabilityAsPercentText(
            thresholds.maxFailureRiskProbability,
          );
        }
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
      final fullCapability = dashboard?.supportsFullStrategySettings == true;
      final thresholds = fullCapability
          ? (_draftWasEdited
                ? _editedThresholds()
                : dashboard?.strategySettings?.jevScreeningThresholds)
          : null;
      final authenticated = widget.bearerToken != null && sessionMatches;
      final controlsEnabled =
          authenticated &&
          dashboard != null &&
          dashboard.settingsLoaded &&
          !dashboard.settingsIsLoading &&
          !dashboard.settingsIsSaving;
      final canSave =
          controlsEnabled &&
          mode != null &&
          (!fullCapability || thresholds != null);

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
                  child: ResponsiveFormContent(
                    maxWidth: 588,
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        if (widget.bearerToken == null)
                          const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text(
                              'Đăng nhập phiên giao dịch để xem và lưu cài đặt chiến thuật.',
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
                          if (dashboard.settingsIsLoading &&
                              !dashboard.settingsLoaded)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: FormPendingStatus(
                                label: 'Đang tải cài đặt chiến thuật…',
                                linear: false,
                              ),
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
                                    onPressed:
                                        dashboard.settingsIsLoading ||
                                            dashboard.settingsIsSaving
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
                                  if (!controlsEnabled || value == null) return;
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
                                      enabled: controlsEnabled,
                                      value: 'sequential',
                                      title: const Text('Hàng đợi tuần tự'),
                                      subtitle: const Text(
                                        'Lệnh tiếp theo được gửi sau khi máy chủ xác nhận lệnh trước đã được nhận, không phải sau khi lệnh khớp.',
                                      ),
                                    ),
                                    RadioListTile<String>(
                                      key: const Key('strategy-settings-batch'),
                                      enabled: controlsEnabled,
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
                          ExpansionTile(
                            key: const Key('strategy-settings-jev-screening'),
                            initiallyExpanded: true,
                            title: const Text('Sàng lọc JEV'),
                            children: [
                              if (!fullCapability)
                                const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Text(
                                    'Cài đặt sàng lọc JEV chưa khả dụng trên API của phiên này.',
                                  ),
                                )
                              else ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    4,
                                    16,
                                    8,
                                  ),
                                  child: InputDecorator(
                                    decoration: const InputDecoration(
                                      labelText:
                                          'Chất lượng cấu trúc tối thiểu',
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<int>(
                                        key: const Key(
                                          'strategy-settings-min-structural-quality',
                                        ),
                                        isExpanded: true,
                                        value: _draftWasEdited
                                            ? _draftQuality
                                            : dashboard
                                                  .strategySettings
                                                  ?.jevScreeningThresholds
                                                  .minStructuralQuality,
                                        hint: const Text('Chọn mức chất lượng'),
                                        items: [
                                          for (
                                            var quality = 0;
                                            quality <= 5;
                                            quality++
                                          )
                                            DropdownMenuItem(
                                              value: quality,
                                              child: Text('$quality'),
                                            ),
                                        ],
                                        onChanged: controlsEnabled
                                            ? (value) {
                                                setState(() {
                                                  _draftQuality = value;
                                                  _draftWasEdited = true;
                                                  _qualityWasEdited = true;
                                                  _savedAcknowledgement = false;
                                                });
                                              }
                                            : null,
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    4,
                                    16,
                                    8,
                                  ),
                                  child: TextField(
                                    key: const Key(
                                      'strategy-settings-entry-suitability-percent',
                                    ),
                                    controller: _entrySuitabilityController,
                                    enabled: controlsEnabled,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'Khả năng phù hợp tối thiểu',
                                      suffixText: '%',
                                    ),
                                    onChanged: (_) {
                                      _entrySuitabilityWasEdited = true;
                                      _markDraftEdited();
                                    },
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    4,
                                    16,
                                    8,
                                  ),
                                  child: TextField(
                                    key: const Key(
                                      'strategy-settings-failure-risk-percent',
                                    ),
                                    controller: _failureRiskController,
                                    enabled: controlsEnabled,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'Rủi ro thất bại tối đa',
                                      suffixText: '%',
                                    ),
                                    onChanged: (_) {
                                      _failureRiskWasEdited = true;
                                      _markDraftEdited();
                                    },
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    8,
                                    8,
                                  ),
                                  child: Row(
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          'Chỉ áp dụng cho bản nháp tạo mới. Tối đa 5 mức mỗi phía; ứng viên cần được đánh giá thành công.',
                                        ),
                                      ),
                                      TextButton(
                                        key: const Key(
                                          'strategy-settings-jev-reset',
                                        ),
                                        onPressed: controlsEnabled
                                            ? _resetJevDefaults
                                            : null,
                                        child: const Text('Mặc định'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
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
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      key: const Key('strategy-settings-cancel'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Hủy'),
                    ),
                    AsyncFormButton(
                      key: const Key('strategy-settings-save'),
                      onPressed: canSave
                          ? () => unawaited(
                              _save(
                                mode: mode.wireValue,
                                thresholds: thresholds,
                              ),
                            )
                          : null,
                      label: 'Lưu',
                      busyLabel: 'Đang lưu cài đặt…',
                      isBusy: dashboard?.settingsIsSaving == true,
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
