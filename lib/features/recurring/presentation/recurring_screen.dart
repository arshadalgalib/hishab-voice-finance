import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/date_x.dart';
import '../../../data/local/app_database.dart';
import '../../../data/repositories/recurring_repository.dart';
import '../../../domain/enums.dart';
import '../../../domain/models/aggregates.dart';

/// Lists recurring rules and the ones waiting for confirmation.
///
/// Rules never post on their own by default, so the "Waiting for you" card is
/// the only place a due rule turns into a transaction — the user always
/// confirms. Posting is idempotent per due date, so a double tap is harmless.
class RecurringScreen extends ConsumerStatefulWidget {
  const RecurringScreen({super.key});

  @override
  ConsumerState<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends ConsumerState<RecurringScreen> {
  @override
  Widget build(BuildContext context) {
    // Names resolve from the read models so a row never shows a raw id.
    final wallets =
        ref.watch(walletBalancesProvider).value ?? const <WalletBalance>[];
    final walletNames = <String, String>{
      for (final wallet in wallets) wallet.walletId: wallet.name,
    };
    final categories =
        ref.watch(allCategoriesProvider).value ?? const <CategoryRow>[];
    final categoryNames = <String, String>{
      for (final category in categories) category.id: category.name,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Recurring')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewRule,
        icon: const Icon(Icons.add),
        label: const Text('New rule'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          _pendingSection(walletNames, categoryNames),
          const SizedBox(height: 16),
          _rulesSection(walletNames, categoryNames),
        ],
      ),
    );
  }

