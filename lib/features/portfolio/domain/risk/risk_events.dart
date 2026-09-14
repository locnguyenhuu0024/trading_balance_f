import 'action_plan.dart';
import 'risk_history.dart';
import 'risk_models.dart';
import 'risk_policy.dart';

enum RiskEventKind {
  stateChange,
  bufferBoundary,
  leverageBoundary,
  marginBoundary,
  ruleEntry,
  zoneEntry,
  factorEntry,
  interestChange,
  configurationChange,
  reconnect,
}

extension RiskEventKindX on RiskEventKind {
  String get name {
    switch (this) {
      case RiskEventKind.stateChange:
        return 'stateChange';
      case RiskEventKind.bufferBoundary:
        return 'bufferBoundary';
      case RiskEventKind.leverageBoundary:
        return 'leverageBoundary';
      case RiskEventKind.marginBoundary:
        return 'marginBoundary';
      case RiskEventKind.ruleEntry:
        return 'ruleEntry';
      case RiskEventKind.zoneEntry:
        return 'zoneEntry';
      case RiskEventKind.factorEntry:
        return 'factorEntry';
      case RiskEventKind.interestChange:
        return 'interestChange';
      case RiskEventKind.configurationChange:
        return 'configurationChange';
      case RiskEventKind.reconnect:
        return 'reconnect';
    }
  }
}

/// A typed reason contributing to one observation-level event.
class RiskEventContribution {
  const RiskEventContribution({
    required this.id,
    required this.kind,
    required this.factorId,
    required this.message,
    required this.createdAt,
    required this.observedAt,
    this.severity,
    this.source,
    this.previousValue,
    this.currentValue,
    this.quality,
  });

  final String id;
  final RiskEventKind kind;
  final String factorId;
  final String message;
  final DateTime createdAt;
  final DateTime observedAt;
  final RiskSeverity? severity;
  final String? source;
  final double? previousValue;
  final double? currentValue;
  final RiskQuality? quality;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'kind': kind.name,
    'factorId': factorId,
    'message': message,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'observedAt': observedAt.toUtc().toIso8601String(),
    'severity': severity?.name,
    'source': source,
    'previousValue': previousValue,
    'currentValue': currentValue,
    'quality': quality == null ? null : _qualityToJson(quality!),
  };

  factory RiskEventContribution.fromJson(Map<String, dynamic> json) {
    final kindText = _requiredString(json, 'kind');
    final severityText = json['severity'];
    return RiskEventContribution(
      id: _requiredString(json, 'id'),
      kind: RiskEventKind.values.firstWhere(
        (value) => value.name == kindText,
        orElse: () =>
            throw FormatException('Unknown risk event kind: $kindText'),
      ),
      factorId: _requiredString(json, 'factorId'),
      message: _requiredString(json, 'message'),
      createdAt: _requiredDate(json, 'createdAt'),
      observedAt: _requiredDate(json, 'observedAt'),
      severity: severityText == null
          ? null
          : RiskSeverity.values.firstWhere(
              (value) => value.name == severityText,
              orElse: () => throw FormatException(
                'Unknown risk event severity: $severityText',
              ),
            ),
      source: _optionalString(json['source']),
      previousValue: _optionalDouble(json['previousValue']),
      currentValue: _optionalDouble(json['currentValue']),
      quality: json['quality'] == null
          ? null
          : _qualityFromJson(_requiredMap(json, 'quality')),
    );
  }
}

class RiskEvent {
  RiskEvent({
    required this.id,
    required this.episodeKey,
    required this.kind,
    required this.message,
    required this.createdAt,
    required this.observedAt,
    this.factorId,
    this.severity,
    this.source,
    this.previousValue,
    this.currentValue,
    this.policyVersion = 'risk.v1',
    this.quality,
    List<RiskEventContribution> contributions = const <RiskEventContribution>[],
  }) : contributions = List<RiskEventContribution>.unmodifiable(contributions);

  final String id;
  final String episodeKey;
  final RiskEventKind kind;
  final String message;
  final DateTime createdAt;
  final DateTime observedAt;
  final String? factorId;
  final RiskSeverity? severity;
  final String? source;
  final double? previousValue;
  final double? currentValue;
  final String policyVersion;
  final RiskQuality? quality;
  final List<RiskEventContribution> contributions;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'episodeKey': episodeKey,
    'kind': kind.name,
    'message': message,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'observedAt': observedAt.toUtc().toIso8601String(),
    'factorId': factorId,
    'severity': severity?.name,
    'source': source,
    'previousValue': previousValue,
    'currentValue': currentValue,
    'policyVersion': policyVersion,
    'quality': quality == null ? null : _qualityToJson(quality!),
    'contributions': contributions
        .map((contribution) => contribution.toJson())
        .toList(growable: false),
  };

  factory RiskEvent.fromJson(Map<String, dynamic> json) {
    final kindText = _requiredString(json, 'kind');
    final kind = RiskEventKind.values.firstWhere(
      (value) => value.name == kindText,
      orElse: () => throw FormatException('Unknown risk event kind: $kindText'),
    );
    final severityText = json['severity'];
    final severity = severityText == null
        ? null
        : RiskSeverity.values.firstWhere(
            (value) => value.name == severityText,
            orElse: () => throw FormatException(
              'Unknown risk event severity: $severityText',
            ),
          );
    final rawContributions = json['contributions'];
    final contributions = rawContributions == null
        ? <RiskEventContribution>[
            RiskEventContribution(
              id: _requiredString(json, 'id'),
              kind: kind,
              factorId: _optionalString(json['factorId']) ?? kind.name,
              message: _requiredString(json, 'message'),
              createdAt: _requiredDate(json, 'createdAt'),
              observedAt: _requiredDate(json, 'observedAt'),
              severity: severity,
              source: _optionalString(json['source']),
              previousValue: _optionalDouble(json['previousValue']),
              currentValue: _optionalDouble(json['currentValue']),
              quality: json['quality'] == null
                  ? null
                  : _qualityFromJson(_requiredMap(json, 'quality')),
            ),
          ]
        : rawContributions is List
        ? rawContributions
              .map(
                (item) =>
                    RiskEventContribution.fromJson(_map(item, 'contribution')),
              )
              .toList(growable: false)
        : (throw const FormatException('contributions must be an array'));
    return RiskEvent(
      id: _requiredString(json, 'id'),
      episodeKey: _requiredString(json, 'episodeKey'),
      kind: kind,
      message: _requiredString(json, 'message'),
      createdAt: _requiredDate(json, 'createdAt'),
      observedAt: _requiredDate(json, 'observedAt'),
      factorId: _optionalString(json['factorId']),
      severity: severity,
      source: _optionalString(json['source']),
      previousValue: _optionalDouble(json['previousValue']),
      currentValue: _optionalDouble(json['currentValue']),
      policyVersion: _requiredString(json, 'policyVersion'),
      quality: json['quality'] == null
          ? null
          : _qualityFromJson(_requiredMap(json, 'quality')),
      contributions: List<RiskEventContribution>.unmodifiable(contributions),
    );
  }
}

