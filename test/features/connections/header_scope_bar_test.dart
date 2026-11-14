import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('screens place compact scope bars in their headers', () {
    for (final path in <String>[
      'lib/features/orders/presentation/orders_screen.dart',
      'lib/features/market/presentation/market_screen.dart',
      'lib/features/fractal_tracker/presentation/fractal_screen.dart',
      'lib/features/support_resistance/presentation/support_resistance_screen.dart',
      'lib/features/settings/presentation/settings_screen.dart',
      'lib/features/tools/tools_screen.dart',
      'lib/features/connections/scope_switch_gate.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('ScopeBar(compact: true)'), reason: path);
      expect(source, isNot(contains('ScopeBar()')), reason: path);
    }
  });
}
