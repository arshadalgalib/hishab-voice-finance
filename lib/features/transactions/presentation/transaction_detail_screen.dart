import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/labels.dart';
import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/date_x.dart';
import '../../../domain/enums.dart';
import '../../../domain/models/aggregates.dart';

/// Everything recorded about one transaction, plus the edit and delete actions.
///
/// Deleting goes through `TransactionService`, which returns the raw rows it
/// removed — including a transfer's linked fee row — so the undo below restores
/// exactly what was there rather than rebuilding an approximation.
class TransactionDetailScreen extends ConsumerWidget {
  const TransactionDetailScreen({super.key, required this.transactionId});

  final String transactionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(transactionDetailProvider(transactionId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () =>
                context.push('/transactions/new', extra: transactionId),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(context, ref),
          ),
        ],
      ),
      body: AsyncView<TransactionListItem?>(
        value: detail,
        loadingMessage: 'Loading transaction…',
        onRetry: () => ref.invalidate(transactionDetailProvider(transactionId)),
        isEmpty: (item) => item == null,
        empty: const EmptyState(
          icon: Icons.search_off,
          title: 'That transaction is no longer here',
          message: 'It may have been deleted from another screen.',
        ),
        builder: (item) => _DetailBody(item: item!),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this transaction?'),
        content: const Text(
          'Your wallet balances and reports update immediately. You can undo '
          'this straight afterwards.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final service = ref.read(transactionServiceProvider);
    final undo = ref.read(undoServiceProvider);
    try {
      final removed = await service.delete(transactionId);
      undo.push(
        description: 'Transaction deleted',
        undo: () => service.restoreRows(removed),
      );
      await ref.read(alertServiceProvider).announceBudgetAlerts();
      if (!context.mounted) return;
      showUndoSnackBar(context, ref, 'Transaction deleted');
      context.pop();
    } on AppException catch (error) {
      if (!context.mounted) return;
      showAppMessage(context, error.message);
    }
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.item});

  final TransactionListItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colour = AppColors.forType(item.type);
    final title = item.description?.trim().isNotEmpty == true
        ? item.description!.trim()
        : (item.categoryName ?? transactionTypeLabel(item.type));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        // Amount header. The sign and the type word carry the meaning together,
        // so the amount is never identified by colour alone.
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Icon(_iconFor(item.type), size: 40, color: colour),
              const SizedBox(height: 12),
              MoneyText(
                item.amountPoisha,
                type: item.type,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                transactionTypeLabel(item.type),
                style: theme.textTheme.titleSmall?.copyWith(color: colour),
              ),
              if (title != transactionTypeLabel(item.type)) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Details',
          child: Column(
            children: <Widget>[
              if (item.isTransfer)
                LabeledRow(label: 'From wallet', value: item.walletName)
              else
                LabeledRow(label: 'Wallet', value: item.walletName),
              if (item.isTransfer)
                LabeledRow(
                  label: 'To wallet',
                  value: item.toWalletName ?? 'Unknown',
                ),
              if (!item.isTransfer)
                LabeledRow(
                  label: 'Category',
                  value: item.categoryName ?? 'Uncategorised',
                ),
              if (item.isTransfer && item.feePoisha > 0)
                LabeledRow(
                  label: 'Transfer fee',
                  value: '',
                  valueWidget: MoneyText(item.feePoisha, showSign: false),
                ),
              LabeledRow(label: 'When', value: formatDateTime(item.occurredAt)),
              LabeledRow(
                label: 'Recorded',
                value: transactionSourceLabel(item.source),
              ),
              if (item.merchant != null && item.merchant!.trim().isNotEmpty)
                LabeledRow(label: 'Merchant', value: item.merchant!.trim()),
              if (item.counterparty != null &&
                  item.counterparty!.trim().isNotEmpty)
                LabeledRow(
                  label: item.type.isIncome ? 'From' : 'With',
                  value: item.counterparty!.trim(),
                ),
            ],
          ),
        ),
        if (item.note != null && item.note!.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          SectionCard(title: 'Note', child: Text(item.note!.trim())),
        ],
        if (item.tags.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          SectionCard(
            title: 'Tags',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final tag in item.tags) Chip(label: Text(tag)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (item.isTransfer)
          _Footnote(
            icon: Icons.swap_horiz,
            text:
                'A transfer moves money between your own wallets. It is never '
                'counted as income or expense.',
          )
        else
          _Footnote(
            icon: Icons.info_outline,
            text:
                'Balances and reports already reflect this transaction. Deleting '
                'it reverses the change.',
          ),
      ],
    );
  }

  static IconData _iconFor(TransactionType type) {
    switch (type) {
      case TransactionType.income:
        return Icons.south_west;
      case TransactionType.expense:
        return Icons.north_east;
      case TransactionType.transfer:
        return Icons.swap_horiz;
    }
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
