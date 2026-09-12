import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/okx_interceptor.dart';
import '../../domain/risk/risk_models.dart';
import 'okx_risk_dto.dart';

typedef RiskRepositoryClock = DateTime Function();

/// A dedicated risk adapter.  Every method below is a GET; no order, borrow,
/// repay, or account-mutating endpoint is exposed from this repository.
final riskRepositoryProvider = Provider<RiskRepository>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: kIsWeb ? '' : 'https://www.okx.com',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: const <String, Object>{'Content-Type': 'application/json'},
    ),
  );
  // Reuse the existing signing interceptor without importing the legacy
  // LogInterceptor, which could expose authenticated request payloads.
  dio.interceptors.add(ref.watch(okxInterceptorProvider));
  return RiskRepository(dio);
});

class RiskRepositoryException implements Exception {
  const RiskRepositoryException(
    this.message, {
    this.statusCode,
    this.endpoint,
    this.cause,
  });

  final String message;
  final int? statusCode;
  final String? endpoint;
  final Object? cause;

  @override
  String toString() {
    final suffix = statusCode == null ? '' : ' (HTTP $statusCode)';
    return 'RiskRepositoryException$suffix: $message';
  }
}

class RiskRepository {
  RiskRepository(
    this._dio, {
    this.environment = 'production',
    RiskRepositoryClock? clock,
    this.maxLedgerPages = 100,
  }) : clock = clock ?? DateTime.now;

  final Dio _dio;
  final String environment;
  final RiskRepositoryClock clock;
  final int maxLedgerPages;

  static const String positionsEndpoint = '/api/v5/account/positions';
  static const String instrumentsEndpoint = '/api/v5/account/instruments';
  static const String configEndpoint = '/api/v5/account/config';
  static const String feeEndpoint = '/api/v5/account/trade-fee';
  static const String interestRateEndpoint = '/api/v5/account/interest-rate';
  static const String interestAccruedEndpoint =
      '/api/v5/account/interest-accrued';

  Future<OkxRiskAccountConfigDto> getAccountConfig() async {
    final response = await _get(configEndpoint);
    final data = _dataList(response, configEndpoint);
    if (data.isEmpty) {
      throw const RiskRepositoryException(
        'OKX account configuration response was empty',
        endpoint: configEndpoint,
      );
    }
    return OkxRiskAccountConfigDto.fromJson(data.first, fetchedAt: clock());
  }

  Future<List<OkxRiskPositionDto>> getPositions({String? instId}) async {
    final query = <String, dynamic>{'instType': 'MARGIN'};
    final requestedInstId = instId?.trim();
    if (requestedInstId != null && requestedInstId.isNotEmpty) {
      query['instId'] = requestedInstId;
    }
    final response = await _get(positionsEndpoint, queryParameters: query);
    final positions = _dataList(response, positionsEndpoint)
        .map((item) => OkxRiskPositionDto.fromJson(item, fetchedAt: clock()))
        .toList(growable: false);
    if (requestedInstId == null || requestedInstId.isEmpty) return positions;
    return positions
        .where((position) => position.instId == requestedInstId)
        .toList(growable: false);
  }

  Future<OkxRiskInstrumentDto?> getMarginInstrument({
    required String instId,
  }) async {
    final response = await _get(
      instrumentsEndpoint,
      queryParameters: <String, dynamic>{
        'instType': 'MARGIN',
        'instId': instId,
      },
    );
    final data = _dataList(response, instrumentsEndpoint);
    for (final item in data) {
      final instrument = OkxRiskInstrumentDto.fromJson(
        item,
        fetchedAt: clock(),
      );
      if (instrument.instId == instId &&
          instrument.instType?.toUpperCase() == 'MARGIN') {
        return instrument;
      }
    }
    return null;
  }

  Future<OkxRiskFeeRateDto?> getTradeFee({required String instId}) async {
    final response = await _get(
      feeEndpoint,
      queryParameters: <String, dynamic>{
        'instType': 'MARGIN',
        'instId': instId,
      },
    );
    final data = _dataList(response, feeEndpoint);
    for (final item in data) {
      final fee = OkxRiskFeeRateDto.fromJson(item, fetchedAt: clock());
      if (fee.instId == instId && fee.instType?.toUpperCase() == 'MARGIN') {
        return fee;
      }
    }
    return null;
  }

