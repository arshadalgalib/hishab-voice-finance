import 'package:drift/drift.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/date_x.dart';
import '../../core/utils/id_generator.dart';
import '../../domain/enums.dart';
import '../../domain/models/budget_progress.dart';
import '../../domain/models/date_range.dart';
import '../local/app_database.dart';

/// Budget CRUD plus the period maths that turns a budget into spend/remaining.
class BudgetRepository {
  BudgetRepository({
    required AppDatabase db,
    required IdGenerator ids,
    required Clock clock,
  }) : _db = db,
       _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final IdGenerator _ids;
  final Clock _clock;

  Stream<List<BudgetRow>> watch({bool includeInactive = true}) =>
      _db.watchBudgets(includeInactive: includeInactive);

  Future<List<BudgetRow>> list({bool includeInactive = true}) =>
      _db.getBudgets(includeInactive: includeInactive);

  Future<String> create({
    required String name,
    required int amountPoisha,
    required BudgetPeriod period,
    required DateTime startDate,
    String? categoryId,
    DateTime? endDate,
    int alertThresholdPercent = 80,
    int? colorValue,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException(
        'Budget name is required.',
        field: 'name',
      );
    }
    if (amountPoisha <= 0) {
      throw const ValidationException(
        'Budget amount must be greater than zero.',
        field: 'amount',
      );
    }
    if (alertThresholdPercent < 1 || alertThresholdPercent > 100) {
      throw const ValidationException(
        'Alert threshold must be between 1% and 100%.',
        field: 'threshold',
      );
    }
    if (period == BudgetPeriod.custom && endDate == null) {
      throw const ValidationException(
        'A custom budget needs an end date.',
        field: 'endDate',
      );
    }
    final id = _ids.next();
    final now = _clock.now();
    await _db.upsertBudget(
      BudgetsCompanion.insert(
        id: id,
        name: trimmed,
        categoryId: Value(categoryId),
        amountPoisha: amountPoisha,
        period: period,
        startDate: startDate,
        endDate: Value(endDate),
        alertThresholdPercent: Value(alertThresholdPercent),
        colorValue: Value(colorValue),
        createdAt: now,
        updatedAt: now,
      ),
    );
    return id;
  }

