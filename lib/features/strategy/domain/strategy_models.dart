class StrategyDecimal implements Comparable<StrategyDecimal> {
  const StrategyDecimal._(this.coefficient, this.scale);

  static final _pattern = RegExp(
    r'^([+-]?)(?:(\d+)(?:\.(\d*))?|\.(\d+))(?:[eE]([+-]?\d+))?$',
  );
  static final _ten = BigInt.from(10);

  final BigInt coefficient;
  final int scale;

  static StrategyDecimal? tryParse(String? text) {
    if (text == null || text.length > 1024) return null;
    final match = _pattern.firstMatch(text.trim());
    if (match == null) return null;
    final whole = match.group(2) ?? '0';
    final fraction = match.group(3) ?? match.group(4) ?? '';
    final exponent = int.tryParse(match.group(5) ?? '0');
    if (exponent == null || exponent.abs() > 1024) return null;
    final digits = '$whole$fraction';
    final parsedCoefficient = BigInt.tryParse(digits);
    if (parsedCoefficient == null) return null;
    var coefficient = match.group(1) == '-'
        ? -parsedCoefficient
        : parsedCoefficient;
    var scale = fraction.length - exponent;
    if (scale < 0) {
      coefficient *= _powerOfTen(-scale);
      scale = 0;
    }
    return _normalized(coefficient, scale);
  }

  static StrategyDecimal _normalized(BigInt coefficient, int scale) {
    while (scale > 0 && coefficient.remainder(_ten) == BigInt.zero) {
      coefficient ~/= _ten;
      scale--;
    }
    return StrategyDecimal._(coefficient, scale);
  }

  static BigInt _powerOfTen(int power) => _ten.pow(power);

  bool get isPositive => coefficient > BigInt.zero;

  @override
  int compareTo(StrategyDecimal other) {
    final commonScale = scale > other.scale ? scale : other.scale;
    final left = coefficient * _powerOfTen(commonScale - scale);
    final right = other.coefficient * _powerOfTen(commonScale - other.scale);
    return left.compareTo(right);
  }

  StrategyDecimal operator +(StrategyDecimal other) {
    final commonScale = scale > other.scale ? scale : other.scale;
    final left = coefficient * _powerOfTen(commonScale - scale);
    final right = other.coefficient * _powerOfTen(commonScale - other.scale);
    return _normalized(left + right, commonScale);
  }

  StrategyDecimal operator -(StrategyDecimal other) {
    final commonScale = scale > other.scale ? scale : other.scale;
    final left = coefficient * _powerOfTen(commonScale - scale);
    final right = other.coefficient * _powerOfTen(commonScale - other.scale);
    return _normalized(left - right, commonScale);
  }

  StrategyDecimal abs() =>
      coefficient.isNegative ? StrategyDecimal._(-coefficient, scale) : this;

  StrategyDecimal multipliedBy(int multiplier) =>
      _normalized(coefficient * BigInt.from(multiplier), scale);

  StrategyDecimal dividedByTwo() =>
      _normalized(coefficient * BigInt.from(5), scale + 1);

  StrategyDecimal quantizedDownTo(StrategyDecimal tick) =>
      _quantizedTo(tick, roundUp: false);

  StrategyDecimal quantizedUpTo(StrategyDecimal tick) =>
      _quantizedTo(tick, roundUp: true);

  StrategyDecimal _quantizedTo(StrategyDecimal tick, {required bool roundUp}) {
    if (!tick.isPositive) throw ArgumentError.value(tick, 'tick');
    final commonScale = scale > tick.scale ? scale : tick.scale;
    final valueUnits = coefficient * _powerOfTen(commonScale - scale);
    final tickUnits = tick.coefficient * _powerOfTen(commonScale - tick.scale);
    var ticks = valueUnits ~/ tickUnits;
    final remainder = valueUnits.remainder(tickUnits);
    if (remainder != BigInt.zero) {
      if (roundUp && !valueUnits.isNegative) ticks += BigInt.one;
      if (!roundUp && valueUnits.isNegative) ticks -= BigInt.one;
    }
    return _normalized(ticks * tickUnits, commonScale);
  }

  double toDouble() => double.parse(toString());

  @override
  String toString() {
    final sign = coefficient.isNegative ? '-' : '';
    final digits = coefficient.abs().toString();
    if (scale == 0) return '$sign$digits';
    final padded = digits.length <= scale
        ? '${List.filled(scale + 1 - digits.length, '0').join()}$digits'
        : digits;
    final point = padded.length - scale;
    return '$sign${padded.substring(0, point)}.${padded.substring(point)}';
  }
}

enum StrategyInterval {
  h6('6H', '6Hutc', Duration(hours: 6)),
  h12('12H', '12Hutc', Duration(hours: 12)),
  d1('1D', '1Dutc', Duration(days: 1)),
  w1('1W', '1Wutc', Duration(days: 7));

  const StrategyInterval(this.label, this.bar, this.duration);

  final String label;
  final String bar;
  final Duration duration;