  Future<OkxRiskInterestRateDto?> getInterestRate({required String ccy}) async {
    final response = await _get(
      interestRateEndpoint,
      queryParameters: <String, dynamic>{'ccy': ccy},
    );
    final data = _dataList(response, interestRateEndpoint);
    for (final item in data) {
      final rate = OkxRiskInterestRateDto.fromJson(item, fetchedAt: clock());
      if (rate.ccy?.toUpperCase() == ccy.toUpperCase()) return rate;
    }
    return null;
  }

  /// Fetches the complete available accrued-interest history for an isolated
  /// position.  If the API's page cap is reached, the result is explicitly
  /// incomplete so callers cannot claim a precise True Exit price.
  Future<RiskInterestLedgerResult> getInterestLedger({
    required String instId,
    String? ccy,
    DateTime? episodeStart,
    DateTime? episodeEnd,
    int pageSize = 100,
  }) async {
    final safePageSize = pageSize.clamp(1, 100);
    final targetInstrument = instId.trim();
    final targetCurrency = ccy?.trim().toUpperCase();
    final hasValidEpisodeWindow =
        episodeStart != null &&
        episodeEnd != null &&
        !episodeStart.isAfter(episodeEnd);
    final entries = <OkxRiskInterestAccruedDto>[];
    String? after;
    var pages = 0;
    var complete = false;
    var ambiguousEntries = !hasValidEpisodeWindow;
    String? reason = hasValidEpisodeWindow
        ? null
        : 'Verified isolated position episode time window is required';
    DateTime? observedAt;
    DateTime? coverageFrom;
    DateTime? coverageTo;

    while (pages < maxLedgerPages) {
      final query = <String, dynamic>{
        'instId': targetInstrument,
        'mgnMode': 'isolated',
        'limit': safePageSize,
      };
      if (targetCurrency != null && targetCurrency.isNotEmpty) {
        query['ccy'] = targetCurrency;
      }
      if (after != null) query['after'] = after;
      final response = await _get(
        interestAccruedEndpoint,
        queryParameters: query,
      );
      final rawPage = _dataList(response, interestAccruedEndpoint);
      final fetchedAt = clock();
      final pageEntries = rawPage
          .map(
            (item) =>
                OkxRiskInterestAccruedDto.fromJson(item, fetchedAt: fetchedAt),
          )
          .toList(growable: false);
      final page = <OkxRiskInterestAccruedDto>[];
      var pageHasAmbiguousAttribution = false;
      for (final entry in pageEntries) {
        final occurredAt = entry.occurredAt;
        // A timestamp outside the verified episode is safely excluded before
        // identity validation. This is how rows from a previous/reopened
        // episode are kept out without relying on a response posId field.
        final outsideEpisode =
            occurredAt != null &&
            ((episodeStart != null && occurredAt.isBefore(episodeStart)) ||
                (episodeEnd != null && occurredAt.isAfter(episodeEnd)));
        if (outsideEpisode) continue;

        // The official endpoint has no posId. A missing identity is never
        // treated as belonging to the selected position; exact attribution is
        // instrument + currency + isolated mode + episode time.
        final instrumentMatches = entry.instId == targetInstrument;
        final currencyMatches =
            targetCurrency != null &&
            entry.ccy?.toUpperCase() == targetCurrency;
        // The request is explicitly scoped to isolated mode. Some OKX
        // responses omit mgnMode; a missing response field therefore does
        // not widen the query, while an explicit non-isolated value remains
        // ineligible for attribution.
        final modeMatches =
            entry.mgnMode == null || entry.mgnMode!.toLowerCase() == 'isolated';
        final exact = instrumentMatches && currencyMatches && modeMatches;
        if (hasValidEpisodeWindow &&
            exact &&
            entry.matchesMarginCost &&
            entry.amount != null &&
            entry.amount! >= 0 &&
            occurredAt != null) {
          page.add(entry);
          if (coverageFrom == null || occurredAt.isBefore(coverageFrom)) {
            coverageFrom = occurredAt;
          }
          if (coverageTo == null || occurredAt.isAfter(coverageTo)) {
            coverageTo = occurredAt;
          }
        } else {
          pageHasAmbiguousAttribution = true;
        }
      }
      ambiguousEntries = ambiguousEntries || pageHasAmbiguousAttribution;
      pages++;
      observedAt = clock();
      entries.addAll(page);
      if (pageHasAmbiguousAttribution) {
        reason ??=
            'Interest ledger contains rows without exact position attribution';
      }
      if (rawPage.length < safePageSize) {
        complete = hasValidEpisodeWindow && !ambiguousEntries;
        break;
      }
      final next = pageEntries.last.ts;
      if (next == null || next == after) {
        reason = 'Interest pagination cursor did not advance';
        break;
      }
      after = next;
    }
    if (!complete && reason == null) {
      reason = 'Interest ledger pagination reached the configured page limit';
    }
    return RiskInterestLedgerResult(
      entries: List.unmodifiable(entries),
      complete: complete,
      pages: pages,
      ambiguousEntries: ambiguousEntries,
      coverageFrom: coverageFrom,
      coverageTo: coverageTo,
      requestedFrom: episodeStart,
      requestedTo: episodeEnd,
      reason: reason,
      observedAt: observedAt,
    );
  }

