import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/strategy/domain/strategy_draft_entries.dart';

void main() {
  test('saved exact Long and Short recommendations stay in saved order', () {
    final record = _draft(
      longIds: const ['long-2', 'long-1'],
      shortIds: const ['short-1'],
      supports: [
        _candidate('long-1', 'long', '90.123456789012345678', rank: 1),
        _candidate(
          'long-2',
          'long',
          '89.987654321098765432',
          rank: 2,
          structuralQuality: 3.9,
          entrySuitability: 0.2,
          failureRisk: 0.9,
        ),
      ],
      resistances: [_candidate('short-1', 'short', '110.000000000000000007')],
    );

    final entries = StrategyDraftEntries.fromDraftRecord(record);

    expect(entries.issue, StrategyDraftEntriesIssue.none);
    expect(entries.longCount, 2);
    expect(entries.shortCount, 1);
    expect(
      entries.entries.map(
        (entry) => '${entry.side.wireValue}:${entry.exactPriceText}',
      ),
      [
        'long:89.987654321098765432',
        'long:90.123456789012345678',
        'short:110.000000000000000007',
      ],
    );
    expect(() => entries.entries.clear(), throwsUnsupportedError);
  });

  test(
    'short-only recommendations preserve five rows and ten total maximum',
    () {
      final shortIds = List.generate(5, (index) => 'short-$index');
      final shortOnly = StrategyDraftEntries.fromDraftRecord(
        _draft(
          shortIds: shortIds,
          resistances: [
            for (var index = 0; index < shortIds.length; index++)
              _candidate(
                shortIds[index],
                'short',
                '${110 + index}.000000000000000001',
                rank: index + 1,
              ),
          ],
        ),
      );
      expect(shortOnly.issue, StrategyDraftEntriesIssue.none);
      expect(shortOnly.longCount, 0);
      expect(shortOnly.shortCount, 5);
      expect(shortOnly.entries, hasLength(5));
      expect(shortOnly.entries.map((entry) => entry.levelId), shortIds);

      final longIds = List.generate(5, (index) => 'long-$index');
      final tenEntries = StrategyDraftEntries.fromDraftRecord(
        _draft(
          longIds: longIds,
          shortIds: shortIds,
          supports: [
            for (var index = 0; index < longIds.length; index++)
              _candidate(
                longIds[index],
                'long',
                '${90 - index}.1',
                rank: index + 1,
              ),
          ],
          resistances: [
            for (var index = 0; index < shortIds.length; index++)
              _candidate(
                shortIds[index],
                'short',
                '${110 + index}.1',
                rank: index + 1,
              ),
          ],
        ),
      );
      expect(tenEntries.entries, hasLength(10));
      expect(tenEntries.longCount, 5);
      expect(tenEntries.shortCount, 5);

      final sixLongIds = List.generate(6, (index) => 'long-over-$index');
      _expectAtomicInvalid(
        _draft(
          longIds: sixLongIds,
          supports: [
            for (var index = 0; index < sixLongIds.length; index++)
              _candidate(
                sixLongIds[index],
                'long',
                '${90 - index}.1',
                rank: index + 1,
              ),
          ],
        ),
      );
    },
  );

  test('nested saved snapshots use their immutable generation metadata', () {
    final record = _draft(longIds: const ['long-1']);
    record['snapshot'] = {'aiGeneration': record.remove('aiGeneration')};

    final entries = StrategyDraftEntries.fromDraftRecord(record);

    expect(entries.issue, StrategyDraftEntriesIssue.none);
    expect(entries.entries.single.levelId, 'long-1');
  });

  test(
    'custom recorded thresholds preserve saved IDs without re-screening',
    () {
      final record = _draft(
        longIds: const ['long-custom'],
        supports: [
          _candidate(
            'long-custom',
            'long',
            '90',
            structuralQuality: 3,
            entrySuitability: 0.55,
            failureRisk: 0.45,
          ),
        ],
      );
      record['aiGeneration']['recommendation'] = {
        'version': 'ai-jev-selection-v1',
        'maxPerSide': 5,
        'minStructuralQuality': 3,
        'minEntrySuitabilityProbability': 0.55,
        'maxFailureRiskProbability': 0.45,
        'longLevelIds': ['long-custom'],
        'shortLevelIds': <String>[],
      };

      final entries = StrategyDraftEntries.fromDraftRecord(record);

      expect(entries.issue, StrategyDraftEntriesIssue.none);
      expect(entries.entries.map((entry) => entry.levelId), ['long-custom']);
    },
  );

  test('empty recommendation diagnostics distinguish saved states safely', () {
    final disabled = StrategyDraftEntries.fromDraftRecord(
      _draft(
        supports: [
          _candidate('long-disabled', 'long', '90', status: 'disabled'),
        ],
      ),
    );
    expect(disabled.issue, StrategyDraftEntriesIssue.disabled);
    expect(disabled.notice, contains('Đánh giá Jev chưa khả dụng'));

    final failed = StrategyDraftEntries.fromDraftRecord(
      _draft(
        supports: [_candidate('long-failed', 'long', '90', status: 'failed')],
      ),
    );
    expect(failed.issue, StrategyDraftEntriesIssue.failed);
    expect(failed.notice, contains('Đánh giá Jev thất bại'));

    final mixed = StrategyDraftEntries.fromDraftRecord(
      _draft(
        supports: [
          _candidate('long-success', 'long', '90'),
          _candidate('long-failed', 'long', '89', status: 'failed', rank: 2),
        ],
      ),
    );
    expect(mixed.issue, StrategyDraftEntriesIssue.failed);
    expect(mixed.successCount, 1);
    expect(mixed.failedCount, 1);
    expect(mixed.notice, contains('1 ứng viên'));
    expect(mixed.notice, isNot(contains('Không có ứng viên nào đạt tiêu chí')));

    final noCandidates = StrategyDraftEntries.fromDraftRecord(_draft());
    expect(noCandidates.issue, StrategyDraftEntriesIssue.noCandidates);

    final qualifiedNone = StrategyDraftEntries.fromDraftRecord(
      _draft(supports: [_candidate('long-success', 'long', '90')]),
    );
    expect(qualifiedNone.issue, StrategyDraftEntriesIssue.noneQualified);

    final legacyRecord = _draft()
      ..['aiGeneration'] = _generation(includeRecommendation: false);
    final legacy = StrategyDraftEntries.fromDraftRecord(legacyRecord);
    expect(legacy.issue, StrategyDraftEntriesIssue.legacy);

    final malformed = _draft()
      ..['aiGeneration'] = _generation()
      ..['aiGeneration']['recommendation'] = {'version': 'old'};
    final invalid = StrategyDraftEntries.fromDraftRecord(malformed);
    expect(invalid.issue, StrategyDraftEntriesIssue.invalid);
    expect(invalid.entries, isEmpty);
  });

  test(
    'partial recommendations keep valid rows and hide provider error details',
    () {
      final disabled = _candidate(
        'long-disabled',
        'long',
        '89',
        status: 'disabled',
        rank: 2,
      );
      (disabled['assessment'] as Map<String, dynamic>)['errorCode'] =
          'provider_private_detail';
      final failed = _candidate(
        'long-failed',
        'long',
        '88',
        status: 'failed',
        rank: 3,
      );
      (failed['assessment'] as Map<String, dynamic>)['errorCode'] =
          'provider_private_detail';
      final entries = StrategyDraftEntries.fromDraftRecord(
        _draft(
          longIds: const ['long-1'],
          supports: [_candidate('long-1', 'long', '90'), disabled, failed],
        ),
      );
      expect(entries.issue, StrategyDraftEntriesIssue.partialDisabledAndFailed);
      expect(entries.entries.map((entry) => entry.levelId), ['long-1']);
      expect(entries.notice, isNot(contains('provider_private_detail')));
    },
  );

  test('malformed recommendation or candidate data is rejected atomically', () {
    final invalidHeaders = [
      {'version': 'unknown', 'maxPerSide': 5},
      {
        'version': 'ai-jev-selection-v1',
        'maxPerSide': 5,
        'minStructuralQuality': 4,
        'minEntrySuitabilityProbability': 0.6,
        'maxFailureRiskProbability': 1.01,
        'longLevelIds': ['long-1'],
        'shortLevelIds': <String>[],
      },
      {
        'version': 'ai-jev-selection-v1',
        'maxPerSide': 5,
        'minStructuralQuality': 3.5,
        'minEntrySuitabilityProbability': 0.55,
        'maxFailureRiskProbability': 0.45,
        'longLevelIds': ['long-1'],
        'shortLevelIds': <String>[],
      },
    ];
    for (final recommendation in invalidHeaders) {
      final record = _draft(longIds: const ['long-1'])
        ..['aiGeneration']['recommendation'] = recommendation;
      _expectAtomicInvalid(record);
    }

    _expectAtomicInvalid(
      _draft(
        longIds: const ['shared'],
        shortIds: const ['shared'],
        supports: [_candidate('shared', 'long', '90')],
        resistances: [_candidate('shared', 'short', '110')],
      ),
    );
    _expectAtomicInvalid(
      _draft(
        longIds: const ['unknown', 'long-1'],
        supports: [_candidate('long-1', 'long', '90')],
      ),
    );
    _expectAtomicInvalid(
      _draft(
        longIds: const ['long-1'],
        supports: [_candidate('long-1', 'short', '90')],
      ),
    );
    _expectAtomicInvalid(
      _draft(
        longIds: const ['long-1'],
        supports: [_candidate('long-1', 'long', '0')],
      ),
    );
    _expectAtomicInvalid(
      _draft(
        longIds: const ['long-1'],
        supports: [_candidate('long-1', 'long', '90', status: 'failed')],
      ),
    );
    _expectAtomicInvalid(
      _draft(
        longIds: const ['long-1'],
        supports: [
          _candidate('long-1', 'long', '90', structuralQuality: double.nan),
        ],
      ),
    );
    _expectAtomicInvalid(
      _draft(
        longIds: const ['long-1'],
        supports: [_candidate('long-1', 'long', '90', entrySuitability: 1.01)],
      ),
    );
    _expectAtomicInvalid(
      _draft(
        longIds: const ['long-1'],
        supports: [_candidate('long-1', 'long', '90', failureRisk: -0.01)],
      ),
    );
    _expectAtomicInvalid(
      _draft(
        longIds: const ['long-1'],
        supports: [
          _candidate('long-1', 'long', '90'),
          _candidate('long-1', 'long', '91', rank: 2),
        ],
      ),
    );
    _expectAtomicInvalid(
      _draft(supports: [_candidate('has space', 'long', '90')]),
    );
    _expectAtomicInvalid(
      _draft(
        longIds: const ['long-1', 'long-1'],
        supports: [_candidate('long-1', 'long', '90')],
      ),
    );
  });
}

