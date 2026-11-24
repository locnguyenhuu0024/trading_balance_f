import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/avatar_colors.dart';
import '../domain/avatar_model.dart';
import '../domain/avatar_mood.dart';
import 'avatar_renderer_native.dart'
    if (dart.library.js_interop) 'avatar_renderer_web.dart';

sealed class AvatarEvent {
  const AvatarEvent();
}

final class AvatarReady extends AvatarEvent {
  const AvatarReady();
}

final class AvatarModelLoaded extends AvatarEvent {
  const AvatarModelLoaded();
}

final class AvatarError extends AvatarEvent {
  const AvatarError(this.code, this.message);

  final String code;
  final String message;
}

final class AvatarInteraction extends AvatarEvent {
  const AvatarInteraction(this.kind);

  final String kind;
}

abstract class AvatarRenderer {
  Widget buildView();
  void setMood(AvatarMood mood);
  void setColors(AvatarColors colors);
  void setOutfit(List<String> itemIds);
  void setPaused(bool paused);
  void setReducedMotion(bool reducedMotion);
  void sendPointer(String phase, double x, double y, int tMs);
  Stream<AvatarEvent> get events;
  void dispose();
}

typedef AvatarRendererFactory = AvatarRenderer Function(AvatarModel model);

final avatarRendererFactoryProvider = Provider<AvatarRendererFactory>(
  (ref) => createPlatformAvatarRenderer,
);

String encodeAvatarMessage(Map<String, Object?> message) =>
    jsonEncode({...message, 'v': 1});

AvatarEvent? decodeAvatarEvent(Object? raw) {
  final Object? message;
  try {
    message = raw is String ? jsonDecode(raw) : raw;
  } on FormatException {
    return null;
  }

  if (message is! Map || message['v'] != 1) return null;
  return switch (message) {
    {'type': 'ready', 'version': 1} => const AvatarReady(),
    {'type': 'modelLoaded'} => const AvatarModelLoaded(),
    {
      'type': 'error',
      'code': final String code,
      'message': final String text,
    } =>
      AvatarError(code, text),
    {'type': 'interaction', 'kind': final String kind}
        when const {
          'pat',
          'pettingStart',
          'pettingEnd',
          'poke',
          'swipe',
        }.contains(kind) =>
      AvatarInteraction(kind),
    _ => null,
  };
}
