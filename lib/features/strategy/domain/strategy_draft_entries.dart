import 'strategy_models.dart';
import 'strategy_settings.dart';

enum StrategyDraftEntriesIssue {
  none,
  legacy,
  invalid,
  noCandidates,
  disabled,
  failed,
  disabledAndFailed,
  noneQualified,
  partialDisabled,
  partialFailed,
  partialDisabledAndFailed,
}

class StrategyDraftEntry {
  const StrategyDraftEntry({
    required this.side,
    required this.levelId,
    required this.exactPrice,
  });

  final StrategySide side;
  final String levelId;
  final StrategyDecimal exactPrice;

  String get exactPriceText => exactPrice.toString();
}

/// Validates and exposes the immutable recommendation saved with a candidate
/// Draft. It never ranks candidates or recalculates their recommendation.
class StrategyDraftEntries {
  const StrategyDraftEntries._({
    required this.entries,
    required this.issue,
    required this.candidateCount,
    required this.successCount,
    required this.disabledCount,
    required this.failedCount,
  });

  static const _legacy = StrategyDraftEntries._(
    entries: <StrategyDraftEntry>[],
    issue: StrategyDraftEntriesIssue.legacy,
    candidateCount: 0,
    successCount: 0,
    disabledCount: 0,
    failedCount: 0,
  );

  static const _invalid = StrategyDraftEntries._(
    entries: <StrategyDraftEntry>[],
    issue: StrategyDraftEntriesIssue.invalid,
    candidateCount: 0,
    successCount: 0,
    disabledCount: 0,
    failedCount: 0,
  );

  final List<StrategyDraftEntry> entries;
  final StrategyDraftEntriesIssue issue;
  final int candidateCount;
  final int successCount;
  final int disabledCount;
  final int failedCount;

  int get longCount =>
      entries.where((entry) => entry.side == StrategySide.long).length;
  int get shortCount =>
      entries.where((entry) => entry.side == StrategySide.short).length;

  List<StrategyDraftEntry> entriesFor(StrategySide side) =>
      List<StrategyDraftEntry>.unmodifiable(
        entries.where((entry) => entry.side == side),
      );

  String? get notice => switch (issue) {
    StrategyDraftEntriesIssue.none => null,
    StrategyDraftEntriesIssue.legacy =>
      'Bản nháp cũ không có đề xuất Jev đã lưu. Bạn có thể chọn mức thủ công khi xem xét.',
    StrategyDraftEntriesIssue.invalid =>
      'Đề xuất Jev đã lưu không hợp lệ; không có mức nào được hiển thị. Bạn có thể chọn thủ công khi xem xét.',
    StrategyDraftEntriesIssue.noCandidates =>
      'Bản nháp không có ứng viên để đánh giá; bạn có thể chọn mức thủ công khi xem xét.',
    StrategyDraftEntriesIssue.disabled =>
      'Đánh giá Jev chưa khả dụng cho $disabledCount ứng viên (có thể do dịch vụ chưa bật hoặc cấu hình/SDK chưa sẵn sàng). Hãy kiểm tra dịch vụ, thử bản nháp mới hoặc chọn mức thủ công khi xem xét.',
    StrategyDraftEntriesIssue.failed =>
      'Đánh giá Jev thất bại cho $failedCount ứng viên; hiện chưa có mức được đề xuất. Hãy thử bản nháp mới hoặc chọn mức thủ công khi xem xét.',
    StrategyDraftEntriesIssue.disabledAndFailed =>
      'Đánh giá Jev chưa khả dụng cho $disabledCount ứng viên và thất bại cho $failedCount ứng viên; hiện chưa có mức được đề xuất. Hãy kiểm tra dịch vụ, thử bản nháp mới hoặc chọn mức thủ công khi xem xét.',
    StrategyDraftEntriesIssue.noneQualified =>
      'Không có ứng viên nào đạt tiêu chí Jev đã lưu; bạn có thể chọn mức thủ công khi xem xét.',
    StrategyDraftEntriesIssue.partialDisabled =>
      'Đánh giá Jev chưa khả dụng cho $disabledCount ứng viên (có thể do dịch vụ chưa bật hoặc cấu hình/SDK chưa sẵn sàng); các mức đã lưu vẫn cần bạn xem xét.',
    StrategyDraftEntriesIssue.partialFailed =>
      'Đánh giá Jev thất bại cho $failedCount ứng viên; các mức đã lưu vẫn cần bạn xem xét.',
    StrategyDraftEntriesIssue.partialDisabledAndFailed =>
      'Đánh giá Jev chưa khả dụng cho $disabledCount ứng viên và thất bại cho $failedCount ứng viên; các mức đã lưu vẫn cần bạn xem xét.',
  };

