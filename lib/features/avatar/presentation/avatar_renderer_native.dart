import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../domain/avatar_mood.dart';
import 'avatar_renderer.dart';

AvatarRenderer createPlatformAvatarRenderer() => _NativeAvatarRenderer();

class _NativeAvatarRenderer implements AvatarRenderer {
  _NativeAvatarRenderer() {
    unawaited(_loadPage());
  }

  static const _channel = 'AvatarChannel';
  static const _chunkSize = 512 * 1024;

  final _controller = WebViewController();
  final _events = StreamController<AvatarEvent>();
  AvatarMood _mood = AvatarMood.neutral;
  bool _paused = false;
  bool _reducedMotion = false;
  bool _ready = false;
  bool _failed = false;
  bool _disposed = false;

  bool get _active => !_disposed && !_failed;

  Future<void> _loadPage() async {
    try {
      await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      if (!_active) return;
      try {
        await _controller.setBackgroundColor(Colors.transparent);
      } catch (_) {
        // Some platform views cannot set their own background color.
      }
      if (!_active) return;
      await _controller.setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (error) {
            if (error.isForMainFrame != false) {
              _fail(AvatarError('load', error.description));
            }
          },
        ),
      );
      if (!_active) return;
      await _controller.addJavaScriptChannel(
        _channel,
        onMessageReceived: (message) => _receive(message.message),
      );
      if (_active) {
        await _controller.loadFlutterAsset('assets/avatar/index.html');
      }
    } catch (error) {
      _fail(AvatarError('load', error.toString()));
    }
  }

  void _receive(String raw) {
    if (!_active) return;
    final event = decodeAvatarEvent(raw);
    if (event == null) return;
    if (event is AvatarError) {
      _fail(event);
      return;
    }
    _events.add(event);
    if (event is AvatarReady && !_ready) {
      _ready = true;
      unawaited(_initializePage());
    }
  }

  Future<void> _initializePage() async {
    try {
      await Future.wait<void>([
        _send({'type': 'setReducedMotion', 'on': _reducedMotion}),
        _send({'type': 'setMood', 'mood': _mood.wireName}),
        if (_paused) _send({'type': 'setPaused', 'paused': true}),
      ]);
      if (!_active) return;
      final model = await rootBundle.load('assets/avatar/avatar.vrm');
      final bytes = Uint8List.sublistView(model);
      final count = (bytes.length + _chunkSize - 1) ~/ _chunkSize;
      for (var index = 0; index < count && _active; index++) {
        final start = index * _chunkSize;
        final end = math.min(start + _chunkSize, bytes.length);
        await _send({
          'type': 'loadModelChunk',
          'i': index,
          'n': count,
          'b64': base64Encode(Uint8List.sublistView(bytes, start, end)),
        });
      }
    } catch (error) {
      _fail(AvatarError('load', error.toString()));
    }
  }

  void _fail(AvatarError error) {
    if (!_active) return;
    _failed = true;
    _events.add(error);
  }

  Future<void> _send(Map<String, Object?> message) async {
    if (!_active || !_ready) return;
    final jsonString = encodeAvatarMessage(message);
    try {
      await _controller.runJavaScript(
        'window.avatar.receive(${jsonEncode(jsonString)})',
      );
    } catch (error) {
      _fail(AvatarError('bridge', error.toString()));
    }
  }

  @override
  Widget buildView() =>
      IgnorePointer(child: WebViewWidget(controller: _controller));

  @override
  Stream<AvatarEvent> get events => _events.stream;

  @override
  void setMood(AvatarMood mood) {
    _mood = mood;
    unawaited(_send({'type': 'setMood', 'mood': mood.wireName}));
  }

  @override
  void setPaused(bool paused) {
    _paused = paused;
    unawaited(_send({'type': 'setPaused', 'paused': paused}));
  }

  @override
  void setReducedMotion(bool reducedMotion) {
    _reducedMotion = reducedMotion;
    unawaited(_send({'type': 'setReducedMotion', 'on': reducedMotion}));
  }

  @override
  void sendPointer(String phase, double x, double y, int tMs) {
    unawaited(
      _send({'type': 'pointer', 'phase': phase, 'x': x, 'y': y, 't': tMs}),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_events.close());
  }
}
