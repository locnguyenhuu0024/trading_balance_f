import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/portfolio/data/risk/okx_risk_dto.dart';
import 'package:trading_balance_f/features/portfolio/data/risk/risk_repository.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_engine.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_models.dart';
import 'package:trading_balance_f/features/portfolio/data/risk/risk_request_coordinator.dart';

void main() {
  test(
    'RED-001 rejects malformed values and keeps ambiguous costs unavailable',
    () async {
      final malformed = OkxRiskPositionDto.fromJson({
        'instId': 'SUI-USDT',
        'instType': 'MARGIN',
        'mgnMode': 'isolated',
        'posSide': 'net',
        'pos': 'not-a-number',
        'markPx': 'NaN',
        'avgPx': '',
        'liqPx': 'Infinity',
        'upl': '-200',
        'interest': '0',
        'mgnRatio': '4',
      });
      expect(malformed.quantity, isNull);
      expect(malformed.markPrice, isNull);
      expect(malformed.averagePrice, isNull);
      expect(malformed.liquidationPrice, isNull);
      expect(malformed.accruedInterest, 0);

      final incompatibleLoanType = OkxRiskInterestAccruedDto.fromJson({
        'instId': 'SUI-USDT',
        'ccy': 'USDT',
        'interest': '1',
        'type': 'interest',
        'ts': '1788220801000',
      });
      expect(incompatibleLoanType.matchesMarginCost, isFalse);

      final adapter = _RecordingAdapter((options) {
        if (options.uri.path == RiskRepository.configEndpoint) {
          return _ok([
            {'uid': 'uid-red', 'mgnIsoMode': 'auto_transfers_ccy'},
          ]);
        }
        if (options.uri.path == RiskRepository.positionsEndpoint) {
          return _ok([_positionJson()]);
        }
        if (options.uri.path == RiskRepository.instrumentsEndpoint) {
          return _ok([
            {'instId': 'SUI-USDT', 'instType': 'MARGIN', 'groupId': '7'},
          ]);
        }
        if (options.uri.path == RiskRepository.feeEndpoint) {
          return _ok([
            {
              'instType': 'MARGIN',
              'instId': 'SUI-USDT',
              'feeGroup': [
                {'groupId': '7', 'taker': '-0.001'},
              ],
              'taker': '-0.001',
            },
          ]);
        }
        if (options.uri.path == RiskRepository.interestRateEndpoint) {
          return _ok([
            {'ccy': 'USDT', 'interestRate': '0.00001'},
          ]);
        }
        if (options.uri.path == RiskRepository.interestAccruedEndpoint) {
          return _ok([
            {
              'instId': 'SUI-USDT',
              'ccy': 'USDT',
              'mgnMode': 'isolated',
              'interest': '100',
              'ts': '1788220801000',
            },
            {
              'instId': 'SUI-USDT',
              'ccy': 'USDT',
              'mgnMode': 'isolated',
              'interest': '2',
              'ts': '1788220802000',
            },
            {
              'instId': 'BTC-USDT',
              'ccy': 'USDT',
              'mgnMode': 'isolated',
              'interest': '900',
              'ts': '1788220803000',
            },
            {
              'ccy': 'USDT',
              'mgnMode': 'isolated',
              'interest': '901',
              'ts': '1788220804000',
            },
            {
              'instId': 'SUI-USDT',
              'ccy': 'USDT',
              'mgnMode': 'isolated',
              'interest': '999',
              'ts': '1788220799000',
            },
          ]);
        }
        throw StateError('Unexpected endpoint ${options.uri.path}');
      });
      final dio = Dio(BaseOptions(baseUrl: 'https://unit.test'))
        ..httpClientAdapter = adapter;
      final repository = RiskRepository(
        dio,
        environment: 'test',
        clock: () => DateTime.utc(2026, 9, 10),
      );
      final selection = await repository.loadPosition();
      expect(selection.status, RiskEligibility.eligible);
      expect(selection.position, isNotNull);
      expect(selection.position!.costAttribution.coverage.complete, isFalse);
      expect(selection.position!.costAttribution.settledInterest, isNull);
      final partialToday =
          selection.position!.costAttribution.actualInterestToday!;
      expect(partialToday.amount, isNull);
      expect(partialToday.knownSubtotal, 0);
      expect(partialToday.quality.status, RiskQualityStatus.partial);
      final ledger = await repository.getInterestLedger(
        instId: 'SUI-USDT',
        ccy: 'USDT',
        episodeStart: DateTime.utc(2026, 9, 1),
        episodeEnd: DateTime.utc(2026, 9, 10),
      );
      expect(ledger.entries, hasLength(2));
      expect(ledger.entries.map((entry) => entry.amount), <double>[100, 2]);
      expect(ledger.ambiguousEntries, isTrue);
      expect(ledger.complete, isFalse);
      final evaluation = const RiskEngine().evaluate(
        // The adapter cannot prove lifetime size stability from an interest
        // page alone, so no True Exit may be emitted from this selection.
        const RiskPosition(
          instrumentId: 'SUI-USDT',
          mode: RiskAccountMode.newMode,
          collateralCurrency: RiskCollateralCurrency.quote,
          quantity: 100,
          rawQuantity: 100,
          margin: 700,
          markPrice: 10,
          entryPrice: 11,
          liquidationPrice: 6,
          unrealizedPnl: -200,
          reportedLiability: 1198,
          reportedInterest: 2,
          marginRatio: 4,
          quality: RiskQuality.complete(source: 'fixture'),
          costAttribution: RiskCostAttribution(
            unbilledInterest: 2,
            coverage: RiskCostCoverage(
              complete: false,
              reason: 'shared or cross-episode ledger row',
            ),
          ),
        ),
      );
      expect(evaluation.trueExitPrice, isNull);
      expect(adapter.requests, isNotEmpty);
      expect(
        adapter.requests.every((request) => request.method == 'GET'),
        isTrue,
      );
    },
  );

  test(
    'GREEN-001 parses actual OKX fields and preserves GET-only/account identity behavior',
    () async {
      final dto = OkxRiskPositionDto.fromJson(_positionJson());
      expect(dto.quantity, 100);
      expect(dto.markPrice, 10);
      expect(dto.averagePrice, 11);
      expect(dto.liquidationPrice, 6);
      expect(dto.marginRatio, 4);
      expect(dto.maintenanceRequirement, 100);
      expect(dto.liability, -1198);
      expect(dto.accruedInterest, 2);
      expect(dto.createdAt, DateTime.utc(2026, 9, 1));
      final fetchTime = DateTime.utc(2026, 9, 10, 12);
      final timestampedDto = OkxRiskPositionDto.fromJson(
        _positionJson(),
        fetchedAt: fetchTime,
      );
      expect(timestampedDto.observedAt, fetchTime);
      expect(timestampedDto.sourceAt, DateTime.utc(2026, 9, 10));

      final fee = OkxRiskFeeRateDto.fromJson({
        'instType': 'MARGIN',
        'instId': 'SUI-USDT',
        'taker': '-0.001',
        'feeGroup': [
          {'groupId': '7', 'taker': '-0.001'},
          {'groupId': '8', 'taker': '-0.002'},
        ],
      });
      expect(fee.takerExpenseRateFor(), isNull);
      expect(fee.takerExpenseRateFor('7'), closeTo(0.001, 1e-12));
      expect(fee.takerExpenseRateFor('missing'), isNull);
      final rebate = OkxRiskFeeRateDto.fromJson({'taker': '0.0003'});
      expect(rebate.takerExpenseRate, 0);
      final rate = OkxRiskInterestRateDto.fromJson({
        'ccy': 'USDT',
        'interestRate': '0.00001',
      });
      expect(rate.hourlyRate, closeTo(0.00001, 1e-15));
      final marketLoanInterest = OkxRiskInterestAccruedDto.fromJson({
        'instId': 'SUI-USDT',
        'ccy': 'USDT',
        'interest': '0.25',
        'type': '2',
        'ts': '1788220800000',
      });
      expect(marketLoanInterest.matchesMarginCost, isTrue);

      final adapter = _RecordingAdapter((options) {
        if (options.uri.path == RiskRepository.configEndpoint) {
          return _ok([
            {'uid': 'uid-green', 'mgnIsoMode': 'auto_transfers_ccy'},
          ]);
        }
        if (options.uri.path == RiskRepository.positionsEndpoint) {
          return _ok([_positionJson()]);
        }
        if (options.uri.path == RiskRepository.instrumentsEndpoint) {
          return _ok([
            {'instId': 'SUI-USDT', 'instType': 'MARGIN', 'groupId': '7'},
          ]);
        }
        if (options.uri.path == RiskRepository.feeEndpoint) {
          return _ok([
            {
              'instType': 'MARGIN',
              'instId': 'SUI-USDT',
              'feeGroup': [
                {'groupId': '7', 'taker': '-0.001'},
              ],
              'taker': '-0.001',
            },
          ]);
        }
        if (options.uri.path == RiskRepository.interestRateEndpoint) {
          return _ok([
            {'ccy': 'USDT', 'interestRate': '0.00001'},
          ]);
        }
        if (options.uri.path == RiskRepository.interestAccruedEndpoint) {
          // Documented interest-accrued rows do not carry a position id. The
          // request's isolated scope supplies the mode for this attribution.
          return _ok([
            {
              'instId': 'SUI-USDT',
              'ccy': 'USDT',
              'interest': '0.25',
              'type': '2',
              'ts': _epoch(DateTime.utc(2026, 9, 10)),
            },
          ]);
        }
        throw StateError('Unexpected endpoint ${options.uri.path}');
      });
      final dio = Dio(BaseOptions(baseUrl: 'https://unit.test'))
        ..httpClientAdapter = adapter;
      final repository = RiskRepository(
        dio,
        environment: 'test',
        clock: () => DateTime.utc(2026, 9, 10),
      );
      final positions = await repository.getPositions();
      expect(positions, hasLength(1));
      final instrument = await repository.getMarginInstrument(
        instId: 'SUI-USDT',
      );
      expect(instrument?.groupId, '7');
      final namespace = await repository.resolveAccountNamespace();
      expect(namespace, isNotNull);
      expect(namespace, hasLength(64));
      expect(namespace, isNot(contains('uid-green')));
      final loaded = await repository.loadPosition();
      expect(loaded.status, RiskEligibility.eligible);
      expect(loaded.position?.entryFeeRate, closeTo(0.001, 1e-12));
      expect(loaded.position?.hourlyBorrowRate, closeTo(0.00001, 1e-15));
      expect(loaded.position?.costAttribution.coverage.complete, isFalse);
      expect(
        loaded.position?.costAttribution.actualInterestToday?.amount,
        closeTo(0.25, 1e-12),
      );
      expect(
        loaded.position?.costAttribution.actualInterestToday?.knownSubtotal,
        closeTo(0.25, 1e-12),
      );
      expect(
        loaded.position?.costAttribution.actualInterestToday?.quality.status,
        RiskQualityStatus.complete,
      );
      expect(
        loaded.position?.episodeKey,
        '68ff32dda9809bde2773ecf1203a0faf80c4467eb5faedc0971c7340e8a38b95:position-1:1788220800000',
      );

      final vanishedSelectionRepository = _fixtureRepository(
        uid: 'uid-selection',
        mode: 'auto_transfers_ccy',
        positions: <Map<String, dynamic>>[
          _positionJson(posId: 'zeta'),
          _positionJson(posId: 'alpha'),
        ],
      );
      final vanishedSelection = await vanishedSelectionRepository.loadPosition(
        selectedEpisodeKey: 'selection:missing:episode',
      );
      expect(vanishedSelection.status, RiskEligibility.eligible);
      expect(vanishedSelection.selectionChanged, isTrue);
      expect(vanishedSelection.position?.positionId, 'alpha');
      expect(vanishedSelection.message, contains('changed'));

      final shortSelection = await _fixtureRepository(
        uid: 'uid-short',
        mode: 'auto_transfers_ccy',
        positions: <Map<String, dynamic>>[
          _positionJson(posId: 'short', posSide: 'short'),
        ],
      ).loadPosition();
      expect(shortSelection.status, RiskEligibility.unsupported);
      expect(
        shortSelection.candidates.single.eligibility,
        RiskEligibility.shortPosition,
      );

      final futuresSelection = await _fixtureRepository(
        uid: 'uid-futures',
        mode: 'auto_transfers_ccy',
        positions: <Map<String, dynamic>>[
          _positionJson(posId: 'futures', instType: 'FUTURES'),
        ],
      ).loadPosition();
      expect(futuresSelection.status, RiskEligibility.unsupported);
      expect(
        futuresSelection.candidates.single.eligibility,
        RiskEligibility.unsupported,
      );

      final ephemeralSelection = await _fixtureRepository(
        uid: null,
        mode: 'auto_transfers_ccy',
        positions: <Map<String, dynamic>>[_positionJson(posId: 'ephemeral')],
      ).loadPosition();
      expect(ephemeralSelection.status, RiskEligibility.eligible);
      expect(ephemeralSelection.position?.accountNamespace, isNull);
      expect(ephemeralSelection.position?.episodeKey, isEmpty);
      expect(
        ephemeralSelection.position?.quality.reason,
        contains('ephemeral'),
      );

      final accountA = await _fixtureRepository(
        uid: 'uid-account-a',
        mode: 'auto_transfers_ccy',
        positions: <Map<String, dynamic>>[_positionJson(posId: 'shared')],
      ).loadPosition();
      final accountBRepository = _fixtureRepository(
        uid: 'uid-account-b',
        mode: 'auto_transfers_ccy',
        positions: <Map<String, dynamic>>[_positionJson(posId: 'shared')],
      );
      final accountB = await accountBRepository.loadPosition();
      expect(accountA.position?.accountNamespace, isNotNull);
      expect(accountB.position?.accountNamespace, isNotNull);
      expect(
        accountA.position?.accountNamespace,
        isNot(equals(accountB.position?.accountNamespace)),
      );
      expect(
        accountA.position?.episodeKey,
        isNot(equals(accountB.position?.episodeKey)),
      );
      final crossAccountSelection = await accountBRepository.loadPosition(
        selectedEpisodeKey: accountA.position!.episodeKey,
      );
      expect(crossAccountSelection.selectionChanged, isTrue);
      expect(
        crossAccountSelection.position?.accountNamespace,
        accountB.position?.accountNamespace,
      );

      final emptyAdapter = _RecordingAdapter((options) {
        if (options.uri.path == RiskRepository.configEndpoint) {
          return _ok([
            {'uid': 'uid-empty', 'mgnIsoMode': 'auto_transfers_ccy'},
          ]);
        }
        if (options.uri.path == RiskRepository.positionsEndpoint) {
          return _ok(<Map<String, dynamic>>[]);
        }
        throw StateError('Unexpected endpoint ${options.uri.path}');
      });
      final emptyRepository = RiskRepository(
        Dio(BaseOptions(baseUrl: 'https://unit.test'))
          ..httpClientAdapter = emptyAdapter,
      );
      final empty = await emptyRepository.loadPosition();
      expect(empty.status, RiskEligibility.empty);
      expect(empty.isEmpty, isTrue);
      expect(
        adapter.requests.every((request) => request.method == 'GET'),
        isTrue,
      );
      expect(
        adapter.requests.map((request) => request.uri.path),
        containsAll(<String>[
          RiskRepository.positionsEndpoint,
          RiskRepository.instrumentsEndpoint,
          RiskRepository.feeEndpoint,
          RiskRepository.interestRateEndpoint,
          RiskRepository.configEndpoint,
        ]),
      );
      final ledgerRequest = adapter.requests.firstWhere(
        (request) => request.uri.path == RiskRepository.interestAccruedEndpoint,
      );
      expect(ledgerRequest.uri.queryParameters['mgnMode'], 'isolated');

      final oldRepository = _fixtureRepository(
        uid: 'uid-old',
        mode: 'automatic',
        positions: <Map<String, dynamic>>[
          _positionJson(
            posId: 'old-position',
            pos: '110',
            margin: '10',
            ccy: 'SUI',
            upl: '-2',
            liab: '-1020',
            interest: '0',
          ),
        ],
      );
      final oldSelection = await oldRepository.loadPosition();
      expect(oldSelection.status, RiskEligibility.eligible);
      expect(
        oldSelection.position?.collateralCurrency,
        RiskCollateralCurrency.base,
      );
      expect(oldSelection.position?.rawQuantity, 110);
      expect(oldSelection.position?.quantity, 100);

      final zeroOldRepository = _fixtureRepository(
        uid: 'uid-old-zero',
        mode: 'automatic',
        positions: <Map<String, dynamic>>[
          _positionJson(
            posId: 'old-zero',
            pos: '10',
            margin: '10',
            ccy: 'SUI',
            upl: '0',
            liab: '0',
            interest: '0',
          ),
        ],
      );
      final zeroOldSelection = await zeroOldRepository.loadPosition();
      expect(zeroOldSelection.status, RiskEligibility.unsupported);
      expect(
        zeroOldSelection.candidates.single.eligibility,
        RiskEligibility.zeroPosition,
      );
      expect(zeroOldSelection.candidates.single.quantity, isNull);

      final unsupportedRepository = _fixtureRepository(
        uid: 'uid-unsupported',
        mode: 'quick',
        positions: <Map<String, dynamic>>[_positionJson()],
      );
      final unsupportedSelection = await unsupportedRepository.loadPosition();
      expect(unsupportedSelection.status, RiskEligibility.unsupported);
      expect(
        unsupportedSelection.candidates.single.quality.status,
        RiskQualityStatus.unsupported,
      );

      final errorAdapter = _RecordingAdapter((options) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          message: 'offline fixture',
        );
      });
      final errorRepository = RiskRepository(
        Dio(BaseOptions(baseUrl: 'https://unit.test'))
          ..httpClientAdapter = errorAdapter,
      );
      final errorSelection = await errorRepository.loadPosition();
      expect(errorSelection.status, RiskEligibility.invalid);
      expect(errorSelection.quality.status, RiskQualityStatus.error);
    },
  );

  test('RED-001 rate-safe risk request batch', () async {
    final clock = _BatchClock(DateTime.utc(2026, 9, 10, 12));
    final adapter = _BatchAdapter(clock, positionCount: 1);
    final repository = RiskRepository(
      Dio(BaseOptions(baseUrl: 'https://unit.test'))
        ..httpClientAdapter = adapter,
      environment: 'test',
      clock: clock.now,
      maxLedgerPages: 2,
      requestCoordinator: RiskRequestCoordinator(
        clock: clock.now,
        minimumSpacing: Duration.zero,
      ),
    );

    await repository.loadPositionsBatch();
    await repository.loadPositionsBatch();

    // Before the resumable hard-limit guard, the second capture requests a
    // third page even though maxLedgerPages was already exhausted.
    expect(adapter.ledgerRequests, lessThanOrEqualTo(2));
  });

  test('GREEN-001 rate-safe risk request batch', () async {
    final clock = _BatchClock(DateTime.utc(2026, 9, 10, 12));
    final adapter = _BatchAdapter(clock);
    final coordinator = RiskRequestCoordinator(
      clock: clock.now,
      delay: (duration) async => clock.advance(duration),
    );
    final repository = RiskRepository(
      Dio(BaseOptions(baseUrl: 'https://unit.test'))
        ..httpClientAdapter = adapter,
      environment: 'test',
      clock: clock.now,
      requestCoordinator: coordinator,
    );

    final first = await repository.loadPositionsBatch();
    expect(first.status, RiskEligibility.eligible);
    expect(first.positions, hasLength(2));
    expect(first.ledgerPagesFetched, 2);
    expect(adapter.positionRequests, 1);
    expect(adapter.ledgerRequests, 2);

    final second = await repository.loadPositionsBatch();
    expect(second.positions, hasLength(2));
    expect(adapter.positionRequests, 2);
    expect(adapter.ledgerRequests, 4);
    expect(adapter.ledgerAfter.whereType<String>(), hasLength(2));
    expect(second.positions.map((position) => position.instrumentId), <String>[
      'AAA-USDT',
      'BBB-USDT',
    ]);

    for (final positionCount in <int>[1, 3, 10]) {
      await _assertFairBatchProgress(positionCount);
    }

    final hardLimitClock = _BatchClock(DateTime.utc(2026, 9, 10, 12));
    final hardLimitAdapter = _BatchAdapter(hardLimitClock, positionCount: 1);
    final hardLimitRepository = RiskRepository(
      Dio(BaseOptions(baseUrl: 'https://unit.test'))
        ..httpClientAdapter = hardLimitAdapter,
      environment: 'test',
      clock: hardLimitClock.now,
      maxLedgerPages: 2,
      requestCoordinator: RiskRequestCoordinator(
        clock: hardLimitClock.now,
        minimumSpacing: Duration.zero,
      ),
    );
    final hardLimitFirst = await hardLimitRepository.loadPositionsBatch();
    final hardLimitSecond = await hardLimitRepository.loadPositionsBatch();
    final hardLimitThird = await hardLimitRepository.loadPositionsBatch();
    expect(hardLimitFirst.ledgerPagesFetched, 2);
    expect(hardLimitSecond.ledgerPagesFetched, 0);
    expect(hardLimitThird.ledgerPagesFetched, 0);
    expect(hardLimitAdapter.ledgerRequests, 2);
    final hardLimitResult = hardLimitSecond.ledgerResults.values.single;
    expect(hardLimitResult.pages, 2);
    expect(hardLimitResult.complete, isFalse);
    expect(hardLimitResult.reason, contains('maxLedgerPages'));
  });
}

