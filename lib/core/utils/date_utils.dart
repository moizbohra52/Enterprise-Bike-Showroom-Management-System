import 'package:intl/intl.dart';

/// Date helpers shared by features and reports.
class DateUtils {
  DateUtils._();

  /// `dd MMM yyyy`, e.g. `12 Sep 2026`.
  static String format(DateTime? date) {
    if (date == null) return '-';
    return DateFormat('dd MMM yyyy').format(date);
  }

  /// `dd MMM yyyy HH:mm`.
  static String formatDateTime(DateTime? date) {
    if (date == null) return '-';
    return DateFormat('dd MMM yyyy HH:mm').format(date);
  }

  /// `HH:mm`.
  static String formatTime(DateTime? date) {
    if (date == null) return '-';
    return DateFormat('HH:mm').format(date);
  }

  /// `yyyy-MM-dd` (ISO date, safe for query params).
  static String isoDate(DateTime? date) {
    if (date == null) return '';
    return DateFormat('yyyy-MM-dd').format(date);
  }

  /// `yyyy-MM`.
  static String isoMonth(DateTime? date) {
    if (date == null) return '';
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}';
  }

  /// Month label, e.g. `Sep 2026`.
  static String monthLabel(DateTime? date) {
    if (date == null) return '-';
    return DateFormat('MMM yyyy').format(date);
  }

  static DateTime startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static DateTime endOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

  static DateTime startOfMonth(DateTime date) =>
      DateTime(date.year, date.month, 1);

  static DateTime endOfMonth(DateTime date) =>
      DateTime(date.year, date.month + 1, 0, 23, 59, 59, 999);

  static DateTime startOfYear(DateTime date) => DateTime(date.year, 1, 1);

  static DateTime addDays(DateTime date, int days) =>
      DateTime(date.year, date.month, date.day + days);

  /// Calendar-month addition (day clamped to month length).
  static DateTime addMonths(DateTime date, int months) {
    final int total = date.year * 12 + (date.month - 1) + months;
    final int year = (total / 12).floor();
    final int month = (total % 12) + 1;
    final int lastDay = DateTime(year, month + 1, 0).day;
    final int day = date.day > lastDay ? lastDay : date.day;
    return DateTime(year, month, day);
  }

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static bool isSameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  /// Whole days from `a` to `b` (negative when `b` is earlier).
  static int daysBetween(DateTime a, DateTime b) {
    final DateTime da = startOfDay(a);
    final DateTime db = startOfDay(b);
    return db.difference(da).inDays;
  }

  /// Days from today to `date` (negative when in the past).
  static int daysUntil(DateTime? date) {
    if (date == null) return 0;
    return daysBetween(DateTime.now(), date);
  }

  /// Inclusive list of months between `start` and `end`.
  static List<DateTime> monthsBetween(DateTime start, DateTime end) {
    final List<DateTime> months = <DateTime>[];
    DateTime cursor = DateTime(start.year, start.month, 1);
    final DateTime stop = DateTime(end.year, end.month, 1);
    while (!cursor.isAfter(stop)) {
      months.add(cursor);
      cursor = addMonths(cursor, 1);
    }
    return months;
  }

  /// Parses an ISO date (`yyyy-MM-dd`) or datetime; null-safe.
  static DateTime? parse(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return DateTime.tryParse(value.trim());
  }
}
