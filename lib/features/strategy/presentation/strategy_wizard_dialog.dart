import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../orders/data/trade_api_client.dart';
import '../../orders/presentation/providers/trade_session_provider.dart';
import '../data/strategy_api_client.dart';
import '../data/strategy_market_repository.dart';
import '../domain/strategy_models.dart';
import '../domain/strategy_selection.dart';
import 'providers/strategy_dashboard_provider.dart';

enum _StrategyDirection { long, short, both }

class StrategyWizardDialog extends ConsumerStatefulWidget {
  const StrategyWizardDialog({
    super.key,
    required this.session,
    required this.dashboard,
    required this.onSaved,
  });

  final TradeSession session;
  final StrategyDashboardController dashboard;
  final Future<void> Function() onSaved;

  @override
  ConsumerState<StrategyWizardDialog> createState() =>
      _StrategyWizardDialogState();
}

class _StrategyWizardDialogState extends ConsumerState<StrategyWizardDialog>
    with WidgetsBindingObserver {
  final _marginController = TextEditingController();
  final _longLeverageController = TextEditingController(text: '5');
  final _shortLeverageController = TextEditingController(text: '5');
  final _longPercentController = TextEditingController(text: '50');
  final Map<String, StrategySelectedLevel> _selected = {};
  final Map<StrategySide, double> _entries = {};
  List<StrategyInstrument> _instruments = const [];
  StrategyMarketSnapshot? _snapshot;
  StrategyInterval _interval = StrategyInterval.h6;
  _StrategyDirection _direction = _StrategyDirection.long;
  StrategyAllocation _allocation = StrategyAllocation.equal;
  String? _instrumentId;
  String? _marketError;
  String? _workflowError;
  Map<String, dynamic>? _preview;
  String? _previewHash;
  String? _savedDraftId;
  bool _isLoadingInstruments = true;
  bool _isLoadingLevels = false;
  bool _isRequestingPreview = false;
  bool _isSaving = false;
  bool _isTickerInFlight = false;
  bool _appVisible = true;
  bool? _reportedTickerFreshness;
  int _tickerFailureCount = 0;
  DateTime? _tickerRetryAt;
  int _marketGeneration = 0;
  int _inputGeneration = 0;
  Timer? _tickerTimer;
  Timer? _tickerFreshnessTimer;

  StrategyMarketRepository get _market =>
      ref.read(strategyMarketRepositoryProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appVisible =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    unawaited(_loadInstruments());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appVisible = state == AppLifecycleState.resumed;
    _updateTickerPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tickerTimer?.cancel();
    _tickerFreshnessTimer?.cancel();
    _marginController.dispose();
    _longLeverageController.dispose();
    _shortLeverageController.dispose();
    _longPercentController.dispose();
    super.dispose();
  }

  Future<void> _loadInstruments() async {
    setState(() {
      _isLoadingInstruments = true;
      _marketError = null;
    });
    try {
      final instruments = await _market.getInstruments();
      if (!mounted) return;
      setState(() {
        _instruments = instruments;
        _isLoadingInstruments = false;
        if (instruments.isNotEmpty)
          _instrumentId = instruments.first.instrumentId;
      });
      if (instruments.isEmpty) {
        setState(
          () => _marketError =
              'Không tìm thấy hợp đồng USDT SWAP đang giao dịch.',
        );
      } else {
        await _loadLevels(instruments.first.instrumentId, _interval);
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingInstruments = false;
        _marketError = _safeError(error);
      });
    }
  }

  Future<void> _loadLevels(
    String instrumentId,
    StrategyInterval interval,
  ) async {
    final generation = ++_marketGeneration;
    setState(() {
      _instrumentId = instrumentId;
      _interval = interval;
      _tickerFailureCount = 0;
      _tickerRetryAt = null;
      _isLoadingLevels = true;
      _marketError = null;
      _snapshot = null;
      _selected.clear();
      _entries.clear();
      _invalidatePreview();
    });
    try {
      final snapshot = await _market.loadLevels(
        instrumentId: instrumentId,
        interval: interval,
      );
      if (!mounted || generation != _marketGeneration) return;
      setState(() {
        _snapshot = snapshot;
        _isLoadingLevels = false;
      });
      _reportedTickerFreshness = snapshot.ticker.isFreshAt(
        DateTime.now().toUtc(),
      );
      _updateTickerPolling();
    } on Object catch (error) {
      if (!mounted || generation != _marketGeneration) return;
      setState(() {
        _isLoadingLevels = false;
        _marketError = _safeError(error);
      });
    }
  }

  Future<void> _refreshTicker() async {
    final id = _instrumentId;
    if (!mounted || id == null || _isTickerInFlight) return;
    final retryAt = _tickerRetryAt;
    if (retryAt != null && DateTime.now().toUtc().isBefore(retryAt)) return;
    _isTickerInFlight = true;
    final generation = _marketGeneration;
    try {
      final ticker = await _market.getTicker(instrumentId: id);
      if (!mounted ||
          !_appVisible ||
          generation != _marketGeneration ||
          _snapshot == null)
        return;
      _tickerFailureCount = 0;
      _tickerRetryAt = null;
      final prior = _snapshot!;
      final priorEntries = Map<StrategySide, double>.of(_entries);
      final analysis = _market.calculator.calculate(
        candles: prior.candles,
        referencePrice: ticker.lastPrice,
      );
      setState(() {
        _snapshot = StrategyMarketSnapshot(
          instrumentId: prior.instrumentId,
          interval: prior.interval,
          ticker: ticker,
          candles: prior.candles,
          analysis: analysis,
        );
        _reportedTickerFreshness = ticker.isFreshAt(DateTime.now().toUtc());
        _moveEntriesToNearest();
        if (!_sameEntries(priorEntries, _entries)) _invalidatePreview();
      });
    } on Object {
      _tickerFailureCount++;
      final retrySeconds = 1 << _tickerFailureCount.clamp(1, 5).toInt();
      _tickerRetryAt = DateTime.now().toUtc().add(
        Duration(seconds: retrySeconds > 30 ? 30 : retrySeconds),
      );
      if (mounted && generation == _marketGeneration) {
        setState(() {
          if (!(_snapshot?.ticker.isFreshAt(DateTime.now().toUtc()) ?? false)) {
            _invalidatePreview();
          }
        });
      }
    } finally {
      _isTickerInFlight = false;
    }
  }

  void _changeDirection(_StrategyDirection direction) {
    setState(() {
      _direction = direction;
      final allowed = _allowedSides;
      _selected.removeWhere((_, item) => !allowed.contains(item.side));
      _entries.removeWhere((side, _) => !allowed.contains(side));
      _moveEntriesToNearest();
      _invalidatePreview();
    });
  }

  Set<StrategySide> get _allowedSides => switch (_direction) {
    _StrategyDirection.long => {StrategySide.long},
    _StrategyDirection.short => {StrategySide.short},
    _StrategyDirection.both => {StrategySide.long, StrategySide.short},
  };

  void _toggleLevel(StrategySide side, StrategyLevel level, bool selected) {
    final item = StrategySelectedLevel(side: side, price: level.price);
    setState(() {
      if (selected) {
        if (_selected.length >= 20) {
          _workflowError = 'Một chiến thuật chỉ được chọn tối đa 20 mức giá.';
          return;
        }
        _selected[item.id] = item;
        _entries.putIfAbsent(side, () => item.price);
        _moveEntriesToNearest();
      } else {
        _selected.remove(item.id);
        if (_entries[side] == item.price) _entries.remove(side);
        _moveEntriesToNearest();
      }
      _workflowError = null;
      _invalidatePreview();
    });
  }

  void _chooseEntry(StrategySide side, double price) {
    if (!_selected.values.any(
      (item) => item.side == side && item.price == price,
    )) {
      return;
    }
    setState(() {
      _entries[side] = price;
      _workflowError = null;
      _invalidatePreview();
    });
  }

  void _moveEntriesToNearest() {
    final reference = _snapshot?.ticker.lastPrice;
    if (reference == null || !reference.isFinite || reference <= 0) return;
    for (final side in _allowedSides) {
      final choices = _selected.values
          .where((item) => item.side == side)
          .toList();
      if (choices.isEmpty) {
        _entries.remove(side);
        continue;
      }
      choices.sort(
        (a, b) =>
            (a.price - reference).abs().compareTo((b.price - reference).abs()),
      );
      if (!choices.any((item) => item.price == _entries[side])) {
        _entries[side] = choices.first.price;
      } else if ((choices.first.price - reference).abs() <
          ((_entries[side]! - reference).abs())) {
        _entries[side] = choices.first.price;
      }
    }
  }

  StrategySelection? _selectionOrNull() {
    final snapshot = _snapshot;
    final instrumentId = _instrumentId;
    if (snapshot == null || instrumentId == null) return null;
    try {
      final selection = StrategySelection.validate(
        instrumentId: instrumentId,
        interval: _interval,
        referencePrice: snapshot.ticker.lastPrice,
        selectedLevels: _selected.values.toList(growable: false),
        entryBySide: Map.of(_entries),
      );
      if (!_allowedSides.containsAll(selection.entryBySide.keys) ||
          !_allowedSides.every(
            (side) =>
                !_selected.values.any((item) => item.side == side) ||
                selection.entryBySide.containsKey(side),
          )) {
        return null;
      }
      return selection;
    } on StrategySelectionException {
      return null;
    }
  }

  bool get _quoteIsFresh =>
      _snapshot?.ticker.isFreshAt(DateTime.now().toUtc()) ?? false;

  void _updateTickerPolling() {
    final shouldPoll = mounted && _appVisible && _snapshot != null;
    if (!shouldPoll) {
      _tickerTimer?.cancel();
      _tickerFreshnessTimer?.cancel();
      _tickerTimer = null;
      _tickerFreshnessTimer = null;
      return;
    }
    _tickerTimer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_refreshTicker()),
    );
    _tickerFreshnessTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _snapshot == null) return;
      final fresh = _quoteIsFresh;
      if (_reportedTickerFreshness != fresh) {
        setState(() {
          _reportedTickerFreshness = fresh;
          if (!fresh) _invalidatePreview();
        });
      }
    });
    unawaited(_refreshTicker());
  }

  void _invalidatePreview() {
    _inputGeneration++;
    _preview = null;
    _previewHash = null;
    _savedDraftId = null;
  }

  bool _sameEntries(
    Map<StrategySide, double> left,
    Map<StrategySide, double> right,
  ) {
    if (left.length != right.length) return false;
    return left.entries.every((entry) => right[entry.key] == entry.value);
  }

  String? _validateBudget() {
    final margin = double.tryParse(_marginController.text.trim());
    if (margin == null || !margin.isFinite || margin <= 0) {
      return 'Nhập ngân sách ký quỹ USDT lớn hơn 0.';
    }
    for (final side in _entries.keys) {
      final text = side == StrategySide.long
          ? _longLeverageController.text
          : _shortLeverageController.text;
      final leverage = int.tryParse(text.trim());
      if (leverage == null || leverage < 1 || leverage > 10) {
        return 'Đòn bẩy mỗi phía phải là số nguyên từ 1 đến 10.';
      }
    }
    if (_entries.length == 2) {
      final longPercent = double.tryParse(_longPercentController.text.trim());
      if (longPercent == null ||
          !longPercent.isFinite ||
          longPercent <= 0 ||
          longPercent >= 100) {
        return 'Tỷ lệ Long phải lớn hơn 0% và nhỏ hơn 100%.';
      }
    }
    return null;
  }

  Future<void> _requestPreview() async {
    final selection = _selectionOrNull();
    if (selection == null) {
      setState(
        () => _workflowError =
            'Chọn ít nhất một mức và một điểm vào gần giá nhất cho mỗi phía.',
      );
      return;
    }
    if (!_quoteIsFresh) {
      setState(
        () => _workflowError =
            'Giá SWAP đã cũ. Chờ một báo giá mới trước khi xem lại.',
      );
      return;
    }
    final validation = _validateBudget();
    if (validation != null) {
      setState(() => _workflowError = validation);
      return;
    }

    final leverage = <StrategySide, int>{};
    for (final side in _entries.keys) {
      leverage[side] = int.parse(
        (side == StrategySide.long
                ? _longLeverageController.text
                : _shortLeverageController.text)
            .trim(),
      );
    }
    final sidePercent = <StrategySide, String>{};
    if (_entries.length == 2) {
      final long = double.parse(_longPercentController.text.trim());
      sidePercent[StrategySide.long] = long.toString();
      sidePercent[StrategySide.short] = (100 - long).toString();
    }
    final request = selection.toRequestJson(
      totalMargin: _marginController.text.trim(),
      leverage: leverage,
      sidePercent: sidePercent,
      allocation: _allocation,
    );
    setState(() {
      _isRequestingPreview = true;
      _workflowError = null;
      _invalidatePreview();
    });
    final requestGeneration = _inputGeneration;
    try {
      final preview = await ref
          .read(strategyApiProvider)
          .preview(
            widget.session.bearerToken,
            Map<String, dynamic>.from(request),
          );
      final hash = _text(preview['previewHash']);
      final orders = _list(preview['orders']);
      if (hash.isEmpty || orders.isEmpty) {
        throw const StrategyApiException(
          code: 'invalid_response',
          message: 'Máy chủ chưa trả về bản xem trước lệnh đầy đủ.',
        );
      }
      if (!mounted) return;
      if (requestGeneration != _inputGeneration) {
        setState(() {
          _isRequestingPreview = false;
          _workflowError =
              'Giá hoặc thông số đã thay đổi trong lúc tính. Hãy xem lại lần nữa.';
        });
        return;
      }
      setState(() {
        _preview = preview;
        _previewHash = hash;
        _isRequestingPreview = false;
        _step = 2;
      });
    } on StrategyApiException catch (error) {
      if (!mounted) return;
      if (error.isUnauthorized) {
        ref.read(tradeSessionProvider.notifier).expire();
      }
      setState(() {
        _isRequestingPreview = false;
        _workflowError = error.message;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _isRequestingPreview = false;
        _workflowError = _safeError(error);
      });
    }
  }

  int _step = 0;

  Map<String, dynamic> _saveBody() {
    final selection = _selectionOrNull();
    if (selection == null || _previewHash == null) {
      throw StateError('The strategy preview is no longer available.');
    }
    final leverage = <StrategySide, int>{
      for (final side in _entries.keys)
        side: int.parse(
          (side == StrategySide.long
                  ? _longLeverageController.text
                  : _shortLeverageController.text)
              .trim(),
        ),
    };
    final sidePercent = <StrategySide, String>{};
    if (_entries.length == 2) {
      final long = double.parse(_longPercentController.text.trim());
      sidePercent[StrategySide.long] = long.toString();
      sidePercent[StrategySide.short] = (100 - long).toString();
    }
    return {
      ...selection.toRequestJson(
        totalMargin: _marginController.text.trim(),
        leverage: leverage,
        sidePercent: sidePercent,
        allocation: _allocation,
      ),
      'previewHash': _previewHash!,
    };
  }

  Future<String> _saveForApply() async {
    final existingId = _savedDraftId;
    if (existingId != null) return existingId;
    final saved = await ref
        .read(strategyApiProvider)
        .saveDraft(widget.session.bearerToken, _saveBody());
    final id = _text(saved['id']);
    if (id.isEmpty) {
      throw const StrategyApiException(
        code: 'invalid_response',
        message: 'Máy chủ chưa trả về mã bản nháp.',
      );
    }
    _savedDraftId = id;
    await widget.onSaved();
    return id;
  }

  Future<void> _saveDraft() async {
    if (!_canActOnPreview) return;
    setState(() {
      _isSaving = true;
      _workflowError = null;
    });
    try {
      final saved = await ref
          .read(strategyApiProvider)
          .saveDraft(widget.session.bearerToken, _saveBody());
      if (_text(saved['id']).isEmpty) {
        throw const StrategyApiException(
          code: 'invalid_response',
          message: 'Máy chủ chưa trả về mã bản nháp.',
        );
      }
      await widget.onSaved();
      if (!mounted) return;
      Navigator.of(context).pop();
      _message('Đã lưu bản nháp.');
    } on Object catch (error) {
      _expireSessionIfUnauthorized(error);
      if (mounted) {
        setState(() {
          _isSaving = false;
          _workflowError = _safeError(error);
        });
      }
    }
  }

  Future<bool> _confirmPrepared(Map<String, dynamic> prepared) async {
    final orders = _preparedOrders(prepared);
    if (orders.isEmpty || !mounted) return false;
    final confirmed = await showDialog<bool>(
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
                  'Đây là danh sách đã được máy chủ chuẩn hóa lại. Xác nhận sẽ gửi một lần.',
                ),
                const SizedBox(height: 8),
                _PreparedFinancialSummary(prepared: prepared),
                const SizedBox(height: 12),
                for (var index = 0; index < orders.length; index++)
                  _PreparedOrderTile(index: index + 1, order: orders[index]),
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
    );
    return confirmed == true;
  }

  Future<void> _applyNow() async {
    if (!_canActOnPreview) return;
    setState(() {
      _isSaving = true;
      _workflowError = null;
    });
    try {
      final id = await _saveForApply();
      final outcome = await widget.dashboard.applyDraft(
        id,
        confirm: _confirmPrepared,
      );
      await widget.onSaved();
      if (!mounted) return;
      if (outcome.kind == StrategyApplyOutcomeKind.cancelled) {
        Navigator.of(context).pop();
        _message('Bản nháp đã lưu; chưa gửi lệnh.');
        return;
      }
      if (outcome.kind == StrategyApplyOutcomeKind.unknown) {
        Navigator.of(context).pop();
        _message(
          outcome.message ??
              'Kết quả chưa rõ. Không gửi lại; làm mới trạng thái chiến thuật.',
        );
        return;
      }
      if (outcome.kind == StrategyApplyOutcomeKind.rejected) {
        setState(() {
          _isSaving = false;
          _workflowError = outcome.message ?? 'Máy chủ từ chối áp dụng.';
        });
        return;
      }
      if (outcome.kind == StrategyApplyOutcomeKind.duplicate) {
        setState(() {
          _isSaving = false;
          _workflowError = 'Yêu cầu này đang được xử lý.';
        });
        return;
      }
      Navigator.of(context).pop();
      final status = _text(outcome.result?['status']).toUpperCase();
      _message(
        status == 'APPLIED'
            ? 'Máy chủ đã chấp nhận lệnh chiến thuật.'
            : 'Trạng thái chiến thuật: ${status.isEmpty ? 'đang cập nhật' : status}.',
      );
    } on Object catch (error) {
      _expireSessionIfUnauthorized(error);
      if (mounted) {
        setState(() {
          _isSaving = false;
          _workflowError = _safeError(error);
        });
      }
    }
  }

  bool get _canActOnPreview =>
      !_isSaving && !_isRequestingPreview && _preview != null && _quoteIsFresh;

  void _message(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: width < 600 ? 8 : 28,
        vertical: 18,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          children: [
            _buildHeader(context),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: switch (_step) {
                  0 => _buildSelectionStep(context),
                  1 => _buildBudgetStep(context),
                  _ => _buildReviewStep(context),
                },
              ),
            ),
            const Divider(height: 1),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 12, 8, 12),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dựng chiến thuật',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text('Bước ${_step + 1} / 3 · ${_stepLabel(_step)}'),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Đóng',
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );

  Widget _buildSelectionStep(BuildContext context) {
    final snapshot = _snapshot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          key: const Key('strategy-instrument-select'),
          value: _instrumentId,
          decoration: const InputDecoration(labelText: 'Hợp đồng USDT SWAP'),
          items: _instruments
              .map(
                (item) => DropdownMenuItem(
                  value: item.instrumentId,
                  child: Text(item.instrumentId),
                ),
              )
              .toList(growable: false),
          onChanged: _isLoadingInstruments || _isLoadingLevels || _isSaving
              ? null
              : (value) {
                  if (value != null) unawaited(_loadLevels(value, _interval));
                },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<StrategyInterval>(
          key: const Key('strategy-interval-select'),
          value: _interval,
          decoration: const InputDecoration(labelText: 'Khung nến UTC'),
          items: StrategyInterval.values
              .map(
                (value) =>
                    DropdownMenuItem(value: value, child: Text(value.label)),
              )
              .toList(growable: false),
          onChanged: _isLoadingLevels || _isSaving
              ? null
              : (value) {
                  if (value != null && _instrumentId != null) {
                    unawaited(_loadLevels(_instrumentId!, value));
                  }
                },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<_StrategyDirection>(
          key: const Key('strategy-direction-select'),
          value: _direction,
          decoration: const InputDecoration(labelText: 'Phía giao dịch'),
          items: const [
            DropdownMenuItem(
              value: _StrategyDirection.long,
              child: Text('Long'),
            ),
            DropdownMenuItem(
              value: _StrategyDirection.short,
              child: Text('Short'),
            ),
            DropdownMenuItem(
              value: _StrategyDirection.both,
              child: Text('Long và Short'),
            ),
          ],
          onChanged: _isSaving
              ? null
              : (value) {
                  if (value != null) _changeDirection(value);
                },
        ),
        const SizedBox(height: 12),
        if (_isLoadingInstruments || _isLoadingLevels)
          const LinearProgressIndicator(),
        if (_marketError != null)
          _WizardNotice(
            message: _marketError!,
            error: true,
            onRetry: _loadInstruments,
          ),
        if (snapshot != null) ...[
          _quoteBanner(snapshot.ticker),
          const SizedBox(height: 8),
          Text('${snapshot.candles.length} nến UTC đã xác nhận · tối đa 500'),
          if (snapshot.candles.length < 5)
            const _WizardNotice(
              message:
                  'Dữ liệu còn thưa; cần ít nhất 5 nến hợp lệ để tìm vùng giá.',
            ),
          if (_allowedSides.contains(StrategySide.long))
            _buildSideLevels(
              context,
              StrategySide.long,
              snapshot.analysis.supports,
            ),
          if (_allowedSides.contains(StrategySide.short))
            _buildSideLevels(
              context,
              StrategySide.short,
              snapshot.analysis.resistances,
            ),
        ],
        if (_workflowError != null)
          _WizardNotice(message: _workflowError!, error: true),
      ],
    );
  }

  Widget _quoteBanner(StrategyTicker ticker) {
    final fresh = ticker.isFreshAt(DateTime.now().toUtc());
    return Card(
      color: fresh ? null : Theme.of(context).colorScheme.errorContainer,
      child: ListTile(
        dense: true,
        leading: Icon(fresh ? Icons.bolt : Icons.schedule),
        title: Text(
          'Giá ${_price(ticker.lastPrice)}${fresh ? '' : ' · đã cũ'}',
        ),
        subtitle: Text('Cập nhật ${_dateTime(ticker.observedAt)}'),
      ),
    );
  }

  Widget _buildSideLevels(
    BuildContext context,
    StrategySide side,
    List<StrategyLevel> levels,
  ) {
    final selectedPrices = _selected.values
        .where((item) => item.side == side)
        .map((item) => item.price)
        .toList(growable: false);
    final nearestPrice = selectedPrices.isEmpty
        ? null
        : selectedPrices.reduce(
            (left, right) =>
                (left - _snapshot!.ticker.lastPrice).abs() <=
                    (right - _snapshot!.ticker.lastPrice).abs()
                ? left
                : right,
          );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            side == StrategySide.long
                ? 'Hỗ trợ cho Long'
                : 'Kháng cự cho Short',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (levels.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Không có vùng ${side == StrategySide.long ? 'hỗ trợ' : 'kháng cự'} hợp lệ.',
              ),
            )
          else
            for (final level in levels)
              _StrategyLevelCard(
                key: ValueKey('strategy-level-${level.id}'),
                side: side,
                level: level,
                referencePrice: _snapshot!.ticker.lastPrice,
                selected: _selected.values.any(
                  (item) => item.side == side && item.price == level.price,
                ),
                entryPrice: _entries[side],
                canBeEntry: level.price == nearestPrice,
                onSelected: (selected) => _toggleLevel(side, level, selected),
                onEntry: () => _chooseEntry(side, level.price),
              ),
        ],
      ),
    );
  }

  Widget _buildBudgetStep(BuildContext context) {
    final sides = _entries.keys.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ngân sách USDT là ký quỹ trước đòn bẩy. Phí mở lệnh được tính riêng.',
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('strategy-margin-input'),
          controller: _marginController,
          enabled: !_isRequestingPreview,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Tổng ký quỹ (USDT)',
            prefixIcon: Icon(Icons.account_balance_wallet_outlined),
          ),
          onChanged: (_) => setState(_invalidatePreview),
        ),
        const SizedBox(height: 12),
        for (final side in sides)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: side == StrategySide.long
                  ? _longLeverageController
                  : _shortLeverageController,
              enabled: !_isRequestingPreview,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Đòn bẩy ${side.label} (1–10)',
                suffixText: 'x · Isolated',
              ),
              onChanged: (_) => setState(_invalidatePreview),
            ),
          ),
        if (sides.length == 2) ...[
          TextField(
            controller: _longPercentController,
            enabled: !_isRequestingPreview,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Tỷ lệ ký quỹ Long (%)',
              helperText:
                  'Phần còn lại được phân bổ cho Short. Mặc định 50/50.',
            ),
            onChanged: (_) => setState(_invalidatePreview),
          ),
          const SizedBox(height: 12),
          Text(
            'Long ${_longPercentController.text.isEmpty ? '50' : _longPercentController.text}% · Short ${_shortPercentLabel}%',
          ),
        ],
        const SizedBox(height: 12),
        DropdownButtonFormField<StrategyAllocation>(
          value: _allocation,
          decoration: const InputDecoration(labelText: 'Phân bổ giữa các lệnh'),
          items: const [
            DropdownMenuItem(
              value: StrategyAllocation.equal,
              child: Text('Đều nhau'),
            ),
            DropdownMenuItem(
              value: StrategyAllocation.increasing,
              child: Text('Tăng dần từ điểm vào'),
            ),
            DropdownMenuItem(
              value: StrategyAllocation.decreasing,
              child: Text('Giảm dần từ điểm vào'),
            ),
          ],
          onChanged: _isRequestingPreview
              ? null
              : (value) {
                  if (value != null)
                    setState(() {
                      _allocation = value;
                      _invalidatePreview();
                    });
                },
        ),
        const SizedBox(height: 12),
        const Text(
          'Đơn vị hợp đồng và số lượng cuối cùng do máy chủ xác minh.',
        ),
        if (_workflowError != null)
          _WizardNotice(message: _workflowError!, error: true),
      ],
    );
  }

  String get _shortPercentLabel {
    final long = double.tryParse(_longPercentController.text.trim()) ?? 50;
    return (100 - long).toStringAsFixed(2).replaceFirst(RegExp(r'\.00$'), '');
  }

  Widget _buildReviewStep(BuildContext context) {
    final preview = _preview;
    if (preview == null) {
      return const _WizardNotice(
        message: 'Bản xem trước đã hết hiệu lực. Quay lại và yêu cầu xem lại.',
      );
    }
    final orders = _list(preview['orders']).map(_asMap).toList(growable: false);
    final margins = <String, dynamic>{
      'totalMargin': preview['totalMargin'],
      'plannedMargin': preview['plannedMargin'],
      'unallocatedMargin': preview['unallocatedMargin'],
    };
    final fees = <String, dynamic>{
      'estimatedOpeningFees': preview['estimatedOpeningFees'],
      'feesOutsideMargin': preview['feesOutsideMargin'],
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Card(
          child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Số liệu bên dưới do máy chủ tính.'),
            subtitle: Text(
              'Thanh lý dự kiến là giả định theo từng lần khớp; giá thực tế có thể khác.',
            ),
          ),
        ),
        if (!_quoteIsFresh)
          _WizardNotice(
            message:
                'Giá SWAP đã cũ. Chờ báo giá mới để lưu hoặc áp dụng bản xem trước này.',
            error: true,
          ),
        Text('Giá thị trường lúc xem: ${_text(preview['currentPrice'])}'),
        Text('Thời điểm giá: ${_text(preview['quoteTimestamp'])}'),
        const SizedBox(height: 8),
        Text(
          'Lệnh đã chuẩn hóa (${orders.length})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        for (var index = 0; index < orders.length; index++)
          _PreviewOrderCard(index: index + 1, order: orders[index]),
        const SizedBox(height: 10),
        _PreviewSummary(label: 'Ký quỹ', value: margins),
        _PreviewSummary(label: 'Phí ước tính, tính riêng', value: fees),
        if (_workflowError != null)
          _WizardNotice(message: _workflowError!, error: true),
      ],
    );
  }

  Widget _buildFooter(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    child: Row(
      children: [
        TextButton(
          onPressed: _isSaving || _isRequestingPreview
              ? null
              : _step == 0
              ? () => Navigator.of(context).pop()
              : () => setState(() {
                  _step--;
                  _workflowError = null;
                }),
          child: Text(_step == 0 ? 'Hủy' : 'Quay lại'),
        ),
        const Spacer(),
        if (_step == 0)
          FilledButton(
            key: const Key('strategy-next-step-one'),
            onPressed: _selectionOrNull() == null || !_quoteIsFresh
                ? null
                : () => setState(() {
                    _step = 1;
                    _workflowError = null;
                  }),
            child: const Text('Tiếp theo'),
          )
        else if (_step == 1)
          FilledButton(
            key: const Key('strategy-request-preview'),
            onPressed: _isRequestingPreview ? null : _requestPreview,
            child: _isRequestingPreview
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Xem lại lệnh'),
          )
        else ...[
          OutlinedButton(
            key: const Key('strategy-save-draft'),
            onPressed: _canActOnPreview ? _saveDraft : null,
            child: const Text('Lưu bản nháp'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const Key('strategy-apply-now'),
            onPressed: _canActOnPreview ? _applyNow : null,
            child: _isSaving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Áp dụng ngay'),
          ),
        ],
      ],
    ),
  );

  String _stepLabel(int step) => switch (step) {
    0 => 'Chọn vùng giá',
    1 => 'Ký quỹ và đòn bẩy',
    _ => 'Xem lại và xác nhận',
  };

  String _safeError(Object error) => error is StrategyMarketException
      ? error.message
      : error is StrategyApiException
      ? error.message
      : 'Không thể hoàn thành yêu cầu. Kiểm tra kết nối và thử lại.';

  void _expireSessionIfUnauthorized(Object error) {
    if (error is StrategyApiException && error.isUnauthorized) {
      ref.read(tradeSessionProvider.notifier).expire();
    }
  }
}

