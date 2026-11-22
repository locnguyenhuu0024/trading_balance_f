enum AvatarMood {
  strongHappy,
  mildHappy,
  neutral,
  mildSad,
  strongSad;

  String get wireName => name;
}

AvatarMood avatarMoodFor(double? ratioPercent, {required bool hidden}) {
  if (hidden || ratioPercent == null || !ratioPercent.isFinite) {
    return AvatarMood.neutral;
  }
  if (ratioPercent >= 5) return AvatarMood.strongHappy;
  if (ratioPercent > 1) return AvatarMood.mildHappy;
  if (ratioPercent <= -5) return AvatarMood.strongSad;
  if (ratioPercent < -1) return AvatarMood.mildSad;
  return AvatarMood.neutral;
}