  bool isUtcAligned(DateTime timestamp) {
    if (!timestamp.isUtc || timestamp.microsecond != 0) return false;
    if (this == StrategyInterval.w1) {
      final mondayEpoch = DateTime.utc(1969, 12, 29).millisecondsSinceEpoch;
      return (timestamp.millisecondsSinceEpoch - mondayEpoch) %
              duration.inMilliseconds ==
          0;
    }
    return timestamp.millisecondsSinceEpoch % duration.inMilliseconds == 0;
  }
}

enum StrategySide {
  long('long', 'Long'),
  short('short', 'Short');

  const StrategySide(this.wireValue, this.label);

  final String wireValue;
  final String label;
}

enum StrategyAllocation { equal, increasing, decreasing }

enum StrategyLimitOrderSubmissionMode {
  sequential(
    'sequential',
    'Hàng đợi tuần tự',
    'Lệnh tiếp theo chỉ được gửi sau khi máy chủ xác nhận lệnh trước đã được nhận; xác nhận nhận lệnh không có nghĩa là lệnh đã khớp.',
  ),
  batch(
    'batch',
    'Gửi theo lô',
    'Các lệnh đã duyệt được gửi cùng nhau theo cơ chế gửi theo lô.',
  );

  const StrategyLimitOrderSubmissionMode(
    this.wireValue,
    this.label,
    this.explanation,
  );

  final String wireValue;
  final String label;
  final String explanation;

  static StrategyLimitOrderSubmissionMode? parse(Object? value) =>
      switch (value) {
        'sequential' => StrategyLimitOrderSubmissionMode.sequential,
        'batch' => StrategyLimitOrderSubmissionMode.batch,
        _ => null,
      };
}

class StrategyQueueProgress {
  const StrategyQueueProgress({
    required this.totalCount,
    required this.attemptedCount,
    required this.acceptedCount,
    required this.pendingCount,
    required this.notSubmittedCount,
  });

  final int totalCount;
  final int attemptedCount;
  final int acceptedCount;
  final int pendingCount;
  final int notSubmittedCount;
}

StrategyQueueProgress? validatedStrategyQueueProgress(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) return null;
  final total = value['totalCount'];
  final attempted = value['attemptedCount'];
  final accepted = value['acceptedCount'];
  final pending = value['pendingCount'];
  final notSubmitted = value['notSubmittedCount'];
  if (total is! int ||
      attempted is! int ||
      accepted is! int ||
      pending is! int ||
      notSubmitted is! int ||
      total < 0 ||
      attempted < 0 ||
      accepted < 0 ||
      pending < 0 ||
      notSubmitted < 0 ||
      total > 20 ||
      attempted > total ||
      accepted > total ||
      accepted > attempted ||
      pending > total ||
      notSubmitted > total ||
      attempted + pending + notSubmitted != total) {
    return null;
  }
  return StrategyQueueProgress(
    totalCount: total,
    attemptedCount: attempted,
    acceptedCount: accepted,
    pendingCount: pending,
    notSubmittedCount: notSubmitted,
  );
}

String? strategyQueueStatusLabel(Object? value) => switch (value) {
  'pending' => 'Đang chờ gửi',
  'sending' => 'Đang gửi',
  'stopped' => 'Đã dừng',
  'submitted' => 'Đã gửi hết lệnh',
  _ => null,
};

String? strategyPlacementStateLabel(Object? value) => switch (value) {
  'pending' || 'queued' => 'Đang xếp hàng',
  'sending' => 'Đang gửi',
  'accepted' => 'Đã được nhận',
  'rejected' => 'Bị từ chối',
  'unknown' => 'Chưa rõ kết quả gửi',
  'not_submitted' => 'Chưa gửi',
  _ => null,
};

class StrategyInstrument {
  const StrategyInstrument({
    required this.instrumentId,
    required this.base,
    this.tickSizeText,
  });

  final String instrumentId;
  final String base;
  final String? tickSizeText;
}

class StrategyTicker {
  const StrategyTicker({
    required this.instrumentId,
    required this.lastPrice,
    required this.observedAt,
    this.exactPriceText,
  });

  final String instrumentId;
  final double lastPrice;
  final DateTime observedAt;
  final String? exactPriceText;

  String get priceText => exactPriceText ?? lastPrice.toString();

  bool isFreshAt(
    DateTime now, {
    Duration maximumAge = const Duration(seconds: 4),
  }) {
    final age = now.toUtc().difference(observedAt.toUtc());
    return lastPrice.isFinite &&
        lastPrice > 0 &&
        !age.isNegative &&
        age <= maximumAge;
  }
}

class StrategyCandle {
  const StrategyCandle({
    required this.timestamp,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.interval,
    this.exactOpenText,
    this.exactHighText,
    this.exactLowText,
    this.exactCloseText,
  });

  final DateTime timestamp;
  final double open;
  final double high;
  final double low;
  final double close;
  final StrategyInterval interval;
  final String? exactOpenText;
  final String? exactHighText;
  final String? exactLowText;
  final String? exactCloseText;

