import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../exchange/binance_read_routes.dart';

typedef BinanceRequestClock = DateTime Function();
typedef BinanceRequestDelay = Future<void> Function(Duration duration);

enum BinanceRequestPriority { bootstrap, interactive, history }

final binanceRequestCoordinatorProvider = Provider<BinanceRequestCoordinator>((
  ref,
) {
  return BinanceRequestCoordinator();
});

class BinanceRateLimitWindow {
  const BinanceRateLimitWindow({
    required this.rateLimitType,
    required this.interval,
    required this.intervalNum,
    required this.limit,
  });

  final String rateLimitType;
  final String interval;
  final int intervalNum;
  final int limit;

  Duration get duration {
    final unit = switch (interval) {
      'SECOND' => const Duration(seconds: 1),
      'MINUTE' => const Duration(minutes: 1),
      'HOUR' => const Duration(hours: 1),
      'DAY' => const Duration(days: 1),
      _ => Duration.zero,
    };
    return Duration(microseconds: unit.inMicroseconds * intervalNum);
  }

  String get key => '$rateLimitType:$interval:$intervalNum';

  String get headerSuffix {
    final unit = switch (interval) {
      'SECOND' => 's',
      'MINUTE' => 'm',
      'HOUR' => 'h',
      'DAY' => 'd',
      _ => '',
    };
    return '$intervalNum$unit';
  }
}

class BinanceHostBudgetState {
  const BinanceHostBudgetState({
    required this.host,
    required this.hasValidBudget,
    required this.isPaused,
    required this.retryAt,
    required this.queuedRequests,
    required this.activeRequests,
    required this.lastStartedAt,
  });

  final BinanceHost host;
  final bool hasValidBudget;
  final bool isPaused;
  final DateTime? retryAt;
  final int queuedRequests;
  final int activeRequests;
  final DateTime? lastStartedAt;
}

class BinanceRequestPausedException implements Exception {
  const BinanceRequestPausedException({
    required this.host,
    required this.retryAt,
    required this.reason,
  });

  final BinanceHost host;
  final DateTime? retryAt;
  final String reason;

  @override
  String toString() {
    if (retryAt == null) {
      return 'Binance ${host.name} requests are paused: $reason.';
    }
    return 'Binance ${host.name} requests are paused until '
        '${retryAt!.toUtc().toIso8601String()}: $reason.';
  }
}

/// Host-wide Binance weight/cooldown scheduler. Public and private routes for
/// one origin share its budget; Spot and Futures retain independent state.
class BinanceRequestCoordinator {
  BinanceRequestCoordinator({
    BinanceRequestClock? clock,
    BinanceRequestDelay? delay,
    this.minimumSpacing = const Duration(milliseconds: 250),
  }) : clock = clock ?? DateTime.now,
       delay = delay ?? _defaultDelay {
    if (minimumSpacing.isNegative) {
      throw ArgumentError.value(
        minimumSpacing,
        'minimumSpacing',
        'must not be negative',
      );
    }
  }

  final BinanceRequestClock clock;
  final BinanceRequestDelay delay;
  final Duration minimumSpacing;
  final Map<BinanceHost, _HostState> _hosts = <BinanceHost, _HostState>{
    BinanceHost.spot: _HostState(),
    BinanceHost.futures: _HostState(),
  };

  /// Installs tested/synthetic budgets, or the validated exchangeInfo limits.
  bool installLimits(BinanceHost host, List<BinanceRateLimitWindow> limits) {
    final state = _hosts[host]!;
    final valid =
        limits.isNotEmpty &&
        limits.every(
          (limit) =>
              (limit.rateLimitType == 'REQUEST_WEIGHT' ||
                  limit.rateLimitType == 'RAW_REQUEST') &&
              limit.duration > Duration.zero &&
              limit.limit > 0,
        ) &&
        limits.any((limit) => limit.rateLimitType == 'REQUEST_WEIGHT') &&
        limits.map((limit) => limit.key).toSet().length == limits.length;
    if (!valid) {
      state.limits = const <BinanceRateLimitWindow>[];
      state.hasValidBudget = false;
      return false;
    }
    state.limits = List<BinanceRateLimitWindow>.unmodifiable(limits);
    state.hasValidBudget = true;
    for (final limit in state.limits) {
      final usage = state.usage.putIfAbsent(limit.key, () => _WindowUsage());
      _prepareWindow(state, limit, usage, clock().toUtc());
      if (limit.rateLimitType == 'REQUEST_WEIGHT') {
        usage.used = _maxInt(
          usage.used,
          _reportedWeightFor(state, limit, usage.windowStartMilliseconds),
        );
      }
    }
    if (state.pendingBootstrapWeight > 0 ||
        state.pendingBootstrapRequests > 0) {
      for (final limit in state.limits) {
        final usage = state.usage[limit.key]!;
        if (limit.rateLimitType == 'REQUEST_WEIGHT') {
          usage.used = _maxInt(usage.used, state.pendingBootstrapWeight);
        } else if (limit.rateLimitType == 'RAW_REQUEST') {
          usage.used += state.pendingBootstrapRequests;
        }
      }
      state.pendingBootstrapWeight = 0;
      state.pendingBootstrapRequests = 0;
    }
    return true;
  }

