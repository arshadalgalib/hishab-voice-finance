import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../domain/enums.dart';
import '../../../domain/models/aggregates.dart';
import '../../../domain/models/budget_progress.dart';
import '../../../domain/services/report_service.dart';

/// Home screen: where the money is, what happened this month, and the fastest
/// route back to recording something.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingRecurringProvider);
    final budgets = ref.watch(budgetProgressProvider);
    final dueCount = pending.value?.length ?? 0;
    final flagged = (budgets.value ?? const <BudgetProgress>[])
        .where((budget) => budget.isOverAlertThreshold)
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hishab'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dashboardReportProvider);
          ref.invalidate(monthlyTrendProvider);
          ref.invalidate(pendingRecurringProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: <Widget>[
            const _BalanceHero(),
            const SizedBox(height: 16),
            const _MonthSummary(),
            const SizedBox(height: 16),
            const _QuickActions(),
            if (dueCount > 0) ...<Widget>[
              const SizedBox(height: 16),
              _DueBanner(count: dueCount),
            ],
            if (flagged.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              _BudgetWatch(budgets: flagged),
            ],
            const SizedBox(height: 16),
            const _TrendCard(),
            const SizedBox(height: 16),
            const _RecentActivity(),
          ],
        ),
      ),
    );
  }
}

