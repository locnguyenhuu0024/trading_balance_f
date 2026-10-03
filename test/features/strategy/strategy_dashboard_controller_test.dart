import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/strategy/data/strategy_api_client.dart';
import 'package:trading_balance_f/features/strategy/domain/strategy_models.dart';
import 'package:trading_balance_f/features/strategy/presentation/providers/strategy_dashboard_provider.dart';

void main() {
  test(
    'logout during confirmation prevents execute and stale success',
    () async {
      var sessionIsCurrent = true;
      final api = _FakeStrategyApi();
      final controller = StrategyDashboardController(
        api: api,
        bearerToken: 'test-session-token',
        clock: () => DateTime.utc(2026, 10, 1, 8),
        sessionIsCurrent: () => sessionIsCurrent,
      );
      addTearDown(controller.dispose);
      await controller.load();

      final outcome = await controller.applyDraft(
        'draft-1',
        confirm: (_) async {
          sessionIsCurrent = false;
          return true;
        },
      );

      expect(api.executeCalls, 0);
      expect(outcome.kind, isNot(StrategyApplyOutcomeKind.applied));
      expect(outcome.result, isNull);
    },
  );

  test('cancelling exact-order confirmation never executes', () async {
    final api = _FakeStrategyApi();
    final controller = _controller(api);
    addTearDown(controller.dispose);
    await controller.load();

    final outcome = await controller.applyDraft(
      'draft-1',
      confirm: (_) async => false,
    );

    expect(outcome.kind, StrategyApplyOutcomeKind.cancelled);
    expect(api.prepareCalls, 1);
    expect(api.executeCalls, 0);
    expect(api.deleteCalls, 0);
  });

  test(
    'confirmation receives every validated prepared row unchanged',
    () async {
      final api = _FakeStrategyApi();
      api.prepared['orders'] = [
        _validOrder(openingFeeEstimate: '0.1'),
        _validOrder(
          side: 'short',
          role: 'dca',
          limitPrice: '66000',
          leverage: 10,
          openingFeeEstimate: '0.2',
        ),
      ];
      api.prepared['estimatedOpeningFees'] = '0.3';
      api.replacementCleanupConflict = true;
      final controller = _controller(api);
      addTearDown(controller.dispose);
      await controller.load();
      List<Map<String, dynamic>>? confirmedRows;

      final outcome = await controller.applyDraft(
        'draft-1',
        confirm: (prepared) async {
          confirmedRows = validatedStrategyOrders(prepared);
          return true;
        },
      );

      expect(outcome.kind, StrategyApplyOutcomeKind.applied);
      expect(confirmedRows, equals(api.prepared['orders']));
      expect(api.executeCalls, 1);
      expect(outcome.result?['replacementCleanupConflict'], isTrue);
      expect(
        controller.strategyById('draft-1')?['replacementCleanupConflict'],
        isTrue,
      );
    },
  );

  test(
    'RED-002 refuses an 11-row prepared response before confirmation or execute',
    () async {
      final api = _FakeStrategyApi();
      api.prepared['orders'] = List.generate(11, (_) => _validOrder());
      api.prepared['estimatedOpeningFees'] = '0.33';
      final controller = _controller(api);
      addTearDown(controller.dispose);
      await controller.load();
      var confirmationShown = false;

      final outcome = await controller.applyDraft(
        'draft-1',
        confirm: (_) async {
          confirmationShown = true;
          return true;
        },
      );

      expect(outcome.kind, StrategyApplyOutcomeKind.rejected);
      expect(confirmationShown, isFalse);
      expect(api.prepareCalls, 1);
      expect(api.executeCalls, 0);
    },
  );

  test(
    'RED-002 rejects a known oversized saved draft before prepare',
    () async {
      final api = _FakeStrategyApi()
        ..savedDraftOrders = List.generate(11, (_) => _validOrder());
      final controller = _controller(api);
      addTearDown(controller.dispose);
      await controller.load();

      final outcome = await controller.applyDraft(
        'draft-1',
        confirm: (_) async => true,
      );

      expect(outcome.kind, StrategyApplyOutcomeKind.rejected);
      expect(api.prepareCalls, 0);
      expect(api.executeCalls, 0);
    },
  );

  test('GREEN-002 preserves the historical 20-row order reader', () {
    final prepared = <String, dynamic>{
      'estimatedOpeningFees': '0.60',
      'orders': List.generate(20, (_) => _validOrder()),
    };

    expect(validatedStrategyOrders(prepared), hasLength(20));
    expect(validatedNewStrategyOrders(prepared), isNull);
    expect(
      validatedNewStrategyOrders({
        'estimatedOpeningFees': '0.30',
        'orders': List.generate(10, (_) => _validOrder()),
      }),
      hasLength(10),
    );
  });

  test('duplicate taps share one prepare and one execute request', () async {
    final api = _FakeStrategyApi()
      ..prepareCompleter = Completer<Map<String, dynamic>>();
    final controller = _controller(api);
    addTearDown(controller.dispose);
    await controller.load();

    final first = controller.applyDraft('draft-1', confirm: (_) async => true);
    await Future<void>.delayed(Duration.zero);
    final second = await controller.applyDraft(
      'draft-1',
      confirm: (_) async => true,
    );
    api.prepareCompleter!.complete(api.prepared);
    final completed = await first;

    expect(second.kind, StrategyApplyOutcomeKind.duplicate);
    expect(completed.kind, StrategyApplyOutcomeKind.applied);
    expect(api.prepareCalls, 1);
    expect(api.executeCalls, 1);
    expect(api.deleteCalls, 0);
  });

  test('an attempted strategy is not sent to draft deletion', () async {
    final api = _FakeStrategyApi(status: 'PARTIAL');
    final controller = _controller(api);
    addTearDown(controller.dispose);
    await controller.load();

    final deleted = await controller.deleteDraft('draft-1');

    expect(deleted, isFalse);
    expect(api.deleteCalls, 0);
  });

  test('deletion follows only the server canDelete hint', () async {
    final api = _FakeStrategyApi(statuses: ['PARTIAL', 'PARTIAL']);
    api.canDeleteIds.add('draft-1');
    final controller = _controller(api);
    addTearDown(controller.dispose);
    await controller.load();

    expect(await controller.deleteDraft('draft-1'), isTrue);
    expect(api.deleteCalls, 1);
    expect(await controller.deleteDraft('strategy-1'), isFalse);
    expect(api.deleteCalls, 1);
  });

  test(
    'an ambiguous execute result is surfaced without another execute call',
    () async {
      final api = _FakeStrategyApi()..executeStatus = 'UNKNOWN';
      final controller = _controller(api);
      addTearDown(controller.dispose);
      await controller.load();

      final outcome = await controller.applyDraft(
        'draft-1',
        confirm: (_) async => true,
      );

      expect(outcome.kind, StrategyApplyOutcomeKind.unknown);
      expect(outcome.result?['status'], 'UNKNOWN');
      expect(api.executeCalls, 1);
      expect(api.deleteCalls, 0);
    },
  );

  test(
    'APPLYING without frozen sequential queue evidence is not queued',
    () async {
      final api = _FakeStrategyApi()..executeStatus = 'APPLYING';
      final controller = _controller(api);
      addTearDown(controller.dispose);
      await controller.load();

      final outcome = await controller.applyDraft(
        'draft-1',
        confirm: (_) async => true,
      );

      expect(outcome.kind, StrategyApplyOutcomeKind.unknown);
      expect(api.executeCalls, 1);
    },
  );

  test('a backend quote becomes visibly stale after a failed poll', () async {
    var now = DateTime.utc(2026, 10, 1, 8);
    final api = _FakeStrategyApi(status: 'APPLIED', clock: () => now);
    final controller = _controller(api, clock: () => now);
    addTearDown(controller.dispose);
    await controller.load();
    controller.setVisibility(pageVisible: true, appVisible: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.quoteIsFresh('BTC-USDT-SWAP'), isTrue);

    var notificationsAfterAge = 0;
    controller.addListener(() => notificationsAfterAge++);
    api.failQuotes = true;
    now = now.add(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    expect(controller.quoteIsFresh('BTC-USDT-SWAP'), isFalse);
    expect(notificationsAfterAge, greaterThan(0));
  });

  test('backs off repeated backend quote failures', () async {
    final api = _FakeStrategyApi(status: 'APPLIED')..failQuotes = true;
    final controller = _controller(api);
    addTearDown(controller.dispose);
    await controller.load();
    controller.setVisibility(pageVisible: true, appVisible: true);
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    expect(api.quoteCalls, 1);
  });

  test('does not poll draft or prepared strategies', () async {
    final api = _FakeStrategyApi(statuses: ['DRAFT', 'PREPARED']);
    final controller = _controller(api);
    addTearDown(controller.dispose);
    await controller.load();
    controller.setVisibility(pageVisible: true, appVisible: true);
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    expect(api.quoteCalls, 0);
  });

  test('backend quote polling stops when the page or app is hidden', () async {
    final api = _FakeStrategyApi(statuses: ['APPLIED', 'PARTIAL', 'UNKNOWN']);
    final controller = _controller(api);
    addTearDown(controller.dispose);
    await controller.load();
    expect(api.quoteCalls, 0);

    controller.setVisibility(pageVisible: true, appVisible: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(api.quoteCalls, 1);

    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(api.quoteCalls, 2);

    controller.setVisibility(pageVisible: true, appVisible: false);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(api.quoteCalls, 2);

    controller.setVisibility(pageVisible: false, appVisible: true);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(api.quoteCalls, 2);
  });

  test('does not overlap a slow backend quote request', () async {
    final api = _FakeStrategyApi(status: 'APPLIED')
      ..quoteCompleter = Completer<Map<String, dynamic>>();
    final controller = _controller(api);
    addTearDown(controller.dispose);
    await controller.load();
    controller.setVisibility(pageVisible: true, appVisible: true);
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    expect(api.quoteCalls, 1);
    api.quoteCompleter!.complete(_quoteResponse(DateTime.utc(2026, 10, 1, 8)));
  });

  test(
    'does not replace a fresh quote with an out-of-order response',
    () async {
      final now = DateTime.utc(2026, 10, 1, 8);
      final api = _FakeStrategyApi(status: 'APPLIED', clock: () => now)
        ..quoteSequence = [
          _quoteResponse(now, price: '65000'),
          _quoteResponse(
            now.subtract(const Duration(seconds: 1)),
            price: '66000',
          ),
        ];
      final controller = _controller(api, clock: () => now);
      addTearDown(controller.dispose);
      await controller.load();
      controller.setVisibility(pageVisible: true, appVisible: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await Future<void>.delayed(const Duration(seconds: 1));

      expect(controller.quoteFor('BTC-USDT-SWAP')?.lastPrice, 65000);
      expect(api.quoteCalls, 2);
    },
  );

  test(
    'marks cached account metrics stale after status refresh failure',
    () async {
      var now = DateTime.utc(2026, 10, 1, 8);
      final api = _FakeStrategyApi();
      final controller = _controller(api, clock: () => now);
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.metricsAreStale, isFalse);

      now = now.add(const Duration(seconds: 7));
      api.listError = const StrategyApiException(
        code: 'network_error',
        message: 'refresh failed',
        statusCode: 503,
      );
      await controller.refresh();

      expect(controller.metricsAreStale, isTrue);
      expect(controller.metricsStaleAt, now);
    },
  );

  test(
    'rejects missing or out-of-range leverage before confirmation',
    () async {
      final missingLeverage = _validOrder()..remove('leverage');
      for (final order in [
        missingLeverage,
        _validOrder(leverage: 0),
        _validOrder(leverage: 11),
        _validOrder(leverage: 5.5),
      ]) {
        await _expectPreparedRejected({
          'orders': [order],
        });
      }
    },
  );

  test('rejects malformed displayed order and aggregate fees', () async {
    final missingFee = _validOrder()..remove('openingFeeEstimate');
    for (final prepared in [
      {
        'orders': [_validOrder(openingFeeEstimate: 'NaN')],
      },
      {
        'orders': [_validOrder(openingFeeEstimate: '-0.01')],
      },
      {
        'orders': [missingFee],
      },
      {'estimatedOpeningFees': 'NaN'},
      {'estimatedOpeningFees': '-0.01'},
      {'estimatedOpeningFees': null},
      {'submissionMode': null},
      {'submissionMode': 'parallel'},
    ]) {
      await _expectPreparedRejected(prepared);
    }
  });

  test(
    'rejects an aggregate opening fee that disagrees with order fees',
    () async {
      await _expectPreparedRejected({'estimatedOpeningFees': '0.031'});
    },
  );

  test('rejects malformed prepared order fields and oversized lists', () async {
    for (final orders in <List<Map<String, dynamic>>>[
      [_validOrder(side: 'buy')],
      [_validOrder(role: 'market')],
      [_validOrder(limitPrice: 'NaN')],
      [_validOrder(contracts: '0')],
      [_validOrder(margin: '-1')],
      List.generate(21, (_) => _validOrder()),
    ]) {
      await _expectPreparedRejected({'orders': orders});
    }
  });

  test(
    'refreshes private status on resume after a long hidden interval',
    () async {
      var now = DateTime.utc(2026, 10, 1, 8);
      final api = _FakeStrategyApi();
      final controller = _controller(api, clock: () => now);
      addTearDown(controller.dispose);
      await controller.load();
      controller.setVisibility(pageVisible: true, appVisible: true);
      controller.setVisibility(pageVisible: false, appVisible: true);
      now = now.add(const Duration(minutes: 1));
      api.listCompleter = Completer<List<Map<String, dynamic>>>();

      controller.setVisibility(pageVisible: true, appVisible: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(api.listCalls, 2);
      expect(controller.metricsAreStale, isTrue);
      expect(controller.metricsStaleAt, now);

      api.listCompleter!.complete(api.strategies);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.metricsAreStale, isFalse);
    },
  );

  test(
    'T65 retries the exact linked order once after prepared confirmation',
    () async {
      final api = _FakeStrategyApi();
      final controller = _controller(api);
      addTearDown(controller.dispose);

      final outcome = await controller.retryLimitOrders(
        'source-1',
        retryRequestId: 'retry-request-1234567890',
        interact: (flow) async {
          final candidates = await flow.loadCandidates();
          expect(
            candidates.candidates.single.sourceClientOrderId,
            'source-order-1',
          );
          await flow.previewSelection(['source-order-1']);
          expect(api.retryPreviewIds, ['source-order-1']);
          final draft = await flow.createLinkedDraft();
          expect(draft.id, 'retry-child-1');
          expect(controller.isActionInFlight('source-1'), isTrue);
          expect(controller.isActionInFlight(draft.id), isTrue);
          final prepared = await flow.prepareChild();
          expect(prepared['submissionMode'], 'batch');
          expect(prepared['orders'], isNotEmpty);
          await flow.executeOnce();
          await expectLater(
            flow.executeOnce(),
            throwsA(isA<StrategyRetryFlowException>()),
          );
          return StrategyRetryOutcome(
            StrategyRetryOutcomeKind.applied,
            childId: draft.id,
          );
        },
      );

      expect(outcome.kind, StrategyRetryOutcomeKind.applied);
      expect(outcome.childId, 'retry-child-1');
      expect(api.retryDraftCalls, 1);
      expect(api.lastRetryRequestId, 'retry-request-1234567890');
      expect(api.prepareCalls, 1);
      expect(api.executeCalls, 1);
      expect(controller.isActionInFlight('source-1'), isFalse);
      expect(controller.isActionInFlight('retry-child-1'), isFalse);
    },
  );

  test(
    'T65 rejects excluded and oversized selections before preview',
    () async {
      final api = _FakeStrategyApi()
        ..retryCandidates = _retryCandidates(
          candidates: [
            _retryCandidate(eligible: false, reason: 'unknown'),
            ...List.generate(
              11,
              (index) => _retryCandidate(id: 'eligible-$index'),
            ),
          ],
        );
      final controller = _controller(api);
      addTearDown(controller.dispose);

      for (final ids in [
        const ['source-order-1'],
        List<String>.generate(11, (index) => 'eligible-$index'),
      ]) {
        final outcome = await controller.retryLimitOrders(
          'source-1',
          retryRequestId: 'retry-request-1234567890',
          interact: (flow) async {
            await flow.loadCandidates();
            try {
              await flow.previewSelection(ids);
              fail('Expected the selection to be rejected.');
            } on StrategyRetryFlowException {
              return const StrategyRetryOutcome(
                StrategyRetryOutcomeKind.cancelled,
              );
            }
          },
        );
        expect(outcome.kind, StrategyRetryOutcomeKind.cancelled);
      }
      expect(api.retryPreviewCalls, 0);
      expect(api.retryDraftCalls, 0);
      expect(api.prepareCalls, 0);
      expect(api.executeCalls, 0);
    },
  );

  test('T65 serializes retry and Apply on both source and child IDs', () async {
    final api = _FakeStrategyApi();
    final controller = _controller(api);
    addTearDown(controller.dispose);

    final outcome = await controller.retryLimitOrders(
      'source-1',
      retryRequestId: 'retry-request-1234567890',
      interact: (flow) async {
        await flow.loadCandidates();
        await flow.previewSelection(['source-order-1']);
        await flow.createLinkedDraft();
        expect(controller.isActionInFlight('source-1'), isTrue);
        expect(controller.isActionInFlight('retry-child-1'), isTrue);
        final duplicateRetry = await controller.retryLimitOrders(
          'source-1',
          retryRequestId: 'retry-request-9876543210',
          interact: (_) async => null,
        );
        final duplicateApply = await controller.applyDraft(
          'retry-child-1',
          confirm: (_) async => true,
        );
        expect(duplicateRetry.kind, StrategyRetryOutcomeKind.duplicate);
        expect(duplicateApply.kind, StrategyApplyOutcomeKind.duplicate);
        expect(api.retryDraftCalls, 1);
        expect(api.prepareCalls, 0);
        return const StrategyRetryOutcome(StrategyRetryOutcomeKind.cancelled);
      },
    );

    expect(outcome.kind, StrategyRetryOutcomeKind.cancelled);
    expect(controller.isActionInFlight('source-1'), isFalse);
    expect(controller.isActionInFlight('retry-child-1'), isFalse);
  });

  test(
    'T65 stops on wrong source, costs, and nested order acknowledgments',
    () async {
      for (final configuredApi in [
        _FakeStrategyApi()
          ..retryPreview = _retryPreview(sourceStrategyId: 'other-source'),
        _FakeStrategyApi()
          ..retryDraft = _retryDraft(
            preview: _retryPreview(estimatedOpeningFees: '0.04'),
          ),
        _FakeStrategyApi()
          ..retryPrepared = _retryPrepared(
            childClientOrderId: 'changed-child-order',
          ),
        _FakeStrategyApi()
          ..retryDraft = _retryDraft(nestedLiquidationPrice: '80.0000000001'),
        _FakeStrategyApi()
          ..retryDraft = _retryDraft(nestedRevision: 'changed-revision'),
        _FakeStrategyApi()
          ..retryDraft = _retryDraft(nestedPreviewHash: 'changed-hash'),
      ]) {
        final controller = _controller(configuredApi);
        try {
          final outcome = await controller.retryLimitOrders(
            'source-1',
            retryRequestId: 'retry-request-1234567890',
            interact: (flow) async {
              await flow.loadCandidates();
              await flow.previewSelection(['source-order-1']);
              try {
                final draft = await flow.createLinkedDraft();
                await flow.prepareChild();
                return StrategyRetryOutcome(
                  StrategyRetryOutcomeKind.applied,
                  childId: draft.id,
                );
              } on StrategyRetryFlowException {
                return const StrategyRetryOutcome(
                  StrategyRetryOutcomeKind.rejected,
                );
              }
            },
          );
          expect(outcome.kind, StrategyRetryOutcomeKind.rejected);
          expect(configuredApi.executeCalls, 0);
        } finally {
          controller.dispose();
        }
      }
    },
  );

  for (final stage in ['candidates', 'preview', 'create', 'prepare']) {
    test(
      'T65 cancel during pending $stage cannot advance or unlock early',
      () async {
        final api = _FakeStrategyApi();
        switch (stage) {
          case 'candidates':
            api.retryCandidatesCompleter = Completer<StrategyRetryCandidates>();
            break;
          case 'preview':
            api.retryPreviewCompleter = Completer<StrategyRetryPreview>();
            break;
          case 'create':
            api.retryDraftCompleter = Completer<StrategyRetryDraft>();
            break;
          case 'prepare':
            api.retryPrepareCompleter = Completer<Map<String, dynamic>>();
            break;
        }
        final controller = _controller(api);
        addTearDown(controller.dispose);

        final operation = controller.retryLimitOrders(
          'source-1',
          retryRequestId: 'retry-request-1234567890',
          interact: (flow) async {
            if (stage == 'candidates') {
              unawaited(
                flow.loadCandidates().then<void>(
                  (_) {},
                  onError: (Object _, StackTrace __) {},
                ),
              );
            } else {
              await flow.loadCandidates();
              if (stage == 'preview') {
                unawaited(
                  flow
                      .previewSelection(['source-order-1'])
                      .then<void>(
                        (_) {},
                        onError: (Object _, StackTrace __) {},
                      ),
                );
              } else {
                await flow.previewSelection(['source-order-1']);
                if (stage == 'create') {
                  unawaited(
                    flow.createLinkedDraft().then<void>(
                      (_) {},
                      onError: (Object _, StackTrace __) {},
                    ),
                  );
                } else {
                  await flow.createLinkedDraft();
                  unawaited(
                    flow.prepareChild().then<void>(
                      (_) {},
                      onError: (Object _, StackTrace __) {},
                    ),
                  );
                }
              }
            }
            await Future<void>.delayed(Duration.zero);
            flow.cancel();
            return const StrategyRetryOutcome(
              StrategyRetryOutcomeKind.cancelled,
            );
          },
        );

        await Future<void>.delayed(Duration.zero);
        expect(controller.isActionInFlight('source-1'), isTrue);
        switch (stage) {
          case 'candidates':
            api.retryCandidatesCompleter!.complete(_retryCandidates());
            break;
          case 'preview':
            api.retryPreviewCompleter!.complete(_retryPreview());
            break;
          case 'create':
            api.retryDraftCompleter!.complete(_retryDraft());
            break;
          case 'prepare':
            api.retryPrepareCompleter!.complete(_retryPrepared());
            break;
        }
        final outcome = await operation;
        expect(outcome.kind, StrategyRetryOutcomeKind.cancelled);
        expect(api.prepareCalls, stage == 'prepare' ? 1 : 0);
        expect(api.executeCalls, 0);
        expect(controller.isActionInFlight('source-1'), isFalse);
      },
    );
  }

  test('T65 session switch after prepare blocks the execute write', () async {
    var ownsSession = true;
    final api = _FakeStrategyApi();
    final controller = _controller(api, sessionIsCurrent: () => ownsSession);
    addTearDown(controller.dispose);

    final outcome = await controller.retryLimitOrders(
      'source-1',
      retryRequestId: 'retry-request-1234567890',
      interact: (flow) async {
        await flow.loadCandidates();
        await flow.previewSelection(['source-order-1']);
        await flow.createLinkedDraft();
        await flow.prepareChild();
        ownsSession = false;
        try {
          await flow.executeOnce();
        } on Object {
          return const StrategyRetryOutcome(StrategyRetryOutcomeKind.cancelled);
        }
        fail('The old session must not execute.');
      },
    );

    expect(outcome.kind, StrategyRetryOutcomeKind.rejected);
    expect(api.executeCalls, 0);
  });

  test(
    'T65 session switch during pending create never prepares or executes',
    () async {
      var ownsSession = true;
      final api = _FakeStrategyApi()
        ..retryDraftCompleter = Completer<StrategyRetryDraft>();
      final controller = _controller(api, sessionIsCurrent: () => ownsSession);
      addTearDown(controller.dispose);

      final operation = controller.retryLimitOrders(
        'source-1',
        retryRequestId: 'retry-request-1234567890',
        interact: (flow) async {
          await flow.loadCandidates();
          await flow.previewSelection(['source-order-1']);
          final creating = flow.createLinkedDraft();
          await Future<void>.delayed(Duration.zero);
          ownsSession = false;
          api.retryDraftCompleter!.complete(_retryDraft());
          try {
            await creating;
          } on Object {
            return const StrategyRetryOutcome(
              StrategyRetryOutcomeKind.cancelled,
            );
          }
          fail('A stale session must not continue from linked draft creation.');
        },
      );

      final outcome = await operation;
      expect(outcome.kind, StrategyRetryOutcomeKind.rejected);
      expect(api.retryDraftCalls, 1);
      expect(api.prepareCalls, 0);
      expect(api.executeCalls, 0);
    },
  );

  test(
    'T65 uncertain create and execute writes refresh without retrying',
    () async {
      final uncertain = StrategyApiException(
        code: 'timeout',
        message: 'request timeout',
        statusCode: null,
      );
      final createApi = _FakeStrategyApi()..retryDraftError = uncertain;
      final createController = _controller(createApi);
      final createOutcome = await createController.retryLimitOrders(
        'source-1',
        retryRequestId: 'retry-request-1234567890',
        interact: (flow) async {
          await flow.loadCandidates();
          await flow.previewSelection(['source-order-1']);
          try {
            await flow.createLinkedDraft();
          } on Object {
            return const StrategyRetryOutcome(StrategyRetryOutcomeKind.unknown);
          }
          fail('Expected uncertain create to stop.');
        },
      );
      expect(createOutcome.kind, StrategyRetryOutcomeKind.unknown);
      expect(createApi.retryDraftCalls, 1);
      expect(createApi.retryCandidatesCalls, greaterThan(1));
      expect(createApi.listCalls, greaterThan(0));
      expect(createApi.prepareCalls, 0);
      createController.dispose();

      final executeApi = _FakeStrategyApi()..retryExecuteError = uncertain;
      final executeController = _controller(executeApi);
      final executeOutcome = await executeController.retryLimitOrders(
        'source-1',
        retryRequestId: 'retry-request-1234567890',
        interact: (flow) async {
          await flow.loadCandidates();
          await flow.previewSelection(['source-order-1']);
          await flow.createLinkedDraft();
          await flow.prepareChild();
          try {
            await flow.executeOnce();
          } on Object {
            return const StrategyRetryOutcome(StrategyRetryOutcomeKind.unknown);
          }
          fail('Expected uncertain execute to stop.');
        },
      );
      expect(executeOutcome.kind, StrategyRetryOutcomeKind.unknown);
      expect(executeApi.executeCalls, 1);
      expect(executeApi.retryCandidatesCalls, greaterThan(1));
      expect(executeApi.listCalls, greaterThan(1));
      executeController.dispose();
    },
  );

  test(
    'T65 malformed execute acknowledgment becomes unknown and stays once',
    () async {
      final api = _FakeStrategyApi()
        ..retryExecuteResponse = {'id': 'retry-child-1', 'status': 'APPLIED'};
      final controller = _controller(api);
      addTearDown(controller.dispose);
      Map<String, dynamic>? result;

      final outcome = await controller.retryLimitOrders(
        'source-1',
        retryRequestId: 'retry-request-1234567890',
        interact: (flow) async {
          await flow.loadCandidates();
          await flow.previewSelection(['source-order-1']);
          await flow.createLinkedDraft();
          await flow.prepareChild();
          result = await flow.executeOnce();
          await expectLater(
            flow.executeOnce(),
            throwsA(isA<StrategyRetryFlowException>()),
          );
          return StrategyRetryOutcome(
            StrategyRetryOutcomeKind.unknown,
            childId: 'retry-child-1',
            result: result,
          );
        },
      );

      expect(outcome.kind, StrategyRetryOutcomeKind.unknown);
      expect(result?['status'], 'UNKNOWN');
      expect(result?['acknowledgementInvalid'], isTrue);
      expect(api.executeCalls, 1);
    },
  );
}

Map<String, dynamic> _validOrder({
  Object? side = 'long',
  Object? role = 'entry',
  Object? limitPrice = '65000',
  Object? contracts = '1',
  Object? margin = '13',
  Object? leverage = 5,
  Object? openingFeeEstimate = '0.03',
}) => {
  'side': side,
  'role': role,
  'limitPrice': limitPrice,
  'contracts': contracts,
  'margin': margin,
  'leverage': leverage,
  'openingFeeEstimate': openingFeeEstimate,
};

StrategyRetryCandidate _retryCandidate({
  String id = 'source-order-1',
  bool eligible = true,
  String? reason,
  String priorOutcome = 'not_submitted',
}) => StrategyRetryCandidate(
  sourceClientOrderId: id,
  side: 'long',
  role: 'entry',
  limitPrice: '65000',
  contracts: '1',
  leverage: '5',
  priorOutcome: priorOutcome,
  eligible: eligible,
  reason: reason,
  levelId: 'level-1',
);

StrategyRetryCandidates _retryCandidates({
  List<StrategyRetryCandidate>? candidates,
}) => StrategyRetryCandidates(
  sourceStrategyId: 'source-1',
  sourceRevision: 'revision-1',
  candidates: candidates ?? [_retryCandidate()],
  blockedReason: null,
  linkedChildren: const [],
);

StrategyRetryPreview _retryPreview({
  String sourceStrategyId = 'source-1',
  String sourceRevision = 'revision-1',
  String previewHash = 'retry-preview-hash-1',
  String estimatedOpeningFees = '0.03',
  String liquidationPrice = '80',
}) {
  final order = _retryOrder(liquidationPrice: liquidationPrice);
  final raw = <String, dynamic>{
    'sourceStrategyId': sourceStrategyId,
    'sourceRevision': sourceRevision,
    'selectedSourceClientOrderIds': ['source-order-1'],
    'previewHash': previewHash,
    'instrumentId': 'BTC-USDT-SWAP',
    'interval': '6Hutc',
    'allocation': 'fixed',
    'feesOutsideMargin': true,
    'currentPrice': '65000',
    'quoteTimestamp': '2026-10-01T08:00:00Z',
    'sidePercent': {'long': '100', 'short': '0'},
    'sides': [
      {'side': 'long', 'contracts': '1'},
    ],
    'totalMargin': '13',
    'plannedMargin': '13',
    'unallocatedMargin': '0',
    'estimatedOpeningFees': estimatedOpeningFees,
    'requiredBalance': (13 + double.parse(estimatedOpeningFees)).toString(),
    'orders': [order],
  };
  return StrategyRetryPreview(
    sourceStrategyId: sourceStrategyId,
    sourceRevision: sourceRevision,
    selectedSourceClientOrderIds: const ['source-order-1'],
    previewHash: previewHash,
    orders: [order],
    totalMargin: '13',
    plannedMargin: '13',
    unallocatedMargin: '0',
    estimatedOpeningFees: estimatedOpeningFees,
    requiredBalance: raw['requiredBalance'] as String,
    raw: raw,
  );
}

Map<String, dynamic> _retryOrder({
  String? clientOrderId,
  String liquidationPrice = '80',
}) => {
  'sourceClientOrderId': 'source-order-1',
  if (clientOrderId != null) 'clientOrderId': clientOrderId,
  'side': 'long',
  'role': 'entry',
  'limitPrice': '65000',
  'contracts': '1',
  'leverage': '5',
  'margin': '13',
  'allocatedMargin': '13',
  'notional': '65000',
  'openingFeeEstimate': '0.03',
  'allocationWeight': '1',
  'cumulativeContracts': '1',
  'cumulativeAverageEntry': '65000',
  'liquidationEstimate': {'price': liquidationPrice, 'method': 'cross'},
  'levelId': 'level-1',
};

StrategyRetryDraft _retryDraft({
  StrategyRetryPreview? preview,
  String childClientOrderId = 'retry-child-order-1',
  String? nestedLiquidationPrice,
  String? nestedRevision,
  String? nestedPreviewHash,
}) {
  final selectedPreview = preview ?? _retryPreview();
  final childOrder = _retryOrder(
    clientOrderId: childClientOrderId,
    liquidationPrice: _retryTextForTest(
      _retryMapForTest(
        selectedPreview.orders.single['liquidationEstimate'],
      )?['price'],
    ),
  );
  final nestedOrder = nestedLiquidationPrice == null
      ? childOrder
      : _retryOrder(
          clientOrderId: childClientOrderId,
          liquidationPrice: nestedLiquidationPrice,
        );
  final nestedPreview = StrategyRetryPreview(
    sourceStrategyId: selectedPreview.sourceStrategyId,
    sourceRevision: nestedRevision ?? selectedPreview.sourceRevision,
    selectedSourceClientOrderIds: selectedPreview.selectedSourceClientOrderIds,
    previewHash: nestedPreviewHash ?? selectedPreview.previewHash,
    orders: [nestedOrder],
    totalMargin: selectedPreview.totalMargin,
    plannedMargin: selectedPreview.plannedMargin,
    unallocatedMargin: selectedPreview.unallocatedMargin,
    estimatedOpeningFees: selectedPreview.estimatedOpeningFees,
    requiredBalance: selectedPreview.requiredBalance,
    raw: {
      ...selectedPreview.raw,
      'orders': [nestedOrder],
    },
  );
  return StrategyRetryDraft(
    id: 'retry-child-1',
    status: 'DRAFT',
    orders: [childOrder],
    resubmission: {
      'sourceStrategyId': selectedPreview.sourceStrategyId,
      'sourceClientOrderIds': selectedPreview.selectedSourceClientOrderIds,
    },
    preview: nestedPreview,
    raw: {
      'id': 'retry-child-1',
      'status': 'DRAFT',
      'orders': [childOrder],
      'resubmission': {
        'sourceStrategyId': selectedPreview.sourceStrategyId,
        'sourceClientOrderIds': selectedPreview.selectedSourceClientOrderIds,
      },
      'preview': nestedPreview.raw,
    },
  );
}

Map<String, dynamic> _retryPrepared({
  String childClientOrderId = 'retry-child-order-1',
}) => {
  'id': 'retry-child-1',
  'status': 'PREPARED',
  'confirmationToken': 'retry-one-use-token',
  'expiresAt': '2026-10-01T08:01:00Z',
  'plannedMargin': '13',
  'unallocatedMargin': '0',
  'estimatedOpeningFees': '0.03',
  'quoteTimestamp': '2026-10-01T08:00:00Z',
  'submissionMode': 'batch',
  'resubmission': {
    'sourceStrategyId': 'source-1',
    'sourceClientOrderIds': ['source-order-1'],
  },
  'orders': [_retryOrder(clientOrderId: childClientOrderId)],
};

Map<String, dynamic>? _retryMapForTest(Object? value) =>
    value is Map<String, dynamic> ? value : null;

String _retryTextForTest(Object? value) => value?.toString() ?? '80';

Future<void> _expectPreparedRejected(
  Map<String, dynamic> preparedValues,
) async {
  final api = _FakeStrategyApi()..prepared.addAll(preparedValues);
  final controller = _controller(api);
  await controller.load();
  var confirmationShown = false;
  try {
    final outcome = await controller.applyDraft(
      'draft-1',
      confirm: (_) async {
        confirmationShown = true;
        return true;
      },
    );
    expect(outcome.kind, StrategyApplyOutcomeKind.rejected);
    expect(confirmationShown, isFalse);
    expect(api.executeCalls, 0);
  } finally {
    controller.dispose();
  }
}

StrategyDashboardController _controller(
  _FakeStrategyApi api, {
  DateTime Function()? clock,
  bool Function()? sessionIsCurrent,
}) {
  if (clock != null) api.quoteClock = clock;
  return StrategyDashboardController(
    api: api,
    bearerToken: 'test-session-token',
    clock: clock ?? () => DateTime.utc(2026, 10, 1, 8),
    sessionIsCurrent: sessionIsCurrent,
  );
}

class _FakeStrategyApi implements StrategyApi {
  _FakeStrategyApi({
    this.status = 'DRAFT',
    List<String>? statuses,
    DateTime Function()? clock,
  }) : statuses = statuses ?? [status],
       quoteClock = clock ?? (() => DateTime.utc(2026, 10, 1, 8));

  final String status;
  final List<String> statuses;
  final prepared = <String, dynamic>{
    'confirmationToken': 'one-use-token',
    'submissionMode': 'sequential',
    'estimatedOpeningFees': '0.03',
    'orders': [_validOrder()],
  };
  StrategyRetryCandidates retryCandidates = _retryCandidates();
  StrategyRetryPreview retryPreview = _retryPreview();
  StrategyRetryDraft retryDraft = _retryDraft();
  Map<String, dynamic> retryPrepared = _retryPrepared();
  Completer<StrategyRetryCandidates>? retryCandidatesCompleter;
  Completer<StrategyRetryPreview>? retryPreviewCompleter;
  Completer<StrategyRetryDraft>? retryDraftCompleter;
  Completer<Map<String, dynamic>>? retryPrepareCompleter;
  int retryCandidatesCalls = 0;
  int retryPreviewCalls = 0;
  int retryDraftCalls = 0;
  StrategyApiException? retryDraftError;
  StrategyApiException? retryExecuteError;
  Map<String, dynamic>? retryExecuteResponse;
  List<String> retryPreviewIds = const [];
  String? lastRetryRequestId;
  Completer<Map<String, dynamic>>? prepareCompleter;
  Completer<List<Map<String, dynamic>>>? listCompleter;
  int prepareCalls = 0;
  int executeCalls = 0;
  int deleteCalls = 0;
  int listCalls = 0;
  int quoteCalls = 0;
  final canDeleteIds = <String>{};
  List<Map<String, dynamic>>? savedDraftOrders;
  String executeStatus = 'APPLIED';
  bool replacementCleanupConflict = false;
  StrategyApiException? listError;
  bool failQuotes = false;
  Completer<Map<String, dynamic>>? quoteCompleter;
  List<Map<String, dynamic>>? quoteSequence;
  DateTime Function() quoteClock;

  List<Map<String, dynamic>> get strategies => List.generate(
    statuses.length,
    (index) => {
      'id': index == 0 ? 'draft-1' : 'strategy-$index',
      'instrumentId': 'BTC-USDT-SWAP',
      'interval': '6Hutc',
      'status': statuses[index],
      if (index == 0 && savedDraftOrders != null) 'orders': savedDraftOrders,
      'canDelete': canDeleteIds.contains(
        index == 0 ? 'draft-1' : 'strategy-$index',
      ),
      'unrealizedPnl': '12',
      'filledMargin': '50',
      'pnlPercent': '24',
      'observedAt': '2026-10-01T08:00:00Z',
      'positions': [
        {
          'avgPx': '65000',
          'markPx': '65100',
          'observedAt': '2026-10-01T08:00:00Z',
        },
      ],
    },
  );

  @override
  Future<StrategyRetryCandidates> getRetryCandidates(
    String token,
    String sourceStrategyId,
  ) {
    retryCandidatesCalls++;
    return retryCandidatesCompleter?.future ?? Future.value(retryCandidates);
  }

  @override
  Future<StrategyRetryPreview> previewRetry(
    String token,
    String sourceStrategyId, {
    required String sourceRevision,
    required List<String> sourceClientOrderIds,
  }) {
    retryPreviewCalls++;
    retryPreviewIds = List<String>.from(sourceClientOrderIds);
    return retryPreviewCompleter?.future ?? Future.value(retryPreview);
  }

  @override
  Future<StrategyRetryDraft> createRetryDraft(
    String token,
    String sourceStrategyId, {
    required String sourceRevision,
    required List<String> sourceClientOrderIds,
    required String previewHash,
    required String retryRequestId,
  }) async {
    retryDraftCalls++;
    lastRetryRequestId = retryRequestId;
    if (retryDraftError != null) throw retryDraftError!;
    return retryDraftCompleter == null
        ? retryDraft
        : await retryDraftCompleter!.future;
  }

  @override
  Future<Map<String, dynamic>> preview(
    String token,
    Map<String, dynamic> body,
  ) async => {};

  @override
  Future<Map<String, dynamic>> saveDraft(
    String token,
    Map<String, dynamic> body,
  ) async => {'id': 'draft-1'};

  @override
  Future<List<Map<String, dynamic>>> listStrategies(String token) async {
    listCalls++;
    if (listError != null) throw listError!;
    if (listCompleter != null && listCalls > 1) return listCompleter!.future;
    return strategies;
  }

  @override
  Future<Map<String, dynamic>> prepareApply(String token, String id) {
    prepareCalls++;
    if (id == retryDraft.id) {
      return retryPrepareCompleter?.future ?? Future.value(retryPrepared);
    }
    return prepareCompleter?.future ?? Future.value(prepared);
  }

  @override
  Future<Map<String, dynamic>> executeApply(
    String token,
    String id,
    String confirmationToken,
  ) async {
    executeCalls++;
    if (id == retryDraft.id && retryExecuteError != null) {
      throw retryExecuteError!;
    }
    if (id == retryDraft.id && retryExecuteResponse != null) {
      return Map<String, dynamic>.from(retryExecuteResponse!);
    }
    return {
      'id': id,
      'status': executeStatus,
      'replacementCleanupConflict': replacementCleanupConflict,
      if (id == retryDraft.id)
        'resubmission': {
          'sourceStrategyId': retryDraft.resubmission['sourceStrategyId'],
          'sourceClientOrderIds':
              retryDraft.resubmission['sourceClientOrderIds'],
        },
    };
  }

  @override
  Future<Map<String, dynamic>> getResult(String token, String id) async => {
    'status': status,
  };

  @override
  Future<Map<String, dynamic>> getQuote(String token, String id) async {
    quoteCalls++;
    if (failQuotes) {
      throw const StrategyApiException(
        code: 'quote_unavailable',
        message: 'quote unavailable',
        statusCode: 503,
      );
    }
    if (quoteCompleter != null) return quoteCompleter!.future;
    final sequence = quoteSequence;
    if (sequence != null && sequence.isNotEmpty) return sequence.removeAt(0);
    return _quoteResponse(quoteClock().toUtc());
  }

  @override
  Future<String> getLimitOrderSubmissionMode(String token) async =>
      'sequential';

  @override
  Future<String> saveLimitOrderSubmissionMode(
    String token,
    String mode,
  ) async => mode;

  @override
  Future<void> deleteDraft(String token, String id) async {
    deleteCalls++;
  }
}

Map<String, dynamic> _quoteResponse(
  DateTime observedAt, {
  String instrumentId = 'BTC-USDT-SWAP',
  String price = '65000',
}) => {
  'instrumentId': instrumentId,
  'lastPrice': price,
  'observedAt': observedAt.toUtc().toIso8601String(),
};
