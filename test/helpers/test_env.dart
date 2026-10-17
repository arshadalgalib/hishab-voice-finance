import 'dart:ffi';
import 'dart:io';

import 'package:personal_finance_manager/core/utils/id_generator.dart';
import 'package:personal_finance_manager/data/local/app_database.dart';
import 'package:personal_finance_manager/data/local/connection.dart';
import 'package:personal_finance_manager/data/repositories/budget_repository.dart';
import 'package:personal_finance_manager/data/repositories/category_repository.dart';
import 'package:personal_finance_manager/data/repositories/goal_repository.dart';
import 'package:personal_finance_manager/data/repositories/loan_repository.dart';
import 'package:personal_finance_manager/data/repositories/recurring_repository.dart';
import 'package:personal_finance_manager/data/repositories/reminder_repository.dart';
import 'package:personal_finance_manager/data/repositories/settings_repository.dart';
import 'package:personal_finance_manager/data/repositories/transaction_repository.dart';
import 'package:personal_finance_manager/data/repositories/wallet_repository.dart';
import 'package:personal_finance_manager/data/services/backup_service.dart';
import 'package:personal_finance_manager/data/services/csv_export_service.dart';
import 'package:personal_finance_manager/data/services/seed_service.dart';
import 'package:personal_finance_manager/domain/enums.dart';
import 'package:personal_finance_manager/domain/services/budget_service.dart';
import 'package:personal_finance_manager/domain/services/goal_service.dart';
import 'package:personal_finance_manager/domain/services/loan_service.dart';
import 'package:personal_finance_manager/domain/services/recurring_service.dart';
import 'package:personal_finance_manager/domain/services/report_service.dart';
import 'package:personal_finance_manager/domain/services/transaction_service.dart';
import 'package:personal_finance_manager/domain/services/undo_service.dart';
import 'package:sqlite3/open.dart' as sqlite_open;

/// Points the `sqlite3` package at the host's shared library.
///
/// The default loader looks for `libsqlite3.so`, which many Linux distributions
/// (including this one) do not ship — only the versioned `libsqlite3.so.0`
/// exists. Overriding keeps `flutter test` working on the developer host while
/// leaving the Android build, which bundles its own SQLite, untouched.
void initTestSqlite() {
  if (Platform.isLinux) {
    sqlite_open.open.overrideFor(
      sqlite_open.OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
}

/// Everything an integration test needs, wired the same way `providers.dart`
/// wires it in the app — but without any Flutter bindings, plugins or
/// secure storage.
class TestEnv {
  TestEnv._({
    required this.db,
    required this.clock,
    required this.ids,
    required this.settings,
    required this.wallets,
    required this.categories,
    required this.transactions,
    required this.budgets,
    required this.goals,
    required this.recurring,
    required this.reminders,
    required this.loans,
    required this.transactionService,
    required this.reportService,
    required this.budgetService,
    required this.goalService,
    required this.recurringService,
    required this.loanService,
    required this.undoService,
    required this.backupService,
    required this.csvService,
    required this.seedService,
  });

  factory TestEnv.create({DateTime? now}) {
    initTestSqlite();
    final clock = FixedClock(now ?? DateTime(2026, 3, 11, 10));
    final ids = SequentialIdGenerator();
    final db = AppDatabase(openInMemoryConnection());

    final settings = SettingsRepository(db);
    final wallets = WalletRepository(
      db: db,
      settings: settings,
      ids: ids,
      clock: clock,
    );
    final categories = CategoryRepository(db: db, ids: ids, clock: clock);
    final transactions = TransactionRepository(db);
    final budgets = BudgetRepository(db: db, ids: ids, clock: clock);
    final goals = GoalRepository(db: db, ids: ids, clock: clock);
    final recurring = RecurringRepository(db: db, ids: ids, clock: clock);
    final reminders = ReminderRepository(db: db, ids: ids, clock: clock);
    final loans = LoanRepository(db: db, ids: ids, clock: clock);

    final transactionService = TransactionService(
      db: db,
      transactions: transactions,
      wallets: wallets,
      categories: categories,
      ids: ids,
      clock: clock,
    );

    return TestEnv._(
      db: db,
      clock: clock,
      ids: ids,
      settings: settings,
      wallets: wallets,
      categories: categories,
      transactions: transactions,
      budgets: budgets,
      goals: goals,
      recurring: recurring,
      reminders: reminders,
      loans: loans,
      transactionService: transactionService,
      reportService: ReportService(transactions: transactions),
      budgetService: BudgetService(budgets: budgets),
      goalService: GoalService(goals: goals, transactions: transactionService),
      recurringService: RecurringService(
        rules: recurring,
        transactions: transactionService,
        db: db,
      ),
      loanService: LoanService(loans: loans, transactions: transactionService),
      undoService: UndoService(now: clock.now),
      backupService: BackupService(db: db, now: clock.now),
      csvService: CsvExportService(transactions: transactions),
      seedService: SeedService(
        categories: categories,
        wallets: wallets,
        settings: settings,
      ),
    );
  }

  final AppDatabase db;
  final FixedClock clock;
  final SequentialIdGenerator ids;
  final SettingsRepository settings;
  final WalletRepository wallets;
  final CategoryRepository categories;
  final TransactionRepository transactions;
  final BudgetRepository budgets;
  final GoalRepository goals;
  final RecurringRepository recurring;
  final ReminderRepository reminders;
  final LoanRepository loans;
  final TransactionService transactionService;
  final ReportService reportService;
  final BudgetService budgetService;
  final GoalService goalService;
  final RecurringService recurringService;
  final LoanService loanService;
  final UndoService undoService;
  final BackupService backupService;
  final CsvExportService csvService;
  final SeedService seedService;

  Future<void> dispose() => db.close();

  /// Creates a wallet with a name that makes assertions readable.
  Future<String> addWallet(
    String name, {
    WalletType type = WalletType.cash,
    int openingBalancePoisha = 0,
    bool isDefaultIncome = false,
    bool isDefaultExpense = false,
  }) => wallets.createWallet(
    name: name,
    type: type,
    openingBalancePoisha: openingBalancePoisha,
    isDefaultIncome: isDefaultIncome,
    isDefaultExpense: isDefaultExpense,
  );

  Future<String> addCategory(
    String name,
    CategoryKind kind, {
    List<String> keywords = const <String>[],
  }) => categories.create(name: name, kind: kind, keywords: keywords);

  Future<int> balanceOf(String walletId) async =>
      (await wallets.balance(walletId))?.balancePoisha ?? 0;
}
