import '../../domain/risk/risk_models.dart';

/// Handwritten, nullable DTOs for the risk feature.  They intentionally do
/// not reuse generated Orders models: OKX sends empty strings for many fields
/// and a malformed number must become unavailable rather than zero.

double? parseRiskNumber(Object? raw) {
  if (raw == null) return null;
  final value = raw is num
      ? raw.toDouble()
      : double.tryParse(raw.toString().trim());
  if (value == null || !value.isFinite) return null;
  return value;
}

String? parseRiskText(Object? raw) {
  if (raw == null) return null;
  final value = raw.toString().trim();
  return value.isEmpty ? null : value;
}

DateTime? parseRiskEpoch(Object? raw) {
  final number = parseRiskNumber(raw);
  if (number != null && number.isFinite && number > 0) {
    try {
      return DateTime.fromMillisecondsSinceEpoch(number.round(), isUtc: true);
    } on RangeError {
      return null;
    }
  }
  final text = parseRiskText(raw);
  if (text == null) return null;
  return DateTime.tryParse(text)?.toUtc();
}

class RiskNumericDto {
  const RiskNumericDto({
    required this.value,
    required this.unit,
    required this.source,
    required this.quality,
    this.observedAt,
    this.sourceAt,
    this.raw,
  });

  factory RiskNumericDto.fromRaw(
    Object? raw, {
    required String unit,
    required String source,
    DateTime? observedAt,
    DateTime? sourceAt,
  }) {
    final value = parseRiskNumber(raw);
    return RiskNumericDto(
      raw: parseRiskText(raw),
      value: value,
      unit: unit,
      source: source,
      observedAt: observedAt,
      sourceAt: sourceAt,
      quality: value == null
          ? RiskQualityStatus.unavailable
          : RiskQualityStatus.complete,
    );
  }

  final String? raw;
  final double? value;
  final String unit;
  final String source;
  final RiskQualityStatus quality;
  final DateTime? observedAt;
  final DateTime? sourceAt;

  String get qualityLabel => quality.name;
}

class OkxRiskPositionDto {
  const OkxRiskPositionDto({
    this.instId,
    this.instType,
    this.mgnMode,
    this.posSide,
    this.pos,
    this.posId,
    this.posCcy,
    this.ccy,
    this.liabCcy,
    this.avgPx,
    this.markPx,
    this.liqPx,
    this.margin,
    this.upl,
    this.lever,
    this.mgnRatio,
    this.mmr,
    this.liab,
    this.interest,
    this.baseBal,
    this.quoteBal,
    this.baseBorrowed,
    this.quoteBorrowed,
    this.baseInterest,
    this.quoteInterest,
    this.notionalUsd,
    this.fee,
    this.cTime,
    this.uTime,
    this.source = 'OKX /api/v5/account/positions',
    this.fetchedAt,
  });

  factory OkxRiskPositionDto.fromJson(
    Map<String, dynamic> json, {
    String source = 'OKX /api/v5/account/positions',
    DateTime? fetchedAt,
  }) {
    return OkxRiskPositionDto(
      instId: parseRiskText(json['instId']),
      instType: parseRiskText(json['instType']),
      mgnMode: parseRiskText(json['mgnMode']),
      posSide: parseRiskText(json['posSide']),
      pos: parseRiskText(json['pos']),
      posId: parseRiskText(json['posId']),
      posCcy: parseRiskText(json['posCcy']),
      ccy: parseRiskText(json['ccy']),
      liabCcy: parseRiskText(json['liabCcy']),
      avgPx: parseRiskText(json['avgPx']),
      markPx: parseRiskText(json['markPx']),
      liqPx: parseRiskText(json['liqPx']),
      margin: parseRiskText(json['margin']),
      upl: parseRiskText(json['upl']),
      lever: parseRiskText(json['lever']),
      mgnRatio: parseRiskText(json['mgnRatio']),
      mmr: parseRiskText(json['mmr']),
      liab: parseRiskText(json['liab']),
      interest: parseRiskText(json['interest']),
      baseBal: parseRiskText(json['baseBal']),
      quoteBal: parseRiskText(json['quoteBal']),
      baseBorrowed: parseRiskText(json['baseBorrowed']),
      quoteBorrowed: parseRiskText(json['quoteBorrowed']),
      baseInterest: parseRiskText(json['baseInterest']),
      quoteInterest: parseRiskText(json['quoteInterest']),
      notionalUsd: parseRiskText(json['notionalUsd']),
      fee: parseRiskText(json['fee']),
      cTime: parseRiskText(json['cTime']),
      uTime: parseRiskText(json['uTime']),
      source: source,
      fetchedAt: fetchedAt,
    );
  }

