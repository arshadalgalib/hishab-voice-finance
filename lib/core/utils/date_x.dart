/// Date / time helpers used across the application.
///
/// The application stores *wall clock* local time for transactions plus a
/// derived `yyyy-MM-dd` day key used for indexed day-range queries. Keeping the
/// day key derived at the repository boundary means reporting never has to
/// re-implement timezone logic.
library;

import 'bengali_digits.dart';

const List<String> _englishMonths = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const List<String> _bengaliMonths = <String>[
  'জানুয়ারি',
  'ফেব্রুয়ারি',
  'মার্চ',
  'এপ্রিল',
  'মে',
  'জুন',
  'জুলাই',
  'আগস্ট',
  'সেপ্টেম্বর',
  'অক্টোবর',
  'নভেম্বর',
  'ডিসেম্বর',
];

const List<String> _shortEnglishMonths = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `yyyy-MM-dd`, always ASCII digits — this is the storage day key.
String dayKeyOf(DateTime date) {
  final d = date.toLocal();
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Parses a `yyyy-MM-dd` day key back to a local midnight [DateTime].
DateTime dateFromDayKey(String key) {
  final parts = key.split('-');
  if (parts.length != 3) {
    throw FormatException('Invalid day key', key);
  }
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

DateTime startOfDay(DateTime value) {
  final d = value.toLocal();
  return DateTime(d.year, d.month, d.day);
}

DateTime endOfDay(DateTime value) => startOfDay(
  value,
).add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));

DateTime startOfMonth(DateTime value) {
  final d = value.toLocal();
  return DateTime(d.year, d.month);
}

DateTime endOfMonth(DateTime value) {
  final d = value.toLocal();
  return DateTime(d.year, d.month + 1, 0, 23, 59, 59, 999);
}

DateTime startOfYear(DateTime value) {
  final d = value.toLocal();
  return DateTime(d.year);
}

/// Monday-based start of week (Bangladesh working week starts Sunday, but
/// ISO weeks keep reporting consistent and are labelled explicitly in the UI).
DateTime startOfWeek(DateTime value, {bool mondayFirst = true}) {
  final d = startOfDay(value);
  final weekday = mondayFirst ? DateTime.monday : DateTime.sunday;
  final delta = (d.weekday - weekday + 7) % 7;
  return d.subtract(Duration(days: delta));
}

/// True when both dates fall on the same calendar day.
bool isSameDay(DateTime a, DateTime b) => dayKeyOf(a) == dayKeyOf(b);

bool isSameMonth(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month;

/// Whole days between two local dates (b - a).
int daysBetween(DateTime a, DateTime b) =>
    startOfDay(b).difference(startOfDay(a)).inDays;

String monthName(int month, {bool bengali = false}) {
  final index = (month - 1).clamp(0, 11);
  return bengali ? _bengaliMonths[index] : _englishMonths[index];
}

String shortMonthName(int month) {
  final index = (month - 1).clamp(0, 11);
  return _shortEnglishMonths[index];
}

/// `12 Mar 2026` style date, with optional Bengali month names.
String formatDate(
  DateTime date, {
  bool bengaliMonths = false,
  bool bengaliDigits = false,
}) {
  final d = date.toLocal();
  final month = bengaliMonths
      ? monthName(d.month, bengali: true)
      : shortMonthName(d.month);
  final text = '${d.day} $month ${d.year}';
  return bengaliDigits ? toBengaliDigits(text) : text;
}

/// `12 Mar 2026, 4:35 PM` style date-time.
String formatDateTime(DateTime date, {bool bengaliMonths = false}) {
  final d = date.toLocal();
  final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  final period = d.hour < 12 ? 'AM' : 'PM';
  return '${formatDate(d, bengaliMonths: bengaliMonths)}, $hour12:$minute $period';
}

/// Groups a month key (`2026-03`) for budget period labels.
String monthKeyOf(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';

/// A human friendly "today / yesterday / 3 days ago" label used in the
/// transaction list headers.
String relativeDayLabel(DateTime date, {DateTime? now, bool bengali = false}) {
  final reference = now ?? DateTime.now();
  final diff = daysBetween(date, reference);
  if (diff == 0) return bengali ? 'আজ' : 'Today';
  if (diff == 1) return bengali ? 'গতকাল' : 'Yesterday';
  if (diff == -1) return bengali ? 'আগামীকাল' : 'Tomorrow';
  if (diff > 1 && diff < 7) {
    return bengali ? '$diff দিন আগে' : '$diff days ago';
  }
  return formatDate(date, bengaliMonths: bengali);
}
