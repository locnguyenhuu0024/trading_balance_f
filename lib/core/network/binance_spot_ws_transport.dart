import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

abstract interface class BinanceSpotPrivateTransport {
  Future<BinanceWsReply> send({
    required String method,
    required Map<String, Object> params,
    CancelToken? cancelToken,
  });

  void close();

  void dispose();
}

enum BinanceSpotTransportFailure { timeout, network, cancelled, closed }

class BinanceSpotTransportException implements Exception {
  const BinanceSpotTransportException(this.kind);

  final BinanceSpotTransportFailure kind;

  @override
  String toString() => 'BinanceSpotTransportException(${kind.name})';
}

class BinanceWsReply {
  const BinanceWsReply({
    required this.status,
    this.result,
    this.errorCode,
    this.errorMessage,
    this.rateLimits = const [],
    this.retryAfter,
  });

  final int status;
  final Object? result;
  final int? errorCode;
  final String? errorMessage;
  final List<Map<String, Object?>> rateLimits;
  final String? retryAfter;
}

abstract interface class BinanceSpotWebSocketConnection {
  Stream<dynamic> get stream;

  StreamSink<dynamic> get sink;

  Future<void> close();
}

typedef BinanceSpotWebSocketConnector =
    FutureOr<BinanceSpotWebSocketConnection> Function(Uri uri);

class BinanceSpotWebSocketTransport implements BinanceSpotPrivateTransport {
  BinanceSpotWebSocketTransport({
    BinanceSpotWebSocketConnector? connector,
    this.requestTimeout = const Duration(seconds: 15),
    this.idleTimeout = const Duration(seconds: 60),
  }) : _connector = connector ?? _connectWebSocketChannel;

  static final Uri endpoint = Uri.parse(
    'wss://ws-api.binance.com:443/ws-api/v3',
  );

  final BinanceSpotWebSocketConnector _connector;
  final Duration requestTimeout;
  final Duration idleTimeout;

  final Map<String, _PendingRequest> _pending = {};
  BinanceSpotWebSocketConnection? _connection;
  StreamSubscription<dynamic>? _connectionSubscription;
  Future<BinanceSpotWebSocketConnection>? _connecting;
  Timer? _idleTimer;
  int _generation = 0;
  int _nextRequestId = 0;
  bool _disposed = false;

  @override
  Future<BinanceWsReply> send({
    required String method,
    required Map<String, Object> params,
    CancelToken? cancelToken,
  }) {
    if (_disposed) {
      return Future<BinanceWsReply>.error(
        const BinanceSpotTransportException(BinanceSpotTransportFailure.closed),
      );
    }
    if (cancelToken?.isCancelled ?? false) {
      return Future<BinanceWsReply>.error(
        const BinanceSpotTransportException(
          BinanceSpotTransportFailure.cancelled,
        ),
      );
    }

    final id = 'binance-spot-${++_nextRequestId}';
    final pending = _PendingRequest();
    _pending[id] = pending;
    _idleTimer?.cancel();
    _idleTimer = null;
    pending.timeoutTimer = Timer(requestTimeout, () {
      _failRequest(id, BinanceSpotTransportFailure.timeout);
    });
    cancelToken?.whenCancel.then<void>((_) {
      _failRequest(id, BinanceSpotTransportFailure.cancelled);
    });

    unawaited(_dispatch(id, method, params));
    return pending.completer.future;
  }

