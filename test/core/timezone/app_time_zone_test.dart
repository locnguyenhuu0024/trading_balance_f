import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/timezone/app_time_zone.dart';

void main() {
  setUpAll(AppTimeZone.initialize);

  test('normalizes missing and unsupported IDs to UTC', () {
    expect(AppTimeZone.normalizeId(null), AppTimeZone.defaultId);
    expect(AppTimeZone.normalizeId('not/a-time-zone'), AppTimeZone.defaultId);
    expect(AppTimeZone.optionFor('Asia/Ho_Chi_Minh').label, 'Hồ Chí Minh');
  });

  test('converts one instant to the selected calendar zone', () {
    final instant = DateTime.utc(2026, 7, 1, 23, 30);

    final utc = AppTimeZone.now('Etc/UTC', instant: instant);
    final hoChiMinh = AppTimeZone.now('Asia/Ho_Chi_Minh', instant: instant);

    expect(utc.year, 2026);
    expect(utc.month, 7);
    expect(utc.day, 1);
    expect(utc.hour, 23);
    expect(utc.minute, 30);
    expect(utc.millisecondsSinceEpoch, instant.millisecondsSinceEpoch);
    expect(hoChiMinh.year, 2026);
    expect(hoChiMinh.month, 7);
    expect(hoChiMinh.day, 2);
    expect(hoChiMinh.hour, 6);
    expect(hoChiMinh.minute, 30);
    expect(hoChiMinh.millisecondsSinceEpoch, instant.millisecondsSinceEpoch);
  });

  test('builds selected-zone day, week, month, and year boundaries', () {
    final instant = DateTime.utc(2026, 7, 1, 16, 30);
    final day = AppTimeZone.currentDayRange(
      'Asia/Ho_Chi_Minh',
      instant: instant,
    );
    final week = AppTimeZone.currentWeekRange(
      'Asia/Ho_Chi_Minh',
      instant: instant,
    );
    final month = AppTimeZone.monthRange(
      'Asia/Ho_Chi_Minh',
      year: 2026,
      month: 7,
    );
    final year = AppTimeZone.yearRange('Asia/Ho_Chi_Minh', year: 2026);

    expect(
      day.startMillisecondsSinceEpoch,
      DateTime.utc(2026, 6, 30, 17).millisecondsSinceEpoch,
    );
    expect(
      day.endMillisecondsSinceEpoch,
      DateTime.utc(2026, 7, 1, 17).millisecondsSinceEpoch,
    );
    expect(
      week.startMillisecondsSinceEpoch,
      DateTime.utc(2026, 6, 28, 17).millisecondsSinceEpoch,
    );
    expect(
      week.endMillisecondsSinceEpoch,
      DateTime.utc(2026, 7, 5, 17).millisecondsSinceEpoch,
    );
    expect(
      month.startMillisecondsSinceEpoch,
      DateTime.utc(2026, 6, 30, 17).millisecondsSinceEpoch,
    );
    expect(
      month.endMillisecondsSinceEpoch,
      DateTime.utc(2026, 7, 31, 17).millisecondsSinceEpoch,
    );
    expect(
      year.startMillisecondsSinceEpoch,
      DateTime.utc(2025, 12, 31, 17).millisecondsSinceEpoch,
    );
    expect(
      year.endMillisecondsSinceEpoch,
      DateTime.utc(2026, 12, 31, 17).millisecondsSinceEpoch,
    );
  });

  test('honors daylight-saving transitions for IANA zones', () {
    final before = AppTimeZone.fromEpochMilliseconds(
      'America/New_York',
      DateTime.utc(2026, 3, 8, 6, 30).millisecondsSinceEpoch,
    );
    final after = AppTimeZone.fromEpochMilliseconds(
      'America/New_York',
      DateTime.utc(2026, 3, 8, 7, 30).millisecondsSinceEpoch,
    );

    expect(before.hour, 1);
    expect(before.timeZoneOffset, const Duration(hours: -5));
    expect(after.hour, 3);
    expect(after.timeZoneOffset, const Duration(hours: -4));
  });

  test('formats epoch timestamps in the selected zone', () {
    final timestampMs = DateTime.utc(2026, 7, 1, 23, 30).millisecondsSinceEpoch;

    expect(
      AppTimeZone.formatEpochMilliseconds('Etc/UTC', timestampMs),
      '01/07/2026 23:30',
    );
    expect(
      AppTimeZone.formatEpochMilliseconds('Asia/Ho_Chi_Minh', timestampMs),
      '02/07/2026 06:30',
    );
  });
}
