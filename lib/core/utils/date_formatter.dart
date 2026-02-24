import 'package:intl/intl.dart';

/// Date/time formatting utilities for Indian locale.
///
/// Examples:
/// - `formatDate(today)` → `"Today"`
/// - `formatDate(yesterday)` → `"Yesterday"`
/// - `formatDate(otherDate)` → `"24 Feb 2026"`
/// - `formatTime(dateTime)` → `"6:30 PM"`
class DateFormatter {
  DateFormatter._();

  static final _fullDate = DateFormat('d MMM yyyy');
  static final _shortDate = DateFormat('d MMM');
  static final _time = DateFormat('h:mm a');
  static final _monthYear = DateFormat('MMMM yyyy');
  static final _dayMonth = DateFormat('d MMM');
  static final _isoDate = DateFormat('yyyy-MM-dd');

  /// Formats with relative labels: Today, Yesterday, or "24 Feb 2026"
  static String format(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(date.year, date.month, date.day);

    if (dateOnly == today) return 'Today';
    if (dateOnly == today.subtract(const Duration(days: 1))) return 'Yesterday';
    if (date.year == now.year) return _shortDate.format(date);
    return _fullDate.format(date);
  }

  /// Full date format: "24 Feb 2026"
  static String formatFull(DateTime date) => _fullDate.format(date);

  /// Time format: "6:30 PM"
  static String formatTime(DateTime date) => _time.format(date);

  /// Date and time: "24 Feb 2026, 6:30 PM"
  static String formatDateTime(DateTime date) {
    return '${format(date)}, ${formatTime(date)}';
  }

  /// Month and year: "February 2026"
  static String formatMonthYear(DateTime date) => _monthYear.format(date);

  /// Day and month: "24 Feb"
  static String formatDayMonth(DateTime date) => _dayMonth.format(date);

  /// ISO format for database: "2026-02-24"
  static String formatIso(DateTime date) => _isoDate.format(date);

  /// Parse ISO date string to DateTime
  static DateTime parseIso(String dateString) => DateTime.parse(dateString);
}
