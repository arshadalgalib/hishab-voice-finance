import 'package:drift/drift.dart';

import '../../domain/enums.dart';

/// Drift table definitions.
///
/// Naming: drift converts Dart getters to `snake_case` SQL column names.
///
/// ## Transfer modelling decision
///
/// A wallet transfer is stored as **one logical row** in [Transactions] with
/// `walletId` = source wallet and `toWalletId` = destination wallet, and
/// `type` = `transfer`. This is enforced by a table-level `CHECK` constraint so
/// a half-transfer can never exist. Reports exclude `type = 'transfer'` from
/// income and expense totals, therefore an internal transfer can never inflate
/// income or spending. A transfer fee is recorded as a separate linked
/// `expense` row sharing the same `transfer_group_id`.
@DataClassName('WalletRow')
class Wallets extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get type => textEnum<WalletType>()();
  TextColumn get institution => text().nullable()();

  /// Opening balance in poisha. Adjustments are recorded in `audit_logs`.
  IntColumn get openingBalancePoisha =>
      integer().withDefault(const Constant(0))();

  IntColumn get colorValue => integer().nullable()();
  IntColumn get iconCodePoint => integer().nullable()();
  TextColumn get note => text().nullable()();

  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  BoolColumn get isDefaultIncome =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isDefaultExpense =>
      boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const ['CHECK (length(name) > 0)'];
}

@DataClassName('CategoryRow')
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get kind => textEnum<CategoryKind>()();
  TextColumn get iconName => text().nullable()();
  IntColumn get colorValue => integer().nullable()();

  /// Comma separated synonyms used by the voice parser, e.g.
  /// `বাজার,মুদি,grocery,bazar`.
  TextColumn get keywords => text().nullable()();

  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'CHECK (kind IN (\'income\', \'expense\'))',
  ];
}

@DataClassName('TransactionRow')
class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get type => textEnum<TransactionType>()();

  /// Always a positive integer number of poisha. Direction is carried by
  /// [type]; validation rejects zero and negative amounts.
  IntColumn get amountPoisha => integer()();

  /// For `income` this is the *destination* wallet.
  /// For `expense` this is the *source* wallet.
  /// For `transfer` this is the *source* wallet.
  TextColumn get walletId => text().customConstraint(
    'NOT NULL REFERENCES wallets (id) ON DELETE RESTRICT',
  )();

  /// Only set for `transfer`: the destination wallet.
  TextColumn get toWalletId => text().nullable().customConstraint(
    'REFERENCES wallets (id) ON DELETE RESTRICT',
  )();

  TextColumn get categoryId => text().nullable().customConstraint(
    'REFERENCES categories (id) ON DELETE SET NULL',
  )();

  DateTimeColumn get occurredAt => dateTime()();

  /// Derived `yyyy-MM-dd` key for fast, index friendly day-range filtering.
  TextColumn get dayKey => text().withLength(min: 10, max: 10)();

  TextColumn get description => text().nullable()();
  TextColumn get merchant => text().nullable()();

  /// Payer (income) or recipient (expense/loan) when known.
  TextColumn get counterparty => text().nullable()();
  TextColumn get note => text().nullable()();

  /// JSON array of tag strings.
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();

  /// Shared identifier between a transfer and its optional fee expense.
  TextColumn get transferGroupId => text().nullable()();

  /// Fee in poisha for a transfer (informational; the fee itself is a linked
  /// expense row so it flows through normal expense reporting).
  IntColumn get feePoisha => integer().withDefault(const Constant(0))();

  TextColumn get source => textEnum<TransactionSource>()();
  TextColumn get recurringRuleId => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'CHECK (amount_poisha > 0)',
    // A transfer must have a destination, and only a transfer may have one.
    'CHECK ((type = \'transfer\' AND to_wallet_id IS NOT NULL AND to_wallet_id <> wallet_id)'
        ' OR (type <> \'transfer\' AND to_wallet_id IS NULL))',
    // Income and expense must not carry a fee.
    'CHECK (type = \'transfer\' OR fee_poisha = 0)',
  ];
}

@DataClassName('BudgetRow')
class Budgets extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 80)();

  /// `null` means an overall budget across every expense category.
  TextColumn get categoryId => text().nullable().customConstraint(
    'REFERENCES categories (id) ON DELETE SET NULL',
  )();

  IntColumn get amountPoisha => integer()();
  TextColumn get period => textEnum<BudgetPeriod>()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();

  /// Percentage of the budget at which the user wants to be warned (1..100).
  IntColumn get alertThresholdPercent =>
      integer().withDefault(const Constant(80))();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get colorValue => integer().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'CHECK (amount_poisha > 0)',
    'CHECK (alert_threshold_percent BETWEEN 1 AND 100)',
  ];
}

/// Prevents repeat notifications for the same budget + period + threshold.
@DataClassName('BudgetAlertRow')
class BudgetAlerts extends Table {
  TextColumn get id => text()();
  TextColumn get budgetId => text().customConstraint(
    'NOT NULL REFERENCES budgets (id) ON DELETE CASCADE',
  )();

