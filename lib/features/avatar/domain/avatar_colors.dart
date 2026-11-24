import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'avatar_model.dart';

enum AvatarPart {
  hair('Tóc'),
  eyes('Mắt'),
  top('Áo'),
  bottom('Quần/Váy'),
  shoes('Giày'),
  accessory('Phụ kiện'),
  dress('Váy'),
  bows('Nơ & huy hiệu'),
  socks('Tất'),
  plasters('Miếng dán');

  const AvatarPart(this.label);

  final String label;
  String get wireName => name;
}

@immutable
class AvatarColors {
  const AvatarColors._(this._parts);

  static const empty = AvatarColors._({});

  final Map<AvatarPart, Color> _parts;

  Color? operator [](AvatarPart part) => _parts[part];

  AvatarColors withPart(AvatarPart part, Color color) {
    final opaque = Color(0xff000000 | (color.toARGB32() & 0xffffff));
    return AvatarColors._(Map.unmodifiable({..._parts, part: opaque}));
  }

  AvatarColors withoutPart(AvatarPart part) =>
      restrictTo(_parts.keys.where((key) => key != part));

  AvatarColors restrictTo(Iterable<AvatarPart> parts) {
    final filtered = {
      for (final part in parts)
        if (_parts[part] case final Color color) part: color,
    };
    if (filtered.length == _parts.length) return this;
    if (filtered.isEmpty) return empty;
    return AvatarColors._(Map.unmodifiable(filtered));
  }

  Map<String, String> toJson() => {
    for (final part in AvatarPart.values)
      if (_parts[part] case final Color color)
        part.wireName:
            '#${(color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}',
  };

  @override
  bool operator ==(Object other) =>
      other is AvatarColors && mapEquals(_parts, other._parts);

  @override
  int get hashCode => Object.hashAllUnordered(
    _parts.entries.map((entry) => Object.hash(entry.key, entry.value)),
  );
}

final _hexColorPattern = RegExp(r'^#[0-9a-fA-F]{6}$');

Map<String, AvatarColors> decodeAvatarColorsMap(String? json) {
  if (json == null) return const {};
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException {
    return const {};
  }
  if (decoded is! Map<String, dynamic>) return const {};

  final colorsByModel = <String, AvatarColors>{};
  for (final model in avatarModels) {
    final modelColors = decoded[model.id];
    if (modelColors is! Map<String, dynamic>) continue;
    var colors = AvatarColors.empty;
    for (final part in model.parts) {
      final hex = modelColors[part.wireName];
      if (hex is String && hex.length == 7 && _hexColorPattern.hasMatch(hex)) {
        colors = colors.withPart(
          part,
          Color(0xff000000 | int.parse(hex.substring(1), radix: 16)),
        );
      }
    }
    if (colors != AvatarColors.empty) colorsByModel[model.id] = colors;
  }
  return Map.unmodifiable(colorsByModel);
}

String encodeAvatarColorsMap(Map<String, AvatarColors> colorsByModel) =>
    jsonEncode(colorsByModel);

final avatarColorsProvider = StateProvider<Map<String, AvatarColors>>(
  (ref) => const {},
);
