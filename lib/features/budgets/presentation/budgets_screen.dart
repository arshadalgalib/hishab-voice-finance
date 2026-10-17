import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../core/errors/app_exception.dart';
import '../../../domain/models/budget_progress.dart';
import 'budget_form_sheet.dart';

/// Lists every active budget with how much of its limit is already spent.
class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showBudgetFormSheet(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New budget'),
      ),
      body: AsyncView<List<BudgetProgress>>(
        value: ref.watch(budgetProgressProvider),
        loadingMessage: 'Loading budgets…',
        onRetry: () => ref.invalidate(budgetProgressProvider),
        isEmpty: (budgets) => budgets.isEmpty,
        empty: EmptyState(
          icon: Icons.savings_outlined,
          title: 'No budgets yet',
          message:
              'Set a spending limit and Hishab warns you before you cross it.',
          action: FilledButton.icon(
            onPressed: () => showBudgetFormSheet(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('New budget'),
          ),
        ),
        builder: (budgets) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          itemCount: budgets.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final progress = budgets[index];
            return _BudgetCard(
              progress: progress,
              onEdit: () =>
                  showBudgetFormSheet(context, ref, existing: progress),
              onDelete: () => _confirmDelete(context, ref, progress),
            );
          },
        ),
      ),
    );
  }
}

/// Asks for confirmation before removing a budget. Spending history is
/// untouched, so the destructive part is only the limit itself.
Future<void> _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  BudgetProgress progress,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete budget?'),
      content: Text(
        '"${progress.name}" will be removed. Your transactions stay unchanged.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await ref.read(budgetRepositoryProvider).delete(progress.budgetId);
    if (context.mounted) showAppMessage(context, 'Budget deleted.');
  } on AppException catch (error) {
    if (context.mounted) showAppMessage(context, error.message);
  }
}

enum _BudgetAction { edit, delete }

class _BudgetCard extends ConsumerWidget {
  const _BudgetCard({
    required this.progress,
    required this.onEdit,
    required this.onDelete,
  });

  final BudgetProgress progress;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final formatter = formatterFor(ref);
    // A saturated bar would overflow the track; a budget can be far over.
    final ratio = progress.ratio.clamp(0.0, 1.0).toDouble();
    final barColor = progress.isOverBudget
        ? AppColors.expense
        : (progress.hasReachedAlertThreshold
              ? AppColors.warning
              : AppColors.seed);
    final usedPercent = progress.percentUsed.clamp(0, 999).toStringAsFixed(0);

    return SectionCard(
      title: progress.name,
      action: PopupMenuButton<_BudgetAction>(
        tooltip: 'Budget actions',
        onSelected: (action) {
          if (action == _BudgetAction.edit) {
            onEdit();
          } else {
            onDelete();
          }
        },
        itemBuilder: (context) => const <PopupMenuEntry<_BudgetAction>>[
          PopupMenuItem<_BudgetAction>(
            value: _BudgetAction.edit,
            child: Text('Edit'),
          ),
          PopupMenuItem<_BudgetAction>(
            value: _BudgetAction.delete,
            child: Text('Delete'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${humanPeriodLabel(progress.period)} · '
            '${progress.categoryName ?? 'All categories'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              color: barColor,
              backgroundColor: barColor.withValues(alpha: 0.16),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              MoneyText(
                progress.spentPoisha,
                showSign: false,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(' of ', style: theme.textTheme.bodyMedium),
              MoneyText(
                progress.amountPoisha,
                showSign: false,
                style: theme.textTheme.bodyMedium,
              ),
              const Spacer(),
              Text(
                '$usedPercent% used',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            progress.isOverBudget
                ? '${formatter.format(progress.spentPoisha - progress.amountPoisha)} over budget'
                : '${formatter.format(progress.remainingPoisha)} left',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: progress.isOverBudget
                  ? AppColors.expense
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (progress.isOverBudget) ...[
            const SizedBox(height: 8),
            _WarningLine(
              icon: Icons.error_outline,
              color: AppColors.expense,
              message: 'You have crossed this budget.',
            ),
          ] else if (progress.hasReachedAlertThreshold) ...[
            const SizedBox(height: 8),
            _WarningLine(
              icon: Icons.warning_amber_rounded,
              color: AppColors.warning,
              message:
                  'You have used ${progress.alertThresholdPercent}% of this budget.',
            ),
          ],
        ],
      ),
    );
  }
}

class _WarningLine extends StatelessWidget {
  const _WarningLine({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
