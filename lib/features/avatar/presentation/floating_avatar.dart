import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/avatar_mood.dart';
import 'avatar_renderer.dart';

class FloatingAvatar extends ConsumerStatefulWidget {
  const FloatingAvatar({super.key, required this.mood});

  final AvatarMood mood;

  @override
  ConsumerState<FloatingAvatar> createState() => _FloatingAvatarState();
}

class _FloatingAvatarState extends ConsumerState<FloatingAvatar>
    with WidgetsBindingObserver {
  late final AvatarRenderer _renderer;
  late final Widget _view;
  late final StreamSubscription<AvatarEvent> _events;
  bool _loaded = false;
  bool _failed = false;
  bool? _reducedMotion;
  Offset? _position;
  Offset? _dragOrigin;
  int? _pointer;
  var _lastLocalPosition = Offset.zero;
  int _lastPointerMs = 0;
  int? _lastMoveMs;

  @override
  void initState() {
    super.initState();
    _renderer = ref.read(avatarRendererFactoryProvider)();
    _events = _renderer.events.listen(_onAvatarEvent);
    _renderer.setMood(widget.mood);
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
  void didUpdateWidget(covariant FloatingAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_failed && widget.mood != oldWidget.mood) {
      _renderer.setMood(widget.mood);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_failed) return;
    final paused = state != AppLifecycleState.resumed;
    if (paused && _pointer != null) {
      if (_dragOrigin == null) _sendPointer('cancel');
      _pointer = null;
      _dragOrigin = null;
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
    if (_dragOrigin == null) {
      if (phase == 'move') {
        final lastMove = _lastMoveMs;
        if (lastMove != null && _lastPointerMs - lastMove < 33) return;
        _lastMoveMs = _lastPointerMs;
      }
      _sendPointer(phase);
    }
    if (phase == 'up' || phase == 'cancel') {
      _pointer = null;
      if (phase == 'cancel') _dragOrigin = null;
    }
  }

  void _sendPointer(String phase) => _renderer.sendPointer(
    phase,
    _lastLocalPosition.dx,
    _lastLocalPosition.dy,
    _lastPointerMs,
  );

  Offset _clamp(Offset position, Offset limit) => Offset(
    position.dx.clamp(0.0, limit.dx).toDouble(),
    position.dy.clamp(0.0, limit.dy).toDouble(),
  );

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();

    final scale = MediaQuery.sizeOf(context).width < 360 ? 0.8 : 1.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(160 * scale, constraints.maxWidth);
        final height = math.min(220 * scale, constraints.maxHeight);
        final limit = Offset(
          constraints.maxWidth - width,
          constraints.maxHeight - height,
        );
        final position = _clamp(
          _position ?? limit - const Offset(16, 16),
          limit,
        );
        return Stack(
          children: [
            Positioned(
              left: position.dx,
              top: position.dy,
              width: width,
              height: height,
              child: Semantics(
                label: 'Nhân vật 3D',
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
                      onLongPressStart: (_) {
                        if (_pointer == null) return;
                        // End the page's gesture before the host takes over.
                        _sendPointer('cancel');
                        _dragOrigin = position;
                      },
                      onLongPressMoveUpdate: (details) {
                        final origin = _dragOrigin;
                        if (origin == null) return;
                        setState(() {
                          _position = _clamp(
                            origin + details.offsetFromOrigin,
                            limit,
                          );
                        });
                      },
                      onLongPressEnd: (_) => _dragOrigin = null,
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
              ),
            ),
          ],
        );
      },
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
