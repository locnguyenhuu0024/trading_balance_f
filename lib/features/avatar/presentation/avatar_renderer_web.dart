import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../domain/avatar_colors.dart';
import '../domain/avatar_model.dart';
import '../domain/avatar_mood.dart';
import 'avatar_renderer.dart';

AvatarRenderer createPlatformAvatarRenderer(AvatarModel model) =>
    _WebAvatarRenderer(model);

class _WebAvatarRenderer implements AvatarRenderer {
  _WebAvatarRenderer(AvatarModel model) {
    final src =
        'assets/assets/avatar/index.html?model='
        '${Uri.encodeQueryComponent(model.id)}';
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int _) => web.HTMLIFrameElement()
        ..src = src
        ..tabIndex = -1
        ..setAttribute('aria-hidden', 'true')
        ..style.cssText =
            'border:0;width:100%;height:100%;background:transparent;pointer-events:none;opacity:0',
    );
    _messages = web.EventStreamProviders.messageEvent
        .forTarget(web.window)
        .listen(_receive);
  }

  static int _nextId = 0;
  final _viewType = 'portfolio-avatar-${_nextId++}';
  web.HTMLIFrameElement? _iframe;
  final _events = StreamController<AvatarEvent>();
  late final StreamSubscription<web.MessageEvent> _messages;
  AvatarMood _mood = AvatarMood.neutral;
  AvatarColors _colors = AvatarColors.empty;
  List<String> _outfit = const [];
  bool _paused = false;
  bool _reducedMotion = false;
  bool _ready = false;
  bool _failed = false;

  void _receive(web.MessageEvent message) {
    final frameWindow = _iframe?.contentWindow;
    if (_failed ||
        message.origin != web.window.location.origin ||
        frameWindow == null ||
        message.source != frameWindow) {
      return;
    }
    final AvatarEvent? event;
    try {
      event = decodeAvatarEvent(message.data.dartify());
    } catch (_) {
      return;
    }
    if (event == null) return;
    if (event is AvatarModelLoaded) _iframe?.style.opacity = '1';
    _events.add(event);
    if (event is AvatarError && event.code != 'outfit') _failed = true;
    if (event is AvatarReady && !_ready) {
      _ready = true;
      setReducedMotion(_reducedMotion);
      setMood(_mood);
      setColors(_colors);
      setOutfit(_outfit);
      if (_paused) setPaused(true);
    }
  }

  void _send(Map<String, Object?> message) {
    if (!_ready || _failed) return;
    _iframe?.contentWindow?.postMessage(
      {...message, 'v': 1}.jsify(),
      web.window.location.origin.toJS,
    );
  }

  @override
  Widget buildView() => HtmlElementView(
    viewType: _viewType,
    onPlatformViewCreated: (id) {
      if (!_failed) {
        _iframe =
            ui_web.platformViewRegistry.getViewById(id)
                as web.HTMLIFrameElement;
      }
    },
  );

  @override
  Stream<AvatarEvent> get events => _events.stream;

  @override
  void setMood(AvatarMood mood) {
    _mood = mood;
    _send({'type': 'setMood', 'mood': mood.wireName});
  }

  @override
  void setColors(AvatarColors colors) {
    _colors = colors;
    _send({'type': 'setColors', 'colors': colors.toJson()});
  }

  @override
  void setOutfit(List<String> itemIds) {
    _outfit = List.unmodifiable(itemIds);
    _send({'type': 'setOutfit', 'items': _outfit});
  }

  @override
  void setPaused(bool paused) {
    _paused = paused;
    _send({'type': 'setPaused', 'paused': paused});
  }

  @override
  void setReducedMotion(bool reducedMotion) {
    _reducedMotion = reducedMotion;
    _send({'type': 'setReducedMotion', 'on': reducedMotion});
  }

  @override
  void sendPointer(String phase, double x, double y, int tMs) {
    _send({'type': 'pointer', 'phase': phase, 'x': x, 'y': y, 't': tMs});
  }

  @override
  void dispose() {
    _failed = true;
    _iframe = null;
    unawaited(_messages.cancel());
    unawaited(_events.close());
  }
}