  bool updateFromExchangeInfo(BinanceHost host, Object? body) {
    if (body is! Map || body['rateLimits'] is! List) {
      installLimits(host, const <BinanceRateLimitWindow>[]);
      return false;
    }
    final parsed = <BinanceRateLimitWindow>[];
    for (final value in body['rateLimits'] as List) {
      if (value is! Map) continue;
      final type = value['rateLimitType'];
      if (type != 'REQUEST_WEIGHT' && type != 'RAW_REQUEST') continue;
      final interval = value['interval'];
      final intervalNum = value['intervalNum'];
      final limit = value['limit'];
      if (interval is! String ||
          intervalNum is! num ||
          limit is! num ||
          intervalNum <= 0 ||
          limit <= 0 ||
          intervalNum % 1 != 0 ||
          limit % 1 != 0) {
        installLimits(host, const <BinanceRateLimitWindow>[]);
        return false;
      }
      parsed.add(
        BinanceRateLimitWindow(
          rateLimitType: type as String,
          interval: interval,
          intervalNum: intervalNum.toInt(),
          limit: limit.toInt(),
        ),
      );
    }
    return installLimits(host, parsed);
  }

  BinanceHostBudgetState stateFor(BinanceHost host) {
    final state = _hosts[host]!;
    final now = clock().toUtc();
    final paused =
        state.blockedUntil != null && now.isBefore(state.blockedUntil!);
    return BinanceHostBudgetState(
      host: host,
      hasValidBudget: state.hasValidBudget,
      isPaused: paused,
      retryAt: paused ? state.blockedUntil : null,
      queuedRequests: state.queue.length,
      activeRequests: state.activeRequests,
      lastStartedAt: state.lastStartedAt,
    );
  }

  /// Applies response weight headers and host-wide 429/418 cooldowns before
  /// the next queued request can start.
  void observeResponse(
    BinanceHost host, {
    required int? statusCode,
    required Map<String, List<String>> headers,
  }) {
    final state = _hosts[host]!;
    final now = clock().toUtc();
    for (final entry in headers.entries) {
      final normalized = entry.key.toLowerCase();
      if (!normalized.startsWith('x-mbx-used-weight-') || entry.value.isEmpty) {
        continue;
      }
      final value = int.tryParse(entry.value.first.trim());
      if (value == null || value < 0) continue;
      final suffix = normalized.substring('x-mbx-used-weight-'.length);
      state.reportedWeight[suffix] = value;
      state.reportedWeightAt[suffix] = now;
      for (final limit in state.limits) {
        if (limit.rateLimitType != 'REQUEST_WEIGHT' ||
            limit.headerSuffix != suffix) {
          continue;
        }
        final usage = state.usage[limit.key]!;
        _prepareWindow(state, limit, usage, now);
        usage.used = _maxInt(usage.used, value);
      }
    }
    if (statusCode != 429 && statusCode != 418) return;
    final retryAfter = _header(headers, 'retry-after');
    final fallback = statusCode == 418
        ? const Duration(minutes: 2)
        : const Duration(seconds: 30);
    final deadline = _parseRetryAfter(retryAfter, now) ?? now.add(fallback);
    final existing = state.blockedUntil;
    if (existing == null || deadline.isAfter(existing)) {
      state.blockedUntil = deadline;
    }
    state.blockReason = statusCode == 418 ? '418 IP ban' : '429 rate limit';
  }

