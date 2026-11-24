import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/avatar_colors.dart';
import '../domain/avatar_model.dart';
import '../domain/avatar_mood.dart';
import 'avatar_renderer.dart';

class AvatarView extends ConsumerStatefulWidget {
  const AvatarView({
    super.key,
    required this.model,
    required this.mood,
    required this.colors,
    required this.semanticsLabel,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
  });

  final AvatarModel model;

  final AvatarMood mood;
  final AvatarColors colors;
  final String semanticsLabel;
  final VoidCallback? onDragStart;
  final GestureLongPressMoveUpdateCallback? onDragUpdate;
  final VoidCallback? onDragEnd;

  @override
  ConsumerState<AvatarView> createState() => _AvatarViewState();
}

class _AvatarViewState extends ConsumerState<AvatarView>
    with WidgetsBindingObserver {
  late final AvatarRenderer _renderer;
  late final Widget _view;
  late final StreamSubscription<AvatarEvent> _events;
  bool _loaded = false;
  bool _failed = false;
  bool? _reducedMotion;
  bool _dragging = false;
  int? _pointer;
  var _lastLocalPosition = Offset.zero;
  int _lastPointerMs = 0;
  int? _lastMoveMs;

  @override
  void initState() {
    super.initState();
    _renderer = ref.read(avatarRendererFactoryProvider)(widget.model);
    _events = _renderer.events.listen(_onAvatarEvent);
    _renderer.setMood(widget.mood);
    _renderer.setColors(widget.colors);
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    final lifecycle = binding.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      _renderer.setPaused(true);
    }
    _view = _renderer.buildView();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (reducedMotion != _reducedMotion) {
      _reducedMotion = reducedMotion;
      if (!_failed) _renderer.setReducedMotion(reducedMotion);
    }
  }

  @override
  void didUpdateWidget(covariant AvatarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_failed) return;
    if (widget.mood != oldWidget.mood) {
      _renderer.setMood(widget.mood);
    }
    if (widget.colors != oldWidget.colors) {
      _renderer.setColors(widget.colors);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_failed) return;
    final paused = state != AppLifecycleState.resumed;
    if (paused && _pointer != null) {
      if (!_dragging) _sendPointer('cancel');
      _pointer = null;
      _endDrag();
    }
    _renderer.setPaused(paused);
  }

  void _onAvatarEvent(AvatarEvent event) {
    if (!mounted || _failed) return;
    switch (event) {
      case AvatarReady():
        break;
      case AvatarModelLoaded():
        if (!_loaded) setState(() => _loaded = true);
      case AvatarError():
        setState(() => _failed = true);
      case AvatarInteraction():
        unawaited(HapticFeedback.lightImpact());
    }
  }

  void _samplePointer(String phase, PointerEvent event) {
    if (_failed) return;
    if (phase == 'down' && _pointer == null) {
      _pointer = event.pointer;
      _lastMoveMs = null;
    }
    if (_pointer != event.pointer) return;
    _lastLocalPosition = event.localPosition;
    _lastPointerMs = event.timeStamp.inMilliseconds;
    if (!_dragging) {
      if (phase == 'move') {
        final lastMove = _lastMoveMs;
        if (lastMove != null && _lastPointerMs - lastMove < 33) return;
        _lastMoveMs = _lastPointerMs;
      }
      _sendPointer(phase);
    }
    if (phase == 'up' || phase == 'cancel') {
      _pointer = null;
      _endDrag();
    }
  }

  void _sendPointer(String phase) => _renderer.sendPointer(
    phase,
    _lastLocalPosition.dx,
    _lastLocalPosition.dy,
    _lastPointerMs,
  );

  void _startDrag() {
    if (_pointer == null || _failed) return;
    // End the renderer's gesture before the floating host takes over.
    _sendPointer('cancel');
    _dragging = true;
    widget.onDragStart?.call();
  }

  void _endDrag() {
    if (!_dragging) return;
    _dragging = false;
    widget.onDragEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();

    return Semantics(
      label: widget.semanticsLabel,
      image: true,
      hidden: !_loaded,
      child: IgnorePointer(
        ignoring: !_loaded,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) => _samplePointer('down', event),
          onPointerMove: (event) => _samplePointer('move', event),
          onPointerUp: (event) => _samplePointer('up', event),
          onPointerCancel: (event) => _samplePointer('cancel', event),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPressStart: widget.onDragStart == null
                ? null
                : (_) => _startDrag(),
            onLongPressMoveUpdate: widget.onDragUpdate == null
                ? null
                : (details) {
                    if (_dragging && !_failed) {
                      widget.onDragUpdate?.call(details);
                    }
                  },
            child: AnimatedOpacity(
              // A fully culled platform view cannot attach its iframe.
              opacity: _loaded ? 1.0 : 1 / 255,
              duration: _reducedMotion == true
                  ? Duration.zero
                  : const Duration(milliseconds: 250),
              child: _view,
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_events.cancel());
    _renderer.dispose();
    super.dispose();
  }
}
