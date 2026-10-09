import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../orders/data/trade_api_client.dart';
import '../../orders/presentation/providers/trade_session_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive_form_content.dart';
import '../data/strategy_api_client.dart';
import '../data/strategy_market_repository.dart';
import '../domain/strategy_models.dart';
import '../domain/strategy_selection.dart';
import '../domain/strategy_settings.dart';
import 'providers/strategy_dashboard_provider.dart';
import 'strategy_number_formatter.dart';

enum _StrategyDirection { long, short, both }

class StrategyWizardDialog extends ConsumerStatefulWidget {
  const StrategyWizardDialog({
    super.key,
    required this.session,
    required this.dashboard,
    required this.onSaved,
    this.replacementSourceId,
    this.initialCandidateDraft,
  });

  final TradeSession session;
  final StrategyDashboardController dashboard;
  final Future<void> Function() onSaved;
  final String? replacementSourceId;
  final Map<String, dynamic>? initialCandidateDraft;

  @override
  ConsumerState<StrategyWizardDialog> createState() =>
      _StrategyWizardDialogState();
}

class _StrategyWizardDialogState extends ConsumerState<StrategyWizardDialog> {
  final _marginController = TextEditingController();
  final _longLeverageController = TextEditingController(text: '5');
  final _shortLeverageController = TextEditingController(text: '5');
  final _longPercentController = TextEditingController(text: '50');
  final Map<String, StrategySelectedLevel> _selected = {};
  final Map<StrategySide, String> _entries = {};
  final Map<String, Map<String, dynamic>> _candidateAssessments = {};
  final Map<String, int> _candidateRanks = {};
  List<StrategyInstrument> _instruments = const [];
  StrategyMarketSnapshot? _snapshot;
  StrategyInterval _interval = StrategyInterval.h6;
  _StrategyDirection _direction = _StrategyDirection.long;
  _StrategyDirection _candidateDirection = _StrategyDirection.both;
  StrategyAllocation _allocation = StrategyAllocation.equal;
  String? _instrumentId;
  String? _marketError;
  String? _workflowError;
  String? _selectionNotice;
  Map<String, dynamic>? _preview;
  String? _previewHash;
  String? _savedDraftId;
  bool _isLoadingInstruments = true;
  bool _isLoadingLevels = false;
  bool _isRequestingPreview = false;
  bool _isSaving = false;
  bool _isSavingDraft = false;
  int _marketGeneration = 0;
  int _inputGeneration = 0;
  String? _candidateDraftId;
  bool _candidateScopeValid = true;

  bool get _isReviewingCandidates => widget.initialCandidateDraft != null;

  StrategyMarketRepository get _market =>
      ref.read(strategyMarketRepositoryProvider);

  bool get _isSessionCurrent {
    if (!mounted) return false;
    final state = ref.read(tradeSessionProvider);
    return state.isAuthenticated &&
        state.session?.bearerToken == widget.session.bearerToken &&
        widget.dashboard.ownsSession;
  }

  @override
  void initState() {
    super.initState();
    final candidateDraft = widget.initialCandidateDraft;
    if (candidateDraft == null) {
      unawaited(_loadInstruments());
    } else {
      _initializeCandidateDraft(candidateDraft);
    }
  }

  void _initializeCandidateDraft(Map<String, dynamic> draft) {
    _candidateScopeValid = false;
    try {
      final rawSnapshot = _asMap(draft['snapshot']);
      final hasTopGeneration = draft.containsKey('aiGeneration');
      if ((hasTopGeneration && draft['aiGeneration'] is! Map) ||
          (!hasTopGeneration &&
              rawSnapshot.containsKey('aiGeneration') &&
              rawSnapshot['aiGeneration'] is! Map)) {
        throw const FormatException('invalid saved candidate scope');
      }
      final aiGeneration = hasTopGeneration
          ? _asMap(draft['aiGeneration'])
          : _asMap(rawSnapshot['aiGeneration']);
      final instrumentId = _text(draft['instrumentId']).isNotEmpty
          ? _text(draft['instrumentId'])
          : _text(aiGeneration['instrumentId']);
      final intervalText = _text(draft['interval']).isNotEmpty
          ? _text(draft['interval'])
          : _text(aiGeneration['interval']);
      final interval = StrategyInterval.values.where(
        (value) => value.bar == intervalText,
      );
      final rawDirection = aiGeneration['direction'];
      final candidateDirection = !aiGeneration.containsKey('direction')
          ? _StrategyDirection.both
          : switch (rawDirection) {
              'long' => _StrategyDirection.long,
              'short' => _StrategyDirection.short,
              'both' => _StrategyDirection.both,
              _ => throw const FormatException('invalid candidate direction'),
            };
      _candidateDirection = candidateDirection;
      _direction = candidateDirection;
      _candidateScopeValid = true;
      final referenceText = _text(aiGeneration['referencePrice']);
      final reference = StrategyDecimal.tryParse(referenceText);
      final snapshotData = _asMap(aiGeneration['evaluationSnapshot']);
      final observedAtText = _text(aiGeneration['observedAt']).isNotEmpty
          ? _text(aiGeneration['observedAt'])
          : _text(snapshotData['observedAt']);
      final observedAt = DateTime.tryParse(observedAtText);
      final draftId = _text(draft['id']).trim();
      if (draftId.isEmpty ||
          instrumentId.isEmpty ||
          !RegExp(r'^[A-Z0-9]+-USDT-SWAP$').hasMatch(instrumentId) ||
          interval.isEmpty ||
          !const {
            StrategyInterval.h6,
            StrategyInterval.d1,
            StrategyInterval.w1,
          }.contains(interval.first) ||
          reference == null ||
          !reference.isPositive ||
          !reference.toDouble().isFinite ||
          observedAt == null ||
          !observedAt.isUtc ||
          aiGeneration['supports'] is! List ||
          aiGeneration['resistances'] is! List) {
        throw const FormatException('invalid saved candidate snapshot');
      }
      final selectedInterval = interval.first;
      final supports = _parseCandidateLevels(
        aiGeneration['supports'],
        StrategySide.long,
      );
      final resistances = _parseCandidateLevels(
        aiGeneration['resistances'],
        StrategySide.short,
      );
      final ticker = StrategyTicker(
        instrumentId: instrumentId,
        lastPrice: reference.toDouble(),
        observedAt: observedAt,
        exactPriceText: reference.toString(),
      );
      _candidateDraftId = draftId;
      _instrumentId = instrumentId;
      _interval = selectedInterval;
      _direction = _candidateDirection;
      _isLoadingInstruments = false;
      _instruments = [
        StrategyInstrument(
          instrumentId: instrumentId,
          base: instrumentId.split('-').first,
          tickSizeText: _text(aiGeneration['tickSize']),
        ),
      ];
      _snapshot = StrategyMarketSnapshot(
        instrumentId: instrumentId,
        interval: selectedInterval,
        ticker: ticker,
        candles: const [],
        analysis: StrategyAnalysis(
          referencePrice: reference.toDouble(),
          exactReferencePriceText: reference.toString(),
          supports: supports,
          resistances: resistances,
        ),
      );
      _applySavedRecommendation(
        aiGeneration['recommendation'],
        supports: supports,
        resistances: resistances,
      );
    } on Object catch (_) {
      _candidateScopeValid = false;
      _isLoadingInstruments = false;
      _marketError = 'Bản chụp ứng viên đã lưu không thể mở để xem xét.';
    }
  }