  Future<RiskInterestLedgerResult> getInterestAccrued({
    required String instId,
    String? ccy,
    DateTime? episodeStart,
    DateTime? episodeEnd,
    int pageSize = 100,
  }) {
    return getInterestLedger(
      instId: instId,
      ccy: ccy,
      episodeStart: episodeStart,
      episodeEnd: episodeEnd,
      pageSize: pageSize,
    );
  }

  /// Resolve a namespace only from environment and the authenticated OKX uid.
  /// Neither an API key nor a secret is ever used in this hash.
  Future<String?> resolveAccountNamespace() async {
    final config = await getAccountConfig();
    final uid = config.uid;
    if (uid == null || uid.trim().isEmpty) return null;
    return accountNamespace(environment: environment, uid: uid);
  }

  static String accountNamespace({
    required String environment,
    required String uid,
  }) {
    return sha256.convert(utf8.encode('$environment$uid')).toString();
  }

  static String accountHash({
    required String environment,
    required String uid,
  }) => accountNamespace(environment: environment, uid: uid);

  /// Typed bridge for the local monitor/history owner when it has established
  /// exact episode and unchanged-size evidence.  This method performs no I/O
  /// and deliberately accepts partial attribution too; the pure engine keeps
  /// full True Exit gated on the coverage flag.
  RiskPosition applyCostAttribution(
    RiskPosition position,
    RiskCostAttribution attribution,
  ) {
    return position.withCostAttribution(attribution);
  }

  /// Explicitly named bridge for a monitor that has proved complete ledger
  /// coverage and unchanged position size. Incomplete evidence is rejected
  /// here so it cannot accidentally become a full True Exit.
  RiskPosition applyVerifiedCostAttribution(
    RiskPosition position,
    RiskCostAttribution attribution,
  ) {
    if (!attribution.coverage.isVerifiedComplete) {
      throw ArgumentError.value(
        attribution.coverage.reason ?? 'Complete cost coverage is required',
        'attribution',
      );
    }
    return position.withCostAttribution(attribution);
  }