  Future<void> update(
    String id, {
    String? name,
    int? amountPoisha,
    BudgetPeriod? period,
    DateTime? startDate,
    DateTime? endDate,
    bool clearEndDate = false,
    String? categoryId,
    bool clearCategory = false,
    int? alertThresholdPercent,
    bool? isActive,
    int? colorValue,
  }) async {
    final existing = await (_db.select(
      _db.budgets,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing == null) {
      throw const NotFoundException('That budget no longer exists.');
    }
    final resolvedAmount = amountPoisha ?? existing.amountPoisha;
    if (resolvedAmount <= 0) {
      throw const ValidationException(
        'Budget amount must be greater than zero.',
        field: 'amount',
      );
    }
    final threshold = alertThresholdPercent ?? existing.alertThresholdPercent;
    if (threshold < 1 || threshold > 100) {
      throw const ValidationException(
        'Alert threshold must be between 1% and 100%.',
        field: 'threshold',
      );
    }
    await _db.upsertBudget(
      BudgetsCompanion(
        id: Value(id),
        name: name == null ? const Value.absent() : Value(name.trim()),
        amountPoisha: Value(resolvedAmount),
        period: period == null ? const Value.absent() : Value(period),
        startDate: startDate == null ? const Value.absent() : Value(startDate),
        endDate: clearEndDate
            ? const Value(null)
            : (endDate == null ? const Value.absent() : Value(endDate)),
        categoryId: clearCategory
            ? const Value(null)
            : (categoryId == null ? const Value.absent() : Value(categoryId)),
        alertThresholdPercent: Value(threshold),
        isActive: isActive == null ? const Value.absent() : Value(isActive),
        colorValue: colorValue == null
            ? const Value.absent()
            : Value(colorValue),
        updatedAt: Value(_clock.now()),
      ),
    );
  }

  Future<void> delete(String id) => _db.deleteBudget(id);

  /// The concrete date window a budget covers for the period containing
  /// [reference]. Budget windows are recomputed rather than stored, so a
  /// monthly budget automatically rolls over.
  static DateRange periodRangeFor(
    BudgetRow budget, {
    required DateTime reference,
  }) {
    switch (budget.period) {
      case BudgetPeriod.weekly:
        return DateRange.week(reference);
      case BudgetPeriod.monthly:
        return DateRange.month(reference);
      case BudgetPeriod.quarterly:
        final quarterStartMonth = ((reference.month - 1) ~/ 3) * 3 + 1;
        return DateRange(
          DateTime(reference.year, quarterStartMonth),
          endOfMonth(DateTime(reference.year, quarterStartMonth + 2)),
        );
      case BudgetPeriod.yearly:
        return DateRange.year(reference);
      case BudgetPeriod.custom:
        final start = budget.startDate;
        final end = budget.endDate ?? endOfMonth(budget.startDate);
        return DateRange(startOfDay(start), endOfDay(end));
    }
  }

  /// Key that identifies one budget period, used to de-duplicate alerts.
  static String periodKeyFor(BudgetRow budget, DateRange range) {
    switch (budget.period) {
      case BudgetPeriod.monthly:
        return range.dayKeyStart.substring(0, 7);
      case BudgetPeriod.quarterly:
        return range.dayKeyStart.substring(0, 7);
      case BudgetPeriod.yearly:
        return range.dayKeyStart.substring(0, 4);
      case BudgetPeriod.weekly:
      case BudgetPeriod.custom:
        return range.dayKeyStart;
    }
  }

  Future<bool> hasAlert({
    required String budgetId,
    required String periodKey,
    required int thresholdPercent,
  }) => _db.hasBudgetAlert(
    budgetId: budgetId,
    periodKey: periodKey,
    thresholdPercent: thresholdPercent,
  );

  Future<void> recordAlert({
    required String budgetId,
    required String periodKey,
    required int thresholdPercent,
  }) async {
    await _db.recordBudgetAlert(
      BudgetAlertsCompanion.insert(
        id: _ids.next(),
        budgetId: budgetId,
        periodKey: periodKey,
        thresholdPercent: thresholdPercent,
        notifiedAt: _clock.now(),
      ),
    );
    await _db.pruneBudgetAlerts(budgetId, keepPeriodKey: periodKey);
  }

  /// Snapshot of a budget's progress for the period containing [reference].
  Future<BudgetProgress> progressFor(
    BudgetRow budget, {
    required DateTime reference,
  }) async {
    final range = periodRangeFor(budget, reference: reference);
    final spent = await _db.expenseTotalForBudget(
      range: range,
      categoryId: budget.categoryId,
    );
    String? categoryName;
    if (budget.categoryId != null) {
      categoryName = (await _db.findCategoryById(budget.categoryId!))?.name;
    }
    return BudgetProgress(
      budgetId: budget.id,
      name: budget.name,
      amountPoisha: budget.amountPoisha,
      spentPoisha: spent,
      period: budget.period,
      range: range,
      periodKey: periodKeyFor(budget, range),
      alertThresholdPercent: budget.alertThresholdPercent,
      categoryId: budget.categoryId,
      categoryName: categoryName,
      colorValue: budget.colorValue,
      isActive: budget.isActive,
    );
  }

  /// Progress for every budget, ordered with the most urgent first.
  Future<List<BudgetProgress>> progressList({DateTime? reference}) async {
    final now = reference ?? _clock.now();
    final budgets = await list(includeInactive: false);
    final result = <BudgetProgress>[];
    for (final budget in budgets) {
      result.add(await progressFor(budget, reference: now));
    }
    result.sort((a, b) => b.percentUsed.compareTo(a.percentUsed));
    return result;
  }

  Stream<List<BudgetProgress>> watchProgressList({DateTime? reference}) {
    final now = reference ?? _clock.now();
    return watch(includeInactive: false).asyncMap((budgets) async {
      final result = <BudgetProgress>[];
      for (final budget in budgets) {
        result.add(await progressFor(budget, reference: now));
      }
      result.sort((a, b) => b.percentUsed.compareTo(a.percentUsed));
      return result;
    });
  }
}