  void _applySavedRecommendation(
    Object? rawRecommendation, {
    required List<StrategyLevel> supports,
    required List<StrategyLevel> resistances,
  }) {
    _selected.clear();
    _entries.clear();
    _direction = _candidateDirection;
    if (rawRecommendation == null) {
      _selectionNotice =
          'Không có đề xuất Jev đã lưu; mọi mức bắt đầu chưa chọn.';
      return;
    }

    final recommendation = _strictStringMap(rawRecommendation);
    if (recommendation == null ||
        recommendation['version'] != 'ai-jev-selection-v1' ||
        recommendation['maxPerSide'] != 5 ||
        StrategyJevScreeningThresholds.tryParseSnapshot(recommendation) ==
            null) {
      _selectionNotice =
          'Đề xuất đã lưu không hợp lệ; mọi mức đã được bỏ chọn. Bạn có thể chọn thủ công.';
      return;
    }
    final rawLongIds = recommendation['longLevelIds'];
    final rawShortIds = recommendation['shortLevelIds'];
    if (rawLongIds is! List ||
        rawShortIds is! List ||
        !rawLongIds.every((id) => id is String) ||
        !rawShortIds.every((id) => id is String) ||
        rawLongIds.length > 5 ||
        rawShortIds.length > 5) {
      _selectionNotice =
          'Đề xuất đã lưu không hợp lệ; mọi mức đã được bỏ chọn. Bạn có thể chọn thủ công.';
      return;
    }

    final longIds = List<String>.from(rawLongIds);
    final shortIds = List<String>.from(rawShortIds);
    if ((_candidateDirection == _StrategyDirection.short &&
            longIds.isNotEmpty) ||
        (_candidateDirection == _StrategyDirection.long &&
            shortIds.isNotEmpty)) {
      _selectionNotice =
          'Đề xuất đã lưu vượt quá phạm vi hướng giao dịch; mọi mức đã được bỏ chọn.';
      return;
    }
    final allIds = [...longIds, ...shortIds];
    if (allIds.toSet().length != allIds.length) {
      _selectionNotice =
          'Đề xuất đã lưu không hợp lệ; mọi mức đã được bỏ chọn. Bạn có thể chọn thủ công.';
      return;
    }

    final levelsBySide = <StrategySide, Map<String, StrategyLevel>>{
      StrategySide.long: {for (final level in supports) level.id: level},
      StrategySide.short: {for (final level in resistances) level.id: level},
    };
    final selections = <StrategySelectedLevel>[];
    for (final (ids, side) in [
      (longIds, StrategySide.long),
      (shortIds, StrategySide.short),
    ]) {
      for (final id in ids) {
        final level = levelsBySide[side]![id];
        final exactPrice = StrategyDecimal.tryParse(level?.priceText);
        if (level == null ||
            exactPrice == null ||
            !exactPrice.isPositive ||
            !_hasValidSuccessfulAssessment(id)) {
          _selectionNotice =
              'Đề xuất đã lưu không hợp lệ; mọi mức đã được bỏ chọn. Bạn có thể chọn thủ công.';
          return;
        }
        selections.add(
          StrategySelectedLevel(
            side: side,
            price: level.price,
            exactPriceText: exactPrice.toString(),
            levelId: id,
          ),
        );
      }
    }

    for (final selection in selections) {
      _selected[selection.id] = selection;
    }
    final hasLong = longIds.isNotEmpty;
    final hasShort = shortIds.isNotEmpty;
    _direction = !hasLong && !hasShort
        ? _candidateDirection
        : switch ((hasLong, hasShort)) {
            (true, false) => _StrategyDirection.long,
            (false, true) => _StrategyDirection.short,
            _ => _StrategyDirection.both,
          };
    if (allIds.isEmpty) {
      _selectionNotice =
          'Không có mức nào đạt tiêu chí Jev; bạn có thể chọn thủ công.';
    }
    _moveEntriesToNearest();
  }