  /// Load one eligible position and enrich it with the applicable fee, rate,
  /// and accrued-interest records.  Selection is deterministic and never
  /// falls back to another account namespace.
  Future<RiskPositionSelection> loadPosition({
    String? selectedPositionId,
    String? selectedEpisodeKey,
  }) async {
    late final OkxRiskAccountConfigDto config;
    late final List<OkxRiskPositionDto> rawPositions;
    try {
      config = await getAccountConfig();
      rawPositions = await getPositions();
    } on RiskRepositoryException catch (error) {
      return RiskPositionSelection(
        status: RiskEligibility.invalid,
        quality: RiskQuality.error(
          source: error.endpoint,
          reason: error.message,
        ),
        message: error.toString(),
      );
    }

    if (rawPositions.isEmpty) {
      return const RiskPositionSelection(
        status: RiskEligibility.empty,
        quality: RiskQuality.empty(
          reason: 'No MARGIN positions returned by OKX',
        ),
        message: 'No eligible isolated MARGIN position',
      );
    }
    final namespace = config.hasIdentity
        ? accountNamespace(environment: environment, uid: config.uid!)
        : null;
    final normalized = rawPositions
        .map((raw) => _toPosition(raw, config, namespace: namespace))
        .toList(growable: false);
    final eligible =
        normalized.where((position) => position.isEligible).toList()
          ..sort(_positionComparator);
    if (eligible.isEmpty) {
      return RiskPositionSelection(
        status: config.normalizedMode == RiskAccountMode.unsupported
            ? RiskEligibility.unsupported
            : RiskEligibility.unsupported,
        quality: RiskQuality.partial(
          source: config.source,
          reason:
              'Positions were returned but none satisfy long isolated MARGIN scope',
          observedAt: config.fetchedAt,
        ),
        candidates: List.unmodifiable(normalized),
        message: 'No eligible long isolated MARGIN position',
      );
    }

    RiskPosition? selected;
    if (selectedEpisodeKey != null && selectedEpisodeKey.isNotEmpty) {
      selected = eligible.firstWhere(
        (candidate) => candidate.episodeKey == selectedEpisodeKey,
        orElse: () => eligible.first,
      );
    } else if (selectedPositionId != null && selectedPositionId.isNotEmpty) {
      selected = eligible.firstWhere(
        (candidate) => candidate.positionId == selectedPositionId,
        orElse: () => eligible.first,
      );
    } else {
      selected = eligible.first;
    }
    final selectionChanged =
        (selectedEpisodeKey != null &&
            selectedEpisodeKey.isNotEmpty &&
            selected.episodeKey != selectedEpisodeKey) ||
        (selectedPositionId != null &&
            selectedPositionId.isNotEmpty &&
            selected.positionId != selectedPositionId);

    final enriched = await _enrichPosition(selected, namespace: namespace);
    return RiskPositionSelection(
      status: RiskEligibility.eligible,
      quality: enriched.quality,
      position: enriched,
      candidates: List.unmodifiable(eligible),
      selectionChanged: selectionChanged,
      message: selectionChanged
          ? 'Selected position changed to the first eligible position'
          : null,
    );
  }

