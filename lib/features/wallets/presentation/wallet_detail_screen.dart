import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/labels.dart';
import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/money.dart';
import '../../../domain/models/aggregates.dart';
import '../../../domain/models/transaction_filter.dart';

/// Everything that counts towards one wallet's balance.
final _walletTransactionsProvider =
    StreamProvider.family<List<TransactionListItem>, String>((ref, walletId) {
      return ref
          .watch(transactionRepositoryProvider)
          .watch(TransactionFilter(walletIds: <String>{walletId}), limit: 200);
    });

class WalletDetailScreen extends ConsumerWidget {
  const WalletDetailScreen({super.key, required this.walletId});

  final String walletId;

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on AppException catch (error) {
      if (!context.mounted) return;
      showAppMessage(context, error.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallets = ref.watch(walletBalancesProvider);
    return AsyncView<List<WalletBalance>>(
      value: wallets,
      onRetry: () => ref.invalidate(walletBalancesProvider),
      builder: (list) {
        WalletBalance? wallet;
        for (final candidate in list) {
          if (candidate.walletId == walletId) {
            wallet = candidate;
            break;
          }
        }
        final found = wallet;
        if (found == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Wallet')),
            body: const EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'That wallet no longer exists',
              message: 'It may have been deleted on another screen.',
            ),
          );
        }
        return _WalletDetail(wallet: found, run: _run);
      },
    );
  }
}

class _WalletDetail extends ConsumerWidget {
  const _WalletDetail({required this.wallet, required this.run});

  final WalletBalance wallet;
  final Future<void> Function(BuildContext, Future<void> Function()) run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final accent = Color(wallet.colorValue ?? AppColors.seed.toARGB32());
    final transactions = ref.watch(
      _walletTransactionsProvider(wallet.walletId),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(wallet.name),
        actions: <Widget>[
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'edit':
                  await context.push<String?>(
                    '/wallets/new',
                    extra: wallet.walletId,
                  );
                case 'opening':
                  await _adjustOpeningBalance(context, ref);
                case 'archive':
                  await run(
                    context,
                    () => ref
                        .read(walletRepositoryProvider)
                        .setArchived(wallet.walletId, !wallet.isArchived),
                  );
                case 'delete':
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text('Delete “${wallet.name}”?'),
                      content: const Text(
                        'Deleting only works when nothing references the '
                        'wallet. Archive it to keep the history and the '
                        'reports intact.',
                      ),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  if (!context.mounted) return;
                  await run(context, () async {
                    await ref
                        .read(walletRepositoryProvider)
                        .deleteWallet(wallet.walletId);
                    if (context.mounted) context.pop();
                  });
              }
            },
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'edit',
                child: Text('Edit details'),
              ),
              const PopupMenuItem<String>(
                value: 'opening',
                child: Text('Adjust opening balance'),
              ),
              PopupMenuItem<String>(
                value: 'archive',
                child: Text(wallet.isArchived ? 'Unarchive' : 'Archive'),
              ),
              const PopupMenuItem<String>(
                value: 'delete',
                child: Text('Delete wallet'),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      CircleAvatar(
                        backgroundColor: accent.withValues(alpha: 0.14),
                        child: Icon(
                          WalletIcons.resolve(wallet.type),
                          size: 20,
                          color: accent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              <String>[
                                walletTypeLabel(wallet.type),
                                if (wallet.institution != null &&
                                    wallet.institution!.trim().isNotEmpty)
                                  wallet.institution!.trim(),
                              ].join(' · '),
                              style: theme.textTheme.bodyMedium,
                            ),
                            if (wallet.isArchived)
                              Text(
                                'Archived — cannot be used for new entries',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.warning,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (wallet.isDefaultIncome || wallet.isDefaultExpense)
                        const Icon(
                          Icons.star,
                          size: 18,
                          color: AppColors.warning,
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'CURRENT BALANCE',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  MoneyText(
                    wallet.balancePoisha,
                    showSign: false,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  LabeledRow(
                    label: 'Opening balance',
                    value: '',
                    valueWidget: MoneyText(
                      wallet.openingBalancePoisha,
                      showSign: false,
                    ),
                  ),
                  LabeledRow(
                    label: 'Money in',
                    value: '',
                    valueWidget: MoneyText(
                      wallet.inflowPoisha,
                      showSign: false,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.income,
                      ),
                    ),
                  ),
                  LabeledRow(
                    label: 'Money out',
                    value: '',
                    valueWidget: MoneyText(
                      wallet.outflowPoisha,
                      showSign: false,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.expense,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'The balance is always derived: opening balance plus '
                      'money in, minus money out. Nothing is stored twice, so '
                      'the figure can never drift from the records.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (wallet.note != null &&
                      wallet.note!.trim().isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(wallet.note!, style: theme.textTheme.bodySmall),
                  ],
                  const SizedBox(height: 8),
                  if (!wallet.isArchived)
                    OutlinedButton.icon(
                      onPressed: () =>
                          context.push('/transactions/new?type=expense'),
                      icon: const Icon(Icons.add),
                      label: const Text('Record a transaction'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'MOVEMENTS IN THIS WALLET',
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
            child: AsyncView<List<TransactionListItem>>(
              value: transactions,
              onRetry: () =>
                  ref.invalidate(_walletTransactionsProvider(wallet.walletId)),
              isEmpty: (items) => items.isEmpty,
              empty: const EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Nothing yet',
                message:
                    'Transactions that touch this wallet will appear here.',
              ),
              builder: (items) => Column(
                children: <Widget>[
                  for (final item in items)
                    TransactionTile(
                      item: item,
                      onTap: () => context.push('/transactions/${item.id}'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _adjustOpeningBalance(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final controller = TextEditingController(
      text: wallet.openingBalancePoisha == 0
          ? ''
          : Money(wallet.openingBalancePoisha).toStorageString(),
    );
    final reason = TextEditingController();
    var amount = wallet.openingBalancePoisha;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Adjust opening balance'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                'The opening balance is the starting point of every figure for '
                'this wallet. Corrections are written to the activity log so '
                'there is a record of what changed and why.',
              ),
              const SizedBox(height: 16),
              AmountField(
                controller: controller,
                label: 'New opening balance',
                onChanged: (poisha) => amount = poisha ?? 0,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reason,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (amount < 0) {
      if (!context.mounted) return;
      showAppMessage(context, 'An opening balance cannot be negative.');
      return;
    }
    if (!context.mounted) return;
    await run(
      context,
      () => ref
          .read(walletRepositoryProvider)
          .adjustOpeningBalance(
            walletId: wallet.walletId,
            newOpeningBalancePoisha: amount,
            reason: reason.text.trim().isEmpty ? null : reason.text.trim(),
          ),
    );
  }
}
