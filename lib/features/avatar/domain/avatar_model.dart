import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'avatar_colors.dart';

class AvatarModel {
  const AvatarModel({
    required this.id,
    required this.name,
    required this.file,
    required this.thumbnail,
    required this.credit,
    required this.licenseText,
    required this.parts,
    required this.originalColors,
  });

  final String id;
  final String name;
  final String file;
  final String thumbnail;
  final String credit;
  final String licenseText;
  final List<AvatarPart> parts;
  final Map<AvatarPart, Color> originalColors;
}

const defaultAvatarModelId = 'pixiv-sample';

const _commonParts = [
  AvatarPart.hair,
  AvatarPart.eyes,
  AvatarPart.top,
  AvatarPart.bottom,
  AvatarPart.shoes,
];

const avatarModels = [
  AvatarModel(
    id: defaultAvatarModelId,
    name: 'Pixiv Sample',
    parts: _commonParts,
    originalColors: {
      AvatarPart.hair: Color(0xff6d4b3a),
      AvatarPart.eyes: Color(0xff0f0904),
      AvatarPart.top: Color(0xfff8f6f6),
      AvatarPart.bottom: Color(0xff050505),
      AvatarPart.shoes: Color(0xff929aab),
    },
    file: 'pixiv-sample.vrm',
    thumbnail: 'assets/avatar/pixiv-sample.png',
    credit:
        'VRM1_Constraint_Twist_Sample © 2022 pixiv Inc. '
        '(VRM Public License 1.0)',
    licenseText:
        'VRM1_Constraint_Twist_Sample © 2022 pixiv Inc.\n\n'
        'Licensed under VRM Public License 1.0 (https://vrm.dev/licenses/1.0/).',
  ),
  AvatarModel(
    id: 'donut-chan',
    name: 'Donut-Chan',
    parts: [
      AvatarPart.hair,
      AvatarPart.eyes,
      AvatarPart.dress,
      AvatarPart.bows,
      AvatarPart.socks,
      AvatarPart.shoes,
      AvatarPart.plasters,
      AvatarPart.accessory,
    ],
    originalColors: {
      AvatarPart.hair: Color(0xffc4b68b),
      AvatarPart.eyes: Color(0xff415130),
      AvatarPart.dress: Color(0xfff7bdc0),
      AvatarPart.bows: Color(0xfff8a5b0),
      AvatarPart.socks: Color(0xfff5b4bd),
      AvatarPart.shoes: Color(0xfff0bec4),
      AvatarPart.plasters: Color(0xffd6cac6),
      AvatarPart.accessory: Color(0xffe5d9b6),
    },
    file: 'donut-chan.vrm',
    thumbnail: 'assets/avatar/donut-chan.png',
    credit: 'Donut-Chan by Kana Fuyuko (Public Domain)',
    licenseText: 'Donut-Chan by Kana Fuyuko. Public Domain.',
  ),
];

AvatarModel avatarModelById(String? id) {
  return avatarModels.firstWhere(
    (model) => model.id == id,
    orElse: () => avatarModels.first,
  );
}

final avatarModelIdProvider = StateProvider<String>(
  (ref) => defaultAvatarModelId,
);