Future<void> _assertFairBatchProgress(int positionCount) async {
  final clock = _BatchClock(DateTime.utc(2026, 9, 10, 12));
  final adapter = _BatchAdapter(clock, positionCount: positionCount);
  final repository = RiskRepository(
    Dio(BaseOptions(baseUrl: 'https://unit.test'))..httpClientAdapter = adapter,
    environment: 'test',
    clock: clock.now,
    maxLedgerPages: 20,
    requestCoordinator: RiskRequestCoordinator(
      clock: clock.now,
      minimumSpacing: Duration.zero,
    ),
  );
  final captureCount = positionCount == 1
      ? 3
      : positionCount == 3
      ? 4
      : 6;
  for (var capture = 0; capture < captureCount; capture++) {
    final batch = await repository.loadPositionsBatch();
    expect(batch.positions, hasLength(positionCount));
    expect(batch.ledgerPagesFetched, 2);
  }

  expect(adapter.positionRequests, captureCount);
  expect(adapter.ledgerRequests, captureCount * 2);
  final counts = adapter.ledgerPageNumbers.values.toList();
  expect(counts, hasLength(positionCount));
  final minCount = counts.reduce((left, right) => left < right ? left : right);
  final maxCount = counts.reduce((left, right) => left > right ? left : right);
  expect(maxCount - minCount, lessThanOrEqualTo(1));
  for (final after in adapter.ledgerAfterByInstrument.values) {
    expect(after.first, isNull);
    expect(after.skip(1).every((value) => value is String), isTrue);
    expect(after.skip(1).toSet(), hasLength(after.length - 1));
  }
}

