import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/fractal_tracker/data/fractal_model.dart';
import 'package:trading_balance_f/features/fractal_tracker/presentation/fractal_screen.dart';
import 'package:trading_balance_f/features/fractal_tracker/presentation/providers/fractal_provider.dart';

FractalData _fractalDataWithPrices() {
  final firstQuarter = QuarterData('Q1')
    ..startTime = DateTime(2026, 1, 1)
    ..open = 123.4567
    ..close = 234.5678
    ..high = 1234567.89
    ..low = 0.00001234;
  final secondQuarter = QuarterData('Q2')..startTime = DateTime(2026, 1, 2);
  final thirdQuarter = QuarterData('Q3')..startTime = DateTime(2026, 1, 3);
  final fourthQuarter = QuarterData('Q4')..startTime = DateTime(2026, 1, 4);

  return FractalData(
    timeframeLabel: 'D1',
    quarters: [firstQuarter, secondQuarter, thirdQuarter, fourthQuarter],
    currentPrice: 0.09117,
  );
}

FractalData _fractalDataWithoutQuarterPrices() {
  return FractalData(
    timeframeLabel: 'D1',
    quarters: [
      QuarterData('Q1'),
      QuarterData('Q2'),
      QuarterData('Q3'),
      QuarterData('Q4'),
    ],
    currentPrice: 0.09117,
  );
}

Widget _screenWithData(FractalData data) {
  return ProviderScope(
    overrides: [
      fractalDataProvider.overrideWith((ref) async => [data]),
    ],
    child: const MaterialApp(home: FractalScreen()),
  );
}

void main() {
  testWidgets('formats Fractal current, open, high and low prices adaptively', (
    tester,
  ) async {
    await tester.pumpWidget(_screenWithData(_fractalDataWithPrices()));
    await tester.pump();
    await tester.pump();

    expect(find.text(r'$0.09117'), findsOneWidget);
    expect(find.text('Mở: 123.4567'), findsOneWidget);
    expect(find.text('🔥 1,234,567.89'), findsOneWidget);
    expect(find.text('💧 0.00001234'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('keeps missing Fractal quarter prices as placeholders', (
    tester,
  ) async {
    await tester.pumpWidget(
      _screenWithData(_fractalDataWithoutQuarterPrices()),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text(r'$0.09117'), findsOneWidget);
    expect(find.text('Mở: --'), findsOneWidget);
    expect(find.text('🔥 --'), findsOneWidget);
    expect(find.text('💧 --'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
