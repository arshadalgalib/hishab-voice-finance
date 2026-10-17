import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../core/utils/date_x.dart';
import '../../../data/local/app_database.dart';
import '../../../domain/enums.dart';
import '../../../domain/models/aggregates.dart';
import '../../../domain/models/date_range.dart';
import '../../../domain/models/transaction_filter.dart';

/// Every recorded transaction, filterable and searchable.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(transactionFilterProvider);
    final items = ref.watch(filteredTransactionsProvider);
    final groupByDay =
        filter.sort == TransactionSort.dateDesc ||
        filter.sort == TransactionSort.dateAsc;

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Filters',
            icon: Badge(
              isLabelVisible: filter.activeFilterCount > 0,
              label: Text('${filter.activeFilterCount}'),
              child: const Icon(Icons.filter_list),
            ),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (context) => const _FilterSheet(),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New transaction',
        onPressed: () => context.push('/transactions/new'),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search descriptions, notes and tags',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: filter.searchText == null
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          ref
                              .read(transactionFilterProvider.notifier)
                              .setSearch(null);
                        },
                      ),
              ),
              onChanged: (value) =>
                  ref.read(transactionFilterProvider.notifier).setSearch(value),
            ),
          ),
          if (!filter.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      _describeFilter(filter),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      _search.clear();
                      ref.read(transactionFilterProvider.notifier).clear();
                    },
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: AsyncView<List<TransactionListItem>>(
              value: items,
              onRetry: () => ref.invalidate(filteredTransactionsProvider),
              isEmpty: (list) => list.isEmpty,
              empty: EmptyState(
                icon: Icons.receipt_long_outlined,
                title: filter.isEmpty
                    ? 'Nothing recorded yet'
                    : 'No transactions match',
                message: filter.isEmpty
                    ? 'Record an expense, income or transfer and it will show '
                          'up here.'
                    : 'Try widening the date range or clearing a filter.',
                action: filter.isEmpty
                    ? FilledButton.icon(
                        onPressed: () => context.push('/transactions/new'),
                        icon: const Icon(Icons.add),
                        label: const Text('Record a transaction'),
                      )
                    : null,
              ),
              builder: (list) {
                final children = <Widget>[];
                String? lastDay;
                for (final item in list) {
                  if (groupByDay) {
                    final key = dayKeyOf(item.occurredAt);
                    if (key != lastDay) {
                      lastDay = key;
                      children.add(_DayHeader(date: item.occurredAt));
                    }
                  }
                  children.add(
                    TransactionTile(
                      item: item,
                      onTap: () => context.push('/transactions/${item.id}'),
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 96),
                  children: children,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _describeFilter(TransactionFilter filter) {
    final parts = <String>[];
    if (filter.range != null) parts.add(filter.range!.label);
    if (filter.types.isNotEmpty) {
      parts.add(filter.types.map((t) => t.name).join('/'));
    }
    if (filter.walletIds.isNotEmpty) {
      parts.add('${filter.walletIds.length} wallet(s)');
    }
    if (filter.categoryIds.isNotEmpty) {
      parts.add('${filter.categoryIds.length} category(ies)');
    }
    if (filter.searchText != null && filter.searchText!.trim().isNotEmpty) {
      parts.add('“${filter.searchText!.trim()}”');
    }
    parts.add(filter.sort.label);
    return parts.join(' · ');
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 6),
      child: Text(
        '${relativeDayLabel(date)} · ${formatDate(date)}',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// The filter editor. It keeps its own copy of the state and only touches the
/// shared filter when Apply is tapped, so dismissing it changes nothing.
class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet();

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late DateRange? _range;
  late Set<TransactionType> _types;
  late Set<String> _walletIds;
  late Set<String> _categoryIds;
  late TransactionSort _sort;

  static const List<DateRangePreset> _presets = <DateRangePreset>[
    DateRangePreset.today,
    DateRangePreset.last7Days,
    DateRangePreset.thisMonth,
    DateRangePreset.lastMonth,
    DateRangePreset.last3Months,
    DateRangePreset.thisYear,
    DateRangePreset.allTime,
  ];

  static String _presetLabel(DateRangePreset preset) {
    switch (preset) {
      case DateRangePreset.today:
        return 'Today';
      case DateRangePreset.yesterday:
        return 'Yesterday';
      case DateRangePreset.last7Days:
        return 'Last 7 days';
      case DateRangePreset.thisWeek:
        return 'This week';
      case DateRangePreset.thisMonth:
        return 'This month';
      case DateRangePreset.lastMonth:
        return 'Last month';
      case DateRangePreset.last3Months:
        return 'Last 3 months';
      case DateRangePreset.thisYear:
        return 'This year';
      case DateRangePreset.allTime:
        return 'All time';
      case DateRangePreset.custom:
        return 'Custom';
    }
  }

  @override
  void initState() {
    super.initState();
    final filter = ref.read(transactionFilterProvider);
    _range = filter.range;
    _types = <TransactionType>{...filter.types};
    _walletIds = <String>{...filter.walletIds};
    _categoryIds = <String>{...filter.categoryIds};
    _sort = filter.sort;
  }

  Future<void> _pickCustomRange() async {
    final now = ref.read(clockProvider).now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _range == null
          ? null
          : DateTimeRange(start: _range!.start, end: _range!.end),
    );
    if (picked == null) return;
    setState(() {
      _range = DateRange.days(picked.start, picked.end);
    });
  }

  void _apply() {
    final controller = ref.read(transactionFilterProvider.notifier);
    controller.setRange(_range);
    controller.setTypes(_types);
    controller.setWallets(_walletIds);
    controller.setCategories(_categoryIds);
    controller.setSort(_sort);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wallets =
        ref.watch(walletBalancesProvider).value ?? const <WalletBalance>[];
    final categories =
        ref.watch(allCategoriesProvider).value ?? const <CategoryRow>[];

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Filters', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            const _SheetLabel('Dates'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final preset in _presets)
                  ChoiceChip(
                    label: Text(_presetLabel(preset)),
                    selected:
                        _range != null &&
                        _range ==
                            resolvePreset(
                              preset,
                              now: ref.read(clockProvider).now(),
                            ),
                    onSelected: (_) => setState(() {
                      _range = resolvePreset(
                        preset,
                        now: ref.read(clockProvider).now(),
                      );
                    }),
                  ),
                ChoiceChip(
                  label: Text(
                    _range == null
                        ? 'Custom range…'
                        : 'Custom: ${_range!.label}',
                  ),
                  selected: false,
                  onSelected: (_) => _pickCustomRange(),
                ),
                if (_range != null)
                  ActionChip(
                    avatar: const Icon(Icons.close, size: 16),
                    label: const Text('Any time'),
                    onPressed: () => setState(() => _range = null),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const _SheetLabel('Types'),
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (final type in TransactionType.values)
                  FilterChip(
                    label: Text(type.name),
                    selected: _types.contains(type),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _types.add(type);
                      } else {
                        _types.remove(type);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const _SheetLabel('Wallets'),
            if (wallets.isEmpty)
              Text('No wallets yet.', style: theme.textTheme.bodySmall)
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final wallet in wallets)
                    FilterChip(
                      label: Text(wallet.name),
                      selected: _walletIds.contains(wallet.walletId),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _walletIds.add(wallet.walletId);
                        } else {
                          _walletIds.remove(wallet.walletId);
                        }
                      }),
                    ),
                ],
              ),
            const SizedBox(height: 20),
            const _SheetLabel('Categories'),
            if (categories.isEmpty)
              Text('No categories yet.', style: theme.textTheme.bodySmall)
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final category in categories)
                    FilterChip(
                      label: Text(category.name),
                      selected: _categoryIds.contains(category.id),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _categoryIds.add(category.id);
                        } else {
                          _categoryIds.remove(category.id);
                        }
                      }),
                    ),
                ],
              ),
            const SizedBox(height: 20),
            FormDropdown<TransactionSort>(
              label: 'Sort by',
              value: _sort,
              items: <DropdownMenuItem<TransactionSort>>[
                for (final sort in TransactionSort.values)
                  DropdownMenuItem<TransactionSort>(
                    value: sort,
                    child: Text(sort.label),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _sort = value);
              },
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _apply,
              icon: const Icon(Icons.check),
              label: const Text('Apply filters'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() {
                _range = null;
                _types = <TransactionType>{};
                _walletIds = <String>{};
                _categoryIds = <String>{};
                _sort = TransactionSort.dateDesc;
              }),
              child: const Text('Reset this sheet'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
