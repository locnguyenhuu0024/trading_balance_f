import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Endpoint classes are deliberately small.  Authenticated and public work
/// must not share credentials, but each class still has one scheduler and one
/// backoff state so another position cannot bypass a rate-limit response.
enum RiskRequestLane { authenticated, public }

typedef RiskRequestClock = DateTime Function();
typedef RiskRequestDelay = Future<void> Function(Duration duration);

final riskRequestCoordinatorProvider = Provider<RiskRequestCoordinator>((ref) {
  return RiskRequestCoordinator();
});

/// A request was rejected by the coordinator before it reached the adapter.
/// The error contains only safe scheduling metadata; it never stores request
/// headers, payloads, or credentials.
class RiskRequestBackoffException implements Exception {
  const RiskRequestBackoffException({
    required this.lane,
    required this.key,
    required this.retryAt,
    this.retryAfter,
    this.statusCode = 429,
    this.cause,
  });

  final RiskRequestLane lane;
  final String key;
  final DateTime retryAt;
  final Duration? retryAfter;
  final int statusCode;
  final Object? cause;

  @override
  String toString() =>
      'RiskRequestBackoffException (HTTP $statusCode): '
      '${lane.name} lane is backing off until ${retryAt.toUtc().toIso8601String()}';
}

/// The first request that receives HTTP 429 closes its lane immediately. The
/// original error is retained only as an opaque cause for local debugging.
class RiskRequestRateLimitException extends RiskRequestBackoffException {
  const RiskRequestRateLimitException({
    required super.lane,
    required super.key,
    required super.retryAt,
    super.retryAfter,
    super.statusCode = 429,
    super.cause,
  });
}

/// Safe, read-only scheduler state exposed for typed UI/monitor metadata.
class RiskRequestLaneState {
  const RiskRequestLaneState({
    required this.lane,
    required this.isClosed,
    required this.activeRequests,
    required this.lastStartedAt,
    required this.retryAt,
    required this.retryAfter,
    required this.consecutiveRateLimits,
  });

  final RiskRequestLane lane;
  final bool isClosed;
  final int activeRequests;
  final DateTime? lastStartedAt;
  final DateTime? retryAt;
  final Duration? retryAfter;
  final int consecutiveRateLimits;

  bool get isBackingOff => isClosed && retryAt != null;
}

/// Shared request foundation for risk repositories.
///
/// Calls are keyed and single-flight, then serialized per endpoint class. A
/// successful call is allowed only after the minimum inter-request spacing;
/// an HTTP 429 closes the entire lane before any queued work can start.
class RiskRequestCoordinator {
  RiskRequestCoordinator({
    RiskRequestClock? clock,
    RiskRequestDelay? delay,
    this.minimumSpacing = const Duration(milliseconds: 250),
    this.backoffSchedule = const <Duration>[
      Duration(seconds: 30),
      Duration(seconds: 60),
      Duration(seconds: 120),
      Duration(seconds: 300),
    ],
  }) : clock = clock ?? DateTime.now,
       delay = delay ?? _defaultDelay {
    if (minimumSpacing.isNegative) {
      throw ArgumentError.value(
        minimumSpacing,
        'minimumSpacing',
        'must not be negative',
      );
    }
    if (backoffSchedule.isEmpty ||
        backoffSchedule.any((duration) => duration.isNegative)) {
      throw ArgumentError.value(
        backoffSchedule,
        'backoffSchedule',
        'must contain at least one non-negative duration',
      );
    }
  }

  final RiskRequestClock clock;
  final RiskRequestDelay delay;
  final Duration minimumSpacing;
  final List<Duration> backoffSchedule;

  final Map<RiskRequestLane, _RiskLaneState> _lanes = {
    RiskRequestLane.authenticated: _RiskLaneState(),
    RiskRequestLane.public: _RiskLaneState(),
  };
  final Map<String, Future<Object?>> _inFlight = <String, Future<Object?>>{};

  /// Execute [request] through the lane scheduler.
  ///
  /// [key] is stable for the request's endpoint and query. Calls with the
  /// same lane/key share one future; distinct keys remain serialized by lane.
  Future<T> run<T>({
    required RiskRequestLane lane,
    required String key,
    required Future<T> Function() request,
  }) {
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty) {
      throw ArgumentError.value(key, 'key', 'must not be empty');
    }
    final inFlightKey = '${lane.name}:$normalizedKey';
    final existing = _inFlight[inFlightKey];
    if (existing != null) return existing as Future<T>;