  bool _hasValidSuccessfulAssessment(String levelId) {
    final assessment = _candidateAssessments[levelId];
    if (assessment == null || assessment['status'] != 'success') return false;
    return _finiteInRange(assessment['structuralQuality'], 0, 5) != null &&
        _finiteInRange(assessment['entrySuitabilityProbability'], 0, 1) !=
            null &&
        _finiteInRange(assessment['failureRiskProbability'], 0, 1) != null;
  }

  Map<String, dynamic>? _strictStringMap(Object? value) =>
      value is Map && value.keys.every((key) => key is String)
      ? Map<String, dynamic>.from(value)
      : null;

  List<StrategyLevel> _parseCandidateLevels(
    Object? value,
    StrategySide expectedSide,
  ) {
    if (value is! List) throw const FormatException('invalid candidates');
    final levels = <StrategyLevel>[];
    for (final raw in value) {
      final candidate = _asMap(raw);
      final levelId = _text(candidate['levelId']);
      final priceText = _text(candidate['price']);
      final exactPrice = StrategyDecimal.tryParse(priceText);
      final side = _text(candidate['side']);
      final touchCount = candidate['touchCount'];
      final generationOrder = candidate['generationOrder'];
      final rank = candidate['rank'];
      final firstTouchAt = DateTime.tryParse(_text(candidate['firstTouchAt']));
      final lastTouchAt = DateTime.tryParse(_text(candidate['lastTouchAt']));
      if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(levelId) ||
          exactPrice == null ||
          exactPrice.coefficient.isNegative ||
          (exactPrice.coefficient == BigInt.zero &&
              expectedSide != StrategySide.long) ||
          side != expectedSide.wireValue ||
          touchCount is! int ||
          touchCount < 1 ||
          generationOrder is! int ||
          generationOrder < 0 ||
          rank is! int ||
          rank < 1 ||
          firstTouchAt == null ||
          !firstTouchAt.isUtc ||
          lastTouchAt == null ||
          !lastTouchAt.isUtc ||
          lastTouchAt.isBefore(firstTouchAt) ||
          _candidateAssessments.containsKey(levelId)) {
        throw const FormatException('invalid candidate level');
      }
      final rawAssessment = _asMap(candidate['assessment']);
      final assessmentStatus = _text(rawAssessment['status']);
      final assessment = <String, dynamic>{
        ...rawAssessment,
        'status':
            const {'success', 'failed', 'disabled'}.contains(assessmentStatus)
            ? assessmentStatus
            : 'unavailable',
      };
      _candidateAssessments[levelId] = assessment;
      _candidateRanks[levelId] = rank;
      levels.add(
        StrategyLevel(
          price: exactPrice.toDouble(),
          firstTouchAt: firstTouchAt,
          lastTouchAt: lastTouchAt,
          touchCount: touchCount,
          side: expectedSide,
          exactPriceText: exactPrice.toString(),
          levelId: levelId,
        ),
      );
    }
    return List.unmodifiable(levels);
  }

  @override
  void dispose() {
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
      _isLoadingLevels = true;
      _marketError = null;
      _snapshot = null;
      _selected.clear();
      _entries.clear();
      _selectionNotice = null;
      _invalidatePreview();
    });
    try {
      final matchingInstrument = _instruments.where(
        (instrument) => instrument.instrumentId == instrumentId,
      );
      final tickSizeText = matchingInstrument.isEmpty
          ? null
          : matchingInstrument.first.tickSizeText;
      if (tickSizeText == null) {
        if (!mounted || generation != _marketGeneration) return;
        setState(() {
          _isLoadingLevels = false;
          _marketError = 'The selected swap tick size is unavailable.';
        });
        return;
      }
      final snapshot = await _market.loadLevels(
        instrumentId: instrumentId,
        interval: interval,
        tickSizeText: tickSizeText,
      );
      if (!mounted || generation != _marketGeneration) return;
      setState(() {
        _snapshot = snapshot;
        _isLoadingLevels = false;
      });
    } on Object catch (error) {
      if (!mounted || generation != _marketGeneration) return;
      setState(() {
        _isLoadingLevels = false;
        _marketError = _safeError(error);
      });
    }
  }

  void _changeDirection(_StrategyDirection direction) {
    if (_isReviewingCandidates &&
        _candidateDirection != _StrategyDirection.both &&
        direction != _candidateDirection) {
      return;
    }
    setState(() {
      _direction = direction;
      final allowed = _allowedSides;
      _selected.removeWhere((_, item) => !allowed.contains(item.side));
      _entries.removeWhere((side, _) => !allowed.contains(side));
      _selectionNotice = null;
      _moveEntriesToNearest();
      _invalidatePreview();
    });
  }

  Set<StrategySide> get _allowedSides {
    final current = switch (_direction) {
      _StrategyDirection.long => {StrategySide.long},
      _StrategyDirection.short => {StrategySide.short},
      _StrategyDirection.both => {StrategySide.long, StrategySide.short},
    };
    final candidate = switch (_candidateDirection) {
      _StrategyDirection.long => {StrategySide.long},
      _StrategyDirection.short => {StrategySide.short},
      _StrategyDirection.both => {StrategySide.long, StrategySide.short},
    };
    return current.intersection(candidate);
  }

  bool get _candidateDirectionIsFixed =>
      _isReviewingCandidates && _candidateDirection != _StrategyDirection.both;

  void _toggleLevel(StrategySide side, StrategyLevel level, bool selected) {
    final parsedPrice = StrategyDecimal.tryParse(level.priceText);
    if (selected && (parsedPrice == null || !parsedPrice.isPositive)) return;
    final item = StrategySelectedLevel(
      side: side,
      price: level.price,
      exactPriceText: level.priceText,
      levelId: level.id,
    );
    setState(() {
      if (selected) {
        if (_selected.length >= strategyNewSubmissionOrderLimit) {
          _workflowError =
              'Một chiến thuật chỉ được chọn tối đa $strategyNewSubmissionOrderLimit lệnh.';
          return;
        }
        _selected[item.id] = item;
        _entries.putIfAbsent(side, () => item.id);
        _moveEntriesToNearest();
      } else {
        _selected.remove(item.id);
        if (_entries[side] == item.id) _entries.remove(side);
        _moveEntriesToNearest();
      }
      _selectionNotice = null;
      _workflowError = null;
      _invalidatePreview();
    });
  }

  void _chooseEntry(StrategySide side, String levelId) {
    if (!_selected.values.any(
      (item) => item.side == side && item.id == levelId,
    )) {
      return;
    }
    setState(() {
      _entries[side] = levelId;
      _selectionNotice = null;
      _workflowError = null;
      _invalidatePreview();
    });
  }

  void _moveEntriesToNearest() {
    final referenceText = _snapshot?.ticker.priceText;
    final reference = StrategyDecimal.tryParse(referenceText);
    if (reference == null || !reference.isPositive) return;
    for (final side in _allowedSides) {
      final choices = _selected.values
          .where((item) => item.side == side)
          .toList();
      if (choices.isEmpty) {
        _entries.remove(side);
        continue;
      }
      choices.sort((left, right) {
        final leftPrice = StrategyDecimal.tryParse(left.priceText)!;
        final rightPrice = StrategyDecimal.tryParse(right.priceText)!;
        final leftDistance = (leftPrice - reference).abs();
        final rightDistance = (rightPrice - reference).abs();
        final distance = leftDistance.compareTo(rightDistance);
        return distance != 0 ? distance : left.id.compareTo(right.id);
      });
      final currentEntry = choices.where((item) => item.id == _entries[side]);
      if (currentEntry.isEmpty) {
        _entries[side] = choices.first.id;
      } else {
        final currentPrice = StrategyDecimal.tryParse(
          currentEntry.first.priceText,
        )!;
        if ((currentPrice - reference).abs().compareTo(
              (StrategyDecimal.tryParse(choices.first.priceText)! - reference)
                  .abs(),
            ) >
            0) {
          _entries[side] = choices.first.id;
        }
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
        referencePriceText: snapshot.ticker.priceText,
        direction: switch (_direction) {
          _StrategyDirection.long => StrategyDirection.long,
          _StrategyDirection.short => StrategyDirection.short,
          _StrategyDirection.both => StrategyDirection.both,
        },
        selectedLevels: _selected.values.toList(growable: false),
        entryLevelIdBySide: Map.of(_entries),
      );
      return selection;
    } on StrategySelectionException {
      return null;
    }
  }

  void _invalidatePreview() {
    _inputGeneration++;
    _preview = null;
    _previewHash = null;
    _savedDraftId = null;
  }

  String? _validateBudget() {
    final margin = _positiveStrategyDecimal(_marginController.text);
    if (margin == null) {
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
      final longPercent = _positiveStrategyDecimal(_longPercentController.text);
      if (longPercent == null || longPercent >= 100) {
        return 'Tỷ lệ Long phải lớn hơn 0% và nhỏ hơn 100%.';
      }
    }
    return null;
  }

  Future<void> _requestPreview() async {
    if (!_isSessionCurrent) return;
    final selection = _selectionOrNull();
    if (selection == null) {
      setState(
        () => _workflowError =
            'Chọn ít nhất một mức và một điểm vào gần giá nhất cho mỗi phía.',
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
      final normalizedLongPercent = _normalizeStrategyDecimalInput(
        _longPercentController.text,
      )!;
      final long = double.parse(normalizedLongPercent);
      sidePercent[StrategySide.long] = normalizedLongPercent;
      sidePercent[StrategySide.short] = (100 - long).toString();
    }
    final request = selection.toRequestJson(
      totalMargin: _normalizeStrategyDecimalInput(_marginController.text)!,
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
      if (!mounted || !_isSessionCurrent) return;
      final hash = _text(preview['previewHash']);
      final orders = _list(preview['orders']);
      if (hash.isEmpty ||
          orders.isEmpty ||
          orders.length > strategyNewSubmissionOrderLimit) {
        throw const StrategyApiException(
          code: 'invalid_response',
          message:
              'Máy chủ chưa trả về bản xem trước hợp lệ trong giới hạn 10 lệnh.',
        );
      }
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
      if (!mounted || !_isSessionCurrent) return;
      if (error.isUnauthorized) {
        ref.read(tradeSessionProvider.notifier).expire();
      }
      setState(() {
        _isRequestingPreview = false;
        _workflowError = error.message;
      });
    } on Object catch (error) {
      if (!mounted || !_isSessionCurrent) return;
      setState(() {
        _isRequestingPreview = false;
        _workflowError = _safeError(error);
      });
    }
  }

  int _step = 0;

  Map<String, dynamic> _saveBody() {
    final selection = _selectionOrNull();
    if (selection == null || !_hasValidNewSubmissionPreview) {
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
      final normalizedLongPercent = _normalizeStrategyDecimalInput(
        _longPercentController.text,
      )!;
      final long = double.parse(normalizedLongPercent);
      sidePercent[StrategySide.long] = normalizedLongPercent;
      sidePercent[StrategySide.short] = (100 - long).toString();
    }
    final body = <String, dynamic>{
      ...selection.toRequestJson(
        totalMargin: _normalizeStrategyDecimalInput(_marginController.text)!,
        leverage: leverage,
        sidePercent: sidePercent,
        allocation: _allocation,
      ),
      'previewHash': _previewHash!,
    };
    final sourceId = widget.replacementSourceId?.trim();
    if (sourceId != null && sourceId.isNotEmpty) {
      body['replacementSourceId'] = sourceId;
    }
    final candidateDraftId = _candidateDraftId;
    if (candidateDraftId != null) {
      body['candidateDraftId'] = candidateDraftId;
    }
    return body;
  }

  Future<String> _saveForApply() async {
    final existingId = _savedDraftId;
    if (existingId != null) return existingId;
    final saved = await ref
        .read(strategyApiProvider)
        .saveDraft(widget.session.bearerToken, _saveBody());
    if (!_isSessionCurrent) throw StateError('The trade session changed.');
    final id = _text(saved['id']);
    if (id.isEmpty) {
      throw const StrategyApiException(
        code: 'invalid_response',
        message: 'Máy chủ chưa trả về mã bản nháp.',
      );
    }
    _savedDraftId = id;
    await widget.onSaved();
    if (!_isSessionCurrent) throw StateError('The trade session changed.');
    return id;
  }

  Future<void> _saveDraft() async {
    if (!_canActOnPreview) return;
    setState(() {
      _isSaving = true;
      _isSavingDraft = true;
      _workflowError = null;
    });
    try {
      final saved = await ref
          .read(strategyApiProvider)
          .saveDraft(widget.session.bearerToken, _saveBody());
      if (!mounted || !_isSessionCurrent) return;
      if (_text(saved['id']).isEmpty) {
        throw const StrategyApiException(
          code: 'invalid_response',
          message: 'Máy chủ chưa trả về mã bản nháp.',
        );
      }
      await widget.onSaved();
      if (!mounted || !_isSessionCurrent) return;
      Navigator.of(context).pop();
      _message('Đã lưu bản nháp.');
    } on Object catch (error) {
      if (!mounted || !_isSessionCurrent) return;
      _expireSessionIfUnauthorized(error);
      setState(() {
        _isSaving = false;
        _isSavingDraft = false;
        _workflowError = _safeError(error);
      });
    }
  }

  Future<bool> _confirmPrepared(Map<String, dynamic> prepared) async {
    final orders = _preparedOrders(prepared);
    final mode = StrategyLimitOrderSubmissionMode.parse(
      prepared['submissionMode'],
    );
    if (orders.isEmpty || mode == null || !mounted || !_isSessionCurrent) {
      return false;
    }
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
                  'Đây là danh sách đã được máy chủ chuẩn hóa lại. Cơ chế gửi bên dưới đã được cố định cho danh sách này.',
                ),
                const SizedBox(height: 8),
                _SubmissionModeSummary(mode: mode),
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
          Consumer(
            builder: (context, ref, _) {
              final state = ref.watch(tradeSessionProvider);
              final ownsSession =
                  state.isAuthenticated &&
                  state.session?.bearerToken == widget.session.bearerToken &&
                  widget.dashboard.ownsSession;
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
    );
    return confirmed == true && mounted && _isSessionCurrent;
  }

  Future<void> _applyNow() async {
    if (!_canActOnPreview) return;
    setState(() {
      _isSaving = true;
      _isSavingDraft = false;
      _workflowError = null;
    });
    try {
      final id = await _saveForApply();
      if (!mounted || !_isSessionCurrent) return;
      final outcome = await widget.dashboard.applyDraft(
        id,
        confirm: _confirmPrepared,
      );
      if (!mounted || !_isSessionCurrent) return;
      await widget.onSaved();
      if (!mounted || !_isSessionCurrent) return;
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
      if (outcome.kind == StrategyApplyOutcomeKind.queued) {
        Navigator.of(context).pop();
        _message(
          outcome.message ?? 'Các lệnh đã được đưa vào hàng đợi tuần tự.',
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
      if (outcome.result?['replacementCleanupConflict'] == true) {
        _message(
          'OKX đã chấp nhận đầy đủ lệnh thay thế, nhưng hệ thống chưa xóa được chiến thuật cũ.',
        );
      } else {
        _message(
          status == 'APPLIED'
              ? 'Máy chủ đã chấp nhận lệnh chiến thuật.'
              : 'Trạng thái chiến thuật: ${status.isEmpty ? 'đang cập nhật' : status}.',
        );
      }
    } on Object catch (error) {
      if (!mounted || !_isSessionCurrent) return;
      _expireSessionIfUnauthorized(error);
      setState(() {
        _isSaving = false;
        _isSavingDraft = false;
        _workflowError = _safeError(error);
      });
    }
  }

  bool get _canActOnPreview =>
      _isSessionCurrent &&
      !_isSaving &&
      !_isRequestingPreview &&
      _hasValidNewSubmissionPreview;

  bool get _hasValidNewSubmissionPreview {
    final preview = _preview;
    final hash = _previewHash;
    if (preview == null || hash == null || hash.isEmpty) return false;
    final orders = _list(preview['orders']);
    return orders.isNotEmpty &&
        orders.length <= strategyNewSubmissionOrderLimit &&
        _selectionOrNull() != null;
  }

  void _message(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(tradeSessionProvider);
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
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ResponsiveFormContent(
                  maxWidth: 760,
                  padding: EdgeInsets.zero,
                  child: switch (_step) {
                    0 => _buildSelectionStep(context),
                    1 => _buildBudgetStep(context),
                    _ => _buildReviewStep(context),
                  },
                ),
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

  Future<void> _openInstrumentPicker() async {
    if (_isLoadingInstruments || _isLoadingLevels || _isSaving) return;
    final instrumentId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _StrategyInstrumentPicker(instruments: _instruments),
    );
    if (!mounted || instrumentId == null || instrumentId == _instrumentId) {
      return;
    }
    await _loadLevels(instrumentId, _interval);
  }

  Widget _buildSelectionStep(BuildContext context) {
    final snapshot = _snapshot;
    final pickerEnabled =
        !_isReviewingCandidates &&
        !_isLoadingInstruments &&
        !_isLoadingLevels &&
        !_isSaving;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          key: const Key('strategy-instrument-picker'),
          onTap: pickerEnabled ? _openInstrumentPicker : null,
          borderRadius: BorderRadius.circular(4),
          child: InputDecorator(
            key: const Key('strategy-instrument-selected'),
            isEmpty: _instrumentId == null,
            decoration: InputDecoration(
              labelText: 'Hợp đồng USDT SWAP',
              floatingLabelBehavior: FloatingLabelBehavior.always,
              enabled: pickerEnabled,
              suffixIcon: const Icon(Icons.search),
            ),
            child: Text(_instrumentId ?? 'Chọn hợp đồng'),
          ),
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
          onChanged: _isLoadingLevels || _isSaving || _isReviewingCandidates
              ? null
              : (value) {
                  if (value != null && _instrumentId != null) {
                    unawaited(_loadLevels(_instrumentId!, value));
                  }
                },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<_StrategyDirection>(
          isExpanded: true,
          key: const Key('strategy-direction-select'),
          value: _direction,
          decoration: const InputDecoration(labelText: 'Phía giao dịch'),
          items: !_candidateScopeValid
              ? [
                  DropdownMenuItem(
                    value: _direction,
                    child: const Text('Không rõ chiều'),
                  ),
                ]
              : [
                  for (final direction in _StrategyDirection.values)
                    if (!_candidateDirectionIsFixed ||
                        direction == _candidateDirection)
                      DropdownMenuItem(
                        value: direction,
                        child: Text(switch (direction) {
                          _StrategyDirection.long => 'Long',
                          _StrategyDirection.short => 'Short',
                          _StrategyDirection.both => 'Long&Short',
                        }),
                      ),
                ],
          onChanged:
              _isSaving || _candidateDirectionIsFixed || !_candidateScopeValid
              ? null
              : (value) {
                  if (value != null) _changeDirection(value);
                },
        ),
        const SizedBox(height: 12),
        if (_isLoadingInstruments || _isLoadingLevels)
          FormPendingStatus(
            label: _isLoadingInstruments
                ? 'Đang tải danh sách hợp đồng…'
                : 'Đang tải mức giá…',
          ),
        if (_marketError != null)
          _WizardNotice(
            message: _marketError!,
            error: true,
            onRetry: _isReviewingCandidates ? null : _loadInstruments,
          ),
        if (snapshot != null) ...[
          _quoteBanner(snapshot.ticker),
          const SizedBox(height: 8),
          Text(
            'Đã chọn ${_selected.length}/$strategyNewSubmissionOrderLimit lệnh · Long ${_selected.values.where((item) => item.side == StrategySide.long).length} · Short ${_selected.values.where((item) => item.side == StrategySide.short).length}',
            key: const Key('strategy-selection-count'),
          ),
          const SizedBox(height: 8),
          Text(
            _isReviewingCandidates
                ? 'Bản chụp ứng viên đã lưu lúc ${_dateTime(snapshot.ticker.observedAt)}'
                : '${snapshot.candles.length} nến UTC đã xác nhận · tối đa 500',
          ),
          if (!_isReviewingCandidates && snapshot.candles.length < 5)
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
          if (_isReviewingCandidates &&
              snapshot.analysis.supports.isEmpty &&
              snapshot.analysis.resistances.isEmpty)
            const _WizardNotice(
              message:
                  'Bản chụp đã lưu không có mức hỗ trợ hoặc kháng cự để chọn.',
            )
          else if (!_isLoadingLevels && _selectionOrNull() == null)
            _WizardNotice(
              message: _direction == _StrategyDirection.both
                  ? 'Chọn ít nhất một mức Long và một mức Short, cùng điểm vào gần nhất cho mỗi phía.'
                  : 'Chọn ít nhất một mức hợp lệ và điểm vào gần giá nhất cho mỗi phía.',
              error: true,
            ),
          if (_selectionNotice != null)
            _WizardNotice(message: _selectionNotice!),
        ],
        if (_workflowError != null)
          _WizardNotice(message: _workflowError!, error: true),
      ],
    );
  }

  Widget _quoteBanner(StrategyTicker ticker) {
    return Card(
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.schedule),
        title: Text(
          'Giá tham chiếu ${StrategyNumberFormatter.amount(ticker.priceText)} USDT',
        ),
        subtitle: Text(
          'Báo giá tham chiếu lúc ${_dateTime(ticker.observedAt)}',
        ),
      ),
    );
  }

  Widget _buildSideLevels(
    BuildContext context,
    StrategySide side,
    List<StrategyLevel> levels,
  ) {
    final selectedLevels = _selected.values
        .where((item) => item.side == side)
        .toList(growable: false);
    final reference = StrategyDecimal.tryParse(_snapshot!.ticker.priceText)!;
    final selectedDistances = <String, StrategyDecimal>{
      for (final item in selectedLevels)
        item.id: (StrategyDecimal.tryParse(item.priceText)! - reference).abs(),
    };
    StrategyDecimal? nearestDistance;
    for (final distance in selectedDistances.values) {
      if (nearestDistance == null || distance.compareTo(nearestDistance) < 0) {
        nearestDistance = distance;
      }
    }
    final nearestIds = {
      for (final entry in selectedDistances.entries)
        if (entry.value.compareTo(nearestDistance ?? entry.value) == 0)
          entry.key,
    };
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
                candidateAssessment: _candidateAssessments[level.id],
                candidateRank: _candidateRanks[level.id],
                referencePrice: _snapshot!.ticker.lastPrice,
                selected: _selected.containsKey(level.id),
                entryLevelId: _entries[side],
                canBeEntry: nearestIds.contains(level.id),
                onSelected: (selected) => _toggleLevel(side, level, selected),
                onEntry: () => _chooseEntry(side, level.id),
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
            key: const Key('strategy-long-percent-input'),
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
          isExpanded: true,
          itemHeight: null,
          value: _allocation,
          decoration: const InputDecoration(labelText: 'Phân bổ giữa các lệnh'),
          selectedItemBuilder: (context) => const [
            _AllocationSelectedLabel('Đều nhau'),
            _AllocationSelectedLabel('Tăng dần từ điểm vào'),
            _AllocationSelectedLabel('Giảm dần từ điểm vào'),
          ],
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
    final normalized = _normalizeStrategyDecimalInput(
      _longPercentController.text,
    );
    final long = normalized == null ? 50 : double.tryParse(normalized) ?? 50;
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
        Text(
          'Giá thị trường lúc xem: ${StrategyNumberFormatter.amount(preview['currentPrice'], placeholder: '')}',
        ),
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
    child: Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppTokens.space2,
      runSpacing: AppTokens.space2,
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
        if (_step == 0)
          FilledButton(
            key: const Key('strategy-next-step-one'),
            onPressed: !_isSessionCurrent || _selectionOrNull() == null
                ? null
                : () => setState(() {
                    _step = 1;
                    _workflowError = null;
                  }),
            child: const Text('Tiếp theo'),
          )
        else if (_step == 1)
          AsyncFormButton(
            key: const Key('strategy-request-preview'),
            onPressed: !_isSessionCurrent || _isRequestingPreview
                ? null
                : _requestPreview,
            isBusy: _isRequestingPreview,
            label: 'Xem lại lệnh',
            busyLabel: 'Đang tính bản xem trước…',
          )
        else ...[
          AsyncFormButton(
            key: const Key('strategy-save-draft'),
            onPressed: _canActOnPreview ? _saveDraft : null,
            isBusy: _isSavingDraft,
            label: 'Lưu bản nháp',
            busyLabel: 'Đang lưu bản nháp…',
            outlined: true,
          ),
          AsyncFormButton(
            key: const Key('strategy-apply-now'),
            onPressed: _canActOnPreview ? _applyNow : null,
            isBusy: _isSaving && !_isSavingDraft,
            label: 'Áp dụng ngay',
            busyLabel: 'Đang áp dụng…',
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

class _StrategyInstrumentPicker extends StatefulWidget {
  const _StrategyInstrumentPicker({required this.instruments});

  final List<StrategyInstrument> instruments;

  @override
  State<_StrategyInstrumentPicker> createState() =>
      _StrategyInstrumentPickerState();
}

class _StrategyInstrumentPickerState extends State<_StrategyInstrumentPicker> {
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
                    key: const Key('strategy-instrument-picker-close'),
                    tooltip: 'Đóng',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              TextField(
                key: const Key('strategy-instrument-search'),
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
                              'strategy-instrument-option-${instrument.instrumentId}',
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

class _StrategyLevelCard extends StatelessWidget {
  const _StrategyLevelCard({
    super.key,
    required this.side,
    required this.level,
    this.candidateAssessment,
    this.candidateRank,
    required this.referencePrice,
    required this.selected,
    required this.entryLevelId,
    required this.canBeEntry,
    required this.onSelected,
    required this.onEntry,
  });

  final StrategySide side;
  final StrategyLevel level;
  final Map<String, dynamic>? candidateAssessment;
  final int? candidateRank;
  final double referencePrice;
  final bool selected;
  final String? entryLevelId;
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
            onChanged: level.price > 0
                ? (value) => onSelected(value ?? false)
                : null,
            title: Text(
              '${StrategyNumberFormatter.amount(level.priceText)} USDT',
            ),
            subtitle: Text(
              '${StrategyNumberFormatter.amount(distance)} · ${StrategyNumberFormatter.percent(percent)}% · ${level.touchCount} lần',
            ),
            secondary: Icon(
              side == StrategySide.long ? Icons.south : Icons.north,
            ),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          if (level.price == 0)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Mức giá bằng 0 nên không thể chọn làm lệnh.'),
              ),
            ),
          if (candidateRank != null && candidateAssessment != null)
            _CandidateAssessmentSummary(
              rank: candidateRank!,
              assessment: candidateAssessment!,
            ),
          if (selected)
            RadioListTile<String>(
              value: level.id,
              groupValue: entryLevelId,
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

class _CandidateAssessmentSummary extends StatelessWidget {
  const _CandidateAssessmentSummary({
    required this.rank,
    required this.assessment,
  });

  final int rank;
  final Map<String, dynamic> assessment;

  @override
  Widget build(BuildContext context) {
    final status = _text(assessment['status']);
    final statusLabel = switch (status) {
      'success' => 'Jev: đã đánh giá',
      'disabled' => 'Jev: chưa bật',
      'failed' => 'Jev: đánh giá không thành công',
      _ => 'Jev: chưa có dữ liệu',
    };
    final quality = _finiteInRange(assessment['structuralQuality'], 0, 5);
    final suitability = _finiteInRange(
      assessment['entrySuitabilityProbability'],
      0,
      1,
    );
    final failureRisk = _finiteInRange(
      assessment['failureRiskProbability'],
      0,
      1,
    );
    final errorCode = _text(assessment['errorCode']);
    final safeErrorCode = RegExp(r'^[A-Za-z0-9_-]{1,32}$').hasMatch(errorCode)
        ? errorCode
        : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hạng Jev: $rank'),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(statusLabel),
              Text(
                'Chất lượng: ${quality == null ? 'chưa có' : '${quality.toStringAsFixed(1)}/5'}',
              ),
              Text(
                'Phù hợp điểm vào: ${suitability == null ? 'chưa có' : '${(suitability * 100).toStringAsFixed(1)}%'}',
              ),
              Text(
                'Rủi ro thất bại: ${failureRisk == null ? 'chưa có' : '${(failureRisk * 100).toStringAsFixed(1)}%'}',
              ),
            ],
          ),
          if (safeErrorCode.isNotEmpty) Text('Mã đánh giá: $safeErrorCode'),
        ],
      ),
    );
  }
}

