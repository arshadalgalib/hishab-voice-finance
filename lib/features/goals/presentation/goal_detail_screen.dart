import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/date_x.dart';
import '../../../core/utils/money.dart';
import '../../../data/local/app_database.dart';
import '../../../domain/models/aggregates.dart';
import '../../../domain/models/budget_progress.dart';
import 'goal_form_sheet.dart';

/// Contributions are read straight from the repository. There is no shared
/// provider because the list is small and only this screen ever shows it; the
/// family key lets one screen own the refresh.
final _goalContributionsProvider =
    FutureProvider.family<List<GoalContributionRow>, String>(
      (ref, goalId) => ref.watch(goalRepositoryProvider).contributions(goalId),
    );

/// A single savings goal with its progress and contribution history.
class GoalDetailScreen extends ConsumerStatefulWidget {
  const GoalDetailScreen({super.key, required this.goalId});

  final String goalId;

  @override
  ConsumerState<GoalDetailScreen> createState() => _GoalDetailScreenState();
}

class _GoalDetailScreenState extends ConsumerState<GoalDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final goals = ref.watch(goalProgressProvider);
    final goal = _resolve(goals.value);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Goal'),
        actions: goal == null
            ? null
            : [
                PopupMenuButton<_GoalDetailAction>(
                  tooltip: 'Goal actions',
                  onSelected: (action) => _handleAction(action, goal),
                  itemBuilder: (context) =>
                      const <PopupMenuEntry<_GoalDetailAction>>[
                        PopupMenuItem<_GoalDetailAction>(
                          value: _GoalDetailAction.edit,
                          child: Text('Edit'),
                        ),
                        PopupMenuItem<_GoalDetailAction>(
                          value: _GoalDetailAction.delete,
                          child: Text('Delete goal'),
                        ),
                      ],
                ),
              ],
      ),
      body: AsyncView<List<GoalProgress>>(
        value: goals,
        loadingMessage: 'Loading goal…',
        onRetry: () => ref.invalidate(goalProgressProvider),
        builder: (list) {
          final resolved = _resolve(list);
          if (resolved == null) {
            // The id can vanish from the list after a delete; showing an empty
            // state is safer than dereferencing a missing goal.
            return const EmptyState(
              icon: Icons.savings_outlined,
              title: 'Goal not found',
              message: 'This savings goal was removed.',
            );
          }
          return _GoalDetailBody(goal: resolved);
        },
      ),
    );
  }

  /// Manual lookup so the screen does not depend on `package:collection`.
  GoalProgress? _resolve(List<GoalProgress>? goals) {
    if (goals == null) return null;
    for (final goal in goals) {
      if (goal.goalId == widget.goalId) return goal;
    }
    return null;
  }

  Future<void> _handleAction(
    _GoalDetailAction action,
    GoalProgress goal,
  ) async {
    switch (action) {
      case _GoalDetailAction.edit:
        await showGoalFormSheet(context, ref, existing: goal);
      case _GoalDetailAction.delete:
        final confirmed = await _confirmDeleteGoal(context, goal.name);
        if (!confirmed || !mounted) return;
        try {
          await ref.read(goalRepositoryProvider).delete(goal.goalId);
          if (!mounted) return;
          context.pop();
        } on AppException catch (error) {
          if (!mounted) return;
          showAppMessage(context, error.message);
        }
    }
  }
}

enum _GoalDetailAction { edit, delete }

/// Progress header, actions and contribution history for one goal.
class _GoalDetailBody extends ConsumerWidget {
  const _GoalDetailBody({required this.goal});