  String get openText => exactOpenText ?? open.toString();
  String get highText => exactHighText ?? high.toString();
  String get lowText => exactLowText ?? low.toString();
  String get closeText => exactCloseText ?? close.toString();

  bool get hasValidPrices {
    if (!open.isFinite || !high.isFinite || !low.isFinite || !close.isFinite) {
      return false;
    }
    final exactOpen = StrategyDecimal.tryParse(openText);
    final exactHigh = StrategyDecimal.tryParse(highText);
    final exactLow = StrategyDecimal.tryParse(lowText);
    final exactClose = StrategyDecimal.tryParse(closeText);
    if (exactOpen == null ||
        exactHigh == null ||
        exactLow == null ||
        exactClose == null ||
        !exactOpen.isPositive ||
        !exactHigh.isPositive ||
        !exactLow.isPositive ||
        !exactClose.isPositive) {
      return false;
    }
    return exactHigh.compareTo(exactLow) >= 0 &&
        exactHigh.compareTo(exactOpen) >= 0 &&
        exactHigh.compareTo(exactClose) >= 0 &&
        exactLow.compareTo(exactOpen) <= 0 &&
        exactLow.compareTo(exactClose) <= 0;
  }
}

class StrategyLevel {
  const StrategyLevel({
    required this.price,
    required this.firstTouchAt,
    required this.lastTouchAt,
    required this.touchCount,
    required this.side,
    this.exactPriceText,
    this.levelId,
  });

  final double price;
  final DateTime firstTouchAt;
  final DateTime lastTouchAt;
  final int touchCount;
  final StrategySide side;
  final String? exactPriceText;
  final String? levelId;

  String get priceText {
    final text = exactPriceText ?? price.toString();
    return StrategyDecimal.tryParse(text)?.toString() ?? text;
  }

  String get id =>
      levelId ?? '${side.wireValue}_${firstTouchAt.millisecondsSinceEpoch}';
}

class StrategyAnalysis {
  const StrategyAnalysis({
    required this.referencePrice,
    required this.supports,
    required this.resistances,
    this.exactReferencePriceText,
  });

  final double referencePrice;
  final String? exactReferencePriceText;
  final List<StrategyLevel> supports;
  final List<StrategyLevel> resistances;
}

class StrategyMarketSnapshot {
  const StrategyMarketSnapshot({
    required this.instrumentId,
    required this.interval,
    required this.ticker,
    required this.candles,
    required this.analysis,
  });

  final String instrumentId;
  final StrategyInterval interval;
  final StrategyTicker ticker;
  final List<StrategyCandle> candles;
  final StrategyAnalysis analysis;
}

class StrategyMarketException implements Exception {
  const StrategyMarketException(this.message);

  final String message;

  @override
  String toString() => message;
}

String strategyNumber(Object? value) => value == null ? '' : value.toString();

class StrategyRetryCandidate {
  const StrategyRetryCandidate({
    required this.sourceClientOrderId,
    required this.side,
    required this.role,
    required this.limitPrice,
    required this.contracts,
    required this.leverage,
    required this.priorOutcome,
    required this.eligible,
    required this.reason,
    required this.levelId,
  });

  final String sourceClientOrderId;
  final String side;
  final String role;
  final String limitPrice;
  final String contracts;
  final String leverage;
  final String priorOutcome;
  final bool eligible;
  final String? reason;
  final String? levelId;

  static StrategyRetryCandidate? tryParse(Object? value) {
    final map = _retryStrictMap(value, const {
      'sourceClientOrderId',
      'side',
      'role',
      'limitPrice',
      'contracts',
      'leverage',
      'priorOutcome',
      'eligible',
      'reason',
      'levelId',
    });
    if (map == null ||
        !_retryHasKeys(map, const {
          'sourceClientOrderId',
          'side',
          'role',
          'limitPrice',
          'contracts',
          'leverage',
          'priorOutcome',
          'eligible',
          'reason',
        })) {
      return null;
    }
    final id = map['sourceClientOrderId'];
    final side = map['side'];
    final role = map['role'];
    final priorOutcome = map['priorOutcome'];
    final eligible = map['eligible'];
    final reasonValue = map['reason'];
    final levelIdValue = map['levelId'];
    final price = _retryDecimalText(map['limitPrice'], positive: true);
    final contracts = _retryDecimalText(map['contracts'], positive: true);
    final leverage = _retryDecimalText(map['leverage'], positive: true);
    final leverageDecimal = StrategyDecimal.tryParse(leverage ?? '');
    if (id is! String ||
        id.isEmpty ||
        id.length > 200 ||
        side is! String ||
        !const {'long', 'short'}.contains(side) ||
        role is! String ||
        !const {'entry', 'dca'}.contains(role) ||
        priorOutcome is! String ||
        !const {'not_submitted', 'rejected', 'other'}.contains(priorOutcome) ||
        eligible is! bool ||
        (eligible && priorOutcome == 'other') ||
        (reasonValue != null && reasonValue is! String) ||
        (levelIdValue != null && levelIdValue is! String) ||
        price == null ||
        contracts == null ||
        leverageDecimal == null ||
        !const {
          '1',
          '2',
          '3',
          '4',
          '5',
          '6',
          '7',
          '8',
          '9',
          '10',
        }.contains(leverageDecimal.toString())) {
      return null;
    }
    final reason = reasonValue as String?;
    if ((eligible && reason != null) ||
        (!eligible && (reason == null || reason.isEmpty))) {
      return null;
    }
    return StrategyRetryCandidate(
      sourceClientOrderId: id,
      side: side,
      role: role,
      limitPrice: price,
      contracts: contracts,
      leverage: leverageDecimal.toString(),
      priorOutcome: priorOutcome,
      eligible: eligible,
      reason: reason,
      levelId: levelIdValue as String?,
    );
  }
}

