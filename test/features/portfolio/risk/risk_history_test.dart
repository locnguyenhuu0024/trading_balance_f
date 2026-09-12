import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_history.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_models.dart';

import 'fixtures/risk_test_fixtures.dart';

void main() {
  test(
    'RED-003 rejects stale, future, late, duplicate and cross-episode history',
    () {
      final now = riskTestNow;
      final history = RiskHistoryBuffer();
      expect(
        history
            .append(
              riskSample(at: now.subtract(const Duration(minutes: 1))),
              now: now,
            )
            .accepted,
        isTrue,
      );
      expect(
        history
            .append(
              riskSample(at: now.subtract(const Duration(minutes: 1))),
              now: now,
            )
            .status,
        RiskHistoryInputStatus.duplicate,
      );
      expect(
        history
            .append(
              riskSample(at: now.subtract(const Duration(minutes: 2))),
              now: now,
            )
            .status,
        RiskHistoryInputStatus.outOfOrder,
      );
      expect(
        history
            .append(
              riskSample(at: now.add(const Duration(seconds: 1))),
              now: now,
            )
            .status,
        RiskHistoryInputStatus.invalid,
      );
      expect(
        history
            .append(
              riskSample(
                at: now,
                quality: const RiskQuality.stale(
                  reason: 'position source expired',
                ),
              ),
              now: now,
            )
            .status,
        RiskHistoryInputStatus.stale,
      );
      expect(
        history
            .append(
              riskSample(
                at: now.add(const Duration(minutes: 1)),
                episode: 'episode-b',
              ),
              now: now.add(const Duration(minutes: 1)),
            )
            .status,
        RiskHistoryInputStatus.wrongEpisode,
      );

      final gapCurrent = riskSample(at: now);
      final gapBaseline = riskSample(
        at: now.subtract(const Duration(hours: 6, minutes: 31)),
      );
      final gapVelocity = RiskHistoryAnalytics.velocity(
        current: gapCurrent,
        history: <RiskHistorySample>[gapBaseline],
        now: now,
      );
      expect(gapVelocity.label, RiskTrendLabel.collectingHistory);
      expect(gapVelocity.pointsPerHour, isNull);
      final trendGap = RiskHistoryAnalytics.trend(
        current: gapCurrent,
        history: <RiskHistorySample>[
          riskSample(at: now.subtract(const Duration(hours: 1, minutes: 16))),
        ],
        now: now,
      );
      expect(trendGap.label, RiskTrendLabel.collectingHistory);
      final internalGap = RiskHistoryAnalytics.trend(
        current: gapCurrent,
        history: <RiskHistorySample>[
          riskSample(at: now.subtract(const Duration(hours: 1))),
          riskSample(at: now.subtract(const Duration(minutes: 15))),
        ],
        now: now,
      );
      expect(internalGap.label, RiskTrendLabel.collectingHistory);

      final oi = RiskOiRingBuffer();
      expect(
        oi.append(oiSample(at: now, value: 100), now: now).status,
        RiskHistoryInputStatus.accepted,
      );
      expect(
        oi.append(oiSample(at: now, value: 101), now: now).status,
        RiskHistoryInputStatus.duplicate,
      );
      expect(
        oi
            .append(
              oiSample(at: now.subtract(const Duration(minutes: 1)), value: 99),
              now: now,
            )
            .status,
        RiskHistoryInputStatus.outOfOrder,
      );
      expect(
        oi
            .append(
              oiSample(
                at: now.add(const Duration(minutes: 1)),
                quality: const RiskQuality.stale(reason: 'OI expired'),
              ),
              now: now,
            )
            .status,
        RiskHistoryInputStatus.stale,
      );
    },
  );

  test(
    'GREEN-003 computes actual elapsed trend/velocity, frozen checks, timezone and bounds',
    () {
      final now = riskTestNow;
      final continuousHistory = <RiskHistorySample>[
        for (var index = 0; index < 12; index++)
          riskSample(
            at: now
                .subtract(const Duration(hours: 6))
                .add(Duration(minutes: index * 30)),
            buffer: 0.40,
            leverage: 2,
          ),
      ];
      final current = riskSample(at: now, buffer: 0.31, leverage: 2);
      final trend = RiskHistoryAnalytics.trend(
        current: current,
        history: continuousHistory,
        now: now,
      );
      expect(trend.label, RiskTrendLabel.deteriorating);
      expect(trend.bufferDeltaPoints, closeTo(-9, 1e-12));

      final velocity = RiskHistoryAnalytics.velocity(
        current: current,
        history: continuousHistory,
        now: now,
      );
      expect(velocity.label, RiskTrendLabel.deteriorating);
      expect(velocity.pointsPerHour, closeTo(-1.5, 1e-12));
      expect(velocity.elapsedHours, closeTo(6, 1e-12));

      final positionChanged = RiskHistoryAnalytics.velocity(
        current: riskSample(at: now, buffer: 0.31, debt: 100.2),
        history: continuousHistory,
        now: now,
      );
      expect(positionChanged.label, RiskTrendLabel.positionChanged);

      final improvingBoundary = RiskHistoryAnalytics.trend(
        current: riskSample(at: now, buffer: 0.42, leverage: 1.75),
        history: continuousHistory,
        now: now,
      );
      expect(improvingBoundary.label, RiskTrendLabel.improving);

      final converted = RiskHistorySample.fromEvaluation(
        episodeKey: 'episode-a',
        evaluation: riskEvaluation(),
        market: const RiskMarketInput(
          complete: true,
          assetStructureLabel: 'Asset range',
          fundingLabel: 'Funding elevated',
          openInterestChange: 0.12,
        ),
      );
      expect(converted.assetStructureLabel, 'Asset range');
      expect(converted.fundingLabel, 'Funding elevated');
      expect(converted.openInterestChange, 0.12);

      final sessionBaseline = riskSample(
        at: now.subtract(const Duration(hours: 2)),
        buffer: 0.40,
      );
      final session = RiskCheckSession.start(
        episodeKey: 'episode-a',
        now: now,
        savedBaseline: sessionBaseline,
        awayDuration: const Duration(seconds: 60),
      );
      final first = session.observe(riskSample(at: now, buffer: 0.39));
      final second = first.observe(
        riskSample(at: now.add(const Duration(minutes: 1)), buffer: 0.38),
      );
      expect(first.baseline, same(sessionBaseline));
      expect(second.baseline, same(sessionBaseline));
      expect(second.firstCurrent?.buffer, 0.39);
      expect(second.departure()?.buffer, 0.38);
      expect(
        RiskCheckSession.start(
          episodeKey: 'episode-a',
          now: now,
          savedBaseline: sessionBaseline,
          awayDuration: const Duration(seconds: 59),
        ).hasPreviousCheck,
        isFalse,
      );
      final changedSession = session.observe(
        riskSample(at: now.add(const Duration(minutes: 2)), quantity: 10.2),
      );
      expect(changedSession.comparison?.positionChanged, isTrue);
      expect(changedSession.comparison?.bufferDeltaPoints, isNull);

      const zone = RiskLocalTimeZone(
        name: 'Asia/Ho_Chi_Minh',
        offset: Duration(hours: 7),
      );
      final before = RiskDailySummaryCapture.capture(
        sample: riskSample(at: DateTime.utc(2026, 9, 10, 0)),
        timeZone: zone,
        summaryHour: 8,
      );
      expect(before, isNull);
      final daily = RiskDailySummaryCapture.capture(
        sample: riskSample(
          at: DateTime.utc(2026, 9, 10, 7),
          actualInterestToday: 0.125,
          knownInterestToday: 0.2,
          positionState: RiskSeverity.watch,
          marketState: RiskSeverity.high,
          recoveryState: RiskSeverity.critical,
          actualInterestQuality: completeQuality(
            DateTime.utc(2026, 9, 10, 7),
            'interest-ledger',
          ),
          interestCoverageComplete: true,
        ),
        timeZone: zone,
        summaryHour: 8,
      );
      expect(daily?.dateKey, '2026-09-10');
      expect(daily?.capturedAt, DateTime.utc(2026, 9, 10, 7));
      expect(daily?.actualInterestToday, 0.125);
      expect(daily?.knownInterestToday, 0.2);
      expect(daily?.positionState, RiskSeverity.watch);
      expect(daily?.marketState, RiskSeverity.high);
      expect(daily?.recoveryState, RiskSeverity.critical);
      expect(daily?.actualInterestQuality?.source, 'interest-ledger');
      expect(daily?.interestCoverageComplete, isTrue);
      expect(
        RiskDailySummaryCapture.capture(
          sample: riskSample(at: DateTime.utc(2026, 9, 10, 8)),
          timeZone: zone,
          summaryHour: 8,
          existing: <RiskDailySummary>[daily!],
        ),
        isNull,
      );
      final boundaryInstant = DateTime.utc(2026, 9, 10, 23, 30);
      final utcSummary = RiskDailySummaryCapture.capture(
        sample: riskSample(at: boundaryInstant),
        timeZone: const RiskLocalTimeZone(name: 'UTC'),
        summaryHour: 8,
      );
      final nextDaySummary = RiskDailySummaryCapture.capture(
        sample: riskSample(at: DateTime.utc(2026, 9, 11, 1, 30)),
        timeZone: zone,
        summaryHour: 8,
      );
      expect(utcSummary?.dateKey, '2026-09-10');
      expect(nextDaySummary?.dateKey, '2026-09-11');

      final bounded = RiskHistoryBuffer(maxSamples: 2);
      for (var index = 0; index < 3; index++) {
        expect(
          bounded
              .append(
                riskSample(at: now.add(Duration(minutes: index)), buffer: 0.4),
                now: now.add(Duration(minutes: index)),
              )
              .accepted,
          isTrue,
        );
      }
      expect(bounded.samples.length, 2);

      final oi = RiskOiRingBuffer(maxSamples: 2);
      for (var index = 0; index < 3; index++) {
        expect(
          oi
              .append(
                oiSample(
                  at: now.add(Duration(minutes: index)),
                  value: 100.0 + index,
                ),
                now: now.add(Duration(minutes: index)),
              )
              .accepted,
          isTrue,
        );
      }
      expect(oi.samples.length, 2);
      expect(oi.latest?.oiCcy, 102);
    },
  );

  test('GREEN-003 preserves partial history as visible but non-comparable', () {
    final partial = riskSample(
      quality: const RiskQuality.partial(reason: 'one component unavailable'),
      buffer: 0.4,
    );
    expect(partial.isFresh, isTrue);
    expect(partial.isComparable, isFalse);
    final result = RiskHistoryAnalytics.trend(
      current: partial,
      history: <RiskHistorySample>[],
      now: riskTestNow,
    );
    expect(result.label, RiskTrendLabel.collectingHistory);
    expect(result.text, contains('Collecting history'));
  });
}
