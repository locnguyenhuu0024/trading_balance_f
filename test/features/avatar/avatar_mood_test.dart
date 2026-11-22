import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/avatar/avatar_licenses.dart';
import 'package:trading_balance_f/features/avatar/domain/avatar_mood.dart';

void main() {
  test(
    'RED-147 hidden, missing, non-finite and near-zero ratios are neutral',
    () {
      expect(avatarMoodFor(6, hidden: true), AvatarMood.neutral);
      for (final ratio in [
        null,
        double.nan,
        double.infinity,
        double.negativeInfinity,
        0.5,
        1.0,
        -1.0,
      ]) {
        expect(avatarMoodFor(ratio, hidden: false), AvatarMood.neutral);
      }
    },
  );

  test('GREEN-147 mood boundaries and wire names', () {
    final cases = {
      1.0001: AvatarMood.mildHappy,
      4.99: AvatarMood.mildHappy,
      5.0: AvatarMood.strongHappy,
      12.0: AvatarMood.strongHappy,
      -1.0001: AvatarMood.mildSad,
      -4.99: AvatarMood.mildSad,
      -5.0: AvatarMood.strongSad,
      -20.0: AvatarMood.strongSad,
    };

    for (final entry in cases.entries) {
      expect(avatarMoodFor(entry.key, hidden: false), entry.value);
    }
    expect(AvatarMood.values.map((mood) => mood.wireName), [
      'strongHappy',
      'mildHappy',
      'neutral',
      'mildSad',
      'strongSad',
    ]);
  });

  test('GREEN-147 registers each avatar license once', () async {
    registerAvatarLicenses();
    registerAvatarLicenses();

    final packages = await LicenseRegistry.licenses
        .expand((entry) => entry.packages)
        .toList();

    for (final package in [
      'three.js',
      '@pixiv/three-vrm',
      'Pixiv Sample (VRM model)',
      'Donut-Chan (VRM model)',
    ]) {
      expect(packages.where((name) => name == package), hasLength(1));
    }
  });
}
