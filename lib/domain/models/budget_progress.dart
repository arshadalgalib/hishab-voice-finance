import 'package:meta/meta.dart';

import '../enums.dart';
import 'date_range.dart';

/// A budget joined with what has actually been spent inside its period.
///
/// Deliberately independent of the database row type so the presentation layer
/// never depends on Drift.
@immutable
class BudgetProgress {
  const BudgetProgress({
    required this.budgetId,
    required this.name,
    required this.amountPoisha,
    required this.spentPoisha,
    required this.period,
    required this.range,
    required this.periodKey,
    required this.alertThresholdPercent,
    this.categoryId,
    this.categoryName,
    this.colorValue,
    this.isActive = true,
  });

  final String budgetId;
  final String name;
  final int amountPoisha;
  final int spentPoisha;
  final BudgetPeriod period;
  final DateRange range;
  final String periodKey;
  final int alertThresholdPercent;

  /// `null` for an overall budget.
  final String? categoryId;
  final String? categoryName;
  final int? colorValue;
  final bool isActive;

  bool get isOverall => categoryId == null;

  int get remainingPoisha => amountPoisha - spentPoisha;

  double get ratio => amountPoisha <= 0 ? 0 : spentPoisha / amountPoisha;

  double get percentUsed => ratio * 100;

  bool get isOverBudget => spentPoisha > amountPoisha;

  bool get isOverAlertThreshold => percentUsed >= alertThresholdPercent;

  bool get hasReachedAlertThreshold => isOverAlertThreshold && !isOverBudget;
}

/// Progress of a savings goal.
@immutable
class GoalProgress {
  const GoalProgress({
    required this.goalId,
    required this.name,
    required this.targetPoisha,
    required this.savedPoisha,
    required this.isCompleted,
    this.targetDate,
    this.walletId,
    this.walletName,
    this.colorValue,
    this.note,
  });

  final String goalId;
  final String name;
  final int targetPoisha;
  final int savedPoisha;
  final bool isCompleted;
  final DateTime? targetDate;
  final String? walletId;
  final String? walletName;
  final int? colorValue;
  final String? note;

  int get remainingPoisha =>
      targetPoisha - savedPoisha < 0 ? 0 : targetPoisha - savedPoisha;

  double get ratio =>
      targetPoisha <= 0 ? 0 : (savedPoisha / targetPoisha).clamp(0, 1);

  double get percentComplete => ratio * 100;

  bool get isReached => savedPoisha >= targetPoisha;
}

/// Outstanding balance of a loan (money lent out or money borrowed).
@immutable
class LoanProgress {
  const LoanProgress({
    required this.loanId,
    required this.counterparty,
    required this.direction,
    required this.principalPoisha,
    required this.repaidPoisha,
    required this.occurredAt,
    this.dueDate,
    this.isSettled = false,
    this.note,
  });

  final String loanId;
  final String counterparty;
  final LoanDirection direction;
  final int principalPoisha;
  final int repaidPoisha;
  final DateTime occurredAt;
  final DateTime? dueDate;
  final bool isSettled;
  final String? note;

  int get outstandingPoisha =>
      principalPoisha - repaidPoisha < 0 ? 0 : principalPoisha - repaidPoisha;

  bool get isFullyRepaid => outstandingPoisha == 0;

  double get ratio =>
      principalPoisha <= 0 ? 0 : (repaidPoisha / principalPoisha).clamp(0, 1);
}