    final state = _lanes[lane]!;
    final now = clock().toUtc();
    final closedUntil = state.closedUntil;
    if (closedUntil != null && now.isBefore(closedUntil)) {
      return Future<T>.error(
        RiskRequestBackoffException(
          lane: lane,
          key: normalizedKey,
          retryAt: closedUntil,
          retryAfter: closedUntil.difference(now),
        ),
      );
    }

    final scheduled = state.tail.then<T>((_) async {
      _throwIfClosed(lane, normalizedKey, state);
      final wait = _spacingWait(state, clock().toUtc());
      if (wait > Duration.zero) await delay(wait);
      // A preceding queued request can receive a 429 while this job was
      // waiting. Re-check immediately before invoking the adapter.
      _throwIfClosed(lane, normalizedKey, state);
      state.activeRequests++;
      state.lastStartedAt = clock().toUtc();
      try {
        final value = await request();
        state.consecutiveRateLimits = 0;
        return value;
      } catch (error, stackTrace) {
        if (_statusCode(error) == 429) {
          final retryAt = _closeLane(
            lane,
            state,
            retryAfter: _retryAfter(error),
          );
          throw RiskRequestRateLimitException(
            lane: lane,
            key: normalizedKey,
            retryAt: retryAt,
            retryAfter: retryAt.difference(clock().toUtc()),
            cause: _withStack(error, stackTrace),
          );
        }
        rethrow;
      } finally {
        state.activeRequests--;
      }
    });

