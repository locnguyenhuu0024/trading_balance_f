import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/avatar/domain/avatar_colors.dart';
import 'package:trading_balance_f/features/avatar/domain/avatar_model.dart';
import 'package:trading_balance_f/features/avatar/domain/avatar_outfit.dart';

const _pixiv = 'pixiv-sample';
const _outfit = 'donut-chan:outfit';
const _shoes = 'donut-chan:shoes';
const _plasters = 'donut-chan:plasters';

void main() {
  final model = avatarModelById(_pixiv);

  test('GREEN-156 effective parts retain order across all outfit slots', () {
    final cases = <List<String>, List<String>>{
      []: ['hair', 'eyes', 'top', 'bottom', 'shoes'],
      [_outfit]: ['hair', 'eyes', 'dress', 'bows', 'shoes'],
      [_shoes]: ['hair', 'eyes', 'top', 'bottom', 'shoes'],
      [_plasters]: ['hair', 'eyes', 'top', 'bottom', 'shoes', 'plasters'],
      [_plasters, _shoes, _outfit]: [
        'hair',
        'eyes',
        'dress',
        'bows',
        'shoes',
        'plasters',
      ],
    };
    for (final entry in cases.entries) {
      expect(
        effectiveParts(model, entry.key).map((part) => part.name),
        entry.value,
        reason: '${entry.key}',
      );
    }
    expect(itemsForModel('donut-chan'), isEmpty);
  });

  test('GREEN-156 borrowed parts use donor swatches', () {
    const items = [_outfit, _shoes, _plasters];
    const expected = {
      AvatarPart.hair: Color(0xff6d4b3a),
      AvatarPart.dress: Color(0xfff7bdc0),
      AvatarPart.bows: Color(0xfff8a5b0),
      AvatarPart.shoes: Color(0xfff0bec4),
      AvatarPart.plasters: Color(0xffd6cac6),
    };
    for (final entry in expected.entries) {
      expect(originalColorFor(model, items, entry.key), entry.value);
    }
    expect(
      originalColorFor(model, [], AvatarPart.shoes),
      const Color(0xff929aab),
    );
  });

  test('RED-156 malformed outfits and unavailable items are ignored', () {
    for (final input in [null, '{', '[]', '{"pixiv-sample":42}']) {
      expect(decodeAvatarOutfits(input), isEmpty);
    }
    expect(
      decodeAvatarOutfits(
        '{"unknown":["$_outfit"],"donut-chan":["$_shoes"],'
        '"$_pixiv":["unknown",null,"$_outfit","$_outfit","$_shoes","$_shoes"]}',
      ),
      {
        _pixiv: [_outfit, _shoes],
      },
    );
  });

  test('GREEN-156 outfit codec round trips and omits empty lists', () {
    const saved = {
      _pixiv: [_shoes, _outfit],
      'donut-chan': <String>[],
    };
    final json = encodeAvatarOutfits(saved);
    expect(json, '{"$_pixiv":["$_shoes","$_outfit"]}');
    expect(decodeAvatarOutfits(json), {
      _pixiv: [_shoes, _outfit],
    });
    expect(encodeAvatarOutfits({'donut-chan': []}), '{}');
  });
}
