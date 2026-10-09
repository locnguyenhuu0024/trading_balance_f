import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/responsive_form_content.dart';
import '../../orders/data/trade_api_client.dart';
import '../../orders/presentation/providers/trade_session_provider.dart';
import '../data/strategy_api_client.dart';
import '../data/strategy_market_repository.dart';
import '../domain/strategy_models.dart';
import 'providers/strategy_dashboard_provider.dart';

enum _AutomaticDirection {
  long('long', 'Long'),
  short('short', 'Short'),
  both('both', 'Long&Short');

  const _AutomaticDirection(this.value, this.label);

  final String value;
  final String label;
}

class StrategyAutomaticDraftDialog extends ConsumerStatefulWidget {
  const StrategyAutomaticDraftDialog({
    super.key,
    required this.session,
    required this.dashboard,
  });

  final TradeSession session;
  final StrategyDashboardController dashboard;

  @override
  ConsumerState<StrategyAutomaticDraftDialog> createState() =>
      _StrategyAutomaticDraftDialogState();
}

class _StrategyAutomaticDraftDialogState
    extends ConsumerState<StrategyAutomaticDraftDialog> {
  List<StrategyInstrument> _instruments = const [];
  String? _instrumentId;
  StrategyInterval? _interval;
  _AutomaticDirection _direction = _AutomaticDirection.both;
  String? _requestId;
  String? _error;
  bool _isLoading = true;
  bool _isGenerating = false;
  bool _sessionDismissScheduled = false;
  int _loadGeneration = 0;

  StrategyMarketRepository get _market =>
      ref.read(strategyMarketRepositoryProvider);

  bool get _isSessionCurrent {
    if (!mounted) return false;
    final state = ref.read(tradeSessionProvider);
    return state.isAuthenticated &&
        state.session?.bearerToken == widget.session.bearerToken &&
        widget.dashboard.ownsSession;
  }

  bool get _canGenerate =>
      _isSessionCurrent &&
      !_isLoading &&
      !_isGenerating &&
      _instrumentId != null &&
      _interval != null;

  @override
  void initState() {
    super.initState();
    _loadInstruments();
  }

  Future<void> _loadInstruments() async {
    final generation = ++_loadGeneration;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final instruments = await _market.getInstruments();
      if (!mounted || generation != _loadGeneration || !_isSessionCurrent) {
        return;
      }
      setState(() {
        _instruments = instruments;
        _isLoading = false;
        if (instruments.isEmpty) {
          _error = 'Không tìm thấy hợp đồng USDT SWAP đang giao dịch.';
        }
      });
    } on Object catch (error) {
      if (!mounted || generation != _loadGeneration || !_isSessionCurrent) {
        return;
      }
      setState(() {
        _isLoading = false;
        _error = _safeError(error);
      });
    }
  }

  Future<void> _pickInstrument() async {
    if (_isLoading || _isGenerating || !_isSessionCurrent) return;
    final instrumentId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AutomaticInstrumentPicker(instruments: _instruments),
    );
    if (!mounted ||
        !_isSessionCurrent ||
        instrumentId == null ||
        instrumentId == _instrumentId) {
      return;
    }
    setState(() {
      _instrumentId = instrumentId;
      _requestId = null;
      _error = null;
    });
  }

  void _selectInterval(StrategyInterval? value) {
    if (value == null || value == _interval) return;
    setState(() {
      _interval = value;
      _requestId = null;
      _error = null;
    });
  }

  void _selectDirection(_AutomaticDirection? value) {
    if (value == null || value == _direction) return;
    setState(() {
      _direction = value;
      _requestId = null;
      _error = null;
    });
  }

  Future<void> _createCandidates() async {
    if (!_canGenerate) return;
    final api = ref.read(strategyApiProvider);
    if (api is! AutomaticStrategyApi) {
      setState(() {
        _error = 'Máy chủ hiện chưa hỗ trợ dựng chiến thuật tự động.';
      });
      return;
    }
    final automaticApi = api as AutomaticStrategyApi;

    final instrumentId = _instrumentId!;
    final interval = _interval!;
    final requestId = _requestId ??= _newRequestId();
    setState(() {
      _isGenerating = true;
      _error = null;
    });
    try {
      final response = await automaticApi.createAutomaticDrafts(
        widget.session.bearerToken,
        instrumentId: instrumentId,
        interval: interval.bar,
        requestId: requestId,
        direction: _direction.value,
      );
      if (!mounted || !_isSessionCurrent) return;
      final draft = _candidateDraft(response);
      final generation = _asStringMap(draft?['aiGeneration']);
      final returnedDirection = _text(generation?['direction']);
      final hasReturnedDirection =
          generation?.containsKey('direction') ?? false;
      if (draft == null ||
          draft['instrumentId'] != instrumentId ||
          draft['interval'] != interval.bar ||
          _text(_asStringMap(draft['aiGeneration'])?['requestId']) !=
              requestId ||
          (!hasReturnedDirection && _direction != _AutomaticDirection.both) ||
          (hasReturnedDirection && returnedDirection != _direction.value)) {
        throw const StrategyApiException(
          code: 'invalid_response',
          message: 'Máy chủ trả về bản xem xét chiến thuật không hợp lệ.',
        );
      }
      Navigator.of(context).pop(draft);
    } on StrategyApiException catch (error) {
      if (!mounted || !_isSessionCurrent) return;
      if (error.isUnauthorized) {
        ref.read(tradeSessionProvider.notifier).expire();
      }
      setState(() {
        _isGenerating = false;
        _error = error.message;
      });
    } on Object catch (error) {
      if (!mounted || !_isSessionCurrent) return;
      setState(() {
        _isGenerating = false;
        _error = _safeError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(tradeSessionProvider);
    ref.listen(tradeSessionProvider, (previous, next) {
      if (!next.isAuthenticated ||
          next.session?.bearerToken != widget.session.bearerToken) {
        _dismissForSessionChange();
      }
    });
    final width = MediaQuery.sizeOf(context).width;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: width < 600 ? 8 : 28,
        vertical: 18,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Dựng chiến thuật tự động',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    key: const Key('strategy-automatic-close'),
                    tooltip: 'Đóng',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ResponsiveFormContent(
                  maxWidth: 560,
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InkWell(
                        key: const Key('strategy-automatic-instrument-picker'),
                        onTap: _isLoading || _isGenerating || !_isSessionCurrent
                            ? null
                            : _pickInstrument,
                        borderRadius: BorderRadius.circular(4),
                        child: InputDecorator(
                          isEmpty: _instrumentId == null,
                          decoration: InputDecoration(
                            labelText: 'Hợp đồng USDT SWAP',
                            floatingLabelBehavior: FloatingLabelBehavior.always,
                            enabled:
                                !_isLoading &&
                                !_isGenerating &&
                                _isSessionCurrent,
                            suffixIcon: const Icon(Icons.search),
                          ),
                          child: Text(_instrumentId ?? 'Chọn coin'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<StrategyInterval>(
                        key: const Key('strategy-automatic-interval-select'),
                        initialValue: _interval,
                        decoration: const InputDecoration(
                          labelText: 'Khung nến UTC',
                        ),
                        items:
                            const [
                                  StrategyInterval.h6,
                                  StrategyInterval.d1,
                                  StrategyInterval.w1,
                                ]
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(value.label),
                                  ),
                                )
                                .toList(growable: false),
                        onChanged:
                            _isLoading || _isGenerating || !_isSessionCurrent
                            ? null
                            : _selectInterval,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<_AutomaticDirection>(
                        isExpanded: true,
                        key: const Key('strategy-automatic-direction-select'),
                        initialValue: _direction,
                        decoration: const InputDecoration(
                          labelText: 'Phía giao dịch',
                        ),
                        items: _AutomaticDirection.values
                            .map(
                              (direction) => DropdownMenuItem(
                                value: direction,
                                child: Text(direction.label),
                              ),
                            )
                            .toList(growable: false),
                        onChanged:
                            _isLoading || _isGenerating || !_isSessionCurrent
                            ? null
                            : _selectDirection,
                      ),
                      if (_isLoading) ...[
                        const SizedBox(height: 16),
                        const FormPendingStatus(
                          label: 'Đang tải danh sách hợp đồng…',
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Card(
                          color: Theme.of(context).colorScheme.errorContainer,
                          child: ListTile(
                            dense: true,
                            leading: const Icon(Icons.warning_amber),
                            title: Text(_error!),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      const Text(
                        'Không tạo hoặc gửi lệnh ở bước này. Bản nháp sẽ tự lưu sau khi tạo; đề xuất Jev chọn tối đa 5 mức cho mỗi phía, không bù phần thiếu. Bạn có thể sửa lựa chọn khi xem lại.',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: _isGenerating
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Hủy'),
                  ),
                  AsyncFormButton(
                    key: const Key('strategy-automatic-generate'),
                    onPressed: _canGenerate ? _createCandidates : null,
                    isBusy: _isGenerating,
                    label: 'Tạo ứng viên',
                    busyLabel: 'Đang dựng…',
                    icon: Icons.auto_awesome_outlined,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _dismissForSessionChange() {
    if (_sessionDismissScheduled) return;
    _sessionDismissScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isSessionCurrent) {
        Navigator.of(context).maybePop();
      }
    });
  }

  Map<String, dynamic>? _candidateDraft(Map<String, dynamic> response) {
    final nested =
        _asStringMap(response['strategy']) ?? _asStringMap(response['draft']);
    final draft = nested ?? response;
    final snapshot = _asStringMap(draft['snapshot']);
    final hasTopGeneration = draft.containsKey('aiGeneration');
    if ((hasTopGeneration && draft['aiGeneration'] is! Map) ||
        (!hasTopGeneration &&
            snapshot?.containsKey('aiGeneration') == true &&
            snapshot?['aiGeneration'] is! Map)) {
      return null;
    }
    final stage = _text(draft['draftStage']);
    final id = _text(draft['id']).trim();
    final aiGeneration = hasTopGeneration
        ? _asStringMap(draft['aiGeneration'])
        : _asStringMap(snapshot?['aiGeneration']);
    if (stage != 'candidates' ||
        id.isEmpty ||
        draft['status'] != 'DRAFT' ||
        draft['canReview'] != true ||
        draft['canApply'] != false ||
        aiGeneration == null ||
        aiGeneration['supports'] is! List ||
        aiGeneration['resistances'] is! List) {
      return null;
    }
    return {...draft, 'aiGeneration': aiGeneration};
  }

  String _newRequestId() {
    final entropy = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    return '${DateTime.now().microsecondsSinceEpoch}_$entropy';
  }

  String _safeError(Object error) => error is StrategyMarketException
      ? error.message
      : error is StrategyApiException
      ? error.message
      : 'Không thể hoàn thành yêu cầu. Kiểm tra kết nối và thử lại.';
}

class _AutomaticInstrumentPicker extends StatefulWidget {
  const _AutomaticInstrumentPicker({required this.instruments});

  final List<StrategyInstrument> instruments;

  @override
  State<_AutomaticInstrumentPicker> createState() =>
      _AutomaticInstrumentPickerState();
}

class _AutomaticInstrumentPickerState
    extends State<_AutomaticInstrumentPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toUpperCase();
    final matches = widget.instruments
        .where(
          (instrument) =>
              query.isEmpty ||
              instrument.base.toUpperCase().contains(query) ||
              instrument.instrumentId.toUpperCase().contains(query),
        )
        .toList(growable: false);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FractionallySizedBox(
        heightFactor: 0.86,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Tìm hợp đồng USDT SWAP',
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
              TextField(
                key: const Key('strategy-automatic-instrument-search'),
                decoration: const InputDecoration(
                  labelText: 'Tìm coin hoặc cặp USDT',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value.trim()),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: matches.isEmpty
                    ? const Center(
                        child: Text('Không tìm thấy hợp đồng phù hợp.'),
                      )
                    : ListView.separated(
                        itemCount: matches.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final instrument = matches[index];
                          return ListTile(
                            key: Key(
                              'strategy-automatic-instrument-${instrument.instrumentId}',
                            ),
                            title: Text(instrument.instrumentId),
                            subtitle: Text(instrument.base),
                            onTap: () => Navigator.of(
                              context,
                            ).pop(instrument.instrumentId),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Map<String, dynamic>? _asStringMap(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) return null;
  return value.map((key, value) => MapEntry(key as String, value));
}

String _text(Object? value) => value == null ? '' : value.toString();