class _StrategyLevelCard extends StatelessWidget {
  const _StrategyLevelCard({
    super.key,
    required this.side,
    required this.level,
    required this.referencePrice,
    required this.selected,
    required this.entryPrice,
    required this.canBeEntry,
    required this.onSelected,
    required this.onEntry,
  });

  final StrategySide side;
  final StrategyLevel level;
  final double referencePrice;
  final bool selected;
  final double? entryPrice;
  final bool canBeEntry;
  final ValueChanged<bool> onSelected;
  final VoidCallback onEntry;

  @override
  Widget build(BuildContext context) {
    final distance = (referencePrice - level.price).abs();
    final percent = distance / referencePrice * 100;
    return Card(
      margin: const EdgeInsets.only(top: 6),
      child: Column(
        children: [
          CheckboxListTile(
            value: selected,
            onChanged: (value) => onSelected(value ?? false),
            title: Text('${_price(level.price)} USDT'),
            subtitle: Text(
              '${distance.toStringAsPrecision(6)} · ${percent.toStringAsFixed(3)}% · ${level.touchCount} lần',
            ),
            secondary: Icon(
              side == StrategySide.long ? Icons.south : Icons.north,
            ),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          if (selected)
            RadioListTile<double>(
              value: level.price,
              groupValue: entryPrice,
              onChanged: canBeEntry ? (_) => onEntry() : null,
              title: const Text('Điểm vào gần giá nhất'),
              dense: true,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

class _PreviewOrderCard extends StatelessWidget {
  const _PreviewOrderCard({required this.index, required this.order});

  final int index;
  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    final liquidation = _asMap(order['liquidationEstimate']);
    final liquidationLabel = liquidation['status'] == 'no_positive_threshold'
        ? 'không có ngưỡng dương'
        : _text(liquidation['price']).isEmpty
        ? 'chưa có dữ liệu'
        : _text(liquidation['price']);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$index. ${_text(order['side']).toUpperCase()} · ${_text(order['role'])}',
            ),
            Text(
              'Giá giới hạn ${_text(order['limitPrice'])} · Hợp đồng ${_text(order['contracts'])}',
            ),
            Text(
              'Ký quỹ ${_text(order['margin'])} · Đòn bẩy ${_text(order['leverage'])}x',
            ),
            Text(
              'Phí mở ước tính ${_text(order['openingFeeEstimate'])} · ngoài ngân sách ký quỹ',
            ),
            Text('Giá vốn lũy kế ${_text(order['cumulativeAverageEntry'])}'),
            Text('Thanh lý giả định $liquidationLabel'),
          ],
        ),
      ),
    );
  }
}

class _PreparedOrderTile extends StatelessWidget {
  const _PreparedOrderTile({required this.index, required this.order});