  factory StrategyDraftEntries.fromDraftRecord(Object? rawRecord) {
    final record = _strictStringMap(rawRecord);
    if (record == null) return _invalid;

    final directGeneration = _strictStringMap(record['aiGeneration']);
    final nestedGeneration = _strictStringMap(
      _strictStringMap(record['snapshot'])?['aiGeneration'],
    );
    final generation = directGeneration?.isNotEmpty == true
        ? directGeneration!
        : nestedGeneration;
    if (generation == null || generation.isEmpty) return _legacy;

    final draftId = _text(record['id']).trim();
    final instrumentId = _text(record['instrumentId']).isNotEmpty
        ? _text(record['instrumentId'])
        : _text(generation['instrumentId']);
    final intervalText = _text(record['interval']).isNotEmpty
        ? _text(record['interval'])
        : _text(generation['interval']);
    final reference = StrategyDecimal.tryParse(
      _text(generation['referencePrice']),
    );
    final evaluationSnapshot = _strictStringMap(
      generation['evaluationSnapshot'],
    );
    final observedAtText = _text(generation['observedAt']).isNotEmpty
        ? _text(generation['observedAt'])
        : _text(evaluationSnapshot?['observedAt']);
    final observedAt = DateTime.tryParse(observedAtText);
    if (draftId.isEmpty ||
        !RegExp(r'^[A-Z0-9]+-USDT-SWAP$').hasMatch(instrumentId) ||
        !const {'6Hutc', '1Dutc', '1Wutc'}.contains(intervalText) ||
        reference == null ||
        !reference.isPositive ||
        !reference.toDouble().isFinite ||
        observedAt == null ||
        !observedAt.isUtc) {
      return _invalid;
    }

    final supports = generation['supports'];
    final resistances = generation['resistances'];
    if (supports is! List || resistances is! List) return _invalid;

    final candidatesBySide = <StrategySide, Map<String, _Candidate>>{
      StrategySide.long: <String, _Candidate>{},
      StrategySide.short: <String, _Candidate>{},
    };
    var successCount = 0;
    var disabledCount = 0;
    var failedCount = 0;
    for (final (rawCandidates, side) in [
      (supports, StrategySide.long),
      (resistances, StrategySide.short),
    ]) {
      for (final rawCandidate in rawCandidates) {
        final candidate = _strictStringMap(rawCandidate);
        final levelId = candidate?['levelId'];
        final price = StrategyDecimal.tryParse(_text(candidate?['price']));
        final firstTouchAt = DateTime.tryParse(
          _text(candidate?['firstTouchAt']),
        );
        final lastTouchAt = DateTime.tryParse(_text(candidate?['lastTouchAt']));
        final touchCount = candidate?['touchCount'];
        final generationOrder = candidate?['generationOrder'];
        final rank = candidate?['rank'];
        if (candidate == null ||
            levelId is! String ||
            !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(levelId) ||
            price == null ||
            price.coefficient.isNegative ||
            (price.coefficient == BigInt.zero && side != StrategySide.long) ||
            candidate['side'] != side.wireValue ||
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
            candidatesBySide.values.any(
              (levels) => levels.containsKey(levelId),
            )) {
          return _invalid;
        }

        final assessment = _strictStringMap(candidate['assessment']);
        if (assessment == null) return _invalid;
        final assessmentStatus = _text(assessment['status']);
        if (assessmentStatus == 'success') {
          successCount++;
        } else if (assessmentStatus == 'disabled') {
          disabledCount++;
        } else {
          failedCount++;
        }
        candidatesBySide[side]![levelId] = _Candidate(
          exactPrice: price,
          assessment: assessment,
        );
      }
    }

    final rawRecommendation = generation['recommendation'];
    if (rawRecommendation == null) return _legacy;
    final recommendation = _strictStringMap(rawRecommendation);
    if (recommendation == null ||
        recommendation['version'] != 'ai-jev-selection-v1' ||
        recommendation['maxPerSide'] != 5 ||
        StrategyJevScreeningThresholds.tryParseSnapshot(recommendation) ==
            null) {
      return _invalid;
    }

    final rawLongIds = recommendation['longLevelIds'];
    final rawShortIds = recommendation['shortLevelIds'];
    if (rawLongIds is! List ||
        rawShortIds is! List ||
        !rawLongIds.every((id) => id is String) ||
        !rawShortIds.every((id) => id is String) ||
        rawLongIds.length > 5 ||
        rawShortIds.length > 5) {
      return _invalid;
    }
    final longIds = List<String>.from(rawLongIds);
    final shortIds = List<String>.from(rawShortIds);
    final allIds = [...longIds, ...shortIds];
    if (allIds.toSet().length != allIds.length) return _invalid;

    final entries = <StrategyDraftEntry>[];
    for (final (ids, side) in [
      (longIds, StrategySide.long),
      (shortIds, StrategySide.short),
    ]) {
      for (final id in ids) {
        final candidate = candidatesBySide[side]![id];
        if (candidate == null ||
            !candidate.exactPrice.isPositive ||
            !_hasValidSuccessfulAssessment(candidate.assessment)) {
          return _invalid;
        }
        entries.add(
          StrategyDraftEntry(
            side: side,
            levelId: id,
            exactPrice: candidate.exactPrice,
          ),
        );
      }
    }

    final issue = _issueFor(
      entries: entries,
      candidateCount: successCount + disabledCount + failedCount,
      successCount: successCount,
      disabledCount: disabledCount,
      failedCount: failedCount,
    );
    return StrategyDraftEntries._(
      entries: List<StrategyDraftEntry>.unmodifiable(entries),
      issue: issue,
      candidateCount: successCount + disabledCount + failedCount,
      successCount: successCount,
      disabledCount: disabledCount,
      failedCount: failedCount,
    );
  }

