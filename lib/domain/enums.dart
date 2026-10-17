/// Shared enumerations used across the domain, database and UI layers.
library;

/// Built-in wallet types. `custom` covers any wallet the user defines.
enum WalletType {
  cash,
  bank,
  bkash,
  nagad,
  rocket,
  mfs,
  savings,
  custom;

  String get id => name;

  static WalletType fromId(String value) => WalletType.values.firstWhere(
    (type) => type.name == value,
    orElse: () => WalletType.custom,
  );
}

/// Whether a category (and the transaction using it) is income or expense.
enum CategoryKind {
  income,
  expense;

  static CategoryKind fromId(String value) => CategoryKind.values.firstWhere(
    (kind) => kind.name == value,
    orElse: () => CategoryKind.expense,
  );
}

/// The three kinds of money movement the application understands.
///
/// A [transfer] is a *single logical record* carrying both a source wallet and
/// a destination wallet. It is explicitly **not** income and **not** expense,
/// which is what keeps internal money movement out of income/expense reports.
enum TransactionType {
  income,
  expense,
  transfer;

  bool get isIncome => this == TransactionType.income;
  bool get isExpense => this == TransactionType.expense;
  bool get isTransfer => this == TransactionType.transfer;

  static TransactionType fromId(String value) =>
      TransactionType.values.firstWhere(
        (type) => type.name == value,
        orElse: () => TransactionType.expense,
      );
}

/// How a transaction came into existence. Used for auditing and for showing
/// the user where a record originated.
enum TransactionSource {
  manual,
  voice,
  recurring,
  import_,
  goal,
  system;

  static TransactionSource fromId(String value) =>
      TransactionSource.values.firstWhere(
        (source) => source.name == value,
        orElse: () => TransactionSource.manual,
      );
}

enum BudgetPeriod {
  weekly,
  monthly,
  quarterly,
  yearly,
  custom;

  static BudgetPeriod fromId(String value) => BudgetPeriod.values.firstWhere(
    (period) => period.name == value,
    orElse: () => BudgetPeriod.monthly,
  );
}

enum RecurrenceFrequency {
  daily,
  weekly,
  monthly,
  yearly;

  static RecurrenceFrequency fromId(String value) =>
      RecurrenceFrequency.values.firstWhere(
        (frequency) => frequency.name == value,
        orElse: () => RecurrenceFrequency.monthly,
      );
}

enum LoanDirection {
  lent,
  borrowed;

  static LoanDirection fromId(String value) => LoanDirection.values.firstWhere(
    (direction) => direction.name == value,
    orElse: () => LoanDirection.lent,
  );
}

/// Which interface produced a transaction. Stored for auditing and for the
/// "recorded by voice" insight widgets.
enum RecordedVia { manual, voice, automatic }
