import 'package:meta/meta.dart';

import '../../data/repositories/budget_repository.dart';
import '../models/budget_progress.dart';

/// A budget that has crossed a threshold and has not been announced yet.
@immutable
class BudgetAlert {
  const BudgetAlert({required this.progress, required this.thresholdPercent});

  final BudgetProgress progress;

  /// `100` for "the budget is used up", otherwise the budget's own threshold.
  final int thresholdPercent;

  bool get isOverBudget => thresholdPercent >= 100;

  String get title => isOverBudget
      ? 'Budget exceeded: ${progress.name}'
      : 'Budget alert: ${progress.name}';
}

/// Turns budget progress into *at most one* alert per threshold per period.
///
/// Nothing here repeats: each (budget, period, threshold) combination is
/// recorded in the `budget_alerts` table the first time it fires, so reopening
/// the app or reshuffling the dashboard cannot produce a second notification
/// for the same event.
class BudgetService {
  BudgetService({required BudgetRepository budgets}) : _budgets = budgets;

  final BudgetRepository _budgets;

  /// Alerts that still need to be shown, evaluated at [reference].
  Future<List<BudgetAlert>> pending({DateTime? reference}) async {
    final progressList = await _budgets.progressList(reference: reference);
    final alerts = <BudgetAlert>[];
    for (final progress in progressList) {
      if (!progress.isActive) continue;

      if (progress.isOverBudget) {
        final already = await _budgets.hasAlert(
          budgetId: progress.budgetId,
          periodKey: progress.periodKey,
          thresholdPercent: 100,
        );
        if (!already) {
          alerts.add(BudgetAlert(progress: progress, thresholdPercent: 100));
        }
        // The over-budget alert supersedes the threshold alert for this period.
        continue;
      }

      if (!progress.hasReachedAlertThreshold) continue;
      final already = await _budgets.hasAlert(
        budgetId: progress.budgetId,
        periodKey: progress.periodKey,
        thresholdPercent: progress.alertThresholdPercent,
      );
      if (!already) {
        alerts.add(
          BudgetAlert(
            progress: progress,
            thresholdPercent: progress.alertThresholdPercent,
          ),
        );
      }
    }
    return alerts;
  }

  /// Records that [alert] has been announced, so it never fires twice.
  Future<void> markAnnounced(BudgetAlert alert) => _budgets.recordAlert(
    budgetId: alert.progress.budgetId,
    periodKey: alert.progress.periodKey,
    thresholdPercent: alert.thresholdPercent,
  );

  /// Evaluates and records every pending alert, returning what was announced.
  /// Used on app start and after a transaction is saved.
  Future<List<BudgetAlert>> consumePending({DateTime? reference}) async {
    final alerts = await pending(reference: reference);
    for (final alert in alerts) {
      await markAnnounced(alert);
    }
    return alerts;
  }

  /// One-line status used by the budget list, e.g.
  /// "৳3,000 of ৳5,000 · 60% used".
  static String describe(BudgetProgress progress) {
    final percent = progress.percentUsed;
    final percentText = percent >= 100
        ? percent.toStringAsFixed(0)
        : percent.toStringAsFixed(0);
    return '${_taka(progress.spentPoisha)} of ${_taka(progress.amountPoisha)} '
        '· $percentText% used';
  }

  static String _taka(int poisha) {
    final whole = poisha ~/ 100;
    final fraction = poisha % 100;
    final grouped = _group(whole);
    return '৳$grouped'
        '${fraction == 0 ? '' : '.${fraction.toString().padLeft(2, '0')}'}';
  }

  static String _group(int value) {
    final digits = value.toString();
    if (digits.length <= 3) return digits;
    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '${parts.join(',')},$last3';
  }
}
