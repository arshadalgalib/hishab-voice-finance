import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/date_x.dart';
import '../../../data/local/app_database.dart';
import '../../../data/repositories/reminder_repository.dart';

/// Lists bill / payment reminders, overdue ones first.
class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).now();
    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openNew(context),
        icon: const Icon(Icons.add),
        label: const Text('New reminder'),
      ),
      body: AsyncView<List<ReminderRow>>(
        value: ref.watch(remindersProvider),
        loadingMessage: 'Loading reminders…',
        isEmpty: (reminders) => reminders.isEmpty,
        empty: EmptyState(
          icon: Icons.notifications_none,
          title: 'No reminders yet',
          message: 'Track bills and payments and mark them paid as they clear.',
          action: FilledButton.icon(
            onPressed: () => _openNew(context),
            icon: const Icon(Icons.add),
            label: const Text('New reminder'),
          ),
        ),
        onRetry: () => ref.invalidate(remindersProvider),
        builder: (reminders) {
          final sorted = _sorted(reminders, now);
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: sorted.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final reminder = sorted[index];
              return _ReminderTile(
                reminder: reminder,
                overdue: ReminderRepository.isOverdue(reminder, now: now),
                onTap: () => _openEdit(context, reminder),
                onAction: (action) =>
                    _runAction(context, ref, reminder, action),
              );
            },
          );
        },
      ),
    );
  }

  /// Overdue first, then by due date, so the most urgent bill is always on top.
  static List<ReminderRow> _sorted(List<ReminderRow> reminders, DateTime now) {
    final sorted = [...reminders];
    sorted.sort((a, b) {
      final aOverdue = ReminderRepository.isOverdue(a, now: now);
      final bOverdue = ReminderRepository.isOverdue(b, now: now);
      if (aOverdue != bOverdue) return aOverdue ? -1 : 1;
      return a.dueDate.compareTo(b.dueDate);
    });
    return sorted;
  }

  static Future<void> _openNew(BuildContext context) async {
    await context.push<bool>('/reminders/new');
  }

  static Future<void> _openEdit(BuildContext context, ReminderRow reminder) {
    return context.push<bool>('/reminders/new', extra: reminder.id);
  }

  static Future<void> _runAction(
    BuildContext context,
    WidgetRef ref,
    ReminderRow reminder,
    _ReminderAction action,
  ) async {
    switch (action) {
      case _ReminderAction.markPaid:
      case _ReminderAction.markUnpaid:
        await _setPaid(context, ref, reminder);
      case _ReminderAction.delete:
        await _delete(context, ref, reminder);
    }
  }

  static Future<void> _setPaid(
    BuildContext context,
    WidgetRef ref,
    ReminderRow reminder,
  ) async {
    try {
      await ref
          .read(reminderRepositoryProvider)
          .markPaid(reminder.id, paid: !reminder.isPaid);
    } on AppException catch (error) {
      if (!context.mounted) return;
      showAppMessage(context, error.message);
    }
  }

  static Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ReminderRow reminder,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete reminder?'),
        content: Text('“${reminder.title}” will be removed.'),
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
      await ref.read(reminderRepositoryProvider).delete(reminder.id);
    } on AppException catch (error) {
      if (!context.mounted) return;
      showAppMessage(context, error.message);
    }
  }
}

enum _ReminderAction { markPaid, markUnpaid, delete }

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({
    required this.reminder,
    required this.overdue,
    required this.onTap,
    required this.onAction,
  });

  final ReminderRow reminder;
  final bool overdue;
  final VoidCallback onTap;
  final ValueChanged<_ReminderAction> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = overdue ? AppColors.warning : theme.colorScheme.primary;
    final note = reminder.note?.trim();
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: accent.withValues(alpha: 0.14),
          child: Icon(
            reminder.isPaid ? Icons.check : Icons.notifications_active_outlined,
            size: 20,
            color: accent,
          ),
        ),
        title: Text(
          reminder.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: reminder.isPaid
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    formatDateTime(reminder.dueDate),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (overdue) ...[
                  const SizedBox(width: 8),
                  Text(
                    'Overdue',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ] else if (reminder.isPaid) ...[
                  const SizedBox(width: 8),
                  Text(
                    'Paid',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
            if (note != null && note.isNotEmpty)
              Text(
                note,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (reminder.amountPoisha != null)
              MoneyText(reminder.amountPoisha!, showSign: false),
            PopupMenuButton<_ReminderAction>(
              tooltip: 'More actions',
              onSelected: onAction,
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: reminder.isPaid
                      ? _ReminderAction.markUnpaid
                      : _ReminderAction.markPaid,
                  child: Text(reminder.isPaid ? 'Mark unpaid' : 'Mark paid'),
                ),
                const PopupMenuItem(
                  value: _ReminderAction.delete,
                  child: Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