class StrategyRetryLinkedChild {
  const StrategyRetryLinkedChild({
    required this.strategyId,
    required this.status,
    required this.sourceClientOrderIds,
  });

  final String strategyId;
  final String status;
  final List<String> sourceClientOrderIds;

  static StrategyRetryLinkedChild? tryParse(Object? value) {
    final map = _retryStrictMap(value, const {
      'strategyId',
      'status',
      'sourceClientOrderIds',
    });
    final id = map?['strategyId'];
    final status = map?['status'];
    final ids = _retryStringList(map?['sourceClientOrderIds']);
    if (map == null ||
        !_retryHasKeys(map, const {
          'strategyId',
          'status',
          'sourceClientOrderIds',
        }) ||
        id is! String ||
        id.isEmpty ||
        status is! String ||
        status.isEmpty ||
        ids == null ||
        ids.isEmpty ||
        ids.toSet().length != ids.length) {
      return null;
    }
    return StrategyRetryLinkedChild(
      strategyId: id,
      status: status,
      sourceClientOrderIds: List.unmodifiable(ids),
    );
  }
}

class StrategyRetryCandidates {
  const StrategyRetryCandidates({
    required this.sourceStrategyId,
    required this.sourceRevision,
    required this.candidates,
    required this.blockedReason,
    required this.linkedChildren,
  });

  final String sourceStrategyId;
  final String sourceRevision;
  final List<StrategyRetryCandidate> candidates;
  final String? blockedReason;
  final List<StrategyRetryLinkedChild> linkedChildren;

  static StrategyRetryCandidates? tryParse(Object? value) {
    final map = _retryStrictMap(value, const {
      'sourceStrategyId',
      'sourceRevision',
      'candidates',
      'blockedReason',
      'linkedChildren',
    });
    if (map == null ||
        !_retryHasKeys(map, const {
          'sourceStrategyId',
          'sourceRevision',
          'candidates',
          'blockedReason',
          'linkedChildren',
        })) {
      return null;
    }
    final sourceId = map['sourceStrategyId'];
    final revision = map['sourceRevision'];
    final rawCandidates = map['candidates'];
    final blocked = map['blockedReason'];
    final rawChildren = map['linkedChildren'];
    if (sourceId is! String ||
        sourceId.isEmpty ||
        revision is! String ||
        revision.isEmpty ||
        rawCandidates is! List ||
        (blocked != null && (blocked is! String || blocked.isEmpty)) ||
        rawChildren is! List) {
      return null;
    }
    final candidates = rawCandidates
        .map(StrategyRetryCandidate.tryParse)
        .toList(growable: false);
    final children = rawChildren
        .map(StrategyRetryLinkedChild.tryParse)
        .toList(growable: false);
    if (candidates.any((candidate) => candidate == null) ||
        children.any((child) => child == null)) {
      return null;
    }
    final parsedCandidates = candidates.cast<StrategyRetryCandidate>();
    final parsedChildren = children.cast<StrategyRetryLinkedChild>();
    if (parsedCandidates
            .map((candidate) => candidate.sourceClientOrderId)
            .toSet()
            .length !=
        parsedCandidates.length) {
      return null;
    }
    return StrategyRetryCandidates(
      sourceStrategyId: sourceId,
      sourceRevision: revision,
      candidates: List.unmodifiable(parsedCandidates),
      blockedReason: blocked as String?,
      linkedChildren: List.unmodifiable(parsedChildren),
    );
  }
}

class StrategyRetryPreview {
  const StrategyRetryPreview({
    required this.sourceStrategyId,
    required this.sourceRevision,
    required this.selectedSourceClientOrderIds,
    required this.previewHash,
    required this.orders,
    required this.totalMargin,
    required this.plannedMargin,
    required this.unallocatedMargin,
    required this.estimatedOpeningFees,
    required this.requiredBalance,
    required this.raw,
  });

  final String sourceStrategyId;
  final String sourceRevision;
  final List<String> selectedSourceClientOrderIds;
  final String previewHash;
  final List<Map<String, dynamic>> orders;
  final String totalMargin;
  final String plannedMargin;
  final String unallocatedMargin;
  final String estimatedOpeningFees;
  final String requiredBalance;
  final Map<String, dynamic> raw;