  Future<RiskPosition> _enrichPosition(
    RiskPosition position, {
    required String? namespace,
  }) async {
    OkxRiskFeeRateDto? fee;
    OkxRiskInstrumentDto? instrument;
    OkxRiskInterestRateDto? rate;
    RiskInterestLedgerResult? ledger;
    final missing = <String>[];
    final instId = position.instrumentId;
    final liabilityCurrency = position.liabilityCurrency;
    final fetchNow = clock();
    // Source uTime bounds the exchange position snapshot. observedAt is the
    // local fetch time and is kept separate so today's ledger window can be
    // covered through the injected clock without pretending uTime was a
    // fetch observation.
    final cutoff = position.updatedAt ?? position.observedAt ?? fetchNow;
    final openedAt = position.createdAt;
    if (namespace == null) {
      missing.add('Account uid is unresolved; this position is ephemeral');
    }
    try {
      instrument = await getMarginInstrument(instId: instId);
      if (instrument == null || instrument.groupId == null) {
        missing.add('Exact instrument fee group is unavailable');
      }
    } catch (_) {
      missing.add('Exact instrument fee group is unavailable');
    }
    try {
      fee = await getTradeFee(instId: instId);
      if (fee == null || fee.takerExpenseRateFor(instrument?.groupId) == null) {
        missing.add('Applicable MARGIN fee rate unavailable');
      }
    } catch (_) {
      missing.add('Applicable MARGIN fee rate unavailable');
    }
    if (liabilityCurrency != null && liabilityCurrency.isNotEmpty) {
      try {
        rate = await getInterestRate(ccy: liabilityCurrency);
      } catch (_) {
        missing.add('Hourly borrowing rate unavailable');
      }
      try {
        ledger = await getInterestLedger(
          instId: instId,
          ccy: liabilityCurrency,
          episodeStart: openedAt,
          episodeEnd: fetchNow,
        );
        if (!ledger.complete) {
          missing.add(
            ledger.reason ?? 'Settled-interest attribution is incomplete',
          );
        }
      } catch (_) {
        missing.add('Settled-interest attribution unavailable');
      }
    } else {
      missing.add('Liability currency is unavailable');
    }

    final retainedHistoryStart = cutoff.subtract(const Duration(days: 365));
    final windowEntries = <OkxRiskInterestAccruedDto>[];
    var windowAmbiguous = ledger?.ambiguousEntries == true;
    if (ledger != null) {
      for (final entry in ledger.entries) {
        final occurredAt = entry.occurredAt;
        if (occurredAt == null || entry.amount == null) {
          windowAmbiguous = true;
          continue;
        }
        if (openedAt != null && occurredAt.isBefore(openedAt)) continue;
        if (occurredAt.isAfter(cutoff)) continue;
        windowEntries.add(entry);
      }
    }
    // A complete API page set is still insufficient when the account/episode
    // start predates the endpoint's retained history or when position-size
    // changes cannot be ruled out.  Keep T unavailable until that proof is
    // supplied by a future history adapter.
    final historyCoversEpisode =
        ledger?.complete == true &&
        !windowAmbiguous &&
        openedAt != null &&
        !openedAt.isBefore(retainedHistoryStart) &&
        ledger?.coverageFrom != null &&
        !openedAt.isBefore(ledger!.coverageFrom!) &&
        ledger.coverageTo != null &&
        !ledger.coverageTo!.isBefore(cutoff);
    if (!historyCoversEpisode) {
      missing.add('Position lifetime coverage or size stability is unproven');
    } else {
      // P01 has no position-size history endpoint, so an increase/reduction
      // cannot be ruled out.  Never claim lifetime allocation from a complete
      // interest page set alone.
      missing.add('Position size-change history is unavailable');
    }
    final actualInterestToday = ledger == null
        ? null
        : _actualInterestToday(
            ledger,
            now: fetchNow,
            positionOpenedAt: openedAt,
          );
    final costs = RiskCostAttribution(
      settledInterest: historyCoversEpisode && !windowAmbiguous
          ? windowEntries.fold<double>(
              0,
              (total, entry) => total + entry.amount!.abs(),
            )
          : null,
      unbilledInterest: position.reportedInterest?.abs(),
      additionalActualCosts: null,
      actualInterestToday: actualInterestToday,
      coverage: RiskCostCoverage(
        complete: false,
        reason: missing.isEmpty
            ? 'Position lifetime cost attribution is not proven complete'
            : missing.join('; '),
        positionOpenedAt: openedAt,
        coverageFrom: ledger?.coverageFrom,
        coverageTo: ledger?.coverageTo,
      ),
      observedAt: ledger?.observedAt,
      source: ledger == null ? null : 'OKX interest-accrued ledger',
    );
    final enriched = _copyWithDetails(
      position,
      namespace: namespace,
      fee: fee,
      feeGroupId: instrument?.groupId,
      rate: rate,
      costs: costs,
      missing: missing,
    );
    return enriched;
  }

  RiskActualInterestToday _actualInterestToday(
    RiskInterestLedgerResult ledger, {
    required DateTime now,
    required DateTime? positionOpenedAt,
  }) {
    final localNow = now.toLocal();
    final localDayStart = DateTime(localNow.year, localNow.month, localNow.day);
    final windowStart =
        positionOpenedAt != null && positionOpenedAt.isAfter(localDayStart)
        ? positionOpenedAt
        : localDayStart;
    final windowEnd = now;
    var knownSubtotal = 0.0;
    for (final entry in ledger.entries) {
      final occurredAt = entry.occurredAt;
      final amount = entry.amount;
      if (occurredAt == null ||
          amount == null ||
          occurredAt.isBefore(windowStart) ||
          occurredAt.isAfter(windowEnd)) {
        continue;
      }
      // Interest is a cost magnitude. The signed raw value remains available
      // on the DTO for audit evidence, while this typed subtotal is safe to
      // use as an accrued-cost display value.
      knownSubtotal += amount.abs();
    }
    final validWindow = !windowStart.isAfter(windowEnd);
    final queryCoversWindow =
        ledger.requestedFrom != null &&
        !ledger.requestedFrom!.isAfter(windowStart) &&
        ledger.requestedTo != null &&
        !ledger.requestedTo!.isBefore(windowEnd);
    // A completed request window proves zero for an empty day. A non-empty
    // day also needs at least one timestamped, attributable row so a malformed
    // or unscoped record cannot be reported as paid interest.
    final coverageComplete =
        validWindow &&
        queryCoversWindow &&
        ledger.complete &&
        !ledger.ambiguousEntries &&
        (ledger.entries.isEmpty || ledger.coverageFrom != null);
    final quality = coverageComplete
        ? RiskQuality.complete(
            source: 'OKX interest-accrued ledger',
            observedAt: ledger.observedAt,
            sourceAt: ledger.coverageTo ?? ledger.requestedTo,
          )
        : RiskQuality.partial(
            source: 'OKX interest-accrued ledger',
            reason:
                ledger.reason ??
                'Local-day actual-interest coverage is incomplete',
            observedAt: ledger.observedAt,
            sourceAt: ledger.coverageTo ?? ledger.requestedTo,
          );
    return RiskActualInterestToday(
      amount: coverageComplete ? knownSubtotal : null,
      knownSubtotal: knownSubtotal.isFinite && knownSubtotal >= 0
          ? knownSubtotal
          : 0,
      windowStart: windowStart,
      windowEnd: windowEnd,
      quality: quality,
      coverageComplete: coverageComplete,
      observedAt: ledger.observedAt,
      sourceAt: ledger.coverageTo ?? ledger.requestedTo,
      source: 'OKX interest-accrued ledger',
    );
  }

