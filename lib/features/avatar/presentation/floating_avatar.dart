import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/avatar_colors.dart';
import '../domain/avatar_display.dart';
import '../domain/avatar_model.dart';
import '../domain/avatar_mood.dart';
import 'avatar_view.dart';

class FloatingAvatar extends StatefulWidget {
  const FloatingAvatar({
    super.key,
    required this.model,
    required this.mood,
    this.colors = AvatarColors.empty,
    this.outfit = const [],
    this.framing = AvatarFraming.full,
    this.scalePercent = AvatarScale.defaultPercent,
  });

  final AvatarModel model;
  final AvatarMood mood;
  final AvatarColors colors;
  final List<String> outfit;
  final AvatarFraming framing;
  final int scalePercent;

  @override
  State<FloatingAvatar> createState() => _FloatingAvatarState();
}

class _FloatingAvatarState extends State<FloatingAvatar> {
  Offset? _position;
  Offset? _dragOrigin;
  Size? _lastSize;

  Offset _clamp(Offset position, Offset limit) => Offset(
    position.dx.clamp(0.0, limit.dx).toDouble(),
    position.dy.clamp(0.0, limit.dy).toDouble(),
  );

  @override
  Widget build(BuildContext context) {
    final screenFactor = MediaQuery.sizeOf(context).width < 360 ? 0.8 : 1.0;
    final target =
        widget.framing.baseSize *
        (AvatarScale.normalize(widget.scalePercent) / 100 * screenFactor);
    return LayoutBuilder(
      builder: (context, constraints) {
        final fit = math.min(
          1.0,
          math.min(
            constraints.maxWidth / target.width,
            constraints.maxHeight / target.height,
          ),
        );
        final size = target * fit;
        final limit = Offset(
          math.max(0.0, constraints.maxWidth - size.width),
          math.max(0.0, constraints.maxHeight - size.height),
        );
        final previousPosition = _position;
        final previousSize = _lastSize;
        if (previousPosition != null && previousSize != null) {
          final position = _clamp(
            previousPosition +
                Offset(
                  previousSize.width - size.width,
                  previousSize.height - size.height,
                ),
            limit,
          );
          _position = position;
          if (_dragOrigin case final Offset origin) {
            _dragOrigin = origin + (position - previousPosition);
          }
        }
        _lastSize = size;
        final position =
            _position ?? _clamp(limit - const Offset(16, 16), limit);
        return Stack(
          children: [
            Positioned(
              left: position.dx,
              top: position.dy,
              width: size.width,
              height: size.height,
              child: AvatarView(
                key: ValueKey(widget.model.id),
                model: widget.model,
                mood: widget.mood,
                colors: widget.colors,
                outfit: widget.outfit,
                framing: widget.framing,
                semanticsLabel: 'Nhân vật 3D',
                onDragStart: () => _dragOrigin = position,
                onDragUpdate: (details) {
                  final origin = _dragOrigin;
                  if (origin == null) return;
                  setState(() {
                    _position = _clamp(
                      origin + details.offsetFromOrigin,
                      limit,
                    );
                  });
                },
                onDragEnd: () => _dragOrigin = null,
              ),
            ),
          ],
        );
      },
    );
  }
}
