import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/avatar/avatar_licenses.dart';
import 'package:trading_balance_f/features/avatar/domain/avatar_colors.dart';
import 'package:trading_balance_f/features/avatar/domain/avatar_model.dart';

void main() {
  test('GREEN-154 the catalog lists customizable parts for each model', () {
    final pixiv = avatarModelById('pixiv-sample');
    expect(pixiv.parts, [
      AvatarPart.hair,
      AvatarPart.eyes,
      AvatarPart.top,
      AvatarPart.bottom,
      AvatarPart.shoes,
    ]);
    expect(avatarModelById('donut-chan').parts, [
      AvatarPart.hair,
      AvatarPart.eyes,
      AvatarPart.dress,
      AvatarPart.bows,
      AvatarPart.socks,
      AvatarPart.shoes,
      AvatarPart.plasters,
      AvatarPart.accessory,
    ]);
    expect(pixiv.originalColors, {
      AvatarPart.hair: const Color(0xff6d4b3a),
      AvatarPart.eyes: const Color(0xff0f0904),
      AvatarPart.top: const Color(0xfff8f6f6),
      AvatarPart.bottom: const Color(0xff050505),
      AvatarPart.shoes: const Color(0xff929aab),
    });
    for (final model in avatarModels) {
      expect(model.originalColors.keys, unorderedEquals(model.parts));
    }
  });

  test('RED-150 unknown and missing ids fall back to Pixiv Sample', () {
    for (final id in [null, '', '../donut-chan', 'DONUT-CHAN', 'unknown']) {
      final model = avatarModelById(id);
      expect(model.id, 'pixiv-sample');
      expect(model.file, 'pixiv-sample.vrm');
    }
  });

  test(
    'GREEN-150 the catalog resolves Donut-Chan and registers both models',
    () async {
      final model = avatarModelById('donut-chan');
      expect(model.name, 'Donut-Chan');
      expect(model.file, 'donut-chan.vrm');
      expect(model.thumbnail, 'assets/avatar/donut-chan.png');

      registerAvatarLicenses();
      registerAvatarLicenses();
      final names = await LicenseRegistry.licenses
          .expand((entry) => entry.packages)
          .toList();
      for (final name in [
        'Pixiv Sample (VRM model)',
        'Donut-Chan (VRM model)',
      ]) {
        expect(names.where((package) => package == name), hasLength(1));
      }
    },
  );
}
