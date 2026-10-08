import 'dart:async';

import 'package:dio/dio.dart';

/// Coordinates foreground GETs for one semantic backend-session generation.
/// It deliberately does not retain successful values or schedule retries.
class ForegroundReadGate {
  ForegroundReadGate({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const List<Duration> _backoff = [
    Duration(seconds: 10),
    Duration(seconds: 20),
    Duration(seconds: 40),
    Duration(seconds: 60),
  ];

  final DateTime Function() _now;
  final Map<String, _ReadRetryState> _retryStates = {};
  final Map<String, _ReadOperation> _operations = {};
  final Map<String, _ReadOperation> _queuedOperations = {};
  Object? _sessionIdentity;
  int? _generation;
  int _nextCallerId = 0;
  bool _disposed = false;

  ForegroundReadLease<T> acquire<T>({
    required Object sessionIdentity,
    required int generation,
    required String requestKey,
    required bool Function() canStart,
    required Future<T> Function(CancelToken cancelToken) load,
    required bool Function(Object error) isTransientFailure,
    bool Function(Object error)? isCancellationFailure,
    required Duration? Function(Object error, DateTime now) retryAfter,
  }) {
    if (_disposed) throw StateError('ForegroundReadGate is disposed.');
    _syncScope(sessionIdentity, generation);

    var operation = _operations[requestKey];
    if (operation?.cancellationRequested == true) {
      operation = _queuedOperations[requestKey];
      if (operation == null) {
        operation = _ReadOperation(requestKey);
        _queuedOperations[requestKey] = operation;
      }
    } else if (operation == null) {
      operation = _ReadOperation(requestKey);
      _operations[requestKey] = operation;
    }

    final callerId = ++_nextCallerId;
    operation.callers[callerId] = _ReadCaller(
      canStart: canStart,
      load: (token) async => await load(token),
      isTransientFailure: isTransientFailure,
      isCancellationFailure: isCancellationFailure ?? _isDioCancellation,
      retryAfter: retryAfter,
    );

    if (identical(_operations[requestKey], operation) &&
        !operation.started &&
        operation.timer == null) {
      _schedule(operation);
    }

    return ForegroundReadLease<T>._(this, operation, callerId);
  }

  static Duration? parseRetryAfter(String? header, DateTime now) {
    final value = header?.trim();
    if (value == null || value.isEmpty) return null;

    if (RegExp(r'^\d+$').hasMatch(value)) {
      final seconds = int.tryParse(value);
      if (seconds == null) return null;
      final delay = Duration(seconds: seconds);
      try {
        now.toUtc().add(delay);
      } on Object {
        return null;
      }
      return delay;
    }

    final date = _parseHttpDate(value, now);
    if (date == null) return null;
    final difference = date.difference(now.toUtc());
    return difference.isNegative ? Duration.zero : difference;
  }

  static DateTime? _parseHttpDate(String value, DateTime now) {
    final imfFixdate = RegExp(
      r'^(Mon|Tue|Wed|Thu|Fri|Sat|Sun), (\d{2}) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
    ).firstMatch(value);
    if (imfFixdate != null) {
      return _validatedDate(
        weekday: imfFixdate[1]!,
        day: int.parse(imfFixdate[2]!),
        monthName: imfFixdate[3]!,
        year: int.parse(imfFixdate[4]!),
        hour: int.parse(imfFixdate[5]!),
        minute: int.parse(imfFixdate[6]!),
        second: int.parse(imfFixdate[7]!),
      );
    }

    final rfc850 = RegExp(
      r'^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday), (\d{2})-(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)-(\d{2}) (\d{2}):(\d{2}):(\d{2}) GMT$',
    ).firstMatch(value);
    if (rfc850 != null) {
      final currentYear = now.toUtc().year;
      final shortYear = int.parse(rfc850[4]!);
      var year = (currentYear ~/ 100) * 100 + shortYear;
      if (year > currentYear + 50) year -= 100;
      return _validatedDate(
        weekday: rfc850[1]!,
        day: int.parse(rfc850[2]!),
        monthName: rfc850[3]!,
        year: year,
        hour: int.parse(rfc850[5]!),
        minute: int.parse(rfc850[6]!),
        second: int.parse(rfc850[7]!),
        longWeekday: true,
      );
    }

    final asctime = RegExp(
      r'^(Mon|Tue|Wed|Thu|Fri|Sat|Sun) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d{1,2}) (\d{2}):(\d{2}):(\d{2}) (\d{4})$',
    ).firstMatch(value);
    if (asctime != null) {
      return _validatedDate(
        weekday: asctime[1]!,
        monthName: asctime[2]!,
        day: int.parse(asctime[3]!),
        hour: int.parse(asctime[4]!),
        minute: int.parse(asctime[5]!),
        second: int.parse(asctime[6]!),
        year: int.parse(asctime[7]!),
      );
    }
    return null;
  }

  static DateTime? _validatedDate({
    required String weekday,
    required int day,
    required String monthName,
    required int year,
    required int hour,
    required int minute,
    required int second,
    bool longWeekday = false,
  }) {
    const months = {
      'Jan': 1,
      'Feb': 2,
      'Mar': 3,
      'Apr': 4,
      'May': 5,
      'Jun': 6,
      'Jul': 7,
      'Aug': 8,
      'Sep': 9,
      'Oct': 10,
      'Nov': 11,
      'Dec': 12,
    };
    const shortWeekdays = {
      'Mon': 1,
      'Tue': 2,
      'Wed': 3,
      'Thu': 4,
      'Fri': 5,
      'Sat': 6,
      'Sun': 7,
    };
    const longWeekdays = {
      'Monday': 1,
      'Tuesday': 2,
      'Wednesday': 3,
      'Thursday': 4,
      'Friday': 5,
      'Saturday': 6,
      'Sunday': 7,
    };
    final month = months[monthName];
    final expectedWeekday = longWeekday
        ? longWeekdays[weekday]
        : shortWeekdays[weekday];
    if (month == null || expectedWeekday == null) return null;

    DateTime date;
    try {
      date = DateTime.utc(year, month, day, hour, minute, second);
    } on ArgumentError {
      return null;
    }
    if (date.year != year ||
        date.month != month ||
        date.day != day ||
        date.hour != hour ||
        date.minute != minute ||
        date.second != second ||
        date.weekday != expectedWeekday) {
      return null;
    }
    return date;
  }

  void _syncScope(Object identity, int generation) {
    if (identical(identity, _sessionIdentity) && generation == _generation) {
      return;
    }
    _sessionIdentity = identity;
    _generation = generation;
    _retryStates.clear();
    final staleOperations = _operations.values.toList();
    staleOperations.addAll(_queuedOperations.values);
    _operations.clear();
    _queuedOperations.clear();
    for (final operation in staleOperations) {
      operation.timer?.cancel();
      if (!operation.cancelToken.isCancelled) {
        operation.cancelToken.cancel('Backend session changed.');
      }
      if (!operation.result.isCompleted) {
        operation.result.completeError(const ForegroundReadStaleSession());
      }
    }
  }

  void _schedule(_ReadOperation operation) {
    final retryState = _retryStates[operation.key];
    final nextAttempt = retryState?.nextAttemptAt;
    final wait = nextAttempt?.difference(_now());
    if (wait != null && wait > Duration.zero) {
      operation.timer = Timer(wait, () {
        operation.timer = null;
        unawaited(_execute(operation));
      });
    } else {
      unawaited(_execute(operation));
    }
  }

  Future<void> _execute(_ReadOperation operation) async {
    if (!_owns(operation) || operation.started) return;
    _ReadCaller? caller;
    for (final candidate in operation.callers.values) {
      try {
        if (candidate.canStart()) {
          caller = candidate;
          break;
        }
      } catch (_) {
        // A disposed provider is not eligible to start a transport request.
      }
    }
    if (caller == null) {
      _finishError(operation, const ForegroundReadStaleSession());
      return;
    }

    operation.started = true;
    try {
      final value = await caller.load(operation.cancelToken);
      if (!_owns(operation)) return;
      if (operation.cancellationRequested || operation.callers.isEmpty) {
        _finishAbandoned(operation);
        return;
      }
      _retryStates.remove(operation.key);
      _operations.remove(operation.key);
      operation.result.complete(value);
    } catch (error, stackTrace) {
      if (!_owns(operation)) return;
      if (operation.cancellationRequested || operation.callers.isEmpty) {
        if (_isTransientFailure(caller, error)) {
          _recordFailure(operation, caller, error);
        }
        _finishAbandoned(operation);
        return;
      }
      _recordFailure(operation, caller, error);
      _operations.remove(operation.key);
      operation.result.completeError(error, stackTrace);
    }
  }

  void _recordFailure(
    _ReadOperation operation,
    _ReadCaller caller,
    Object error,
  ) {
    if (_isCancellationFailure(caller, error)) return;
    if (!_isTransientFailure(caller, error)) {
      _retryStates.remove(operation.key);
      return;
    }

    final failureCount = (_retryStates[operation.key]?.failureCount ?? 0) + 1;
    final localDelay =
        _backoff[(failureCount - 1).clamp(0, _backoff.length - 1)];
    Duration delay = localDelay;
    try {
      final serverDelay = caller.retryAfter(error, _now());
      if (serverDelay != null && serverDelay > delay) delay = serverDelay;
    } catch (_) {
      // An invalid Retry-After value falls back to the local backoff.
    }
    final now = _now();
    DateTime nextAttemptAt;
    try {
      nextAttemptAt = now.add(delay);
    } on Object {
      nextAttemptAt = now.add(localDelay);
    }
    _retryStates[operation.key] = _ReadRetryState(
      failureCount: failureCount,
      nextAttemptAt: nextAttemptAt,
    );
  }

  bool _isTransientFailure(_ReadCaller caller, Object error) {
    try {
      return caller.isTransientFailure(error);
    } catch (_) {
      return false;
    }
  }

  bool _isCancellationFailure(_ReadCaller caller, Object error) {
    try {
      return caller.isCancellationFailure(error);
    } catch (_) {
      return false;
    }
  }

  bool _isDioCancellation(Object error) =>
      error is DioException && error.type == DioExceptionType.cancel;

  bool _owns(_ReadOperation operation) =>
      !_disposed && identical(_operations[operation.key], operation);

  void _finishError(_ReadOperation operation, Object error) {
    if (!_owns(operation)) return;
    _operations.remove(operation.key);
    if (!operation.result.isCompleted) operation.result.completeError(error);
  }

  void _finishAbandoned(_ReadOperation operation) {
    if (!_owns(operation)) return;
    _operations.remove(operation.key);
    final queued = _queuedOperations.remove(operation.key);
    if (queued != null && queued.callers.isNotEmpty) {
      _operations[operation.key] = queued;
      _schedule(queued);
    } else if (queued != null && !queued.result.isCompleted) {
      queued.result.completeError(const ForegroundReadCancelled());
    }
  }

  void _release(_ReadOperation operation, int callerId) {
    operation.callers.remove(callerId);
    if (identical(_queuedOperations[operation.key], operation)) {
      if (operation.callers.isEmpty) {
        _queuedOperations.remove(operation.key);
        operation.timer?.cancel();
        if (!operation.cancelToken.isCancelled) {
          operation.cancelToken.cancel('No foreground readers remain.');
        }
        if (!operation.result.isCompleted) {
          operation.result.completeError(const ForegroundReadCancelled());
        }
      }
      return;
    }
    if (operation.callers.isNotEmpty || !_owns(operation)) return;

    if (operation.started) {
      operation.cancellationRequested = true;
      if (!operation.cancelToken.isCancelled) {
        operation.cancelToken.cancel('No foreground readers remain.');
      }
      if (!operation.result.isCompleted) {
        operation.result.completeError(const ForegroundReadCancelled());
      }
      return;
    }

    _operations.remove(operation.key);
    operation.timer?.cancel();
    if (!operation.cancelToken.isCancelled) {
      operation.cancelToken.cancel('No foreground readers remain.');
    }
    if (!operation.result.isCompleted) {
      operation.result.completeError(const ForegroundReadCancelled());
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final operations = _operations.values.toList();
    operations.addAll(_queuedOperations.values);
    _operations.clear();
    _queuedOperations.clear();
    _retryStates.clear();
    for (final operation in operations) {
      operation.timer?.cancel();
      if (!operation.cancelToken.isCancelled) {
        operation.cancelToken.cancel('Foreground read gate disposed.');
      }
      if (!operation.result.isCompleted) {
        operation.result.completeError(const ForegroundReadCancelled());
      }
    }
  }
}

class ForegroundReadLease<T> {
  ForegroundReadLease._(this._gate, this._operation, this._callerId)
    : future = _operation.result.future.then((value) => value as T);

  final ForegroundReadGate _gate;
  final _ReadOperation _operation;
  final int _callerId;
  final Future<T> future;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _gate._release(_operation, _callerId);
  }
}

class ForegroundReadStaleSession implements Exception {
  const ForegroundReadStaleSession();

  @override
  String toString() => 'The backend session changed before the read started.';
}

class ForegroundReadCancelled implements Exception {
  const ForegroundReadCancelled();

  @override
  String toString() => 'The foreground read no longer has an active caller.';
}

class _ReadRetryState {
  const _ReadRetryState({
    required this.failureCount,
    required this.nextAttemptAt,
  });

  final int failureCount;
  final DateTime nextAttemptAt;
}

class _ReadOperation {
  _ReadOperation(this.key);

  final String key;
  final Completer<Object?> result = Completer<Object?>();
  final CancelToken cancelToken = CancelToken();
  final Map<int, _ReadCaller> callers = {};
  Timer? timer;
  bool started = false;
  bool cancellationRequested = false;
}

class _ReadCaller {
  const _ReadCaller({
    required this.canStart,
    required this.load,
    required this.isTransientFailure,
    required this.isCancellationFailure,
    required this.retryAfter,
  });

  final bool Function() canStart;
  final Future<Object?> Function(CancelToken cancelToken) load;
  final bool Function(Object error) isTransientFailure;
  final bool Function(Object error) isCancellationFailure;
  final Duration? Function(Object error, DateTime now) retryAfter;
}