    // Keep the lane chain alive after a failed request. The request future
    // itself still reports the original typed failure to its caller.
    state.tail = scheduled.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    _inFlight[inFlightKey] = scheduled;
    scheduled.then<void>(
      (_) {
        if (identical(_inFlight[inFlightKey], scheduled)) {
          _inFlight.remove(inFlightKey);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_inFlight[inFlightKey], scheduled)) {
          _inFlight.remove(inFlightKey);
        }
      },
    );
    return scheduled;
  }

  /// Alias used by repository adapters that describe a scheduled operation as
  /// a request rather than a run.
  Future<T> request<T>({
    required RiskRequestLane lane,
    required String key,
    required Future<T> Function() operation,
  }) => run(lane: lane, key: key, request: operation);

  /// Alias retained for callers that use queue terminology.
  Future<T> enqueue<T>({
    required RiskRequestLane lane,
    required String key,
    required Future<T> Function() operation,
  }) => run(lane: lane, key: key, request: operation);

  RiskRequestLaneState stateFor(RiskRequestLane lane) {
    final state = _lanes[lane]!;
    final now = clock().toUtc();
    final retryAt = state.closedUntil;
    return RiskRequestLaneState(
      lane: lane,
      isClosed: retryAt != null && now.isBefore(retryAt),
      activeRequests: state.activeRequests,
      lastStartedAt: state.lastStartedAt,
      retryAt: retryAt,
      retryAfter: retryAt == null
          ? null
          : retryAt.difference(now).isNegative
          ? Duration.zero
          : retryAt.difference(now),
      consecutiveRateLimits: state.consecutiveRateLimits,
    );
  }

  RiskRequestLaneState laneState(RiskRequestLane lane) => stateFor(lane);

  bool isBackingOff(RiskRequestLane lane) => stateFor(lane).isBackingOff;

  DateTime? retryAtFor(RiskRequestLane lane) => stateFor(lane).retryAt;

  Duration? retryAfterFor(RiskRequestLane lane) => stateFor(lane).retryAfter;

  /// Clear a lane's backoff after credential rotation or an explicit owner
  /// reset. In-flight work is intentionally not cancelled.
  void clearLane(RiskRequestLane lane) {
    final state = _lanes[lane]!;
    state.closedUntil = null;
    state.consecutiveRateLimits = 0;
  }

  void clear() {
    clearLane(RiskRequestLane.authenticated);
    clearLane(RiskRequestLane.public);
  }

  Duration _spacingWait(_RiskLaneState state, DateTime now) {
    final last = state.lastStartedAt;
    if (last == null) return Duration.zero;
    final elapsed = now.difference(last);
    if (elapsed >= minimumSpacing) return Duration.zero;
    return minimumSpacing - elapsed;
  }

  void _throwIfClosed(RiskRequestLane lane, String key, _RiskLaneState state) {
    final retryAt = state.closedUntil;
    if (retryAt == null) return;
    final now = clock().toUtc();
    if (!now.isBefore(retryAt)) return;
    throw RiskRequestBackoffException(
      lane: lane,
      key: key,
      retryAt: retryAt,
      retryAfter: retryAt.difference(now),
    );
  }

  DateTime _closeLane(
    RiskRequestLane lane,
    _RiskLaneState state, {
    required Duration? retryAfter,
  }) {
    final now = clock().toUtc();
    final index = state.consecutiveRateLimits.clamp(
      0,
      backoffSchedule.length - 1,
    );
    final backoff = backoffSchedule[index];
    state.consecutiveRateLimits++;
    final effective = retryAfter == null || retryAfter < backoff
        ? backoff
        : retryAfter;
    final retryAt = now.add(effective);
    final existing = state.closedUntil;
    state.closedUntil = existing == null || retryAt.isAfter(existing)
        ? retryAt
        : existing;
    state.lastRetryAfter = effective;
    return state.closedUntil!;
  }

  int? _statusCode(Object error) {
    if (error is RiskRequestBackoffException) return error.statusCode;
    if (error is DioException) return error.response?.statusCode;
    return null;
  }

  Duration? _retryAfter(Object error) {
    if (error is RiskRequestBackoffException) return error.retryAfter;
    if (error is! DioException) return null;
    final raw = error.response?.headers.value('retry-after')?.trim();
    if (raw == null || raw.isEmpty) return null;
    final seconds = int.tryParse(raw);
    if (seconds != null && seconds >= 0) {
      return Duration(seconds: seconds);
    }
    final date = _parseHttpDate(raw);
    if (date == null) return null;
    final duration = date.difference(clock().toUtc());
    return duration.isNegative ? Duration.zero : duration;
  }

  DateTime? _parseHttpDate(String raw) {
    final monthNumbers = <String, int>{
      'jan': 1,
      'feb': 2,
      'mar': 3,
      'apr': 4,
      'may': 5,
      'jun': 6,
      'jul': 7,
      'aug': 8,
      'sep': 9,
      'oct': 10,
      'nov': 11,
      'dec': 12,
    };
    final rfc1123 = RegExp(
      r'^(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun),\s+(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})\s+GMT$',
      caseSensitive: false,
    ).firstMatch(raw);
    final rfc850 = RegExp(
      r'^(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday),\s+(\d{1,2})-([A-Za-z]{3})-(\d{2})\s+(\d{2}):(\d{2}):(\d{2})\s+GMT$',
      caseSensitive: false,
    ).firstMatch(raw);
    final asctime = RegExp(
      r'^(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s+([A-Za-z]{3})\s+(\d{1,2})\s+(\d{2}):(\d{2}):(\d{2})\s+(\d{4})$',
      caseSensitive: false,
    ).firstMatch(raw);
    try {
      if (rfc1123 != null) {
        final month = monthNumbers[rfc1123.group(2)!.toLowerCase()];
        if (month == null) return null;
        return DateTime.utc(
          int.parse(rfc1123.group(3)!),
          month,
          int.parse(rfc1123.group(1)!),
          int.parse(rfc1123.group(4)!),
          int.parse(rfc1123.group(5)!),
          int.parse(rfc1123.group(6)!),
        );
      }
      if (rfc850 != null) {
        final month = monthNumbers[rfc850.group(2)!.toLowerCase()];
        if (month == null) return null;
        final shortYear = int.parse(rfc850.group(3)!);
        final year = shortYear >= 50 ? 1900 + shortYear : 2000 + shortYear;
        return DateTime.utc(
          year,
          month,
          int.parse(rfc850.group(1)!),
          int.parse(rfc850.group(4)!),
          int.parse(rfc850.group(5)!),
          int.parse(rfc850.group(6)!),
        );
      }
      if (asctime != null) {
        final month = monthNumbers[asctime.group(1)!.toLowerCase()];
        if (month == null) return null;
        return DateTime.utc(
          int.parse(asctime.group(6)!),
          month,
          int.parse(asctime.group(2)!),
          int.parse(asctime.group(3)!),
          int.parse(asctime.group(4)!),
          int.parse(asctime.group(5)!),
        );
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  Object _withStack(Object error, StackTrace stackTrace) => error;

  static Future<void> _defaultDelay(Duration duration) {
    return Future<void>.delayed(duration);
  }
}

class _RiskLaneState {
  Future<void> tail = Future<void>.value();
  DateTime? lastStartedAt;
  DateTime? closedUntil;
  Duration? lastRetryAfter;
  int consecutiveRateLimits = 0;
  int activeRequests = 0;
}