  final GoalProgress goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Full wallet list (including archived) so old contributions can still name
    // the wallet they came from.
    final wallets =
        ref.watch(walletBalancesProvider).value ?? const <WalletBalance>[];
    final contributions = ref.watch(_goalContributionsProvider(goal.goalId));
    final badgeLabel = goal.isCompleted
        ? 'Done'
        : (goal.isReached ? 'Reached' : null);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        SectionCard(
          title: 'Progress',
          action: badgeLabel == null ? null : _StatusBadge(label: badgeLabel),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  MoneyText(
                    goal.savedPoisha,
                    showSign: false,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    ' of ',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  MoneyText(
                    goal.targetPoisha,
                    showSign: false,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: goal.ratio,
                minHeight: 10,
                borderRadius: BorderRadius.circular(6),
              ),
              const SizedBox(height: 12),
              LabeledRow(
                label: 'Complete',
                value: '${goal.percentComplete.toStringAsFixed(0)}%',
              ),
              LabeledRow(
                label: 'Remaining',
                value: '',
                valueWidget: MoneyText(goal.remainingPoisha, showSign: false),
              ),
              if (goal.targetDate != null)
                LabeledRow(
                  label: 'Target date',
                  value: formatDate(goal.targetDate!),
                ),
              LabeledRow(
                label: 'Linked wallet',
                value: goal.walletName ?? 'None',
              ),
              if (goal.note != null && goal.note!.trim().isNotEmpty)
                LabeledRow(label: 'Note', value: goal.note!.trim()),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => _addContribution(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('Add contribution'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _toggleCompleted(context, ref),
          icon: Icon(
            goal.isCompleted ? Icons.replay : Icons.check_circle_outline,
          ),
          label: Text(goal.isCompleted ? 'Reopen goal' : 'Mark complete'),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Contributions',
          child: AsyncView<List<GoalContributionRow>>(
            value: contributions,
            loadingMessage: 'Loading contributions…',
            onRetry: () =>
                ref.invalidate(_goalContributionsProvider(goal.goalId)),
            empty: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No contributions recorded yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            isEmpty: (rows) => rows.isEmpty,
            builder: (rows) => Column(
              children: [
                for (final row in rows)
                  _ContributionTile(
                    contribution: row,
                    walletName: _walletName(wallets, row.fromWalletId),
                    onDelete: () => _removeContribution(context, ref, row),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _addContribution(BuildContext context, WidgetRef ref) async {
    final input = await showDialog<_ContributionInput>(
      context: context,
      builder: (context) => _ContributionDialog(goal: goal),
    );
    if (input == null) return;
    try {
      final result = await ref
          .read(goalServiceProvider)
          .contribute(
            goalId: goal.goalId,
            amountPoisha: input.amountPoisha,
            occurredAt: input.occurredAt,
            fromWalletId: input.fromWalletId,
          );
      if (!context.mounted) return;
      ref.invalidate(_goalContributionsProvider(goal.goalId));
      showAppMessage(
        context,
        result.goalCompleted
            ? 'Goal reached — well done!'
            : 'Contribution added.',
      );
    } on AppException catch (error) {
      if (!context.mounted) return;
      showAppMessage(context, error.message);
    }
  }

  Future<void> _toggleCompleted(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(goalServiceProvider)
          .setCompleted(goal.goalId, !goal.isCompleted);
      if (!context.mounted) return;
      showAppMessage(
        context,
        goal.isCompleted ? 'Goal reopened.' : 'Goal marked complete.',
      );
    } on AppException catch (error) {
      if (!context.mounted) return;
      showAppMessage(context, error.message);
    }
  }

  Future<void> _removeContribution(
    BuildContext context,
    WidgetRef ref,
    GoalContributionRow contribution,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete contribution?'),
        content: const Text(
          'If this contribution was funded from a wallet, the matching '
          'transfer is reversed too and the money returns to that wallet.',
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
    if (confirmed != true) return;
    try {
      await ref
          .read(goalServiceProvider)
          .removeContribution(
            goalId: goal.goalId,
            contributionId: contribution.id,
          );
      if (!context.mounted) return;
      ref.invalidate(_goalContributionsProvider(goal.goalId));
    } on AppException catch (error) {
      if (!context.mounted) return;
      showAppMessage(context, error.message);
    }
  }

  static String? _walletName(List<WalletBalance> wallets, String? walletId) {
    if (walletId == null) return null;
    for (final wallet in wallets) {
      if (wallet.walletId == walletId) return wallet.name;
    }
    return null;
  }
}

/// What the contribution dialog hands back to the screen.
class _ContributionInput {
  const _ContributionInput({
    required this.amountPoisha,
    required this.occurredAt,
    this.fromWalletId,
  });

  final int amountPoisha;
  final DateTime occurredAt;
  final String? fromWalletId;
}

class _ContributionDialog extends ConsumerStatefulWidget {
  const _ContributionDialog({required this.goal});

  final GoalProgress goal;

  @override
  ConsumerState<_ContributionDialog> createState() =>
      _ContributionDialogState();
}

class _ContributionDialogState extends ConsumerState<_ContributionDialog> {
  late final TextEditingController _amount;
  late DateTime _date;
  String? _walletId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController();
    _date = DateTime.now();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wallets =
        ref.watch(activeWalletBalancesProvider).value ??
        const <WalletBalance>[];
    final linkedWallet = widget.goal.walletName;
    return AlertDialog(
      title: const Text('Add contribution'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AmountField(
              controller: _amount,
              label: 'Amount',
              autofocus: true,
              errorText: _error,
            ),
            const SizedBox(height: 12),
            Text(
              linkedWallet == null
                  ? 'Choosing a source wallet records a real transfer out of '
                        'it. Without a linked wallet there is nowhere to move '
                        'the money to, so the contribution is just noted.'
                  : 'Money moved from a wallet into “$linkedWallet” is recorded '
                        'as a transfer, not as spending.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            WalletPickerField(
              wallets: wallets,
              value: _walletId,
              onChanged: (value) => setState(() => _walletId = value),
              label: 'Source wallet (optional)',
              helperText:
                  'Pick a wallet only if money really moved. The service then '
                  'records a transfer that changes wallet balances.',
            ),
            const SizedBox(height: 12),
            DateFieldButton(
              value: _date,
              onChanged: (value) => setState(() => _date = value),
              label: 'Date',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }

  void _submit() {
    final amount = Money.tryParse(_amount.text)?.poisha;
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }
    Navigator.pop(
      context,
      _ContributionInput(
        amountPoisha: amount,
        occurredAt: _date,
        fromWalletId: _walletId,
      ),
    );
  }
}

/// One contribution row with its source wallet when it is known.
class _ContributionTile extends StatelessWidget {
  const _ContributionTile({
    required this.contribution,
    required this.onDelete,
    this.walletName,
  });

  final GoalContributionRow contribution;
  final VoidCallback onDelete;
  final String? walletName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = <String>[
      formatDate(contribution.occurredAt),
      if (walletName != null) 'from $walletName',
    ];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.savings_outlined),
      title: MoneyText(contribution.amountPoisha, showSign: false),
      subtitle: Text(
        parts.join(' · '),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: IconButton(
        onPressed: onDelete,
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Delete contribution',
      ),
    );
  }
}

/// Confirms removing a goal; wallet transfers already recorded are not reversed.
Future<bool> _confirmDeleteGoal(BuildContext context, String name) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete goal?'),
      content: Text(
        '“$name” will be removed. Wallet transfers already recorded are not '
        'removed with the goal.',
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
