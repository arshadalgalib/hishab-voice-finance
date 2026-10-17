import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../../domain/enums.dart';
import '../../domain/models/aggregates.dart';
import '../../domain/models/date_range.dart';
import '../../domain/models/transaction_filter.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// The single source of truth for all financial data.
///
/// Every mutation that touches more than one row goes through
/// [transaction] so a failure can never leave a partially applied financial
/// operation (e.g. a transfer that debited the source but not the destination).
@DriftDatabase(
  tables: [
    Wallets,
    Categories,
    Transactions,
    Budgets,
    BudgetAlerts,
    SavingsGoals,
    GoalContributions,
    RecurringRules,
    Reminders,
    Loans,
    LoanPayments,
    AppSettings,
    AuditLogs,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _createIndices();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      // Sequential, forward-only migration steps. Each step must be
      // idempotent-safe and must never lose user data.
      if (from < 2) {
        // Reserved for schema v2.
      }
      await _createIndices();
    },
    beforeOpen: (details) async {
      // Foreign keys are what make the transfer CHECK constraints and the
      // cascade behaviour meaningful, so they must be enabled per
      // connection. Drift runs `beforeOpen` once for every connection.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _createIndices() async {
    const statements = <String>[
      'CREATE INDEX IF NOT EXISTS idx_tx_day_key ON transactions(day_key)',
      'CREATE INDEX IF NOT EXISTS idx_tx_wallet ON transactions(wallet_id)',
      'CREATE INDEX IF NOT EXISTS idx_tx_to_wallet ON transactions(to_wallet_id)',
      'CREATE INDEX IF NOT EXISTS idx_tx_category ON transactions(category_id)',
      'CREATE INDEX IF NOT EXISTS idx_tx_type_day ON transactions(type, day_key)',
      'CREATE INDEX IF NOT EXISTS idx_tx_transfer_group ON transactions(transfer_group_id)',
      'CREATE INDEX IF NOT EXISTS idx_wallet_archived ON wallets(is_archived)',
      'CREATE INDEX IF NOT EXISTS idx_category_kind ON categories(kind)',
      'CREATE INDEX IF NOT EXISTS idx_goal_contrib_goal ON goal_contributions(goal_id)',
    ];
    for (final statement in statements) {
      await customStatement(statement);
    }
  }

  /// Inserts [row], or updates the existing row selected by [match].
  ///
  /// drift's `insertOnConflictUpdate` validates its argument as a *complete*
  /// insert, so it cannot be used with the partial companions the repositories
  /// build for an in-place edit (`setArchived`, `markPosted`, …). This helper
  /// keeps those call sites correct: an existing row is updated field-by-field,
  /// a missing one is inserted.
  Future<void> _upsertRow<T extends Table, D>(
    TableInfo<T, D> table,
    Insertable<D> row,
    Expression<bool> Function(T table) match,
  ) async {
    final existing = await (select(table)..where(match)).getSingleOrNull();
    if (existing == null) {
      await into(table).insert(row);
    } else {
      await (update(table)..where(match)).write(row);
    }
  }

  // ─────────────────────────────────────────────────────────── wallets ──────

  Stream<List<WalletBalance>> watchWalletBalances({
    bool includeArchived = true,
  }) {
    return _walletBalanceSelect(includeArchived: includeArchived).watch().map(
      (rows) => rows.map(_mapWalletBalance).toList(growable: false),
    );
  }

  Future<List<WalletBalance>> getWalletBalances({
    bool includeArchived = true,
  }) async {
    final rows = await _walletBalanceSelect(
      includeArchived: includeArchived,
    ).get();
    return rows.map(_mapWalletBalance).toList(growable: false);
  }

  Future<WalletBalance?> getWalletBalance(String walletId) async {
    final rows = await _walletBalanceSelect(includeArchived: true).get();
    for (final row in rows) {
      if (row.read<String>('wallet_id') == walletId) {
        return _mapWalletBalance(row);
      }
    }
    return null;
  }

  Selectable<QueryRow> _walletBalanceSelect({required bool includeArchived}) {
    final where = includeArchived ? '' : 'WHERE w.is_archived = 0';
    return customSelect(
      '''
      SELECT w.id                                   AS wallet_id,
             w.name                                 AS name,
             w.type                                 AS type,
             w.institution                          AS institution,
             w.opening_balance_poisha               AS opening_balance_poisha,
             w.color_value                          AS color_value,
             w.icon_code_point                      AS icon_code_point,
             w.note                                 AS note,
             w.is_archived                          AS is_archived,
             w.is_default_income                    AS is_default_income,
             w.is_default_expense                   AS is_default_expense,
             w.opening_balance_poisha + COALESCE(SUM(
               CASE
                 WHEN t.type = 'income'   AND t.wallet_id    = w.id THEN  t.amount_poisha
                 WHEN t.type = 'expense'  AND t.wallet_id    = w.id THEN -t.amount_poisha
                 WHEN t.type = 'transfer' AND t.to_wallet_id = w.id THEN  t.amount_poisha
                 WHEN t.type = 'transfer' AND t.wallet_id    = w.id THEN -t.amount_poisha
                 ELSE 0
               END), 0)                               AS balance_poisha,
             COALESCE(SUM(
               CASE
                 WHEN t.type = 'income'   AND t.wallet_id    = w.id THEN t.amount_poisha
                 WHEN t.type = 'transfer' AND t.to_wallet_id = w.id THEN t.amount_poisha
                 ELSE 0
               END), 0)                               AS inflow_poisha,
             COALESCE(SUM(
               CASE
                 WHEN t.type = 'expense'  AND t.wallet_id = w.id THEN t.amount_poisha
                 WHEN t.type = 'transfer' AND t.wallet_id = w.id THEN t.amount_poisha
                 ELSE 0
               END), 0)                               AS outflow_poisha
      FROM wallets w
      LEFT JOIN transactions t
             ON t.wallet_id = w.id OR t.to_wallet_id = w.id
      $where
      GROUP BY w.id
      ORDER BY w.sort_order ASC, w.created_at ASC
      ''',
      readsFrom: {wallets, transactions},
    );
  }

  WalletBalance _mapWalletBalance(QueryRow row) {
    return WalletBalance(
      walletId: row.read<String>('wallet_id'),
      name: row.read<String>('name'),
      type: WalletType.fromId(row.read<String>('type')),
      institution: row.readNullable<String>('institution'),
      openingBalancePoisha: row.read<int>('opening_balance_poisha'),
      balancePoisha: row.read<int>('balance_poisha'),
      inflowPoisha: row.read<int>('inflow_poisha'),
      outflowPoisha: row.read<int>('outflow_poisha'),
      isArchived: row.read<bool>('is_archived'),
      isDefaultIncome: row.read<bool>('is_default_income'),
      isDefaultExpense: row.read<bool>('is_default_expense'),
      colorValue: row.readNullable<int>('color_value'),
      iconCodePoint: row.readNullable<int>('icon_code_point'),
      note: row.readNullable<String>('note'),
    );
  }

  Stream<List<WalletRow>> watchWalletRows({bool includeArchived = true}) {
    final query = select(wallets)
      ..orderBy([
        (t) => OrderingTerm.asc(t.sortOrder),
        (t) => OrderingTerm.asc(t.createdAt),
      ]);
    if (!includeArchived) {
      query.where((t) => t.isArchived.equals(false));
    }
    return query.watch();
  }

  Future<List<WalletRow>> getWalletRows({bool includeArchived = true}) {
    final query = select(wallets);
    if (!includeArchived) {
      query.where((t) => t.isArchived.equals(false));
    }
    return query.get();
  }

  Future<WalletRow?> findWalletById(String id) =>
      (select(wallets)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<WalletRow?> findWalletByName(String name) =>
      (select(wallets)
            ..where((t) => t.name.lower().equals(name.trim().toLowerCase()))
            ..limit(1))
          .getSingleOrNull();

  Future<int> nextWalletSortOrder() async {
    final row = await customSelect(
      'SELECT COALESCE(MAX(sort_order), -1) + 1 AS next FROM wallets',
      readsFrom: {wallets},
    ).getSingle();
    return row.read<int>('next');
  }

  Future<void> upsertWallet(WalletsCompanion wallet) => _upsertRow(
    wallets,
    wallet,
    (t) => t.id.equals(wallet.id.present ? wallet.id.value : ''),
  );

  /// Clears the "default wallet" flag for [kind], optionally keeping
  /// [exceptWalletId] set. Called before assigning a new default so exactly one
  /// wallet is ever the default for a kind.
  Future<void> clearDefaultWalletFlags({
    required CategoryKind kind,
    String? exceptWalletId,
  }) async {
    final column = kind == CategoryKind.income
        ? wallets.isDefaultIncome
        : wallets.isDefaultExpense;
    var predicate = column.equals(true);
    if (exceptWalletId != null) {
      predicate = predicate & wallets.id.equals(exceptWalletId).not();
    }
    await (update(wallets)..where((t) => predicate)).write(
      WalletsCompanion(
        isDefaultIncome: kind == CategoryKind.income
            ? const Value(false)
            : const Value.absent(),
        isDefaultExpense: kind == CategoryKind.expense
            ? const Value(false)
            : const Value.absent(),
      ),
    );
  }

  /// Recomputes and stores nothing — balances are always derived. This exists
  /// so callers can assert the derived total equals the sum of wallats, which
  /// is the invariant that protects against an independently editable total.
  Future<int> totalWalletBalancePoisha() async {
    final balances = await getWalletBalances();
    return balances
        .where((b) => !b.isArchived)
        .fold<int>(0, (sum, b) => sum + b.balancePoisha);
  }

  // ──────────────────────────────────────────────────────── categories ──────

  Stream<List<CategoryRow>> watchCategories({
    CategoryKind? kind,
    bool includeArchived = false,
  }) {
    final query = select(categories)
      ..orderBy([
        (t) => OrderingTerm.asc(t.sortOrder),
        (t) => OrderingTerm.asc(t.name),
      ]);
    if (kind != null) query.where((t) => t.kind.equalsValue(kind));
    if (!includeArchived) query.where((t) => t.isArchived.equals(false));
    return query.watch();
  }

  Future<List<CategoryRow>> getCategories({
    CategoryKind? kind,
    bool includeArchived = false,
  }) {
    final query = select(categories);
    if (kind != null) query.where((t) => t.kind.equalsValue(kind));
    if (!includeArchived) query.where((t) => t.isArchived.equals(false));
    return query.get();
  }

  Future<CategoryRow?> findCategoryById(String id) =>
      (select(categories)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<CategoryRow?> findCategoryByName(String name, {CategoryKind? kind}) {
    final query = select(categories)
      ..where((t) => t.name.lower().equals(name.trim().toLowerCase()))
      ..limit(1);
    if (kind != null) query.where((t) => t.kind.equalsValue(kind));
    return query.getSingleOrNull();
  }

  Future<void> upsertCategory(CategoriesCompanion category) => _upsertRow(
    categories,
    category,
    (t) => t.id.equals(category.id.present ? category.id.value : ''),
  );

  Future<int> countCategories() async {
    final row = await customSelect(
      'SELECT COUNT(*) AS c FROM categories',
      readsFrom: {categories},
    ).getSingle();
    return row.read<int>('c');
  }

  // ─────────────────────────────────────────────────────── transactions ─────

  static const String _transactionSelectColumns = '''
      t.id                AS id,
      t.type              AS type,
      t.amount_poisha     AS amount_poisha,
      t.occurred_at       AS occurred_at,
      t.wallet_id         AS wallet_id,
      w.name              AS wallet_name,
      t.to_wallet_id      AS to_wallet_id,
      w2.name             AS to_wallet_name,
      t.category_id       AS category_id,
      c.name              AS category_name,
      t.description       AS description,
      t.merchant          AS merchant,
      t.counterparty      AS counterparty,
      t.note              AS note,
      t.tags_json         AS tags_json,
      t.transfer_group_id AS transfer_group_id,
      t.fee_poisha        AS fee_poisha,
      t.source            AS source
  ''';

  static const String _transactionFrom = '''
    FROM transactions t
    JOIN wallets w   ON w.id = t.wallet_id
    LEFT JOIN wallets w2 ON w2.id = t.to_wallet_id
    LEFT JOIN categories c ON c.id = t.category_id
  ''';

  TransactionListItem _mapTransactionListItem(QueryRow row) {
    List<String> tags = const <String>[];
    final tagsJson = row.readNullable<String>('tags_json');
    if (tagsJson != null && tagsJson.isNotEmpty && tagsJson != '[]') {
      try {
        final decoded = jsonDecode(tagsJson);
        if (decoded is List) {
          tags = decoded.whereType<String>().toList(growable: false);
        }
      } on FormatException {
        tags = const <String>[];
      }
    }
    return TransactionListItem(
      id: row.read<String>('id'),
      type: TransactionType.fromId(row.read<String>('type')),
      amountPoisha: row.read<int>('amount_poisha'),
      occurredAt: row.read<DateTime>('occurred_at'),
      walletId: row.read<String>('wallet_id'),
      walletName: row.read<String>('wallet_name'),
      toWalletId: row.readNullable<String>('to_wallet_id'),
      toWalletName: row.readNullable<String>('to_wallet_name'),
      categoryId: row.readNullable<String>('category_id'),
      categoryName: row.readNullable<String>('category_name'),
      description: row.readNullable<String>('description'),
      merchant: row.readNullable<String>('merchant'),
      counterparty: row.readNullable<String>('counterparty'),
      note: row.readNullable<String>('note'),
      tags: tags,
      transferGroupId: row.readNullable<String>('transfer_group_id'),
      feePoisha: row.read<int>('fee_poisha'),
      source: TransactionSource.fromId(row.read<String>('source')),
    );
  }

  /// Builds the `WHERE` clause plus its bound variables for [filter].
  @visibleForTesting
  static (String, List<Variable<Object>>) buildFilterClause(
    TransactionFilter filter,
  ) {
    final conditions = <String>[];
    final variables = <Variable<Object>>[];

    final range = filter.range;
    if (range != null) {
      conditions.add('t.day_key BETWEEN ? AND ?');
      variables
        ..add(Variable.withString(range.dayKeyStart))
        ..add(Variable.withString(range.dayKeyEnd));
    }
    if (filter.types.isNotEmpty) {
      final placeholders = List.filled(filter.types.length, '?').join(', ');
      conditions.add('t.type IN ($placeholders)');
      variables.addAll(filter.types.map((t) => Variable.withString(t.name)));
    }
    if (filter.walletIds.isNotEmpty) {
      final placeholders = List.filled(filter.walletIds.length, '?').join(', ');
      conditions.add(
        '(t.wallet_id IN ($placeholders) OR t.to_wallet_id IN ($placeholders))',
      );
      variables
        ..addAll(filter.walletIds.map(Variable.withString))
        ..addAll(filter.walletIds.map(Variable.withString));
    }
    if (filter.categoryIds.isNotEmpty) {
      final placeholders = List.filled(
        filter.categoryIds.length,
        '?',
      ).join(', ');
      conditions.add('t.category_id IN ($placeholders)');
      variables.addAll(filter.categoryIds.map(Variable.withString));
    }
    if (filter.unresolvedCategoryOnly) {
      conditions.add('t.category_id IS NULL');
    }
    final search = filter.searchText?.trim();
    if (search != null && search.isNotEmpty) {
      conditions.add(
        '(LOWER(COALESCE(t.description, \'\')) LIKE ? '
        'OR LOWER(COALESCE(t.merchant, \'\')) LIKE ? '
        'OR LOWER(COALESCE(t.note, \'\')) LIKE ? '
        'OR LOWER(COALESCE(t.counterparty, \'\')) LIKE ?)',
      );
      final needle = '%${search.toLowerCase()}%';
      variables
        ..add(Variable.withString(needle))
        ..add(Variable.withString(needle))
        ..add(Variable.withString(needle))
        ..add(Variable.withString(needle));
    }
    if (filter.tags.isNotEmpty) {
      for (final tag in filter.tags) {
        conditions.add('t.tags_json LIKE ?');
        variables.add(Variable.withString('%"$tag"%'));
      }
    }
    if (filter.minAmountPoisha != null) {
      conditions.add('t.amount_poisha >= ?');
      variables.add(Variable.withInt(filter.minAmountPoisha!));
    }
    if (filter.maxAmountPoisha != null) {
      conditions.add('t.amount_poisha <= ?');
      variables.add(Variable.withInt(filter.maxAmountPoisha!));
    }

    final where = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';
    return (where, variables);
  }

  Selectable<QueryRow> transactionSelect(
    TransactionFilter filter, {
    int? limit,
    int? offset,
  }) {
    final (where, variables) = buildFilterClause(filter);
    final limitClause = limit == null ? '' : 'LIMIT ?';
    final offsetClause = limit != null && offset != null ? 'OFFSET ?' : '';
    final allVariables = <Variable<Object>>[
      ...variables,
      if (limit != null) Variable.withInt(limit),
      if (limit != null && offset != null) Variable.withInt(offset),
    ];
    return customSelect(
      'SELECT $_transactionSelectColumns $_transactionFrom $where '
      'ORDER BY ${filter.sort.sql} $limitClause $offsetClause',
      variables: allVariables,
      readsFrom: {transactions, wallets, categories},
    );
  }

  Stream<List<TransactionListItem>> watchTransactions(
    TransactionFilter filter, {
    int? limit,
    int? offset,
  }) {
    return transactionSelect(filter, limit: limit, offset: offset).watch().map(
      (rows) => rows.map(_mapTransactionListItem).toList(growable: false),
    );
  }

  Future<List<TransactionListItem>> getTransactions(
    TransactionFilter filter, {
    int? limit,
    int? offset,
  }) async {
    final rows = await transactionSelect(
      filter,
      limit: limit,
      offset: offset,
    ).get();
    return rows.map(_mapTransactionListItem).toList(growable: false);
  }

  Stream<TransactionListItem?> watchTransaction(String id) {
    return customSelect(
      'SELECT $_transactionSelectColumns $_transactionFrom WHERE t.id = ?',
      variables: [Variable.withString(id)],
      readsFrom: {transactions, wallets, categories},
    ).watchSingleOrNull().map(
      (row) => row == null ? null : _mapTransactionListItem(row),
    );
  }

  Future<TransactionListItem?> getTransaction(String id) async {
    final row = await customSelect(
      'SELECT $_transactionSelectColumns $_transactionFrom WHERE t.id = ?',
      variables: [Variable.withString(id)],
      readsFrom: {transactions, wallets, categories},
    ).getSingleOrNull();
    return row == null ? null : _mapTransactionListItem(row);
  }

  Future<TransactionRow?> findTransactionRow(String id) =>
      (select(transactions)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<TransactionRow>> findTransactionsByGroup(String groupId) =>
      (select(
        transactions,
      )..where((t) => t.transferGroupId.equals(groupId))).get();

  Future<void> insertTransaction(TransactionsCompanion transaction) =>
      into(transactions).insert(transaction);

  Future<void> updateTransactionRow(String id, TransactionsCompanion patch) =>
      (update(transactions)..where((t) => t.id.equals(id))).write(patch);

  Future<void> deleteTransactionRow(String id) =>
      (delete(transactions)..where((t) => t.id.equals(id))).go();

  Future<void> deleteTransactionsByGroup(String groupId) => (delete(
    transactions,
  )..where((t) => t.transferGroupId.equals(groupId))).go();

  Future<int> countTransactions({TransactionFilter? filter}) async {
    final (where, variables) = buildFilterClause(
      filter ?? const TransactionFilter(),
    );
    final row = await customSelect(
      'SELECT COUNT(*) AS c $_transactionFrom $where',
      variables: variables,
      readsFrom: {transactions, wallets, categories},
    ).getSingle();
    return row.read<int>('c');
  }

  /// Totals for a period. Transfers are reported separately and are excluded
  /// from income and expense so internal movement cannot inflate either.
  Stream<PeriodSummary> watchPeriodSummary(DateRange range) {
    return customSelect(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN t.type = 'income'   THEN t.amount_poisha ELSE 0 END), 0) AS income_poisha,
        COALESCE(SUM(CASE WHEN t.type = 'expense'  THEN t.amount_poisha ELSE 0 END), 0) AS expense_poisha,
        COALESCE(SUM(CASE WHEN t.type = 'transfer' THEN t.amount_poisha ELSE 0 END), 0) AS transfer_poisha,
        COALESCE(SUM(CASE WHEN t.type = 'income'   THEN 1 ELSE 0 END), 0) AS income_count,
        COALESCE(SUM(CASE WHEN t.type = 'expense'  THEN 1 ELSE 0 END), 0) AS expense_count,
        COALESCE(SUM(CASE WHEN t.type = 'transfer' THEN 1 ELSE 0 END), 0) AS transfer_count
      FROM transactions t
      WHERE t.day_key BETWEEN ? AND ?
      ''',
      variables: [
        Variable.withString(range.dayKeyStart),
        Variable.withString(range.dayKeyEnd),
      ],
      readsFrom: {transactions},
    ).watchSingle().map(_mapPeriodSummary);
  }

  Future<PeriodSummary> getPeriodSummary(DateRange range) async {
    final row = await customSelect(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN t.type = 'income'   THEN t.amount_poisha ELSE 0 END), 0) AS income_poisha,
        COALESCE(SUM(CASE WHEN t.type = 'expense'  THEN t.amount_poisha ELSE 0 END), 0) AS expense_poisha,
        COALESCE(SUM(CASE WHEN t.type = 'transfer' THEN t.amount_poisha ELSE 0 END), 0) AS transfer_poisha,
        COALESCE(SUM(CASE WHEN t.type = 'income'   THEN 1 ELSE 0 END), 0) AS income_count,
        COALESCE(SUM(CASE WHEN t.type = 'expense'  THEN 1 ELSE 0 END), 0) AS expense_count,
        COALESCE(SUM(CASE WHEN t.type = 'transfer' THEN 1 ELSE 0 END), 0) AS transfer_count
      FROM transactions t
      WHERE t.day_key BETWEEN ? AND ?
      ''',
      variables: [
        Variable.withString(range.dayKeyStart),
        Variable.withString(range.dayKeyEnd),
      ],
      readsFrom: {transactions},
    ).getSingle();
    return _mapPeriodSummary(row);
  }

  PeriodSummary _mapPeriodSummary(QueryRow row) => PeriodSummary(
    incomePoisha: row.read<int>('income_poisha'),
    expensePoisha: row.read<int>('expense_poisha'),
    transferVolumePoisha: row.read<int>('transfer_poisha'),
    incomeCount: row.read<int>('income_count'),
    expenseCount: row.read<int>('expense_count'),
    transferCount: row.read<int>('transfer_count'),
  );

  /// Expense (or income) totals grouped by category. `transfer` rows are
  /// always excluded.
  Stream<List<CategoryTotal>> watchCategoryTotals({
    required CategoryKind kind,
    DateRange? range,
  }) {
    final typeName = kind == CategoryKind.income ? 'income' : 'expense';
    final rangeClause = range == null ? '' : ' AND t.day_key BETWEEN ? AND ?';
    return customSelect(
      '''
      SELECT t.category_id            AS category_id,
             COALESCE(c.name, 'Uncategorised') AS category_name,
             c.color_value            AS color_value,
             c.icon_name              AS icon_name,
             COALESCE(SUM(t.amount_poisha), 0) AS total_poisha,
             COUNT(*)                 AS tx_count
      FROM transactions t
      LEFT JOIN categories c ON c.id = t.category_id
      WHERE t.type = '$typeName'$rangeClause
      GROUP BY t.category_id
      ORDER BY total_poisha DESC
      ''',
      variables: [
        if (range != null) Variable.withString(range.dayKeyStart),
        if (range != null) Variable.withString(range.dayKeyEnd),
      ],
      readsFrom: {transactions, categories},
    ).watch().map(
      (rows) => rows
          .map((row) {
            return CategoryTotal(
              categoryId: row.readNullable<String>('category_id'),
              categoryName: row.read<String>('category_name'),
              kind: kind,
              totalPoisha: row.read<int>('total_poisha'),
              transactionCount: row.read<int>('tx_count'),
              colorValue: row.readNullable<int>('color_value'),
              iconName: row.readNullable<String>('icon_name'),
            );
          })
          .toList(growable: false),
    );
  }

  /// Bucketed income/expense trend. [monthly] groups by `yyyy-MM`, otherwise
  /// by `yyyy-MM-dd`.
  Stream<List<TrendPoint>> watchTrend({
    required DateRange range,
    bool monthly = true,
  }) {
    final bucket = monthly ? 'substr(t.day_key, 1, 7)' : 't.day_key';
    return customSelect(
      '''
      SELECT $bucket AS bucket_key,
        COALESCE(SUM(CASE WHEN t.type = 'income'  THEN t.amount_poisha ELSE 0 END), 0) AS income_poisha,
        COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount_poisha ELSE 0 END), 0) AS expense_poisha
      FROM transactions t
      WHERE t.day_key BETWEEN ? AND ? AND t.type <> 'transfer'
      GROUP BY bucket_key
      ORDER BY bucket_key ASC
      ''',
      variables: [
        Variable.withString(range.dayKeyStart),
        Variable.withString(range.dayKeyEnd),
      ],
      readsFrom: {transactions},
    ).watch().map(
      (rows) => rows
          .map(
            (row) => TrendPoint(
              bucketKey: row.read<String>('bucket_key'),
              label: row.read<String>('bucket_key'),
              incomePoisha: row.read<int>('income_poisha'),
              expensePoisha: row.read<int>('expense_poisha'),
            ),
          )
          .toList(growable: false),
    );
  }

  /// Sum of expenses for a budget. [categoryId] of `null` means "all expense
  /// categories"; [uncategorisedOnly] restricts to rows with no category.
  Future<int> expenseTotalForBudget({
    required DateRange range,
    String? categoryId,
    bool uncategorisedOnly = false,
  }) async {
    var sql = '''
      SELECT COALESCE(SUM(t.amount_poisha), 0) AS total
      FROM transactions t
      WHERE t.type = 'expense' AND t.day_key BETWEEN ? AND ?
    ''';
    final variables = <Variable<Object>>[
      Variable.withString(range.dayKeyStart),
      Variable.withString(range.dayKeyEnd),
    ];
    if (uncategorisedOnly) {
      sql += ' AND t.category_id IS NULL';
    } else if (categoryId != null) {
      sql += ' AND t.category_id = ?';
      variables.add(Variable.withString(categoryId));
    }
    final row = await customSelect(
      sql,
      variables: variables,
      readsFrom: {transactions},
    ).getSingle();
    return row.read<int>('total');
  }

  Stream<int> watchExpenseTotalForBudget({
    required DateRange range,
    String? categoryId,
    bool uncategorisedOnly = false,
  }) {
    var sql = '''
      SELECT COALESCE(SUM(t.amount_poisha), 0) AS total
      FROM transactions t
      WHERE t.type = 'expense' AND t.day_key BETWEEN ? AND ?
    ''';
    final variables = <Variable<Object>>[
      Variable.withString(range.dayKeyStart),
      Variable.withString(range.dayKeyEnd),
    ];
    if (uncategorisedOnly) {
      sql += ' AND t.category_id IS NULL';
    } else if (categoryId != null) {
      sql += ' AND t.category_id = ?';
      variables.add(Variable.withString(categoryId));
    }
    return customSelect(
      sql,
      variables: variables,
      readsFrom: {transactions},
    ).watchSingle().map((row) => row.read<int>('total'));
  }

  /// Distinct tags across all transactions, de-duplicated and sorted.
  Stream<List<String>> watchAllTags() {
    return customSelect(
      "SELECT tags_json FROM transactions WHERE tags_json <> '[]'",
      readsFrom: {transactions},
    ).watch().map((rows) {
      final tags = <String>{};
      for (final row in rows) {
        final raw = row.readNullable<String>('tags_json');
        if (raw == null || raw.isEmpty) continue;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) tags.addAll(decoded.whereType<String>());
        } on FormatException {
          // Ignore malformed tag payloads rather than breaking the list.
        }
      }
      final sorted = tags.toList()..sort();
      return sorted;
    });
  }

  /// Detects a probable duplicate of a transaction being created.
  Future<TransactionListItem?> findProbableDuplicate({
    required TransactionType type,
    required int amountPoisha,
    required String walletId,
    required DateTime occurredAt,
    Duration window = const Duration(minutes: 5),
  }) async {
    final range = DateRange(
      occurredAt.subtract(window),
      occurredAt.add(window),
    );
    final candidates = await getTransactions(
      TransactionFilter(
        range: range,
        types: {type},
        walletIds: {walletId},
        minAmountPoisha: amountPoisha,
        maxAmountPoisha: amountPoisha,
      ),
    );
    return candidates.isEmpty ? null : candidates.first;
  }

  // ──────────────────────────────────────────────────────────── budgets ─────

  Stream<List<BudgetRow>> watchBudgets({bool includeInactive = true}) {
    final query = select(budgets)
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    if (!includeInactive) query.where((t) => t.isActive.equals(true));
    return query.watch();
  }

  Future<List<BudgetRow>> getBudgets({bool includeInactive = true}) {
    final query = select(budgets);
    if (!includeInactive) query.where((t) => t.isActive.equals(true));
    return query.get();
  }

  Future<void> upsertBudget(BudgetsCompanion budget) => _upsertRow(
    budgets,
    budget,
    (t) => t.id.equals(budget.id.present ? budget.id.value : ''),
  );

  Future<void> deleteBudget(String id) =>
      (delete(budgets)..where((t) => t.id.equals(id))).go();

  Future<bool> hasBudgetAlert({
    required String budgetId,
    required String periodKey,
    required int thresholdPercent,
  }) async {
    final row =
        await (select(budgetAlerts)
              ..where(
                (t) =>
                    t.budgetId.equals(budgetId) &
                    t.periodKey.equals(periodKey) &
                    t.thresholdPercent.equals(thresholdPercent),
              )
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  Future<void> recordBudgetAlert(BudgetAlertsCompanion alert) => _upsertRow(
    budgetAlerts,
    alert,
    (t) => t.id.equals(alert.id.present ? alert.id.value : ''),
  );

  Future<void> pruneBudgetAlerts(
    String budgetId, {
    required String keepPeriodKey,
  }) =>
      (delete(budgetAlerts)..where(
            (t) =>
                t.budgetId.equals(budgetId) &
                t.periodKey.isNotValue(keepPeriodKey),
          ))
          .go();

  // ──────────────────────────────────────────────────────── savings goals ───

  Stream<List<SavingsGoalRow>> watchSavingsGoals() => (select(
    savingsGoals,
  )..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).watch();

  Future<List<SavingsGoalRow>> getSavingsGoals() => select(savingsGoals).get();

  Future<SavingsGoalRow?> findSavingsGoal(String id) =>
      (select(savingsGoals)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> upsertSavingsGoal(SavingsGoalsCompanion goal) => _upsertRow(
    savingsGoals,
    goal,
    (t) => t.id.equals(goal.id.present ? goal.id.value : ''),
  );

  Future<void> deleteSavingsGoal(String id) =>
      (delete(savingsGoals)..where((t) => t.id.equals(id))).go();

  Stream<List<GoalContributionRow>> watchGoalContributions(String goalId) =>
      (select(goalContributions)
            ..where((t) => t.goalId.equals(goalId))
            ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
          .watch();

  Future<List<GoalContributionRow>> getGoalContributions(String goalId) =>
      (select(goalContributions)
            ..where((t) => t.goalId.equals(goalId))
            ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
          .get();

  Future<int> totalGoalContributions(String goalId) async {
    final row = await customSelect(
      'SELECT COALESCE(SUM(amount_poisha), 0) AS total FROM goal_contributions WHERE goal_id = ?',
      variables: [Variable.withString(goalId)],
      readsFrom: {goalContributions},
    ).getSingle();
    return row.read<int>('total');
  }

  Future<void> upsertGoalContribution(
    GoalContributionsCompanion contribution,
  ) => _upsertRow(
    goalContributions,
    contribution,
    (t) => t.id.equals(contribution.id.present ? contribution.id.value : ''),
  );

  Future<void> deleteGoalContribution(String id) =>
      (delete(goalContributions)..where((t) => t.id.equals(id))).go();

  // ───────────────────────────────────────────────────────── recurring ──────

  Stream<List<RecurringRuleRow>> watchRecurringRules() => (select(
    recurringRules,
  )..orderBy([(t) => OrderingTerm.asc(t.nextDueDate)])).watch();

  Future<List<RecurringRuleRow>> getRecurringRules() =>
      select(recurringRules).get();

  Future<RecurringRuleRow?> findRecurringRule(String id) =>
      (select(recurringRules)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> upsertRecurringRule(RecurringRulesCompanion rule) => _upsertRow(
    recurringRules,
    rule,
    (t) => t.id.equals(rule.id.present ? rule.id.value : ''),
  );

  Future<void> deleteRecurringRule(String id) =>
      (delete(recurringRules)..where((t) => t.id.equals(id))).go();

  // ────────────────────────────────────────────────────────── reminders ─────

  Stream<List<ReminderRow>> watchReminders({bool includePaid = true}) {
    final query = select(reminders)
      ..orderBy([(t) => OrderingTerm.asc(t.dueDate)]);
    if (!includePaid) query.where((t) => t.isPaid.equals(false));
    return query.watch();
  }

  Future<List<ReminderRow>> getReminders({bool includePaid = true}) {
    final query = select(reminders);
    if (!includePaid) query.where((t) => t.isPaid.equals(false));
    return query.get();
  }

  Future<void> upsertReminder(RemindersCompanion reminder) => _upsertRow(
    reminders,
    reminder,
    (t) => t.id.equals(reminder.id.present ? reminder.id.value : ''),
  );

  Future<void> deleteReminder(String id) =>
      (delete(reminders)..where((t) => t.id.equals(id))).go();

  // ────────────────────────────────────────────────────────────── loans ─────

  Stream<List<LoanRow>> watchLoans() => (select(
    loans,
  )..orderBy([(t) => OrderingTerm.desc(t.occurredAt)])).watch();

  Future<List<LoanRow>> getLoans() =>
      (select(loans)..orderBy([(t) => OrderingTerm.desc(t.occurredAt)])).get();

  Future<LoanRow?> findLoan(String id) =>
      (select(loans)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> upsertLoan(LoansCompanion loan) => _upsertRow(
    loans,
    loan,
    (t) => t.id.equals(loan.id.present ? loan.id.value : ''),
  );

  Future<void> deleteLoan(String id) =>
      (delete(loans)..where((t) => t.id.equals(id))).go();

  Stream<List<LoanPaymentRow>> watchLoanPayments(String loanId) =>
      (select(loanPayments)
            ..where((t) => t.loanId.equals(loanId))
            ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
          .watch();

  Future<int> totalLoanPayments(String loanId) async {
    final row = await customSelect(
      'SELECT COALESCE(SUM(amount_poisha), 0) AS total FROM loan_payments WHERE loan_id = ?',
      variables: [Variable.withString(loanId)],
      readsFrom: {loanPayments},
    ).getSingle();
    return row.read<int>('total');
  }

  Future<void> upsertLoanPayment(LoanPaymentsCompanion payment) => _upsertRow(
    loanPayments,
    payment,
    (t) => t.id.equals(payment.id.present ? payment.id.value : ''),
  );

  Future<void> deleteLoanPayment(String id) =>
      (delete(loanPayments)..where((t) => t.id.equals(id))).go();

  // ─────────────────────────────────────────────────────── app settings ─────

  Future<String?> readSetting(String key) async {
    final row = await (select(
      appSettings,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Stream<String?> watchSetting(String key) =>
      (select(appSettings)..where((t) => t.key.equals(key)))
          .watchSingleOrNull()
          .map((row) => row?.value);

  Future<Map<String, String>> readAllSettings() async {
    final rows = await select(appSettings).get();
    return {for (final row in rows) row.key: row.value};
  }

  Future<void> writeSetting(String key, String value) =>
      into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: key,
          value: value,
          updatedAt: DateTime.now(),
        ),
      );

  Future<void> deleteSetting(String key) =>
      (delete(appSettings)..where((t) => t.key.equals(key))).go();

  // ───────────────────────────────────────────────────────── audit log ─────

  Future<void> writeAuditLog({
    required String entityType,
    required String action,
    String? entityId,
    Map<String, Object?> payload = const <String, Object?>{},
  }) {
    return into(auditLogs).insert(
      AuditLogsCompanion.insert(
        id: 'audit-${DateTime.now().microsecondsSinceEpoch}-${_auditCounter++}',
        entityType: entityType,
        action: action,
        entityId: Value(entityId),
        payloadJson: Value(jsonEncode(payload)),
        createdAt: DateTime.now(),
      ),
    );
  }

  Stream<List<AuditLogRow>> watchAuditLogs({int limit = 200}) =>
      (select(auditLogs)
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
            ..limit(limit))
          .watch();

  Future<List<AuditLogRow>> getAuditLogs({int limit = 500}) =>
      (select(auditLogs)
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
            ..limit(limit))
          .get();

  // ──────────────────────────────────────────────────────── maintenance ─────

  /// Deletes every user row inside a single transaction. Used by
  /// "clear all data" and by a replace-style restore.
  Future<void> clearAllData() => transaction(() async {
    await delete(transactions).go();
    await delete(goalContributions).go();
    await delete(savingsGoals).go();
    await delete(budgetAlerts).go();
    await delete(budgets).go();
    await delete(recurringRules).go();
    await delete(reminders).go();
    await delete(loanPayments).go();
    await delete(loans).go();
    await delete(categories).go();
    await delete(wallets).go();
    await delete(auditLogs).go();
    await delete(appSettings).go();
  });

  Future<int> _countOf(TableInfo table) async {
    final name = table.actualTableName;
    final row = await customSelect(
      'SELECT COUNT(*) AS c FROM $name',
    ).getSingle();
    return row.read<int>('c');
  }

  Future<Map<String, int>> tableCounts() async {
    return {
      'wallets': await _countOf(wallets),
      'categories': await _countOf(categories),
      'transactions': await _countOf(transactions),
      'budgets': await _countOf(budgets),
      'savingsGoals': await _countOf(savingsGoals),
      'goalContributions': await _countOf(goalContributions),
      'recurringRules': await _countOf(recurringRules),
      'reminders': await _countOf(reminders),
      'loans': await _countOf(loans),
      'loanPayments': await _countOf(loanPayments),
      'appSettings': await _countOf(appSettings),
      'auditLogs': await _countOf(auditLogs),
    };
  }

  /// Runs `PRAGMA integrity_check`. Used before exporting a backup so a
  /// corrupt database is never exported as if it were valid.
  Future<String> integrityCheck() async {
    final row = await customSelect('PRAGMA integrity_check').getSingle();
    return row.data.values.first?.toString() ?? 'unknown';
  }

  static int _auditCounter = 0;
}
