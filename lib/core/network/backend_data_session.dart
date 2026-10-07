import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/orders/data/trade_api_client.dart';

/// In-memory session identity shared by foreground data clients and native
/// successors. It deliberately does not persist or log the bearer token.
class BackendDataSession extends ChangeNotifier {
  BackendDataSession({TradeSession? initialSession}) {
    update(initialSession);
  }

  final StreamController<void> _changes = StreamController<void>.broadcast(
    sync: true,
  );
  TradeSession? _session;
  Timer? _expiryTimer;
  int _generation = 0;
  bool _disposed = false;

  int get generation => _generation;

  /// Returns the current session only while it remains active.
  TradeSession? get current {
    if (_disposed) return null;
    final session = _session;
    return session != null && session.isActive ? session : null;
  }

  /// Emits synchronously after a semantic session change.
  Stream<void> get changes => _changes.stream;

  void update(TradeSession? next) {
    if (_disposed) return;
    final active = next != null && next.isActive ? next : null;
    if (_sameSession(_session, active)) return;

    _expiryTimer?.cancel();
    _expiryTimer = null;
    _session = active;
    _generation++;
    if (active != null) _scheduleExpiry(active, _generation);
    notifyListeners();
    _changes.add(null);
  }

  /// Clears a session whose deadline elapsed before its timer callback ran.
  void expireIfNeeded() {
    final session = _session;
    if (session != null && !session.isActive) update(null);
  }

  /// Checks that an asynchronous result still belongs to the active session.
  bool matches(int expectedGeneration, TradeSession expectedSession) {
    if (_disposed) return false;
    final session = _session;
    return expectedGeneration == _generation &&
        session != null &&
        session.isActive &&
        _sameSession(session, expectedSession);
  }

  void _scheduleExpiry(TradeSession session, int generation) {
    final remaining = session.expiresAt.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      update(null);
      return;
    }
    _expiryTimer = Timer(remaining, () {
      if (_generation != generation || !_sameSession(_session, session)) return;
      if (session.isActive) {
        _scheduleExpiry(session, generation);
      } else {
        update(null);
      }
    });
  }

  bool _sameSession(TradeSession? left, TradeSession? right) {
    if (identical(left, right)) return true;
    if (left == null || right == null) return false;
    return left.bearerToken == right.bearerToken &&
        left.accountIdentifier == right.accountIdentifier &&
        left.expiresAt == right.expiresAt;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _session = null;
    _disposed = true;
    _generation++;
    notifyListeners();
    _changes.add(null);
    _expiryTimer?.cancel();
    _expiryTimer = null;
    unawaited(_changes.close());
    super.dispose();
  }
}
