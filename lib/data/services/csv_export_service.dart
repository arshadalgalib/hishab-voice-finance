import 'package:csv/csv.dart';

import '../../core/utils/money.dart';
import '../../domain/enums.dart';
import '../../domain/models/aggregates.dart';
import '../../domain/models/date_range.dart';
import '../../domain/models/transaction_filter.dart';
import '../repositories/transaction_repository.dart';

/// CSV export for spreadsheets.
///
/// Amounts are written as plain ASCII decimal taka (`1234.50`) with a separate
/// currency column, and dates as ISO-8601, so the file opens correctly in Excel,
/// LibreOffice and Google Sheets without any locale guessing. Bengali numerals
/// are never used in exports, because most spreadsheet software cannot parse
/// them as numbers.
class CsvExportService {
  CsvExportService({required TransactionRepository transactions})
    : _transactions = transactions;

  final TransactionRepository _transactions;

  /// UTF-8 BOM so Excel opens the file as UTF-8 and Bengali text survives.
  static final Csv _csv = Csv(addBom: true);

  static const List<String> transactionHeaders = <String>[
    'id',
    'date',
    'time',
    'type',
    'amount_bdt',
    'currency',
    'wallet',
    'destination_wallet',
    'category',
    'description',
    'merchant',
    'counterparty',
    'note',
    'tags',
    'fee_bdt',
    'recorded_by',
    'transfer_group_id',
  ];

  /// Exports every transaction matching [filter].
  Future<String> exportTransactions({
    TransactionFilter filter = const TransactionFilter(),
  }) async {
    final rows = await _transactions.list(filter);
    final table = <List<Object?>>[transactionHeaders];
    for (final item in rows) {
      table.add(_toRow(item));
    }
    return _csv.encode(table);
  }

  /// Exports the per-category totals for a period, which is what most people
  /// actually want in a spreadsheet.
  Future<String> exportCategoryTotals({
    required DateRange range,
    CategoryKind kind = CategoryKind.expense,
  }) async {
    final totals = await _transactions
        .watchCategoryTotals(kind: kind, range: range)
        .first;
    final table = <List<Object?>>[
      <String>['category', 'type', 'total_bdt', 'currency', 'transactions'],
      for (final total in totals)
        <Object?>[
          total.categoryName,
          total.kind.name,
          Money(total.totalPoisha).toStorageString(),
          'BDT',
          total.transactionCount,
        ],
    ];
    return _csv.encode(table);
  }

  /// Exports a period summary (income, expense, transfers kept separate).
  Future<String> exportSummary(DateRange range) async {
    final summary = await _transactions.summary(range);
    final table = <List<Object?>>[
      <String>['metric', 'amount_bdt', 'currency', 'count'],
      <Object?>[
        'income',
        Money(summary.incomePoisha).toStorageString(),
        'BDT',
        summary.incomeCount,
      ],
      <Object?>[
        'expense',
        Money(summary.expensePoisha).toStorageString(),
        'BDT',
        summary.expenseCount,
      ],
      <Object?>[
        'net_cash_flow',
        Money(summary.netCashFlowPoisha).toStorageString(),
        'BDT',
        null,
      ],
      <Object?>[
        'transfers',
        Money(summary.transferVolumePoisha).toStorageString(),
        'BDT',
        summary.transferCount,
      ],
      <Object?>['period', range.label, null, null],
    ];
    return _csv.encode(table);
  }

  List<Object?> _toRow(TransactionListItem item) {
    final local = item.occurredAt.toLocal();
    final date =
        '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
    final time =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    return <Object?>[
      item.id,
      date,
      time,
      item.type.name,
      Money(item.amountPoisha).toStorageString(),
      'BDT',
      item.walletName,
      item.toWalletName ?? '',
      item.categoryName ?? '',
      item.description ?? '',
      item.merchant ?? '',
      item.counterparty ?? '',
      item.note ?? '',
      item.tags.join('|'),
      Money(item.feePoisha).toStorageString(),
      item.source.name,
      item.transferGroupId ?? '',
    ];
  }

  /// Suggested file name, e.g. `pfm-transactions-20260311.csv`.
  static String fileName(String prefix, DateTime now) {
    final stamp =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    return 'pfm-$prefix-$stamp.csv';
  }
}
