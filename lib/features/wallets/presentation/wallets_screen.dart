import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/labels.dart';
import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../core/errors/app_exception.dart';
import '../../../domain/enums.dart';
import '../../../domain/models/aggregates.dart';

/// Every wallet with its derived balance.
///
/// Archived wallets are shown in their own section rather than hidden: their
/// history still counts towards reports, so pretending they are gone would make
/// the totals look wrong.
class WalletsScreen extends ConsumerWidget {
  const WalletsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wallets')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/wallets/new'),
        icon: const Icon(Icons.add),
        label: const Text('New wallet'),
      ),
      body: AsyncView<List<WalletBalance>>(
        value: ref.watch(walletBalancesProvider),
        onRetry: () => ref.invalidate(walletBalancesProvider),
        isEmpty: (wallets) => wallets.isEmpty,
        empty: EmptyState(
          icon: Icons.account_balance_wallet_outlined,
          title: 'No wallets yet',
          message:
              'A wallet is anywhere money sits — cash, a bank account, bKash, '
              'or a savings pot.',
          action: FilledButton.icon(
            onPressed: () => context.push('/wallets/new'),
            icon: const Icon(Icons.add),
            label: const Text('Create a wallet'),
          ),
        ),
        builder: (wallets) {
          final active = wallets
              .where((wallet) => !wallet.isArchived)
              .toList(growable: false);
          final archived = wallets
              .where((wallet) => wallet.isArchived)
              .toList(growable: false);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: <Widget>[
              for (final wallet in active)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _WalletTile(wallet: wallet),
                ),
              if (archived.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    'ARCHIVED',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                for (final wallet in archived)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _WalletTile(wallet: wallet),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Archived wallets keep their history and still appear in '
                    'reports. They just cannot be used for new transactions.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _WalletTile extends ConsumerWidget {
  const _WalletTile({required this.wallet});

  final WalletBalance wallet;

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
    final theme = Theme.of(context);
    final accent = Color(wallet.colorValue ?? AppColors.seed.toARGB32());

    return Card(
      child: ListTile(
        onTap: () => context.push('/wallets/${wallet.walletId}'),
        leading: CircleAvatar(
          backgroundColor: accent.withValues(alpha: 0.14),
          child: Icon(
            WalletIcons.resolve(wallet.type),
            size: 20,
            color: accent,
          ),
        ),
        title: Text(wallet.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              <String>[
                walletTypeLabel(wallet.type),
                if (wallet.institution != null &&
                    wallet.institution!.trim().isNotEmpty)
                  wallet.institution!.trim(),
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (wallet.isDefaultIncome || wallet.isDefaultExpense) ...<Widget>[
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: <Widget>[
                  if (wallet.isDefaultIncome)
                    const _Badge(text: 'Default for income'),
                  if (wallet.isDefaultExpense)
                    const _Badge(text: 'Default for expenses'),
                ],
              ),
            ],
          ],
        ),
        isThreeLine: wallet.isDefaultIncome || wallet.isDefaultExpense,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                MoneyText(
                  wallet.balancePoisha,
                  showSign: false,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (wallet.isArchived)
                  Text(
                    'archived',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            _menu(context, ref),
          ],
        ),
      ),
    );
  }

  Widget _menu(BuildContext context, WidgetRef ref) {
    final repository = ref.read(walletRepositoryProvider);
    return PopupMenuButton<String>(
      onSelected: (value) async {
        switch (value) {
          case 'income-default':
            await _run(
              context,
              () => repository.setDefault(
                kind: CategoryKind.income,
                walletId: wallet.walletId,
              ),
            );
          case 'expense-default':
            await _run(
              context,
              () => repository.setDefault(
                kind: CategoryKind.expense,
                walletId: wallet.walletId,
              ),
            );
          case 'edit':
            if (context.mounted) {
              await context.push<String?>(
                '/wallets/new',
                extra: wallet.walletId,
              );
            }
          case 'archive':
            await _run(
              context,
              () => repository.setArchived(wallet.walletId, !wallet.isArchived),
            );
          case 'delete':
            final confirmed = await _confirmDelete(context);
            if (!confirmed) return;
            if (!context.mounted) return;
            await _run(context, () => repository.deleteWallet(wallet.walletId));
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        if (!wallet.isArchived && !wallet.isDefaultIncome)
          const PopupMenuItem<String>(
            value: 'income-default',
            child: Text('Set as default for income'),
          ),
        if (!wallet.isArchived && !wallet.isDefaultExpense)
          const PopupMenuItem<String>(
            value: 'expense-default',
            child: Text('Set as default for expenses'),
          ),
        const PopupMenuItem<String>(value: 'edit', child: Text('Edit')),
        PopupMenuItem<String>(
          value: 'archive',
          child: Text(wallet.isArchived ? 'Unarchive' : 'Archive'),
        ),
        const PopupMenuItem<String>(value: 'delete', child: Text('Delete')),
      ],
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete “${wallet.name}”?'),
        content: const Text(
          'This only works if nothing references the wallet. If it has '
          'transactions, archive it instead — archiving keeps the history and '
          'still counts it in reports.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