  static StrategyRetryPreview? tryParse(Object? value) {
    final map = _retryStringKeyedMap(value);
    if (map == null ||
        !_retryHasKeys(map, const {
          'sourceStrategyId',
          'sourceRevision',
          'selectedSourceClientOrderIds',
          'previewHash',
          'orders',
          'totalMargin',
          'plannedMargin',
          'unallocatedMargin',
          'estimatedOpeningFees',
          'requiredBalance',
          'allocation',
          'feesOutsideMargin',
          'instrumentId',
          'interval',
          'currentPrice',
          'quoteTimestamp',
          'sidePercent',
          'sides',
        })) {
      return null;
    }
    final sourceId = map['sourceStrategyId'];
    final revision = map['sourceRevision'];
    final hash = map['previewHash'];
    final ids = _retryStringList(map['selectedSourceClientOrderIds']);
    final rawOrders = map['orders'];
    final totalMargin = _retryDecimalText(map['totalMargin'], positive: false);
    final plannedMargin = _retryDecimalText(
      map['plannedMargin'],
      positive: false,
    );
    final unallocatedMargin = _retryDecimalText(
      map['unallocatedMargin'],
      positive: false,
    );
    final openingFees = _retryDecimalText(
      map['estimatedOpeningFees'],
      positive: false,
    );
    final requiredBalance = _retryDecimalText(
      map['requiredBalance'],
      positive: false,
    );
    final instrumentId = map['instrumentId'];
    final interval = map['interval'];
    final currentPrice = _retryDecimalText(map['currentPrice'], positive: true);
    final quoteTimestamp = map['quoteTimestamp'];
    final sidePercent = map['sidePercent'];
    final sides = map['sides'];
    if (sourceId is! String ||
        sourceId.isEmpty ||
        revision is! String ||
        revision.isEmpty ||
        hash is! String ||
        hash.isEmpty ||
        ids == null ||
        ids.isEmpty ||
        ids.length > strategyNewSubmissionOrderLimit ||
        ids.toSet().length != ids.length ||
        rawOrders is! List ||
        rawOrders.length != ids.length ||
        totalMargin == null ||
        plannedMargin == null ||
        unallocatedMargin == null ||
        openingFees == null ||
        requiredBalance == null ||
        instrumentId is! String ||
        instrumentId.isEmpty ||
        interval is! String ||
        interval.isEmpty ||
        currentPrice == null ||
        quoteTimestamp is! String ||
        DateTime.tryParse(quoteTimestamp) == null ||
        sidePercent is! Map ||
        sidePercent.keys.any((key) => key is! String) ||
        sides is! List ||
        map['allocation'] != 'fixed' ||
        map['feesOutsideMargin'] != true) {
      return null;
    }
    final orders = <Map<String, dynamic>>[];
    for (var index = 0; index < rawOrders.length; index++) {
      final order = _retryStringKeyedMap(rawOrders[index]);
      if (order == null ||
          !_retryHasKeys(order, const {
            'sourceClientOrderId',
            'side',
            'role',
            'limitPrice',
            'contracts',
            'leverage',
            'margin',
            'openingFeeEstimate',
            'allocatedMargin',
            'notional',
            'allocationWeight',
            'cumulativeContracts',
            'cumulativeAverageEntry',
            'liquidationEstimate',
          }) ||
          order['sourceClientOrderId'] != ids[index] ||
          !_retryValidOrder(order, child: false)) {
        return null;
      }
      orders.add(Map.unmodifiable(order));
    }
    if (!_retryCostsMatch(
      totalMargin: totalMargin,
      plannedMargin: plannedMargin,
      unallocatedMargin: unallocatedMargin,
      openingFees: openingFees,
      requiredBalance: requiredBalance,
      orders: orders,
    )) {
      return null;
    }
    return StrategyRetryPreview(
      sourceStrategyId: sourceId,
      sourceRevision: revision,
      selectedSourceClientOrderIds: List.unmodifiable(ids),
      previewHash: hash,
      orders: List.unmodifiable(orders),
      totalMargin: totalMargin,
      plannedMargin: plannedMargin,
      unallocatedMargin: unallocatedMargin,
      estimatedOpeningFees: openingFees,
      requiredBalance: requiredBalance,
      raw: Map.unmodifiable(map),
    );
  }
}

class StrategyRetryDraft {
  const StrategyRetryDraft({
    required this.id,
    required this.status,
    required this.orders,
    required this.resubmission,
    required this.preview,
    required this.raw,
  });

  final String id;
  final String status;
  final List<Map<String, dynamic>> orders;
  final Map<String, dynamic> resubmission;
  final StrategyRetryPreview preview;
  final Map<String, dynamic> raw;