  final int index;
  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    leading: CircleAvatar(radius: 14, child: Text('$index')),
    title: Text(
      '${_text(order['side']).toUpperCase()} · ${_text(order['role'])} · ${_text(order['limitPrice'])}',
    ),
    subtitle: Text(
      'Contr ${_text(order['contracts'])} · Margin ${_text(order['margin'])} · ${_text(order['leverage'])}x',
    ),
  );
}

class _PreviewSummary extends StatelessWidget {
  const _PreviewSummary({required this.label, required this.value});

  final String label;
  final Map<String, dynamic> value;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleSmall),
            for (final entry in value.entries)
              Text('${entry.key}: ${entry.value ?? '—'}'),
          ],
        ),
      ),
    );
  }
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

class _WizardNotice extends StatelessWidget {
  const _WizardNotice({
    required this.message,
    this.error = false,
    this.onRetry,
  });

  final String message;
  final bool error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Card(
    color: error ? Theme.of(context).colorScheme.errorContainer : null,
    child: ListTile(
      dense: true,
      leading: Icon(error ? Icons.warning_amber : Icons.info_outline),
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

List<Object?> _list(Object? value) =>
    value is List ? List<Object?>.from(value) : const [];

Map<String, dynamic> _asMap(Object? value) => value is Map
    ? value.map((key, item) => MapEntry(key.toString(), item))
    : const {};

String _text(Object? value) => value == null ? '' : value.toString();

String _price(double value) => value >= 1000
    ? value.toStringAsFixed(2)
    : value
          .toStringAsPrecision(8)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');

String _dateTime(DateTime value) {
  final local = value.toLocal();
  String two(int item) => item.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
