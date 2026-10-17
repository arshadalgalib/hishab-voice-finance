import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../core/utils/money.dart';
import '../../../domain/enums.dart';
import '../../../domain/models/aggregates.dart';
import '../../../domain/models/date_range.dart';
import '../../../domain/services/report_service.dart';

/// Reporting over an arbitrary window. Transfers never enter the income or
/// expense figures — the model accessors already keep them separate.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  late DateRange _range;
  DateRangePreset _preset = DateRangePreset.thisMonth;

  /// Cached so a rebuild cannot kick off a second identical query.
  late Future<PeriodReport> _future;

  @override
  void initState() {
    super.initState();
    _range = ref.read(currentMonthRangeProvider);
    _future = ref.read(reportServiceProvider).reportFor(_range);
  }

  void _load(DateRange range) {
    setState(() {
      _range = range;
      _future = ref.read(reportServiceProvider).reportFor(range);
    });
  }

  Future<void> _selectPreset(DateRangePreset preset) async {
    if (preset == DateRangePreset.custom) {
      final now = ref.read(clockProvider).now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(now.year + 1, 12, 31),
        initialDateRange: DateTimeRange(start: _range.start, end: _range.end),
      );
      // A cancelled picker must never discard the window already on screen.
      if (picked == null) return;
      _preset = DateRangePreset.custom;
      _load(DateRange.days(picked.start, picked.end));
      return;
    }
    _preset = preset;
    _load(resolvePreset(preset, now: ref.read(clockProvider).now()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: Column(
        children: [
          _presetBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Icon(
                  Icons.date_range_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _range.label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<PeriodReport>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LoadingView(message: 'Crunching the numbers…');
                }
                if (snapshot.hasError) {
                  return ErrorStateView(
                    message: snapshot.error.toString(),
                    onRetry: () => _load(_range),
                  );
                }
                final report = snapshot.data;
                if (report == null) {
                  return ErrorStateView(
                    message: 'No report is available for this period.',
                    onRetry: () => _load(_range),
                  );
                }
                return _ReportBody(report: report);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _presetBar() {
    const presets = <DateRangePreset>[
      DateRangePreset.thisMonth,
      DateRangePreset.lastMonth,
      DateRangePreset.last3Months,
      DateRangePreset.thisYear,
      DateRangePreset.allTime,
      DateRangePreset.custom,
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          for (final preset in presets)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(_presetLabel(preset)),
                selected: _preset == preset,
                onSelected: (_) => _selectPreset(preset),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.report});

  final PeriodReport report;

  @override
  Widget build(BuildContext context) {
    final summary = report.summary;
    final net = report.netPoisha;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        SectionCard(
          title: 'Summary',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                    // The sign lives in the type, so feed the magnitude in and
                    // let the colour and prefix carry the direction.
                    child: StatTile(
                      label: 'Net',
                      valuePoisha: net.abs(),
                      type: net < 0
                          ? TransactionType.expense
                          : TransactionType.income,
                      icon: Icons.swap_vert,
                    ),
                  ),
                ],
              ),
              const Divider(height: 28),
              LabeledRow(
                label: 'Transfers (excluded from income and expense)',
                value: '',
                valueWidget: MoneyText(
                  summary.transferVolumePoisha,
                  type: TransactionType.transfer,
                  showSign: false,
                ),
              ),
              LabeledRow(
                label: 'Transactions counted',
                value: '${summary.transactionCount}',
              ),
              LabeledRow(
                label: 'Spending vs previous period',
                value: '',
                valueWidget: _ChangeLabel(
                  ratio: report.expenseChangeRatio,
                  increaseIsGood: false,
                ),
              ),
              LabeledRow(
                label: 'Income vs previous period',
                value: '',
                valueWidget: _ChangeLabel(
                  ratio: report.incomeChangeRatio,
                  increaseIsGood: true,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _CategoryBreakdown(
          title: 'Where the money went',
          rows: report.expenseByCategory,
          totalPoisha: summary.expensePoisha,
          color: AppColors.expense,
          emptyMessage: 'No spending in this period.',
        ),
        const SizedBox(height: 12),
        _CategoryBreakdown(
          title: 'Where it came from',
          rows: report.incomeByCategory,
          totalPoisha: summary.incomePoisha,
          color: AppColors.income,
          emptyMessage: 'No income in this period.',
        ),
        const SizedBox(height: 12),
        _TrendSection(points: report.trend),
        if (report.expenseByCategory.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ExpenseSplitSection(rows: report.expenseByCategory),
        ],
      ],
    );
  }
}

/// A signed percentage change, or an explicit note when there is no window to
/// compare against (which is different from a zero change).
class _ChangeLabel extends StatelessWidget {
  const _ChangeLabel({required this.ratio, required this.increaseIsGood});

  final double? ratio;
  final bool increaseIsGood;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = this.ratio;
    if (ratio == null) {
      return Text(
        'no comparable previous period',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    final percent = ratio * 100;
    final isUp = percent > 0;
    final sign = isUp ? '+' : (percent < 0 ? '\u2212' : '');
    final good = percent == 0 ? null : (isUp == increaseIsGood);
    final color = good == null
        ? theme.colorScheme.onSurfaceVariant
        : (good ? AppColors.income : AppColors.expense);
    return Text(
      '$sign${percent.abs().toStringAsFixed(1)}%',
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: color,
      ),
    );
  }
}

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({
    required this.title,
    required this.rows,
    required this.totalPoisha,
    required this.color,
    required this.emptyMessage,
  });

  final String title;
  final List<CategoryTotal> rows;
  final int totalPoisha;
  final Color color;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Bars are scaled to the biggest category so the leader fills the track.
    final maxTotal = rows.fold<int>(
      0,
      (largest, row) => row.totalPoisha > largest ? row.totalPoisha : largest,
    );
    return SectionCard(
      title: title,
      child: rows.isEmpty
          ? Text(
              emptyMessage,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final row in rows)
                  _CategoryBreakdownRow(
                    row: row,
                    color: color,
                    maxTotal: maxTotal,
                    totalPoisha: totalPoisha,
                  ),
              ],
            ),
    );
  }
}