  RiskPosition _toPosition(
    OkxRiskPositionDto dto,
    OkxRiskAccountConfigDto config, {
    required String? namespace,
  }) {
    final base = dto.baseCurrency;
    final quote =
        dto.instId
            ?.split('-')
            .skip(1)
            .firstWhere((part) => part.isNotEmpty, orElse: () => 'USDT') ??
        'USDT';
    final positionCurrency = dto.posCcy?.toUpperCase();
    final marginCurrency = dto.ccy?.toUpperCase();
    final mode = config.normalizedMode;
    final collateral =
        mode == RiskAccountMode.unsupported || marginCurrency == null
        ? RiskCollateralCurrency.unsupported
        : marginCurrency == base?.toUpperCase()
        ? RiskCollateralCurrency.base
        : marginCurrency == quote.toUpperCase()
        ? RiskCollateralCurrency.quote
        : RiskCollateralCurrency.unsupported;
    final positionSide = dto.posSide ?? 'net';
    final rawQuantity = dto.quantity;
    final quantity = _normalizedQuantity(dto, mode);
    final eligibility = _eligibility(
      dto,
      config,
      base: base,
      quote: quote,
      collateral: collateral,
      quantity: quantity,
    );
    final hasIdentity =
        dto.instId != null &&
        dto.instId!.isNotEmpty &&
        dto.posId != null &&
        dto.posId!.isNotEmpty &&
        dto.createdAt != null;
    final identityReason = namespace == null
        ? 'Account uid is unresolved; this position is ephemeral'
        : null;
    final quality = mode == RiskAccountMode.unsupported
        ? RiskQuality.unsupported(
            source: dto.source,
            reason: 'OKX isolated margin accounting mode is unsupported',
            observedAt: dto.observedAt,
            sourceAt: dto.sourceAt,
          )
        : !hasIdentity || eligibility != RiskEligibility.eligible
        ? RiskQuality.partial(
            source: dto.source,
            reason: [
              _eligibilityText(eligibility),
              if (identityReason != null) identityReason,
            ].join('; '),
            observedAt: dto.observedAt,
            sourceAt: dto.sourceAt,
          )
        : RiskQuality.partial(
            source: dto.source,
            reason: [
              'Cost and applicable-rate inputs require enrichment',
              if (identityReason != null) identityReason,
            ].join('; '),
            observedAt: dto.observedAt,
            sourceAt: dto.sourceAt,
          );
    return RiskPosition(
      instrumentId: dto.instId ?? '',
      instrumentType: dto.instType ?? 'MARGIN',
      mode: mode,
      collateralCurrency: collateral,
      positionSide: positionSide,
      accountNamespace: namespace,
      positionId: dto.posId,
      createdAt: dto.createdAt,
      updatedAt: dto.updatedAt,
      observedAt: dto.observedAt,
      baseCurrency: base,
      quoteCurrency: quote,
      positionCurrency: positionCurrency,
      accountCurrency: marginCurrency,
      liabilityCurrency: dto.liabCcy?.toUpperCase(),
      rawQuantity: rawQuantity,
      quantity: quantity,
      margin: dto.marginValue,
      markPrice: dto.markPrice,
      entryPrice: dto.averagePrice,
      liquidationPrice: dto.liquidationPrice,
      unrealizedPnl: dto.unrealizedPnl,
      reportedLeverage: dto.leverage,
      marginRatio: dto.marginRatio,
      maintenanceRequirement: dto.maintenanceRequirement,
      reportedLiability: dto.liability,
      reportedInterest: dto.accruedInterest,
      baseBalance: dto.baseBalanceValue,
      quoteBalance: dto.quoteBalanceValue,
      baseBorrowed: dto.baseBorrowedValue,
      quoteBorrowed: dto.quoteBorrowedValue,
      baseInterest: dto.baseInterestValue,
      quoteInterest: dto.quoteInterestValue,
      quality: quality,
      eligibility: eligibility,
      source: dto.source,
    );
  }