Map<String, dynamic> _ok(Object data) => <String, dynamic>{
  'code': '0',
  'msg': '',
  'data': data,
};

String _epoch(DateTime value) => value.millisecondsSinceEpoch.toString();

Map<String, dynamic> _positionJson({
  String instId = 'SUI-USDT',
  String instType = 'MARGIN',
  String posSide = 'net',
  String pos = '100',
  String posId = 'position-1',
  String margin = '700',
  String ccy = 'USDT',
  String posCcy = 'SUI',
  String liabCcy = 'USDT',
  String upl = '-200',
  String liab = '-1198',
  String interest = '2',
}) => <String, dynamic>{
  'instId': instId,
  'instType': instType,
  'mgnMode': 'isolated',
  'posSide': posSide,
  'pos': pos,
  'posId': posId,
  'posCcy': posCcy,
  'ccy': ccy,
  'liabCcy': liabCcy,
  'avgPx': '11',
  'markPx': '10',
  'liqPx': '6',
  'margin': margin,
  'upl': upl,
  'lever': '2',
  'mgnRatio': '4',
  'mmr': '100',
  'liab': liab,
  'interest': interest,
  'cTime': '1788220800000',
  'uTime': '1788998400000',
};

RiskRepository _fixtureRepository({
  required String? uid,
  required String mode,
  required List<Map<String, dynamic>> positions,
}) {
  final adapter = _RecordingAdapter((options) {
    if (options.uri.path == RiskRepository.configEndpoint) {
      return _ok([
        <String, dynamic>{if (uid != null) 'uid': uid, 'mgnIsoMode': mode},
      ]);
    }
    if (options.uri.path == RiskRepository.positionsEndpoint) {
      return _ok(positions);
    }
    if (options.uri.path == RiskRepository.instrumentsEndpoint) {
      return _ok([
        {'instId': 'SUI-USDT', 'instType': 'MARGIN', 'groupId': '7'},
      ]);
    }
    if (options.uri.path == RiskRepository.feeEndpoint) {
      return _ok([
        {
          'instType': 'MARGIN',
          'instId': 'SUI-USDT',
          'feeGroup': [
            {'groupId': '7', 'taker': '-0.001'},
          ],
        },
      ]);
    }
    if (options.uri.path == RiskRepository.interestRateEndpoint) {
      return _ok([
        {'ccy': 'USDT', 'interestRate': '0.00001'},
      ]);
    }
    if (options.uri.path == RiskRepository.interestAccruedEndpoint) {
      return _ok(<Map<String, dynamic>>[]);
    }
    throw StateError('Unexpected endpoint ${options.uri.path}');
  });
  return RiskRepository(
    Dio(BaseOptions(baseUrl: 'https://unit.test'))..httpClientAdapter = adapter,
    environment: 'test',
    clock: () => DateTime.utc(2026, 9, 10),
  );
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.handler);

  final Object Function(RequestOptions options) handler;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return _responseBody(handler(options));
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _responseBody(Object data) {
  return ResponseBody.fromString(
    jsonEncode(data),
    200,
    headers: <String, List<String>>{
      'content-type': <String>['application/json'],
    },
  );
}