/// Total across active wallets. Archived wallets are excluded, which is
/// spelled out so the number is never mistaken for net worth.
class _BalanceHero extends ConsumerWidget {
  const _BalanceHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/wallets'),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'TOTAL BALANCE',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              AsyncView<int>(
                value: ref.watch(totalBalanceProvider),
                onRetry: () => ref.invalidate(walletBalancesProvider),
                builder: (total) => Text(
                  formatterFor(ref).format(total, withSign: true),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Opening balances plus everything recorded, across wallets '
                'that are not archived.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthSummary extends ConsumerWidget {
  const _MonthSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(dashboardReportProvider);
    return SectionCard(
      title: 'THIS MONTH',
      child: AsyncView<PeriodReport>(
        value: report,
        loadingMessage: 'Adding up this month…',
        onRetry: () => ref.invalidate(dashboardReportProvider),
        builder: (data) {
          final summary = data.summary;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                data.range.label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: StatTile(
                      label: 'Income',
                      valuePoisha: summary.incomePoisha,
                      type: TransactionType.income,
                      icon: Icons.south_west,
                    ),
                  ),
                  Expanded(
                    child: StatTile(
                      label: 'Expenses',
                      valuePoisha: summary.expensePoisha,
                      type: TransactionType.expense,
                      icon: Icons.north_east,
                    ),
                  ),
                  Expanded(
                    child: StatTile(
                      label: 'Net',
                      valuePoisha: summary.netCashFlowPoisha,
                      type: summary.netCashFlowPoisha >= 0
                          ? TransactionType.income
                          : TransactionType.expense,
                      icon: Icons.trending_up,
                    ),
                  ),
                ],
              ),
              if (summary.transferCount > 0) ...<Widget>[
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    const Icon(Icons.swap_horiz, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${summary.transferCount} transfer(s) moved '
                        '${formatterFor(ref).format(summary.transferVolumePoisha)} '
                        'between your own wallets — not counted as income or '
                        'expense.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (summary.transactionCount == 0) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  'Nothing recorded this month yet.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'RECORD SOMETHING',
      child: Row(
        children: <Widget>[
          _QuickAction(
            icon: Icons.north_east,
            label: 'Expense',
            color: AppColors.expense,
            onTap: () => context.push('/transactions/new?type=expense'),
          ),
          _QuickAction(
            icon: Icons.south_west,
            label: 'Income',
            color: AppColors.income,
            onTap: () => context.push('/transactions/new?type=income'),
          ),
          _QuickAction(
            icon: Icons.swap_horiz,
            label: 'Transfer',
            color: AppColors.transfer,
            onTap: () => context.push('/transactions/new?type=transfer'),
          ),
          _QuickAction(
            icon: Icons.mic,
            label: 'Voice',
            color: AppColors.seed,
            onTap: () => context.go('/voice'),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: theme.textTheme.labelMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nudge for recurring rules whose due date has passed. Posting one is never
/// automatic — it always goes through the user.
class _DueBanner extends StatelessWidget {
  const _DueBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: AppColors.warning.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            const Icon(Icons.event_repeat, color: AppColors.warning),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                count == 1
                    ? '1 recurring entry is due and waiting for you.'
                    : '$count recurring entries are due and waiting for you.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            TextButton(
              onPressed: () => context.push('/recurring'),
              child: const Text('Review'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetWatch extends ConsumerWidget {
  const _BudgetWatch({required this.budgets});

  final List<BudgetProgress> budgets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return SectionCard(
      title: 'BUDGET WATCH',
      action: TextButton(
        onPressed: () => context.push('/budgets'),
        child: const Text('All'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final budget in budgets)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          budget.name,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      MoneyText(
                        budget.spentPoisha,
                        showSign: false,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: budget.ratio.clamp(0.0, 1.0),
                      minHeight: 8,
                      color: budget.isOverBudget
                          ? AppColors.expense
                          : AppColors.warning,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    budget.isOverBudget
                        ? 'Over by ${formatterFor(ref).format(budget.spentPoisha - budget.amountPoisha)}'
                        : '${budget.percentUsed.toStringAsFixed(0)}% of your '
                              'budget used',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: budget.isOverBudget
                          ? AppColors.expense
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TrendCard extends ConsumerWidget {
  const _TrendCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return SectionCard(
      title: 'LAST 6 MONTHS',
      child: AsyncView<List<TrendPoint>>(
        value: ref.watch(monthlyTrendProvider),
        loadingMessage: 'Building the chart…',
        onRetry: () => ref.invalidate(monthlyTrendProvider),
        builder: (points) {
          if (points.isEmpty) {
            return Text(
              'No months to show yet.',
              style: theme.textTheme.bodyMedium,
            );
          }
          final peak = points.fold<int>(
            0,
            (best, point) => math.max(
              best,
              math.max(point.incomePoisha, point.expensePoisha),
            ),
          );
          if (peak <= 0) {
            return Text(
              'No income or expenses in the last six months yet.',
              style: theme.textTheme.bodyMedium,
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  _LegendDot(color: AppColors.income, label: 'Income'),
                  const SizedBox(width: 16),
                  _LegendDot(color: AppColors.expense, label: 'Expenses'),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 180,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    minY: 0,
                    maxY: peak * 1.15,
                    barTouchData: BarTouchData(enabled: false),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          getTitlesWidget: (value, meta) {
                            final index = value.round();
                            if (index < 0 || index >= points.length) {
                              return const SizedBox.shrink();
                            }
                            return SideTitleWidget(
                              meta: meta,
                              child: Text(
                                points[index].label,
                                style: theme.textTheme.labelSmall,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    barGroups: <BarChartGroupData>[
                      for (var index = 0; index < points.length; index++)
                        BarChartGroupData(
                          x: index,
                          barsSpace: 4,
                          barRods: <BarChartRodData>[
                            BarChartRodData(
                              toY: points[index].incomePoisha / 100,
                              color: AppColors.income,
                              width: 8,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            BarChartRodData(
                              toY: points[index].expensePoisha / 100,
                              color: AppColors.expense,
                              width: 8,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

class _RecentActivity extends ConsumerWidget {
  const _RecentActivity();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SectionCard(
      title: 'RECENT ACTIVITY',
      action: TextButton(
        onPressed: () => context.go('/history'),
        child: const Text('See all'),
      ),
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      child: AsyncView<List<TransactionListItem>>(
        value: ref.watch(recentTransactionsProvider),
        onRetry: () => ref.invalidate(recentTransactionsProvider),
        isEmpty: (items) => items.isEmpty,
        empty: const EmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'Nothing recorded yet',
          message:
              'Tap the microphone and say what you spent, or use one of the '
              'shortcuts above.',
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
    );
  }
}
