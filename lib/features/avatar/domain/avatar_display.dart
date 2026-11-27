import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AvatarFraming {
  half('half', 'Nửa người', Size(160, 220)),
  full('full', 'Toàn thân', Size(150, 300));

  const AvatarFraming(this.wireName, this.label, this.baseSize);

  final String wireName;
  final String label;
  final Size baseSize;

  static AvatarFraming fromWire(String? value) =>
      value == half.wireName ? half : full;
}

abstract final class AvatarScale {
  static const min = 60;
  static const max = 160;
  static const step = 10;
  static const defaultPercent = 100;

  static int normalize(Object? raw) {
    final value = switch (raw) {
      num number => number.toDouble(),
      String text => double.tryParse(text),
      _ => null,
    };
    if (value == null || !value.isFinite) return defaultPercent;
    return (value.clamp(min, max) / step).round() * step;
  }
}

final avatarFramingProvider = StateProvider<AvatarFraming>(
  (ref) => AvatarFraming.full,
);

final avatarScalePercentProvider = StateProvider<int>(
  (ref) => AvatarScale.defaultPercent,
);
