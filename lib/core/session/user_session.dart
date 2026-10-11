import 'dart:async';

import 'package:flutter/foundation.dart';

/// Server-issued identity and authority held only in process memory.
@immutable
class UserSession {
  const UserSession({
    required this.userId,
    required this.username,
    required this.sessionId,
    required this.mode,
    required this.expiresAt,
    this.stepUpUntil,
    this.bearerToken,
    this.csrfToken,
  });

  final String userId;
  final String username;
  final String sessionId;
  final String mode;
  final DateTime expiresAt;
  final DateTime? stepUpUntil;

  /// Native-only opaque session token. Web sessions use the server cookie.
  final String? bearerToken;

  /// Cookie transport mutation proof, kept in memory only.
  final String? csrfToken;

  bool get isActive => DateTime.now().isBefore(expiresAt);
  bool get canReadPrivate => mode == 'ordinary' && isActive;
  bool get canTrade =>
      canReadPrivate &&
      stepUpUntil != null &&
      DateTime.now().isBefore(stepUpUntil!);

  UserSession withStepUp(DateTime until) => UserSession(
    userId: userId,
    username: username,
    sessionId: sessionId,
    mode: mode,
    expiresAt: expiresAt,
    stepUpUntil: until,
    bearerToken: bearerToken,
    csrfToken: csrfToken,
  );

  bool sameIdentity(UserSession other) =>
      userId == other.userId &&
      sessionId == other.sessionId &&
      expiresAt == other.expiresAt;
}

/// Synchronous session generation fence shared by private request consumers.
class UserSessionStore extends ChangeNotifier {
  UserSession? _current;
  Timer? _expiryTimer;
  int _generation = 0;
  bool _disposed = false;

  UserSessionStore({UserSession? initialSession}) {
    update(initialSession);
  }

  int get generation => _generation;
  UserSession? get current =>
      !_disposed && (_current?.isActive ?? false) ? _current : null;

  void update(UserSession? next) {
    if (_disposed) return;
    final active = next != null && next.isActive ? next : null;
    if (_sameSession(_current, active)) return;
    _expiryTimer?.cancel();
    _current = active;
    _generation++;
    if (active != null) _scheduleExpiry(active, _generation);
    notifyListeners();
  }

  bool matches(int generation, UserSession expected) {
    final current = _current;
    return !_disposed &&
        generation == _generation &&
        current != null &&
        current.isActive &&
        current.sameIdentity(expected) &&
        current.bearerToken == expected.bearerToken;
  }

  /// Checks whether the same login lifetime still owns work already sent.
  /// Unlike [matches], this allows a same-session step-up refresh to advance
  /// the store generation while fencing logout and subsequent logins.
  bool hasSameOwner(UserSession expected) {
    final current = _current;
    return !_disposed &&
        current != null &&
        current.isActive &&
        current.sameIdentity(expected) &&
        current.bearerToken == expected.bearerToken;
  }

  void expireIfNeeded() {
    final session = _current;
    if (session != null && !session.isActive) update(null);
  }

  void _scheduleExpiry(UserSession session, int generation) {
    final remaining = session.expiresAt.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      update(null);
      return;
    }
    _expiryTimer = Timer(remaining, () {
      if (_generation != generation || !_sameSession(_current, session)) return;
      if (session.isActive) {
        _scheduleExpiry(session, generation);
      } else {
        update(null);
      }
    });
  }

  bool _sameSession(UserSession? left, UserSession? right) {
    if (identical(left, right)) return true;
    if (left == null || right == null) return false;
    return left.sameIdentity(right) &&
        left.mode == right.mode &&
        left.stepUpUntil == right.stepUpUntil &&
        left.bearerToken == right.bearerToken &&
        left.csrfToken == right.csrfToken;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _current = null;
    _generation++;
    _disposed = true;
    super.dispose();
  }
}
