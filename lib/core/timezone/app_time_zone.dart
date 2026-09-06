// File Name: app_time_zone.dart
// File Path: lib/core/timezone/app_time_zone.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

@immutable
class AppTimeZoneOption {
  const AppTimeZoneOption({required this.id, required this.label});

  final String id;
  final String label;
}

@immutable
class AppTimeZoneRange {
  const AppTimeZoneRange({required this.start, required this.end});

  final timezone.TZDateTime start;
  final timezone.TZDateTime end;

  int get startMillisecondsSinceEpoch => start.millisecondsSinceEpoch;
  int get endMillisecondsSinceEpoch => end.millisecondsSinceEpoch;
}

/// Shared application time-zone catalog and conversion helpers.
abstract final class AppTimeZone {
  static const String defaultId = 'Etc/UTC';

  static const List<AppTimeZoneOption> options = [
    AppTimeZoneOption(id: 'Etc/UTC', label: 'UTC'),
    AppTimeZoneOption(id: 'Asia/Ho_Chi_Minh', label: 'Hồ Chí Minh'),
    AppTimeZoneOption(id: 'Asia/Singapore', label: 'Singapore'),
    AppTimeZoneOption(id: 'Asia/Tokyo', label: 'Tokyo'),
    AppTimeZoneOption(id: 'Asia/Kolkata', label: 'Kolkata'),
    AppTimeZoneOption(id: 'Europe/London', label: 'London'),
    AppTimeZoneOption(id: 'Europe/Paris', label: 'Paris'),
    AppTimeZoneOption(id: 'America/New_York', label: 'New York'),
    AppTimeZoneOption(id: 'America/Chicago', label: 'Chicago'),
    AppTimeZoneOption(id: 'America/Los_Angeles', label: 'Los Angeles'),
    AppTimeZoneOption(id: 'Australia/Sydney', label: 'Sydney'),
  ];

  static bool _isInitialized = false;
  static bool _initializationFailed = false;

  static bool get initializationFailed => _initializationFailed;

  /// Initializes the embedded IANA database exactly once per isolate.
  static void initialize() {
    if (_isInitialized) return;

    _isInitialized = true;
    try {
      if (timezone.timeZoneDatabase.locations.isEmpty) {
        timezone_data.initializeTimeZones();
      }
    } catch (_) {
      _initializationFailed = true;
    }
  }

  /// Returns a supported ID, falling back to UTC for unknown persisted data.
  static String normalizeId(String? id) {
    if (id == null) return defaultId;

    for (final option in options) {
      if (option.id == id) return option.id;
    }
    return defaultId;
  }

  static AppTimeZoneOption optionFor(String? id) {
    final normalizedId = normalizeId(id);
    return options.firstWhere((option) => option.id == normalizedId);
  }

  static timezone.Location locationFor(String? id) {
    initialize();
    if (_initializationFailed) return timezone.UTC;

    try {
      return timezone.getLocation(normalizeId(id));
    } catch (_) {
      return timezone.UTC;
    }
  }

  static timezone.TZDateTime fromEpochMilliseconds(
    String? id,
    int millisecondsSinceEpoch,
  ) {
    return timezone.TZDateTime.fromMillisecondsSinceEpoch(
      locationFor(id),
      millisecondsSinceEpoch,
    );
  }

  static timezone.TZDateTime now(String? id, {DateTime? instant}) {
    final source = instant ?? DateTime.now().toUtc();
    return timezone.TZDateTime.from(source, locationFor(id));
  }

  static AppTimeZoneRange dayRange(String? id, {required DateTime date}) {
    final location = locationFor(id);
    final start = timezone.TZDateTime(
      location,
      date.year,
      date.month,
      date.day,
    );
    final end = timezone.TZDateTime(
      location,
      date.year,
      date.month,
      date.day + 1,
    );
    return AppTimeZoneRange(start: start, end: end);
  }

  static AppTimeZoneRange currentDayRange(String? id, {DateTime? instant}) {
    return dayRange(id, date: now(id, instant: instant));
  }

  static AppTimeZoneRange currentWeekRange(String? id, {DateTime? instant}) {
    final location = locationFor(id);
    final localNow = now(id, instant: instant);
    final mondayOffset = localNow.weekday - DateTime.monday;
    final start = timezone.TZDateTime(
      location,
      localNow.year,
      localNow.month,
      localNow.day - mondayOffset,
    );
    final end = timezone.TZDateTime(
      location,
      start.year,
      start.month,
      start.day + DateTime.daysPerWeek,
    );
    return AppTimeZoneRange(start: start, end: end);
  }

  static AppTimeZoneRange monthRange(
    String? id, {
    required int year,
    required int month,
  }) {
    final location = locationFor(id);
    final start = timezone.TZDateTime(location, year, month);
    final end = timezone.TZDateTime(location, year, month + 1);
    return AppTimeZoneRange(start: start, end: end);
  }

  static AppTimeZoneRange yearRange(String? id, {required int year}) {
    final location = locationFor(id);
    final start = timezone.TZDateTime(location, year);
    final end = timezone.TZDateTime(location, year + 1);
    return AppTimeZoneRange(start: start, end: end);
  }

  static String formatEpochMilliseconds(
    String? id,
    int millisecondsSinceEpoch, {
    String pattern = 'dd/MM/yyyy HH:mm',
    String locale = 'en_US',
  }) {
    return DateFormat(
      pattern,
      locale,
    ).format(fromEpochMilliseconds(id, millisecondsSinceEpoch));
  }
}

final appTimeZoneProvider = StateProvider<String>(
  (ref) => AppTimeZone.defaultId,
);