  final String? instId;
  final String? instType;
  final String? mgnMode;
  final String? posSide;
  final String? pos;
  final String? posId;
  final String? posCcy;
  final String? ccy;
  final String? liabCcy;
  final String? avgPx;
  final String? markPx;
  final String? liqPx;
  final String? margin;
  final String? upl;
  final String? lever;
  final String? mgnRatio;
  final String? mmr;
  final String? liab;
  final String? interest;
  final String? baseBal;
  final String? quoteBal;
  final String? baseBorrowed;
  final String? quoteBorrowed;
  final String? baseInterest;
  final String? quoteInterest;
  final String? notionalUsd;
  final String? fee;
  final String? cTime;
  final String? uTime;
  final String source;
  final DateTime? fetchedAt;

  double? get quantity => parseRiskNumber(pos);
  double? get averagePrice => parseRiskNumber(avgPx);
  double? get markPrice => parseRiskNumber(markPx);
  double? get liquidationPrice => parseRiskNumber(liqPx);
  double? get marginValue => parseRiskNumber(margin);
  double? get unrealizedPnl => parseRiskNumber(upl);
  double? get leverage => parseRiskNumber(lever);
  double? get marginRatio => parseRiskNumber(mgnRatio);
  double? get maintenanceRequirement => parseRiskNumber(mmr);
  double? get liability => parseRiskNumber(liab);
  double? get accruedInterest => parseRiskNumber(interest);
  double? get baseBalanceValue => parseRiskNumber(baseBal);
  double? get quoteBalanceValue => parseRiskNumber(quoteBal);
  double? get baseBorrowedValue => parseRiskNumber(baseBorrowed);
  double? get quoteBorrowedValue => parseRiskNumber(quoteBorrowed);
  double? get baseInterestValue => parseRiskNumber(baseInterest);
  double? get quoteInterestValue => parseRiskNumber(quoteInterest);
  double? get notionalUsdValue => parseRiskNumber(notionalUsd);
  double? get feeValue => parseRiskNumber(fee);
  DateTime? get createdAt => parseRiskEpoch(cTime);
  DateTime? get updatedAt => parseRiskEpoch(uTime);

  /// Local observation time is when this response was fetched.  The exchange
  /// uTime remains available separately as [sourceAt] so freshness and source
  /// age cannot be conflated.
  DateTime? get observedAt => fetchedAt;
  DateTime? get sourceAt => updatedAt;

  String? get baseCurrency {
    final id = instId;
    if (id == null) return null;
    final parts = id.split('-');
    return parts.isEmpty || parts.first.isEmpty ? null : parts.first;
  }

  bool get hasFinitePriceInputs =>
      markPrice != null && averagePrice != null && liquidationPrice != null;
}

class OkxRiskAccountConfigDto {
  const OkxRiskAccountConfigDto({
    this.uid,
    this.mgnIsoMode,
    this.acctLv,
    this.posMode,
    this.autoLoan,
    this.source = 'OKX /api/v5/account/config',
    this.fetchedAt,
  });

  factory OkxRiskAccountConfigDto.fromJson(
    Map<String, dynamic> json, {
    String source = 'OKX /api/v5/account/config',
    DateTime? fetchedAt,
  }) {
    return OkxRiskAccountConfigDto(
      uid: parseRiskText(json['uid']),
      mgnIsoMode: parseRiskText(json['mgnIsoMode']),
      acctLv: parseRiskText(json['acctLv']),
      posMode: parseRiskText(json['posMode']),
      autoLoan: parseRiskText(json['autoLoan']),
      source: source,
      fetchedAt: fetchedAt,
    );
  }

  final String? uid;
  final String? mgnIsoMode;
  final String? acctLv;
  final String? posMode;
  final String? autoLoan;
  final String source;
  final DateTime? fetchedAt;

  RiskAccountMode get normalizedMode {
    switch (mgnIsoMode?.toLowerCase()) {
      case 'auto_transfers_ccy':
        return RiskAccountMode.newMode;
      case 'automatic':
        return RiskAccountMode.oldMode;
      default:
        return RiskAccountMode.unsupported;
    }
  }

