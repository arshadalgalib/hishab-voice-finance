import '../../domain/enums.dart';
import '../../domain/models/aggregates.dart';
import '../../domain/models/date_range.dart';
import '../../domain/models/transaction_filter.dart';
import '../local/app_database.dart';

/// Read/write access to the transaction ledger.
///
/// Contains no business rules — validation and multi-step invariants live in
/// `TransactionService` — but every read path used by reports is funnelled
/// through here so there is exactly one definition of "income", "expense" and
/// "transfer".
class TransactionRepository {
  TransactionRepository(this._db);

  final AppDatabase _db;

  Stream<List<TransactionListItem>> watch(
    TransactionFilter filter, {
    int? limit,
    int? offset,
  }) => _db.watchTransactions(filter, limit: limit, offset: offset);

  Future<List<TransactionListItem>> list(
    TransactionFilter filter, {
    int? limit,
    int? offset,
  }) => _db.getTransactions(filter, limit: limit, offset: offset);

  Stream<TransactionListItem?> watchOne(String id) => _db.watchTransaction(id);

  Future<TransactionListItem?> find(String id) => _db.getTransaction(id);

  Future<TransactionRow?> findRow(String id) => _db.findTransactionRow(id);

  Future<List<TransactionRow>> rowsByGroup(String groupId) =>
      _db.findTransactionsByGroup(groupId);

  Stream<List<TransactionListItem>> watchRecent({int limit = 10}) =>
      _db.watchTransactions(const TransactionFilter(), limit: limit);

  Future<int> count({TransactionFilter? filter}) =>
      _db.countTransactions(filter: filter);

  Stream<PeriodSummary> watchSummary(DateRange range) =>
      _db.watchPeriodSummary(range);

  Future<PeriodSummary> summary(DateRange range) => _db.getPeriodSummary(range);

  Stream<List<CategoryTotal>> watchCategoryTotals({
    required CategoryKind kind,
    DateRange? range,
  }) => _db.watchCategoryTotals(kind: kind, range: range);

  Stream<List<TrendPoint>> watchTrend({
    required DateRange range,
    bool monthly = true,
  }) => _db.watchTrend(range: range, monthly: monthly);

  Future<int> expenseTotalForBudget({
    required DateRange range,
    String? categoryId,
    bool uncategorisedOnly = false,
  }) => _db.expenseTotalForBudget(
    range: range,
    categoryId: categoryId,
    uncategorisedOnly: uncategorisedOnly,
  );

  Stream<int> watchExpenseTotalForBudget({
    required DateRange range,
    String? categoryId,
    bool uncategorisedOnly = false,
  }) => _db.watchExpenseTotalForBudget(
    range: range,
    categoryId: categoryId,
    uncategorisedOnly: uncategorisedOnly,
  );

  Stream<List<String>> watchTags() => _db.watchAllTags();

  Future<TransactionListItem?> findProbableDuplicate({
    required TransactionType type,
    required int amountPoisha,
    required String walletId,
    required DateTime occurredAt,
    Duration window = const Duration(minutes: 5),
  }) => _db.findProbableDuplicate(
    type: type,
    amountPoisha: amountPoisha,
    walletId: walletId,
    occurredAt: occurredAt,
    window: window,
  );

  Future<void> insert(TransactionsCompanion transaction) =>
      _db.insertTransaction(transaction);

  Future<void> patch(String id, TransactionsCompanion patch) =>
      _db.updateTransactionRow(id, patch);

  Future<void> deleteRow(String id) => _db.deleteTransactionRow(id);

  Future<void> deleteGroup(String groupId) =>
      _db.deleteTransactionsByGroup(groupId);

  /// Every `day_key` that currently holds data — used to invalidate only the
  /// report periods that actually changed.
  Future<List<String>> distinctDayKeys() async {
    final rows = await _db
        .customSelect(
          'SELECT DISTINCT day_key FROM transactions ORDER BY day_key',
          readsFrom: {_db.transactions},
        )
        .get();
    return rows
        .map((row) => row.read<String>('day_key'))
        .toList(growable: false);
  }
}
