import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/typography/app_text_scale.dart';
import 'package:trading_balance_f/main.dart';

void main() {
  test('normalizes missing, malformed, and unsupported values safely', () {
    expect(AppTextScale.normalize(null), AppTextScale.defaultScale);
    expect(AppTextScale.normalize('not-a-scale'), AppTextScale.defaultScale);
    expect(AppTextScale.normalize(2.0), AppTextScale.defaultScale);
    expect(AppTextScale.normalize(1.05), AppTextScale.defaultScale);
    expect(AppTextScale.normalize(0.9), 0.9);
    expect(AppTextScale.normalize('1.15'), 1.15);
  });

  test('multiplies the app preference on top of platform text scaling', () {
    final combined = AppTextScale.combine(const TextScaler.linear(1.25), 1.15);

    expect(combined.scale(10), closeTo(14.375, 0.0001));
  });

  testWidgets('applies the selected scale at the application root', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appTextScaleProvider.overrideWith((ref) => 1.15)],
        child: const TradingBalanceApp(
          requireBiometrics: false,
          home: Text('Scaled content', key: Key('scaled-content')),
        ),
      ),
    );

    final mediaQuery = MediaQuery.of(
      tester.element(find.byKey(const Key('scaled-content'))),
    );
    expect(mediaQuery.textScaler.scale(10), closeTo(11.5, 0.0001));
  });
}