  bool get hasIdentity => uid != null && uid!.trim().isNotEmpty;
}

class OkxRiskInstrumentDto {
  const OkxRiskInstrumentDto({
    this.instId,
    this.instType,
    this.baseCcy,
    this.quoteCcy,
    this.groupId,
    this.source = 'OKX /api/v5/account/instruments',
    this.fetchedAt,
  });

  factory OkxRiskInstrumentDto.fromJson(
    Map<String, dynamic> json, {
    String source = 'OKX /api/v5/account/instruments',
    DateTime? fetchedAt,
  }) {
    return OkxRiskInstrumentDto(
      instId: parseRiskText(json['instId']),
      instType: parseRiskText(json['instType']),
      baseCcy: parseRiskText(json['baseCcy']),
      quoteCcy: parseRiskText(json['quoteCcy']),
      groupId: parseRiskText(json['groupId']),
      source: source,
      fetchedAt: fetchedAt,
    );
  }

  final String? instId;
  final String? instType;
  final String? baseCcy;
  final String? quoteCcy;
  final String? groupId;
  final String source;
  final DateTime? fetchedAt;
}

class OkxRiskFeeRateDto {
  const OkxRiskFeeRateDto({
    this.instType,
    this.instId,
    this.feeGroup = const <OkxRiskFeeGroupDto>[],
    this.taker,
    this.maker,
    this.source = 'OKX /api/v5/account/trade-fee',
    this.fetchedAt,
  });

  factory OkxRiskFeeRateDto.fromJson(
    Map<String, dynamic> json, {
    String source = 'OKX /api/v5/account/trade-fee',
    DateTime? fetchedAt,
  }) {
    return OkxRiskFeeRateDto(
      instType: parseRiskText(json['instType']),
      instId: parseRiskText(json['instId']),
      feeGroup: _parseFeeGroups(json['feeGroup']),
      taker: parseRiskText(json['taker']),
      maker: parseRiskText(json['maker']),
      source: source,
      fetchedAt: fetchedAt,
    );
  }

  final String? instType;
  final String? instId;
  final List<OkxRiskFeeGroupDto> feeGroup;
  final String? taker;
  final String? maker;
  final String source;
  final DateTime? fetchedAt;

  double? get takerRate => parseRiskNumber(taker);
  double? get makerRate => parseRiskNumber(maker);

  /// Resolve an exact instrument fee group.  The top-level legacy rate is
  /// accepted only when the response is unambiguous (one group or no groups).
  double? takerExpenseRateFor([String? groupId]) {
    OkxRiskFeeGroupDto? group;
    if (groupId == null) {
      group = feeGroup.length == 1 && feeGroup.first.groupId != null
          ? feeGroup.first
          : null;
    } else {
      for (final candidate in feeGroup) {
        if (candidate.groupId == groupId) {
          group = candidate;
          break;
        }
      }
    }
    final value = group?.takerRate ?? (feeGroup.isEmpty ? takerRate : null);
    if (value == null || !value.isFinite) return null;
    // In OKX signed fee fields a negative value is an expense. A positive
    // value denotes a rebate and is excluded from the expense allowance.
    return value < 0 ? -value : 0;
  }

  double? get takerExpenseRate => takerExpenseRateFor();
}

class OkxRiskFeeGroupDto {
  const OkxRiskFeeGroupDto({this.groupId, this.taker, this.maker});

  factory OkxRiskFeeGroupDto.fromJson(Map<String, dynamic> json) {
    return OkxRiskFeeGroupDto(
      groupId: parseRiskText(json['groupId']),
      taker: parseRiskText(json['taker']),
      maker: parseRiskText(json['maker']),
    );
  }

  final String? groupId;
  final String? taker;
  final String? maker;

  double? get takerRate => parseRiskNumber(taker);
  double? get makerRate => parseRiskNumber(maker);
}

List<OkxRiskFeeGroupDto> _parseFeeGroups(Object? raw) {
  if (raw is! List) return const <OkxRiskFeeGroupDto>[];
  return raw
      .whereType<Map>()
      .map(
        (item) => OkxRiskFeeGroupDto.fromJson(Map<String, dynamic>.from(item)),
      )
      .toList(growable: false);
}