  /// e.g. `2026-03` for monthly budgets, `2026-03-11` for weekly ones.
  TextColumn get periodKey => text()();
  IntColumn get thresholdPercent => integer()();
  DateTimeColumn get notifiedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column>>? get uniqueKeys => [
    {budgetId, periodKey, thresholdPercent},
  ];
}

@DataClassName('SavingsGoalRow')
class SavingsGoals extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  IntColumn get targetPoisha => integer()();
  DateTimeColumn get targetDate => dateTime().nullable()();

  /// When set, progress is the current balance of this wallet. Otherwise
  /// progress is the sum of explicit contributions.
  TextColumn get walletId => text().nullable().customConstraint(
    'REFERENCES wallets (id) ON DELETE SET NULL',
  )();

  TextColumn get note => text().nullable()();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  IntColumn get colorValue => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const ['CHECK (target_poisha > 0)'];
}

@DataClassName('GoalContributionRow')
class GoalContributions extends Table {
  TextColumn get id => text()();
  TextColumn get goalId => text().customConstraint(
    'NOT NULL REFERENCES savings_goals (id) ON DELETE CASCADE',
  )();
  IntColumn get amountPoisha => integer()();
  DateTimeColumn get occurredAt => dateTime()();

  /// When set, the contribution was funded by a transfer out of this wallet.
  TextColumn get fromWalletId => text().nullable().customConstraint(
    'REFERENCES wallets (id) ON DELETE SET NULL',
  )();

  /// The transfer created for this contribution, if any (for undo / delete).
  TextColumn get transferId => text().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const ['CHECK (amount_poisha > 0)'];
}

@DataClassName('RecurringRuleRow')
class RecurringRules extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get type => textEnum<TransactionType>()();
  IntColumn get amountPoisha => integer()();
  TextColumn get walletId => text().customConstraint(
    'NOT NULL REFERENCES wallets (id) ON DELETE RESTRICT',
  )();
  TextColumn get toWalletId => text().nullable().customConstraint(
    'REFERENCES wallets (id) ON DELETE SET NULL',
  )();
  TextColumn get categoryId => text().nullable()();
  TextColumn get description => text().nullable()();

  TextColumn get frequency => textEnum<RecurrenceFrequency>()();
  IntColumn get intervalCount => integer().withDefault(const Constant(1))();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get nextDueDate => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();

  /// When false the rule only produces a *reminder* the user must confirm,
  /// which is the default. Posting automatically is always opt-in.
  BoolColumn get autoPost => boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get lastPostedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'CHECK (amount_poisha > 0)',
    'CHECK (interval_count >= 1)',
    'CHECK (type <> \'transfer\' OR to_wallet_id IS NOT NULL)',
  ];
}

@DataClassName('ReminderRow')
class Reminders extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 120)();
  IntColumn get amountPoisha => integer().nullable()();
  DateTimeColumn get dueDate => dateTime()();
  TextColumn get walletId => text().nullable().customConstraint(
    'REFERENCES wallets (id) ON DELETE SET NULL',
  )();
  TextColumn get categoryId => text().nullable()();
  BoolColumn get isPaid => boolean().withDefault(const Constant(false))();
  TextColumn get note => text().nullable()();
  IntColumn get reminderDaysBefore =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('LoanRow')
class Loans extends Table {
  TextColumn get id => text()();
  TextColumn get counterparty => text().withLength(min: 1, max: 120)();
  TextColumn get direction => textEnum<LoanDirection>()();
  IntColumn get principalPoisha => integer()();
  DateTimeColumn get occurredAt => dateTime()();
  DateTimeColumn get dueDate => dateTime().nullable()();

  /// Wallet the money left from (lent) or arrived in (borrowed).
  TextColumn get walletId => text().nullable().customConstraint(
    'REFERENCES wallets (id) ON DELETE SET NULL',
  )();

  BoolColumn get isSettled => boolean().withDefault(const Constant(false))();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const ['CHECK (principal_poisha > 0)'];
}

@DataClassName('LoanPaymentRow')
class LoanPayments extends Table {
  TextColumn get id => text()();
  TextColumn get loanId => text().customConstraint(
    'NOT NULL REFERENCES loans (id) ON DELETE CASCADE',
  )();
  IntColumn get amountPoisha => integer()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get walletId => text().nullable().customConstraint(
    'REFERENCES wallets (id) ON DELETE SET NULL',
  )();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const ['CHECK (amount_poisha > 0)'];
}

/// Simple key/value store for user preferences.
@DataClassName('AppSettingRow')
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Append-only audit trail. Opening-balance adjustments, restores, bulk
/// imports and wallet archives are all recorded here so the user can see why a
/// balance changed.
@DataClassName('AuditLogRow')
class AuditLogs extends Table {
  TextColumn get id => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text().nullable()();
  TextColumn get action => text()();

  /// JSON payload. Financial *statements* are not stored here; only structured
  /// deltas such as previous/new amounts.
  TextColumn get payloadJson => text().withDefault(const Constant('{}'))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