  Future<T> run<T>({
    required BinanceHost host,
    required int weight,
    required BinanceRequestPriority priority,
    int rawRequests = 1,
    required Future<T> Function() request,
  }) {
    if (weight <= 0 || rawRequests <= 0) {
      return Future<T>.error(
        ArgumentError('Binance request cost must be positive.'),
      );
    }
    final state = _hosts[host]!;
    final job = _ScheduledRequest<T>(
      sequence: state.nextSequence++,
      weight: weight,
      rawRequests: rawRequests,
      priority: priority,
      request: request,
    );
    state.queue.add(job);
    _pump(host, state);
    return job.completer.future;
  }

  void _pump(BinanceHost host, _HostState state) {
    if (state.running) return;
    state.running = true;
    unawaited(_drain(host, state));
  }

  Future<void> _drain(BinanceHost host, _HostState state) async {
    try {
      while (state.queue.isNotEmpty) {
        state.queue.sort((left, right) => _compareJobs(left, right));
        final candidate = state.queue.first;
        final initialBlock = _blocked(
          host,
          state,
          candidate.priority,
          candidate.weight,
          candidate.rawRequests,
        );
        if (initialBlock != null) {
          state.queue.removeAt(0).completeError(initialBlock);
          continue;
        }
        final spacing = _spacing(state, clock().toUtc());
        if (spacing > Duration.zero) await delay(spacing);
        state.queue.sort((left, right) => _compareJobs(left, right));
        final job = state.queue.removeAt(0);
        final readyBlock = _blocked(
          host,
          state,
          job.priority,
          job.weight,
          job.rawRequests,
        );
        if (readyBlock != null) {
          job.completeError(readyBlock);
          continue;
        }
        _charge(state, job);
        state.lastStartedAt = clock().toUtc();
        state.activeRequests++;
        try {
          job.complete(await job.request());
        } catch (error, stackTrace) {
          job.completeError(error, stackTrace);
        } finally {
          state.activeRequests--;
        }
      }
    } finally {
      state.running = false;
      if (state.queue.isNotEmpty) _pump(host, state);
    }
  }

  BinanceRequestPausedException? _blocked(
    BinanceHost host,
    _HostState state,
    BinanceRequestPriority priority,
    int weight,
    int rawRequests,
  ) {
    final now = clock().toUtc();
    final blockedUntil = state.blockedUntil;
    if (blockedUntil != null && now.isBefore(blockedUntil)) {
      return BinanceRequestPausedException(
        host: host,
        retryAt: blockedUntil,
        reason: state.blockReason ?? 'host cooldown',
      );
    }
    if (blockedUntil != null && !now.isBefore(blockedUntil)) {
      state.blockedUntil = null;
      state.blockReason = null;
    }
    if (!state.hasValidBudget) {
      if (priority == BinanceRequestPriority.bootstrap) return null;
      return BinanceRequestPausedException(
        host: host,
        retryAt: null,
        reason: 'valid exchangeInfo rate-limit metadata is unavailable',
      );
    }
    DateTime? retryAt;
    for (final limit in state.limits) {
      final usage = state.usage[limit.key]!;
      _prepareWindow(state, limit, usage, now);
      final cost = limit.rateLimitType == 'REQUEST_WEIGHT'
          ? weight
          : rawRequests;
      final ownerCeiling = limit.limit * 80 ~/ 100;
      final historyCeiling = limit.limit * 60 ~/ 100;
      final exceedsOwnerCeiling = usage.used + cost > ownerCeiling;
      final exceedsHistoryCeiling =
          priority == BinanceRequestPriority.history &&
          usage.historyUsed + cost > historyCeiling;
      if (!exceedsOwnerCeiling && !exceedsHistoryCeiling) continue;
      final deadline = DateTime.fromMillisecondsSinceEpoch(
        usage.windowStartMilliseconds + limit.duration.inMilliseconds,
        isUtc: true,
      );
      if (retryAt == null || deadline.isAfter(retryAt)) retryAt = deadline;
    }
    if (retryAt == null) return null;
    return BinanceRequestPausedException(
      host: host,
      retryAt: retryAt,
      reason: priority == BinanceRequestPriority.history
          ? 'the reserved history weight budget is exhausted'
          : 'the agent-owned request weight budget is exhausted',
    );
  }

  void _charge(_HostState state, _ScheduledRequest<Object?> job) {
    if (!state.hasValidBudget) {
      state.pendingBootstrapWeight += job.weight;
      state.pendingBootstrapRequests += job.rawRequests;
      return;
    }
    for (final limit in state.limits) {
      final usage = state.usage[limit.key]!;
      _prepareWindow(state, limit, usage, clock().toUtc());
      final cost = limit.rateLimitType == 'REQUEST_WEIGHT'
          ? job.weight
          : job.rawRequests;
      usage.used += cost;
      if (job.priority == BinanceRequestPriority.history) {
        usage.historyUsed += cost;
      }
    }
  }