  static StrategyRetryDraft? tryParse(Object? value) {
    // Retry creation returns the ordinary strategy result envelope as well as
    // the retry-specific fields. Validate those fields while tolerating the
    // documented status, cost, and lifecycle fields in that envelope.
    final map = _retryStringKeyedMap(value);
    if (map == null ||
        !_retryHasKeys(map, const {
          'id',
          'status',
          'orders',
          'resubmission',
          'preview',
        })) {
      return null;
    }
    final id = map['id'];
    final status = map['status'];
    final rawOrders = map['orders'];
    final lineage = _retryStrictMap(map['resubmission'], const {
      'sourceStrategyId',
      'sourceClientOrderIds',
    });
    final rawPreview = map['preview'];
    if (id is! String ||
        id.isEmpty ||
        status is! String ||
        status.toUpperCase() != 'DRAFT' ||
        rawOrders is! List ||
        rawOrders.isEmpty ||
        rawOrders.length > strategyNewSubmissionOrderLimit ||
        lineage == null ||
        !_retryHasKeys(lineage, const {
          'sourceStrategyId',
          'sourceClientOrderIds',
        })) {
      return null;
    }
    final sourceId = lineage['sourceStrategyId'];
    final sourceIds = _retryStringList(lineage['sourceClientOrderIds']);
    final parsedOrders = <Map<String, dynamic>>[];
    for (final rawOrder in rawOrders) {
      final order = _retryStringKeyedMap(rawOrder);
      if (order == null || !_retryValidOrder(order, child: true)) return null;
      parsedOrders.add(Map.unmodifiable(order));
    }
    if (sourceId is! String ||
        sourceId.isEmpty ||
        sourceIds == null ||
        sourceIds.isEmpty ||
        sourceIds.length != parsedOrders.length ||
        sourceIds.toSet().length != sourceIds.length ||
        parsedOrders
                .map((order) => order['sourceClientOrderId'])
                .join('\u0000') !=
            sourceIds.join('\u0000') ||
        parsedOrders.map((order) => order['clientOrderId']).toSet().length !=
            parsedOrders.length) {
      return null;
    }
    final nestedPreview = StrategyRetryPreview.tryParse(rawPreview);
    if (nestedPreview == null ||
        nestedPreview.sourceStrategyId != sourceId ||
        !_sameStrings(nestedPreview.selectedSourceClientOrderIds, sourceIds) ||
        nestedPreview.orders.length != parsedOrders.length ||
        !_sameRetryOrderBindings(
          nestedPreview.orders,
          parsedOrders,
          requireChildIds: true,
        )) {
      return null;
    }
    return StrategyRetryDraft(
      id: id,
      status: status,
      orders: List.unmodifiable(parsedOrders),
      resubmission: Map.unmodifiable(lineage),
      preview: nestedPreview,
      raw: Map.unmodifiable(map),
    );
  }
}

bool _sameStrings(List<String> left, List<String> right) =>
    left.length == right.length &&
    List<bool>.generate(
      left.length,
      (index) => left[index] == right[index],
    ).every((match) => match);

bool _sameRetryOrderBindings(
  List<Map<String, dynamic>> expected,
  List<Map<String, dynamic>> actual, {
  required bool requireChildIds,
}) {
  if (expected.length != actual.length) return false;
  const stableKeys = {
    'sourceClientOrderId',
    'side',
    'role',
    'limitPrice',
    'contracts',
    'leverage',
    'margin',
    'allocatedMargin',
    'notional',
    'openingFeeEstimate',
    'allocationWeight',
    'cumulativeContracts',
    'cumulativeAverageEntry',
    'liquidationEstimate',
    'levelId',
  };
  for (var index = 0; index < expected.length; index++) {
    final left = expected[index];
    final right = actual[index];
    for (final key in stableKeys) {
      if (left.containsKey(key) != right.containsKey(key)) return false;
      if (left.containsKey(key) &&
          !_retryOrderValueEqual(key, left[key], right[key])) {
        return false;
      }
    }
    final childId = right['clientOrderId'];
    if (requireChildIds &&
        (childId is! String ||
            childId.isEmpty ||
            childId == left['sourceClientOrderId'])) {
      return false;
    }
  }
  return true;
}

bool _retryOrderValueEqual(String key, Object? left, Object? right) {
  if (const {'sourceClientOrderId', 'side', 'role', 'levelId'}.contains(key)) {
    return left == right;
  }
  return _retryValuesEqual(left, right);
}

bool _retryValuesEqual(Object? left, Object? right) {
  if (left == null || right == null) return left == right;
  if (left is Map && right is Map) {
    if (left.keys.any((key) => key is! String) ||
        right.keys.any((key) => key is! String) ||
        left.length != right.length ||
        left.keys.toSet().difference(right.keys.toSet()).isNotEmpty) {
      return false;
    }
    for (final key in left.keys) {
      if (!_retryValuesEqual(left[key], right[key])) return false;
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!_retryValuesEqual(left[index], right[index])) return false;
    }
    return true;
  }
  final leftDecimal = StrategyDecimal.tryParse(strategyNumber(left));
  final rightDecimal = StrategyDecimal.tryParse(strategyNumber(right));
  if ((left is num || left is String) &&
      (right is num || right is String) &&
      leftDecimal != null &&
      rightDecimal != null) {
    if (left is String && right is String) return left == right;
    if (left is num && right is num) {
      return leftDecimal.compareTo(rightDecimal) == 0;
    }
    return leftDecimal.compareTo(rightDecimal) == 0;
  }
  return left == right;
}