class OkxRiskInterestRateDto {
  const OkxRiskInterestRateDto({
    this.ccy,
    this.rate,
    this.source = 'OKX /api/v5/account/interest-rate',
    this.fetchedAt,
  });

  factory OkxRiskInterestRateDto.fromJson(
    Map<String, dynamic> json, {
    String source = 'OKX /api/v5/account/interest-rate',
    DateTime? fetchedAt,
  }) {
    return OkxRiskInterestRateDto(
      ccy: parseRiskText(json['ccy']),
      rate: parseRiskText(
        json['interestRate'] ?? json['rate'] ?? json['hourlyRate'],
      ),
      source: source,
      fetchedAt: fetchedAt,
    );
  }

  final String? ccy;
  final String? rate;
  final String source;
  final DateTime? fetchedAt;

  double? get hourlyRate {
    final value = parseRiskNumber(rate);
    if (value == null || value < 0) return null;
    return value;
  }
}

class OkxRiskInterestAccruedDto {
  const OkxRiskInterestAccruedDto({
    this.instId,
    this.ccy,
    this.mgnMode,
    this.interest,
    this.loanTrans,
    this.type,
    this.ts,
    this.source = 'OKX /api/v5/account/interest-accrued',
    this.fetchedAt,
  });

  factory OkxRiskInterestAccruedDto.fromJson(
    Map<String, dynamic> json, {
    String source = 'OKX /api/v5/account/interest-accrued',
    DateTime? fetchedAt,
  }) {
    return OkxRiskInterestAccruedDto(
      instId: parseRiskText(json['instId']),
      ccy: parseRiskText(json['ccy']),
      mgnMode: parseRiskText(json['mgnMode']),
      interest: parseRiskText(json['interest'] ?? json['interestAmt']),
      loanTrans: parseRiskText(json['loanTrans']),
      type: parseRiskText(json['type']),
      ts: parseRiskText(json['ts'] ?? json['uTime']),
      source: source,
      fetchedAt: fetchedAt,
    );
  }

  final String? instId;
  final String? ccy;
  final String? mgnMode;
  final String? interest;
  final String? loanTrans;
  final String? type;
  final String? ts;
  final String source;
  final DateTime? fetchedAt;

  double? get amount => parseRiskNumber(interest);
  DateTime? get occurredAt => parseRiskEpoch(ts);

  /// OKX documents `type` as a loan-type code, where `2` means market loan.
  /// An absent code is tolerated only as an otherwise exact, scoped row; an
  /// explicit non-market code or event prose must not be attributed here.
  bool get matchesMarginCost {
    final normalizedType = type?.trim();
    final marketLoan = normalizedType == null || normalizedType == '2';
    return marketLoan && amount != null;
  }
}

class RiskInterestLedgerResult {
  const RiskInterestLedgerResult({
    required this.entries,
    required this.complete,
    required this.pages,
    this.ambiguousEntries = false,
    this.coverageFrom,
    this.coverageTo,
    this.requestedFrom,
    this.requestedTo,
    this.reason,
    this.observedAt,
  });

  final List<OkxRiskInterestAccruedDto> entries;
  final bool complete;
  final int pages;
  final bool ambiguousEntries;
  final DateTime? coverageFrom;
  final DateTime? coverageTo;

  /// The bounds of the completed query window. These are separate from the
  /// timestamps on matching rows so an empty day can still prove zero rows,
  /// and a non-empty day can carry a known subtotal without claiming that the
  /// last row timestamp is the end of the covered window.
  final DateTime? requestedFrom;
  final DateTime? requestedTo;
  final String? reason;
  final DateTime? observedAt;
}

/// Generic adapter envelope used when a caller needs a quality result rather
/// than throwing away the distinction between an empty response and a failed
/// request.
class RiskRepositoryResult<T> {
  const RiskRepositoryResult({
    required this.data,
    required this.quality,
    this.error,
    this.fetchedAt,
  });

  final T? data;
  final String quality;
  final Object? error;
  final DateTime? fetchedAt;

  bool get isSuccess => error == null && data != null;
  bool get isError => error != null;
}

// Retained as a tiny helper for adapters that need a conservative finite
// check without importing the domain engine.
bool isFiniteRiskValue(double? value) => value != null && value.isFinite;

double absRiskFee(Object? raw) {
  final value = parseRiskNumber(raw);
  if (value == null) return double.nan;
  return value.abs();
}
