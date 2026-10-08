import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/network/foreground_read_gate.dart';

void main() {
  testWidgets(
    'overlapping readers share one transport and an active lease keeps it alive',
    (tester) async {
      final gate = ForegroundReadGate();
      final session = Object();
      final response = Completer<int>();
      CancelToken? observedToken;
      var loads = 0;

      final first = _read(
        gate,
        session: session,
        load: (token) {
          loads++;
          observedToken = token;
          return response.future;
        },
      );
      final second = _read(
        gate,
        session: session,
        load: (_) {
          loads++;
          return Future.value(99);
        },
      );
      first.release();

      expect(loads, 1);
      expect(observedToken?.isCancelled, isFalse);
      response.complete(7);
      await tester.pump();
      expect(await second.future, 7);
      second.release();
      gate.dispose();
    },
  );

  testWidgets('transient failures use capped 10, 20, 40, 60 second delays', (
    tester,
  ) async {
    final gate = ForegroundReadGate();
    final session = Object();
    var attempts = 0;

    Future<void> fail(ForegroundReadLease<int> lease) async {
      final result = expectLater(lease.future, throwsA(isA<_ReadFailure>()));
      await tester.pump();
      await result;
      lease.release();
    }

    ForegroundReadLease<int> nextRead() => _read(
      gate,
      session: session,
      load: (_) async {
        attempts++;
        throw const _ReadFailure();
      },
    );

    await fail(nextRead());
    expect(attempts, 1);

    const delays = [10, 20, 40, 60];
    for (var index = 0; index < delays.length; index++) {
      final delay = delays[index];
      final retry = nextRead();
      final result = expectLater(retry.future, throwsA(isA<_ReadFailure>()));
      expect(attempts, index + 1);
      await tester.pump(Duration(seconds: delay - 1));
      expect(attempts, index + 1);
      await tester.pump(const Duration(seconds: 1));
      expect(attempts, index + 2);
      await result;
      retry.release();
    }

    expect(attempts, 5);
    gate.dispose();
  });

  testWidgets('Retry-After 120 seconds delays a 429 beyond local backoff', (
    tester,
  ) async {
    final gate = ForegroundReadGate();
    final session = Object();
    var attempts = 0;

    Future<void> failFirst() async {
      final lease = _read(
        gate,
        session: session,
        load: (_) async {
          attempts++;
          throw const _ReadFailure(statusCode: 429, retryAfter: '120');
        },
      );
      final result = expectLater(lease.future, throwsA(isA<_ReadFailure>()));
      await tester.pump();
      await result;
      lease.release();
    }

    await failFirst();
    final retry = _read(
      gate,
      session: session,
      load: (_) async {
        attempts++;
        return attempts;
      },
    );
    final result = retry.future;
    await tester.pump(const Duration(seconds: 60));
    expect(attempts, 1);
    await tester.pump(const Duration(seconds: 60));
    await tester.pump();
    expect(await result, 2);
    retry.release();
    gate.dispose();
  });

  testWidgets('disposing the last reader cancels a cooldown wait', (
    tester,
  ) async {
    final gate = ForegroundReadGate(now: tester.binding.clock.now);
    final session = Object();
    var attempts = 0;

    final first = _read(
      gate,
      session: session,
      load: (_) async {
        attempts++;
        throw const _ReadFailure();
      },
    );
    final firstResult = expectLater(first.future, throwsA(isA<_ReadFailure>()));
    await tester.pump();
    await firstResult;
    first.release();

    final abandoned = _read(
      gate,
      session: session,
      load: (_) async {
        attempts++;
        return attempts;
      },
    );
    final abandonedResult = expectLater(
      abandoned.future,
      throwsA(isA<ForegroundReadCancelled>()),
    );
    abandoned.release();
    await abandonedResult;
    await tester.pump(const Duration(seconds: 5));
    expect(attempts, 1);

    final reentered = _read(
      gate,
      session: session,
      load: (_) async {
        attempts++;
        return attempts;
      },
    );
    await tester.pump();
    expect(attempts, 1);
    await tester.pump(const Duration(seconds: 4));
    expect(attempts, 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(attempts, 2);
    expect(await reentered.future, 2);
    reentered.release();
    gate.dispose();
  });

  testWidgets(
    'session replacement cancels old work and ignores its completion',
    (tester) async {
      final gate = ForegroundReadGate();
      final session = Object();
      final oldResponse = Completer<int>();
      CancelToken? oldToken;

      final old = _read(
        gate,
        session: session,
        generation: 1,
        load: (token) {
          oldToken = token;
          return oldResponse.future;
        },
      );
      final oldResult = expectLater(
        old.future,
        throwsA(isA<ForegroundReadStaleSession>()),
      );
      final current = _read(
        gate,
        session: session,
        generation: 2,
        load: (_) async => 2,
      );
      await tester.pump();

      expect(oldToken?.isCancelled, isTrue);
      await oldResult;
      expect(await current.future, 2);
      oldResponse.completeError(const _ReadFailure(statusCode: 429));
      await tester.pump();

      final next = _read(
        gate,
        session: session,
        generation: 2,
        load: (_) async => 3,
      );
      expect(await next.future, 3);
      old.release();
      current.release();
      next.release();
      gate.dispose();
    },
  );

  testWidgets('an ignored cancellation keeps same-key re-entry queued', (
    tester,
  ) async {
    final gate = ForegroundReadGate();
    final session = Object();
    final oldResponse = Completer<int>();
    var attempts = 0;

    final old = _read(
      gate,
      session: session,
      load: (_) {
        attempts++;
        return oldResponse.future;
      },
    );
    final oldResult = expectLater(
      old.future,
      throwsA(isA<ForegroundReadCancelled>()),
    );
    await tester.pump();
    old.release();

    final reentered = _read(
      gate,
      session: session,
      load: (_) async {
        attempts++;
        return attempts;
      },
    );
    await tester.pump();
    expect(attempts, 1);

    oldResponse.complete(1);
    await tester.pump();
    await oldResult;
    await tester.pump();
    expect(attempts, 2);
    expect(await reentered.future, 2);

    reentered.release();
    gate.dispose();
  });

  testWidgets('an abandoned 429 still delays queued re-entry', (tester) async {
    final gate = ForegroundReadGate(now: tester.binding.clock.now);
    final session = Object();
    final oldResponse = Completer<int>();
    var attempts = 0;

    final old = _read(
      gate,
      session: session,
      load: (_) {
        attempts++;
        return oldResponse.future;
      },
    );
    final oldResult = expectLater(
      old.future,
      throwsA(isA<ForegroundReadCancelled>()),
    );
    await tester.pump();
    old.release();

    final reentered = _read(
      gate,
      session: session,
      load: (_) async {
        attempts++;
        return attempts;
      },
    );
    await tester.pump();
    expect(attempts, 1);

    oldResponse.completeError(
      const _ReadFailure(statusCode: 429, retryAfter: '120'),
    );
    await tester.pump();
    await oldResult;
    await tester.pump(const Duration(seconds: 119));
    expect(attempts, 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(attempts, 2);
    expect(await reentered.future, 2);

    reentered.release();
    gate.dispose();
  });

  testWidgets(
    'disposing queued readers prevents their transport from starting',
    (tester) async {
      final gate = ForegroundReadGate();
      final session = Object();
      final oldResponse = Completer<int>();
      var attempts = 0;
      final old = _read(
        gate,
        session: session,
        load: (_) {
          attempts++;
          return oldResponse.future;
        },
      );
      final oldResult = expectLater(
        old.future,
        throwsA(isA<ForegroundReadCancelled>()),
      );
      await tester.pump();
      old.release();

      final queued = _read(
        gate,
        session: session,
        load: (_) async {
          attempts++;
          return attempts;
        },
      );
      final queuedResult = expectLater(
        queued.future,
        throwsA(isA<ForegroundReadCancelled>()),
      );
      queued.release();
      await queuedResult;

      oldResponse.complete(1);
      await tester.pump();
      await oldResult;
      expect(attempts, 1);
      gate.dispose();
    },
  );

  testWidgets('session replacement cancels queued same-key readers', (
    tester,
  ) async {
    final gate = ForegroundReadGate();
    final session = Object();
    final oldResponse = Completer<int>();
    var attempts = 0;
    final old = _read(
      gate,
      session: session,
      load: (_) {
        attempts++;
        return oldResponse.future;
      },
    );
    final oldResult = expectLater(
      old.future,
      throwsA(isA<ForegroundReadCancelled>()),
    );
    await tester.pump();
    old.release();

    final queued = _read(
      gate,
      session: session,
      load: (_) async {
        attempts++;
        return attempts;
      },
    );
    final queuedResult = expectLater(
      queued.future,
      throwsA(isA<ForegroundReadStaleSession>()),
    );
    final current = _read(
      gate,
      session: session,
      generation: 2,
      load: (_) async {
        attempts++;
        return attempts;
      },
    );
    await tester.pump();
    await oldResult;
    await queuedResult;
    expect(attempts, 2);
    expect(await current.future, 2);

    oldResponse.complete(1);
    await tester.pump();
    expect(attempts, 2);
    current.release();
    gate.dispose();
  });

  test('Retry-After accepts delta seconds and all HTTP-date forms', () {
    final now = DateTime.utc(2015, 10, 21, 7);
    const headers = [
      'Wed, 21 Oct 2015 07:02:00 GMT',
      'Wednesday, 21-Oct-15 07:02:00 GMT',
      'Wed Oct 21 07:02:00 2015',
    ];

    expect(
      ForegroundReadGate.parseRetryAfter('120', now),
      const Duration(seconds: 120),
    );
    for (final header in headers) {
      expect(
        ForegroundReadGate.parseRetryAfter(header, now),
        const Duration(minutes: 2),
      );
    }
    expect(ForegroundReadGate.parseRetryAfter('-1', now), isNull);
    expect(
      ForegroundReadGate.parseRetryAfter('Thu, 21 Oct 2015 07:02:00 GMT', now),
      isNull,
    );
    expect(ForegroundReadGate.parseRetryAfter('9000000000000', now), isNull);
  });

  testWidgets('successful values are never cached between reads', (
    tester,
  ) async {
    final gate = ForegroundReadGate();
    final session = Object();
    var attempts = 0;
    final first = _read(gate, session: session, load: (_) async => ++attempts);
    await tester.pump();
    expect(await first.future, 1);
    first.release();

    final second = _read(gate, session: session, load: (_) async => ++attempts);
    await tester.pump();
    expect(await second.future, 2);
    second.release();
    gate.dispose();
  });
}

ForegroundReadLease<int> _read(
  ForegroundReadGate gate, {
  required Object session,
  int generation = 1,
  Future<int> Function(CancelToken token)? load,
}) => gate.acquire<int>(
  sessionIdentity: session,
  generation: generation,
  requestKey: 'orders/pending/ALL',
  canStart: () => true,
  load: load ?? (_) async => 1,
  isTransientFailure: (error) =>
      error is _ReadFailure &&
      (error.statusCode == null || error.statusCode == 429),
  retryAfter: (error, now) => error is _ReadFailure && error.statusCode == 429
      ? ForegroundReadGate.parseRetryAfter(error.retryAfter, now)
      : null,
);

class _ReadFailure implements Exception {
  const _ReadFailure({this.statusCode, this.retryAfter});

  final int? statusCode;
  final String? retryAfter;
}
