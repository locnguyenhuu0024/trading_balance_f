import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trading_balance_f/core/timezone/app_time_zone.dart';
import 'package:trading_balance_f/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('web storage defaults a missing time-zone preference to UTC', () async {
    SharedPreferences.setMockInitialValues({});

    final preferences = await SharedPreferences.getInstance();
    final storage = WebStorageHelper(preferences);

    expect(await storage.getTimeZoneId(), AppTimeZone.defaultId);
  });

  test('web storage round-trips a supported time-zone ID', () async {
    SharedPreferences.setMockInitialValues({});

    final preferences = await SharedPreferences.getInstance();
    final storage = WebStorageHelper(preferences);

    await storage.saveTimeZoneId('Asia/Ho_Chi_Minh');

    expect(await storage.getTimeZoneId(), 'Asia/Ho_Chi_Minh');
  });

  test('web storage normalizes an unsupported time-zone ID to UTC', () async {
    SharedPreferences.setMockInitialValues({'TIME_ZONE_ID': 'Mars/Phobos'});

    final preferences = await SharedPreferences.getInstance();
    final storage = WebStorageHelper(preferences);

    expect(await storage.getTimeZoneId(), AppTimeZone.defaultId);
  });
}