Map<String, dynamic>? _retryStringKeyedMap(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) return null;
  return Map<String, dynamic>.from(value);
}

Map<String, dynamic>? _retryStrictMap(Object? value, Set<String> allowed) {
  final map = _retryStringKeyedMap(value);
  if (map == null || map.keys.any((key) => !allowed.contains(key))) return null;
  return map;
}

bool _retryHasKeys(Map<String, dynamic> value, Set<String> required) =>
    required.every(value.containsKey);

List<String>? _retryStringList(Object? value) {
  if (value is! List || value.any((item) => item is! String || item.isEmpty)) {
    return null;
  }
  return value.cast<String>();
}

String? _retryDecimalText(Object? value, {required bool positive}) {
  final text = switch (value) {
    String string => string.trim(),
    int number => number.toString(),
    double number when number.isFinite => number.toString(),
    _ => null,
  };
  final decimal = StrategyDecimal.tryParse(text);
  if (text == null ||
      decimal == null ||
      (positive ? !decimal.isPositive : decimal.coefficient.isNegative)) {
    return null;
  }
  return decimal.toString();
}

bool _retryValidOrder(Map<String, dynamic> order, {required bool child}) {
  final sourceId = order['sourceClientOrderId'];
  final childId = order['clientOrderId'];
  final side = order['side'];
  final role = order['role'];
  final price = _retryDecimalText(order['limitPrice'], positive: true);
  final contracts = _retryDecimalText(order['contracts'], positive: true);
  final leverage = _retryDecimalText(order['leverage'], positive: true);
  final margin = _retryDecimalText(order['margin'], positive: true);
  final fee = _retryDecimalText(order['openingFeeEstimate'], positive: false);
  final allocatedMargin = _retryDecimalText(
    order['allocatedMargin'],
    positive: false,
  );
  final notional = _retryDecimalText(order['notional'], positive: true);
  final allocationWeight = _retryDecimalText(
    order['allocationWeight'],
    positive: false,
  );
  final cumulativeContracts = _retryDecimalText(
    order['cumulativeContracts'],
    positive: true,
  );
  final cumulativeAverageEntry = _retryDecimalText(
    order['cumulativeAverageEntry'],
    positive: true,
  );
  final leverageDecimal = StrategyDecimal.tryParse(leverage ?? '');
  return sourceId is String &&
      sourceId.isNotEmpty &&
      (!child ||
          (childId is String && childId.isNotEmpty && childId != sourceId)) &&
      (child || childId == null || childId is String) &&
      (side == 'long' || side == 'short') &&
      (role == 'entry' || role == 'dca') &&
      price != null &&
      contracts != null &&
      leverageDecimal != null &&
      const {
        '1',
        '2',
        '3',
        '4',
        '5',
        '6',
        '7',
        '8',
        '9',
        '10',
      }.contains(leverageDecimal.toString()) &&
      margin != null &&
      fee != null &&
      allocatedMargin != null &&
      allocatedMargin == margin &&
      notional != null &&
      allocationWeight != null &&
      cumulativeContracts != null &&
      cumulativeAverageEntry != null &&
      order['liquidationEstimate'] != null;
}

bool _retryCostsMatch({
  required String totalMargin,
  required String plannedMargin,
  required String unallocatedMargin,
  required String openingFees,
  required String requiredBalance,
  required List<Map<String, dynamic>> orders,
}) {
  final total = StrategyDecimal.tryParse(totalMargin);
  final planned = StrategyDecimal.tryParse(plannedMargin);
  final unallocated = StrategyDecimal.tryParse(unallocatedMargin);
  final fees = StrategyDecimal.tryParse(openingFees);
  final balance = StrategyDecimal.tryParse(requiredBalance);
  if (total == null ||
      planned == null ||
      unallocated == null ||
      fees == null ||
      balance == null ||
      total.compareTo(planned) != 0 ||
      unallocated.coefficient != BigInt.zero) {
    return false;
  }
  var marginSum = StrategyDecimal.tryParse('0')!;
  var feeSum = StrategyDecimal.tryParse('0')!;
  for (final order in orders) {
    final margin = StrategyDecimal.tryParse(
      _retryDecimalText(order['margin'], positive: true) ?? '',
    );
    final fee = StrategyDecimal.tryParse(
      _retryDecimalText(order['openingFeeEstimate'], positive: false) ?? '',
    );
    if (margin == null || fee == null) return false;
    marginSum = marginSum + margin;
    feeSum = feeSum + fee;
  }
  return marginSum.compareTo(total) == 0 &&
      feeSum.compareTo(fees) == 0 &&
      (total + fees).compareTo(balance) == 0;
}

const strategyNewSubmissionOrderLimit = 10;
const strategyHistoricalOrderLimit = 20;

bool hasOversizedNewStrategyOrderPayload(Map<String, dynamic> strategy) {
  final selectedLevels = strategy['selectedLevels'];
  final orders = strategy['orders'];
  return (selectedLevels is List &&
          selectedLevels.length > strategyNewSubmissionOrderLimit) ||
      (orders is List && orders.length > strategyNewSubmissionOrderLimit);
}