class RiskPendingImprovement {
  const RiskPendingImprovement({
    required this.component,
    required this.targetRank,
    required this.startedAt,
  });

  final String component;
  final int targetRank;
  final DateTime startedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'component': component,
    'targetRank': targetRank,
    'startedAt': startedAt.toUtc().toIso8601String(),
  };

  factory RiskPendingImprovement.fromJson(Map<String, dynamic> json) {
    final rank = json['targetRank'];
    if (rank is! int) throw const FormatException('targetRank must be integer');
    return RiskPendingImprovement(
      component: _requiredString(json, 'component'),
      targetRank: rank,
      startedAt: _requiredDate(json, 'startedAt'),
    );
  }
}

/// Persistent anti-spam state.  The maps are keyed by a distinct factor or
/// threshold identity so a new, more-severe boundary can notify immediately.
class RiskEventLatch {
  const RiskEventLatch({
    required this.episodeKey,
    this.initialized = false,
    this.lastObservedAt,
    this.lastSample,
    this.activeFactors = const <String>[],
    this.rearmSince = const <String, DateTime>{},
    this.emittedEventIds = const <String>[],
    this.pendingImprovements = const <String, RiskPendingImprovement>{},
    this.lastNotifiedTrueExit,
    this.lastNotifiedTrueExitAt,
  });

  final String episodeKey;
  final bool initialized;
  final DateTime? lastObservedAt;
  final RiskHistorySample? lastSample;
  final List<String> activeFactors;
  final Map<String, DateTime> rearmSince;
  final List<String> emittedEventIds;
  final Map<String, RiskPendingImprovement> pendingImprovements;
  final double? lastNotifiedTrueExit;
  final DateTime? lastNotifiedTrueExitAt;

  RiskEventLatch copyWith({
    bool? initialized,
    DateTime? lastObservedAt,
    RiskHistorySample? lastSample,
    List<String>? activeFactors,
    Map<String, DateTime>? rearmSince,
    List<String>? emittedEventIds,
    Map<String, RiskPendingImprovement>? pendingImprovements,
    double? lastNotifiedTrueExit,
    DateTime? lastNotifiedTrueExitAt,
    bool clearPendingImprovement = false,
    bool clearTrueExit = false,
  }) {
    return RiskEventLatch(
      episodeKey: episodeKey,
      initialized: initialized ?? this.initialized,
      lastObservedAt: lastObservedAt ?? this.lastObservedAt,
      lastSample: lastSample ?? this.lastSample,
      activeFactors: activeFactors ?? this.activeFactors,
      rearmSince: rearmSince ?? this.rearmSince,
      emittedEventIds: emittedEventIds ?? this.emittedEventIds,
      pendingImprovements: clearPendingImprovement
          ? const <String, RiskPendingImprovement>{}
          : pendingImprovements ?? this.pendingImprovements,
      lastNotifiedTrueExit: clearTrueExit
          ? null
          : lastNotifiedTrueExit ?? this.lastNotifiedTrueExit,
      lastNotifiedTrueExitAt: clearTrueExit
          ? null
          : lastNotifiedTrueExitAt ?? this.lastNotifiedTrueExitAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'episodeKey': episodeKey,
    'initialized': initialized,
    'lastObservedAt': lastObservedAt?.toUtc().toIso8601String(),
    'lastSample': lastSample?.toJson(),
    'activeFactors': activeFactors,
    'rearmSince': rearmSince.map(
      (key, value) => MapEntry(key, value.toUtc().toIso8601String()),
    ),
    'emittedEventIds': emittedEventIds,
    'pendingImprovements': pendingImprovements.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
    'lastNotifiedTrueExit': lastNotifiedTrueExit,
    'lastNotifiedTrueExitAt': lastNotifiedTrueExitAt?.toUtc().toIso8601String(),
  };

  factory RiskEventLatch.fromJson(Map<String, dynamic> json) {
    final active = json['activeFactors'];
    final emitted = json['emittedEventIds'];
    final rawRearm = json['rearmSince'];
    if (active is! List || active.any((item) => item is! String)) {
      throw const FormatException('activeFactors must be a string array');
    }
    if (emitted is! List || emitted.any((item) => item is! String)) {
      throw const FormatException('emittedEventIds must be a string array');
    }
    if (rawRearm is! Map) {
      throw const FormatException('rearmSince must be an object');
    }
    final initialized = json['initialized'];
    if (initialized is! bool) {
      throw const FormatException('initialized must be boolean');
    }
    final rearm = <String, DateTime>{};
    for (final entry in rawRearm.entries) {
      final value = DateTime.tryParse(entry.value.toString());
      if (value == null) throw const FormatException('Invalid rearm timestamp');
      rearm[entry.key.toString()] = value.toUtc();
    }
    final rawSample = json['lastSample'];
    final rawPending = json['pendingImprovements'];
    if (rawPending is! Map) {
      throw const FormatException('pendingImprovements must be an object');
    }
    final pending = <String, RiskPendingImprovement>{};
    for (final entry in rawPending.entries) {
      pending[entry.key.toString()] = RiskPendingImprovement.fromJson(
        _map(entry.value, 'pendingImprovement'),
      );
    }
    return RiskEventLatch(
      episodeKey: _requiredString(json, 'episodeKey'),
      initialized: initialized,
      lastObservedAt: _optionalDate(json['lastObservedAt']),
      lastSample: rawSample == null
          ? null
          : RiskHistorySample.fromJson(_map(rawSample, 'lastSample')),
      activeFactors: List<String>.unmodifiable(active.cast<String>()),
      rearmSince: Map<String, DateTime>.unmodifiable(rearm),
      emittedEventIds: List<String>.unmodifiable(emitted.cast<String>()),
      pendingImprovements: Map<String, RiskPendingImprovement>.unmodifiable(
        pending,
      ),
      lastNotifiedTrueExit: _optionalDouble(json['lastNotifiedTrueExit']),
      lastNotifiedTrueExitAt: _optionalDate(json['lastNotifiedTrueExitAt']),
    );
  }
}

typedef RiskEventLatches = RiskEventLatch;

class RiskEventReduction {
  const RiskEventReduction({required this.events, required this.latches});

