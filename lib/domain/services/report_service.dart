import 'package:meta/meta.dart';

import '../../core/utils/date_x.dart';
import '../../data/repositories/transaction_repository.dart';
import '../enums.dart';
import '../models/aggregates.dart';
import '../models/date_range.dart';
import '../models/transaction_filter.dart';

/// A complete picture of one period, assembled from the repository so the UI
/// never has to run several queries and stitch them together itself.
@immutable
class PeriodReport {
  const PeriodReport({
    required this.range,
    required this.summary,
    required this.expenseByCategory,
    required this.incomeByCategory,
    required this.trend,
    this.previousSummary,
  });

  final DateRange range;
  final PeriodSummary summary;

  /// Expense / income totals per category. `transfer` rows are never present
  /// here — internal movement is not a category of spending.
  final List<CategoryTotal> expenseByCategory;
  final List<CategoryTotal> incomeByCategory;

  /// Time buckets inside [range].
  final List<TrendPoint> trend;

  /// The immediately preceding window of the same length, for comparisons.
  final PeriodSummary? previousSummary;

  int get netPoisha => summary.netCashFlowPoisha;

  /// Change in spending vs the previous window. `null` when there is no
  /// comparable previous window (so the UI never shows "+∞%").
  double? get expenseChangeRatio {
    final previous = previousSummary;
    if (previous == null || previous.expensePoisha <= 0) return null;
    return (summary.expensePoisha - previous.expensePoisha) /
        previous.expensePoisha;
  }

  double? get incomeChangeRatio {
    final previous = previousSummary;
    if (previous == null || previous.incomePoisha <= 0) return null;
    return (summary.incomePoisha - previous.incomePoisha) /
        previous.incomePoisha;
  }

  /// The single largest expense category, if there is one.
  CategoryTotal? get topExpenseCategory {
    if (expenseByCategory.isEmpty) return null;
    final sorted = [...expenseByCategory]
      ..sort((a, b) => b.totalPoisha.compareTo(a.totalPoisha));
    final top = sorted.first;
    return top.totalPoisha <= 0 ? null : top;
  }

  /// Share of income kept (negative when spending exceeded income).
  double get savingRate {
    if (summary.incomePoisha <= 0) return 0;
    return (netPoisha / summary.incomePoisha).clamp(-1, 1);
  }
}

/// Read-only reporting.
///
/// Every number here is derived from the same `TransactionRepository` the rest
/// of the app uses, so a report can never disagree with the transaction list.
class ReportService {
  ReportService({required TransactionRepository transactions})
    : _transactions = transactions;

  final TransactionRepository _transactions;

  /// Builds the report for [range]. [bucketMonthly] controls whether the in-range
  /// trend is bucketed per month (good for a year) or per day (good for a
  /// month).
  Future<PeriodReport> reportFor(DateRange range, {bool? bucketMonthly}) async {
    final monthly = bucketMonthly ?? range.dayCount > 62;
    final summary = await _transactions.summary(range);
    final previous = await _transactions.summary(range.previousPeriod());
    final expenses = await _transactions
        .watchCategoryTotals(kind: CategoryKind.expense, range: range)
        .first;
    final incomes = await _transactions
        .watchCategoryTotals(kind: CategoryKind.income, range: range)
        .first;
    final trend = await _transactions
        .watchTrend(range: range, monthly: monthly)
        .first;

    return PeriodReport(
      range: range,
      summary: summary,
      previousSummary: previous,
      // Category rows with no spending in the window are noise.
      expenseByCategory: expenses
          .where((row) => row.totalPoisha > 0)
          .toList(growable: false),
      incomeByCategory: incomes
          .where((row) => row.totalPoisha > 0)
          .toList(growable: false),
      trend: trend,
    );
  }

  /// Rolling monthly income/expense for the last [months] calendar months,
  /// including the current one. Used by the dashboard chart.
  Future<List<TrendPoint>> monthlyTrend({int months = 6, DateTime? now}) async {
    final reference = now ?? DateTime.now();
    final start = startOfMonth(
      DateTime(reference.year, reference.month - (months - 1)),
    );
    final range = DateRange(start, endOfMonth(reference));
    return _transactions.watchTrend(range: range, monthly: true).first;
  }

  /// Count of every transaction in [range], including transfers. Used by the
  /// report footer to show that nothing was silently hidden.
  Future<int> transactionCount(DateRange range) =>
      _transactions.count(filter: TransactionFilter(range: range));
}
