import 'package:flutter_riverpod/flutter_riverpod.dart';

class AvatarModel {
  const AvatarModel({
    required this.id,
    required this.name,
    required this.file,
    required this.thumbnail,
    required this.credit,
    required this.licenseText,
  });

  final String id;
  final String name;
  final String file;
  final String thumbnail;
  final String credit;
  final String licenseText;
}

const defaultAvatarModelId = 'pixiv-sample';

const avatarModels = [
  AvatarModel(
    id: defaultAvatarModelId,
    name: 'Pixiv Sample',
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