double? _finiteInRange(Object? value, double minimum, double maximum) {
  final parsed = value is num
      ? value.toDouble()
      : double.tryParse(_text(value));
  if (parsed == null ||
      !parsed.isFinite ||
      parsed < minimum ||
      parsed > maximum) {
    return null;
  }
  return parsed;
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
        : StrategyNumberFormatter.amount(
            liquidation['price'],
            placeholder: 'chưa có dữ liệu',
          );
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
              'Giá giới hạn ${StrategyNumberFormatter.amount(order['limitPrice'], placeholder: '—')} · Hợp đồng ${StrategyNumberFormatter.amount(order['contracts'], placeholder: '—')}',
            ),
            Text(
              'Ký quỹ ${StrategyNumberFormatter.amount(order['margin'], placeholder: '—')} · Đòn bẩy ${_text(order['leverage'])}x',
            ),
            Text(
              'Phí mở ước tính ${StrategyNumberFormatter.amount(order['openingFeeEstimate'], placeholder: '—')} · ngoài ngân sách ký quỹ',
            ),
            Text(
              'Giá vốn lũy kế ${StrategyNumberFormatter.amount(order['cumulativeAverageEntry'], placeholder: '—')}',
            ),
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
      '${_text(order['side']).toUpperCase()} · ${_text(order['role'])} · ${StrategyNumberFormatter.amount(order['limitPrice'], placeholder: '—')}',
    ),
    subtitle: Text(
      'Contr ${StrategyNumberFormatter.amount(order['contracts'], placeholder: '—')} · Margin ${StrategyNumberFormatter.amount(order['margin'], placeholder: '—')} · ${_text(order['leverage'])}x',
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
              Text(
                '${entry.key}: ${entry.value is bool ? entry.value : StrategyNumberFormatter.amount(entry.value, placeholder: '—')}',
              ),
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

class _AllocationSelectedLabel extends StatelessWidget {
  const _AllocationSelectedLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: ExcludeSemantics(
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
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

String? _normalizeStrategyDecimalInput(String input) {
  final value = input.trim();
  if (!RegExp(r'^(?:\d+(?:[.,]\d+)?|[.,]\d+)$').hasMatch(value)) {
    return null;
  }
  if (value.contains(',') && RegExp(r'^\d{1,3}(?:,\d{3})+$').hasMatch(value)) {
    return null;
  }
  return value.replaceAll(',', '.');
}

double? _positiveStrategyDecimal(String input) {
  final normalized = _normalizeStrategyDecimalInput(input);
  if (normalized == null) return null;
  final value = double.tryParse(normalized);
  return value != null && value.isFinite && value > 0 ? value : null;
}

List<Map<String, dynamic>> _preparedOrders(Map<String, dynamic> prepared) {
  return validatedNewStrategyOrders(prepared) ?? const [];
}

List<Object?> _list(Object? value) =>
    value is List ? List<Object?>.from(value) : const [];

Map<String, dynamic> _asMap(Object? value) => value is Map
    ? value.map((key, item) => MapEntry(key.toString(), item))
    : const {};

String _text(Object? value) => value == null ? '' : value.toString();

String _dateTime(DateTime value) {
  final local = value.toLocal();
  String two(int item) => item.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