  static StrategyDraftEntriesIssue _issueFor({
    required List<StrategyDraftEntry> entries,
    required int candidateCount,
    required int successCount,
    required int disabledCount,
    required int failedCount,
  }) {
    if (entries.isEmpty) {
      if (candidateCount == 0) return StrategyDraftEntriesIssue.noCandidates;
      if (disabledCount > 0 && failedCount > 0) {
        return StrategyDraftEntriesIssue.disabledAndFailed;
      }
      if (disabledCount > 0) return StrategyDraftEntriesIssue.disabled;
      if (failedCount > 0) return StrategyDraftEntriesIssue.failed;
      if (successCount > 0) return StrategyDraftEntriesIssue.noneQualified;
      return StrategyDraftEntriesIssue.failed;
    }
    if (disabledCount > 0 && failedCount > 0) {
      return StrategyDraftEntriesIssue.partialDisabledAndFailed;
    }
    if (disabledCount > 0) return StrategyDraftEntriesIssue.partialDisabled;
    if (failedCount > 0) return StrategyDraftEntriesIssue.partialFailed;
    return StrategyDraftEntriesIssue.none;
  }

  static bool _hasValidSuccessfulAssessment(Map<String, dynamic> assessment) {
    if (assessment['status'] != 'success') return false;
    return _finiteInRange(assessment['structuralQuality'], 0, 5) != null &&
        _finiteInRange(assessment['entrySuitabilityProbability'], 0, 1) !=
            null &&
        _finiteInRange(assessment['failureRiskProbability'], 0, 1) != null;
  }

  static double? _finiteInRange(Object? value, double minimum, double maximum) {
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
}

class _Candidate {
  const _Candidate({required this.exactPrice, required this.assessment});

  final StrategyDecimal exactPrice;
  final Map<String, dynamic> assessment;
}

Map<String, dynamic>? _strictStringMap(Object? value) =>
    value is Map && value.keys.every((key) => key is String)
    ? Map<String, dynamic>.from(value)
    : null;

String _text(Object? value) => value == null ? '' : value.toString();