  final List<RiskEvent> events;
  final RiskEventLatch latches;

  bool get hasEvents => events.isNotEmpty;
}

typedef RiskEventClock = DateTime Function();

/// Pure event reducer.  It never writes storage, calls a platform API, or
/// delivers notifications; the owner persists [latches] before delivery.
class RiskEventReducer {
  const RiskEventReducer({this.clock});

  final RiskEventClock? clock;

  RiskEventReduction reduce(
    RiskHistorySample? previous,
    RiskHistorySample current,
    RiskEventLatch latches,
    RiskPolicy policy, {
    RiskPlanEvaluation? previousPlan,
    RiskPlanEvaluation? currentPlan,
    DateTime? now,
    bool reconnected = false,
  }) {
    policy.requireValid();
    final reducedAt = (now ?? clock?.call() ?? DateTime.now().toUtc()).toUtc();
    if (current.episodeKey != latches.episodeKey || !current.isFresh) {
      return RiskEventReduction(events: const <RiskEvent>[], latches: latches);
    }
    final prior = previous ?? latches.lastSample;
    if (prior != null && prior.episodeKey != current.episodeKey) {
      return RiskEventReduction(events: const <RiskEvent>[], latches: latches);
    }
    if (latches.lastObservedAt != null &&
        !current.observedAt.isAfter(latches.lastObservedAt!)) {
      return RiskEventReduction(events: const <RiskEvent>[], latches: latches);
    }

    final updated = <String>{...latches.activeFactors};
    final rearm = <String, DateTime>{...latches.rearmSince};
    final emitted = <String>[...latches.emittedEventIds];
    final contributions = <RiskEventContribution>[];
    final pending = <String, RiskPendingImprovement>{
      ...latches.pendingImprovements,
    };
    var lastTrueExit = latches.lastNotifiedTrueExit;
    var lastTrueExitAt = latches.lastNotifiedTrueExitAt;

    void addEvent({
      required RiskEventKind kind,
      required String factor,
      required String message,
      RiskSeverity? severity,
      double? previousValue,
      double? currentValue,
      String? source,
    }) {
      final id = _eventId(
        current,
        kind,
        factor,
        currentValue?.toString() ?? message,
      );
      if (emitted.contains(id)) return;
      contributions.add(
        RiskEventContribution(
          id: id,
          kind: kind,
          factorId: factor,
          message: message,
          createdAt: reducedAt,
          observedAt: current.observedAt,
          severity: severity,
          source: source ?? current.source,
          previousValue: previousValue,
          currentValue: currentValue,
          quality: current.quality,
        ),
      );
      emitted.add(id);
    }

    if (prior == null || !latches.initialized) {
      _seedActiveFactors(updated, current, currentPlan);
      final seeded = RiskEventLatch(
        episodeKey: latches.episodeKey,
        initialized: true,
        lastObservedAt: current.observedAt,
        lastSample: current,
        activeFactors: List.unmodifiable(updated),
        rearmSince: Map.unmodifiable(rearm),
        emittedEventIds: List.unmodifiable(_trimIds(emitted)),
        pendingImprovements: Map.unmodifiable(pending),
        lastNotifiedTrueExit: current.trueExitVerified
            ? current.trueExit
            : null,
        lastNotifiedTrueExitAt:
            current.trueExitVerified && current.trueExit != null
            ? current.observedAt
            : null,
      );
      return RiskEventReduction(events: const <RiskEvent>[], latches: seeded);
    }

    // A policy edit changes interpretation and is persisted as history by the
    // owner. It is not a market crossing or an alert by itself.
    final policyChanged = prior.policyVersion != current.policyVersion;
    final gap = current.observedAt.difference(prior.observedAt);
    final reconnect = reconnected || gap > const Duration(minutes: 5);
    final activeRuleIds = _activeIds(currentPlan);
    final priorActiveRuleIds = _activeIds(previousPlan);
    final rulesChanged = !_sameSet(activeRuleIds, priorActiveRuleIds);
    final editedPlanKeys = _editedPlanKeys(previousPlan, currentPlan);
    final stateChanged =
        prior.overallState != current.overallState ||
        prior.positionState != current.positionState ||
        prior.marketState != current.marketState ||
        prior.recoveryState != current.recoveryState;

    final riskChangedDuringGap =
        stateChanged ||
        rulesChanged ||
        prior.buffer != current.buffer ||
        prior.effectiveLeverage != current.effectiveLeverage ||
        prior.marginRatio != current.marginRatio ||
        prior.activeFactorIds.toSet().length !=
            current.activeFactorIds.toSet().length ||
        !_sameSet(
          prior.activeFactorIds.toSet(),
          current.activeFactorIds.toSet(),
        );

    if (policyChanged || reconnect) {
      // A gap or policy edit invalidates every in-flight improvement
      // confirmation; it cannot be carried across an unobserved interval.
      pending.clear();
    }
    if (policyChanged) {
      // A policy edit invalidates the previous verified-cost comparison too;
      // the next coherent observation becomes the new materiality baseline.
      lastTrueExit = null;
      lastTrueExitAt = null;
    }

    if (editedPlanKeys.isNotEmpty) {
      // A definition edit changes the user's configuration, not the market.
      // Reseed only the edited latches so the same live value is not reported
      // as a new crossing under the replacement definition.
      _reseedEditedPlanLatches(
        currentPlan: currentPlan,
        editedKeys: editedPlanKeys,
        updated: updated,
        rearm: rearm,
      );
      addEvent(
        kind: RiskEventKind.configurationChange,
        factor: 'plan-configuration',
        message: 'Action plan configuration changed',
      );
    }

    if (!policyChanged && reconnect && riskChangedDuringGap) {
      addEvent(
        kind: RiskEventKind.reconnect,
        factor: 'reconnect',
        message: 'Risk changed since last observation',
        severity: current.overallState,
      );
    } else if (!policyChanged && !reconnect) {
      // Each component has its own state transition semantics. A worsening
      // state is immediate; an improvement is only emitted after the next
      // fresh complete comparable sample confirms the same or a further
      // improvement at least 30s later. Unknown transitions clear that
      // component's pending proof.
      void reduceStateChange(
        String factor,
        String label,
        RiskSeverity? priorState,
        RiskSeverity? currentState,
      ) {
        final existing = pending[factor];
        if (priorState == null || currentState == null) {
          pending.remove(factor);
          return;
        }
        final priorRank = _rank(priorState);
        final currentRank = _rank(currentState);
        final stateFactor = '$factor-state';
        if (currentRank > priorRank) {
          pending.remove(factor);
          addEvent(
            kind: RiskEventKind.stateChange,
            factor: '$stateFactor-$currentRank',
            message:
                '$label risk worsened from ${priorState.name} to ${currentState.name}',
            severity: currentState,
            previousValue: priorRank.toDouble(),
            currentValue: currentRank.toDouble(),
          );
          return;
        }

        final completeComparable =
            current.isComparable &&
            current.quality.status == RiskQualityStatus.complete;
        if (currentRank < priorRank) {
          if (!completeComparable) {
            pending.remove(factor);
            return;
          }
          if (existing == null) {
            pending[factor] = RiskPendingImprovement(
              component: factor,
              targetRank: currentRank,
              startedAt: current.observedAt,
            );
          } else if (current.observedAt.difference(existing.startedAt) >=
                  const Duration(seconds: 30) &&
              currentRank <= existing.targetRank) {
            addEvent(
              kind: RiskEventKind.stateChange,
              factor: '$stateFactor-improvement',
              message:
                  '$label risk improvement confirmed from ${priorState.name} to ${currentState.name}',
              severity: currentState,
              previousValue: priorRank.toDouble(),
              currentValue: currentRank.toDouble(),
            );
            pending.remove(factor);
          } else if (currentRank > existing.targetRank) {
            pending[factor] = RiskPendingImprovement(
              component: factor,
              targetRank: currentRank,
              startedAt: current.observedAt,
            );
          }
          return;
        }

        if (existing != null) {
          if (!completeComparable) {
            pending.remove(factor);
          } else if (current.observedAt.difference(existing.startedAt) >=
                  const Duration(seconds: 30) &&
              currentRank <= existing.targetRank) {
            addEvent(
              kind: RiskEventKind.stateChange,
              factor: '$stateFactor-improvement',
              message: '$label risk improvement confirmed',
              severity: currentState,
              previousValue: priorRank.toDouble(),
              currentValue: currentRank.toDouble(),
            );
            pending.remove(factor);
          } else if (currentRank > existing.targetRank) {
            pending.remove(factor);
          }
        }
      }

      reduceStateChange(
        'overall',
        'Overall',
        prior.overallState,
        current.overallState,
      );
      reduceStateChange(
        'position',
        'Position',
        prior.positionState,
        current.positionState,
      );
      reduceStateChange(
        'market',
        'Market',
        prior.marketState,
        current.marketState,
      );
      reduceStateChange(
        'recovery',
        'Recovery',
        prior.recoveryState,
        current.recoveryState,
      );

      _reduceThreshold(
        keyPrefix: 'buffer',
        priorValue: prior.buffer,
        currentValue: current.buffer,
        boundaries: <double>[
          policy.bufferCritical,
          policy.bufferHigh,
          policy.bufferWatch,
        ],
        worse: (value, boundary) => boundary == policy.bufferWatch
            ? value <= boundary
            : value < boundary,
        rearmSafe: (value, boundary) => value >= boundary + 0.01,
        kind: RiskEventKind.bufferBoundary,
        unit: 'buffer',
        current: current,
        updated: updated,
        rearm: rearm,
        addEvent: addEvent,
        now: current.observedAt,
      );
      _reduceThreshold(
        keyPrefix: 'leverage',
        priorValue: prior.effectiveLeverage,
        currentValue: current.effectiveLeverage,
        boundaries: <double>[
          policy.leverageWatch,
          policy.leverageHigh,
          policy.leverageCritical,
        ],
        worse: (value, boundary) => value >= boundary,
        rearmSafe: (value, boundary) => value <= boundary - 0.2,
        kind: RiskEventKind.leverageBoundary,
        unit: 'effective leverage',
        current: current,
        updated: updated,
        rearm: rearm,
        addEvent: addEvent,
        now: current.observedAt,
      );
      // A high ratio is safer, hence the inverse comparison for a boundary.
      _reduceThreshold(
        keyPrefix: 'margin',
        priorValue: prior.marginRatio,
        currentValue: current.marginRatio,
        boundaries: <double>[
          policy.marginRatioCritical,
          policy.marginRatioHigh,
          policy.marginRatioWatch,
        ],
        worse: (value, boundary) => value <= boundary,
        rearmSafe: (value, boundary) => value >= boundary + 0.10,
        kind: RiskEventKind.marginBoundary,
        unit: 'margin ratio',
        current: current,
        updated: updated,
        rearm: rearm,
        addEvent: addEvent,
        now: current.observedAt,
      );
      _reduceFactors(prior, current, updated, addEvent);
      _reducePlanEntries(
        priorPlan: previousPlan,
        currentPlan: currentPlan,
        updated: updated,
        rearm: rearm,
        now: current.observedAt,
        editedKeys: editedPlanKeys,
        addEvent: addEvent,
      );
    }

    // Verified True Exit materiality remains valid across a reconnect because
    // it compares two coherent cost observations, while market crossings are
    // intentionally suppressed across the unobserved gap above.
    if (!policyChanged) {
      final currentT = current.trueExit;
      final priorT = lastTrueExit;
      final sameInterestIdentity =
          _samePosition(prior, current) &&
          _sameRequiredValue(prior.entryPrice, current.entryPrice) &&
          _sameRequiredValue(prior.entryFeeRate, current.entryFeeRate) &&
          _sameRequiredValue(prior.exitFeeRate, current.exitFeeRate) &&
          prior.trueExitVerified &&
          current.trueExitVerified;
      if (currentT != null &&
          currentT.isFinite &&
          currentT > 0 &&
          priorT != null &&
          priorT > 0 &&
          sameInterestIdentity &&
          currentT >= priorT * 1.0025 &&
          (lastTrueExitAt == null ||
              current.observedAt.difference(lastTrueExitAt) >=
                  const Duration(hours: 24))) {
        addEvent(
          kind: RiskEventKind.interestChange,
          factor: 'true-exit-interest',
          message: 'Verified True Exit increased by at least 0.25%',
          currentValue: currentT,
        );
        lastTrueExit = currentT;
        lastTrueExitAt = current.observedAt;
      } else if (lastTrueExit == null &&
          currentT != null &&
          currentT > 0 &&
          current.trueExitVerified) {
        lastTrueExit = currentT;
        lastTrueExitAt = current.observedAt;
      }
    }

    // Clear active market factors on a fresh observation. Threshold latches
    // have their explicit safe-side hysteresis above.
    _clearInactiveFactors(current, updated, rearm);
    final next = RiskEventLatch(
      episodeKey: latches.episodeKey,
      initialized: true,
      lastObservedAt: current.observedAt,
      lastSample: current,
      activeFactors: List.unmodifiable(updated),
      rearmSince: Map.unmodifiable(rearm),
      emittedEventIds: List.unmodifiable(_trimIds(emitted)),
      pendingImprovements: Map.unmodifiable(pending),
      lastNotifiedTrueExit: lastTrueExit,
      lastNotifiedTrueExitAt: lastTrueExitAt,
    );
    return RiskEventReduction(
      events: _aggregateEvents(contributions, current),
      latches: next,
    );
  }
}

int _rank(RiskSeverity? state) => state?.rank ?? -1;

bool _samePosition(RiskHistorySample first, RiskHistorySample second) {
  bool same(double? left, double? right) {
    if (left == null || right == null || !left.isFinite || !right.isFinite) {
      return false;
    }
    final magnitude = left.abs() > right.abs() ? left.abs() : right.abs();
    final denominator = magnitude > 1e-12 ? magnitude : 1;
    return (left - right).abs() / denominator <= 0.001;
  }

  return same(first.quantity, second.quantity) &&
      same(first.margin, second.margin) &&
      same(first.debt, second.debt);
}

bool _sameRequiredValue(double? left, double? right) {
  if (left == null || right == null || !left.isFinite || !right.isFinite) {
    return false;
  }
  final magnitude = left.abs() > right.abs() ? left.abs() : right.abs();
  final denominator = magnitude > 1e-12 ? magnitude : 1;
  return (left - right).abs() / denominator <= 1e-9;
}

List<RiskEvent> _aggregateEvents(
  List<RiskEventContribution> contributions,
  RiskHistorySample current,
) {
  if (contributions.isEmpty) return const <RiskEvent>[];
  final first = contributions.first;
  final kind = contributions.length == 1
      ? first.kind
      : RiskEventKind.stateChange;
  final factor = contributions.length == 1 ? first.factorId : 'observation';
  final message = contributions.length == 1
      ? first.message
      : '${contributions.length} risk changes observed';
  final id = contributions.length == 1
      ? first.id
      : '${current.episodeKey}|observation|${current.observedAt.toUtc().toIso8601String()}|${contributions.map((item) => item.id).join('|')}';
  return <RiskEvent>[
    RiskEvent(
      id: id,
      episodeKey: current.episodeKey,
      kind: kind,
      message: message,
      createdAt: first.createdAt,
      observedAt: current.observedAt,
      factorId: factor,
      severity: first.severity,
      source: first.source ?? current.source,
      previousValue: contributions.length == 1 ? first.previousValue : null,
      currentValue: contributions.length == 1 ? first.currentValue : null,
      policyVersion: current.policyVersion,
      quality: current.quality,
      contributions: List<RiskEventContribution>.unmodifiable(contributions),
    ),
  ];
}

Set<String> _activeIds(RiskPlanEvaluation? evaluation) => evaluation == null
    ? const <String>{}
    : <String>{
        ...evaluation.rules
            .where((item) => item.active)
            .map((item) => 'rule:${item.rule.id}'),
        ...evaluation.zones
            .where((item) => item.active)
            .map((item) => 'zone:${item.zone.id}'),
      };

Set<String> _editedPlanKeys(
  RiskPlanEvaluation? previous,
  RiskPlanEvaluation? current,
) {
  final edited = <String>{};
  final previousRules = <String, RiskRule>{
    for (final item in previous?.rules ?? const <RiskRuleEvaluation>[])
      item.rule.id: item.rule,
  };
  final currentRules = <String, RiskRule>{
    for (final item in current?.rules ?? const <RiskRuleEvaluation>[])
      item.rule.id: item.rule,
  };
  for (final id in <String>{...previousRules.keys, ...currentRules.keys}) {
    final before = previousRules[id];
    final after = currentRules[id];
    if (before == null ||
        after == null ||
        !_sameRuleDefinition(before, after)) {
      edited.add('rule:$id');
    }
  }

  final previousZones = <String, RiskZone>{
    for (final item in previous?.zones ?? const <RiskZoneEvaluation>[])
      item.zone.id: item.zone,
  };
  final currentZones = <String, RiskZone>{
    for (final item in current?.zones ?? const <RiskZoneEvaluation>[])
      item.zone.id: item.zone,
  };
  for (final id in <String>{...previousZones.keys, ...currentZones.keys}) {
    final before = previousZones[id];
    final after = currentZones[id];
    if (before == null ||
        after == null ||
        !_sameZoneDefinition(before, after)) {
      edited.add('zone:$id');
    }
  }
  return edited;
}

bool _sameRuleDefinition(RiskRule first, RiskRule second) =>
    first.id == second.id &&
    first.episodeKey == second.episodeKey &&
    first.enabled == second.enabled &&
    first.metric == second.metric &&
    first.comparison == second.comparison &&
    first.threshold == second.threshold &&
    first.upperThreshold == second.upperThreshold &&
    first.title == second.title &&
    first.label == second.label &&
    first.note == second.note &&
    first.createdAt.isAtSameMomentAs(second.createdAt) &&
    first.updatedAt.isAtSameMomentAs(second.updatedAt);

bool _sameZoneDefinition(RiskZone first, RiskZone second) =>
    first.id == second.id &&
    first.episodeKey == second.episodeKey &&
    first.title == second.title &&
    first.lowerPrice == second.lowerPrice &&
    first.upperPrice == second.upperPrice &&
    first.enabled == second.enabled &&
    first.note == second.note &&
    first.createdAt.isAtSameMomentAs(second.createdAt) &&
    first.updatedAt.isAtSameMomentAs(second.updatedAt);

void _reseedEditedPlanLatches({
  required RiskPlanEvaluation? currentPlan,
  required Set<String> editedKeys,
  required Set<String> updated,
  required Map<String, DateTime> rearm,
}) {
  final currentRules = <String, RiskRuleEvaluation>{
    for (final item in currentPlan?.rules ?? const <RiskRuleEvaluation>[])
      'rule:${item.rule.id}': item,
  };
  final currentZones = <String, RiskZoneEvaluation>{
    for (final item in currentPlan?.zones ?? const <RiskZoneEvaluation>[])
      'zone:${item.zone.id}': item,
  };
  for (final key in editedKeys) {
    final rule = currentRules[key];
    final zone = currentZones[key];
    rearm.remove(key);
    if ((rule?.active ?? false) || (zone?.active ?? false)) {
      updated.add(key);
    } else {
      updated.remove(key);
    }
  }
}

bool _sameSet(Set<String> first, Set<String> second) {
  if (first.length != second.length) return false;
  return first.containsAll(second);
}

void _reduceThreshold({
  required String keyPrefix,
  required double? priorValue,
  required double? currentValue,
  required List<double> boundaries,
  required bool Function(double value, double boundary) worse,
  required bool Function(double value, double boundary) rearmSafe,
  required RiskEventKind kind,
  required String unit,
  required RiskHistorySample current,
  required Set<String> updated,
  required Map<String, DateTime> rearm,
  required void Function({
    required RiskEventKind kind,
    required String factor,
    required String message,
    RiskSeverity? severity,
    double? previousValue,
    double? currentValue,
    String? source,
  })
  addEvent,
  required DateTime now,
}) {
  if (boundaries.isEmpty ||
      priorValue == null ||
      currentValue == null ||
      !priorValue.isFinite ||
      !currentValue.isFinite) {
    return;
  }
  String? selectedKey;
  double? selectedBoundary;
  for (final boundary in boundaries) {
    if (!boundary.isFinite) continue;
    final key = '$keyPrefix-${boundary.toString()}';
    final priorBad = worse(priorValue, boundary);
    final currentBad = worse(currentValue, boundary);
    if (currentBad) {
      rearm.remove(key);
      if (!priorBad && !updated.contains(key)) {
        updated.add(key);
        final previousBoundary = selectedBoundary;
        final isMoreSevere =
            previousBoundary == null ||
            (keyPrefix == 'leverage'
                ? boundary > previousBoundary
                : boundary < previousBoundary);
        if (isMoreSevere) {
          selectedKey = key;
          selectedBoundary = boundary;
        }
      }
    } else if (updated.contains(key)) {
      if (!rearmSafe(currentValue, boundary)) {
        // Returning only part-way into the safe side must restart the
        // confirmation window rather than preserve an earlier safe sample.
        rearm.remove(key);
      } else {
        final started = rearm[key];
        if (started == null) {
          rearm[key] = now;
        } else if (now.difference(started) >= const Duration(seconds: 30)) {
          updated.remove(key);
          rearm.remove(key);
        }
      }
    }
  }
  if (selectedKey != null) {
    addEvent(
      kind: kind,
      factor: selectedKey,
      message: '$unit crossed ${selectedBoundary.toString()}',
      currentValue: currentValue,
      previousValue: priorValue,
      severity: current.overallState,
    );
  }
}

void _reduceFactors(
  RiskHistorySample prior,
  RiskHistorySample current,
  Set<String> updated,
  void Function({
    required RiskEventKind kind,
    required String factor,
    required String message,
    RiskSeverity? severity,
    double? previousValue,
    double? currentValue,
    String? source,
  })
  addEvent,
) {
  final old = prior.activeFactorIds.toSet();
  final next = current.activeFactorIds.toSet();
  for (final factor in next) {
    if (!old.contains(factor) && !updated.contains('factor:$factor')) {
      updated.add('factor:$factor');
      addEvent(
        kind: RiskEventKind.factorEntry,
        factor: factor,
        message: 'New confirmed risk factor: $factor',
        severity: current.overallState,
      );
    }
  }
  for (final factor in old.difference(next)) {
    updated.remove('factor:$factor');
  }
}

void _reducePlanEntries({
  required RiskPlanEvaluation? priorPlan,
  required RiskPlanEvaluation? currentPlan,
  required Set<String> updated,
  required Map<String, DateTime> rearm,
  required DateTime now,
  required Set<String> editedKeys,
  required void Function({
    required RiskEventKind kind,
    required String factor,
    required String message,
    RiskSeverity? severity,
    double? previousValue,
    double? currentValue,
    String? source,
  })
  addEvent,
}) {
  if (currentPlan == null) {
    updated.removeWhere(
      (key) => key.startsWith('rule:') || key.startsWith('zone:'),
    );
    rearm.removeWhere(
      (key, _) => key.startsWith('rule:') || key.startsWith('zone:'),
    );
    return;
  }
  final currentRuleKeys = currentPlan.rules
      .map((item) => 'rule:${item.rule.id}')
      .toSet();
  final currentZoneKeys = currentPlan.zones
      .map((item) => 'zone:${item.zone.id}')
      .toSet();
  updated.removeWhere(
    (key) =>
        (key.startsWith('rule:') && !currentRuleKeys.contains(key)) ||
        (key.startsWith('zone:') && !currentZoneKeys.contains(key)),
  );
  rearm.removeWhere(
    (key, _) =>
        (key.startsWith('rule:') && !currentRuleKeys.contains(key)) ||
        (key.startsWith('zone:') && !currentZoneKeys.contains(key)),
  );
  final oldRules = <String, RiskRuleState>{
    for (final item in priorPlan?.rules ?? const <RiskRuleEvaluation>[])
      item.rule.id: item.state,
  };
  for (final item in currentPlan.rules) {
    final key = 'rule:${item.rule.id}';
    final edited = editedKeys.contains(key);
    if (item.state == RiskRuleState.active) {
      rearm.remove(key);
      if (!edited &&
          oldRules[item.rule.id] == RiskRuleState.inactive &&
          !updated.contains(key)) {
        updated.add(key);
        addEvent(
          kind: RiskEventKind.ruleEntry,
          factor: item.rule.id,
          message: 'Action rule entered: ${item.rule.displayLabel}',
        );
      }
    } else if (item.state == RiskRuleState.inactive && updated.contains(key)) {
      if (_ruleIsSafelyOutside(item)) {
        _advanceRearm(key, updated, rearm, now);
      } else {
        rearm.remove(key);
      }
    } else {
      rearm.remove(key);
    }
  }
  final oldZones = <String, RiskRuleState>{
    for (final item in priorPlan?.zones ?? const <RiskZoneEvaluation>[])
      item.zone.id: item.state,
  };
  for (final item in currentPlan.zones) {
    final key = 'zone:${item.zone.id}';
    final edited = editedKeys.contains(key);
    if (item.state == RiskRuleState.active) {
      rearm.remove(key);
      if (!edited &&
          oldZones[item.zone.id] == RiskRuleState.inactive &&
          !updated.contains(key)) {
        updated.add(key);
        addEvent(
          kind: RiskEventKind.zoneEntry,
          factor: item.zone.id,
          message: 'Price zone entered: ${item.zone.title}',
        );
      }
    } else if (item.state == RiskRuleState.inactive && updated.contains(key)) {
      if (_zoneIsSafelyOutside(item)) {
        _advanceRearm(key, updated, rearm, now);
      } else {
        rearm.remove(key);
      }
    } else {
      rearm.remove(key);
    }
  }
}

void _advanceRearm(
  String key,
  Set<String> updated,
  Map<String, DateTime> rearm,
  DateTime now,
) {
  final started = rearm[key];
  if (started == null) {
    rearm[key] = now;
  } else if (now.difference(started) >= const Duration(seconds: 30)) {
    updated.remove(key);
    rearm.remove(key);
  }
}

bool _ruleIsSafelyOutside(RiskRuleEvaluation item) {
  final rule = item.rule;
  final value = item.value;
  if (value == null || !value.isFinite) return false;
  double margin(double boundary) {
    if (rule.metric == RiskPlanMetric.buffer) return 0.01;
    if (rule.metric == RiskPlanMetric.effectiveLeverage) return 0.2;
    if (rule.metric == RiskPlanMetric.totalDebt ||
        rule.metric == RiskPlanMetric.dailyHoldingCost) {
      return boundary.abs() * 0.01;
    }
    return boundary.abs() * 0.005;
  }

  final dynamicReference = item.referenceValue;
  if (rule.metric == RiskPlanMetric.priceVsTrueExit) {
    if (dynamicReference == null || !dynamicReference.isFinite) return false;
    final difference = dynamicReference.abs() * 0.005;
    return rule.comparison == RiskPlanComparison.lessThan
        ? _atLeast(value, dynamicReference + difference)
        : _atMost(value, dynamicReference - difference);
  }
  final lower = rule.threshold;
  if (lower == null || !lower.isFinite) return false;
  final lowerMargin = margin(lower);
  switch (rule.comparison) {
    case RiskPlanComparison.lessThan:
    case RiskPlanComparison.lessThanOrEqual:
      return _atLeast(value, lower + lowerMargin);
    case RiskPlanComparison.greaterThan:
    case RiskPlanComparison.greaterThanOrEqual:
      return _atMost(value, lower - lowerMargin);
    case RiskPlanComparison.betweenInclusive:
      final upper = rule.upperThreshold;
      if (upper == null || !upper.isFinite) return false;
      if (value < lower) {
        return _atLeast(lower - value, lowerMargin);
      }
      if (value > upper) {
        return _atLeast(value - upper, margin(upper));
      }
      return false;
  }
}

bool _zoneIsSafelyOutside(RiskZoneEvaluation item) {
  final mark = item.markPrice;
  if (mark == null || !mark.isFinite || mark <= 0) return false;
  final zone = item.zone;
  if (mark < zone.lowerPrice) {
    return _atLeast((zone.lowerPrice - mark) / zone.lowerPrice, 0.005);
  }
  if (mark > zone.upperPrice) {
    return _atLeast((mark - zone.upperPrice) / zone.upperPrice, 0.005);
  }
  return false;
}

bool _atLeast(double value, double boundary) =>
    value + _numericTolerance(boundary) >= boundary;

bool _atMost(double value, double boundary) =>
    value - _numericTolerance(boundary) <= boundary;

double _numericTolerance(double value) =>
    1e-12 * (value.abs() > 1 ? value.abs() : 1);

void _seedActiveFactors(
  Set<String> target,
  RiskHistorySample current,
  RiskPlanEvaluation? plan,
) {
  for (final factor in current.activeFactorIds) {
    target.add('factor:$factor');
  }
  for (final rule in plan?.rules ?? const <RiskRuleEvaluation>[]) {
    if (rule.active) target.add('rule:${rule.rule.id}');
  }
  for (final zone in plan?.zones ?? const <RiskZoneEvaluation>[]) {
    if (zone.active) target.add('zone:${zone.zone.id}');
  }
}

void _clearInactiveFactors(
  RiskHistorySample current,
  Set<String> updated,
  Map<String, DateTime> rearm,
) {
  final currentFactors = current.activeFactorIds
      .map((factor) => 'factor:$factor')
      .toSet();
  for (final key in List<String>.from(updated)) {
    if (key.startsWith('factor:') && !currentFactors.contains(key)) {
      updated.remove(key);
    }
    if (!key.startsWith('buffer-') &&
        !key.startsWith('leverage-') &&
        !key.startsWith('margin-') &&
        !key.startsWith('rule:') &&
        !key.startsWith('zone:')) {
      rearm.remove(key);
    }
  }
}

String _eventId(
  RiskHistorySample current,
  RiskEventKind kind,
  String factor,
  String discriminator,
) =>
    '${current.episodeKey}|${kind.name}|$factor|${current.observedAt.toUtc().toIso8601String()}|$discriminator';

List<String> _trimIds(List<String> ids) {
  if (ids.length <= 2000) return ids;
  return ids.sublist(ids.length - 2000);
}

Map<String, dynamic> _qualityToJson(RiskQuality quality) => <String, dynamic>{
  'status': quality.status.name,
  'source': quality.source,
  'reason': quality.reason,
  'observedAt': quality.observedAt?.toUtc().toIso8601String(),
  'sourceAt': quality.sourceAt?.toUtc().toIso8601String(),
};

RiskQuality _qualityFromJson(Map<String, dynamic> json) {
  final status = RiskQualityStatus.values.firstWhere(
    (value) => value.name == json['status'],
    orElse: () => throw const FormatException('Unknown quality status'),
  );
  return RiskQuality(
    status: status,
    source: _optionalString(json['source']),
    reason: _optionalString(json['reason']),
    observedAt: _optionalDate(json['observedAt']),
    sourceAt: _optionalDate(json['sourceAt']),
  );
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string');
  }
  return value;
}

String? _optionalString(Object? value) => value is String ? value : null;

DateTime _requiredDate(Map<String, dynamic> json, String key) {
  final value = _optionalDate(json[key]);
  if (value == null) throw FormatException('$key must be an ISO timestamp');
  return value;
}

DateTime? _optionalDate(Object? value) {
  if (value == null) return null;
  if (value is! String) throw const FormatException('Invalid timestamp');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw const FormatException('Invalid timestamp');
  return parsed.toUtc();
}

double? _optionalDouble(Object? value) {
  if (value == null) return null;
  if (value is! num || !value.toDouble().isFinite) {
    throw const FormatException('Expected finite number');
  }
  return value.toDouble();
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! Map) throw FormatException('$key must be an object');
  return value.map<String, dynamic>(
    (itemKey, itemValue) => MapEntry(itemKey.toString(), itemValue),
  );
}

Map<String, dynamic> _map(Object? value, String key) {
  if (value is! Map) throw FormatException('$key must be an object');
  return value.map<String, dynamic>(
    (itemKey, itemValue) => MapEntry(itemKey.toString(), itemValue),
  );
}
