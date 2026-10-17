import 'package:meta/meta.dart';

import '../../core/utils/date_x.dart';

/// Inclusive date range used by filters, reports and the dashboard.
@immutable
class DateRange {
  const DateRange(this.start, this.end);

  /// Inclusive lower bound (local midnight recommended).
  final DateTime start;

  /// Inclusive upper bound.
  final DateTime end;

  factory DateRange.day(DateTime day) =>
      DateRange(startOfDay(day), endOfDay(day));

  factory DateRange.days(DateTime from, DateTime to) =>
      DateRange(startOfDay(from), endOfDay(to));

  factory DateRange.month(DateTime month) =>
      DateRange(startOfMonth(month), endOfMonth(month));

  factory DateRange.year(DateTime year) => DateRange(
    startOfYear(year),
    DateTime(year.year, 12, 31, 23, 59, 59, 999),
  );

  factory DateRange.week(DateTime week) {
    final start = startOfWeek(week);
    return DateRange(start, endOfDay(start.add(const Duration(days: 6))));
  }

  factory DateRange.lastDays(int days, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    return DateRange(
      startOfDay(reference.subtract(Duration(days: days - 1))),
      endOfDay(reference),
    );
  }

  /// Rolling window ending *before* the current period, used for comparisons.
  DateRange previousPeriod() {
    final length = end.difference(start);
    final newEnd = start.subtract(const Duration(milliseconds: 1));
    return DateRange(newEnd.subtract(length), newEnd);
  }

  Duration get duration => end.difference(start);

  int get dayCount => daysBetween(start, end) + 1;

  bool contains(DateTime value) {
    final v = value.toLocal();
    return !v.isBefore(start) && !v.isAfter(end);
  }

  String get dayKeyStart => dayKeyOf(start);

  String get dayKeyEnd => dayKeyOf(end);

  String get label {
    final sameYear = start.year == end.year;
    final startText = sameYear
        ? '${start.day} ${shortMonthName(start.month)}'
        : formatDate(start);
    return '$startText – ${formatDate(end)}';
  }

  DateRange copyWith({DateTime? start, DateTime? end}) =>
      DateRange(start ?? this.start, end ?? this.end);

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'DateRange($dayKeyStart..$dayKeyEnd)';
}

/// Named presets shown in filter sheets.
enum DateRangePreset {
  today,
  yesterday,
  last7Days,
  thisWeek,
  thisMonth,
  lastMonth,
  last3Months,
  thisYear,
  allTime,
  custom,
}

DateRange resolvePreset(DateRangePreset preset, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  switch (preset) {
    case DateRangePreset.today:
      return DateRange.day(reference);
    case DateRangePreset.yesterday:
      return DateRange.day(reference.subtract(const Duration(days: 1)));
    case DateRangePreset.last7Days:
      return DateRange.lastDays(7, now: reference);
    case DateRangePreset.thisWeek:
      return DateRange.week(reference);
    case DateRangePreset.thisMonth:
      return DateRange.month(reference);
    case DateRangePreset.lastMonth:
      return DateRange.month(DateTime(reference.year, reference.month - 1));
    case DateRangePreset.last3Months:
      return DateRange(
        startOfMonth(DateTime(reference.year, reference.month - 2)),
        endOfMonth(reference),
      );
    case DateRangePreset.thisYear:
      return DateRange.year(reference);
    case DateRangePreset.allTime:
      return DateRange(DateTime(2000), DateTime(reference.year + 1, 12, 31));
    case DateRangePreset.custom:
      return DateRange.month(reference);
  }
}
