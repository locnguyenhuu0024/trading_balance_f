import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/portfolio/data/risk/risk_request_coordinator.dart';

void main() {
  test('GREEN-001 rate-safe risk request batch', () async {
    final clock = _FakeClock(DateTime.utc(2026, 9, 10));
    final delays = <Duration>[];
    final coordinator = RiskRequestCoordinator(
      clock: clock.now,
      delay: (duration) async {
        delays.add(duration);
        clock.advance(duration);
      },
    );
    var calls = 0;
    var active = 0;
    var maxActive = 0;

    Future<int> request() async {
      calls++;
      active++;
      if (active > maxActive) maxActive = active;
      await Future<void>.delayed(Duration.zero);
      active--;
      return 7;
    }

    final first = coordinator.run<int>(
      lane: RiskRequestLane.authenticated,
      key: '/positions?instType=MARGIN',
      request: request,
    );
    final duplicate = coordinator.run<int>(
      lane: RiskRequestLane.authenticated,
      key: '/positions?instType=MARGIN',
      request: request,
    );
    expect(identical(first, duplicate), isTrue);
    expect(await first, 7);
    expect(await duplicate, 7);
    expect(calls, 1);
    expect(maxActive, 1);

    await coordinator.run<int>(
      lane: RiskRequestLane.authenticated,
      key: '/config',
      request: request,
    );
    expect(delays, contains(const Duration(milliseconds: 250)));

    var rateLimitCalls = 0;
    await expectLater(
      coordinator.run<void>(
        lane: RiskRequestLane.public,
        key: '/candles?instId=BTC-USDT',
        request: () async {
          rateLimitCalls++;
          throw DioException(
            requestOptions: RequestOptions(path: '/candles'),
            response: Response<dynamic>(
              requestOptions: RequestOptions(path: '/candles'),
              statusCode: 429,
              headers: Headers.fromMap(<String, List<String>>{
                'retry-after': <String>['180'],
              }),
            ),
          );
        },
      ),
      throwsA(isA<RiskRequestRateLimitException>()),
    );
    expect(rateLimitCalls, 1);

    await expectLater(
      coordinator.run<void>(
        lane: RiskRequestLane.public,
        key: '/funding?instId=ETH-USDT-SWAP',
        request: () async {},
      ),
      throwsA(
        isA<RiskRequestBackoffException>().having(
          (error) => error.retryAfter,
          'retryAfter',
          const Duration(seconds: 180),
        ),
      ),
    );
    expect(rateLimitCalls, 1);
    expect(
      coordinator.stateFor(RiskRequestLane.public).retryAfter,
      const Duration(seconds: 180),
    );

    clock.advance(const Duration(seconds: 180));
    await coordinator.run<void>(
      lane: RiskRequestLane.public,
      key: '/funding?instId=ETH-USDT-SWAP',
      request: () async {},
    );

    final scheduleClock = _FakeClock(DateTime.utc(2026, 9, 10));
    final scheduleCoordinator = RiskRequestCoordinator(
      clock: scheduleClock.now,
      minimumSpacing: Duration.zero,
    );
    final observedBackoffs = <Duration>[];
    var adapterCalls = 0;
    Future<void> rateLimitedRequest() async {
      adapterCalls++;
      throw DioException(
        requestOptions: RequestOptions(path: '/rate-limited'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/rate-limited'),
          statusCode: 429,
        ),
      );
    }

    var queuedCalls = 0;
    final firstFailure = scheduleCoordinator.run<void>(
      lane: RiskRequestLane.authenticated,
      key: '/rate-limited/first',
      request: rateLimitedRequest,
    );
    final queued = scheduleCoordinator.run<void>(
      lane: RiskRequestLane.authenticated,
      key: '/rate-limited/queued',
      request: () async {
        queuedCalls++;
      },
    );
    await expectLater(
      firstFailure,
      throwsA(
        isA<RiskRequestRateLimitException>().having(
          (error) => error.retryAfter,
          'retryAfter',
          const Duration(seconds: 30),
        ),
      ),
    );
    await expectLater(
      queued,
      throwsA(
        isA<RiskRequestBackoffException>().having(
          (error) => error.retryAfter,
          'retryAfter',
          const Duration(seconds: 30),
        ),
      ),
    );
    expect(queuedCalls, 0);

    const expectedBackoffs = <Duration>[
      Duration(seconds: 30),
      Duration(seconds: 60),
      Duration(seconds: 120),
      Duration(seconds: 300),
      Duration(seconds: 300),
    ];
    observedBackoffs.add(expectedBackoffs.first);
    for (var index = 1; index < expectedBackoffs.length; index++) {
      scheduleClock.advance(expectedBackoffs[index - 1]);
      await expectLater(
        scheduleCoordinator.run<void>(
          lane: RiskRequestLane.authenticated,
          key: '/rate-limited/retry-$index',
          request: rateLimitedRequest,
        ),
        throwsA(isA<RiskRequestRateLimitException>()),
      );
      observedBackoffs.add(
        scheduleCoordinator.stateFor(RiskRequestLane.authenticated).retryAfter!,
      );
    }
    expect(observedBackoffs, expectedBackoffs);
    expect(adapterCalls, expectedBackoffs.length);

    var cooldownCalls = 0;
    final inCooldown = scheduleCoordinator.run<void>(
      lane: RiskRequestLane.authenticated,
      key: '/rate-limited/cooldown',
      request: () async {
        cooldownCalls++;
      },
    );
    await expectLater(inCooldown, throwsA(isA<RiskRequestBackoffException>()));
    expect(cooldownCalls, 0);
  });
}

class _FakeClock {
  _FakeClock(this.value);

  DateTime value;

  DateTime now() => value;

  void advance(Duration duration) {
    value = value.add(duration);
  }
}
