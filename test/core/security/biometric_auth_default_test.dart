import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trading_balance_f/core/navigation/navigation_preferences.dart';
import 'package:trading_balance_f/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'web storage disables biometric auth when no preference is saved',
    () async {
      SharedPreferences.setMockInitialValues({});

      final preferences = await SharedPreferences.getInstance();
      final storage = WebStorageHelper(preferences);

      expect(await storage.getBiometricAuth(), isFalse);
    },
  );

  test(
    'web storage preserves an explicitly enabled biometric preference',
    () async {
      SharedPreferences.setMockInitialValues({'BIO_AUTH': 'true'});

      final preferences = await SharedPreferences.getInstance();
      final storage = WebStorageHelper(preferences);

      expect(await storage.getBiometricAuth(), isTrue);
    },
  );

  test(
    'web storage uses safe navigation defaults when no record exists',
    () async {
      SharedPreferences.setMockInitialValues({});

      final preferences = await SharedPreferences.getInstance();
      final storage = WebStorageHelper(preferences);

      expect(
        await storage.getNavigationPreferences(),
        NavigationPreferences.defaults,
      );
    },
  );

  test(
    'web storage persists the complete navigation preference record',
    () async {
      SharedPreferences.setMockInitialValues({});

      final preferences = await SharedPreferences.getInstance();
      final storage = WebStorageHelper(preferences);
      const expected = NavigationPreferences(
        displayMode: NavigationDisplayMode.floating,
        floatingEdge: NavigationEdge.right,
      );

      await storage.saveNavigationPreferences(expected);

      expect(await storage.getNavigationPreferences(), expected);
    },
  );
}
