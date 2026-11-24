import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/avatar_colors.dart';
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
  });

  final AvatarModel model;
  final AvatarMood mood;
  final AvatarColors colors;
  final List<String> outfit;

  @override
  State<FloatingAvatar> createState() => _FloatingAvatarState();
}

class _FloatingAvatarState extends State<FloatingAvatar> {
  Offset? _position;
  Offset? _dragOrigin;

  Offset _clamp(Offset position, Offset limit) => Offset(
    position.dx.clamp(0.0, limit.dx).toDouble(),
    position.dy.clamp(0.0, limit.dy).toDouble(),
  );

  @override
  Widget build(BuildContext context) {
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
              child: AvatarView(
                key: ValueKey(widget.model.id),
                model: widget.model,
                mood: widget.mood,
                colors: widget.colors,
                outfit: widget.outfit,
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