class _BatchClock {
  _BatchClock(this.value);

  DateTime value;

  DateTime now() => value;

  void advance(Duration duration) {
    value = value.add(duration);
  }
}

class _BatchAdapter implements HttpClientAdapter {
  _BatchAdapter(this.clock, {this.positionCount = 2});

  final _BatchClock clock;
  final int positionCount;
  var positionRequests = 0;
  var ledgerRequests = 0;
  final List<Object?> ledgerAfter = <Object?>[];
  final Map<String, List<Object?>> ledgerAfterByInstrument =
      <String, List<Object?>>{};
  final Map<String, int> ledgerPageNumbers = <String, int>{};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    final Object data;
    if (path == RiskRepository.configEndpoint) {
      data = <Map<String, dynamic>>[
        {'uid': 'uid-batch', 'mgnIsoMode': 'auto_transfers_ccy'},
      ];
    } else if (path == RiskRepository.positionsEndpoint) {
      positionRequests++;
      data = List<Map<String, dynamic>>.generate(positionCount, (index) {
        final letter = String.fromCharCode('A'.codeUnitAt(0) + index);
        final base = List<String>.filled(3, letter).join();
        return _batchPosition(
          '$base-USDT',
          base,
          'position-${base.toLowerCase()}',
        );
      });
    } else if (path == RiskRepository.instrumentsEndpoint) {
      final instId = options.queryParameters['instId']?.toString() ?? '';
      data = <Map<String, dynamic>>[
        {'instId': instId, 'instType': 'MARGIN', 'groupId': '7'},
      ];
    } else if (path == RiskRepository.feeEndpoint) {
      final instId = options.queryParameters['instId']?.toString() ?? '';
      data = <Map<String, dynamic>>[
        {
          'instType': 'MARGIN',
          'instId': instId,
          'feeGroup': [
            {'groupId': '7', 'taker': '-0.001'},
          ],
        },
      ];
    } else if (path == RiskRepository.interestRateEndpoint) {
      data = <Map<String, dynamic>>[
        {'ccy': 'USDT', 'interestRate': '0.00001'},
      ];
    } else if (path == RiskRepository.interestAccruedEndpoint) {
      ledgerRequests++;
      final instId = options.queryParameters['instId']?.toString() ?? '';
      final after = options.queryParameters['after'];
      ledgerAfter.add(after);
      (ledgerAfterByInstrument[instId] ??= <Object?>[]).add(after);
      final page = ledgerPageNumbers[instId] ?? 0;
      ledgerPageNumbers[instId] = page + 1;
      data = List<Map<String, dynamic>>.generate(100, (index) {
        final occurredAt = clock.value.subtract(
          Duration(minutes: page * 100 + index),
        );
        return <String, dynamic>{
          'instId': instId,
          'ccy': 'USDT',
          'mgnMode': 'isolated',
          'interest': '0.25',
          'type': '2',
          'ts': _epoch(occurredAt),
        };
      });
    } else {
      throw StateError('Unexpected endpoint $path');
    }
    return _responseBody(_ok(data));
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _batchPosition(String instId, String base, String posId) =>
    <String, dynamic>{
      'instId': instId,
      'instType': 'MARGIN',
      'mgnMode': 'isolated',
      'posSide': 'net',
      'pos': '100',
      'posId': posId,
      'posCcy': base,
      'ccy': 'USDT',
      'liabCcy': 'USDT',
      'avgPx': '11',
      'markPx': '10',
      'liqPx': '6',
      'margin': '700',
      'upl': '-200',
      'lever': '2',
      'mgnRatio': '4',
      'mmr': '100',
      'liab': '-1198',
      'interest': '2',
      'cTime': '1788220800000',
      'uTime': '1788998400000',
    };