  /// A due, non auto-posting rule needs an explicit decision, so it is promoted
  /// above the full list. An empty card would only be noise.
  Widget _pendingSection(
    Map<String, String> walletNames,
    Map<String, String> categoryNames,
  ) {
    return AsyncView<List<RecurringRuleRow>>(
      value: ref.watch(pendingRecurringProvider),
      loadingMessage: 'Checking what is due…',
      isEmpty: (rules) => rules.isEmpty,
      empty: const SizedBox.shrink(),
      onRetry: () => ref.invalidate(pendingRecurringProvider),
      builder: (rules) => SectionCard(
        title: 'Waiting for you',
        child: Column(
          children: [
            for (var i = 0; i < rules.length; i++) ...[
              if (i > 0) const Divider(height: 24),
              _pendingRow(rules[i], walletNames, categoryNames),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pendingRow(
    RecurringRuleRow rule,
    Map<String, String> walletNames,
    Map<String, String> categoryNames,
  ) {
    final theme = Theme.of(context);
    final categoryName = categoryNames[rule.categoryId];
    final details = <String>[?categoryName, _walletLabel(rule, walletNames)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rule.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    details.join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Due ${formatDateTime(rule.nextDueDate)}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            MoneyText(rule.amountPoisha, type: rule.type),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _skip(rule),
                child: const Text('Skip'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () => _post(rule),
                child: const Text('Post now'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _rulesSection(
    Map<String, String> walletNames,
    Map<String, String> categoryNames,
  ) {
    return AsyncView<List<RecurringRuleRow>>(
      value: ref.watch(recurringRulesProvider),
      loadingMessage: 'Loading rules…',
      isEmpty: (rules) => rules.isEmpty,
      empty: EmptyState(
        icon: Icons.repeat,
        title: 'No recurring rules yet',
        message:
            'Set up repeating income, bills or transfers and confirm each '
            'one when it falls due.',
        action: FilledButton.icon(
          onPressed: _openNewRule,
          icon: const Icon(Icons.add),
          label: const Text('New rule'),
        ),
      ),
      onRetry: () => ref.invalidate(recurringRulesProvider),
      builder: (rules) => SectionCard(
        title: 'All rules',
        child: Column(
          children: [
            for (var i = 0; i < rules.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              _ruleTile(rules[i], walletNames, categoryNames),
            ],
          ],
        ),
      ),
    );
  }

  Widget _ruleTile(
    RecurringRuleRow rule,
    Map<String, String> walletNames,
    Map<String, String> categoryNames,
  ) {
    final theme = Theme.of(context);
    final description = rule.description?.trim();
    final categoryName = categoryNames[rule.categoryId];
    final details = <String>[
      if (description != null &&
          description.isNotEmpty &&
          description != rule.name)
        description,
      ?categoryName,
      _walletLabel(rule, walletNames),
    ];
    return ListTile(
      onTap: () => _openEditRule(rule),
      contentPadding: EdgeInsets.zero,
      isThreeLine: true,
      title: Text(
        rule.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: rule.isActive
            ? null
            : theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (details.isNotEmpty)
            Text(
              details.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          Text(
            RecurringRepository.describeSchedule(rule),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Row(
            children: [
              Icon(
                Icons.event,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  'Next ${formatDateTime(rule.nextDueDate)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: rule.isActive
                        ? theme.colorScheme.onSurfaceVariant
                        : AppColors.warning,
                    fontWeight: rule.isActive ? null : FontWeight.w600,
                  ),
                ),
              ),
              if (!rule.isActive) ...[
                const SizedBox(width: 8),
                Text(
                  'Paused',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MoneyText(rule.amountPoisha, type: rule.type),
          PopupMenuButton<_RuleAction>(
            tooltip: 'More actions',
            onSelected: (action) {
              switch (action) {
                case _RuleAction.toggleActive:
                  _toggleActive(rule);
                case _RuleAction.delete:
                  _delete(rule);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _RuleAction.toggleActive,
                child: Text(rule.isActive ? 'Pause' : 'Resume'),
              ),
              const PopupMenuItem(
                value: _RuleAction.delete,
                child: Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _walletLabel(RecurringRuleRow rule, Map<String, String> walletNames) {
    final source = walletNames[rule.walletId] ?? rule.walletId;
    final destination = rule.toWalletId;
    if (rule.type == TransactionType.transfer && destination != null) {
      return '$source → ${walletNames[destination] ?? destination}';
    }
    return source;
  }

  Future<void> _openNewRule() async {
    final created = await context.push<bool>('/recurring/new');
    if (created == true) _refresh();
  }

  Future<void> _openEditRule(RecurringRuleRow rule) async {
    final changed = await context.push<bool>('/recurring/new', extra: rule.id);
    if (changed == true) _refresh();
  }

  Future<void> _post(RecurringRuleRow rule) async {
    try {
      final result = await ref.read(recurringServiceProvider).post(rule);
      if (!mounted) return;
      _refresh();
      showAppMessage(
        context,
        'Posted ${result.ruleName} to ${_walletLabel(rule, _walletNames())}. '
        'Next due ${formatDate(result.nextDueDate)}.',
      );
    } on AppException catch (error) {
      if (!mounted) return;
      showAppMessage(context, error.message);
    }
  }

  Future<void> _skip(RecurringRuleRow rule) async {
    try {
      final next = await ref.read(recurringServiceProvider).skip(rule);
      if (!mounted) return;
      _refresh();
      showAppMessage(
        context,
        'Skipped ${rule.name}. Next due ${formatDate(next)}.',
      );
    } on AppException catch (error) {
      if (!mounted) return;
      showAppMessage(context, error.message);
    }
  }

  Future<void> _toggleActive(RecurringRuleRow rule) async {
    try {
      await ref
          .read(recurringRepositoryProvider)
          .update(rule.id, isActive: !rule.isActive);
      if (!mounted) return;
      _refresh();
      showAppMessage(
        context,
        rule.isActive ? '${rule.name} paused.' : '${rule.name} resumed.',
      );
    } on AppException catch (error) {
      if (!mounted) return;
      showAppMessage(context, error.message);
    }
  }

  Future<void> _delete(RecurringRuleRow rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete rule?'),
        content: Text(
          '“${rule.name}” will be removed. Transactions it already created are '
          'kept.',
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
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(recurringRepositoryProvider).delete(rule.id);
      if (!mounted) return;
      _refresh();
      showAppMessage(context, 'Rule deleted.');
    } on AppException catch (error) {
      if (!mounted) return;
      showAppMessage(context, error.message);
    }
  }

  Map<String, String> _walletNames() {
    final wallets =
        ref.read(walletBalancesProvider).value ?? const <WalletBalance>[];
    return <String, String>{
      for (final wallet in wallets) wallet.walletId: wallet.name,
    };
  }

  /// Posting writes a transaction, so every read model that reflects money has
  /// to be refreshed, not just the rule list.
  void _refresh() {
    ref.invalidate(pendingRecurringProvider);
    ref.invalidate(recurringRulesProvider);
    ref.invalidate(recentTransactionsProvider);
    ref.invalidate(filteredTransactionsProvider);
    ref.invalidate(walletBalancesProvider);
    ref.invalidate(activeWalletBalancesProvider);
    ref.invalidate(totalBalanceProvider);
    ref.invalidate(dashboardReportProvider);
    ref.invalidate(monthlyTrendProvider);
  }
}

enum _RuleAction { toggleActive, delete }
