import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/avatar/avatar_licenses.dart';
import 'package:trading_balance_f/features/avatar/domain/avatar_colors.dart';
import 'package:trading_balance_f/features/avatar/domain/avatar_model.dart';

void main() {
  test('GREEN-152 the catalog lists customizable parts for each model', () {
    const common = [
      AvatarPart.hair,
      AvatarPart.eyes,
      AvatarPart.top,
      AvatarPart.bottom,
      AvatarPart.shoes,
    ];
    expect(avatarModelById('pixiv-sample').parts, common);
    expect(avatarModelById('donut-chan').parts, [
      ...common,
      AvatarPart.accessory,
    ]);
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
