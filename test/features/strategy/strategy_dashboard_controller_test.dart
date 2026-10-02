import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/portfolio/data/risk/risk_request_coordinator.dart';
import 'package:trading_balance_f/features/strategy/data/strategy_api_client.dart';
import 'package:trading_balance_f/features/strategy/data/strategy_market_repository.dart';
import 'package:trading_balance_f/features/strategy/domain/strategy_models.dart';
import 'package:trading_balance_f/features/strategy/presentation/providers/strategy_dashboard_provider.dart';

void main() {
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
    },
  );

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
    },
  );

  test(
    'a fresh dashboard quote becomes visibly stale after a failed poll',
    () async {
      var now = DateTime.utc(2026, 10, 1, 8);
      final market = _FakeMarketRepository(clock: () => now);
      final api = _FakeStrategyApi(status: 'APPLIED');
      final controller = _controller(api, market: market, clock: () => now);
      addTearDown(controller.dispose);
      await controller.load();
      controller.setVisibility(pageVisible: true, appVisible: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.quoteIsFresh('BTC-USDT-SWAP'), isTrue);

      var notificationsAfterAge = 0;
      controller.addListener(() => notificationsAfterAge++);
      market.failTickers = true;
      now = now.add(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 1100));

      expect(controller.quoteIsFresh('BTC-USDT-SWAP'), isFalse);
      expect(notificationsAfterAge, greaterThan(0));
    },
  );

  test('backs off repeated public ticker failures', () async {
    final market = _FakeMarketRepository()..failTickers = true;
    final controller = _controller(
      _FakeStrategyApi(status: 'APPLIED'),
      market: market,
    );
    addTearDown(controller.dispose);
    await controller.load();
    controller.setVisibility(pageVisible: true, appVisible: true);
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    expect(market.tickerCalls, 1);
  });

  test('does not poll draft or prepared strategies', () async {
    final market = _FakeMarketRepository();
    final api = _FakeStrategyApi(statuses: ['DRAFT', 'PREPARED']);
    final controller = _controller(api, market: market);
    addTearDown(controller.dispose);
    await controller.load();
    controller.setVisibility(pageVisible: true, appVisible: true);
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    expect(market.tickerCalls, 0);
  });

  test('public ticker polling stops when the page or app is hidden', () async {
    final market = _FakeMarketRepository();
    final api = _FakeStrategyApi(statuses: ['APPLIED', 'PARTIAL', 'UNKNOWN']);
    final controller = _controller(api, market: market);
    addTearDown(controller.dispose);
    await controller.load();
    expect(market.tickerCalls, 0);

    controller.setVisibility(pageVisible: true, appVisible: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(market.tickerCalls, 1);

    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(market.tickerCalls, 2);

    controller.setVisibility(pageVisible: true, appVisible: false);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(market.tickerCalls, 2);

    controller.setVisibility(pageVisible: false, appVisible: true);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(market.tickerCalls, 2);
  });

  test('does not overlap a slow public ticker request', () async {
    final market = _FakeMarketRepository()
      ..tickerCompleter = Completer<StrategyTicker>();
    final controller = _controller(
      _FakeStrategyApi(status: 'APPLIED'),
      market: market,
    );
    addTearDown(controller.dispose);
    await controller.load();
    controller.setVisibility(pageVisible: true, appVisible: true);
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    expect(market.tickerCalls, 1);
    market.tickerCompleter!.complete(
      StrategyTicker(
        instrumentId: 'BTC-USDT-SWAP',
        lastPrice: 65000,
        observedAt: DateTime.utc(2026, 10, 1, 8),
      ),
    );
  });

  test(
    'does not replace a fresh quote with an out-of-order response',
    () async {
      final now = DateTime.utc(2026, 10, 1, 8);
      final market = _FakeMarketRepository(clock: () => now)
        ..tickerSequence = [
          StrategyTicker(
            instrumentId: 'BTC-USDT-SWAP',
            lastPrice: 65000,
            observedAt: now,
          ),
          StrategyTicker(
            instrumentId: 'BTC-USDT-SWAP',
            lastPrice: 66000,
            observedAt: now.subtract(const Duration(seconds: 1)),
          ),
        ];
      final controller = _controller(
        _FakeStrategyApi(status: 'APPLIED'),
        market: market,
        clock: () => now,
      );
      addTearDown(controller.dispose);
      await controller.load();
      controller.setVisibility(pageVisible: true, appVisible: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await Future<void>.delayed(const Duration(seconds: 1));

      expect(controller.quoteFor('BTC-USDT-SWAP')?.lastPrice, 65000);
      expect(market.tickerCalls, 2);
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
  StrategyMarketRepository? market,
  DateTime Function()? clock,
}) {
  final resolvedMarket =
      market ??
      (() {
        final adapter = _TickerAdapter();
        return StrategyMarketRepository(
          Dio(BaseOptions(baseUrl: 'https://www.okx.com'))
            ..httpClientAdapter = adapter,
          requestCoordinator: RiskRequestCoordinator(
            minimumSpacing: Duration.zero,
            delay: (_) async {},
          ),
          clock: clock ?? () => DateTime.utc(2026, 10, 1, 8),
        );
      })();
  return StrategyDashboardController(
    api: api,
    marketRepository: resolvedMarket,
    bearerToken: 'test-session-token',
    clock: clock ?? () => DateTime.utc(2026, 10, 1, 8),
  );
}

class _FakeMarketRepository extends StrategyMarketRepository {
  _FakeMarketRepository({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now,
      super(
        Dio(BaseOptions(baseUrl: 'https://www.okx.com')),
        requestCoordinator: RiskRequestCoordinator(
          minimumSpacing: Duration.zero,
          delay: (_) async {},
        ),
      );

  final DateTime Function() _clock;
  bool failTickers = false;
  int tickerCalls = 0;
  Completer<StrategyTicker>? tickerCompleter;
  List<StrategyTicker>? tickerSequence;

  @override
  Future<StrategyTicker> getTicker({required String instrumentId}) async {
    tickerCalls++;
    if (failTickers) throw const StrategyMarketException('ticker failure');
    if (tickerCompleter != null) return tickerCompleter!.future;
    final sequence = tickerSequence;
    if (sequence != null && sequence.isNotEmpty) {
      return sequence.removeAt(0);
    }
    final observedAt = _clock().toUtc();
    return StrategyTicker(
      instrumentId: instrumentId,
      lastPrice: 65000,
      observedAt: observedAt,
    );
  }
}

class _FakeStrategyApi implements StrategyApi {
  _FakeStrategyApi({this.status = 'DRAFT', List<String>? statuses})
    : statuses = statuses ?? [status];

  final String status;
  final List<String> statuses;
  final prepared = <String, dynamic>{
    'confirmationToken': 'one-use-token',
    'estimatedOpeningFees': '0.03',
    'orders': [_validOrder()],
  };
  Completer<Map<String, dynamic>>? prepareCompleter;
  Completer<List<Map<String, dynamic>>>? listCompleter;
  int prepareCalls = 0;
  int executeCalls = 0;
  int deleteCalls = 0;
  int listCalls = 0;
  String executeStatus = 'APPLIED';
  StrategyApiException? listError;

  List<Map<String, dynamic>> get strategies => List.generate(
    statuses.length,
    (index) => {
      'id': index == 0 ? 'draft-1' : 'strategy-$index',
      'instrumentId': 'BTC-USDT-SWAP',
      'interval': '6Hutc',
      'status': statuses[index],
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
    return prepareCompleter?.future ?? Future.value(prepared);
  }

  @override
  Future<Map<String, dynamic>> executeApply(
    String token,
    String id,
    String confirmationToken,
  ) async {
    executeCalls++;
    return {'status': executeStatus};
  }

  @override
  Future<Map<String, dynamic>> getResult(String token, String id) async => {
    'status': status,
  };

  @override
  Future<void> deleteDraft(String token, String id) async {
    deleteCalls++;
  }
}

class _TickerAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode({
      'code': '0',
      'data': [
        {
          'instId': options.uri.queryParameters['instId'],
          'last': '65000',
          'ts': DateTime.utc(2026, 10, 1, 8).millisecondsSinceEpoch.toString(),
        },
      ],
    }),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
