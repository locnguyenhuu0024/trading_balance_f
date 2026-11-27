import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/avatar/domain/avatar_display.dart';

void main() {
  test('RED-158 invalid framing and scale values use safe defaults', () {
    for (final value in [null, '', 'unknown']) {
      expect(AvatarFraming.fromWire(value), AvatarFraming.full);
    }
    for (final value in [
      null,
      '',
      'large',
      true,
      double.nan,
      double.infinity,
    ]) {
      expect(AvatarScale.normalize(value), 100);
    }
  });

  test(
    'GREEN-158 framing and scale round trip and scale rounds and clamps',
    () {
      for (final framing in AvatarFraming.values) {
        expect(AvatarFraming.fromWire(framing.wireName), framing);
      }
      for (var percent = 60; percent <= 160; percent += 10) {
        expect(AvatarScale.normalize(percent.toString()), percent);
      }
      expect(AvatarScale.normalize(104.9), 100);
      expect(AvatarScale.normalize(' 105 '), 110);
      expect(AvatarScale.normalize(-10), 60);
      expect(AvatarScale.normalize(1e308), 160);
    },
  );
}
