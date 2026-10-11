import 'package:flutter/foundation.dart';

import 'user_session.dart';

/// Immutable identity used for every private cache, page and action.
@immutable
class ConnectionScope {
  const ConnectionScope({
    required this.userId,
    required this.sessionId,
    required this.connectionId,
    required this.exchange,
    required this.environment,
    required this.region,
    required this.product,
    required this.credentialVersion,
    required this.permissionVersion,
    required this.generation,
  });

  final String userId;
  final String sessionId;
  final String connectionId;
  final String exchange;
  final String environment;
  final String region;
  final String product;
  final int credentialVersion;
  final int permissionVersion;
  final int generation;

  bool belongsTo(UserSession session) =>
      userId == session.userId && sessionId == session.sessionId;

  bool sameAuthority(ConnectionScope other) =>
      userId == other.userId &&
      sessionId == other.sessionId &&
      connectionId == other.connectionId &&
      exchange == other.exchange &&
      environment == other.environment &&
      region == other.region &&
      product == other.product &&
      credentialVersion == other.credentialVersion &&
      permissionVersion == other.permissionVersion &&
      generation == other.generation;

  bool sameSelection(ConnectionScope other) =>
      userId == other.userId &&
      sessionId == other.sessionId &&
      connectionId == other.connectionId &&
      exchange == other.exchange &&
      environment == other.environment &&
      region == other.region &&
      product == other.product &&
      credentialVersion == other.credentialVersion &&
      permissionVersion == other.permissionVersion;

  @override
  bool operator ==(Object other) =>
      other is ConnectionScope && sameAuthority(other);

  @override
  int get hashCode => Object.hash(
    userId,
    sessionId,
    connectionId,
    exchange,
    environment,
    region,
    product,
    credentialVersion,
    permissionVersion,
    generation,
  );
}

/// Advances synchronously when account/product/version ownership changes.
class ConnectionScopeStore extends ChangeNotifier {
  ConnectionScope? _current;
  int _generation = 0;
  bool _disposed = false;

  int get generation => _generation;
  ConnectionScope? get current => _disposed ? null : _current;

  ConnectionScope? select({
    required UserSession session,
    required String connectionId,
    required String exchange,
    required String environment,
    required String region,
    required String product,
    required int credentialVersion,
    required int permissionVersion,
  }) {
    if (_disposed || !session.canReadPrivate) {
      clear();
      return null;
    }
    final next = ConnectionScope(
      userId: session.userId,
      sessionId: session.sessionId,
      connectionId: connectionId,
      exchange: exchange,
      environment: environment,
      region: region,
      product: product,
      credentialVersion: credentialVersion,
      permissionVersion: permissionVersion,
      generation: _generation + 1,
    );
    if (_current?.sameSelection(next) == true) return _current;
    _generation++;
    _current = next;
    notifyListeners();
    return next;
  }

  void clear() {
    if (_disposed || _current == null) return;
    _current = null;
    _generation++;
    notifyListeners();
  }

  bool matches(int generation, ConnectionScope expected) =>
      !_disposed &&
      generation == _generation &&
      _current != null &&
      _current!.sameAuthority(expected);

  @override
  void dispose() {
    if (_disposed) return;
    _current = null;
    _generation++;
    _disposed = true;
    super.dispose();
  }
}