  @override
  void close() {
    if (_disposed) return;
    unawaited(_shutdown(BinanceSpotTransportFailure.closed));
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_shutdown(BinanceSpotTransportFailure.closed));
  }

  Future<void> _dispatch(
    String id,
    String method,
    Map<String, Object> params,
  ) async {
    try {
      final connection = await _ensureConnection();
      if (!_pending.containsKey(id) || !identical(_connection, connection)) {
        return;
      }

      final frame = jsonEncode({'id': id, 'method': method, 'params': params});
      connection.sink.add(frame);
    } on BinanceSpotTransportException catch (error) {
      _failRequest(id, error.kind);
    } catch (_) {
      final connection = _connection;
      if (connection != null) {
        _handleConnectionEnd(connection);
      } else {
        _failRequest(id, BinanceSpotTransportFailure.network);
      }
    }
  }

  Future<BinanceSpotWebSocketConnection> _ensureConnection() {
    if (_disposed) {
      return Future<BinanceSpotWebSocketConnection>.error(
        const BinanceSpotTransportException(BinanceSpotTransportFailure.closed),
      );
    }
    final connection = _connection;
    if (connection != null) {
      return Future<BinanceSpotWebSocketConnection>.value(connection);
    }
    final connecting = _connecting;
    if (connecting != null) return connecting;

    final generation = _generation;
    final attempt =
        Future<BinanceSpotWebSocketConnection>.sync(
          () => _connector(endpoint),
        ).then<BinanceSpotWebSocketConnection>(
          (candidate) {
            if (_disposed || generation != _generation) {
              unawaited(_closeQuietly(candidate));
              throw const BinanceSpotTransportException(
                BinanceSpotTransportFailure.closed,
              );
            }

            try {
              _connection = candidate;
              _connectionSubscription = candidate.stream.listen(
                (frame) => _handleFrame(candidate, frame),
                onError: (Object error, StackTrace stackTrace) {
                  _handleConnectionEnd(candidate);
                },
                onDone: () => _handleConnectionEnd(candidate),
              );
            } catch (_) {
              if (identical(_connection, candidate)) _connection = null;
              unawaited(_closeQuietly(candidate));
              throw const BinanceSpotTransportException(
                BinanceSpotTransportFailure.network,
              );
            }

            if (_pending.isEmpty) _scheduleIdleClose();
            return candidate;
          },
          onError: (Object error, StackTrace stackTrace) {
            if (_disposed || generation != _generation) {
              throw const BinanceSpotTransportException(
                BinanceSpotTransportFailure.closed,
              );
            }
            throw const BinanceSpotTransportException(
              BinanceSpotTransportFailure.network,
            );
          },
        );

    _connecting = attempt;
    attempt.then<void>(
      (_) {
        if (identical(_connecting, attempt)) _connecting = null;
      },
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_connecting, attempt)) _connecting = null;
      },
    );
    return attempt;
  }

  void _handleFrame(
    BinanceSpotWebSocketConnection connection,
    Object? rawFrame,
  ) {
    if (!identical(_connection, connection) || rawFrame is! String) return;

    Object? decoded;
    try {
      decoded = jsonDecode(rawFrame);
    } catch (_) {
      return;
    }
    if (decoded is! Map) return;

    if (decoded['method'] == 'serverShutdown' ||
        decoded['event'] == 'serverShutdown' ||
        decoded['type'] == 'serverShutdown') {
      _handleConnectionEnd(connection);
      return;
    }

    final idValue = decoded['id'];
    if (idValue is! String) return;
    final pending = _pending[idValue];
    if (pending == null) return;

    final statusValue = decoded['status'];
    if (statusValue is! int) return;

    final error = decoded['error'];
    final errorMap = error is Map ? error : null;
    final codeValue = errorMap?['code'];
    final errorCode = switch (codeValue) {
      int value => value,
      num value => value.toInt(),
      _ => null,
    };
    final messageValue = errorMap?['msg'];
    final retryAfterValue = decoded['retryAfter'] ?? errorMap?['retryAfter'];

    final reply = BinanceWsReply(
      status: statusValue,
      result: decoded['result'],
      errorCode: errorCode,
      errorMessage: messageValue is String ? messageValue : null,
      rateLimits: _parseRateLimits(decoded['rateLimits']),
      retryAfter: retryAfterValue?.toString(),
    );
    _completeRequest(idValue, pending, reply);
  }

  List<Map<String, Object?>> _parseRateLimits(Object? value) {
    if (value is! List) return const [];
    final limits = <Map<String, Object?>>[];
    for (final item in value) {
      if (item is! Map) continue;
      final limit = <String, Object?>{};
      for (final entry in item.entries) {
        if (entry.key is String) limit[entry.key as String] = entry.value;
      }
      limits.add(Map<String, Object?>.unmodifiable(limit));
    }
    return List<Map<String, Object?>>.unmodifiable(limits);
  }

  void _completeRequest(
    String id,
    _PendingRequest pending,
    BinanceWsReply reply,
  ) {
    if (!identical(_pending[id], pending)) return;
    _pending.remove(id);
    pending.timeoutTimer?.cancel();
    pending.completer.complete(reply);
    _scheduleIdleClose();
  }

  void _failRequest(String id, BinanceSpotTransportFailure failure) {
    final pending = _pending.remove(id);
    if (pending == null) return;
    pending.timeoutTimer?.cancel();
    pending.completer.completeError(BinanceSpotTransportException(failure));
    _scheduleIdleClose();
  }

  void _failAll(BinanceSpotTransportFailure failure) {
    final ids = _pending.keys.toList(growable: false);
    for (final id in ids) {
      _failRequest(id, failure);
    }
  }

  void _handleConnectionEnd(BinanceSpotWebSocketConnection connection) {
    if (!identical(_connection, connection)) return;
    _connection = null;
    final subscription = _connectionSubscription;
    _connectionSubscription = null;
    _connecting = null;
    _generation++;
    _idleTimer?.cancel();
    _idleTimer = null;
    if (subscription != null) unawaited(subscription.cancel());
    _failAll(BinanceSpotTransportFailure.network);
    unawaited(_closeQuietly(connection));
  }

  Future<void> _shutdown(BinanceSpotTransportFailure failure) async {
    _generation++;
    _connecting = null;
    _idleTimer?.cancel();
    _idleTimer = null;
    _failAll(failure);

    final subscription = _connectionSubscription;
    final connection = _connection;
    _connectionSubscription = null;
    _connection = null;
    if (subscription != null) {
      try {
        await subscription.cancel();
      } catch (_) {}
    }
    if (connection != null) await _closeQuietly(connection);
  }

  void _scheduleIdleClose() {
    _idleTimer?.cancel();
    _idleTimer = null;
    final connection = _connection;
    if (connection == null || _pending.isNotEmpty || _disposed) return;

    _idleTimer = Timer(idleTimeout, () {
      if (!identical(_connection, connection) || _pending.isNotEmpty) return;
      _connection = null;
      final subscription = _connectionSubscription;
      _connectionSubscription = null;
      _generation++;
      if (subscription != null) unawaited(subscription.cancel());
      unawaited(_closeQuietly(connection));
    });
  }

  Future<void> _closeQuietly(BinanceSpotWebSocketConnection connection) async {
    try {
      await connection.close();
    } catch (_) {}
  }
}

class _PendingRequest {
  final Completer<BinanceWsReply> completer = Completer<BinanceWsReply>();
  Timer? timeoutTimer;
}

Future<BinanceSpotWebSocketConnection> _connectWebSocketChannel(Uri uri) async {
  final channel = WebSocketChannel.connect(uri);
  try {
    await channel.ready;
    return _WebSocketChannelConnection(channel);
  } catch (_) {
    try {
      await channel.sink.close();
    } catch (_) {}
    rethrow;
  }
}

class _WebSocketChannelConnection implements BinanceSpotWebSocketConnection {
  const _WebSocketChannelConnection(this._channel);

  final WebSocketChannel _channel;

  @override
  Stream<dynamic> get stream => _channel.stream;

  @override
  StreamSink<dynamic> get sink => _channel.sink;

  @override
  Future<void> close() => _channel.sink.close();
}