  RiskPosition _copyWithDetails(
    RiskPosition position, {
    required String? namespace,
    required OkxRiskFeeRateDto? fee,
    required String? feeGroupId,
    required OkxRiskInterestRateDto? rate,
    required RiskCostAttribution costs,
    required List<String> missing,
  }) {
    final feeExpense = fee?.takerExpenseRateFor(feeGroupId);
    final complete =
        missing.isEmpty && feeExpense != null && rate?.hourlyRate != null;
    final preservedQuality = switch (position.quality.status) {
      RiskQualityStatus.stale ||
      RiskQualityStatus.unavailable ||
      RiskQualityStatus.error ||
      RiskQualityStatus.unsupported ||
      RiskQualityStatus.empty => position.quality,
      _ => null,
    };
    return RiskPosition(
      instrumentId: position.instrumentId,
      instrumentType: position.instrumentType,
      mode: position.mode,
      collateralCurrency: position.collateralCurrency,
      positionSide: position.positionSide,
      accountNamespace: namespace ?? position.accountNamespace,
      positionId: position.positionId,
      createdAt: position.createdAt,
      updatedAt: position.updatedAt,
      observedAt: position.observedAt,
      baseCurrency: position.baseCurrency,
      quoteCurrency: position.quoteCurrency,
      positionCurrency: position.positionCurrency,
      accountCurrency: position.accountCurrency,
      liabilityCurrency: position.liabilityCurrency,
      rawQuantity: position.rawQuantity,
      quantity: position.quantity,
      margin: position.margin,
      markPrice: position.markPrice,
      entryPrice: position.entryPrice,
      liquidationPrice: position.liquidationPrice,
      unrealizedPnl: position.unrealizedPnl,
      reportedLeverage: position.reportedLeverage,
      marginRatio: position.marginRatio,
      maintenanceRequirement: position.maintenanceRequirement,
      reportedLiability: position.reportedLiability,
      reportedInterest: position.reportedInterest,
      baseBalance: position.baseBalance,
      quoteBalance: position.quoteBalance,
      baseBorrowed: position.baseBorrowed,
      quoteBorrowed: position.quoteBorrowed,
      baseInterest: position.baseInterest,
      quoteInterest: position.quoteInterest,
      hourlyBorrowRate: rate?.hourlyRate,
      entryFeeRate: feeExpense,
      exitFeeRate: feeExpense,
      costAttribution: costs,
      quality:
          preservedQuality ??
          (complete
              ? RiskQuality.complete(
                  source: position.source,
                  observedAt: position.observedAt,
                  sourceAt: position.updatedAt,
                )
              : RiskQuality.partial(
                  source: position.source,
                  reason: missing.isEmpty
                      ? 'Cost or lifetime coverage remains incomplete'
                      : missing.join('; '),
                  observedAt: position.observedAt,
                  sourceAt: position.updatedAt,
                )),
      eligibility: position.eligibility,
      source: position.source,
    );
  }