void _expectAtomicInvalid(Map<String, dynamic> record) {
  final result = StrategyDraftEntries.fromDraftRecord(record);
  expect(result.issue, StrategyDraftEntriesIssue.invalid);
  expect(result.entries, isEmpty);
}

Map<String, dynamic> _draft({
  List<String> longIds = const [],
  List<String> shortIds = const [],
  List<Map<String, dynamic>>? supports,
  List<Map<String, dynamic>>? resistances,
}) => {
  'id': 'draft-1',
  'instrumentId': 'BTC-USDT-SWAP',
  'interval': '6Hutc',
  'draftStage': 'candidates',
  'aiGeneration': _generation(
    longIds: longIds,
    shortIds: shortIds,
    supports: supports,
    resistances: resistances,
  ),
};

Map<String, dynamic> _generation({
  List<String> longIds = const [],
  List<String> shortIds = const [],
  List<Map<String, dynamic>>? supports,
  List<Map<String, dynamic>>? resistances,
  bool includeRecommendation = true,
}) => {
  'instrumentId': 'BTC-USDT-SWAP',
  'interval': '6Hutc',
  'referencePrice': '100.000000000000000001',
  'observedAt': '2030-01-01T00:00:00Z',
  'supports':
      supports ??
      [
        for (var index = 0; index < longIds.length; index++)
          _candidate(
            longIds[index],
            'long',
            '${90 - index}.1',
            rank: index + 1,
          ),
      ],
  'resistances':
      resistances ??
      [
        for (var index = 0; index < shortIds.length; index++)
          _candidate(
            shortIds[index],
            'short',
            '${110 + index}.1',
            rank: index + 1,
          ),
      ],
  if (includeRecommendation)
    'recommendation': {
      'version': 'ai-jev-selection-v1',
      'maxPerSide': 5,
      'minStructuralQuality': 4,
      'minEntrySuitabilityProbability': 0.6,
      'maxFailureRiskProbability': 0.4,
      'longLevelIds': longIds,
      'shortLevelIds': shortIds,
    },
};

Map<String, dynamic> _candidate(
  String id,
  String side,
  String price, {
  int rank = 1,
  String status = 'success',
  Object structuralQuality = 4,
  Object entrySuitability = 0.6,
  Object failureRisk = 0.4,
}) => {
  'levelId': id,
  'side': side,
  'price': price,
  'touchCount': 1,
  'firstTouchAt': '2029-12-31T00:00:00Z',
  'lastTouchAt': '2030-01-01T00:00:00Z',
  'generationOrder': rank - 1,
  'rank': rank,
  'assessment': {
    'provider': 'typesafe',
    'status': status,
    'structuralQuality': structuralQuality,
    'entrySuitabilityProbability': entrySuitability,
    'failureRiskProbability': failureRisk,
  },
};