List<Map<String, dynamic>>? validatedStrategyOrders(
  Map<String, dynamic> prepared,
) => _validatedStrategyOrders(
  prepared,
  maximumCount: strategyHistoricalOrderLimit,
);

List<Map<String, dynamic>>? validatedNewStrategyOrders(
  Map<String, dynamic> prepared,
) => _validatedStrategyOrders(
  prepared,
  maximumCount: strategyNewSubmissionOrderLimit,
);

List<Map<String, dynamic>>? _validatedStrategyOrders(
  Map<String, dynamic> prepared, {
  required int maximumCount,
}) {
  if (_nonNegativeOrderNumber(prepared['estimatedOpeningFees']) == null) {
    return null;
  }
  final rawOrders = prepared['orders'];
  if (rawOrders is! List ||
      rawOrders.isEmpty ||
      rawOrders.length > maximumCount) {
    return null;
  }
  final orders = <Map<String, dynamic>>[];
  for (final rawOrder in rawOrders) {
    if (rawOrder is! Map || rawOrder.keys.any((key) => key is! String)) {
      return null;
    }
    final order = Map<String, dynamic>.from(rawOrder);
    final side = order['side'];
    final role = order['role'];
    if (side is! String ||
        !const {'long', 'short'}.contains(side) ||
        role is! String ||
        !const {'entry', 'dca'}.contains(role)) {
      return null;
    }
    if (_positiveOrderNumber(order['limitPrice']) == null ||
        _positiveOrderNumber(order['contracts']) == null ||
        _positiveOrderNumber(order['margin']) == null) {
      return null;
    }
    final leverage = _positiveOrderNumber(order['leverage']);
    if (leverage == null ||
        leverage < 1 ||
        leverage > 10 ||
        leverage != leverage.roundToDouble() ||
        _nonNegativeOrderNumber(order['openingFeeEstimate']) == null) {
      return null;
    }
    orders.add(Map.unmodifiable(order));
  }
  if (!_openingFeesMatch(prepared['estimatedOpeningFees'], orders)) {
    return null;
  }
  return List.unmodifiable(orders);
}

bool _openingFeesMatch(
  Object? aggregateValue,
  List<Map<String, dynamic>> orders,
) {
  final aggregate = _ExactDecimal.parse(aggregateValue);
  if (aggregate == null) return false;
  final fees = <_ExactDecimal>[];
  var commonScale = aggregate.scale;
  for (final order in orders) {
    final fee = _ExactDecimal.parse(order['openingFeeEstimate']);
    if (fee == null) return false;
    fees.add(fee);
    if (fee.scale > commonScale) commonScale = fee.scale;
  }
  final scaledAggregate =
      aggregate.coefficient *
      BigInt.from(10).pow(commonScale - aggregate.scale);
  final scaledFeeSum = fees.fold<BigInt>(
    BigInt.zero,
    (sum, fee) =>
        sum + fee.coefficient * BigInt.from(10).pow(commonScale - fee.scale),
  );
  return scaledAggregate == scaledFeeSum;
}

class _ExactDecimal {
  const _ExactDecimal(this.coefficient, this.scale);

  static final _pattern = RegExp(
    r'^([+-]?)(?:(\d+)(?:\.(\d*))?|\.(\d+))(?:[eE]([+-]?\d+))?$',
  );

  final BigInt coefficient;
  final int scale;

  static _ExactDecimal? parse(Object? value) {
    final text = switch (value) {
      num number => number.toString(),
      String string => string.trim(),
      _ => null,
    };
    if (text == null || text.length > 1024) return null;
    final match = _pattern.firstMatch(text);
    if (match == null) return null;
    final whole = match.group(2) ?? '0';
    final fraction = match.group(3) ?? match.group(4) ?? '';
    final exponent = int.tryParse(match.group(5) ?? '0');
    if (exponent == null || exponent.abs() > 1024) return null;
    final digits = '$whole$fraction';
    final parsedCoefficient = BigInt.tryParse(digits);
    if (parsedCoefficient == null) return null;
    var coefficient = match.group(1) == '-'
        ? -parsedCoefficient
        : parsedCoefficient;
    var scale = fraction.length - exponent;
    if (scale < 0) {
      coefficient *= BigInt.from(10).pow(-scale);
      scale = 0;
    }
    while (scale > 0 && coefficient.remainder(BigInt.from(10)) == BigInt.zero) {
      coefficient ~/= BigInt.from(10);
      scale--;
    }
    return _ExactDecimal(coefficient, scale);
  }
}

double? _positiveOrderNumber(Object? value) {
  final number = switch (value) {
    num number => number.toDouble(),
    String text => double.tryParse(text.trim()),
    _ => null,
  };
  return number != null && number.isFinite && number > 0 ? number : null;
}

double? _nonNegativeOrderNumber(Object? value) {
  final number = switch (value) {
    num number => number.toDouble(),
    String text => double.tryParse(text.trim()),
    _ => null,
  };
  return number != null && number.isFinite && number >= 0 ? number : null;
}