  Duration _spacing(_HostState state, DateTime now) {
    final last = state.lastStartedAt;
    if (last == null) return Duration.zero;
    final elapsed = now.difference(last);
    return elapsed >= minimumSpacing ? Duration.zero : minimumSpacing - elapsed;
  }

  void _prepareWindow(
    _HostState state,
    BinanceRateLimitWindow limit,
    _WindowUsage usage,
    DateTime now,
  ) {
    final durationMs = limit.duration.inMilliseconds;
    final start = (now.millisecondsSinceEpoch ~/ durationMs) * durationMs;
    if (usage.windowStartMilliseconds == start) return;
    usage
      ..windowStartMilliseconds = start
      ..used = 0
      ..historyUsed = 0;
    if (limit.rateLimitType == 'REQUEST_WEIGHT') {
      usage.used = _reportedWeightFor(state, limit, start);
    }
  }

  int _reportedWeightFor(
    _HostState state,
    BinanceRateLimitWindow limit,
    int windowStartMilliseconds,
  ) {
    final reportedAt = state.reportedWeightAt[limit.headerSuffix];
    if (reportedAt == null) return 0;
    final time = reportedAt.millisecondsSinceEpoch;
    final windowEnd = windowStartMilliseconds + limit.duration.inMilliseconds;
    if (time < windowStartMilliseconds || time >= windowEnd) return 0;
    return state.reportedWeight[limit.headerSuffix] ?? 0;
  }

  static String? _header(Map<String, List<String>> headers, String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name && entry.value.isNotEmpty) {
        return entry.value.first.trim();
      }
    }
    return null;
  }

  static DateTime? _parseRetryAfter(String? value, DateTime now) {
    if (value == null || value.isEmpty) return null;
    final seconds = int.tryParse(value);
    if (seconds != null && seconds >= 0)
      return now.add(Duration(seconds: seconds));
    final match = RegExp(
      r'^(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun),\s+(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})\s+GMT$',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) return null;
    const months = <String, int>{
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
    final month = months[match.group(2)!.toLowerCase()];
    if (month == null) return null;
    try {
      return DateTime.utc(
        int.parse(match.group(3)!),
        month,
        int.parse(match.group(1)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
      );
    } on FormatException {
      return null;
    }
  }

  static int _maxInt(int left, int right) => left > right ? left : right;

  static int _compareJobs(
    _ScheduledRequest<Object?> left,
    _ScheduledRequest<Object?> right,
  ) {
    final byPriority = left.priority.index.compareTo(right.priority.index);
    return byPriority == 0
        ? left.sequence.compareTo(right.sequence)
        : byPriority;
  }

  static Future<void> _defaultDelay(Duration duration) =>
      Future<void>.delayed(duration);
}

class _HostState {
  List<BinanceRateLimitWindow> limits = const <BinanceRateLimitWindow>[];
  final List<_ScheduledRequest<Object?>> queue = <_ScheduledRequest<Object?>>[];
  final Map<String, _WindowUsage> usage = <String, _WindowUsage>{};
  final Map<String, int> reportedWeight = <String, int>{};
  final Map<String, DateTime> reportedWeightAt = <String, DateTime>{};
  bool hasValidBudget = false;
  bool running = false;
  int nextSequence = 0;
  int activeRequests = 0;
  int pendingBootstrapWeight = 0;
  int pendingBootstrapRequests = 0;
  DateTime? lastStartedAt;
  DateTime? blockedUntil;
  String? blockReason;
}

class _WindowUsage {
  int windowStartMilliseconds = -1;
  int used = 0;
  int historyUsed = 0;
}

class _ScheduledRequest<T> {
  _ScheduledRequest({
    required this.sequence,
    required this.weight,
    required this.rawRequests,
    required this.priority,
    required this.request,
  });

  final int sequence;
  final int weight;
  final int rawRequests;
  final BinanceRequestPriority priority;
  final Future<T> Function() request;
  final Completer<T> completer = Completer<T>();

  void complete(T result) {
    if (!completer.isCompleted) completer.complete(result);
  }

  void completeError(Object error, [StackTrace? stackTrace]) {
    if (!completer.isCompleted) completer.completeError(error, stackTrace);
  }
}
