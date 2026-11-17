import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/core/widgets/app_motion.dart';
import 'package:trading_balance_f/features/fractal_tracker/data/fractal_model.dart';
import 'package:trading_balance_f/features/fractal_tracker/presentation/fractal_screen.dart';
import 'package:trading_balance_f/features/fractal_tracker/presentation/providers/fractal_provider.dart';
import 'package:trading_balance_f/features/tools/tools_screen.dart';
import 'package:trading_balance_f/main.dart' show WebStorageHelper;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('remaining screens use entrances and specified skeletons', () {
    const files = [
      'lib/features/strategy/presentation/strategy_screen.dart',
      'lib/features/support_resistance/presentation/support_resistance_screen.dart',
      'lib/features/tools/tools_screen.dart',
      'lib/features/settings/presentation/settings_screen.dart',
      'lib/features/connections/connections_screen.dart',
    ];
    for (final path in files) {
      final source = File(path).readAsStringSync();
      expect(source, contains('AppEntranceScope('), reason: path);
      expect(source, contains('AppEntrance('), reason: path);
    }
    for (final index in [0, 1, 4]) {
      expect(File(files[index]).readAsStringSync(), contains('AppSkeleton('));
    }
    for (final entry in {
      files[0]: 'Đang tải chiến thuật…',
      files[1]: 'Đang tải danh sách coin…',
    }.entries) {
      final source = File(entry.key).readAsStringSync();
      expect(
        source,
        matches(RegExp("AppSkeleton\\s*\\(\\s*caption: '${entry.value}'")),
      );
      expect(RegExp(RegExp.escape(entry.value)).allMatches(source).length, 1);
    }
  });

  testWidgets('tool entrances animate and retain navigation', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStorageProvider.overrideWithValue(
            WebStorageHelper(preferences),
          ),
          fractalDataProvider.overrideWith(
            (ref, scope) async => <FractalData>[],
          ),
        ],
        child: const MaterialApp(home: ToolsScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final entrances = find.byType(AppEntrance);
    expect(entrances, findsNWidgets(4));
    final transition = tester.widget<FadeTransition>(
      find
          .descendant(
            of: entrances.first,
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(transition.opacity.value, lessThan(1));
    await tester.pumpAndSettle();
    for (var index = 0; index < 4; index++) {
      final entrance = entrances.at(index);
      expect(tester.widget<AppEntrance>(entrance).index, index);
      final fade = tester.widget<FadeTransition>(
        find
            .descendant(of: entrance, matching: find.byType(FadeTransition))
            .first,
      );
      expect(fade.opacity.value, 1);
    }
    for (final title in [
      'BMAG',
      'Hỗ trợ / kháng cự',
      'Sàn & tài khoản',
      'Cài đặt',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    await tester.tap(find.text('BMAG'));
    await tester.pumpAndSettle();
    expect(find.byType(FractalScreen), findsOneWidget);
  });
}