class _CategoryBreakdownRow extends StatelessWidget {
  const _CategoryBreakdownRow({
    required this.row,
    required this.color,
    required this.maxTotal,
    required this.totalPoisha,
  });

  final CategoryTotal row;
  final Color color;
  final int maxTotal;
  final int totalPoisha;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final share = totalPoisha <= 0
        ? 0.0
        : (row.totalPoisha / totalPoisha) * 100;
    final barValue = maxTotal <= 0 ? 0.0 : row.totalPoisha / maxTotal;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(CategoryIcons.resolve(row.iconName), size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  row.categoryName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: 8),
              MoneyText(
                row.totalPoisha,
                showSign: false,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: barValue,
                    minHeight: 6,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.16),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 48,
                child: Text(
                  '${share.toStringAsFixed(1)}%',
                  textAlign: TextAlign.right,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrendSection extends StatelessWidget {
  const _TrendSection({required this.points});

  final List<TrendPoint> points;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allZero = points.every(
      (point) => point.incomePoisha == 0 && point.expensePoisha == 0,
    );
    if (points.isEmpty || allZero) {
      return SectionCard(
        title: 'Trend',
        child: Text(
          'No income or spending in this period.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return SectionCard(
      title: 'Trend',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              _LegendDot(color: AppColors.income, label: 'Income'),
              SizedBox(width: 16),
              _LegendDot(color: AppColors.expense, label: 'Expense'),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                minY: 0,
                alignment: BarChartAlignment.spaceAround,
                barGroups: [
                  for (var index = 0; index < points.length; index++)
                    BarChartGroupData(
                      x: index,
                      barsSpace: 4,
                      barRods: [
                        BarChartRodData(
                          toY: points[index].incomePoisha / Money.poishaPerTaka,
                          color: AppColors.income,
                          width: 8,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        BarChartRodData(
                          toY:
                              points[index].expensePoisha / Money.poishaPerTaka,
                          color: AppColors.expense,
                          width: 8,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ],
                    ),
                ],
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: const AxisTitles(),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
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
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(enabled: false),
              ),
            ),
          ),
        ],
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
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.labelMedium),
      ],
    );
  }
}

class _ExpenseSplitSection extends StatelessWidget {
  const _ExpenseSplitSection({required this.rows});

  final List<CategoryTotal> rows;

  /// Distinct hues for the slices; the app palette only names the two sides of
  /// the ledger, so the rest comes from a small fixed set.
  static const List<Color> _palette = <Color>[
    Color(0xFF00695C),
    Color(0xFF2E7D32),
    Color(0xFFEF6C00),
    Color(0xFF1565C0),
    Color(0xFF6A1B9A),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sorted = [...rows]
      ..sort((a, b) => b.totalPoisha.compareTo(a.totalPoisha));
    final top = sorted.take(5).toList(growable: false);
    final rest = sorted.skip(5);
    final otherTotal = rest.fold<int>(0, (sum, row) => sum + row.totalPoisha);
    final grandTotal = top.fold<int>(
      otherTotal,
      (sum, row) => sum + row.totalPoisha,
    );
    if (grandTotal <= 0) return const SizedBox.shrink();

    final slices = <_Slice>[
      for (var index = 0; index < top.length; index++)
        _Slice(
          label: top[index].categoryName,
          totalPoisha: top[index].totalPoisha,
          color: _palette[index % _palette.length],
        ),
      if (otherTotal > 0)
        _Slice(
          label: 'Other',
          totalPoisha: otherTotal,
          color: theme.colorScheme.outline,
        ),
    ];

    return SectionCard(
      title: 'Expense split',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 52,
                sections: [
                  for (final slice in slices)
                    PieChartSectionData(
                      value: slice.totalPoisha.toDouble(),
                      color: slice.color,
                      radius: 56,
                      title:
                          '${(slice.totalPoisha / grandTotal * 100).toStringAsFixed(0)}%',
                      titleStyle: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (final slice in slices)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: slice.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      slice.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  MoneyText(
                    slice.totalPoisha,
                    showSign: false,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Slice {
  const _Slice({
    required this.label,
    required this.totalPoisha,
    required this.color,
  });

  final String label;
  final int totalPoisha;
  final Color color;
}

/// English label for each report window preset.
String _presetLabel(DateRangePreset preset) {
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
