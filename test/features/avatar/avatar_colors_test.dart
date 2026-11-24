import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/avatar/domain/avatar_colors.dart';

void main() {
  test('RED-152 rejects corrupt JSON and non-object roots', () {
    for (final json in [null, 'not json', '[]', 'null', '42']) {
      expect(decodeAvatarColorsMap(json), isEmpty, reason: '$json');
    }
  });

  test('RED-152 drops unknown models, unsupported parts, and bad hex', () {
    final decoded = decodeAvatarColorsMap('''
      {
        "unknown-model": {"hair": "#005500"},
        "pixiv-sample": {
          "hair": "#00ABcd", "eyes": "123456", "top": "#123",
          "bottom": "#12345g", "shoes": 123456, "lips": "#aa0000",
          "accessory": "#ffffff"
        },
        "donut-chan": ["#aaaaaa"]
      }
    ''');
    expect(decoded.keys, ['pixiv-sample']);
    expect(decoded['pixiv-sample']!.toJson(), {'hair': '#00abcd'});
  });

  test('GREEN-152 round-trips per-model colours with value equality', () {
    const purple = Color(0xffa020f0);
    const orange = Color(0xffff8200);
    final hair = AvatarColors.empty.withPart(AvatarPart.hair, purple);
    final both = hair.withPart(AvatarPart.accessory, orange);
    final reordered = AvatarColors.empty
        .withPart(AvatarPart.accessory, orange)
        .withPart(AvatarPart.hair, purple);

    expect(both, reordered);
    expect(both.hashCode, reordered.hashCode);
    expect(both.withoutPart(AvatarPart.accessory), hair);
    expect(both.restrictTo([AvatarPart.hair]), hair);
    expect(hair.restrictTo([AvatarPart.eyes]), AvatarColors.empty);
    expect(hair, isNot(both));

    final original = {'pixiv-sample': hair, 'donut-chan': both};
    final encoded = encodeAvatarColorsMap(original);
    expect(
      encoded,
      '{"pixiv-sample":{"hair":"#a020f0"},'
      '"donut-chan":{"hair":"#a020f0","accessory":"#ff8200"}}',
    );
    expect(decodeAvatarColorsMap(encoded), original);
  });
}
