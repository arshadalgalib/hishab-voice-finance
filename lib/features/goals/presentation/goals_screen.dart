import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/date_x.dart';
import '../../../domain/models/budget_progress.dart';
import 'goal_form_sheet.dart';

/// Savings goals, each card showing how close the user is to the target.
class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Savings goals')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showGoalFormSheet(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New goal'),
      ),
      body: AsyncView<List<GoalProgress>>(
        value: ref.watch(goalProgressProvider),
        loadingMessage: 'Loading goals…',
        onRetry: () => ref.invalidate(goalProgressProvider),
        empty: EmptyState(
          icon: Icons.savings_outlined,
          title: 'No savings goals yet',
          message: 'Set a target and start putting money aside.',
          action: FilledButton.icon(
            onPressed: () => showGoalFormSheet(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('New goal'),
          ),
        ),
        isEmpty: (goals) => goals.isEmpty,
        builder: (goals) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: goals.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) => _GoalCard(goal: goals[index]),
        ),
      ),
    );
  }
}

/// One goal, tappable through to its detail screen.
class _GoalCard extends ConsumerWidget {
  const _GoalCard({required this.goal});

  final GoalProgress goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final badgeLabel = goal.isCompleted
        ? 'Done'
        : (goal.isReached ? 'Reached' : null);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/goals/${goal.goalId}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      goal.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (badgeLabel != null) _StatusBadge(label: badgeLabel),
                  _GoalMenu(goal: goal),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: goal.ratio,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  MoneyText(
                    goal.savedPoisha,
                    showSign: false,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    ' of ',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  MoneyText(
                    goal.targetPoisha,
                    showSign: false,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    '${goal.percentComplete.toStringAsFixed(0)}% complete',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (goal.remainingPoisha > 0)
                    Text(
                      'Remaining ${formatterFor(ref).format(goal.remainingPoisha)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              if (goal.targetDate != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Target ${formatDate(goal.targetDate!)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The edit / delete menu shared by every goal card.
class _GoalMenu extends ConsumerWidget {
  const _GoalMenu({required this.goal});

  final GoalProgress goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_GoalAction>(
      tooltip: 'Goal actions',
      onSelected: (action) => _handle(context, ref, action),
      itemBuilder: (context) => const <PopupMenuEntry<_GoalAction>>[
        PopupMenuItem<_GoalAction>(
          value: _GoalAction.edit,
          child: Text('Edit'),
        ),
        PopupMenuItem<_GoalAction>(
          value: _GoalAction.delete,
          child: Text('Delete'),
        ),
      ],
    );
  }

  Future<void> _handle(
    BuildContext context,
    WidgetRef ref,
    _GoalAction action,
  ) async {
    switch (action) {
      case _GoalAction.edit:
        await showGoalFormSheet(context, ref, existing: goal);
      case _GoalAction.delete:
        final confirmed = await _confirmDeleteGoal(context, goal.name);
        if (!confirmed || !context.mounted) return;
        try {
          await ref.read(goalRepositoryProvider).delete(goal.goalId);
        } on AppException catch (error) {
          if (!context.mounted) return;
          showAppMessage(context, error.message);
        }
    }
  }
}

enum _GoalAction { edit, delete }

/// Confirms removing a goal. Wallet transfers already recorded stay put, so the
/// wording says so rather than implying the money comes back.
Future<bool> _confirmDeleteGoal(BuildContext context, String name) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete goal?'),
      content: Text(
        '“$name” will be removed. Wallet transfers already recorded are not '
        'reversed.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// A compact "Reached" / "Done" pill.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onSecondaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