  RiskEligibility _eligibility(
    OkxRiskPositionDto dto,
    OkxRiskAccountConfigDto config, {
    required String? base,
    required String quote,
    required RiskCollateralCurrency collateral,
    required double? quantity,
  }) {
    final instrumentParts = dto.instId?.split('-');
    final validInstrumentId =
        instrumentParts != null &&
        instrumentParts.length == 2 &&
        instrumentParts.every((part) => part.isNotEmpty);
    if (config.normalizedMode == RiskAccountMode.unsupported ||
        (config.normalizedMode == RiskAccountMode.oldMode &&
            collateral != RiskCollateralCurrency.base) ||
        dto.instType?.toUpperCase() != 'MARGIN' ||
        dto.mgnMode?.toLowerCase() != 'isolated' ||
        collateral == RiskCollateralCurrency.unsupported ||
        !validInstrumentId ||
        base == null ||
        quote.toUpperCase() != 'USDT' ||
        dto.posCcy?.toUpperCase() != base.toUpperCase() ||
        dto.liabCcy?.toUpperCase() != quote.toUpperCase()) {
      return RiskEligibility.unsupported;
    }
    if (dto.instId == null ||
        dto.posId == null ||
        dto.createdAt == null ||
        dto.posCcy == null ||
        dto.liabCcy == null) {
      return RiskEligibility.invalid;
    }
    if (dto.posSide?.toLowerCase() == 'short' ||
        dto.posSide?.toLowerCase() == 'sell' ||
        (dto.quantity != null && dto.quantity! < 0) ||
        dto.posCcy?.toUpperCase() == quote.toUpperCase()) {
      return RiskEligibility.shortPosition;
    }
    if (quantity == null || quantity <= 0) return RiskEligibility.zeroPosition;
    return RiskEligibility.eligible;
  }

  double? _normalizedQuantity(OkxRiskPositionDto dto, RiskAccountMode mode) {
    final raw = dto.quantity;
    if (raw == null || raw <= 0) return null;
    if (mode == RiskAccountMode.oldMode) {
      final margin = dto.marginValue;
      if (margin == null) return null;
      final value = raw - margin;
      return value > 0 ? value : null;
    }
    return raw;
  }

  String _eligibilityText(RiskEligibility eligibility) {
    switch (eligibility) {
      case RiskEligibility.eligible:
        return 'Eligible position';
      case RiskEligibility.empty:
        return 'No position';
      case RiskEligibility.unsupported:
        return 'Unsupported or incomplete position';
      case RiskEligibility.invalid:
        return 'Invalid position identity';
      case RiskEligibility.shortPosition:
        return 'Short position is outside the long-only scope';
      case RiskEligibility.zeroPosition:
        return 'Position quantity is zero';
    }
  }

  int _positionComparator(RiskPosition left, RiskPosition right) {
    final byInstrument = left.instrumentId.compareTo(right.instrumentId);
    if (byInstrument != 0) return byInstrument;
    final byPosition = (left.positionId ?? '').compareTo(
      right.positionId ?? '',
    );
    if (byPosition != 0) return byPosition;
    return (left.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
      right.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Future<Response<dynamic>> _get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      return await _dio.get<dynamic>(
        endpoint,
        queryParameters: queryParameters,
        options: Options(extra: const <String, Object>{'requiresAuth': true}),
      );
    } on DioException catch (error) {
      throw RiskRepositoryException(
        _dioErrorMessage(error),
        statusCode: error.response?.statusCode,
        endpoint: endpoint,
        cause: error,
      );
    }
  }

  List<Map<String, dynamic>> _dataList(
    Response<dynamic> response,
    String endpoint,
  ) {
    final raw = response.data;
    if (raw is! Map) {
      throw RiskRepositoryException(
        'Malformed response envelope',
        endpoint: endpoint,
      );
    }
    final envelope = Map<String, dynamic>.from(raw);
    final code = envelope['code']?.toString();
    if (code != '0') {
      throw RiskRepositoryException(
        envelope['msg']?.toString() ?? 'OKX returned an error',
        endpoint: endpoint,
      );
    }
    final data = envelope['data'];
    if (data is! List) {
      throw RiskRepositoryException(
        'Malformed data array in response envelope',
        endpoint: endpoint,
      );
    }
    if (data.any((item) => item is! Map)) {
      throw RiskRepositoryException(
        'Malformed object in response data array',
        endpoint: endpoint,
      );
    }
    return data
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  String _dioErrorMessage(DioException error) {
    if (error.response?.statusCode == 401) {
      return 'Authenticated OKX request was unauthorized';
    }
    if (error.response?.statusCode == 429) {
      return 'OKX request rate limit reached';
    }
    return error.message ?? 'OKX request failed';
  }
}
