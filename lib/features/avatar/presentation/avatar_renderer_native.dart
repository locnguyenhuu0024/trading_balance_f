import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../domain/avatar_colors.dart';
import '../domain/avatar_display.dart';
import '../domain/avatar_model.dart';
import '../domain/avatar_mood.dart';
import '../domain/avatar_outfit.dart';
import 'avatar_renderer.dart';

AvatarRenderer createPlatformAvatarRenderer(AvatarModel model) =>
    _NativeAvatarRenderer(model);

class _NativeAvatarRenderer implements AvatarRenderer {
  _NativeAvatarRenderer(this._model) {
    unawaited(_loadPage());
  }

  static const _channel = 'AvatarChannel';
  static const _chunkSize = 512 * 1024;

  final AvatarModel _model;
  final _controller = WebViewController();
  final _events = StreamController<AvatarEvent>();
  AvatarMood _mood = AvatarMood.neutral;
  AvatarColors _colors = AvatarColors.empty;
  List<String> _outfit = const [];
  AvatarFraming _framing = AvatarFraming.full;
  final _streamedDonors = <String>{};
  bool _modelLoaded = false;
  bool _streamingDonors = false;
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
    if (event is AvatarError && event.code != 'outfit') {
      _fail(event);
      return;
    }
    _events.add(event);
    if (event is AvatarReady && !_ready) {
      _ready = true;
      unawaited(_initializePage());
    }
    if (event is AvatarModelLoaded) {
      _modelLoaded = true;
      unawaited(_streamDonors());
    }
  }

  Future<void> _initializePage() async {
    try {
      await Future.wait<void>([
        _send({'type': 'setReducedMotion', 'on': _reducedMotion}),
        _send({'type': 'setMood', 'mood': _mood.wireName}),
        _send({'type': 'setColors', 'colors': _colors.toJson()}),
        _send({'type': 'setOutfit', 'items': _outfit}),
        _send({'type': 'setFraming', 'mode': _framing.wireName}),
        if (_paused) _send({'type': 'setPaused', 'paused': true}),
      ]);
      if (_active) await _streamModel(_model);
    } catch (error) {
      _fail(AvatarError('load', error.toString()));
    }
  }

  Future<void> _streamModel(AvatarModel model, {bool donor = false}) async {
    final data = await rootBundle.load('assets/avatar/${model.file}');
    final bytes = Uint8List.sublistView(data);
    final count = (bytes.length + _chunkSize - 1) ~/ _chunkSize;
    for (var index = 0; index < count && _active; index++) {
      final start = index * _chunkSize;
      final end = math.min(start + _chunkSize, bytes.length);
      await _send({
        'type': donor ? 'loadDonorChunk' : 'loadModelChunk',
        if (donor) 'model': model.id,
        'i': index,
        'n': count,
        'b64': base64Encode(Uint8List.sublistView(bytes, start, end)),
      });
    }
  }

  Future<void> _streamDonors() async {
    if (!_modelLoaded || _streamingDonors) return;
    _streamingDonors = true;
    try {
      while (_active) {
        final donorId = equippedItems(_model.id, _outfit)
            .map((item) => item.donorModelId)
            .where((id) => !_streamedDonors.contains(id))
            .firstOrNull;
        if (donorId == null) return;
        _streamedDonors.add(donorId);
        try {
          await _streamModel(avatarModelById(donorId), donor: true);
        } catch (error) {
          if (_active) _events.add(AvatarError('outfit', error.toString()));
        }
      }
    } finally {
      _streamingDonors = false;
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
  void setColors(AvatarColors colors) {
    _colors = colors;
    unawaited(_send({'type': 'setColors', 'colors': colors.toJson()}));
  }

  @override
  void setOutfit(List<String> itemIds) {
    _outfit = List.unmodifiable(itemIds);
    unawaited(_send({'type': 'setOutfit', 'items': _outfit}));
    unawaited(_streamDonors());
  }

  @override
  void setFraming(AvatarFraming framing) {
    _framing = framing;
    unawaited(_send({'type': 'setFraming', 'mode': framing.wireName}));
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
