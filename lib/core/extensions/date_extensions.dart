import 'package:enterprise_bike_showroom/core/utils/date_utils.dart';

/// DateTime conveniences.
extension DateX on DateTime {
  String get dateLabel => DateUtils.format(this);
  String get dateTimeLabel => DateUtils.formatDateTime(this);
  String get timeLabel => DateUtils.formatTime(this);
  String get isoDay => DateUtils.isoDate(this);

  DateTime get startOfDay => DateUtils.startOfDay(this);
  DateTime get endOfDay => DateUtils.endOfDay(this);
  DateTime get startOfMonth => DateUtils.startOfMonth(this);
  DateTime get endOfMonth => DateUtils.endOfMonth(this);

  DateTime addDaysExt(int days) => DateUtils.addDays(this, days);
  DateTime addMonthsExt(int months) => DateUtils.addMonths(this, months);

  bool isToday() => DateUtils.isSameDay(this, DateTime.now());
  bool isSameDayAs(DateTime other) => DateUtils.isSameDay(this, other);
  bool isSameMonthAs(DateTime other) => DateUtils.isSameMonth(this, other);
  bool isBeforeDay(DateTime other) =>
      startOfDay.isBefore(other.startOfDay);
  bool isAfterDay(DateTime other) => startOfDay.isAfter(other.startOfDay);

  /// Whole days until `other` (negative when in the past).
  int daysUntil(DateTime other) => DateUtils.daysBetween(this, other);
  int daysAgo() => DateUtils.daysBetween(this, DateTime.now()).abs();

  /// `true` when inside [days] days of today (either side).
  bool isWithinDays(int days) {
    final int diff = DateUtils.daysBetween(DateTime.now(), this).abs();
    return diff <= days;
  }
}
