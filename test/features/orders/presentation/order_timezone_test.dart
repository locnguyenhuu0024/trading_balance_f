import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/timezone/app_time_zone.dart';
import 'package:trading_balance_f/features/orders/presentation/orders_screen.dart';

void main() {
  setUpAll(AppTimeZone.initialize);

  test('formats order creation timestamps in the selected zone', () {
    final timestampMs = DateTime.utc(2026, 7, 1, 23, 30).millisecondsSinceEpoch;

    expect(
      formatOrderTimestamp(timestampMs.toString(), AppTimeZone.defaultId),
      '01/07/2026 23:30',
    );
    expect(
      formatOrderTimestamp(timestampMs.toString(), 'Asia/Ho_Chi_Minh'),
      '02/07/2026 06:30',
    );
  });

  test('keeps the placeholder for malformed order timestamps', () {
    expect(formatOrderTimestamp('', 'Asia/Ho_Chi_Minh'), '--');
    expect(formatOrderTimestamp('not-a-timestamp', 'Asia/Ho_Chi_Minh'), '--');
  });
}
