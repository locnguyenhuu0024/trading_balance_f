import 'dart:convert';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'avatar_colors.dart';
import 'avatar_model.dart';

enum AvatarSlot {
  outfit('Trang phục'),
  shoes('Giày'),
  plasters('Miếng dán');

  const AvatarSlot(this.label);

  final String label;
}

class AvatarItem {
  const AvatarItem({
    required this.id,
    required this.donorModelId,
    required this.slot,
    required this.label,
    required this.parts,
    required this.replacesParts,
  });

  final String id;
  final String donorModelId;
  final AvatarSlot slot;
  final String label;
  final List<AvatarPart> parts;
  final List<AvatarPart> replacesParts;
}

const _donutItems = [
  AvatarItem(
    id: 'donut-chan:outfit',
    donorModelId: 'donut-chan',
    slot: AvatarSlot.outfit,
    label: 'Váy Donut-Chan',
    parts: [AvatarPart.dress, AvatarPart.bows],
    replacesParts: [AvatarPart.top, AvatarPart.bottom],
  ),
  AvatarItem(
    id: 'donut-chan:shoes',
    donorModelId: 'donut-chan',
    slot: AvatarSlot.shoes,
    label: 'Giày Donut-Chan',
    parts: [AvatarPart.shoes],
    replacesParts: [AvatarPart.shoes],
  ),
  AvatarItem(
    id: 'donut-chan:plasters',
    donorModelId: 'donut-chan',
    slot: AvatarSlot.plasters,
    label: 'Miếng dán Donut-Chan',
    parts: [AvatarPart.plasters],
    replacesParts: [],
  ),
];

List<AvatarItem> itemsForModel(String modelId) =>
    modelId == defaultAvatarModelId ? _donutItems : const [];

Iterable<AvatarItem> equippedItems(
  String modelId,
  Iterable<String> itemIds,
) sync* {
  final available = {for (final item in itemsForModel(modelId)) item.id: item};
  final occupiedSlots = <AvatarSlot>{};
  for (final id in itemIds) {
    final item = available[id];
    if (item != null && occupiedSlots.add(item.slot)) yield item;
  }
}

List<AvatarPart> effectiveParts(AvatarModel model, List<String> itemIds) {
  final items = equippedItems(model.id, itemIds).toList();
  final replacements = {
    for (final item in items)
      for (final part in item.replacesParts) part: item,
  };
  return {
    for (final part in model.parts)
      if (replacements[part] case final AvatarItem item)
        ...item.parts
      else
        part,
    for (final item in items)
      if (item.replacesParts.isEmpty) ...item.parts,
  }.toList();
}

Color? originalColorFor(
  AvatarModel model,
  List<String> itemIds,
  AvatarPart part,
) {
  for (final item in equippedItems(model.id, itemIds)) {
    if (item.parts.contains(part)) {
      return avatarModelById(item.donorModelId).originalColors[part];
    }
  }
  return model.originalColors[part];
}

Object? _decodeJson(String? json) {
  if (json == null) return null;
  try {
    return jsonDecode(json);
  } on FormatException {
    return null;
  }
}

Map<String, List<String>> decodeAvatarOutfits(String? json) {
  final decoded = _decodeJson(json);
  if (decoded is! Map<String, dynamic>) return const {};
  final outfits = <String, List<String>>{};
  for (final model in avatarModels) {
    final values = decoded[model.id];
    if (values is! List) continue;
    final ids = equippedItems(
      model.id,
      values.whereType<String>(),
    ).map((item) => item.id).toList();
    if (ids.isNotEmpty) outfits[model.id] = List.unmodifiable(ids);
  }
  return Map.unmodifiable(outfits);
}

String encodeAvatarOutfits(Map<String, List<String>> outfits) => jsonEncode({
  for (final entry in outfits.entries)
    if (entry.value.isNotEmpty) entry.key: entry.value,
});

final _hexColor = RegExp(r'^#[0-9a-fA-F]{6}$');

Map<String, AvatarColors> decodeAvatarColorsWithOutfits(
  String? json,
  Map<String, List<String>> outfits,
) {
  final baseColors = decodeAvatarColorsMap(json);
  if (outfits.isEmpty) return baseColors;
  final decoded = _decodeJson(json);
  if (decoded is! Map<String, dynamic>) return baseColors;
  final colorsByModel = {...baseColors};
  for (final model in avatarModels) {
    final ids = outfits[model.id];
    final saved = decoded[model.id];
    if (ids == null || saved is! Map<String, dynamic>) continue;
    var colors = colorsByModel[model.id] ?? AvatarColors.empty;
    // The base codec handles all the model's original parts, including shoes.
    for (final part in effectiveParts(model, ids)) {
      if (model.parts.contains(part)) continue;
      final hex = saved[part.wireName];
      if (hex is String && hex.length == 7 && _hexColor.hasMatch(hex)) {
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

final avatarOutfitsProvider = StateProvider<Map<String, List<String>>>(
  (ref) => const {},
);
